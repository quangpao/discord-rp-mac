import Foundation

/// Minimal file logging: the payload Discord actually received is written to disk so a push can
/// be verified from the shell (`~/Library/Logs/DiscordRP/last-presence.json`). No telemetry, no
/// network — the plan's logging decision.
public enum PresenceLog {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        return base.appendingPathComponent("Logs/DiscordRP", isDirectory: true)
    }

    public static var lastPayloadURL: URL { directory.appendingPathComponent("last-presence.json") }
    private static var logURL: URL { directory.appendingPathComponent("customrp.log") }

    private static let maxLogBytes = 1 << 20

    public static func record(payload: Data?, error: String?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())

        if let payload {
            try? payload.write(to: lastPayloadURL, options: .atomic)
            append("\(stamp) pushed \(String(decoding: payload, as: UTF8.self))\n")
        }
        if let error {
            append("\(stamp) error \(error)\n")
        }
    }

    /// Diagnostic breadcrumbs for the connection lifecycle (timer start/stop, paused, periodic
    /// keepalive). Kept deliberately sparse: a long-lived app must not grow its log without bound.
    public static func note(_ message: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        append("\(ISO8601DateFormatter().string(from: Date())) note \(message)\n")
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int,
           size > maxLogBytes {
            try? FileManager.default.removeItem(at: logURL)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
