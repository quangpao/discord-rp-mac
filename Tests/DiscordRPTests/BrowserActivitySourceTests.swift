import XCTest

@testable import DiscordRP

final class BrowserActivitySourceTests: XCTestCase {
    func testDomainExtractionNormalizesHostOnly() {
        XCTAssertEqual(BrowserActivitySource.domain(from: "https://www.github.com/a/b?x=1"), "github.com")
        XCTAssertEqual(BrowserActivitySource.domain(from: "https://WWW.Example.COM/path"), "example.com")
        XCTAssertEqual(BrowserActivitySource.domain(from: "http://localhost:3000/a"), "localhost")
        XCTAssertEqual(BrowserActivitySource.domain(from: "https://example.com:8443/a"), "example.com")
    }

    func testDomainExtractionRejectsNonWebURLs() {
        XCTAssertNil(BrowserActivitySource.domain(from: "about:blank"))
        XCTAssertNil(BrowserActivitySource.domain(from: "chrome://settings"))
        XCTAssertNil(BrowserActivitySource.domain(from: "file:///tmp/index.html"))
    }

    func testBlocklistMatchesBareDomainWildcardAndCaseInsensitively() {
        let patterns = ["mail.google.com", "*.icloud.com", "LOCALHOST"]

        XCTAssertTrue(BrowserActivitySource.isBlocked(domain: "mail.google.com", by: patterns))
        XCTAssertTrue(BrowserActivitySource.isBlocked(domain: "drive.icloud.com", by: patterns))
        XCTAssertTrue(BrowserActivitySource.isBlocked(domain: "icloud.com", by: patterns))
        XCTAssertTrue(BrowserActivitySource.isBlocked(domain: "localhost", by: patterns))
        XCTAssertFalse(BrowserActivitySource.isBlocked(domain: "calendar.google.com", by: patterns))
        XCTAssertFalse(BrowserActivitySource.isBlocked(domain: "evilicloud.com", by: patterns))
    }

    func testIncognitoIsNeverPublished() {
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "example.com", browserName: "Chrome", isIncognito: true)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )

        XCTAssertTrue(specs.isEmpty)
        XCTAssertEqual(issues.map(\.kind), [.browserUnavailable])
    }

    func testUnsupportedOrAbsentBrowserYieldsNoBrowserSpec() {
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .failure(.unsupportedFrontmostApplication)
        )

        XCTAssertTrue(specs.isEmpty)
        XCTAssertEqual(issues.map(\.kind), [.browserUnavailable])
    }

    func testPermissionDeniedIsReportedAsOwnCase() {
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .failure(.automationPermissionDenied)
        )

        XCTAssertTrue(specs.isEmpty)
        XCTAssertEqual(issues.map(\.kind), [.browserPermissionDenied])
    }

    func testBrowserCardUsesPresetShellAndBrowserFields() {
        var activity = Activity(name: "Work", details: "preset", state: "old")
        activity.kind = .watching
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: "Pull request", browserName: "Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(showsPageTitle: true, blocklist: [])
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(specs.first?.activity.name, "Work")
        XCTAssertEqual(specs.first?.activity.kind, .watching)
        XCTAssertEqual(specs.first?.activity.details, "github.com")
        XCTAssertEqual(specs.first?.activity.state, "Pull request")
    }

    func testBrowserCardPublishesOnlyWhenValueChanges() {
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", browserName: "Chrome", isIncognito: false)

        let (firstSpecs, firstIssues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )
        let firstDiff = PresenceCardPlanner.diff(desired: firstSpecs, running: [])

        let (secondSpecs, secondIssues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )
        let running = firstSpecs.map {
            RunningCardSnapshot(cardID: $0.cardID, applicationID: $0.applicationID, activity: $0.activity)
        }
        let secondDiff = PresenceCardPlanner.diff(desired: secondSpecs, running: running)

        XCTAssertTrue(firstIssues.isEmpty)
        XCTAssertEqual(firstDiff.count, 1)
        XCTAssertTrue(secondIssues.isEmpty)
        XCTAssertTrue(secondDiff.isEmpty)
    }

    func testPreviousSettingsDecodeAllCardsPresetsKeysAndDefaultCardSource() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("browser-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let presetID = UUID()
        let preset = Preset(id: presetID, name: "Kept", activity: Activity(name: "Activity", details: "Details"))
        let store = PresetStore(directory: directory)
        try store.save(presets: [preset])

        let cardID = UUID()
        let settingsJSON = """
        {
          "schemaVersion": 2,
          "pipeIndex": 3,
          "launchAtLogin": true,
          "cards": [{
            "id": "\(cardID.uuidString)",
            "name": "Main",
            "presetID": "\(presetID.uuidString)",
            "applicationID": "123",
            "isOn": true
          }]
        }
        """
        try settingsJSON.write(to: directory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let presets = store.loadPresets()
        let settings = store.loadSettings()

        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets.first?.id, presetID)
        XCTAssertEqual(settings.cards.count, 1)
        XCTAssertEqual(settings.cards.first?.id, cardID)
        XCTAssertEqual(settings.cards.first?.presetID, presetID)
        XCTAssertEqual(settings.cards.first?.applicationID, "123")
        XCTAssertEqual(settings.cards.first?.source, .preset)
        XCTAssertEqual(settings.pipeIndex, 3)
        XCTAssertTrue(settings.launchAtLogin)
    }
}
