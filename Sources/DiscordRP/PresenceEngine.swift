import Foundation

/// Connection status surfaced to the UI.
public enum PresenceStatus: Equatable, Sendable {
    case idle
    case connecting
    case connected(user: String)
    /// Socket missing or refused — Discord is not running (the normal reason).
    case discordNotRunning
    case failed(code: Int, message: String)

    public var shortText: String {
        switch self {
        case .idle: "Starting…"
        case .connecting: "Connecting to Discord…"
        case .connected(let user): "Connected as \(user)"
        case .discordNotRunning: "Discord not running"
        case .failed(_, let message): message
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// SF Symbol for the menu bar item — per the design spec the glyph stays a template image
    /// and only the *shape* encodes state.
    public var symbolName: String {
        switch self {
        case .connected: "bolt.horizontal.circle.fill"
        default: "bolt.horizontal.circle"
        }
    }

    /// Leading dot on the status row.
    public var dotSymbolName: String {
        switch self {
        case .connected: "circle.fill"
        case .connecting: "circle.dotted"
        case .discordNotRunning: "circle"
        case .failed: "exclamationmark.circle.fill"
        case .idle: "circle.dotted"
        }
    }

    /// Draws the 6 px red badge on the status item.
    public var needsAttention: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Owns the Discord connection: connect, push, keepalive, reconnect, debounce.
///
/// All IO happens on a private serial queue (the client is queue-confined); published state
/// hops back to the main actor.
@MainActor
public final class PresenceEngine: ObservableObject {
    @Published public private(set) var status: PresenceStatus = .idle
    @Published public private(set) var issues: [ActivityIssue] = []

    private let worker: Worker

    public init(appID: String, pipeIndex: Int = 0, appStarted: Date = Date()) {
        let box = StatusBox()
        let worker = Worker(appID: appID, pipeIndex: pipeIndex, appStarted: appStarted)
        self.worker = worker
        box.engine = self
        worker.onStatus = { status in
            Task { @MainActor in box.engine?.status = status }
        }
        worker.onIssues = { issues in
            Task { @MainActor in box.engine?.issues = issues }
        }
    }

    public func start() { worker.start() }

    public func update(appID: String, pipeIndex: Int) {
        worker.update(appID: appID, pipeIndex: pipeIndex)
    }

    /// Validates locally first: invalid input never reaches Discord. Returns the issues so the
    /// editor can show them.
    @discardableResult
    public func apply(_ activity: Activity) -> [ActivityIssue] {
        let issues = ActivityRules.validate(activity, appID: worker.appID)
        self.issues = issues
        guard ActivityRules.errors(in: issues).isEmpty else { return issues }
        worker.push(activity)
        return issues
    }

    public func clear() { worker.clear() }

    /// Force an immediate keepalive ping and re-push the current activity. Used when the system
    /// wakes (or when the app was idle long enough that App Nap may have stalled the timers), so
    /// the presence is re-asserted instead of silently going stale.
    public func reassert() { worker.reassert() }

    /// Clears the presence and closes the socket — used on quit.
    public func stop() { worker.stop() }
}

/// Indirection so the worker's status callback can reach the engine without a retain cycle.
@MainActor
private final class StatusBox {
    weak var engine: PresenceEngine?
}

// MARK: - worker

private final class Worker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.kun.customrp.ipc")
    private var timer: DispatchSourceTimer?
    private var client: DiscordIPCClient?

    private(set) var appID: String
    private var pipeIndex: Int
    private let appStarted: Date

    private var currentActivity: Activity?
    private var needsPush = false
    private var pushAt: Date?
    private var presenceStarted = Date()
    private var connectionStarted: Date?
    private var lastPing = Date.distantPast
    private var pingCount = 0
    private var nextRetryAt = Date.distantPast
    private var backoffIndex = 0
    /// Set when Discord rejects the Application ID (code 4000): retrying forever is pointless.
    private var paused = false

    var onStatus: (@Sendable (PresenceStatus) -> Void)?
    var onIssues: (@Sendable ([ActivityIssue]) -> Void)?

    private static let retryDelays: [TimeInterval] = [2, 5, 10, 30]

    init(appID: String, pipeIndex: Int, appStarted: Date) {
        self.appID = appID
        self.pipeIndex = pipeIndex
        self.appStarted = appStarted
    }

    // MARK: commands (called from the main actor)

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 0.5)
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
            PresenceLog.note("timer started (tick 0.5s, ping 15s)")
        }
    }

    func update(appID: String, pipeIndex: Int) {
        queue.async { [self] in
            guard appID != self.appID || pipeIndex != self.pipeIndex else { return }
            self.appID = appID
            self.pipeIndex = pipeIndex
            self.paused = false
            teardown()
            backoffIndex = 0
            nextRetryAt = .distantPast
            emit(.connecting)
        }
    }

    func push(_ activity: Activity) {
        queue.async { [self] in
            currentActivity = activity
            needsPush = true
            // Discord rate-limits SET_ACTIVITY: coalesce rapid edits.
            pushAt = Date().addingTimeInterval(1.5)
        }
    }

    func clear() {
        queue.async { [self] in
            currentActivity = nil
            needsPush = false
            pushAt = nil
            guard let client, client.isConnected else { return }
            try? client.setActivity(nil)
        }
    }

    func stop() {
        queue.sync { [self] in
            if let client, client.isConnected { try? client.setActivity(nil) }
            teardown()
            timer?.cancel()
            timer = nil
            emit(.idle)
            PresenceLog.note("timer stopped")
        }
    }

    /// Ping now and re-send the presence, without waiting for the next timer deadline.
    func reassert() {
        queue.async { [self] in
            lastPing = .distantPast
            if currentActivity != nil {
                needsPush = true
                pushAt = Date()
            }
            tick()
        }
    }

    // MARK: state machine (queue-confined)

    private func tick() {
        guard !paused else { return }
        let now = Date()

        guard let client else {
            guard now >= nextRetryAt else { return }
            connect()
            return
        }

        if needsPush, let pushAt, now >= pushAt {
            self.pushAt = nil
            needsPush = false
            present(client: client, at: now)
        }

        if now.timeIntervalSince(lastPing) >= 15 {
            lastPing = now
            pingCount += 1
            // One line a minute: enough to prove the keepalive is alive without flooding the log.
            if pingCount % 4 == 0 {
                PresenceLog.note("alive pings=\(pingCount) connected=\(client.isConnected)")
            }
            if !client.ping() {
                PresenceLog.note("ping failed — reconnecting")
                teardown()
                scheduleRetry()
            }
        }
    }

    private func connect() {
        emit(.connecting)
        let candidate = DiscordIPCClient(appID: appID)
        do {
            try candidate.connect(pipeIndex: pipeIndex)
            client = candidate
            connectionStarted = Date()
            lastPing = Date()
            backoffIndex = 0
            let user = candidate.readyUser?.username ?? "Discord"
            emit(.connected(user: user))
            onIssues?([])
            // (Re)send the current presence as soon as we are ready — CustomRP does the same
            // on its OnReady event (MainForm.cs:835).
            if currentActivity != nil {
                needsPush = true
                pushAt = Date()
            }
        } catch let error as IPCError {
            candidate.close()
            switch error {
            case .discordRejected(let code, let message):
                if code == 4000 {
                    paused = true
                    PresenceLog.note("paused: Discord rejected the application id (4000)")
                }
                emit(.failed(code: code, message: code == 4000 ? "Invalid Application ID" : message))
                onIssues?([ActivityIssue(field: .appID, message: message)])
            default:
                emit(.discordNotRunning)
            }
            scheduleRetry()
        } catch {
            candidate.close()
            emit(.discordNotRunning)
            scheduleRetry()
        }
    }

    private func present(client: DiscordIPCClient, at now: Date) {
        guard let activity = currentActivity else {
            try? client.setActivity(nil)
            return
        }
        let payload = ActivityRules.payload(
            activity,
            appID: appID,
            now: now,
            appStarted: appStarted,
            connectionStarted: connectionStarted ?? now,
            presenceStarted: presenceStarted
        )
        guard let payload else {
            // Should be unreachable — the engine validates before pushing.
            onIssues?(ActivityRules.validate(activity, appID: appID))
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try client.setActivity(data)
            presenceStarted = now
            PresenceLog.record(payload: data, error: nil)
            onIssues?([])
        } catch let error as IPCError {
            if case .discordRejected(let code, let message) = error {
                if code == 4000 { paused = true }
                emit(.failed(code: code, message: code == 4000 ? "Invalid Application ID" : message))
            } else {
                teardown()
                scheduleRetry()
            }
            PresenceLog.record(payload: nil, error: "\(error)")
        } catch {
            teardown()
            scheduleRetry()
            PresenceLog.record(payload: nil, error: "\(error)")
        }
    }

    private func scheduleRetry() {
        let delay = Self.retryDelays[min(backoffIndex, Self.retryDelays.count - 1)]
        backoffIndex += 1
        nextRetryAt = Date().addingTimeInterval(delay)
    }

    private func teardown() {
        client?.close()
        client = nil
        connectionStarted = nil
    }

    private func emit(_ status: PresenceStatus) {
        onStatus?(status)
    }
}
