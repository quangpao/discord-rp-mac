import AppKit
import Foundation

/// A second launch must not become a second presence owner. Here: an exclusive `flock` on a
/// lock file; the newcomer activates the running copy and exits.
enum SingleInstance {
    private static var lockDescriptor: Int32 = -1

    private static var lockURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let directory = base.appendingPathComponent("DiscordRPMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("instance.lock")
    }

    /// Exits the process when another instance already holds the lock.
    static func exitIfAlreadyRunning() {
        let url = lockURL
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            activateExistingInstance()
            close(descriptor)
            exit(0)
        }
        lockDescriptor = descriptor
        // Keep the descriptor open for the process lifetime; released by the kernel on exit.
    }

    private static func activateExistingInstance() {
        let bundleID = Bundle.main.bundleIdentifier
        if let bundleID {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != getpid() }
            if let running = others.first {
                running.activate(options: [.activateAllWindows])
                return
            }
        }
        if let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.hnc.Discord"
        }) {
            other.activate(options: [])
        }
    }
}
