import XCTest
@testable import DiscordRP

/// The Reconnect button used to call `updateConnection`, which returns early when the values are
/// unchanged — so pressing it with the current settings did nothing. These tests pin the behaviour
/// that replaced it: unchanged settings must still plan a reapply, and only real edits persist.
final class ReconnectPlanTests: XCTestCase {
    private let current = ConnectionSettings(appID: "123456789012345678", pipeIndex: 0)

    func testUnchangedSettingsStillReapply() {
        let plan = ReconnectPlan.plan(current: current,
                                      requestedAppID: current.appID,
                                      requestedPipeIndex: current.pipeIndex)
        XCTAssertEqual(plan, .reapplyOnly)
        XCTAssertFalse(plan.changesSettings,
                       "an unchanged reconnect must not rewrite settings, but must still reassert and re-apply")
    }

    func testWhitespaceOnlyEditIsNotAChange() {
        let plan = ReconnectPlan.plan(current: current,
                                      requestedAppID: "  \(current.appID)\n",
                                      requestedPipeIndex: current.pipeIndex)
        XCTAssertEqual(plan, .reapplyOnly)
    }

    func testChangedAppIDUpdates() {
        let plan = ReconnectPlan.plan(current: current,
                                      requestedAppID: "987654321098765432",
                                      requestedPipeIndex: 0)
        XCTAssertEqual(plan, .updateAndReapply(ConnectionSettings(appID: "987654321098765432", pipeIndex: 0)))
        XCTAssertTrue(plan.changesSettings)
    }

    func testChangedPipeIndexUpdates() {
        let plan = ReconnectPlan.plan(current: current,
                                      requestedAppID: current.appID,
                                      requestedPipeIndex: 2)
        XCTAssertEqual(plan, .updateAndReapply(ConnectionSettings(appID: current.appID, pipeIndex: 2)))
    }

    func testTrimsBeforeComparing() {
        let plan = ReconnectPlan.plan(current: current,
                                      requestedAppID: " \(current.appID) ",
                                      requestedPipeIndex: 1)
        XCTAssertEqual(plan, .updateAndReapply(ConnectionSettings(appID: current.appID, pipeIndex: 1)))
    }

    func testClearedAppIDIsPersisted() {
        // Clearing the field must be written to disk (the engine then stops pushing), not ignored.
        let plan = ReconnectPlan.plan(current: current, requestedAppID: "   ", requestedPipeIndex: 0)
        XCTAssertEqual(plan, .updateAndReapply(ConnectionSettings(appID: "", pipeIndex: 0)))
    }
}
