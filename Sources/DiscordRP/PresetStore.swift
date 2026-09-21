import Foundation

public struct Preset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var activity: Activity

    public init(id: UUID = UUID(), name: String, activity: Activity) {
        self.id = id
        self.name = name
        self.activity = activity
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appID: String = ""
    public var pipeIndex: Int = 0
    public var activePresetID: UUID?
    /// Mirror of the real login-item state (SMAppService / LaunchAgent), never optimistic.
    public var launchAtLogin: Bool = false

    public init() {}
}

/// JSON persistence in `~/Library/Application Support/DiscordRPMac/`.
/// A corrupt file is moved aside to `<name>.bak` and replaced by defaults, so one bad write
/// cannot leave the app unusable.
public final class PresetStore: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.directory = base.appendingPathComponent("DiscordRPMac", isDirectory: true)
        }
    }

    private var presetsURL: URL { directory.appendingPathComponent("presets.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    /// Dates are pinned to **epoch milliseconds** in the JSON — the same unit Discord uses on the
    /// wire and the same unit `scripts/seed-demo-presets.py` writes. Swift's default `Date`
    /// Codable representation is seconds since 2001, which silently reinterpreted hand-written
    /// timestamps as 1970/2057; never let that default back in.
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public func loadPresets() -> [Preset] {
        guard let data = try? Data(contentsOf: presetsURL) else { return [] }
        if let presets = try? Self.decoder().decode([Preset].self, from: data) {
            return Self.normalized(presets)
        }
        quarantine(presetsURL)
        return []
    }

    public func save(presets: [Preset]) throws {
        try ensureDirectory()
        try Self.encoder().encode(Self.normalized(presets)).write(to: presetsURL, options: .atomic)
    }

    /// Storage keeps epoch milliseconds, so dates are snapped to that precision on both sides —
    /// a hand-written preset file cannot introduce a sub-millisecond mismatch either.
    private static func normalized(_ presets: [Preset]) -> [Preset] {
        presets.map { preset in
            var preset = preset
            preset.activity.customStart = ActivityRules.millisecondPrecision(preset.activity.customStart)
            preset.activity.customEnd = ActivityRules.millisecondPrecision(preset.activity.customEnd)
            return preset
        }
    }

    public func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        if let settings = try? Self.decoder().decode(AppSettings.self, from: data) {
            return settings
        }
        quarantine(settingsURL)
        return AppSettings()
    }

    public func save(settings: AppSettings) throws {
        try ensureDirectory()
        try Self.encoder().encode(settings).write(to: settingsURL, options: .atomic)
    }

    /// Single-file preset import/export (`open -a "Discord RP" preset.json`).
    public func exportPreset(_ preset: Preset, to url: URL) throws {
        try Self.encoder().encode(preset).write(to: url, options: .atomic)
    }

    public func importPreset(from url: URL) throws -> Preset {
        let data = try Data(contentsOf: url)
        return try Self.decoder().decode(Preset.self, from: data)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func quarantine(_ url: URL) {
        let backup = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
