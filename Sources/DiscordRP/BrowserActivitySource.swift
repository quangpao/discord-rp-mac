import AppKit
import Foundation

public struct BrowserActivityValue: Equatable, Sendable {
    public var domain: String
    public var title: String?
    public var browserName: String
    public var isIncognito: Bool

    public init(domain: String, title: String? = nil, browserName: String, isIncognito: Bool) {
        self.domain = domain
        self.title = title
        self.browserName = browserName
        self.isIncognito = isIncognito
    }
}

public enum BrowserActivityFailure: Equatable, Sendable {
    case unsupportedFrontmostApplication
    case browserNotRunning
    case automationPermissionDenied
    case scriptCompileFailed(String)
    case timeout
    case noFrontWindow
    case unsupportedURL
    case incognito
    case blocked(String)
    case scriptFailed(String)

    public var userMessage: String {
        switch self {
        case .unsupportedFrontmostApplication:
            "Open a supported Chromium browser to use this card."
        case .browserNotRunning:
            "The selected browser is not running."
        case .automationPermissionDenied:
            "Allow Discord RP to control the browser in System Settings > Privacy & Security > Automation."
        case .scriptCompileFailed:
            "Browser reader could not be prepared."
        case .timeout:
            "The browser did not answer quickly enough."
        case .noFrontWindow:
            "The browser has no front window."
        case .unsupportedURL:
            "The focused tab is not a web page."
        case .incognito:
            "Incognito windows are never published."
        case .blocked(let domain):
            "\(domain) is blocked."
        case .scriptFailed(let message):
            message.isEmpty ? "The browser tab could not be read." : message
        }
    }
}

public enum BrowserActivityReadResult: Equatable, Sendable {
    case value(BrowserActivityValue)
    case failure(BrowserActivityFailure)
}

public struct SupportedBrowser: Equatable, Sendable {
    public var bundleIdentifier: String
    public var applicationName: String
    public var displayName: String

    public init(bundleIdentifier: String, applicationName: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.displayName = displayName
    }
}

public protocol FrontmostApplicationProviding: Sendable {
    func frontmostBundleIdentifier() -> String?
}

public struct WorkspaceFrontmostApplicationProvider: FrontmostApplicationProviding {
    public init() {}

    public func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

public protocol BrowserActivityReading: Sendable {
    func read(includeTitle: Bool, timeout: TimeInterval, completion: @escaping @Sendable (BrowserActivityReadResult) -> Void)
}

public final class BrowserActivitySource: BrowserActivityReading, @unchecked Sendable {
    public static let supportedBrowsers: [SupportedBrowser] = [
        SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome"),
        SupportedBrowser(bundleIdentifier: "com.brave.Browser", applicationName: "Brave Browser", displayName: "Brave"),
        SupportedBrowser(bundleIdentifier: "com.microsoft.edgemac", applicationName: "Microsoft Edge", displayName: "Microsoft Edge"),
        SupportedBrowser(bundleIdentifier: "com.vivaldi.Vivaldi", applicationName: "Vivaldi", displayName: "Vivaldi"),
        SupportedBrowser(bundleIdentifier: "org.chromium.Chromium", applicationName: "Chromium", displayName: "Chromium"),
    ]

    private let frontmostProvider: FrontmostApplicationProviding
    private let queue = DispatchQueue(label: "dev.quangpao.discordrp.browser-source", qos: .utility)
    private var scripts: [ScriptKey: NSAppleScript] = [:]
    private var compileFailures: [String: BrowserActivityFailure] = [:]

    public init(frontmostProvider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider()) {
        self.frontmostProvider = frontmostProvider
    }

    public static func frontmostSupportedBrowser(using provider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider()) -> SupportedBrowser? {
        guard let bundleIdentifier = provider.frontmostBundleIdentifier() else { return nil }
        return supportedBrowsers.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public static func domain(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    public static func isBlocked(domain: String, by patterns: [String]) -> Bool {
        let normalizedDomain = domain.lowercased()
        for rawPattern in patterns {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !pattern.isEmpty else { continue }
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(2))
                if normalizedDomain == suffix || normalizedDomain.hasSuffix("." + suffix) {
                    return true
                }
            } else if normalizedDomain == pattern {
                return true
            }
        }
        return false
    }

    public func read(includeTitle: Bool, timeout: TimeInterval = 0.35,
                     completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        guard let browser = Self.frontmostSupportedBrowser(using: frontmostProvider) else {
            completion(.failure(.unsupportedFrontmostApplication))
            return
        }
        let box = CompletionBox(completion)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let key = ScriptKey(bundleIdentifier: browser.bundleIdentifier, includeTitle: includeTitle)
            if let failure = self.compileFailures[browser.bundleIdentifier] {
                box.deliver(.failure(failure))
                return
            }
            guard let script = self.scripts[key] ?? self.compileScript(for: browser, includeTitle: includeTitle) else {
                box.deliver(.failure(self.compileFailures[browser.bundleIdentifier]
                                     ?? .scriptCompileFailed("No compiled script for \(browser.displayName).")))
                return
            }
            let result = self.execute(script: script, browser: browser, includeTitle: includeTitle)
            box.deliver(result)
        }
        queue.async(execute: work)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            box.deliver(.failure(.timeout))
        }
    }

    private func compileScript(for browser: SupportedBrowser, includeTitle: Bool) -> NSAppleScript? {
        let key = ScriptKey(bundleIdentifier: browser.bundleIdentifier, includeTitle: includeTitle)
        var error: NSDictionary?
        let script = NSAppleScript(source: Self.scriptSource(for: browser.applicationName, includeTitle: includeTitle))
        guard script?.compileAndReturnError(&error) == true, let script else {
            compileFailures[browser.bundleIdentifier] = .scriptCompileFailed(Self.errorDescription(error))
            return nil
        }
        scripts[key] = script
        return script
    }

    private func execute(script: NSAppleScript,
                         browser: SupportedBrowser,
                         includeTitle: Bool) -> BrowserActivityReadResult {
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let failure = Self.failure(from: error) {
            return .failure(failure)
        }
        guard descriptor.numberOfItems >= 3 else {
            return .failure(.scriptFailed("Unexpected browser reply."))
        }

        let url = descriptor.atIndex(1)?.stringValue ?? ""
        let title = descriptor.atIndex(2)?.stringValue ?? ""
        let mode = descriptor.atIndex(3)?.stringValue?.lowercased() ?? ""
        guard !mode.contains("incognito") else {
            return .failure(.incognito)
        }
        guard let domain = Self.domain(from: url) else {
            return .failure(.unsupportedURL)
        }
        return .value(BrowserActivityValue(
            domain: domain,
            title: includeTitle ? title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            browserName: browser.displayName,
            isIncognito: false
        ))
    }

    public static func compileCheck() -> [BrowserActivityFailure] {
        [supportedBrowsers[0]].compactMap { browser in
            var error: NSDictionary?
            let script = NSAppleScript(source: scriptSource(for: browser.applicationName, includeTitle: true))
            return script?.compileAndReturnError(&error) == true ? nil : .scriptCompileFailed(errorDescription(error))
        }
    }

    private static func scriptSource(for applicationName: String, includeTitle: Bool) -> String {
        let escaped = applicationName.replacingOccurrences(of: "\"", with: "\\\"")
        let titleLine = includeTitle ? "set tabTitle to «property pnam» of frontTab as text" : "set tabTitle to \"\""
        return """
        tell application "\(escaped)"
            try
                set frontTab to «property acTa» of front window
                set tabURL to «property URL » of frontTab as text
                \(titleLine)
                set windowMode to «property mode» of front window as text
                return {tabURL, tabTitle, windowMode}
            on error errMsg number errNum
                error errMsg number errNum
            end try
        end tell
        """
    }

    private static func failure(from error: NSDictionary?) -> BrowserActivityFailure? {
        guard let error else { return nil }
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = errorDescription(error)
        switch number {
        case -1743:
            return .automationPermissionDenied
        case -600, -609:
            return .browserNotRunning
        case -1728:
            return .noFrontWindow
        default:
            return .scriptFailed(message)
        }
    }

    private static func errorDescription(_ error: NSDictionary?) -> String {
        guard let error else { return "Unknown AppleScript error." }
        let message = error[NSAppleScript.errorMessage] as? String
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        if let message, let number {
            return "\(message) (\(number))"
        }
        return message ?? "Unknown AppleScript error."
    }
}

private struct ScriptKey: Hashable {
    var bundleIdentifier: String
    var includeTitle: Bool
}

private final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (BrowserActivityReadResult) -> Void)?

    init(_ completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        self.completion = completion
    }

    func deliver(_ result: BrowserActivityReadResult) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
