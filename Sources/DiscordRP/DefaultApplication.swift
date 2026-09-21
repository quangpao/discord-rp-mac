import Foundation

/// The Discord application this project registers, so the app works with **no setup at all**.
///
/// An Application ID is not optional: Discord's IPC handshake always carries one
/// (`["v": 1, "client_id": …]`) and an unknown id is rejected with `code 4000` — verified against the
/// live client, not the documentation. What *is* optional is using **your own**:
///
/// - **No id set** → nothing is sent to Discord at all (the engine is not even started).
/// - **This default** → the activity is set through this project's application, so the card reads
///   "Discord RP" and can use the assets uploaded to it.
/// - **Your own id** → your own name, icon and art assets. Two minutes in the Developer Portal.
///
/// The id is not a secret (every Rich Presence application publishes one), but it is deliberately
/// isolated here so the choice is explicit and greppable.
public enum DefaultApplication {
    public static let id = "1041550572223995925"

    /// True when `id` is the built-in application, ignoring surrounding whitespace.
    public static func isDefault(_ id: String) -> Bool {
        id.trimmingCharacters(in: .whitespacesAndNewlines) == Self.id
    }
}
