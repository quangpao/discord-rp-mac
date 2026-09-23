import XCTest
@testable import DiscordRP

/// The log was renamed with the app (`customrp.log` → `discord-rp.log`). The pre-rename file must be
/// carried over rather than abandoned, and a new one must never be clobbered. These tests also keep
/// every log write inside a temporary directory — a real test run once overwrote the developer's
/// `last-presence.json` with a fixture payload.
final class PresenceLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-presencelog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if PresenceLog.directoryOverride == directory {
            PresenceLog.directoryOverride = nil
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testLegacyLogIsCarriedOver() throws {
        _ = try write("customrp.log", "old history\n")
        let url = PresenceLog.migratedLogURL(in: directory)

        XCTAssertEqual(url.lastPathComponent, "discord-rp.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the log must exist under the new name")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old history\n",
                       "the pre-rename history must survive")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("customrp.log").path),
                       "the stale name must not be left behind")
    }

    func testAnExistingNewLogIsNotClobbered() throws {
        _ = try write("discord-rp.log", "current\n")
        _ = try write("customrp.log", "older\n")

        let url = PresenceLog.migratedLogURL(in: directory)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "current\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("customrp.log").path),
                      "with both files present the legacy one is left untouched, not merged")
    }

    func testNoLegacyFileMeansNoWork() {
        let url = PresenceLog.migratedLogURL(in: directory)
        XCTAssertEqual(url.lastPathComponent, "discord-rp.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "reading the URL must not create the file")
    }

    func testNoteWritesUnderTheNewName() throws {
        PresenceLog.directoryOverride = directory
        defer { PresenceLog.directoryOverride = nil }

        PresenceLog.note("hello")

        let current = directory.appendingPathComponent("discord-rp.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(try String(contentsOf: current, encoding: .utf8).contains("hello"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("customrp.log").path))
    }
}
