import XCTest

@testable import DiscordRP

/// The JSON date contract: epoch **milliseconds**, matching Discord's wire format and
/// `scripts/seed-demo-presets.py`. Swift's default `Date` Codable is seconds since 2001, which
/// silently reinterpreted hand-written timestamps as 1970/2057 — this pins the unit so a future
/// change cannot drift back.
final class DateStorageTests: XCTestCase {
    func testPresetDatesAreStoredAsEpochMilliseconds() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-dates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PresetStore(directory: directory)
        var activity = Activity(name: "T", details: "ok")
        activity.timestampMode = .custom
        activity.customStart = Date(timeIntervalSince1970: 1_789_837_200)  // 2026-09-17
        activity.customEnd = Date(timeIntervalSince1970: 1_789_847_400)
        activity.customEndEnabled = true

        try store.save(presets: [Preset(name: "P", activity: activity)])

        let raw = try String(contentsOf: directory.appendingPathComponent("presets.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("1789837200000"), "expected epoch ms in the JSON, got:\n\(raw)")
        XCTAssertFalse(raw.contains("1789837200.0"), "seconds leaked into the JSON:\n\(raw)")

        let loaded = try XCTUnwrap(store.loadPresets().first)
        XCTAssertEqual(loaded.activity.customStart.timeIntervalSince1970, 1_789_837_200, accuracy: 0.001)
        XCTAssertEqual(loaded.activity.customEnd.timeIntervalSince1970, 1_789_847_400, accuracy: 0.001)
        XCTAssertTrue(loaded.activity.customEndEnabled)
    }

    /// A settings round-trip must not need a date at all, but it shares the coder — keep it honest.
    func testSettingsRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PresetStore(directory: directory)
        let presetID = UUID()
        var settings = AppSettings()
        settings.pipeIndex = 2
        settings.cards = [
            PresenceCard(name: "Main", presetID: presetID, applicationID: "123456789012345678", isOn: true),
        ]
        settings.appID = "123456789012345678"
        settings.activePresetID = presetID
        try store.save(settings: settings)

        let loaded = store.loadSettings()
        XCTAssertEqual(loaded.appID, "123456789012345678")
        XCTAssertEqual(loaded.pipeIndex, 2)
    }
}
