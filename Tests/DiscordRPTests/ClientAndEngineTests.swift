import XCTest

@testable import DiscordRP

/// Client behaviour against a local fake: handshake, push, clear, ping, rejection, hangup.
final class DiscordIPCClientTests: XCTestCase {
    private var server: FakeDiscordServer!

    override func setUpWithError() throws {
        server = FakeDiscordServer()
        try server.start()
        let traceServer = server
        IPCDiagnostics.install { event in
            traceServer?.appendEvent(event)
        }
        setenv("DISCORDRP_IPC_PATH", server.path, 1)
        // Never write into the developer's real log directory: a test run used to overwrite
        // ~/Library/Logs/DiscordRP/last-presence.json with the fixture payload.
        PresenceLog.directoryOverride = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-log-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        unsetenv("DISCORDRP_IPC_PATH")
        IPCDiagnostics.install(nil)
        PresenceLog.directoryOverride = nil
        server.stop()
    }

    func testHandshakeSendsClientIDAndReadsUser() throws {
        let client = DiscordIPCClient(appID: "123", readTimeout: 5)
        try client.connect()
        defer { client.close() }

        XCTAssertEqual(client.path, server.path)
        XCTAssertEqual(server.handshake?["v"] as? Int, 1)
        XCTAssertEqual(server.handshake?["client_id"] as? String, "123")
        XCTAssertEqual(client.readyUser?.username, "tester")
    }

    func testSetActivitySendsPIDAndNonce() throws {
        let client = DiscordIPCClient(appID: "123", readTimeout: 5)
        try client.connect()
        defer { client.close() }

        let payload = try JSONSerialization.data(withJSONObject: ["details": "hi"], options: [.sortedKeys])
        try client.setActivity(payload)

        XCTAssertEqual(server.commands, ["SET_ACTIVITY"])
        let activity = server.activities.first as? [String: Any]
        XCTAssertEqual(activity?["details"] as? String, "hi")
    }

    func testClearSendsNullActivity() throws {
        let client = DiscordIPCClient(appID: "123", readTimeout: 5)
        try client.connect()
        defer { client.close() }

        try client.setActivity(nil)
        XCTAssertEqual(server.activities.first as? NSNull, NSNull())
    }

    func testCommandReplyRejectsMatchingCommandWithStaleNonce() throws {
        server.commandReplyNonceOverride = "stale-nonce"
        let client = DiscordIPCClient(appID: "123", readTimeout: 1)
        try client.connect()
        defer { client.close() }

        XCTAssertThrowsError(try client.setActivity(nil)) { error in
            guard case IPCError.timeout = error else {
                return XCTFail("expected timeout, got \(error)")
            }
        }
        XCTAssertNil(client.lastReply, "a stale nonce must not be accepted as this command's reply")
    }

    func testCommandReplyAcceptsMatchingCommandWhenNonceIsAbsent() throws {
        server.omitCommandReplyNonce = true
        let client = DiscordIPCClient(appID: "123", readTimeout: 5)
        try client.connect()
        defer { client.close() }

        try client.setActivity(nil)

        XCTAssertEqual(client.lastReply?.opcode, .frame)
        XCTAssertEqual(server.activities.first as? NSNull, NSNull())
    }

    func testPingIsAnswered() throws {
        let client = DiscordIPCClient(appID: "123", readTimeout: 5)
        try client.connect()
        defer { client.close() }
        XCTAssertTrue(client.ping())
        XCTAssertTrue(client.isConnected)
    }

    func testBadApplicationIDIsReported() throws {
        server.reject = (4000, "Invalid Client ID")
        let client = DiscordIPCClient(appID: "0", readTimeout: 5)
        XCTAssertThrowsError(try client.connect()) { error in
            guard case IPCError.discordRejected(let code, let message) = error else {
                return XCTFail("expected discordRejected, got \(error)")
            }
            XCTAssertEqual(code, 4000)
            XCTAssertEqual(message, "Invalid Client ID")
        }
        XCTAssertFalse(client.isConnected)
    }

    func testServerHangupIsNotFatal() throws {
        server.closeAfterHandshake = true
        let client = DiscordIPCClient(appID: "123", readTimeout: 2)
        try client.connect()
        XCTAssertFalse(client.ping(), "a dead socket must report false, not crash")
        XCTAssertFalse(client.isConnected)
    }

    func testWriteAfterPeerCloseReportsClosedConnection() throws {
        let client = DiscordIPCClient(appID: "123", readTimeout: 2)
        try client.connect()

        server.closeConnectedClients()

        XCTAssertThrowsError(try client.setActivity(nil)) { error in
            guard case IPCError.discordClosed = error else {
                return XCTFail("expected discordClosed, got \(error)")
            }
        }
        XCTAssertFalse(client.isConnected)
        XCTAssertTrue(server.commands.isEmpty, "a frame written after peer close must not be handled as live")
        XCTAssertTrue(server.activities.isEmpty, "a frame written after peer close must not be attributed to a connection")
    }

    func testCommandsWithoutConnectionThrow() {
        let client = DiscordIPCClient(appID: "123", readTimeout: 1)
        XCTAssertThrowsError(try client.setActivity(nil))
    }
}

final class PresenceCardPlannerActivityNameTests: XCTestCase {
    func testEnabledCardsSharingActivityNameAreReported() {
        let presetA = Preset(id: UUID(), name: "A", activity: Activity(name: "Shared", details: "one"))
        let presetB = Preset(id: UUID(), name: "B", activity: Activity(name: "Shared", details: "two"))
        let first = PresenceCard(name: "One", presetID: presetA.id, applicationID: "1", isOn: true)
        let second = PresenceCard(name: "Two", presetID: presetB.id, applicationID: "2", isOn: true)

        XCTAssertEqual(
            PresenceCardPlanner.duplicateActivityNameCards([first, second], presets: [presetA, presetB]),
            [first.id: "Shared", second.id: "Shared"]
        )
    }

    func testDisabledCardSharingActivityNameIsIgnored() {
        let presetA = Preset(id: UUID(), name: "A", activity: Activity(name: "Shared", details: "one"))
        let presetB = Preset(id: UUID(), name: "B", activity: Activity(name: "Shared", details: "two"))
        let enabled = PresenceCard(name: "One", presetID: presetA.id, applicationID: "1", isOn: true)
        let disabled = PresenceCard(name: "Two", presetID: presetB.id, applicationID: "2", isOn: false)

        XCTAssertTrue(PresenceCardPlanner.duplicateActivityNameCards([enabled, disabled], presets: [presetA, presetB]).isEmpty)
    }

    func testCaseAndWhitespaceDifferencesCollide() {
        let presetA = Preset(id: UUID(), name: "A", activity: Activity(name: "  Shared  ", details: "one"))
        let presetB = Preset(id: UUID(), name: "B", activity: Activity(name: "shared", details: "two"))
        let first = PresenceCard(name: "One", presetID: presetA.id, applicationID: "1", isOn: true)
        let second = PresenceCard(name: "Two", presetID: presetB.id, applicationID: "2", isOn: true)

        XCTAssertEqual(
            PresenceCardPlanner.duplicateActivityNameCards([first, second], presets: [presetA, presetB]),
            [first.id: "Shared", second.id: "shared"]
        )
    }

    func testDistinctActivityNamesAreNotReported() {
        let presetA = Preset(id: UUID(), name: "A", activity: Activity(name: "First", details: "one"))
        let presetB = Preset(id: UUID(), name: "B", activity: Activity(name: "Second", details: "two"))
        let first = PresenceCard(name: "One", presetID: presetA.id, applicationID: "1", isOn: true)
        let second = PresenceCard(name: "Two", presetID: presetB.id, applicationID: "2", isOn: true)

        XCTAssertTrue(PresenceCardPlanner.duplicateActivityNameCards([first, second], presets: [presetA, presetB]).isEmpty)
    }

    func testMissingPresetIsIgnored() {
        let preset = Preset(id: UUID(), name: "A", activity: Activity(name: "Shared", details: "one"))
        let configured = PresenceCard(name: "One", presetID: preset.id, applicationID: "1", isOn: true)
        let missing = PresenceCard(name: "Two", presetID: UUID(), applicationID: "2", isOn: true)

        XCTAssertTrue(PresenceCardPlanner.duplicateActivityNameCards([configured, missing], presets: [preset]).isEmpty)
    }
}

/// End-to-end through the engine: connect, push a preset, clear.
@MainActor
final class PresenceEngineTests: XCTestCase {
    /// `nonisolated(unsafe)`: on the CI runner's older toolchain (Xcode 16 / Swift 6.0–6.1) XCTest's
    /// synchronous `setUpWithError`/`tearDownWithError` are nonisolated even inside a `@MainActor`
    /// test class, so an isolated stored property cannot be assigned there. This file has to compile
    /// on both the local 6.2 toolchain and the runner's, and XCTest only ever touches this from the
    /// main thread.
    private nonisolated(unsafe) var server: FakeDiscordServer!

    override func setUpWithError() throws {
        server = FakeDiscordServer()
        try server.start()
        let traceServer = server
        IPCDiagnostics.install { event in
            traceServer?.appendEvent(event)
        }
        setenv("DISCORDRP_IPC_PATH", server.path, 1)
        // Never write into the developer's real log directory: a test run used to overwrite
        // ~/Library/Logs/DiscordRP/last-presence.json with the fixture payload.
        PresenceLog.directoryOverride = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-log-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        unsetenv("DISCORDRP_IPC_PATH")
        IPCDiagnostics.install(nil)
        PresenceLog.directoryOverride = nil
        server.stop()
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return condition()
    }

    private func payload(_ value: Any, contains needle: String) -> Bool {
        if let string = value as? String { return string.contains(needle) }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { payload($0, contains: needle) }
        }
        if let array = value as? [Any] {
            return array.contains { payload($0, contains: needle) }
        }
        return false
    }

    func testEngineConnectsAndPushesActivity() async throws {
        let engine = PresenceEngine(appID: "123")
        engine.start()

        var activity = Activity(name: "Integration", details: "Engine push")
        activity.timestampMode = .off
        engine.apply(activity)

        let pushed = await waitUntil { !self.server.activities.isEmpty }
        XCTAssertTrue(pushed, "engine never pushed an activity")
        let sent = server.activities.first as? [String: Any]
        XCTAssertEqual(sent?["details"] as? String, "Engine push")

        engine.stop()
        let tornDown = await waitUntil { !engine.status.isConnected }
        XCTAssertTrue(tornDown, "stop() must tear the connection down, status was \(engine.status)")
    }

    func testEngineReportsRejectedApplicationID() async throws {
        server.reject = (4000, "Invalid Client ID")
        let engine = PresenceEngine(appID: "0")
        engine.start()
        // Discord's own wording is surfaced: code 4000 is generic (it is also what an unsupported
        // activity type returns), so the app must not paraphrase it as "Invalid Application ID".
        let failed = await waitUntil { engine.status == .failed(code: 4000, message: "Invalid Client ID") }
        XCTAssertTrue(failed, "status was \(engine.status)")
        engine.stop()
    }

    func testForceReconnectRecoversPausedWorkerWithoutChangingApplicationID() async throws {
        server.rejectNextHandshake = (4000, "Invalid Client ID")
        let engine = PresenceEngine(appID: "unused")
        let cardID = UUID()
        var activity = Activity(name: "Reconnect", details: "same app id")
        activity.timestampMode = .off

        engine.apply([
            CardRunSpec(cardID: cardID, applicationID: "123", activity: activity),
        ])

        let failed = await waitUntil {
            if case .failed(let message, let failing) = engine.multiStatus {
                return message == "Invalid Client ID" && failing == 1
            }
            return false
        }
        XCTAssertTrue(failed, "first handshake should pause the card worker, status was \(engine.multiStatus)")

        engine.forceReconnect()

        let pushed = await waitUntil(timeout: 10) {
            engine.multiStatus.isConnected && self.server.activities.contains { activity in
                (activity as? [String: Any])?["details"] as? String == "same app id"
            }
        }
        XCTAssertTrue(pushed, "forceReconnect() with the same app id never recovered; status was \(engine.multiStatus)")
        let clientIDs = server.handshakes.compactMap { $0["client_id"] as? String }
        XCTAssertFalse(clientIDs.contains("unused"), "forceReconnect() must not wake the idle primary worker")
        XCTAssertEqual(clientIDs, ["123", "123"])
        engine.stop()
    }

    func testStopReturnsBeforeSocketGoodbyeReply() async throws {
        server.commandReplyDelay = 2
        let engine = PresenceEngine(appID: "123")
        engine.start()

        var activity = Activity(name: "Stop", details: "slow goodbye")
        activity.timestampMode = .off
        engine.apply(activity)

        let pushed = await waitUntil { !self.server.activities.isEmpty }
        XCTAssertTrue(pushed, "engine never pushed an activity")

        let started = Date()
        engine.stop()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.5, "stop() must not block the main actor on socket I/O")

        let cleared = await waitUntil(timeout: 6) {
            self.server.activities.contains { $0 is NSNull }
        }
        XCTAssertTrue(cleared, "stop() should still send activity:null before closing")
    }

    /// A rejected *push* must not pause the engine: 4000 also means "bad payload" (e.g. an
    /// unsupported activity type), and pausing used to stop the timer for good.
    func testRejectedPushKeepsRetryingInsteadOfPausing() async throws {
        server.reject = (4000, #"child "activity" fails because [child "type" fails because ["type" must be one of [0, 2, 3, 5]]]"#)
        let engine = PresenceEngine(appID: "123")
        engine.start()
        _ = await waitUntil { engine.status.isConnected }

        var activity = Activity(name: "Bad", details: "rejected payload")
        activity.kind = .playing
        engine.apply(activity)
        let reported = await waitUntil {
            if case .failed(let code, _) = engine.status { return code == 4000 }
            return false
        }
        XCTAssertTrue(reported, "the rejection must be reported, status was \(engine.status)")
        engine.stop()
    }

    func testInvalidInputNeverReachesSocket() async throws {
        let engine = PresenceEngine(appID: "123")
        engine.start()
        _ = await waitUntil { engine.status.isConnected }

        var activity = Activity(name: "Bad", details: "x")
        let issues = engine.apply(activity)
        XCTAssertTrue(issues.contains { $0.field == .details })
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(server.activities.isEmpty, "an invalid activity must not be sent")

        activity.details = "fine"
        engine.apply(activity)
        let pushed = await waitUntil { !self.server.activities.isEmpty }
        XCTAssertTrue(pushed)
        engine.stop()
    }

    func testValidationFailureKeepsPreviouslyPublishedCardUntilExplicitClear() async throws {
        let engine = PresenceEngine(appID: "unused")
        let cardID = UUID()
        let applicationID = "111111111111111111"

        let firstIssues = engine.apply([
            CardRunSpec(cardID: cardID, applicationID: applicationID, activity: Activity(name: "A", details: "first")),
        ])
        XCTAssertTrue(firstIssues.isEmpty)

        let firstPushed = await waitUntil(timeout: 10) {
            self.server.connectionActivities.values.contains { activities in
                activities.contains { activity in
                    (activity as? [String: Any])?["details"] as? String == "first"
                }
            }
        }
        XCTAssertTrue(firstPushed)

        let invalid = Activity(name: "A", details: String(repeating: "x", count: ActivityRules.maxTextLength + 1))
        let invalidIssues = engine.apply([
            CardRunSpec(cardID: cardID, applicationID: applicationID, activity: invalid),
        ])

        XCTAssertEqual(invalidIssues.map(\.kind), [.invalidActivity])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertFalse(
            server.connectionActivities.values.contains { activities in
                activities.contains { $0 is NSNull }
            },
            "validation failure must not clear the existing Discord activity"
        )

        engine.clear(cardID: cardID)
        let cleared = await waitUntil(timeout: 5) {
            self.server.connectionActivities.values.contains { activities in
                activities.contains { $0 is NSNull }
            }
        }
        let trace = server.events.joined(separator: "\n")
        print("FakeDiscordServer trace for testValidationFailureKeepsPreviouslyPublishedCardUntilExplicitClear:\n\(trace)")
        XCTAssertTrue(cleared, "explicit clear must still remove the activity; server events:\n\(trace)")
        engine.stop()
    }

    func testBlockedBrowserReadKeepsPreviouslyPublishedCardAndSendsNoBlockedPayload() async throws {
        let engine = PresenceEngine(appID: "unused")
        let cardID = UUID()
        let applicationID = "111111111111111111"
        var activity = Activity(name: "Browsing", details: "preset", state: "old")
        activity.largeKey = "preset_logo"
        let preset = Preset(name: "Web", activity: activity)
        let card = PresenceCard(
            id: cardID,
            name: "Browser",
            presetID: preset.id,
            applicationID: applicationID,
            isOn: true,
            source: .browser
        )
        let allowed = BrowserActivityValue(
            domain: "github.com",
            title: "Pull request",
            browserName: "Google Chrome",
            isIncognito: false
        )

        let firstIssues = engine.apply(
            cards: [card],
            presets: [preset],
            browserResult: .value(allowed),
            browserSettings: BrowserPrivacySettings(blocklist: ["blocked.example"])
        )
        XCTAssertTrue(firstIssues.isEmpty)

        let firstPushed = await waitUntil(timeout: 10) {
            self.server.activities.contains { payload in
                self.payload(payload, contains: "github.com")
            }
        }
        XCTAssertTrue(firstPushed)
        let activityCountBeforeBlockedRead = server.activities.count
        let clearCountBeforeBlockedRead = server.activities.filter { $0 is NSNull }.count

        let blocked = BrowserActivityValue(
            domain: "blocked.example",
            title: "Private page",
            browserName: "Google Chrome",
            isIncognito: false
        )
        let blockedIssues = engine.apply(
            cards: [card],
            presets: [preset],
            browserResult: .value(blocked),
            browserSettings: BrowserPrivacySettings(blocklist: ["blocked.example"])
        )

        XCTAssertEqual(blockedIssues.map(\.kind), [.browserBlocked])
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(server.activities.count, activityCountBeforeBlockedRead)
        XCTAssertEqual(server.activities.filter { $0 is NSNull }.count, clearCountBeforeBlockedRead)
        XCTAssertFalse(server.activities.contains { payload($0, contains: "blocked.example") })
        XCTAssertFalse(server.activities.contains { payload($0, contains: "Private page") })
        engine.stop()
    }

    func testExplicitBrowserPauseAndTurnOffStillClearPublishedCard() async throws {
        let engine = PresenceEngine(appID: "unused")
        let cardID = UUID()
        let applicationID = "111111111111111111"
        let preset = Preset(name: "Web", activity: Activity(name: "Browsing", details: "preset"))
        var card = PresenceCard(
            id: cardID,
            name: "Browser",
            presetID: preset.id,
            applicationID: applicationID,
            isOn: true,
            source: .browser
        )
        let value = BrowserActivityValue(domain: "github.com", browserName: "Google Chrome", isIncognito: false)

        engine.apply(cards: [card], presets: [preset], browserResult: .value(value))
        let firstPushed = await waitUntil(timeout: 10) {
            self.server.activities.contains { payload in self.payload(payload, contains: "github.com") }
        }
        XCTAssertTrue(firstPushed)

        let pauseIssues = engine.apply(
            cards: [card],
            presets: [preset],
            browserResult: .value(value),
            browserSettings: BrowserPrivacySettings(isPaused: true)
        )
        XCTAssertEqual(pauseIssues.map(\.kind), [.browserPaused])
        let pauseCleared = await waitUntil(timeout: 5) {
            self.server.activities.contains { $0 is NSNull }
        }
        XCTAssertTrue(pauseCleared)

        let clearsAfterPause = server.activities.filter { $0 is NSNull }.count
        engine.apply(cards: [card], presets: [preset], browserResult: .value(value))
        let repushed = await waitUntil(timeout: 10) {
            self.server.activities.filter { payload in self.payload(payload, contains: "github.com") }.count >= 2
        }
        XCTAssertTrue(repushed)

        card.isOn = false
        engine.apply(cards: [card], presets: [preset], browserResult: .value(value))
        let turnOffCleared = await waitUntil(timeout: 5) {
            self.server.activities.filter { $0 is NSNull }.count > clearsAfterPause
        }
        XCTAssertTrue(turnOffCleared)
        engine.stop()
    }

    func testTwoCardsUseTwoConnectionsAndSendTwoActivities() async throws {
        let engine = PresenceEngine(appID: "unused")
        let firstID = UUID()
        let secondID = UUID()

        engine.apply([
            CardRunSpec(cardID: firstID, applicationID: "111111111111111111", activity: Activity(name: "A", details: "first")),
            CardRunSpec(cardID: secondID, applicationID: "222222222222222222", activity: Activity(name: "B", details: "second")),
        ])

        let pushed = await waitUntil(timeout: 10) {
            self.server.connectionActivities.values.filter { !$0.isEmpty }.count == 2
        }
        XCTAssertTrue(pushed, "expected one SET_ACTIVITY on each connection, got \(server.connectionActivities)")
        XCTAssertEqual(server.connectionClientIDs.values.sorted(), ["111111111111111111", "222222222222222222"])

        engine.stop()
    }

    /// One application means one card, so the duplicate is refused — but refusing it must not take
    /// the *other* card down with it: the first card keeps running, exactly one connection exists.
    func testDuplicateApplicationIDIsBlockedWithoutHoldingBackTheFirstCard() async throws {
        let engine = PresenceEngine(appID: "unused")
        let issues = engine.apply([
            CardRunSpec(cardID: UUID(), applicationID: "111111111111111111", activity: Activity(name: "A", details: "first")),
            CardRunSpec(cardID: UUID(), applicationID: "111111111111111111", activity: Activity(name: "B", details: "second")),
        ])

        XCTAssertEqual(issues.map(\.kind), [.duplicateApplicationID], "the second card must be reported")

        let pushed = await waitUntil(timeout: 10) {
            self.server.connectionActivities.values.filter { !$0.isEmpty }.count == 1
        }
        XCTAssertTrue(pushed, "the first card must still run, got \(server.connectionActivities)")
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(Set(server.connectionClientIDs.values), ["111111111111111111"],
                       "one application id must mean one connection")
        engine.stop()
    }

    /// A card the user has not finished configuring (no application id yet) must not stop a card
    /// that is ready — otherwise adding a second card breaks the first one.
    func testUnconfiguredCardDoesNotHoldBackAConfiguredOne() async throws {
        let engine = PresenceEngine(appID: "unused")
        let issues = engine.apply([
            CardRunSpec(cardID: UUID(), applicationID: "", activity: Activity(name: "A", details: "first")),
            CardRunSpec(cardID: UUID(), applicationID: "111111111111111111", activity: Activity(name: "B", details: "second")),
        ])

        XCTAssertEqual(issues.map(\.kind), [.emptyApplicationID])

        let pushed = await waitUntil(timeout: 10) {
            self.server.connectionActivities.values.contains { activities in
                activities.contains { !($0 is NSNull) }
            }
        }
        XCTAssertTrue(pushed, "a half-configured card must not stop the configured one")
        engine.stop()
    }

    func testClearingOneCardOnlyClearsThatConnection() async throws {
        let engine = PresenceEngine(appID: "unused")
        let firstID = UUID()
        let secondID = UUID()
        engine.apply([
            CardRunSpec(cardID: firstID, applicationID: "111111111111111111", activity: Activity(name: "A", details: "first")),
            CardRunSpec(cardID: secondID, applicationID: "222222222222222222", activity: Activity(name: "B", details: "second")),
        ])
        let bothPushed = await waitUntil(timeout: 10) {
            self.server.connectionActivities.values.filter { !$0.isEmpty }.count == 2
        }
        XCTAssertTrue(bothPushed)

        let clearRequestedAt = server.appendEvent("test requested clear cardID=\(firstID)")
        engine.clear(cardID: firstID)

        let cleared = await waitUntil(timeout: 5) {
            self.server.anyConnectionContainsClear(
                forClientID: "111111111111111111",
                afterEventIndex: clearRequestedAt,
                reason: "testClearingOneCardOnlyClearsThatConnection clear assertion"
            )
        }
        let secondCleared = server.anyConnectionContainsClear(
            forClientID: "222222222222222222",
            afterEventIndex: clearRequestedAt,
            reason: "testClearingOneCardOnlyClearsThatConnection second assertion"
        )
        let trace = server.events.joined(separator: "\n")
        print("FakeDiscordServer trace for testClearingOneCardOnlyClearsThatConnection:\n\(trace)")
        XCTAssertTrue(cleared, "first card never sent activity:null; server events:\n\(trace)")
        XCTAssertFalse(secondCleared,
                       "clearing the first card must not clear the second client; server events:\n\(trace)")
        engine.stop()
    }

    func testRejectedHandshakeOnOneCardLeavesTheOtherConnected() async throws {
        server.rejectedClientIDs["222222222222222222"] = (4000, "Invalid Client ID")
        let engine = PresenceEngine(appID: "unused")
        engine.apply([
            CardRunSpec(cardID: UUID(), applicationID: "111111111111111111", activity: Activity(name: "A", details: "first")),
            CardRunSpec(cardID: UUID(), applicationID: "222222222222222222", activity: Activity(name: "B", details: "second")),
        ])

        let firstPushed = await waitUntil(timeout: 10) {
            guard let connectionID = self.server.latestConnectionID(
                forClientID: "111111111111111111",
                reason: "testRejectedHandshakeOnOneCardLeavesTheOtherConnected first push assertion"
            ) else {
                return false
            }
            return self.server.connectionActivities[connectionID]?.isEmpty == false
        }
        XCTAssertTrue(firstPushed, "healthy card must still connect and send")

        let failed = await waitUntil(timeout: 5) {
            if case .partial(let live, let failing) = engine.multiStatus {
                return live == 1 && failing == 1
            }
            if case .failed(_, let failing) = engine.multiStatus {
                return failing == 1
            }
            return false
        }
        XCTAssertTrue(failed, "expected one-card failure to be summarized, got \(engine.multiStatus)")
        engine.stop()
    }
}
