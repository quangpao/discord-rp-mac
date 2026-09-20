import Foundation

/// One GIF that was pushed to Giphy, kept so it can be reused without uploading it again.
public struct GiphyUpload: Codable, Equatable, Sendable, Identifiable {
    /// Giphy's id — the identity of the upload.
    public var id: String
    /// `https://media.giphy.com/media/<id>/giphy.gif` — what an image key should be set to.
    public var mediaURL: String
    /// `https://giphy.com/gifs/<id>` — the page a human can open.
    public var pageURL: String
    public var filename: String
    public var bytes: Int
    public var hidden: Bool
    public var uploadedAt: Date

    public init(id: String, mediaURL: String, pageURL: String, filename: String,
                bytes: Int, hidden: Bool, uploadedAt: Date = Date()) {
        self.id = id
        self.mediaURL = mediaURL
        self.pageURL = pageURL
        self.filename = filename
        self.bytes = bytes
        self.hidden = hidden
        self.uploadedAt = uploadedAt
    }
}

/// Local history of Giphy uploads (`~/Library/Application Support/DiscordRPMac/giphy-uploads.json`).
///
/// Why this exists: the Giphy API has **no** "list my uploads" endpoint, and a private
/// (`is_hidden`) upload does not show up on the account page either — without a local record the
/// only way back to an upload would be the URL still sitting in a preset field. Recording it here
/// means an upload is done once and can be re-picked for any preset afterwards.
public final class GiphyLibrary: @unchecked Sendable {
    public static let shared = GiphyLibrary()
    /// Old uploads are dropped once the list is this long.
    public static let maxEntries = 100

    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.directory = base.appendingPathComponent("DiscordRPMac", isDirectory: true)
        }
    }

    private var fileURL: URL { directory.appendingPathComponent("giphy-uploads.json") }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Newest first. A corrupt file is ignored rather than quarantined — this is a convenience
    /// index, not user data worth blocking the app over.
    public func load() -> [GiphyUpload] {
        guard let data = try? Data(contentsOf: fileURL),
              let uploads = try? Self.decoder().decode([GiphyUpload].self, from: data)
        else { return [] }
        return uploads.sorted { $0.uploadedAt > $1.uploadedAt }
    }

    /// Records an upload and returns the new list. Re-uploading the same Giphy id (same file pushed
    /// twice) moves the existing entry to the front instead of duplicating it.
    @discardableResult
    public func record(_ upload: GiphyUpload) -> [GiphyUpload] {
        var uploads = load()
        uploads.removeAll { $0.id == upload.id }
        uploads.insert(upload, at: 0)
        if uploads.count > Self.maxEntries {
            uploads = Array(uploads.prefix(Self.maxEntries))
        }
        save(uploads)
        return uploads
    }

    public func save(_ uploads: [GiphyUpload]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder().encode(uploads) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
