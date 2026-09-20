import Foundation
import ServiceManagement

/// Launch at login: `SMAppService.mainApp` first (the modern, macOS 13+ way), with a
/// LaunchAgent fallback because an ad-hoc-signed bundle can be refused with
/// "Operation not permitted".
enum LaunchAtLogin {
    static let agentLabel = "dev.quangpao.discordrp"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Human-readable state for the CLI diagnostics (`--login-item status`).
    static var debugDescription: String {
        let main = SMAppService.mainApp.status
        let mainText: String
        switch main {
        case .enabled: mainText = "enabled"
        case .notRegistered: mainText = "notRegistered"
        case .notFound: mainText = "notFound"
        case .requiresApproval: mainText = "requiresApproval"
        @unknown default: mainText = "unknown(\(main.rawValue))"
        }
        let agent = FileManager.default.fileExists(atPath: agentURL.path) ? "present" : "absent"
        return "SMAppService=\(mainText) launchAgent=\(agent) isEnabled=\(isEnabled)"
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if !isEnabled {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    try writeAgent()
                }
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
            removeAgent()
        }
    }

    // MARK: fallback LaunchAgent

    private static func writeAgent() throws {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // `launchctl bootstrap` needs the file gone first when reloading.
        removeAgent(silently: true)
        try data.write(to: agentURL, options: .atomic)
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
    }

    private static func removeAgent(silently: Bool = false) {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return }
        run("/bin/launchctl", ["bootout", "gui/\(getuid())", agentURL.path])
        try? FileManager.default.removeItem(at: agentURL)
        if !silently { run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"]) }
    }

    private static func run(_ launchPath: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
