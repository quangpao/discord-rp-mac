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

public struct PresenceCard: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var presetID: UUID
    public var applicationID: String
    public var isOn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        presetID: UUID,
        applicationID: String,
        isOn: Bool
    ) {
        self.id = id
        self.name = name
        self.presetID = presetID
        self.applicationID = applicationID
        self.isOn = isOn
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 2
    public var pipeIndex: Int = 0
    public var cards: [PresenceCard] = []
    /// Mirror of the real login-item state (SMAppService / LaunchAgent), never optimistic.
    public var launchAtLogin: Bool = false

    /// Legacy compatibility for the unchanged SwiftUI target. These are decoded from v1 files and
    /// mirrored from the first card during migration, but custom encoding never writes them.
    public var appID: String = DefaultApplication.id
    public var activePresetID: UUID?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, pipeIndex, cards, launchAtLogin
        case appID, activePresetID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        pipeIndex = try container.decodeIfPresent(Int.self, forKey: .pipeIndex) ?? 0
        cards = try container.decodeIfPresent([PresenceCard].self, forKey: .cards) ?? []
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? DefaultApplication.id
        activePresetID = try container.decodeIfPresent(UUID.self, forKey: .activePresetID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(pipeIndex, forKey: .pipeIndex)
        try container.encode(cards, forKey: .cards)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }

    public static func migrated(_ decoded: AppSettings, presets: [Preset]) -> AppSettings {
        guard decoded.cards.isEmpty else {
            var settings = decoded
            settings.schemaVersion = 2
            // The shadow fields must mirror what a pre-cards build would have pushed: the first card
            // that is actually ON. With every card off, an old build has to push nothing, which is
            // what the empty application id means.
            let shadow = settings.cards.first(where: { $0.isOn })
            settings.appID = shadow?.applicationID ?? ""
            settings.activePresetID = shadow?.presetID
            return settings
        }

        var settings = decoded
        settings.schemaVersion = 2

        let presetID = decoded.activePresetID ?? presets.first?.id
        guard let presetID else { return settings }

        let finalApplicationID = decoded.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetExists = presets.contains { $0.id == presetID }
        let isOn = presetExists && !finalApplicationID.isEmpty

        let card = PresenceCard(
            name: "Main",
            presetID: presetID,
            applicationID: finalApplicationID,
            isOn: isOn
        )
        settings.cards = [card]
        settings.appID = finalApplicationID
        settings.activePresetID = presetID
        return settings
    }
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
            return AppSettings.migrated(settings, presets: loadPresets())
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
