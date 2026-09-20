import Foundation

/// Where an image key can be fetched from for a preview.
///
/// * An `https://` key is loaded as-is (that is what Discord does too).
/// * A bare name is a **Discord application asset**. The CDN serves those by numeric id —
///   `https://cdn.discordapp.com/app-assets/<application_id>/<asset_id>.png` (verified 200; the
///   name-based path returns 404) — so a preview of an asset key needs the id from the assets API
///   as well as the Application ID.
///
/// Lives in the library (not the app target) so the URL rules are unit-tested.
public struct PreviewTarget: Equatable, Sendable {
    public let url: URL
    public let kind: String

    public init(url: URL, kind: String) {
        self.url = url
        self.kind = kind
    }

    public static func make(key: String, appID: String, assetID: String? = nil) -> PreviewTarget? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            guard let url = URL(string: trimmed) else { return nil }
            return PreviewTarget(url: url, kind: "external URL")
        }

        // A Discord asset name: no slashes, no spaces, and it needs both the app and the asset id.
        let applicationID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !applicationID.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains(" "),
              let assetID, !assetID.isEmpty,
              let url = URL(string: "https://cdn.discordapp.com/app-assets/\(applicationID)/\(assetID).png")
        else { return nil }
        return PreviewTarget(url: url, kind: "Discord asset")
    }
}
