import AppKit
import Combine
import DiscordRP
import SwiftUI

/// Single source of truth for the UI: presets, settings and the presence engine.
@MainActor
final class AppModel: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var settings = AppSettings()
    /// Per-card problems (a missing preset, an empty or duplicated application id…). The menu only
    /// ever shows one status line, so these surface in Settings, not as extra rows.
    @Published private(set) var cardIssues: [CardValidationIssue] = []
    /// The reduced state of every live card — what the single menu status line reports.
    @Published var multiStatus: MultiPresenceStatus = .idle
    @Published var status: PresenceStatus = .idle
    @Published var issues: [ActivityIssue] = []
    @Published var launchAtLogin: Bool = false
    @Published var updateStatus: UpdateStatus = .idle

    let engine: PresenceEngine
    private let store: PresetStore
    private var editor: EditorWindowController?
    private var settingsWindow: SettingsWindowController?
    /// Held for the app's lifetime: App Nap suspends a menu bar app's timers, which silently killed
    /// the RPC keepalive (measured: pings stopped ~2 minutes after launch, so Discord saw a dead
    /// connection and the activity disappeared). This token keeps the app out of App Nap while
    /// still allowing the system itself to sleep.
    private var activityToken: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// `store` is injectable so the screenshot renderer can draw the built-in demo preset set from
    /// a throwaway directory instead of the developer's own presets.
    init(startEngine: Bool = true, store injected: PresetStore? = nil) {
        // Before anything reads presets/settings: move the data files over from the pre-rename names
        // (`CustomRP` → `Discord RP`). Files only — the Keychain half runs later, off the main
        // thread, because a Keychain prompt on this path used to hang the launch (see
        // `Migration.migrateKeychainInBackground`).
        Migration.runIfNeeded()

        let store = injected ?? PresetStore()
        var settings = store.loadSettings()
        var presets = store.loadPresets()

        if presets.isEmpty {
            presets = [Preset(name: "Default", activity: Activity.sample())]
            settings.activePresetID = presets.first?.id
            try? store.save(presets: presets)
        }
        if settings.activePresetID == nil || !presets.contains(where: { $0.id == settings.activePresetID }) {
            settings.activePresetID = presets.first?.id
        }

        // A file written before cards existed (or a fresh install) gets exactly one card — the same
        // single presence a pre-cards build would have pushed. `PresetStore` already migrates the
        // stored case; this covers the empty one, and `wasLegacy` decides whether the file has to be
        // rewritten once so what is on disk is the card model.
        let wasLegacyFile = store.settingsFileIsLegacy()
        if settings.cards.isEmpty, let preset = presets.first(where: { $0.id == settings.activePresetID }) ?? presets.first {
            let cardAppID = settings.appID.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cards = [PresenceCard(name: "Main", presetID: preset.id,
                                           applicationID: cardAppID, isOn: !cardAppID.isEmpty)]
        }

        let engine = PresenceEngine(appID: settings.appID, pipeIndex: settings.pipeIndex)

        self.store = store
        self.settings = settings
        self.presets = presets
        self.engine = engine
        self.launchAtLogin = LaunchAtLogin.isEnabled

        engine.$status.assign(to: &$status)
        engine.$issues.assign(to: &$issues)
        engine.$multiStatus.assign(to: &$multiStatus)
        engine.$cardIssues.assign(to: &$cardIssues)

        if startEngine {
            // One connection per enabled card; a card with no application id is reported, not sent.
            _ = engine.apply(cards: settings.cards, presets: presets)
        }

        guard startEngine else { return }

        // The Keychain half of the rename, off the main thread: it can wait for a system prompt
        // without freezing the app or the presence engine.
        Migration.migrateKeychainInBackground { outcome in
            PresenceLog.note("giphy key migration: \(outcome.rawValue)")
        }

        // Launch-at-login: the registration is the source of truth, not the stored flag. Replacing
        // the app bundle (every rebuild) can silently drop an SMAppService registration, and the
        // CLI toggle does not write settings — so reconcile both ways and persist what is real.
        let loginItemEnabled = LaunchAtLogin.isEnabled
        launchAtLogin = loginItemEnabled
        if loginItemEnabled {
            settings.launchAtLogin = true
        } else if settings.launchAtLogin {
            try? LaunchAtLogin.setEnabled(true)
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        persistSettings()
        if wasLegacyFile { persistSettings() }

        // Keep the keepalive timer alive while the app sits idle in the menu bar.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep the Discord Rich Presence connection alive while idle"
        )
        // After a sleep/wake the socket may be stale: re-ping and re-push immediately.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [engine] _ in
            Task { @MainActor in engine.reassert() }
        }
    }

    deinit {
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    // MARK: presets

    var activePreset: Preset? {
        presets.first { $0.id == settings.activePresetID } ?? presets.first
    }

    var activePresetName: String { activePreset?.name ?? "None" }

    func select(_ preset: Preset) {
        settings.activePresetID = preset.id
        // With one card — the only case a user who never adds a second card sees — picking a preset
        // from the menu must keep behaving exactly as it always has: that card now shows it.
        if let index = settings.cards.firstIndex(where: { $0.id == primaryCard?.id }) {
            settings.cards[index].presetID = preset.id
        }
        applyCards()
    }

    func upsert(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persistPresets()
    }

    func addPreset(from activity: Activity, name: String) {
        let preset = Preset(name: name, activity: activity)
        presets.append(preset)
        settings.activePresetID = preset.id
        persistPresets()
        persistSettings()
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        if presets.isEmpty {
            presets = [Preset(name: "Default", activity: Activity.sample())]
        }
        if settings.activePresetID == preset.id {
            settings.activePresetID = presets.first?.id
        }
        // A card whose preset vanished is a configuration error the user must see, not a card that
        // silently keeps pushing a deleted preset's activity.
        if let fallback = settings.activePresetID {
            for index in settings.cards.indices where settings.cards[index].presetID == preset.id {
                settings.cards[index].presetID = fallback
            }
        }
        persistPresets()
        persistSettings()
        applyCards()
    }

    func duplicateActivePreset() {
        guard let active = activePreset else { return }
        addPreset(from: active.activity, name: active.name + " copy")
    }

    func deleteActivePreset() {
        guard let active = activePreset else { return }
        deletePreset(active)
    }

    func reapply() {
        applyCards()
    }

    // MARK: cards

    /// The card the menu and the editor mean when there is only one. A single-card user never has to
    /// know the card model exists.
    var primaryCard: PresenceCard? { settings.cards.first }

    var enabledCards: [PresenceCard] { settings.cards.filter(\.isOn) }

    var duplicateActivityNameCards: [UUID: String] {
        PresenceCardPlanner.duplicateActivityNameCards(settings.cards, presets: presets)
    }

    /// True when at least one enabled card has an application id — the condition for anything being
    /// sent at all.
    var hasRunnableCard: Bool {
        enabledCards.contains { !$0.applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Cancels what is being shown without changing the configuration: Reapply (or picking a preset)
    /// brings every enabled card straight back.
    func clearPresence() {
        engine.clearAll()
    }

    /// Pushes every enabled card and persists. This replaces the old single-card `engine.apply(_:)`
    /// call: with one card the result is identical, with several each card gets its own connection.
    func applyCards() {
        if settings.cards.isEmpty,
           let preset = presets.first(where: { $0.id == settings.activePresetID }) ?? presets.first {
            let cardAppID = settings.appID.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cards = [PresenceCard(name: "Main", presetID: preset.id,
                                           applicationID: cardAppID, isOn: !cardAppID.isEmpty)]
        }
        syncShadowSettings()
        cardIssues = engine.apply(cards: settings.cards, presets: presets)
        persistSettings()
    }

    /// The application id and active preset a pre-cards build reads must mirror the first card that
    /// is on, so opening this settings file with an older build still pushes the right presence.
    private func syncShadowSettings() {
        let shadow = settings.cards.first(where: { $0.isOn })
        settings.appID = shadow?.applicationID ?? ""
        if let presetID = shadow?.presetID ?? settings.cards.first?.presetID {
            settings.activePresetID = presetID
        }
    }

    func setCard(_ card: PresenceCard) {
        guard let index = settings.cards.firstIndex(where: { $0.id == card.id }) else { return }
        settings.cards[index] = card
        applyCards()
    }

    func addCard(presetID: UUID, applicationID: String) {
        settings.cards.append(PresenceCard(name: "Card \(settings.cards.count + 1)",
                                           presetID: presetID,
                                           applicationID: applicationID,
                                           isOn: false))
        persistSettings()
    }

    func removeCard(id: UUID) {
        engine.clear(cardID: id)
        settings.cards.removeAll { $0.id == id }
        applyCards()
    }

    func toggleCard(id: UUID, isOn: Bool) {
        guard let index = settings.cards.firstIndex(where: { $0.id == id }) else { return }
        settings.cards[index].isOn = isOn
        applyCards()
    }

    func makeActivityNameUnique(for cardID: UUID) {
        guard let cardIndex = settings.cards.firstIndex(where: { $0.id == cardID }),
              let presetIndex = presets.firstIndex(where: { $0.id == settings.cards[cardIndex].presetID })
        else { return }

        let label = cardLabel(for: settings.cards[cardIndex], index: cardIndex)
        let existing = presets[presetIndex].activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueName = "\(existing.isEmpty ? "Activity" : existing) · \(label)"
        var preset = presets[presetIndex]
        preset.activity.name = uniqueName

        let samePresetCollision = settings.cards.contains { card in
            card.id != cardID && card.isOn && card.presetID == preset.id
        }
        if samePresetCollision {
            preset.id = UUID()
            preset.name = "\(preset.name) · \(label)"
            presets.append(preset)
            settings.cards[cardIndex].presetID = preset.id
        } else {
            presets[presetIndex] = preset
        }

        persistPresets()
        applyCards()
    }

    private func cardLabel(for card: PresenceCard, index: Int) -> String {
        let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Card \(index + 1)" : name
    }

    // MARK: settings

    /// Always re-applies, even when the settings did not change: `updateConnection` returns early
    /// for unchanged values, which made the Reconnect button a no-op exactly when it is needed
    /// (Discord restarted, socket stale, active preset needs re-pushing).
    func reconnect(appID: String, pipeIndex: Int) {
        let plan = ReconnectPlan.plan(
            current: ConnectionSettings(appID: settings.appID, pipeIndex: settings.pipeIndex),
            requestedAppID: appID,
            requestedPipeIndex: pipeIndex)
        if case .updateAndReapply(let next) = plan {
            settings.appID = next.appID
            settings.pipeIndex = next.pipeIndex
            persistSettings()
            engine.update(appID: next.appID, pipeIndex: next.pipeIndex)
        }
        // The editor's Application ID field edits the primary card until the Cards screen owns it.
        if let index = settings.cards.firstIndex(where: { $0.id == primaryCard?.id }) {
            settings.cards[index].applicationID = settings.appID.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.cards[index].isOn = !settings.appID.isEmpty
        }
        PresenceLog.note("reconnect requested (settingsChanged=\(plan.changesSettings))")
        engine.reassert()
        reapply()
    }

    func updateConnection(appID: String, pipeIndex: Int) {
        let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != settings.appID || pipeIndex != settings.pipeIndex else { return }
        settings.appID = trimmed
        settings.pipeIndex = pipeIndex
        persistSettings()
        // The editor's Application ID field edits the primary card until the Cards screen owns it.
        if let index = settings.cards.firstIndex(where: { $0.id == primaryCard?.id }) {
            settings.cards[index].applicationID = trimmed
            settings.cards[index].isOn = !trimmed.isEmpty
        }
        applyCards()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            issues = [ActivityIssue(field: .appID, message: "Could not change login item: \(error.localizedDescription)")]
        }
        // Always report reality, never the requested value.
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func openEditor() {
        // Always rebuild the window: a cached one keeps the draft it loaded when it was first
        // opened, so after the presets file changed on disk the editor still showed the old values
        // (empty image keys) — and pressing Save wrote that stale draft back over the file. That is
        // what looked like "the images rolled back to default".
        let controller = EditorWindowController(model: self)
        editor = controller
        controller.show()
    }

    func openSettings() {
        // Match the editor: always rebuild so file changes and card validation state are fresh.
        let controller = SettingsWindowController(model: self)
        settingsWindow = controller
        controller.show()
    }

    func openDiscord() {
        let url = URL(fileURLWithPath: "/Applications/Discord.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(string: "https://discord.com/download")!)
        }
    }

    // MARK: persistence

    /// Errors are logged rather than swallowed: a user who thinks a preset was saved (but the disk
    /// refused) has no way to find out otherwise. The message never contains secrets.
    /// Manual by design — nothing polls on a timer, so the app keeps making only the network calls
    /// the user triggers. See `UpdateCheck` and SECURITY.md.
    func checkForUpdates() async {
        updateStatus = .checking
        switch await UpdateCheck.fetchLatest() {
        case .upToDate(let current): updateStatus = .upToDate(current)
        case .newer(let version, let url): updateStatus = .available(version, url)
        case .failed(let reason): updateStatus = .failed(reason)
        }
    }

    /// Opens a link in the default browser (the release page, normally).
    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }

    private func persistPresets() {
        do { try store.save(presets: presets) }
        catch { PresenceLog.note("presets save failed: \(error.localizedDescription)") }
    }

    func persistSettings() {
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        do { try store.save(settings: settings) }
        catch { PresenceLog.note("settings save failed: \(error.localizedDescription)") }
    }

    func shutdown() {
        engine.stop()
        persistSettings()
        persistPresets()
    }
}

/// What the menu shows about the last manual update check.
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(String, URL)
    case failed(String)
}
