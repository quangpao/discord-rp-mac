import Foundation

/// One-time move from the pre-rename layout.
///
/// The app used to be `CustomRP` / `customrp-mac` with bundle id `dev.kun.customrp`; it is now
/// **Discord RP** (`dev.quangpao.discordrp`), so its Application Support folder and its Keychain
/// service both moved. Files are **copied, never deleted** — if anything goes wrong the old ones are
/// still there, and the new copy is never allowed to overwrite an existing file.
public enum Migration {
    public static let legacyDataDirectoryName = "CustomRPMac"
    public static let currentDataDirectoryName = "DiscordRPMac"
    public static let legacyKeychainService = "dev.kun.customrp.giphy"
    public static let migratedFileNames = ["presets.json", "settings.json", "giphy-uploads.json"]

    public static func runIfNeeded(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil,
        storage: GiphyKeyStorage? = nil
    ) {
        migrateDataDirectory(fileManager: fileManager, supportDirectory: supportDirectory)
        migrateKeychain(target: storage)
    }

    /// Copies the old JSON files into the new folder, one by one, only when the destination is
    /// missing. Idempotent: running it twice changes nothing.
    @discardableResult
    public static func migrateDataDirectory(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) -> [String] {
        let base = supportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return [] }
        let legacy = base.appendingPathComponent(legacyDataDirectoryName, isDirectory: true)
        let current = base.appendingPathComponent(currentDataDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return [] }
        try? fileManager.createDirectory(at: current, withIntermediateDirectories: true)

        var copied: [String] = []
        for name in migratedFileNames {
            let source = legacy.appendingPathComponent(name)
            let destination = current.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path) else { continue }
            if (try? fileManager.copyItem(at: source, to: destination)) != nil {
                copied.append(name)
            }
        }
        return copied
    }

    /// What the key migration did, for diagnostics (`--giphy-key migrate`).
    public enum KeyMigrationOutcome: String, Sendable {
        case alreadyPresent
        case movedFromLegacyKeychain
        case seededFromLegacyFile
        case nothingToMigrate
    }

    /// Gets the key into the new Keychain service.
    ///
    /// Order matters: a key created by the **previous app** may be unreadable to this build (macOS
    /// ties a generic-password item to the app that created it, and an ad-hoc-signed bundle cannot
    /// prompt its way out of that), so when the legacy item cannot be read we fall back to the file
    /// the old version documented (`~/.giphy/api_key`) and seed the Keychain from it. The file is
    /// left in place — it may belong to other tooling.
    @discardableResult
    public static func migrateKeychain(
        target: GiphyKeyStorage? = nil,
        legacy: GiphyKeyStorage? = nil,
        legacyFilePath: String? = nil
    ) -> KeyMigrationOutcome {
        let target = target ?? GiphyKeyStore.storage
        guard target.read() == nil else { return .alreadyPresent }

        let legacy = legacy ?? KeychainGiphyKeyStorage(service: legacyKeychainService)
        if let key = legacy.read() {
            try? target.write(key)
            if target.read() != nil {
                legacy.delete()
                return .movedFromLegacyKeychain
            }
        }

        let path = legacyFilePath ?? GiphyKeyStore.legacyPath()
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, (try? target.write(trimmed)) != nil, target.read() != nil {
                return .seededFromLegacyFile
            }
        }
        return .nothingToMigrate
    }
}
