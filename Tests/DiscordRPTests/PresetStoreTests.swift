import XCTest

@testable import DiscordRP

final class PresetStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPresetRoundTrip() throws {
        let store = PresetStore(directory: directory)
        var activity = Activity.sample("Round trip")
        activity.buttons = [Button(label: "Docs", url: "https://example.com")]
        activity.largeKey = "asset_1"
        let preset = Preset(name: "Work", activity: activity)

        try store.save(presets: [preset])
        XCTAssertEqual(store.loadPresets(), [preset])
    }

    func testSettingsRoundTrip() throws {
        let store = PresetStore(directory: directory)
        let presetID = UUID()
        var settings = AppSettings()
        settings.pipeIndex = 2
        settings.launchAtLogin = true
        settings.appID = "42"
        settings.activePresetID = presetID
        settings.cards = [
            PresenceCard(name: "Main", presetID: presetID, applicationID: "42", isOn: true),
        ]
        try store.save(settings: settings)
        XCTAssertEqual(store.loadSettings(), settings)

        let raw = try String(contentsOf: directory.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("appID"), "v2 settings must not write legacy appID:\n\(raw)")
        XCTAssertFalse(raw.contains("activePresetID"), "v2 settings must not write legacy activePresetID:\n\(raw)")
    }

    func testMissingFilesYieldDefaults() {
        let store = PresetStore(directory: directory)
        XCTAssertEqual(store.loadPresets(), [])
        XCTAssertEqual(store.loadSettings().appID, DefaultApplication.id,
                       "a fresh store starts from the built-in application")
    }

    func testCorruptPresetsAreQuarantined() throws {
        let store = PresetStore(directory: directory)
        try "not json at all".write(to: directory.appendingPathComponent("presets.json"),
                                    atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadPresets(), [])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("presets.json.bak").path
        ))
    }

    func testCorruptSettingsAreQuarantined() throws {
        let store = PresetStore(directory: directory)
        try Data([0x00, 0x01, 0x02]).write(to: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.loadSettings().appID, DefaultApplication.id,
                       "a quarantined settings file falls back to the built-in application")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("settings.json.bak").path
        ))
    }

    func testLegacySettingsMigrateToOneMainCard() throws {
        let preset = Preset(id: UUID(), name: "P", activity: Activity.sample("P"))
        let store = PresetStore(directory: directory)
        try store.save(presets: [preset])
        try """
        {
          "appID": "  123456789012345678  ",
          "pipeIndex": 2,
          "activePresetID": "\(preset.id.uuidString)",
          "launchAtLogin": true
        }
        """.write(to: directory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let settings = store.loadSettings()

        XCTAssertEqual(settings.schemaVersion, 2)
        XCTAssertEqual(settings.pipeIndex, 2)
        XCTAssertEqual(settings.launchAtLogin, true)
        XCTAssertEqual(settings.cards.count, 1)
        XCTAssertEqual(settings.cards.first?.name, "Main")
        XCTAssertEqual(settings.cards.first?.presetID, preset.id)
        XCTAssertEqual(settings.cards.first?.applicationID, "123456789012345678")
        XCTAssertEqual(settings.cards.first?.isOn, true)
    }

    func testLegacyMigrationFallsBackToFirstPresetAndBlocksMissingPreset() throws {
        let first = Preset(id: UUID(), name: "First", activity: Activity.sample("First"))
        let store = PresetStore(directory: directory)
        try store.save(presets: [first])
        try #"{"appID":"123456789012345678"}"#.write(
            to: directory.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(store.loadSettings().cards.first?.presetID, first.id)

        try #"{"appID":"123456789012345678","activePresetID":"00000000-0000-0000-0000-000000000001"}"#.write(
            to: directory.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(store.loadSettings().cards.first?.isOn, false)
    }

    func testLegacyMigrationKeepsEmptyApplicationIDOff() throws {
        let preset = Preset(id: UUID(), name: "P", activity: Activity.sample("P"))
        let store = PresetStore(directory: directory)
        try store.save(presets: [preset])
        try """
        {"appID":"   ","activePresetID":"\(preset.id.uuidString)"}
        """.write(to: directory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let card = try XCTUnwrap(store.loadSettings().cards.first)
        XCTAssertEqual(card.applicationID, "")
        XCTAssertFalse(card.isOn)
    }

    func testPresetImportExport() throws {
        let store = PresetStore(directory: directory)
        let preset = Preset(name: "Exported", activity: Activity.sample("Exported"))
        let file = directory.appendingPathComponent("one.json")
        try store.exportPreset(preset, to: file)
        XCTAssertEqual(try store.importPreset(from: file), preset)
    }
}
