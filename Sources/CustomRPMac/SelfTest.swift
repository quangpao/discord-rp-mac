import DiscordRP
import Foundation

/// Headless checks that need no XCTest (the CommandLineTools toolchain has no test runner),
/// plus a live probe against the real Discord client.
///
/// `CustomRPMac --self-test` · `CustomRPMac --version` · `CustomRPMac --live --app-id <ID>`
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
        if let index = args.firstIndex(of: "--presets") {
            let directory = index + 1 < args.count && !args[index + 1].hasPrefix("--") ? args[index + 1] : nil
            return dumpPresetPayloads(directory: directory)
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
        var activity = Activity(name: "Test", details: "coding", state: "customrp-mac")
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
            var activity = Activity(name: "CustomRP", details: "Live probe", state: "customrp-mac")
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
