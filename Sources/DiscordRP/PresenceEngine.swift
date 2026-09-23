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

    /// The one line the menu shows. Phrased so a single-card user reads exactly what the app said
    /// before cards existed.
    public var shortText: String {
        switch self {
        case .idle: "Starting…"
        case .connecting(let active): active == 1 ? "Connecting to Discord…" : "Connecting \(active) cards…"
        case .live(let active): active == 1 ? "Connected" : "Connected — \(active) cards"
        case .partial(let live, let failing): "\(live) live, \(failing) needs attention"
        case .discordNotRunning: "Discord not running"
        case .failed(let message, _): message
        }
    }

    /// True while at least one card is being pushed — a partly-failing setup is still connected.
    public var isConnected: Bool {
        switch self {
        case .live, .partial: true
        default: false
        }
    }

    /// Drives the red badge on the menu bar item.
    public var needsAttention: Bool {
        switch self {
        case .partial, .failed: true
        default: false
        }
    }

    public var symbolName: String {
        isConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
    }

    public var dotSymbolName: String {
        switch self {
        case .live: "circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .connecting, .idle: "circle.dotted"
        case .discordNotRunning: "circle"
        case .failed: "exclamationmark.circle.fill"
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
    /// Cards that are enabled and whose preset activity names collide. Discord renders one activity
    /// per name, so the extra cards never appear on the profile.
    public static func duplicateActivityNameCards(_ cards: [PresenceCard], presets: [Preset]) -> [UUID: String] {
        let presetsByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        var cardsByName: [String: [(UUID, String)]] = [:]

        for card in cards where card.isOn {
            guard let preset = presetsByID[card.presetID] else { continue }
            let name = preset.activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            cardsByName[name.folding(options: [.caseInsensitive], locale: nil), default: []].append((card.id, name))
        }

        var duplicates: [UUID: String] = [:]
        for group in cardsByName.values where group.count > 1 {
            for (cardID, name) in group {
                duplicates[cardID] = name
            }
        }
        return duplicates
    }

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

    public func forceReconnect() {
        worker.forceReconnect()
        for worker in cardWorkers.values { worker.forceReconnect() }
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
        var started = 0
        for change in changes {
            switch change {
            case .start(let spec):
                let worker = makeCardWorker(for: spec)
                cardWorkers[spec.cardID] = worker
                cardSpecs[spec.cardID] = spec
                cardStatuses[spec.cardID] = .connecting
                // Discord throttles a *burst* of handshakes: about four back-to-back ones are
                // answered and the fifth times out. Starting several cards at once is therefore
                // staggered by 400 ms — a handful of cards, and the engine's own retry/backoff
                // covers the rest.
                let delay = Double(started) * 0.4
                started += 1
                if delay > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        // The card may have been turned off again while this was waiting.
                        guard self.cardWorkers[spec.cardID] === worker else { return }
                        worker.start()
                        worker.push(spec.activity)
                    }
                } else {
                    worker.start()
                    worker.push(spec.activity)
                }
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
    private let stateLock = NSLock()
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
    private var stopped = false
    private var running = false

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
        setStopped(false)
        setRunning(true)
        queue.async { [self] in
            guard !isStopped else { return }
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 0.5)
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
            logNote("timer started (tick 0.5s, ping 15s)")
        }
    }

    func update(appID: String, pipeIndex: Int) {
        queue.async { [self] in
            guard !isStopped else { return }
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

    func forceReconnect() {
        guard isRunning else { return }
        queue.async { [self] in
            guard !isStopped, timer != nil else { return }
            forceReconnectOnQueue()
        }
    }

    func push(_ activity: Activity) {
        queue.async { [self] in
            guard !isStopped else { return }
            currentActivity = activity
            needsPush = true
            // Discord rate-limits SET_ACTIVITY: coalesce rapid edits.
            pushAt = Date().addingTimeInterval(1.5)
        }
    }

    func clear() {
        queue.async { [self] in
            guard !isStopped else { return }
            currentActivity = nil
            needsPush = false
            pushAt = nil
            guard let client, client.isConnected else { return }
            do {
                let reply = try client.setActivityWithReply(nil)
                guard !isStopped else { return }
                logRecord(payload: nil, appID: appID, reply: reply, error: nil)
            } catch {
                guard !isStopped else { return }
                logRecord(payload: nil, appID: appID, reply: client.lastReply, error: "\(error)")
            }
        }
    }

    func stop() {
        setRunning(false)
        setStopped(true)
        logNote("timer stopped")
        queue.async { [self] in
            let closingClient = client
            client = nil
            connectionStarted = nil
            currentActivity = nil
            needsPush = false
            pushAt = nil
            paused = false
            backoffIndex = 0
            nextRetryAt = .distantPast
            timer?.cancel()
            timer = nil
            emit(.idle)

            if let closingClient, closingClient.isConnected {
                do {
                    let reply = try closingClient.setActivityWithReply(nil)
                    logRecord(payload: nil, appID: appID, reply: reply, error: nil)
                } catch IPCError.discordClosed {
                    // The peer can disappear during async teardown; closing below is enough.
                } catch {
                    logRecord(payload: nil, appID: appID, reply: closingClient.lastReply, error: "\(error)")
                }
            }
            closingClient?.close()
        }
    }

    /// Ping now and re-send the presence, without waiting for the next timer deadline.
    func reassert() {
        queue.async { [self] in
            guard !isStopped else { return }
            if paused {
                forceReconnectOnQueue()
                return
            }
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
        guard !isStopped else { return }
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
                logNote("alive pings=\(pingCount) connected=\(client.isConnected)")
            }
            if !client.ping() {
                logNote("ping failed — reconnecting")
                teardown()
                scheduleRetry()
            }
        }
    }

    private func connect() {
        guard !isStopped else { return }
        emit(.connecting)
        let candidate = DiscordIPCClient(appID: appID)
        do {
            try candidate.connect(pipeIndex: pipeIndex)
            guard !isStopped else {
                candidate.close()
                return
            }
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
            guard !isStopped else { return }
            switch error {
            case .discordRejected(let code, let message):
                if code == 4000 {
                    // During the handshake 4000 does mean the client id was refused, so retrying
                    // forever would be pointless — Reconnect clears this once the id is fixed.
                    paused = true
                    logNote("handshake rejected (4000): \(message)")
                }
                emit(.failed(code: code, message: message))
                onIssues?([ActivityIssue(field: .appID, message: message)])
            default:
                emit(.discordNotRunning)
            }
            scheduleRetry()
        } catch {
            candidate.close()
            guard !isStopped else { return }
            emit(.discordNotRunning)
            scheduleRetry()
        }
    }

    private func present(client: DiscordIPCClient, at now: Date) {
        guard let activity = currentActivity else {
            do {
                let reply = try client.setActivityWithReply(nil)
                guard !isStopped else { return }
                logRecord(payload: nil, appID: appID, reply: reply, error: nil)
            } catch {
                guard !isStopped else { return }
                logRecord(payload: nil, appID: appID, reply: client.lastReply, error: "\(error)")
            }
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
            let reply = try client.setActivityWithReply(data)
            guard !isStopped else { return }
            presenceStarted = now
            logRecord(payload: data, appID: appID, reply: reply, error: nil)
            onIssues?([])
        } catch let error as IPCError {
            guard !isStopped else { return }
            if case .discordRejected(let code, let message) = error {
                // 4000 is Discord's generic "invalid payload" rejection, NOT necessarily a bad
                // Application ID: sending type 1 (Streaming) produces exactly this code with
                // `"type" must be one of [0, 2, 3, 5]`. Never pause on it — pause used to stop the
                // timer for good and report "Invalid Application ID", which hid the real cause.
                logNote("push rejected (code \(code)): \(message)")
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
            logRecord(payload: nil, appID: appID, reply: client.lastReply, error: "\(error)")
        } catch {
            guard !isStopped else { return }
            teardown()
            scheduleRetry()
            logRecord(payload: nil, appID: appID, reply: client.lastReply, error: "\(error)")
        }
    }

    private func forceReconnectOnQueue() {
        paused = false
        teardown()
        backoffIndex = 0
        nextRetryAt = .distantPast
        lastPing = .distantPast
        emit(.connecting)
        connect()
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
        guard !isStopped || status == .idle else { return }
        onStatus?(status)
    }

    private func logRecord(payload: Data?,
                           appID: String? = nil,
                           reply: DiscordIPCClient.Reply? = nil,
                           error: String?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return }
        PresenceLog.record(payload: payload, appID: appID, reply: reply, error: error)
    }

    private func logNote(_ message: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return }
        PresenceLog.note(message)
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    private var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    private func setStopped(_ value: Bool) {
        stateLock.lock()
        stopped = value
        stateLock.unlock()
    }

    private func setRunning(_ value: Bool) {
        stateLock.lock()
        running = value
        stateLock.unlock()
    }
}
