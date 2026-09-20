import Foundation

/// An Art Asset uploaded to the Discord application.
///
/// The **name** is what an activity key must contain, but the CDN serves the image by the numeric
/// **id** (`https://cdn.discordapp.com/app-assets/<app_id>/<asset_id>.png` — verified 200; the
/// name-based path 404s). So previewing an asset key needs both.
struct DiscordAsset: Decodable, Equatable, Identifiable {
    let name: String
    let id: String
}

/// Discord exposes an application's uploaded Art Assets without authentication — the same
/// call CustomRP makes (`MainForm.cs:1758-1797`). Cached for a minute; a failure is never fatal,
/// the editor just falls back to free text.
enum AssetCatalog {
    private static var cache: (appID: String, assets: [DiscordAsset], at: Date)?

    static func assets(appID: String, forceRefresh: Bool = false) async throws -> [DiscordAsset] {
        if !forceRefresh, let cache, cache.appID == appID,
           Date().timeIntervalSince(cache.at) < 60 {
            return cache.assets
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
        let assets = try JSONDecoder().decode([DiscordAsset].self, from: data)
            .sorted { $0.name < $1.name }
        cache = (appID, assets, Date())
        return assets
    }

    static func assetNames(appID: String, forceRefresh: Bool = false) async throws -> [String] {
        try await assets(appID: appID, forceRefresh: forceRefresh).map(\.name)
    }

    /// The numeric id for an asset name, for building a preview URL.
    static func assetID(named name: String, appID: String) async throws -> String? {
        try await assets(appID: appID).first { $0.name == name }?.id
    }
}
