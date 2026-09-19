import Foundation

/// Finds the Discord client's IPC socket.
///
/// macOS: `$TMPDIR/discord-ipc-<n>` (`/var/folders/…/T/…` — verifiably connectable, no
/// `/private` prefix needed). Windows-style named pipes do not exist here; index 0 is the
/// stable client, 1 PTB, 2 Canary. The original CustomRP exposes the same index to the user
/// as its "pipe" setting, so we keep `pipeIndex` configurable.
public enum SocketLocator {
    public static let socketName = "discord-ipc"

    public static func candidates(
        env: [String: String] = ProcessInfo.processInfo.environment,
        tmpdir: String = NSTemporaryDirectory(),
        home: String = NSHomeDirectory(),
        pipeIndex: Int = 0
    ) -> [String] {
        var out: [String] = []
        // `getenv` (not `ProcessInfo`) so tests can point the client at a fake server with
        // `setenv` — ProcessInfo caches the environment on first access.
        let explicit = getenv("CUSTOMRP_IPC_PATH").map { String(cString: $0) } ?? env["CUSTOMRP_IPC_PATH"]
        if let explicit, !explicit.isEmpty {
            out.append(explicit)
        }

        let tmp = tmpdir.hasSuffix("/") ? String(tmpdir.dropLast()) : tmpdir
        // Preferred index first, then the other clients so a single running Discord is found
        // even if the user's pipe setting points at one that is not running.
        var indexes = [pipeIndex]
        indexes.append(contentsOf: [0, 1, 2].filter { $0 != pipeIndex })
        for index in indexes {
            out.append("\(tmp)/\(socketName)-\(index)")
        }
        out.append("/tmp/\(socketName)-\(pipeIndex)")
        out.append("\(home)/Library/Application Support/discord/\(socketName)-\(pipeIndex)")
        out.append("\(home)/Library/Application Support/Discord/\(socketName)-\(pipeIndex)")
        return out.uniqued()
    }

    public static func firstAvailable(
        env: [String: String] = ProcessInfo.processInfo.environment,
        tmpdir: String = NSTemporaryDirectory(),
        home: String = NSHomeDirectory(),
        pipeIndex: Int = 0,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        candidates(env: env, tmpdir: tmpdir, home: home, pipeIndex: pipeIndex)
            .first(where: fileExists)
    }

    /// `/var/folders/...` and `/private/var/folders/...` are the same socket; dedupe both forms.
    public static func sameSocket(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    public static func normalize(_ path: String) -> String {
        let resolved = (path as NSString).resolvingSymlinksInPath
        return resolved.hasPrefix("/private") ? String(resolved.dropFirst("/private".count)) : resolved
    }
}

extension Array where Element: Hashable {
    /// Order-preserving dedupe.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
