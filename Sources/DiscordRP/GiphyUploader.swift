import Foundation

public struct GiphyUploadResult: Equatable, Sendable {
    public let id: String
    /// `https://media.giphy.com/media/<id>/giphy.gif` — what the image key should become.
    public let mediaURL: String
    public let pageURL: String
}

public enum GiphyError: Error, Equatable, Sendable {
    case missingAPIKey(String)
    case fileMissing(String)
    case fileTooLarge(bytes: Int, limit: Int)
    case unsupportedType(String)
    case http(status: Int, body: String)
    case malformedResponse(String)

    public var message: String {
        switch self {
        case .missingAPIKey(let path):
            "No Giphy API key. Put one in \(path) (chmod 600) or set GIPHY_API_KEY."
        case .fileMissing(let path):
            "File not found: \(path)"
        case .fileTooLarge(let bytes, let limit):
            "Giphy accepts up to \(limit / 1_048_576) MB — this file is \(bytes / 1_048_576) MB."
        case .unsupportedType(let ext):
            "Giphy accepts animated GIF, MP4 or WebM — not “.\(ext)”."
        case .http(let status, let body):
            status == 401 || status == 403
                ? "Giphy rejected the API key (HTTP \(status)). Check ~/.giphy/api_key."
                : status == 429
                ? "Giphy rate limit hit (10 uploads/day on a dashboard key) — try again tomorrow."
                : "Giphy returned HTTP \(status): \(body.prefix(200))"
        case .malformedResponse(let text):
            "Giphy sent something unexpected: \(text.prefix(200))"
        }
    }
}

/// Uploads a local GIF to Giphy and returns the CDN URL, so the editor can turn a file into an
/// image key. Credentials: API key read from `~/.giphy/api_key` or `$GIPHY_API_KEY` — never from
/// the repo, never logged.
public enum GiphyUploader {
    public static let endpoint = URL(string: "https://upload.giphy.com/v1/gifs")!
    public static let maxBytes = 100 * 1_048_576
    public static let allowedExtensions: Set<String> = ["gif", "mp4", "webm"]

    public static func defaultKeyPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.giphy/api_key"
    }

    /// Returns the key, or nil when it is missing/blank.
    public static func apiKey(
        path: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let value = getenv("GIPHY_API_KEY").map({ String(cString: $0) }), !value.isEmpty {
            return value
        }
        if let value = environment["GIPHY_API_KEY"], !value.isEmpty { return value }
        let file = path ?? defaultKeyPath()
        guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - request building

    public static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String = "file",
        filename: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }

        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    public static func parse(_ data: Data) throws -> GiphyUploadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty
        else {
            throw GiphyError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return GiphyUploadResult(
            id: id,
            mediaURL: "https://media.giphy.com/media/\(id)/giphy.gif",
            pageURL: "https://giphy.com/gifs/\(id)"
        )
    }

    // MARK: - upload

    public static func upload(
        file: URL,
        apiKey key: String,
        hidden: Bool = false,
        tags: String? = nil,
        session: URLSession = .shared
    ) async throws -> GiphyUploadResult {
        let path = file.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw GiphyError.fileMissing(path)
        }
        let ext = file.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw GiphyError.unsupportedType(ext)
        }
        let data = try Data(contentsOf: file)
        guard data.count <= maxBytes else {
            throw GiphyError.fileTooLarge(bytes: data.count, limit: maxBytes)
        }

        var fields = ["api_key": key, "source_post_url": "https://quangpao.dev"]
        if hidden { fields["is_hidden"] = "true" }
        if let tags, !tags.isEmpty { fields["tags"] = tags }

        let boundary = "----customrp\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, fields: fields,
                                         filename: file.lastPathComponent, fileData: data)
        request.timeoutInterval = 120

        let (responseData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GiphyError.http(status: http.statusCode,
                                  body: String(decoding: responseData.prefix(300), as: UTF8.self))
        }
        return try parse(responseData)
    }
}
