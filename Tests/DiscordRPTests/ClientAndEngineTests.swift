import XCTest

@testable import DiscordRP

/// Client behaviour against a local fake: handshake, push, clear, ping, rejection, hangup.
final class DiscordIPCClientTests: XCTestCase {
    private var server: FakeDiscordServer!

    override func setUpWithError() throws {
        server = FakeDiscordServer()
        try server.start()
        setenv("CUSTOMRP_IPC_PATH", server.path, 1)
        // Never write into the developer's real log directory: a test run used to overwrite
        // ~/Library/Logs/DiscordRP/last-presence.json with the fixture payload.
        PresenceLog.directoryOverride = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-log-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        unsetenv("CUSTOMRP_IPC_PATH")
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

    func testCommandsWithoutConnectionThrow() {
        let client = DiscordIPCClient(appID: "123", readTimeout: 1)
        XCTAssertThrowsError(try client.setActivity(nil))
    }
}

/// End-to-end through the engine: connect, push a preset, clear.
@MainActor
final class PresenceEngineTests: XCTestCase {
    private var server: FakeDiscordServer!

    override func setUpWithError() throws {
        server = FakeDiscordServer()
        try server.start()
        setenv("CUSTOMRP_IPC_PATH", server.path, 1)
        // Never write into the developer's real log directory: a test run used to overwrite
        // ~/Library/Logs/DiscordRP/last-presence.json with the fixture payload.
        PresenceLog.directoryOverride = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-log-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        unsetenv("CUSTOMRP_IPC_PATH")
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
}
