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
        var settings = AppSettings()
        settings.appID = "42"
        settings.pipeIndex = 2
        settings.activePresetID = UUID()
        try store.save(settings: settings)
        XCTAssertEqual(store.loadSettings(), settings)
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

    func testPresetImportExport() throws {
        let store = PresetStore(directory: directory)
        let preset = Preset(name: "Exported", activity: Activity.sample("Exported"))
        let file = directory.appendingPathComponent("one.json")
        try store.exportPreset(preset, to: file)
        XCTAssertEqual(try store.importPreset(from: file), preset)
    }
}
