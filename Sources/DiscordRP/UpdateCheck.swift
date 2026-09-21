import Foundation

/// The outcome of a manual update check.
public enum UpdateCheckResult: Equatable {
    case upToDate(current: String)
    case newer(version: String, url: URL)
    case failed(reason: String)
}

/// Compares the running version with this project's latest GitHub release.
///
/// It runs **only when the user asks for it**: nothing here polls on a timer, so the app still makes
/// exactly the network calls the user triggers (see `SECURITY.md`). The decision is split from the
/// request (`interpret` vs `fetchLatest`) so the tests never touch the network.
public enum UpdateCheck {
    public static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/quangpao/discord-rp-mac/releases/latest"
    )!
    public static let releasesPage = URL(
        string: "https://github.com/quangpao/discord-rp-mac/releases/latest"
    )!

    /// Numeric comparison of dotted versions. A leading `v`, a pre-release suffix and missing
    /// components do not change the answer: `1.10.0` is newer than `1.9.9` (a plain string compare
    /// would say otherwise), and `2.0` is newer than `1.9.9`.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// `v1.2.0` → `[1, 2, 0]`; `1.2.0-beta.1` → `[1, 2, 0]`. Anything non-numeric ends a component.
    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[text.startIndex..<dash]) }
        return text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// The decision, with no network involved.
    public static func interpret(latestTag: String, current: String, htmlURL: URL?) -> UpdateCheckResult {
        let tag = latestTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return .failed(reason: "the latest release has no tag") }
        guard isNewer(tag, than: current) else { return .upToDate(current: current) }
        var name = tag
        if name.hasPrefix("v") || name.hasPrefix("V") { name.removeFirst() }
        return .newer(version: name, url: htmlURL ?? releasesPage)
    }

    /// The only network call in this type. Unauthenticated, and it sends nothing about the user.
    public static func fetchLatest(
        session: URLSession = .shared,
        current: String = Version.string
    ) async -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(reason: "unexpected response")
            }
            guard http.statusCode == 200 else {
                return .failed(reason: "GitHub answered \(http.statusCode)")
            }
            struct Release: Decodable {
                let tag_name: String
                let html_url: String?
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            return interpret(latestTag: release.tag_name,
                             current: current,
                             htmlURL: release.html_url.flatMap(URL.init(string:)))
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }
    }
}
