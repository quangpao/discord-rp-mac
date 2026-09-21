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
        let legacy = FakeStorage(value: "fixture-key-not-a-real-key")

        let outcome = Migration.migrateKeychain(target: target, legacy: legacy,
                                                legacyFilePath: base.appendingPathComponent("absent").path)
        XCTAssertEqual(outcome, .movedFromLegacyKeychain)
        XCTAssertEqual(target.value, "fixture-key-not-a-real-key")
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

/// A storage that records whether it was read through the prompting API or the prompt-free one, so a
/// regression that reintroduces a blocking Keychain prompt on the startup path fails the suite.
private final class ProbeRecordingStorage: GiphyKeyStorage, @unchecked Sendable {
    private var stored: String?
    private(set) var interactiveReads = 0
    private(set) var promptFreeReads = 0

    init(value: String? = nil) { stored = value }

    func read() -> String? { interactiveReads += 1; return stored }
    func readWithoutPrompt() -> String? { promptFreeReads += 1; return stored }
    func write(_ value: String) throws { stored = value }
    func delete() { stored = nil }
}

final class KeychainProbeTests: XCTestCase {
    func testMigrationNeverUsesThePromptingRead() {
        let target = ProbeRecordingStorage()
        let legacy = ProbeRecordingStorage(value: "fixture-key-not-a-real-key")

        let outcome = Migration.migrateKeychain(target: target, legacy: legacy,
                                                legacyFilePath: "/nonexistent/giphy/api_key")

        XCTAssertEqual(outcome, .movedFromLegacyKeychain)
        XCTAssertEqual(target.interactiveReads, 0,
                       "the startup probe must not be able to put a Keychain prompt on screen")
        XCTAssertEqual(legacy.interactiveReads, 0,
                       "reading the pre-rename item must not prompt either")
        XCTAssertGreaterThan(legacy.promptFreeReads, 0)
    }

    func testExistingKeyShortCircuitsWithoutPrompting() {
        let target = ProbeRecordingStorage(value: "fixture-key-not-a-real-key")
        let legacy = ProbeRecordingStorage(value: "fixture-key-not-a-real-key")

        XCTAssertEqual(Migration.migrateKeychain(target: target, legacy: legacy), .alreadyPresent)
        XCTAssertEqual(target.interactiveReads, 0)
        XCTAssertEqual(legacy.promptFreeReads, 0, "nothing to read once the target already has a key")
    }
}

/// The Keychain half of the rename must never run on the main thread: a prompt for a legacy item
/// blocked `AppModel.init` and left the app alive but doing nothing (no socket, no log).
final class KeychainBackgroundMigrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Migration.resetKeychainMigrationForTesting()
    }

    func testRunsOffTheMainThreadAndReportsTheOutcome() {
        let target = ProbeRecordingStorage()
        let legacy = ProbeRecordingStorage(value: "fixture-key-not-a-real-key")
        let done = expectation(description: "migration ran")
        let box = OutcomeBox()

        Migration.migrateKeychainInBackground(target: target, legacy: legacy,
                                             legacyFilePath: "/nonexistent/giphy/api_key") { outcome in
            box.outcome = outcome
            box.onMainThread = Thread.isMainThread
            done.fulfill()
        }

        wait(for: [done], timeout: 5)
        XCTAssertEqual(box.outcome, .movedFromLegacyKeychain)
        XCTAssertFalse(box.onMainThread, "a Keychain prompt here must not be able to freeze the app")
    }

    func testStartsOnlyOncePerProcess() {
        let first = expectation(description: "first run")
        Migration.migrateKeychainInBackground(target: ProbeRecordingStorage(),
                                             legacy: ProbeRecordingStorage(),
                                             legacyFilePath: "/nonexistent") { _ in first.fulfill() }
        wait(for: [first], timeout: 5)

        let second = OutcomeBox()
        Migration.migrateKeychainInBackground(target: ProbeRecordingStorage(),
                                             legacy: ProbeRecordingStorage(),
                                             legacyFilePath: "/nonexistent") { _ in second.ran = true }
        // Give the utility queue a moment to (not) do anything.
        let idle = expectation(description: "idle")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { idle.fulfill() }
        wait(for: [idle], timeout: 5)

        XCTAssertFalse(second.ran, "the migration is once per process, so it cannot prompt twice")
    }
}

/// Mutable state shared with the migration's completion handler, which runs on another queue.
private final class OutcomeBox: @unchecked Sendable {
    var outcome: Migration.KeyMigrationOutcome?
    var onMainThread = true
    var ran = false
}
