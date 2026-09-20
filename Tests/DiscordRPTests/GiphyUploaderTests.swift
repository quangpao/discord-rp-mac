import XCTest

@testable import DiscordRP

final class GiphyUploaderTests: XCTestCase {
    private var directory: URL!
    private var previousStorage: GiphyKeyStorage!

    /// Never let a test read the developer's real Keychain, and never let a failure message print a
    /// key value: an open-source CI log is public, and `XCTAssertEqual`/`XCTAssertNil` include the
    /// actual value on failure. Assertions about key material use booleans on purpose.
    private final class EmptyStorage: GiphyKeyStorage, @unchecked Sendable {
        func read() -> String? { nil }
        func write(_ value: String) throws {}
        func delete() {}
    }

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("customrp-giphy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        previousStorage = GiphyKeyStore.storage
        GiphyKeyStore.storage = EmptyStorage()
    }

    override func tearDownWithError() throws {
        GiphyKeyStore.storage = previousStorage
        try? FileManager.default.removeItem(at: directory)
    }

    func testMultipartBodyCarriesFieldsAndFile() {
        let body = GiphyUploader.multipartBody(
            boundary: "BOUND",
            fields: ["api_key": "k", "is_hidden": "true"],
            filename: "logo.gif",
            fileData: Data([0x47, 0x49, 0x46])  // "GIF"
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"api_key\"\r\n\r\nk\r\n"))
        XCTAssertTrue(text.contains("name=\"is_hidden\"\r\n\r\ntrue\r\n"))
        XCTAssertTrue(text.contains("filename=\"logo.gif\""))
        XCTAssertTrue(text.hasPrefix("--BOUND\r\n"))
        XCTAssertTrue(text.hasSuffix("--BOUND--\r\n"))
        XCTAssertTrue(body.count > 3, "file bytes are appended")
    }

    func testParseSuccess() throws {
        let json = #"{"data":{"id":"AbC123","images":{"original":{"url":"x"}}},"meta":{"status":200}}"#
        let result = try GiphyUploader.parse(Data(json.utf8))
        XCTAssertEqual(result.id, "AbC123")
        XCTAssertEqual(result.mediaURL, "https://media.giphy.com/media/AbC123/giphy.gif")
        XCTAssertEqual(result.pageURL, "https://giphy.com/gifs/AbC123")
    }

    func testParseFailure() {
        XCTAssertThrowsError(try GiphyUploader.parse(Data(#"{"meta":{"status":401}}"#.utf8))) { error in
            guard case GiphyError.malformedResponse = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertThrowsError(try GiphyUploader.parse(Data("not json".utf8)))
    }

    func testAPIKeyMissingIsNil() {
        XCTAssertTrue(GiphyUploader.apiKey(path: "\(directory.path)/nope", environment: [:]) == nil,
                      "an empty environment and a missing file must yield no key")
    }

    func testAPIKeyReadFromFile() throws {
        let file = directory.appendingPathComponent("api_key")
        try "  my-key\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GiphyUploader.apiKey(path: file.path, environment: [:]) == "my-key",
                      "the file value is used when the Keychain is empty")
    }

    func testUnsupportedExtensionIsRejected() async throws {
        let file = directory.appendingPathComponent("logo.png")
        try Data([0x89, 0x50]).write(to: file)
        do {
            _ = try await GiphyUploader.upload(file: file, apiKey: "k")
            XCTFail("should have thrown")
        } catch let error as GiphyError {
            guard case .unsupportedType(let ext) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(ext, "png")
        }
    }

    func testMissingFileIsRejected() async {
        do {
            _ = try await GiphyUploader.upload(file: directory.appendingPathComponent("nope.gif"), apiKey: "k")
            XCTFail("should have thrown")
        } catch let error as GiphyError {
            guard case .fileMissing = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testErrorMessageForRateLimit() {
        XCTAssertTrue(GiphyError.http(status: 429, body: "").message.contains("rate limit"))
        XCTAssertTrue(GiphyError.missingAPIKey("~/.giphy/api_key").message.contains("API key"))
    }
}
