import AppKit
import Combine
import DiscordRP
import SwiftUI

/// Single source of truth for the UI: presets, settings and the presence engine.
@MainActor
final class AppModel: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var settings = AppSettings()
    @Published var status: PresenceStatus = .idle
    @Published var issues: [ActivityIssue] = []
    @Published var launchAtLogin: Bool = false

    let engine: PresenceEngine
    private let store: PresetStore
    private var editor: EditorWindowController?
    /// Held for the app's lifetime: App Nap suspends a menu bar app's timers, which silently killed
    /// the RPC keepalive (measured: pings stopped ~2 minutes after launch, so Discord saw a dead
    /// connection and the activity disappeared). This token keeps the app out of App Nap while
    /// still allowing the system itself to sleep.
    private var activityToken: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(startEngine: Bool = true) {
        let store = PresetStore()
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

        let engine = PresenceEngine(appID: settings.appID, pipeIndex: settings.pipeIndex)

        self.store = store
        self.settings = settings
        self.presets = presets
        self.engine = engine
        self.launchAtLogin = LaunchAtLogin.isEnabled

        engine.$status.assign(to: &$status)
        engine.$issues.assign(to: &$issues)

        if startEngine, !settings.appID.isEmpty {
            engine.start()
        }
        if startEngine, let active = activePreset {
            engine.apply(active.activity)
        }

        guard startEngine else { return }
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
        persistSettings()
        engine.apply(preset.activity)
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
        persistPresets()
        persistSettings()
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
        guard let active = activePreset else { return }
        engine.apply(active.activity)
    }

    // MARK: settings

    func updateConnection(appID: String, pipeIndex: Int) {
        let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != settings.appID || pipeIndex != settings.pipeIndex else { return }
        settings.appID = trimmed
        settings.pipeIndex = pipeIndex
        persistSettings()
        engine.update(appID: trimmed, pipeIndex: pipeIndex)
        if !trimmed.isEmpty { engine.start() }
        reapply()
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

    func openDiscord() {
        let url = URL(fileURLWithPath: "/Applications/Discord.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(string: "https://discord.com/download")!)
        }
    }

    // MARK: persistence

    private func persistPresets() { try? store.save(presets: presets) }

    func persistSettings() {
        settings.launchAtLogin = LaunchAtLogin.isEnabled
        try? store.save(settings: settings)
    }

    func shutdown() {
        engine.stop()
        persistSettings()
        persistPresets()
    }
}
