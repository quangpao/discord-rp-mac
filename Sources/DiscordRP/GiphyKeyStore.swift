import Foundation
import Security

/// Where a user's Giphy API key lives.
///
/// The app is **BYOK** (bring your own key): no key ships with it, none is ever read from the repo,
/// and the user pastes their own. On macOS the right home for a credential is the Keychain, so that
/// is the primary store; `$GIPHY_API_KEY` and the legacy `~/.giphy/api_key` file stay supported for
/// scripted/CLI use.
///
/// The key is never logged, never written into the repo, and never shown back to the user — the UI
/// only reports *which* source supplied it.
public enum GiphyKeySource: String, Sendable {
    case keychain
    case environment
    case file
    case none

    public var description: String {
        switch self {
        case .keychain: "Keychain (saved in this app)"
        case .environment: "$GIPHY_API_KEY"
        case .file: "~/.giphy/api_key"
        case .none: "No key — uploads are disabled"
        }
    }
}

public enum GiphyKeyError: Error, Equatable, CustomStringConvertible {
    case empty
    case looksWrong(String)
    case keychain(OSStatus)

    public var description: String {
        switch self {
        case .empty: "The key is empty."
        case .looksWrong(let why): "That does not look like a Giphy API key (\(why))."
        case .keychain(let status):
            status == errSecUserCanceled
                ? "Keychain access was cancelled."
                : "Keychain error \(status)."
        }
    }
}

/// Swappable so tests (and the CLI) can run without touching the real Keychain.
public protocol GiphyKeyStorage: Sendable {
    func read() -> String?
    func write(_ value: String) throws
    func delete()
}

public struct KeychainGiphyKeyStorage: GiphyKeyStorage {
    public static let service = "dev.quangpao.discordrp.giphy"
    public static let account = "api-key"

    private let service: String
    private let account: String

    /// The service is a parameter so the pre-rename item (`dev.kun.customrp.giphy`) can be read for
    /// the one-time migration.
    public init(service: String = KeychainGiphyKeyStorage.service,
                account: String = KeychainGiphyKeyStorage.account) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    public func write(_ value: String) throws {
        let data = Data(value.utf8)
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let attributes = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else { throw GiphyKeyError.keychain(status) }
        } else {
            var query = self.query
            query[kSecValueData as String] = data
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw GiphyKeyError.keychain(status) }
        }
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

public enum GiphyKeyStore {
    private static let storageLock = NSLock()
    nonisolated(unsafe) private static var backingStorage: GiphyKeyStorage = KeychainGiphyKeyStorage()

    /// Swapped by tests; the app uses the Keychain. Lock-guarded so it is safe under strict
    /// concurrency (a bare `static var` is rejected in Swift 6).
    public static var storage: GiphyKeyStorage {
        get {
            storageLock.lock()
            defer { storageLock.unlock() }
            return backingStorage
        }
        set {
            storageLock.lock()
            defer { storageLock.unlock() }
            backingStorage = newValue
        }
    }

    public static func legacyPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.giphy/api_key"
    }

    /// Keychain first, then the environment, then the legacy file — so a user who saved a key in
    /// the app never has a stale shell variable silently win.
    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        file: String? = nil
    ) -> String? {
        if let stored = normalized(storage.read()) { return stored }
        if let value = normalized(environment["GIPHY_API_KEY"]) { return value }
        let path = file ?? legacyPath()
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return normalized(contents)
    }

    public static func source(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        file: String? = nil
    ) -> GiphyKeySource {
        if normalized(storage.read()) != nil { return .keychain }
        if normalized(environment["GIPHY_API_KEY"]) != nil { return .environment }
        let path = file ?? legacyPath()
        if let contents = try? String(contentsOfFile: path, encoding: .utf8),
           normalized(contents) != nil { return .file }
        return .none
    }

    public static func isConfigured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        file: String? = nil
    ) -> Bool {
        source(environment: environment, file: file) != .none
    }

    /// Stores the user's own key in the Keychain. Validated first so a paste of the wrong thing
    /// fails loudly instead of producing confusing 401s later.
    public static func save(_ key: String) throws {
        guard let value = normalized(key) else { throw GiphyKeyError.empty }
        try validate(value)
        try storage.write(value)
    }

    public static func clear() {
        storage.delete()
    }

    /// Giphy keys are 32-ish alphanumeric characters. Deliberately loose: reject only what is
    /// clearly not a key, so a future key format still works.
    public static func validate(_ key: String) throws {
        guard key.count >= 20 else { throw GiphyKeyError.looksWrong("too short") }
        guard key.count <= 64 else { throw GiphyKeyError.looksWrong("too long") }
        guard !key.contains(" ") else { throw GiphyKeyError.looksWrong("contains a space") }
        guard key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw GiphyKeyError.looksWrong("unexpected characters")
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
