import Foundation

/// Discord exposes an application's uploaded Art Assets without authentication — the same
/// call CustomRP makes (`MainForm.cs:1758-1797`). Names are cached for a minute; a failure is
/// never fatal, the editor just falls back to free text.
enum AssetCatalog {
    private struct Asset: Decodable { let name: String }

    private static var cache: (appID: String, names: [String], at: Date)?

    static func assetNames(appID: String, forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh, let cache, cache.appID == appID,
           Date().timeIntervalSince(cache.at) < 60 {
            return cache.names
        }
        guard let url = URL(string: "https://discord.com/api/oauth2/applications/\(appID)/assets") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let assets = try JSONDecoder().decode([Asset].self, from: data)
        let names = assets.map(\.name).sorted()
        cache = (appID, names, Date())
        return names
    }
}
