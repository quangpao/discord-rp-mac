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

public struct CardRunSpec: Equatable, Sendable, Identifiable {
    public var id: UUID { cardID }
    public var cardID: UUID
    public var applicationID: String
    public var activity: Activity

    public init(cardID: UUID, applicationID: String, activity: Activity) {
        self.cardID = cardID
        self.applicationID = applicationID
        self.activity = activity
    }
}

public struct CardValidationIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case missingPreset
        case emptyApplicationID
        case duplicateApplicationID
        case invalidActivity
    }

    public var cardID: UUID
    public var kind: Kind
    public var message: String

    public init(cardID: UUID, kind: Kind, message: String) {
        self.cardID = cardID
        self.kind = kind
        self.message = message
    }
}

public enum MultiPresenceStatus: Equatable, Sendable {
    case idle
    case connecting(active: Int)
    case live(active: Int)
    case partial(live: Int, failing: Int)
    case discordNotRunning
    case failed(message: String, failing: Int)

    public var shortText: String {
        switch self {
        case .idle: "Idle"
        case .connecting(let active): "Connecting \(active) card\(active == 1 ? "" : "s")…"
        case .live(let active): "Live on \(active) card\(active == 1 ? "" : "s")"
        case .partial(let live, let failing): "\(live) live, \(failing) failing"
        case .discordNotRunning: "Discord not running"
        case .failed(let message, _): message
        }
    }
}

public struct RunningCardSnapshot: Equatable, Sendable {
    public var cardID: UUID
    public var applicationID: String
    public var activity: Activity?

    public init(cardID: UUID, applicationID: String, activity: Activity?) {
        self.cardID = cardID
        self.applicationID = applicationID
        self.activity = activity
    }
}

public enum CardWorkerChange: Equatable, Sendable {
    case start(CardRunSpec)
    case update(CardRunSpec)
    case clear(UUID)
    case stop(UUID)
}

public enum PresenceCardPlanner {
    /// The rules a card must pass before anything is sent. Messages stay generic and every issue
    /// carries the card id — the UI shows the card's own name beside it, so the name is not baked
    /// into the message (that is what made two copies of these rules drift apart).
    public static func validate(specs: [CardRunSpec]) -> [CardValidationIssue] {
        var seenApplications: Set<String> = []
        var issues: [CardValidationIssue] = []

        for spec in specs {
            let applicationID = spec.applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !applicationID.isEmpty else {
                issues.append(CardValidationIssue(
                    cardID: spec.cardID,
                    kind: .emptyApplicationID,
                    message: "Application ID is required."
                ))
                continue
            }
            guard !seenApplications.contains(applicationID) else {
                issues.append(CardValidationIssue(
                    cardID: spec.cardID,
                    kind: .duplicateApplicationID,
                    message: "Application ID \(applicationID) is already used by another active card."
                ))
                continue
            }
            seenApplications.insert(applicationID)

            let activityIssues = ActivityRules.errors(in: ActivityRules.validate(spec.activity, appID: applicationID))
            if !activityIssues.isEmpty {
                issues.append(CardValidationIssue(
                    cardID: spec.cardID,
                    kind: .invalidActivity,
                    message: activityIssues.map(\.message).joined(separator: " ")
                ))
            }
        }
        return issues
    }

    /// Resolves each enabled card's preset, then applies the shared spec-level rules. Returns the
    /// specs that may run plus every issue found, so a caller can start the good cards and still
    /// report the bad one.
    public static func validate(cards: [PresenceCard],
                                presets: [Preset]) -> ([CardRunSpec], [CardValidationIssue]) {
        let presetsByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        var specs: [CardRunSpec] = []
        var issues: [CardValidationIssue] = []

        for card in cards where card.isOn {
            guard let preset = presetsByID[card.presetID] else {
                issues.append(CardValidationIssue(
                    cardID: card.id,
                    kind: .missingPreset,
                    message: "Preset not found."
                ))
                continue
            }
            specs.append(CardRunSpec(cardID: card.id, applicationID: card.applicationID, activity: preset.activity))
        }

        issues.append(contentsOf: validate(specs: specs))
        let unrunnable = Set(issues.map(\.cardID))
        return (specs.filter { !unrunnable.contains($0.cardID) }, issues)
    }

    public static func diff(desired: [CardRunSpec], running: [RunningCardSnapshot]) -> [CardWorkerChange] {
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.cardID, $0) })
        let runningByID = Dictionary(uniqueKeysWithValues: running.map { ($0.cardID, $0) })
        var changes: [CardWorkerChange] = []

        for spec in desired where runningByID[spec.cardID] == nil {
            changes.append(.start(spec))
        }

        for spec in desired {
            guard let current = runningByID[spec.cardID] else { continue }
            if current.applicationID != spec.applicationID || current.activity != spec.activity {
                changes.append(.update(spec))
            }
        }

        for current in running where desiredByID[current.cardID] == nil {
            if current.activity != nil { changes.append(.clear(current.cardID)) }
            changes.append(.stop(current.cardID))
        }

        return changes
    }

    public static func reduce(statuses: [PresenceStatus]) -> MultiPresenceStatus {
        guard !statuses.isEmpty else { return .idle }

        let connected = statuses.filter(\.isConnected).count
        let connecting = statuses.filter {
            if case .connecting = $0 { return true }
            if case .idle = $0 { return true }
            return false
        }.count
        let discordMissing = statuses.filter { $0 == .discordNotRunning }.count
        let failures = statuses.compactMap { status -> String? in
            if case .failed(_, let message) = status { return message }
            return nil
        }

        if connected == statuses.count { return .live(active: connected) }
        if connected > 0 {
            let failing = statuses.count - connected - connecting
            return failing > 0 ? .partial(live: connected, failing: failing) : .connecting(active: statuses.count)
        }
        if connecting > 0 { return .connecting(active: statuses.count) }
        if discordMissing == statuses.count { return .discordNotRunning }
        return .failed(message: failures.first ?? "Presence failed", failing: max(1, failures.count))
    }
}

/// Owns the Discord connection: connect, push, keepalive, reconnect, debounce.
///
/// All IO happens on a private serial queue (the client is queue-confined); published state
/// hops back to the main actor.
@MainActor
public final class PresenceEngine: ObservableObject {
    @Published public private(set) var status: PresenceStatus = .idle
    @Published public private(set) var multiStatus: MultiPresenceStatus = .idle
    @Published public private(set) var issues: [ActivityIssue] = []
    @Published public private(set) var cardIssues: [CardValidationIssue] = []

    private let worker: Worker
    private var cardWorkers: [UUID: Worker] = [:]
    private var cardStatuses: [UUID: PresenceStatus] = [:]
    private var cardSpecs: [UUID: CardRunSpec] = [:]

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

    @discardableResult
    public func apply(_ specs: [CardRunSpec]) -> [CardValidationIssue] {
        let specs = specs.map {
            CardRunSpec(
                cardID: $0.cardID,
                applicationID: $0.applicationID.trimmingCharacters(in: .whitespacesAndNewlines),
                activity: $0.activity
            )
        }
        let issues = PresenceCardPlanner.validate(specs: specs)
        cardIssues = issues
        // A misconfigured card must not hold back the others: run every spec that validated and
        // report the rest. A card that *became* invalid is no longer in `desired`, so the diff below
        // clears and stops it.
        let unrunnable = Set(issues.map(\.cardID))
        let runnable = specs.filter { !unrunnable.contains($0.cardID) }

        let running = cardSpecs.values.map {
            RunningCardSnapshot(cardID: $0.cardID, applicationID: $0.applicationID, activity: $0.activity)
        }
        let changes = PresenceCardPlanner.diff(desired: runnable, running: running)
        for change in changes {
            switch change {
            case .start(let spec):
                let worker = makeCardWorker(for: spec)
                cardWorkers[spec.cardID] = worker
                cardSpecs[spec.cardID] = spec
                cardStatuses[spec.cardID] = .connecting
                worker.start()
                worker.push(spec.activity)
            case .update(let spec):
                if let worker = cardWorkers[spec.cardID] {
                    let previous = cardSpecs[spec.cardID]
                    if previous?.applicationID != spec.applicationID {
                        worker.update(appID: spec.applicationID, pipeIndex: worker.pipeIndex)
                    }
                    worker.push(spec.activity)
                    cardSpecs[spec.cardID] = spec
                }
            case .clear(let cardID):
                cardWorkers[cardID]?.clear()
                cardSpecs[cardID] = nil
            case .stop(let cardID):
                cardWorkers[cardID]?.stop()
                cardWorkers[cardID] = nil
                cardStatuses[cardID] = nil
                cardSpecs[cardID] = nil
            }
        }
        reduceCardStatus()
        return issues
    }

    @discardableResult
    public func apply(cards: [PresenceCard], presets: [Preset]) -> [CardValidationIssue] {
        let (specs, issues) = PresenceCardPlanner.validate(cards: cards, presets: presets)
        _ = apply(specs)
        cardIssues = issues
        return issues
    }

    public func clear(cardID: UUID) {
        cardWorkers[cardID]?.stop()
        cardWorkers[cardID] = nil
        cardStatuses[cardID] = nil
        cardSpecs[cardID] = nil
        reduceCardStatus()
    }

    public func clearAll() {
        for worker in cardWorkers.values { worker.stop() }
        cardWorkers.removeAll()
        cardStatuses.removeAll()
        cardSpecs.removeAll()
        reduceCardStatus()
    }

    /// Force an immediate keepalive ping and re-push the current activity. Used when the system
    /// wakes (or when the app was idle long enough that App Nap may have stalled the timers), so
    /// the presence is re-asserted instead of silently going stale.
    public func reassert() {
        worker.reassert()
        for worker in cardWorkers.values { worker.reassert() }
    }

    /// Clears the presence and closes the socket — used on quit.
    public func stop() {
        worker.stop()
        for worker in cardWorkers.values { worker.stop() }
        cardWorkers.removeAll()
        cardStatuses.removeAll()
        cardSpecs.removeAll()
        reduceCardStatus()
    }

    private func makeCardWorker(for spec: CardRunSpec) -> Worker {
        let worker = Worker(appID: spec.applicationID, pipeIndex: self.worker.pipeIndex, appStarted: Date())
        worker.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.cardStatuses[spec.cardID] = status
                self?.reduceCardStatus()
            }
        }
        return worker
    }

    private func reduceCardStatus() {
        multiStatus = PresenceCardPlanner.reduce(statuses: Array(cardStatuses.values))
    }
}

/// Indirection so the worker's status callback can reach the engine without a retain cycle.
@MainActor
private final class StatusBox {
    weak var engine: PresenceEngine?
}

// MARK: - worker

private final class Worker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.quangpao.discordrp.ipc")
    private var timer: DispatchSourceTimer?
    private var client: DiscordIPCClient?

    private(set) var appID: String
    private(set) var pipeIndex: Int
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
            // (Re)send the current presence as soon as the handshake completes, so a preset is
            // live the moment Discord is reachable.
            if currentActivity != nil {
                needsPush = true
                pushAt = Date()
            }
        } catch let error as IPCError {
            candidate.close()
            switch error {
            case .discordRejected(let code, let message):
                if code == 4000 {
                    // During the handshake 4000 does mean the client id was refused, so retrying
                    // forever would be pointless — Reconnect clears this once the id is fixed.
                    paused = true
                    PresenceLog.note("handshake rejected (4000): \(message)")
                }
                emit(.failed(code: code, message: message))
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
                // 4000 is Discord's generic "invalid payload" rejection, NOT necessarily a bad
                // Application ID: sending type 1 (Streaming) produces exactly this code with
                // `"type" must be one of [0, 2, 3, 5]`. Never pause on it — pause used to stop the
                // timer for good and report "Invalid Application ID", which hid the real cause.
                PresenceLog.note("push rejected (code \(code)): \(message)")
                onIssues?([ActivityIssue(field: .kind, message: message)])
                needsPush = true
                pushAt = Date().addingTimeInterval(10)
                // Report Discord's own wording: code 4000 is a payload rejection, not necessarily
                // a bad Application ID, and the old hardcoded text sent us chasing the wrong thing.
                emit(.failed(code: code, message: message))
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
