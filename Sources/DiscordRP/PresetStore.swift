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

/// JSON persistence in `~/Library/Application Support/CustomRPMac/`.
/// A corrupt file is moved aside to `<name>.bak` and replaced by defaults, mirroring
/// CustomRP's corrupt-settings recovery (`Program.cs:128-145`).
public final class PresetStore: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.directory = base.appendingPathComponent("CustomRPMac", isDirectory: true)
        }
    }

    private var presetsURL: URL { directory.appendingPathComponent("presets.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    private static func decoder() -> JSONDecoder { JSONDecoder() }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public func loadPresets() -> [Preset] {
        guard let data = try? Data(contentsOf: presetsURL) else { return [] }
        if let presets = try? Self.decoder().decode([Preset].self, from: data) {
            return presets
        }
        quarantine(presetsURL)
        return []
    }

    public func save(presets: [Preset]) throws {
        try ensureDirectory()
        try Self.encoder().encode(presets).write(to: presetsURL, options: .atomic)
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

    /// Single-file preset import/export (`open -a CustomRP preset.json`).
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
