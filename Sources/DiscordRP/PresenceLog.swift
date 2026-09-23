import Foundation

/// Minimal file logging: the payload Discord actually received is written to disk so a push can
/// be verified from the shell (`~/Library/Logs/DiscordRP/last-presence.json`). No telemetry, no
/// network — the plan's logging decision.
public enum PresenceLog {
    /// Overridable so tests never write into the developer's real log directory (a test run used to
    /// clobber `last-presence.json` with its own fixture payload).
    nonisolated(unsafe) public static var directoryOverride: URL?

    public static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        return base.appendingPathComponent("Logs/DiscordRP", isDirectory: true)
    }

    public static var lastPayloadURL: URL { directory.appendingPathComponent("last-presence.json") }
    /// The log was `customrp.log` before the app was renamed to Discord RP. The pre-rename file is
    /// carried over once (renamed, so the history survives) instead of leaving a stale file behind.
    /// Internal rather than private so `PresenceLogTests` can exercise it without a reset hook; the
    /// two `fileExists` calls are free next to an actual log write.
    static func migratedLogURL(in directory: URL) -> URL {
        let current = directory.appendingPathComponent("discord-rp.log")
        let legacy = directory.appendingPathComponent("customrp.log")
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: current)
        }
        return current
    }

    private static var logURL: URL { migratedLogURL(in: directory) }

    private static let maxLogBytes = 1 << 20
    private static let appendQueue = DispatchQueue(label: "discord-rp.presence-log.append")

    public static func record(payload: Data?, appID: String? = nil, reply: DiscordIPCClient.Reply? = nil, error: String?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let app = appID.map { " appID=\($0)" } ?? ""

        if let payload {
            try? payload.write(to: lastPayloadURL, options: .atomic)
            append("\(stamp) pushed\(app) \(String(decoding: payload, as: UTF8.self))\n")
        }
        if let reply {
            append("\(stamp) reply\(app) opcode=\(reply.opcode.rawValue) data=\(reply.data) evt=\(reply.evt)\n")
        }
        if let error {
            append("\(stamp) error\(app) \(error)\n")
        }
    }

    /// Diagnostic breadcrumbs for the connection lifecycle (timer start/stop, paused, periodic
    /// keepalive). Kept deliberately sparse: a long-lived app must not grow its log without bound.
    public static func note(_ message: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        append("\(ISO8601DateFormatter().string(from: Date())) note \(message)\n")
    }

    private static func append(_ line: String) {
        appendQueue.sync {
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
}
