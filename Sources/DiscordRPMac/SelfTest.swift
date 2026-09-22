import AppKit
import DiscordRP
import Foundation
import SwiftUI

/// Headless checks that need no XCTest (the CommandLineTools toolchain has no test runner),
/// plus a live probe against the real Discord client.
///
/// `DiscordRPMac --self-test` · `DiscordRPMac --version` · `DiscordRPMac --live --app-id <ID>`
enum SelfTest {
    private static var failures = 0

    static func runIfRequested() -> Int32? {
        let args = CommandLine.arguments
        if args.contains("--version") {
            print("Discord RP \(Version.string)")
            return 0
        }
        if let index = args.firstIndex(of: "--login-item") {
            let action = index + 1 < args.count ? args[index + 1] : "status"
            print("bundle: \(Bundle.main.bundlePath)")
            print("before: \(LaunchAtLogin.debugDescription)")
            switch action {
            case "on", "off":
                do {
                    try LaunchAtLogin.setEnabled(action == "on")
                } catch {
                    print("error: \(error)")
                }
            default:
                break
            }
            print("after:  \(LaunchAtLogin.debugDescription)")
            return 0
        }
        if let index = args.firstIndex(of: "--giphy-key") {
            let action = index + 1 < args.count && !args[index + 1].hasPrefix("--") ? args[index + 1] : "status"
            switch action {
            case "status":
                print("source: \(GiphyKeyStore.source().description)")
                return 0
            case "migrate":
                let outcome = Migration.migrateKeychain()
                let copied = Migration.migrateDataDirectory()
                print("key: \(outcome.rawValue)")
                print("data: copied \(copied.isEmpty ? "nothing" : copied.joined(separator: ", "))")
                print("source: \(GiphyKeyStore.source().description)")
                return 0
            case "clear":
                GiphyKeyStore.clear()
                print("cleared — source: \(GiphyKeyStore.source().description)")
                return 0
            case "set":
                // Read from stdin: a key on the command line would end up in shell history and in
                // the process table for anyone to read.
                let input = FileHandle.standardInput.readDataToEndOfFile()
                let key = String(decoding: input, as: UTF8.self)
                do {
                    try GiphyKeyStore.save(key)
                    print("saved — source: \(GiphyKeyStore.source().description)")
                    return 0
                } catch let error as GiphyKeyError {
                    print("error: \(error.description)")
                    return 1
                } catch {
                    print("error: \(error.localizedDescription)")
                    return 1
                }
            default:
                print("usage: --giphy-key status|set|clear|migrate   (set reads the key from stdin)")
                return 1
            }
        }
        if args.contains("--giphy-library") {
            let library = GiphyLibrary.shared.load()
            if library.isEmpty {
                print("no uploads recorded yet")
            } else {
                print("\(library.count) upload(s), newest first:")
                for upload in library {
                    print("  \(upload.id)  \(upload.filename)  \(upload.hidden ? "private" : "public")  "
                          + upload.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    print("      \(upload.mediaURL)")
                }
            }
            return 0
        }
        if let index = args.firstIndex(of: "--check-updates") {
            // An optional version after the flag stands in for the running one, so the "newer
            // release" branch can be exercised against the real API.
            let current = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : Version.string
            return checkForUpdates(current: current)
        }
        if let index = args.firstIndex(of: "--presets") {
            let directory = index + 1 < args.count && !args[index + 1].hasPrefix("--") ? args[index + 1] : nil
            return dumpPresetPayloads(directory: directory)
        }
        if let index = args.firstIndex(of: "--render-editor") {
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "/tmp/discordrp-editor.png"
            let width = index + 2 < args.count ? Double(args[index + 2]) ?? 720 : 720
            let height = index + 3 < args.count ? Double(args[index + 3]) ?? 800 : 800
            return renderEditor(to: path, width: width, height: height)
        }
        if let index = args.firstIndex(of: "--render-settings") {
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "/tmp/discordrp-settings.png"
            let sizeArgs = args.dropFirst(index + 2).prefix { !$0.hasPrefix("--") }.compactMap(Double.init)
            let width = sizeArgs.first ?? 640
            let height = sizeArgs.dropFirst().first ?? 520
            let paneName = value(of: "--pane", in: args) ?? "cards"
            let pane = SettingsPane.allCases.first { $0.rawValue.lowercased() == paneName.lowercased() } ?? .cards
            return renderSettings(to: path, width: width, height: height, pane: pane,
                                  preset: value(of: "--preset", in: args))
        }
        if let index = args.firstIndex(of: "--render-menu") {
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "/tmp/discord-rp-menu.png"
            let width = index + 2 < args.count ? Double(args[index + 2]) ?? 300 : 300
            let height = index + 3 < args.count ? Double(args[index + 3]) ?? 420 : 420
            return renderMenu(to: path, width: width, height: height)
        }
        if let index = args.firstIndex(of: "--giphy-upload") {
            let file = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "dist/discord/discord-rp-animated-logo.gif"
            return uploadToGiphy(file: file, hidden: args.contains("--hidden"))
        }
        let live = args.contains("--live")
        guard args.contains("--self-test") || live else { return nil }

        print("Discord RP \(Version.string) — self-test")
        checkFraming()
        checkSocketLocator()
        checkRules()
        checkPresetStore()
        if live {
            checkLive(appID: value(of: "--app-id", in: args) ?? "")
        }
        print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
        return failures == 0 ? 0 : 1
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func expect(_ condition: Bool, _ label: String, detail: String = "") {
        if condition {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label) \(detail)")
        }
    }

    // MARK: checks

    private static func checkFraming() {
        print("framing:")
        let payload: [String: Any] = ["v": 1, "client_id": "123"]
        guard let frame = try? IPCProtocol.encode(opcode: .handshake, payload: payload) else {
            return expect(false, "encode handshake")
        }
        let body = String(decoding: frame.dropFirst(IPCProtocol.headerSize), as: UTF8.self)
        expect(Array(frame.prefix(4)) == [0, 0, 0, 0], "opcode 0 little-endian")
        expect(frame.loadLE(at: 4) == UInt32(frame.count - IPCProtocol.headerSize), "length field")
        expect(body == #"{"client_id":"123","v":1}"#, "sorted-key JSON body", detail: body)
        if let (op, decoded) = try? IPCProtocol.decode(frame) {
            expect(op == .handshake, "decoded opcode")
            expect(decoded["client_id"] as? String == "123", "decoded payload")
        } else {
            expect(false, "decode round trip")
        }
        expect((try? IPCProtocol.decode(Data([0, 0, 0]))) == nil, "short header rejected")
    }

    private static func checkSocketLocator() {
        print("socket locator:")
        let candidates = SocketLocator.candidates(
            env: ["DISCORDRP_IPC_PATH": "/custom/path"],
            tmpdir: "/tmp/x", home: "/Users/nobody", pipeIndex: 1
        )
        print("  candidates: \(candidates)")
        expect(candidates.first == "/custom/path", "env override wins")
        expect(candidates.contains("/tmp/x/discord-ipc-1"), "preferred pipe index")
        expect(candidates.contains("/tmp/x/discord-ipc-0"), "other indexes still tried")
        let real = SocketLocator.candidates()
        print("  default:    \(real)")
        print("  NSTemporaryDirectory: \(NSTemporaryDirectory())")
        expect(real.first?.contains("discord-ipc-") == true, "default candidates built")
        let live = SocketLocator.firstAvailable()
        expect(live != nil, "Discord socket found on this machine", detail: live ?? "none")
    }

    private static func checkRules() {
        print("discord rules:")
        var activity = Activity(name: "Test", details: "coding", state: "discord-rp-mac")
        expect(ActivityRules.validate(activity, appID: "123").isEmpty, "valid activity passes")

        activity.details = "x"
        expect(ActivityRules.errors(in: ActivityRules.validate(activity, appID: "123")).count == 1,
               "1-char details rejected")
        activity.details = "ok"

        activity.buttons = [Button(label: String(repeating: "ế", count: 20), url: "example.com")]
        let byteIssue = ActivityRules.validate(activity, appID: "123")
        expect(byteIssue.contains { $0.field == .buttonLabel },
               "button label limited by UTF-8 bytes",
               detail: "\(ActivityRules.utf8ByteCount(activity.buttons[0].label)) bytes")
        expect(ActivityRules.normalizedURL("example.com") == "https://example.com", "url scheme added")
        activity.buttons = []
        expect(activity.buttons.isEmpty, "buttons cleared")

        expect(ActivityRules.zeroWidthGuarded("\u{00A0}lead") == "\u{200B}\u{00A0}lead", "NBSP zero-width guard")

        let long = "https://cdn.example.com/" + String(repeating: "a", count: 300) + ".png"
        activity.largeKey = long
        expect(ActivityRules.validate(activity, appID: "123").contains { $0.field == .imageKey },
               "mp:external budget enforced")
        activity.largeKey = "my_asset-1"
        expect(ActivityRules.validate(activity, appID: "123").isEmpty, "asset name accepted")

        activity.kind = .competing
        activity.timestampMode = .sinceConnection
        let competing = ActivityRules.payload(activity, appID: "123", appStarted: Date(),
                                              connectionStarted: Date(), presenceStarted: Date())
        expect(competing?["timestamps"] == nil, "competing strips timestamps")
        activity.kind = .playing

        let now = Date()
        activity.timestampMode = .custom
        activity.customStart = now.addingTimeInterval(3600)
        let countdown = ActivityRules.payload(activity, appID: "123", now: now, appStarted: now,
                                              connectionStarted: now, presenceStarted: now)
        let timestamps = countdown?["timestamps"] as? [String: Int]
        expect(timestamps?["end"] != nil, "future custom start becomes a countdown")

        activity.timestampMode = .off
        activity.partySize = 3
        activity.partyMax = 2
        let party = ActivityRules.payload(activity, appID: "123", now: now, appStarted: now,
                                          connectionStarted: now, presenceStarted: now)
        expect((party?["party"] as? [String: Any])?["size"] as? [Int] == [3, 3], "party max raised")

        var empty = Activity()
        empty.details = ""
        expect(ActivityRules.payload(empty, appID: "123", now: now, appStarted: now,
                                     connectionStarted: now, presenceStarted: now) != nil,
               "empty activity still produces a payload")
    }

    private static func checkPresetStore() {
        print("preset store:")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("discordrp-selftest-\(UUID().uuidString)")
        let store = PresetStore(directory: directory)
        let preset = Preset(name: "Round trip", activity: Activity.sample("RT"))
        try? store.save(presets: [preset])
        expect(store.loadPresets() == [preset], "round trip")
        var settings = AppSettings()
        settings.appID = "42"
        try? store.save(settings: settings)
        expect(store.loadSettings().appID == "42", "settings round trip")
        try? "not json".write(to: directory.appendingPathComponent("presets.json"), atomically: true, encoding: .utf8)
        expect(store.loadPresets().isEmpty, "corrupt file yields empty list")
        expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("presets.json.bak").path),
               "corrupt file quarantined to .bak")
        try? FileManager.default.removeItem(at: directory)
    }

    /// `--render-editor <out.png> [width height]` — draws the editor off-screen through the app's
    /// own AppKit/SwiftUI stack. The app renders its **own view**, so this needs no Screen Recording
    /// permission and still yields real pixels to inspect the layout with.
    private static func renderEditor(to path: String, width: Double, height: Double) -> Int32 {
        let render: @MainActor () -> Void = {
            installRenderGiphyStorage()
            let model = demoModel()
            capture(NSHostingView(rootView: ActivityEditorView(model: model)),
                    titled: true, to: path, width: width, height: height, settle: 3.0)
        }
        return runOnMain(render)
    }

    /// `--render-settings <out.png> [width height] [--pane cards|presets|general|giphy]
    /// [--preset <index|id>] [--demo <dir>]` — draws Settings without touching the real Keychain.
    private static func renderSettings(to path: String, width: Double, height: Double,
                                       pane: SettingsPane, preset: String?) -> Int32 {
        let render: @MainActor () -> Void = {
            installRenderGiphyStorage()
            let model = demoModel()
            let presetID = resolvePreset(preset, in: model.presets)
            capture(NSHostingView(rootView: SettingsView(model: model, initialPane: pane,
                                                         selectedPresetID: presetID)),
                    titled: true, to: path, width: width, height: height, settle: 1.5)
        }
        return runOnMain(render)
    }

    private static func resolvePreset(_ value: String?, in presets: [Preset]) -> UUID? {
        guard let value, !value.isEmpty else { return nil }
        if let id = UUID(uuidString: value), presets.contains(where: { $0.id == id }) {
            return id
        }
        guard let index = Int(value) else { return nil }
        let resolvedIndex = index == 0 ? 0 : index - 1
        guard presets.indices.contains(resolvedIndex) else { return nil }
        return presets[resolvedIndex].id
    }

    private static func installRenderGiphyStorage() {
        // A render must never read the developer's real Keychain: the binary is ad-hoc signed, so
        // every rebuild changes its identity, macOS raises an ACL prompt, and the render blocks in
        // `mach_msg` until somebody answers a dialog it cannot show. Stub storage instead; with
        // `--no-key` the stub is swapped for the empty one so the BYOK gating can be seen.
        GiphyKeyStore.storage = CommandLine.arguments.contains("--no-key")
            ? NoGiphyKeyStorage()
            : StubGiphyKeyStorage()
        setenv("GIPHY_API_KEY", "", 1)
        GiphyKeyStore.legacyPathOverride = "/nonexistent/giphy/api_key"
    }

    /// `--render-menu <out.png> [width height]` — the same capture for the menu bar menu, so the
    /// README screenshot is a real render of the real view rather than a mock.
    private static func renderMenu(to path: String, width: Double, height: Double) -> Int32 {
        let render: @MainActor () -> Void = {
            let model = demoModel()
            let root = MenuContentView(model: model)
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .frame(width: width)
            capture(NSHostingView(rootView: root), titled: false, to: path,
                    width: width, height: height, settle: 1.5)
        }
        return runOnMain(render)
    }

    /// The model a screenshot is drawn from. With `--demo <dir>` it reads that throwaway preset set
    /// (no personal data) and shows a neutral connected status, because a screenshot of an app that
    /// is still mid-start reads as broken. The README states the screenshots come from the demo set.
    @MainActor
    private static func demoModel() -> AppModel {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--demo"), index + 1 < args.count else {
            return AppModel(startEngine: false)
        }
        let store = PresetStore(directory: URL(fileURLWithPath: args[index + 1]))
        let model = AppModel(startEngine: false, store: store)
        model.status = .connected(user: "demo")
        model.multiStatus = .live(active: max(1, model.enabledCards.count))
        return model
    }

    /// Not `@MainActor` itself: it is called from the nonisolated CLI entry point and does its own
    /// hop onto the main thread, which is what the original inline version did.
    private static func runOnMain(_ work: @MainActor () -> Void) -> Int32 {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { work() } }
        }
        return 0
    }

    /// Renders `hosting` off-screen (never shown to the user) and writes a PNG. The settle time
    /// matters: image previews load asynchronously, so capturing at once shows spinners instead.
    @MainActor
    private static func capture(_ hosting: NSView, titled: Bool, to path: String,
                                width: Double, height: Double, settle: TimeInterval) {
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        // Pin the appearance. The harness used to follow the system theme, so regenerating the
        // screenshots at night produced dark images while the committed ones were light, and the two
        // README screenshots could disagree. Switch to `.darkAqua` to ship dark ones.
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: titled ? [.titled] : [.borderless],
                              backing: .buffered, defer: false)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))  // never shown, only rendered
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hosting.display()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hosting.display()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("render failed: no bitmap rep")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("render failed: no PNG data")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("rendered \(Int(width))x\(Int(height)) → \(path)")
        } catch {
            print("render failed: \(error.localizedDescription)")
        }
    }

    /// `--check-updates` — the same call the menu makes, so the network path can be verified
    /// headlessly instead of by clicking a menu item.
    private static func checkForUpdates(current: String) -> Int32 {
        var exit: Int32 = 0
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            switch await UpdateCheck.fetchLatest(current: current) {
            case .upToDate(let current):
                print("up to date (\(current))")
            case .newer(let version, let url):
                print("update available: \(version) — \(url.absoluteString)")
            case .failed(let reason):
                print("check failed: \(reason)")
                exit = 1
            }
            done.signal()
        }
        done.wait()
        return exit
    }

    /// `--presets [support-dir]` prints, for every stored preset, the exact SET_ACTIVITY payload the
    /// app would send plus its validation issues. Deterministic — no socket, no restart — which is
    /// what makes it usable to check "does the demo cover every field?".
    private static func dumpPresetPayloads(directory: String?) -> Int32 {
        let store = PresetStore(directory: directory.map { URL(fileURLWithPath: $0) })
        let settings = store.loadSettings()
        let presets = store.loadPresets()
        let now = Date()
        print("appID: \(settings.appID)  presets: \(presets.count)")
        var report: [[String: Any]] = []
        for preset in presets {
            let issues = ActivityRules.validate(preset.activity, appID: settings.appID)
            let payload = ActivityRules.payload(
                preset.activity, appID: settings.appID, now: now,
                appStarted: now.addingTimeInterval(-3600), connectionStarted: now.addingTimeInterval(-2520),
                presenceStarted: now
            )
            let errors = ActivityRules.errors(in: issues)
            print("--- \(preset.name)")
            print("    errors: \(errors.count)  warnings: \(issues.count - errors.count)")
            for issue in issues {
                print("      \(issue.isError ? "!" : "i") \(issue.message)")
            }
            if let payload,
               let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]),
               let text = String(data: data, encoding: .utf8) {
                print(text.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))
                report.append(["name": preset.name, "payload": payload, "errors": errors.count])
            } else {
                print("    (no payload — errors block it)")
                report.append(["name": preset.name, "payload": NSNull(), "errors": errors.count])
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("discordrp-presets.json")
            try? data.write(to: out)
            print("machine-readable: \(out.path)")
        }
        return 0
    }

    /// `--giphy-upload [file] [--hidden]` — the same code path the editor's button uses, so the
    /// real upload can be verified from the shell.
    private static func uploadToGiphy(file: String, hidden: Bool) -> Int32 {
        guard let key = GiphyUploader.apiKey() else {
            print("no API key at \(GiphyUploader.defaultKeyPath()) and GIPHY_API_KEY is unset")
            return 1
        }
        let semaphore = DispatchSemaphore(value: 0)
        var output = "timeout"
        Task {
            do {
                let result = try await GiphyUploader.upload(
                    file: URL(fileURLWithPath: file), apiKey: key, hidden: hidden
                )
                output = """
                id:        \(result.id)
                media url: \(result.mediaURL)
                page:      \(result.pageURL)
                key length: \(result.mediaURL.count) chars
                """
            } catch let error as GiphyError {
                output = "error: \(error.message)"
            } catch {
                output = "error: \(error)"
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 150)
        print(output)
        return output.hasPrefix("error") || output == "timeout" ? 1 : 0
    }

    private static func checkLive(appID: String) {
        print("live probe:")
        guard !appID.isEmpty else {
            return expect(false, "app id supplied", detail: "pass --app-id <ID>")
        }
        let client = DiscordIPCClient(appID: appID)
        do {
            let path = try client.connect()
            print("  socket: \(path)")
            print("  user:   \(client.readyUser?.username ?? "unknown")")
            var activity = Activity(name: "Discord RP", details: "Live probe", state: "discord-rp-mac")
            activity.timestampMode = .sincePresenceUpdate
            let payload = ActivityRules.payload(activity, appID: appID, appStarted: Date(),
                                                connectionStarted: Date(), presenceStarted: Date()) ?? [:]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try client.setActivity(data)
            print("  SET_ACTIVITY accepted")
            expect(true, "SET_ACTIVITY accepted")
            Thread.sleep(forTimeInterval: 3)
            try? client.setActivity(nil)
            print("  cleared")
        } catch IPCError.discordRejected(let code, let message) {
            // A placeholder id still proves the whole path: socket, framing, handshake, and
            // Discord's own reply decoded correctly.
            print("  Discord answered: code \(code) — \(message)")
            expect(true, "handshake verified end-to-end (Discord rejected this id, as expected for a placeholder)")
        } catch IPCError.timeout {
            print("  no reply within the timeout — Discord throttles repeated probes with a bad id; retry in a minute")
            expect(false, "live probe replied")
        } catch {
            expect(false, "live connect/set", detail: "\(error)")
            if case IPCError.socketUnavailable(let failures) = error {
                for failure in failures { print("  tried: \(failure)") }
            }
        }
        client.close()
    }
}
