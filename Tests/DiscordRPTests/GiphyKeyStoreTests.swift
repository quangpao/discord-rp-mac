import XCTest

@testable import DiscordRP

/// BYOK: the app ships no key, the user's own key comes from the Keychain first, and nothing about
/// the key is ever echoed back (no logging, no UI read-back).
final class GiphyKeyStoreTests: XCTestCase {
    /// In-memory stand-in for the Keychain, so tests never touch the real one.
    private final class FakeStorage: GiphyKeyStorage, @unchecked Sendable {
        var value: String?
        var writes = 0
        var deletes = 0
        func read() -> String? { value }
        func write(_ value: String) throws { self.value = value; writes += 1 }
        func delete() { value = nil; deletes += 1 }
    }

    private var storage: FakeStorage!
    private var keyFile: String!

    override func setUpWithError() throws {
        storage = FakeStorage()
        GiphyKeyStore.storage = storage
        keyFile = NSTemporaryDirectory() + "giphy-key-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        GiphyKeyStore.storage = KeychainGiphyKeyStorage()
        try? FileManager.default.removeItem(atPath: keyFile)
    }

    private func writeLegacyFile(_ contents: String) throws {
        try contents.write(toFile: keyFile, atomically: true, encoding: .utf8)
    }

    private let goodKey = "abcdefghijklmnopqrstuvwxyz123456"

    // MARK: resolution order

    func testKeychainWinsOverEnvironmentAndFile() throws {
        storage.value = goodKey
        try writeLegacyFile("from-file-key-aaaaaaaaaaaaaaaa")
        let key = GiphyKeyStore.apiKey(environment: ["GIPHY_API_KEY": "from-env-key-bbbbbbbbbbbbbbbb"], file: keyFile)
        XCTAssertEqual(key, goodKey)
        XCTAssertEqual(GiphyKeyStore.source(environment: ["GIPHY_API_KEY": "x"], file: keyFile), .keychain)
    }

    func testEnvironmentWinsOverFile() throws {
        try writeLegacyFile("from-file-key-aaaaaaaaaaaaaaaa")
        XCTAssertEqual(GiphyKeyStore.apiKey(environment: ["GIPHY_API_KEY": goodKey], file: keyFile), goodKey)
        XCTAssertEqual(GiphyKeyStore.source(environment: ["GIPHY_API_KEY": goodKey], file: keyFile), .environment)
    }

    func testLegacyFileIsStillSupported() throws {
        try writeLegacyFile("  \(goodKey)\n")
        XCTAssertEqual(GiphyKeyStore.apiKey(environment: [:], file: keyFile), goodKey)
        XCTAssertEqual(GiphyKeyStore.source(environment: [:], file: keyFile), .file)
    }

    func testNoKeyAnywhere() {
        XCTAssertNil(GiphyKeyStore.apiKey(environment: [:], file: keyFile))
        XCTAssertEqual(GiphyKeyStore.source(environment: [:], file: keyFile), .none)
        // Never assert on the machine's real state: a developer with ~/.giphy/api_key present would
        // otherwise "fail" a test that is really about the resolution order.
        XCTAssertFalse(GiphyKeyStore.isConfigured(environment: [:], file: keyFile))
    }

    func testBlankValuesCountAsMissing() throws {
        storage.value = "   \n"
        try writeLegacyFile("")
        XCTAssertNil(GiphyKeyStore.apiKey(environment: ["GIPHY_API_KEY": "  "], file: keyFile))
    }

    // MARK: saving

    func testSaveTrimsAndStoresInTheStorage() throws {
        try GiphyKeyStore.save("  \(goodKey)  ")
        XCTAssertEqual(storage.value, goodKey)
        XCTAssertEqual(storage.writes, 1)
    }

    func testSaveRejectsObviouslyWrongInput() {
        XCTAssertThrowsError(try GiphyKeyStore.save("   ")) { error in
            XCTAssertEqual(error as? GiphyKeyError, .empty)
        }
        XCTAssertThrowsError(try GiphyKeyStore.save("short")) { error in
            XCTAssertEqual(error as? GiphyKeyError, .looksWrong("too short"))
        }
        XCTAssertThrowsError(try GiphyKeyStore.save("has a space in the middle of it")) { error in
            XCTAssertEqual(error as? GiphyKeyError, .looksWrong("contains a space"))
        }
        XCTAssertThrowsError(try GiphyKeyStore.save(String(repeating: "x", count: 80))) { error in
            XCTAssertEqual(error as? GiphyKeyError, .looksWrong("too long"))
        }
        XCTAssertEqual(storage.writes, 0, "nothing invalid may reach the storage")
    }

    func testClearRemovesTheStoredKey() throws {
        try GiphyKeyStore.save(goodKey)
        GiphyKeyStore.clear()
        XCTAssertNil(storage.value)
        XCTAssertEqual(storage.deletes, 1)
        XCTAssertFalse(GiphyKeyStore.isConfigured(environment: [:], file: keyFile))
    }

    // MARK: never leak

    /// The UI reports the *source*, never the secret — these strings are safe to log and to show.
    func testSourceDescriptionsNeverContainTheKey() throws {
        try GiphyKeyStore.save(goodKey)
        for source in [GiphyKeySource.keychain, .environment, .file, .none] {
            XCTAssertFalse(source.description.contains(goodKey))
        }
        XCTAssertEqual(GiphyKeyStore.source().description, "Keychain (saved in this app)")
    }
}
