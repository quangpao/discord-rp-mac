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
            browserResult: .failure(.browserNotFrontmost)
        )

        XCTAssertTrue(specs.isEmpty)
        XCTAssertEqual(issues.map(\.kind), [.browserUnavailable])
    }

    func testBrowserOverrideSkipsFrontmostGate() throws {
        let noFrontmostBrowser = StubFrontmostApplicationProvider(bundleIdentifier: nil)

        let defaultSelection = BrowserActivitySource.browserForRead(
            browserBundleIdentifierOverride: nil,
            using: noFrontmostBrowser
        )
        XCTAssertEqual(defaultSelection, .failure(.browserNotFrontmost))

        let overrideSelection = BrowserActivitySource.browserForRead(
            browserBundleIdentifierOverride: "com.google.Chrome",
            using: noFrontmostBrowser
        )
        let browser = try XCTUnwrap(try? overrideSelection.get())
        XCTAssertEqual(browser.bundleIdentifier, "com.google.Chrome")

        let unsupportedOverrideSelection = BrowserActivitySource.browserForRead(
            browserBundleIdentifierOverride: "com.example.Unsupported",
            using: StubFrontmostApplicationProvider(bundleIdentifier: "com.google.Chrome")
        )
        XCTAssertEqual(unsupportedOverrideSelection, .failure(.browserNotRunning))
    }

    func testDecodedWebURLMapsToDomainOnly() {
        let result = BrowserActivitySource.result(
            fromDecodedURL: "https://www.github.com/openai/codex?tab=readme",
            title: "  Pull request  ",
            mode: "normal",
            includeTitle: true,
            browser: SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")
        )

        XCTAssertEqual(result, .value(BrowserActivityValue(
            domain: "github.com",
            title: "Pull request",
            browserName: "Google Chrome",
            isIncognito: false
        )))

        if case .value(let value) = result {
            XCTAssertEqual(browserSiteIconURL(forDomain: value.domain), "https://www.google.com/s2/favicons?domain=github.com&sz=128")
        }
    }

    func testDecodedBrowserInternalURLsAreNotWebPages() {
        let browser = SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")

        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: "chrome://settings", title: nil, mode: "normal", includeTitle: false, browser: browser),
            .failure(.unsupportedURL)
        )
        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: "about:blank", title: nil, mode: "normal", includeTitle: false, browser: browser),
            .failure(.unsupportedURL)
        )
    }

    func testMissingDecodedURLIsAReadFailure() {
        let browser = SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")

        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: nil, title: nil, mode: "normal", includeTitle: false, browser: browser),
            .failure(.couldNotReadURL("Browser reply did not include a URL."))
        )
    }

    func testAppleEventTimeoutKeepsTimeoutFailure() {
        let error: NSDictionary = [
            NSAppleScript.errorNumber: NSNumber(value: -1712),
            NSAppleScript.errorMessage: "Apple event timed out."
        ]

        XCTAssertEqual(BrowserActivitySource.failure(from: error), .timeout)
    }

    func testBrowserWindowModeMapsKnownTextDescriptors() {
        XCTAssertEqual(BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(string: "normal")), .normal)
        XCTAssertEqual(BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(string: "incognito")), .incognito)
        XCTAssertNil(BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(string: "guest")))
    }

    func testBrowserWindowModeMapsKnownEnumCodes() {
        XCTAssertEqual(
            BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(typeCode: BrowserWindowMode.fourCharacterCode("norm"))),
            .normal
        )
        XCTAssertEqual(
            BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(typeCode: BrowserWindowMode.fourCharacterCode("incg"))),
            .incognito
        )
        XCTAssertNil(
            BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(typeCode: BrowserWindowMode.fourCharacterCode("????")))
        )
    }

    func testUnknownModeFailsClosedBeforePublishingDomain() {
        let browser = SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")

        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: "https://example.com/private", title: nil, mode: Optional<String>.none, includeTitle: false, browser: browser),
            .failure(.incognitoUnknown)
        )
        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: "https://example.com/private", title: nil, mode: "unknown", includeTitle: false, browser: browser),
            .failure(.incognitoUnknown)
        )
    }

    func testUnknownModeReadResultPublishesNothingWithoutStickyValue() {
        let browser = SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")
        var state = BrowserActivityPublicationState()

        state.record(BrowserActivitySource.result(
            fromDecodedURL: "https://example.com/private",
            title: nil,
            mode: BrowserWindowMode.from(descriptor: NSAppleEventDescriptor(typeCode: BrowserWindowMode.fourCharacterCode("????"))),
            includeTitle: false,
            browser: browser
        ))

        XCTAssertEqual(state.latestReadResult, .failure(.incognitoUnknown))
        XCTAssertNil(state.publishedReadResult)
    }

    func testIncognitoModeFailsClosedBeforePublishingDomain() {
        let browser = SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome")

        XCTAssertEqual(
            BrowserActivitySource.result(fromDecodedURL: "https://example.com/private", title: nil, mode: "incognito", includeTitle: false, browser: browser),
            .failure(.incognito)
        )
    }

    func testStickyBrowserPublicationKeepsLastValueAcrossReadFailures() {
        let value = BrowserActivityValue(domain: "example.com", title: "Example", browserName: "Chrome", isIncognito: false)
        let failures: [BrowserActivityFailure] = [
            .browserNotFrontmost,
            .browserNotRunning,
            .automationPermissionDenied,
            .scriptCompileFailed("compile"),
            .timeout,
            .noFrontWindow,
            .unsupportedURL,
            .couldNotReadURL("missing"),
            .incognito,
            .incognitoUnknown,
            .blocked("example.com"),
            .scriptFailed("failed"),
        ]

        for failure in failures {
            var state = BrowserActivityPublicationState()
            state.record(.value(value))
            state.record(.failure(failure))

            XCTAssertEqual(state.latestReadResult, .failure(failure))
            XCTAssertEqual(state.publishedReadResult, .value(value), "failure \(failure) should keep last published value")
        }
    }

    func testExplicitBrowserPublicationClearRemovesStickyValue() {
        var state = BrowserActivityPublicationState()
        let value = BrowserActivityValue(domain: "example.com", browserName: "Chrome", isIncognito: false)

        state.record(.value(value))
        state.clear()

        XCTAssertNil(state.latestReadResult)
        XCTAssertNil(state.publishedReadResult)
    }

    func testIncognitoUnknownWithoutLastValuePublishesNothing() {
        var state = BrowserActivityPublicationState()

        state.record(.failure(.incognitoUnknown))

        XCTAssertEqual(state.latestReadResult, .failure(.incognitoUnknown))
        XCTAssertNil(state.publishedReadResult)
    }

    func testAppleScriptWorkerRunsBlocksOnThreadWithRunLoop() {
        let expectation = expectation(description: "worker reports run loop")

        AppleScriptRunLoopWorker.shared.runLoopThreadCheck { hasRunLoopMode in
            XCTAssertTrue(hasRunLoopMode)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testAppleScriptTargetsBundleIdentifier() {
        let browser = SupportedBrowser(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            displayName: "Google Chrome"
        )

        let source = BrowserActivitySource.scriptSource(for: browser, includeTitle: false)

        XCTAssertTrue(source.contains("tell application id \"com.google.Chrome\""))
        XCTAssertTrue(source.contains("active tab of front window"))
        XCTAssertFalse(source.contains("name of frontTab"))
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
        activity.largeKey = "preset_logo"
        activity.largeText = "Preset Logo"
        activity.smallKey = "small_logo"
        activity.smallText = "Small Logo"
        activity.buttons = [Button(label: "Docs", url: "https://example.com/docs")]
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: "Pull request", browserName: "Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(specs.first?.activity.name, "Work")
        XCTAssertEqual(specs.first?.activity.kind, .watching)
        XCTAssertEqual(specs.first?.activity.details, "Pull request")
        XCTAssertEqual(specs.first?.activity.state, "github.com")
        XCTAssertEqual(specs.first?.activity.largeKey, "https://www.google.com/s2/favicons?domain=github.com&sz=128")
        XCTAssertEqual(specs.first?.activity.largeText, "Chrome")
        XCTAssertEqual(specs.first?.activity.smallKey, "small_logo")
        XCTAssertEqual(specs.first?.activity.smallText, "Small Logo")
        XCTAssertEqual(specs.first?.activity.buttons, [Button(label: "Docs", url: "https://example.com/docs")])
    }

    func testBrowserCardDoesNotRepeatPageTitleInLargeText() {
        let title = "LƯU NIÊN - NGUYỄN ĐÌNH VŨ | JACK J97 | TAM THÁI TỬ | COVER - YouTube"
        var activity = Activity(name: "Watching", details: "preset", state: "old")
        activity.largeKey = "preset_logo"
        activity.largeText = "Preset Logo"
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "youtube.com", title: title, browserName: "Google Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(specs.first?.activity.details, title)
        XCTAssertEqual(specs.first?.activity.state, "youtube.com")
        XCTAssertEqual(specs.first?.activity.largeText, "Google Chrome")
        XCTAssertNotEqual(specs.first?.activity.largeText, title)
    }

    func testBrowserCardTruncatesLongTitleBeforeValidation() throws {
        let title = String(repeating: "a", count: 200)
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: title, browserName: "Google Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )
        let activity = try XCTUnwrap(specs.first?.activity)

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(activity.details.count, ActivityRules.maxTextLength)
        XCTAssertTrue(ActivityRules.errors(in: ActivityRules.validate(activity, appID: "123")).isEmpty)
    }

    func testBrowserTitleTruncationDoesNotSplitCharacters() throws {
        let title = String(repeating: "a", count: ActivityRules.maxTextLength - 1) + "🎧" + "tail"
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: title, browserName: "Google Chrome", isIncognito: false)

        let (specs, _) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value)
        )
        let details = try XCTUnwrap(specs.first?.activity.details)

        XCTAssertEqual(details.count, ActivityRules.maxTextLength)
        XCTAssertTrue(details.hasSuffix("🎧"))
        XCTAssertTrue(ActivityRules.errors(in: ActivityRules.validate(specs[0].activity, appID: "123")).isEmpty)
    }

    func testBrowserCardKeepsPresetLargeTextWhenSiteIconIsOff() {
        var activity = Activity(name: "Work", details: "preset", state: "old")
        activity.largeKey = "preset_logo"
        activity.largeText = "Preset Hover"
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: "Pull request", browserName: "Google Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(usesSiteIcon: false)
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(specs.first?.activity.details, "Pull request")
        XCTAssertEqual(specs.first?.activity.state, "github.com")
        XCTAssertEqual(specs.first?.activity.largeKey, "preset_logo")
        XCTAssertEqual(specs.first?.activity.largeText, "Preset Hover")
    }

    func testBrowserCardWithTitleDisabledUsesDomainAndEmptyState() {
        var activity = Activity(name: "Work", details: "preset", state: "old")
        activity.largeKey = "preset_logo"
        activity.largeText = "Preset Logo"
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", title: "Pull request", browserName: "Chrome", isIncognito: false)

        let (specs, issues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(showsPageTitle: false, usesSiteIcon: false)
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(specs.first?.activity.details, "github.com")
        XCTAssertEqual(specs.first?.activity.state, "")
        XCTAssertEqual(specs.first?.activity.largeKey, "preset_logo")
        XCTAssertEqual(specs.first?.activity.largeText, "Preset Logo")
    }

    func testBrowserCardPublishesOnlyWhenValueChanges() {
        var activity = Activity(name: "Browsing", details: "preset", state: "old")
        activity.largeKey = "preset_logo"
        activity.largeText = "Preset Logo"
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(name: "Browser", presetID: preset.id, applicationID: "123", isOn: true, source: .browser)
        let value = BrowserActivityValue(domain: "github.com", browserName: "Chrome", isIncognito: false)

        let (firstSpecs, firstIssues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(usesSiteIcon: false)
        )
        let firstDiff = PresenceCardPlanner.diff(desired: firstSpecs, running: [])

        let (secondSpecs, secondIssues) = PresenceCardPlanner.validate(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(usesSiteIcon: false)
        )
        let running = firstSpecs.map {
            RunningCardSnapshot(cardID: $0.cardID, applicationID: $0.applicationID, activity: $0.activity)
        }
        let secondDiff = PresenceCardPlanner.diff(desired: secondSpecs, running: running)

        XCTAssertTrue(firstIssues.isEmpty)
        XCTAssertEqual(firstDiff.count, 1)
        XCTAssertEqual(firstSpecs.first?.activity.state, "")
        XCTAssertEqual(firstSpecs.first?.activity.largeKey, "preset_logo")
        XCTAssertEqual(firstSpecs.first?.activity.largeText, "Preset Logo")
        XCTAssertTrue(secondIssues.isEmpty)
        XCTAssertTrue(secondDiff.isEmpty)
    }

    func testPreviousSettingsDecodeAllCardsPresetsKeysAndDefaultCardSource() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("browser-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let presetID = UUID()
        var activity = Activity(name: "Activity", details: "Details")
        activity.largeKey = "large_key"
        activity.smallKey = "small_key"
        activity.buttons = [Button(label: "Open", url: "https://example.com")]
        let preset = Preset(id: presetID, name: "Kept", activity: activity)
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
        XCTAssertEqual(presets.first?.activity.largeKey, "large_key")
        XCTAssertEqual(presets.first?.activity.smallKey, "small_key")
        XCTAssertEqual(presets.first?.activity.buttons, [Button(label: "Open", url: "https://example.com")])
        XCTAssertEqual(settings.cards.count, 1)
        XCTAssertEqual(settings.cards.first?.id, cardID)
        XCTAssertEqual(settings.cards.first?.presetID, presetID)
        XCTAssertEqual(settings.cards.first?.applicationID, "123")
        XCTAssertEqual(settings.cards.first?.source, .preset)
        XCTAssertEqual(settings.pipeIndex, 3)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.browser.showsPageTitle)
        XCTAssertTrue(settings.browser.usesSiteIcon)
    }
}

private struct StubFrontmostApplicationProvider: FrontmostApplicationProviding {
    var bundleIdentifier: String?

    func frontmostBundleIdentifier() -> String? {
        bundleIdentifier
    }
}
