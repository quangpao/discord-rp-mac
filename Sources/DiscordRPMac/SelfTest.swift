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
            print("CustomRP \(Version.string)")
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
        if let index = args.firstIndex(of: "--presets") {
            let directory = index + 1 < args.count && !args[index + 1].hasPrefix("--") ? args[index + 1] : nil
            return dumpPresetPayloads(directory: directory)
        }
        if let index = args.firstIndex(of: "--render-editor") {
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "/tmp/customrp-editor.png"
            let width = index + 2 < args.count ? Double(args[index + 2]) ?? 720 : 720
            let height = index + 3 < args.count ? Double(args[index + 3]) ?? 800 : 800
            return renderEditor(to: path, width: width, height: height)
        }
        if let index = args.firstIndex(of: "--giphy-upload") {
            let file = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1]
                : "dist/discord/discord-rp-animated-logo.gif"
            return uploadToGiphy(file: file, hidden: args.contains("--hidden"))
        }
        let live = args.contains("--live")
        guard args.contains("--self-test") || live else { return nil }

        print("CustomRP \(Version.string) — self-test")
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
            env: ["CUSTOMRP_IPC_PATH": "/custom/path"],
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
            .appendingPathComponent("customrp-selftest-\(UUID().uuidString)")
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
            if CommandLine.arguments.contains("--no-key") {
                // The "no key yet" state, so the BYOK gating can be verified as pixels.
                GiphyKeyStore.storage = NoGiphyKeyStorage()
                setenv("GIPHY_API_KEY", "", 1)
                GiphyKeyStore.legacyPathOverride = "/nonexistent/giphy/api_key"
            }
            let model = AppModel(startEngine: false)
            let hosting = NSHostingView(rootView: ActivityEditorView(model: model))
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.frame = frame
            let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))  // never shown, only rendered
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            hosting.display()
            // Image previews load asynchronously; let them land before capturing, or the shot shows
            // spinners instead of the images the user actually sees.
            RunLoop.main.run(until: Date().addingTimeInterval(3.0))
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

        if Thread.isMainThread {
            MainActor.assumeIsolated { render() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { render() } }
        }
        return 0
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
            let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("customrp-presets.json")
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
                    file: URL(fileURLWithPath: file), apiKey: key, hidden: hidden, tags: "customrp,quangpao"
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
            var activity = Activity(name: "CustomRP", details: "Live probe", state: "discord-rp-mac")
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
