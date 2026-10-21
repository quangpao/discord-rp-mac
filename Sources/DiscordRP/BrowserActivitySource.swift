import AppKit
import Foundation

public struct BrowserActivityValue: Equatable, Sendable {
    public var domain: String
    public var title: String?
    public var browserName: String
    public var isIncognito: Bool
    /// Which browser produced this value, so the card can show that browser's own icon. Optional so
    /// existing callers and fixtures keep compiling.
    public var browserBundleIdentifier: String?

    public init(domain: String, title: String? = nil, browserName: String, isIncognito: Bool,
                browserBundleIdentifier: String? = nil) {
        self.domain = domain
        self.title = title
        self.browserName = browserName
        self.isIncognito = isIncognito
    }
}

public func browserSiteIconURL(forDomain domain: String) -> String {
    "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
}

public enum BrowserActivityFailure: Equatable, Error, Sendable {
    case browserNotFrontmost
    case browserNotRunning
    case automationPermissionDenied
    case scriptCompileFailed(String)
    case timeout
    case noFrontWindow
    case unsupportedURL
    case couldNotReadURL(String)
    case incognito
    case incognitoUnknown
    case blocked(String)
    case scriptFailed(String)

    public var userMessage: String {
        switch self {
        case .browserNotFrontmost:
            "The browser is not frontmost."
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
            "The tab is not a web page."
        case .couldNotReadURL:
            "Could not read the URL from the focused tab."
        case .incognito:
            "Incognito windows are never published."
        case .incognitoUnknown:
            "Browser privacy mode could not be determined."
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

private enum BrowserReadScriptKind: Equatable {
    case urlOnly
    case urlAndTitle
    case urlAndMode
    case urlAndModeRaw
    case urlTitleAndMode
    case modeRawOnly(timeout: TimeInterval)
    case modeStringOnly(timeout: TimeInterval)
    case titleOnly(timeout: TimeInterval)
}

enum BrowserWindowMode: String, Equatable, Sendable {
    case normal
    case incognito

    private static let normalEnumCodes: Set<DescType> = [
        fourCharacterCode("norm"),
    ]

    private static let incognitoEnumCodes: Set<DescType> = [
        fourCharacterCode("incg"),
        fourCharacterCode("inca"),
        fourCharacterCode("prvt"),
    ]

    static func from(text: String?) -> BrowserWindowMode? {
        guard let text else { return nil }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "normal":
            return .normal
        case "incognito":
            return .incognito
        default:
            return nil
        }
    }

    static func from(enumCode: DescType) -> BrowserWindowMode? {
        if normalEnumCodes.contains(enumCode) { return .normal }
        if incognitoEnumCodes.contains(enumCode) { return .incognito }
        return nil
    }

    static func from(descriptor: NSAppleEventDescriptor?) -> BrowserWindowMode? {
        guard let descriptor else { return nil }
        if let mode = from(text: descriptor.stringValue) {
            return mode
        }
        return from(enumCode: descriptor.enumCodeValue)
    }

    static func fourCharacterCode(_ string: String) -> DescType {
        precondition(string.utf8.count == 4)
        return string.utf8.reduce(DescType(0)) { ($0 << 8) | DescType($1) }
    }
}

public struct BrowserActivityPublicationState: Equatable, Sendable {
    public private(set) var latestReadResult: BrowserActivityReadResult?
    public private(set) var publishedValue: BrowserActivityValue?

    public init() {}

    public var publishedReadResult: BrowserActivityReadResult? {
        publishedValue.map(BrowserActivityReadResult.value)
    }

    public mutating func record(_ result: BrowserActivityReadResult) {
        latestReadResult = result
        if case .value(let value) = result, !value.isIncognito {
            publishedValue = value
        }
    }

    public mutating func clear() {
        latestReadResult = nil
        publishedValue = nil
    }
}

public final class BrowserActivitySource: BrowserActivityReading, @unchecked Sendable {
    public static let supportedBrowsers: [SupportedBrowser] = [
        SupportedBrowser(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", displayName: "Google Chrome"),
        SupportedBrowser(bundleIdentifier: "com.brave.Browser", applicationName: "Brave Browser", displayName: "Brave"),
        SupportedBrowser(bundleIdentifier: "com.microsoft.edgemac", applicationName: "Microsoft Edge", displayName: "Microsoft Edge"),
        SupportedBrowser(bundleIdentifier: "com.vivaldi.Vivaldi", applicationName: "Vivaldi", displayName: "Vivaldi"),
        SupportedBrowser(bundleIdentifier: "org.chromium.Chromium", applicationName: "Chromium", displayName: "Chromium"),
    ]

    /// The browser's own icon, used as the small image on a browser-sourced card. Two sources, both
    /// verified to serve a PNG that Discord's asset proxy can fetch: Wikimedia's PNG thumbnails for the
    /// browsers whose logos live there, and the vendor's own domain through the favicon service for the
    /// rest. Neither source learns which page the user is reading — only which browser is in front.
    public static func browserIconURL(forBundleIdentifier bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Google_Chrome_icon_%28February_2022%29.svg/120px-Google_Chrome_icon_%28February_2022%29.svg.png"
        case "com.microsoft.edgemac":
            return "https://upload.wikimedia.org/wikipedia/commons/thumb/9/98/Microsoft_Edge_logo_%282019%29.svg/120px-Microsoft_Edge_logo_%282019%29.svg.png"
        case "com.brave.Browser":
            return "https://www.google.com/s2/favicons?domain=brave.com&sz=64"
        case "com.vivaldi.Vivaldi":
            return "https://www.google.com/s2/favicons?domain=vivaldi.com&sz=64"
        case "org.chromium.Chromium":
            return "https://www.google.com/s2/favicons?domain=chromium.org&sz=64"
        default:
            return nil
        }
    }

    private let frontmostProvider: FrontmostApplicationProviding
    private let scriptWorker: AppleScriptRunLoopWorker
    private var compileFailures: [String: BrowserActivityFailure] = [:]

    public init(frontmostProvider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider()) {
        self.frontmostProvider = frontmostProvider
        self.scriptWorker = .shared
    }

    public static func frontmostSupportedBrowser(using provider: FrontmostApplicationProviding = WorkspaceFrontmostApplicationProvider()) -> SupportedBrowser? {
        guard let bundleIdentifier = provider.frontmostBundleIdentifier() else { return nil }
        return supportedBrowser(bundleIdentifier: bundleIdentifier)
    }

    public static func supportedBrowser(bundleIdentifier: String) -> SupportedBrowser? {
        return supportedBrowsers.first { $0.bundleIdentifier == bundleIdentifier }
    }

    static func browserForRead(browserBundleIdentifierOverride: String?,
                               using provider: FrontmostApplicationProviding) -> Result<SupportedBrowser, BrowserActivityFailure> {
        if let browserBundleIdentifierOverride {
            guard let selectedBrowser = supportedBrowser(bundleIdentifier: browserBundleIdentifierOverride) else {
                return .failure(.browserNotRunning)
            }
            return .success(selectedBrowser)
        }
        guard let frontmostBrowser = frontmostSupportedBrowser(using: provider) else {
            return .failure(.browserNotFrontmost)
        }
        return .success(frontmostBrowser)
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

    public func read(includeTitle: Bool, timeout: TimeInterval = 3.0,
                     completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        read(includeTitle: includeTitle, timeout: timeout, browserBundleIdentifierOverride: nil, completion: completion)
    }

    public func read(includeTitle: Bool, timeout: TimeInterval = 3.0,
                     browserBundleIdentifierOverride: String?,
                     completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        read(includeTitle: includeTitle,
             timeout: timeout,
             browserBundleIdentifierOverride: browserBundleIdentifierOverride,
             diagnostics: nil,
             completion: completion)
    }

    public func diagnosticRead(includeTitle: Bool, timeout: TimeInterval = 3.0,
                               browserBundleIdentifierOverride: String?,
                               diagnostics: @escaping @Sendable (String) -> Void,
                               completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        read(includeTitle: includeTitle,
             timeout: timeout,
             browserBundleIdentifierOverride: browserBundleIdentifierOverride,
             diagnostics: diagnostics,
             measureParts: true,
             completion: completion)
    }

    private func read(includeTitle: Bool,
                      timeout: TimeInterval,
                      browserBundleIdentifierOverride: String?,
                      diagnostics: (@Sendable (String) -> Void)?,
                      measureParts: Bool = false,
                      completion: @escaping @Sendable (BrowserActivityReadResult) -> Void) {
        let browser: SupportedBrowser
        switch Self.browserForRead(browserBundleIdentifierOverride: browserBundleIdentifierOverride, using: frontmostProvider) {
        case .success(let selectedBrowser):
            browser = selectedBrowser
            diagnostics?("selected browser: \(browser.displayName) (\(browser.bundleIdentifier))")
        case .failure(let failure):
            diagnostics?("browser selection failed: \(failure)")
            completion(.failure(failure))
            return
        }
        let box = CompletionBox(completion)
        scriptWorker.async { [weak self] in
            guard let self else { return }
            if let failure = self.compileFailures[browser.bundleIdentifier] {
                diagnostics?("compile skipped: cached failure \(failure)")
                box.deliver(.failure(failure))
                return
            }
            diagnostics?("script worker thread has run loop: \(RunLoop.current.currentMode != nil)")
            if measureParts {
                self.reportDiagnosticPartTimings(for: browser, diagnostics: diagnostics)
            }
            guard let script = self.compileScript(for: browser, kind: .urlOnly, diagnostics: diagnostics) else {
                box.deliver(.failure(self.compileFailures[browser.bundleIdentifier]
                                     ?? .scriptCompileFailed("No compiled script for \(browser.displayName).")))
                return
            }
            let urlResult = self.executeURLOnly(script: script, diagnostics: diagnostics)
            guard case .success(let url) = urlResult else {
                box.deliver(.failure(urlResult.failure ?? .couldNotReadURL("Unexpected browser reply.")))
                return
            }
            self.readModeIfAvailable(for: browser, diagnostics: diagnostics) { modeResult in
                let result: BrowserActivityReadResult
                switch modeResult {
                case .success(let mode):
                    result = Self.result(fromDecodedURL: url, title: nil, mode: mode, includeTitle: false, browser: browser)
                case .failure(let failure):
                    result = .failure(failure)
                }
                guard includeTitle, case .value(let value) = result else {
                    box.deliver(result)
                    return
                }
                self.readTitleIfAvailable(for: browser, value: value, diagnostics: diagnostics, completion: box)
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            diagnostics?("read timeout fired after \(String(format: "%.3f", timeout))s")
            box.deliver(.failure(.timeout))
        }
    }

    private func compileScript(for browser: SupportedBrowser,
                               kind: BrowserReadScriptKind,
                               appleEventTimeout: TimeInterval? = nil,
                               diagnostics: (@Sendable (String) -> Void)?) -> NSAppleScript? {
        var error: NSDictionary?
        let source = Self.scriptSource(for: browser, kind: kind, appleEventTimeout: appleEventTimeout)
        diagnostics?("script source:\n\(source)")
        diagnostics?("compile started")
        let script = NSAppleScript(source: source)
        guard script?.compileAndReturnError(&error) == true, let script else {
            diagnostics?("compile failed")
            diagnostics?("AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
            if kind == .urlAndMode {
                compileFailures[browser.bundleIdentifier] = .scriptCompileFailed(Self.errorDescription(error))
            }
            return nil
        }
        diagnostics?("compile finished: success")
        return script
    }

    private func executeURLOnly(script: NSAppleScript,
                                diagnostics: (@Sendable (String) -> Void)?) -> Result<String, BrowserActivityFailure> {
        var error: NSDictionary?
        diagnostics?("url execution started")
        let descriptor = script.executeAndReturnError(&error)
        diagnostics?("url execution finished")
        diagnostics?("url descriptor: \(Self.diagnosticDescriptorDescription(descriptor))")
        if error != nil {
            diagnostics?("url AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
        }
        if let failure = Self.failure(from: error) {
            return .failure(failure)
        }
        guard descriptor.numberOfItems >= 1,
              let url = descriptor.atIndex(1)?.stringValue else {
            return .failure(.couldNotReadURL("Unexpected browser reply."))
        }
        return .success(url)
    }

    private func readModeIfAvailable(for browser: SupportedBrowser,
                                     diagnostics: (@Sendable (String) -> Void)?,
                                     completion: @escaping @Sendable (Result<BrowserWindowMode, BrowserActivityFailure>) -> Void) {
        let modeTimeout: TimeInterval = 1.0
        guard let script = compileScript(for: browser, kind: .modeRawOnly(timeout: modeTimeout), diagnostics: diagnostics) else {
            completion(.failure(.incognitoUnknown))
            return
        }
        let modeBox = ModeCompletionBox(completion)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + modeTimeout) {
            diagnostics?("mode timeout fired after \(String(format: "%.3f", modeTimeout))s")
            modeBox.deliver(.failure(.incognitoUnknown))
        }
        var error: NSDictionary?
        diagnostics?("mode execution started")
        let descriptor = script.executeAndReturnError(&error)
        diagnostics?("mode execution finished")
        diagnostics?("mode descriptor: \(Self.diagnosticDescriptorDescription(descriptor))")
        if error != nil {
            diagnostics?("mode AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
        }
        if let failure = Self.failure(from: error) {
            modeBox.deliver(.failure(failure == .timeout ? .incognitoUnknown : failure))
            return
        }
        guard let mode = BrowserWindowMode.from(descriptor: descriptor) else {
            modeBox.deliver(.failure(.incognitoUnknown))
            return
        }
        modeBox.deliver(.success(mode))
    }

    private func executeURLAndMode(script: NSAppleScript,
                                   browser: SupportedBrowser,
                                   diagnostics: (@Sendable (String) -> Void)?) -> BrowserActivityReadResult {
        var error: NSDictionary?
        diagnostics?("url + mode execution started")
        let descriptor = script.executeAndReturnError(&error)
        diagnostics?("url + mode execution finished")
        diagnostics?("returned descriptor: \(Self.diagnosticDescriptorDescription(descriptor))")
        if error != nil {
            diagnostics?("AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
        }
        if let failure = Self.failure(from: error) {
            return .failure(failure)
        }
        guard descriptor.numberOfItems >= 2,
              let url = descriptor.atIndex(1)?.stringValue else {
            return .failure(.couldNotReadURL("Unexpected browser reply."))
        }

        let mode = BrowserWindowMode.from(descriptor: descriptor.atIndex(2))
        return Self.result(fromDecodedURL: url, title: nil, mode: mode, includeTitle: false, browser: browser)
    }

    private func readTitleIfAvailable(for browser: SupportedBrowser,
                                      value: BrowserActivityValue,
                                      diagnostics: (@Sendable (String) -> Void)?,
                                      completion box: CompletionBox) {
        let titleTimeout: TimeInterval = 1.0
        guard let script = compileScript(for: browser, kind: .titleOnly(timeout: titleTimeout), diagnostics: diagnostics) else {
            box.deliver(.value(value))
            return
        }
        let titleBox = CompletionBox { result in
            switch result {
            case .value(let titledValue):
                box.deliver(.value(titledValue))
            case .failure:
                box.deliver(.value(value))
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + titleTimeout) {
            diagnostics?("title timeout fired after \(String(format: "%.3f", titleTimeout))s")
            titleBox.deliver(.value(value))
        }
        var error: NSDictionary?
        diagnostics?("title execution started")
        let descriptor = script.executeAndReturnError(&error)
        diagnostics?("title execution finished")
        diagnostics?("title descriptor: \(Self.diagnosticDescriptorDescription(descriptor))")
        if error != nil {
            diagnostics?("title AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
        }
        guard Self.failure(from: error) == nil else {
            titleBox.deliver(.value(value))
            return
        }
        let title = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        titleBox.deliver(.value(BrowserActivityValue(
            domain: value.domain,
            title: title,
            browserName: value.browserName,
            isIncognito: value.isIncognito,
            browserBundleIdentifier: value.browserBundleIdentifier
            )))
    }

    private func reportDiagnosticPartTimings(for browser: SupportedBrowser,
                                             diagnostics: (@Sendable (String) -> Void)?) {
        diagnostics?("diagnostic timings started")
        let probeTimeout: TimeInterval = 3.0
        let probes: [(String, BrowserReadScriptKind)] = [
            ("url", .urlOnly),
            ("url + title", .urlAndTitle),
            ("url + raw mode", .urlAndModeRaw),
            ("url + title + mode", .urlTitleAndMode),
            ("raw mode only, separate 1s event", .modeRawOnly(timeout: 1.0)),
            ("text mode only, separate 1s event", .modeStringOnly(timeout: 1.0)),
        ]
        for (label, kind) in probes {
            guard let script = compileScript(for: browser,
                                             kind: kind,
                                             appleEventTimeout: probeTimeout,
                                             diagnostics: diagnostics) else {
                diagnostics?("diagnostic \(label): compile failed")
                continue
            }
            var error: NSDictionary?
            let startedAt = Date()
            diagnostics?("diagnostic \(label): execution started")
            let descriptor = script.executeAndReturnError(&error)
            let duration = Date().timeIntervalSince(startedAt)
            diagnostics?("diagnostic \(label): execution finished in \(String(format: "%.3f", duration))s")
            diagnostics?("diagnostic \(label): descriptor \(Self.diagnosticDescriptorDescription(descriptor))")
            if error != nil {
                diagnostics?("diagnostic \(label): AppleScript error dictionary: \(Self.diagnosticErrorDescription(error))")
            }
        }
        diagnostics?("diagnostic timings finished")
    }

    static func result(fromDecodedURL url: String?,
                       title: String?,
                       mode: String?,
                       includeTitle: Bool,
                       browser: SupportedBrowser) -> BrowserActivityReadResult {
        result(fromDecodedURL: url,
               title: title,
               mode: BrowserWindowMode.from(text: mode),
               includeTitle: includeTitle,
               browser: browser)
    }

    static func result(fromDecodedURL url: String?,
                       title: String?,
                       mode: BrowserWindowMode?,
                       includeTitle: Bool,
                       browser: SupportedBrowser) -> BrowserActivityReadResult {
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.couldNotReadURL("Browser reply did not include a URL."))
        }
        guard let mode else {
            return .failure(.incognitoUnknown)
        }
        guard mode != .incognito else {
            return .failure(.incognito)
        }
        guard let domain = Self.domain(from: url) else {
            return .failure(.unsupportedURL)
        }
        return .value(BrowserActivityValue(
            domain: domain,
            title: includeTitle ? title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            browserName: browser.displayName,
            isIncognito: false,
            browserBundleIdentifier: browser.bundleIdentifier
        ))
    }

    public static func compileCheck() -> [BrowserActivityFailure] {
        [supportedBrowsers[0]].compactMap { browser in
            var error: NSDictionary?
            let source: String
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil {
                source = scriptSource(for: browser, kind: .modeRawOnly(timeout: 1.0))
            } else {
                source = syntaxCheckScriptSource(includeTitle: true)
            }
            let script = NSAppleScript(source: source)
            return script?.compileAndReturnError(&error) == true ? nil : .scriptCompileFailed(errorDescription(error))
        }
    }

    static func scriptSource(for browser: SupportedBrowser, includeTitle: Bool) -> String {
        scriptSource(for: browser, kind: includeTitle ? .urlAndTitle : .urlOnly)
    }

    private static func scriptSource(for browser: SupportedBrowser,
                                     kind: BrowserReadScriptKind,
                                     appleEventTimeout: TimeInterval? = nil) -> String {
        let escaped = browser.bundleIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
        let body: String
        switch kind {
        case .urlOnly:
            body = """
                    set frontTab to active tab of front window
                    set tabURL to URL of frontTab as text
                    return {tabURL}
            """
        case .urlAndTitle:
            body = """
                    set frontTab to active tab of front window
                    set tabURL to URL of frontTab as text
                    set tabTitle to name of frontTab as text
                    return {tabURL, tabTitle}
            """
        case .urlAndMode:
            body = """
                    set frontTab to active tab of front window
                    set tabURL to URL of frontTab as text
                    set windowMode to mode of front window as text
                    return {tabURL, windowMode}
            """
        case .urlAndModeRaw:
            body = """
                    set frontTab to active tab of front window
                    set tabURL to URL of frontTab as text
                    set windowMode to mode of front window
                    return {tabURL, windowMode}
            """
        case .urlTitleAndMode:
            body = """
                    set frontTab to active tab of front window
                    set tabURL to URL of frontTab as text
                    set tabTitle to name of frontTab as text
                    set windowMode to mode of front window
                    return {tabURL, tabTitle, windowMode}
            """
        case .modeRawOnly(let timeout):
            body = """
                    with timeout of \(max(1, Int(ceil(timeout)))) seconds
                        return mode of front window
                    end timeout
            """
        case .modeStringOnly(let timeout):
            body = """
                    with timeout of \(max(1, Int(ceil(timeout)))) seconds
                        return mode of front window as text
                    end timeout
            """
        case .titleOnly(let timeout):
            body = """
                    with timeout of \(max(1, Int(ceil(timeout)))) seconds
                        set frontTab to active tab of front window
                        return name of frontTab as text
                    end timeout
            """
        }
        let timedBody: String
        if let appleEventTimeout {
            timedBody = [
                "        with timeout of \(max(1, Int(ceil(appleEventTimeout)))) seconds",
                body,
                "        end timeout",
            ].joined(separator: "\n")
        } else {
            timedBody = body
        }
        return """
        tell application id "\(escaped)"
            try
        \(timedBody)
            on error errMsg number errNum
                error errMsg number errNum
            end try
        end tell
        """
    }

    private static func syntaxCheckScriptSource(includeTitle: Bool) -> String {
        let titleLine = includeTitle ? "set tabTitle to name of frontTab as text" : "set tabTitle to \"\""
        return """
        set frontTab to {URL:"https://example.com", name:"Example"}
        set frontWindow to {mode:"normal"}
        set tabURL to URL of frontTab as text
        \(titleLine)
        set windowMode to mode of frontWindow as text
        return {tabURL, tabTitle, windowMode}
        """
    }

    static func failure(from error: NSDictionary?) -> BrowserActivityFailure? {
        guard let error else { return nil }
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = errorDescription(error)
        switch number {
        case -1743:
            return .automationPermissionDenied
        case -1712:
            return .timeout
        case -600, -609:
            return .browserNotRunning
        case -1728:
            return .noFrontWindow
        default:
            return .couldNotReadURL(message)
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

    private static func diagnosticErrorDescription(_ error: NSDictionary?) -> String {
        guard let error else { return "nil" }
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let message = error[NSAppleScript.errorMessage] as? String
        return "number=\(number.map(String.init) ?? "nil"), message=\(message ?? "nil"), raw=\(error)"
    }

    private static func diagnosticDescriptorDescription(_ descriptor: NSAppleEventDescriptor) -> String {
        var items: [String] = []
        if descriptor.numberOfItems > 0 {
            for index in 1...descriptor.numberOfItems {
                guard let item = descriptor.atIndex(index) else { continue }
                items.append("#\(index){type=\(fourCharacterCode(item.descriptorType)), enum=\(fourCharacterCode(item.enumCodeValue)), string=\(redactedDiagnosticString(item.stringValue))}")
            }
        }
        return "type=\(fourCharacterCode(descriptor.descriptorType)), enum=\(fourCharacterCode(descriptor.enumCodeValue)), items=\(descriptor.numberOfItems), string=\(redactedDiagnosticString(descriptor.stringValue)), itemDetails=[\(items.joined(separator: ", "))]"
    }

    private static func redactedDiagnosticString(_ string: String?) -> String {
        guard let string else { return "nil" }
        guard let domain = domain(from: string) else { return string }
        return "https://\(domain)/"
    }

    private static func fourCharacterCode(_ code: DescType) -> String {
        let scalars = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        if scalars.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return "'" + String(bytes: scalars, encoding: .macOSRoman)! + "'"
        }
        return String(format: "0x%08x", code)
    }
}

private extension Result where Failure == BrowserActivityFailure {
    var failure: BrowserActivityFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
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

private final class ModeCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<BrowserWindowMode, BrowserActivityFailure>) -> Void)?

    init(_ completion: @escaping @Sendable (Result<BrowserWindowMode, BrowserActivityFailure>) -> Void) {
        self.completion = completion
    }

    func deliver(_ result: Result<BrowserWindowMode, BrowserActivityFailure>) {
        lock.lock()
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }
}

final class AppleScriptRunLoopWorker: NSObject, @unchecked Sendable {
    static let shared = AppleScriptRunLoopWorker()

    private let ready = DispatchSemaphore(value: 0)
    private var thread: Thread!

    override init() {
        super.init()
        let thread = Thread(target: self, selector: #selector(threadMain), object: nil)
        thread.name = "dev.quangpao.discordrp.applescript"
        self.thread = thread
        thread.start()
        ready.wait()
    }

    func async(_ block: @escaping @Sendable () -> Void) {
        perform(#selector(runBlock(_:)), on: thread, with: AppleScriptBlock(block), waitUntilDone: false)
    }

    func runLoopThreadCheck(completion: @escaping @Sendable (Bool) -> Void) {
        async {
            completion(RunLoop.current.currentMode != nil)
        }
    }

    @objc private func threadMain() {
        autoreleasepool {
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            while !Thread.current.isCancelled {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 60))
            }
        }
    }

    @objc private func runBlock(_ box: AppleScriptBlock) {
        box.block()
    }
}

private final class AppleScriptBlock: NSObject, @unchecked Sendable {
    let block: @Sendable () -> Void

    init(_ block: @escaping @Sendable () -> Void) {
        self.block = block
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
