import XCTest

@testable import DiscordRP

/// The rename (`CustomRP` → `Discord RP`) moved the Application Support folder and the Keychain
/// service. Migration must copy rather than move, and must never clobber newer files.
final class MigrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private var base: URL!

    private final class FakeStorage: GiphyKeyStorage, @unchecked Sendable {
        var value: String?
        var deletes = 0
        init(value: String? = nil) { self.value = value }
        func read() -> String? { value }
        func write(_ value: String) throws { self.value = value }
        func delete() { value = nil; deletes += 1 }
    }

    override func setUpWithError() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("migration-\(UUID().uuidString)")
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: base)
    }

    private var legacyDirectory: URL { base.appendingPathComponent(Migration.legacyDataDirectoryName) }
    private var currentDirectory: URL { base.appendingPathComponent(Migration.currentDataDirectoryName) }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: data directory

    func testCopiesMissingFilesAndLeavesNewerOnesAlone() throws {
        try write(#"{"presets":true}"#, to: legacyDirectory.appendingPathComponent("presets.json"))
        try write("old settings", to: legacyDirectory.appendingPathComponent("settings.json"))
        try write("new settings", to: currentDirectory.appendingPathComponent("settings.json"))

        let copied = Migration.migrateDataDirectory(fileManager: fileManager, supportDirectory: base)

        XCTAssertEqual(copied, ["presets.json"])
        XCTAssertEqual(try String(contentsOf: currentDirectory.appendingPathComponent("presets.json"), encoding: .utf8),
                       #"{"presets":true}"#)
        XCTAssertEqual(try String(contentsOf: currentDirectory.appendingPathComponent("settings.json"), encoding: .utf8),
                       "new settings", "an existing file must never be overwritten")
        XCTAssertTrue(fileManager.fileExists(atPath: legacyDirectory.appendingPathComponent("presets.json").path),
                      "the legacy file is copied, not moved")
    }

    func testIsIdempotent() throws {
        try write("{}", to: legacyDirectory.appendingPathComponent("presets.json"))
        XCTAssertEqual(Migration.migrateDataDirectory(fileManager: fileManager, supportDirectory: base), ["presets.json"])
        XCTAssertEqual(Migration.migrateDataDirectory(fileManager: fileManager, supportDirectory: base), [],
                       "a second run has nothing left to do")
    }

    func testDoesNothingWithoutALegacyDirectory() {
        XCTAssertEqual(Migration.migrateDataDirectory(fileManager: fileManager, supportDirectory: base), [])
        XCTAssertFalse(fileManager.fileExists(atPath: currentDirectory.path),
                       "no legacy folder → no new folder is created")
    }

    // MARK: keychain

    func testKeyIsMovedOnceAndTheOldCopyIsDeleted() {
        let target = FakeStorage()
        let legacy = FakeStorage(value: "abcdefghijklmnopqrstuvwxyz123456")

        let outcome = Migration.migrateKeychain(target: target, legacy: legacy,
                                                legacyFilePath: base.appendingPathComponent("absent").path)
        XCTAssertEqual(outcome, .movedFromLegacyKeychain)
        XCTAssertEqual(target.value, "abcdefghijklmnopqrstuvwxyz123456")
        XCTAssertEqual(legacy.deletes, 1)
        XCTAssertNil(legacy.value)
    }

    func testExistingTargetKeyWinsAndTheLegacyCopyIsLeftAlone() {
        let target = FakeStorage(value: "new-key-aaaaaaaaaaaaaaaaaaaaaaaa")
        let legacy = FakeStorage(value: "old-key-bbbbbbbbbbbbbbbbbbbbbbbb")

        let outcome = Migration.migrateKeychain(target: target, legacy: legacy,
                                                legacyFilePath: base.appendingPathComponent("absent").path)
        XCTAssertEqual(outcome, .alreadyPresent)
        XCTAssertEqual(target.value, "new-key-aaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(legacy.deletes, 0, "the legacy item must not be touched")
    }

    func testNoLegacyKeyAndNoFileIsNotAFailure() {
        let outcome = Migration.migrateKeychain(
            target: FakeStorage(), legacy: FakeStorage(),
            legacyFilePath: base.appendingPathComponent("absent").path
        )
        XCTAssertEqual(outcome, .nothingToMigrate)
    }

    /// The old version documented `~/.giphy/api_key`; when the legacy Keychain item is unreadable
    /// (which is what happens across a bundle-identity change) the Keychain is seeded from that file.
    func testKeyIsSeededFromTheLegacyFileWhenTheLegacyKeychainIsUnreadable() throws {
        let file = base.appendingPathComponent("api_key")
        try write("legacy-file-key-aaaaaaaaaaaaaaaa\n", to: file)
        let target = FakeStorage()
        let outcome = Migration.migrateKeychain(target: target, legacy: FakeStorage(), legacyFilePath: file.path)
        XCTAssertEqual(outcome, .seededFromLegacyFile)
        XCTAssertEqual(target.value, "legacy-file-key-aaaaaaaaaaaaaaaa")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the user's file is left alone")
    }
}
