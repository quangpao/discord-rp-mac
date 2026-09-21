import Foundation

/// What a Reconnect has to do.
///
/// This lives in the library rather than in the app target so it can be unit tested: the app target
/// is Swift 5 language mode and has no test target of its own. It exists because the app used to call
/// `updateConnection`, which returns early when nothing changed — so pressing Reconnect with the
/// current settings did nothing at all, exactly when a user needs it (Discord restarted, stale
/// socket, or the active preset has to be pushed again).
public struct ConnectionSettings: Equatable, Sendable {
    public var appID: String
    public var pipeIndex: Int

    public init(appID: String, pipeIndex: Int) {
        self.appID = appID
        self.pipeIndex = pipeIndex
    }
}

public enum ReconnectPlan: Equatable, Sendable {
    /// Nothing to persist or reconnect — but the caller must still reassert the socket and re-apply
    /// the active preset. This is the case that used to be a no-op.
    case reapplyOnly
    /// Persist these settings, point the engine at them, then reassert and re-apply.
    case updateAndReapply(ConnectionSettings)

    public static func plan(current: ConnectionSettings,
                            requestedAppID: String,
                            requestedPipeIndex: Int) -> ReconnectPlan {
        let trimmed = requestedAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = ConnectionSettings(appID: trimmed, pipeIndex: requestedPipeIndex)
        return next == current ? .reapplyOnly : .updateAndReapply(next)
    }

    /// True when the user's edit has to be written to disk and pushed into the engine.
    public var changesSettings: Bool {
        if case .updateAndReapply = self { return true }
        return false
    }
}
