# Architecture

Two SwiftPM targets, no Xcode project. The split exists so the protocol and rules can be tested
without a UI, and so the executable target (which bridges SwiftUI/AppKit) stays small.

```
Sources/
  DiscordRP/        core library — no SwiftUI, no AppKit UI, strict Swift 6 concurrency
  DiscordRPMac/     menu bar app — SwiftUI + AppKit glue, Swift 5 language mode
Tests/
  DiscordRPTests/   unit tests for the core library (fake Discord IPC server included)
```

## `Sources/DiscordRP` (core, Swift 6 language mode)

| File | Responsibility |
| --- | --- |
| `IPCProtocol.swift` | Frame encoding/decoding: 4-byte little-endian opcode + length + JSON payload; opcodes 0/1/2/3. |
| `DiscordIPCClient.swift` | Connects to the `AF_UNIX` socket `discord-ipc-<n>` in `$TMPDIR`, handshake, `SET_ACTIVITY`, close. |
| `PresenceEngine.swift` | Owns the client: apply/clear an activity, 15 s keepalive, backoff 2/5/10/30 s, reassert after wake, `beginActivity` token against App Nap. Never pauses on a rejected payload — it retries. |
| `Activity.swift` | The activity model (type, display type, name, details/state, party, timestamps, assets, buttons). |
| `ActivityRules.swift` | Discord's validation rules with readable reasons; returns Discord's own wording when it rejects something. |
| `ReconnectPlan.swift` | Pure decision for the Reconnect button (unchanged settings still reapply). Testable here because the app target has no test target. |
| `PresetStore.swift` | JSON persistence of presets/settings (`~/Library/Application Support/DiscordRPMac`), epoch **milliseconds** pinned. |
| `PresenceLog.swift` | Appends to `~/Library/Logs/DiscordRP/discord-rp.log` and writes `last-presence.json`; directory is overridable so tests never touch the real one. |
| `GiphyUploader.swift` | Multipart upload to Giphy. Sends only `api_key` (+ optional hidden/tags/source). |
| `GiphyKeyStore.swift` | Key resolution: Keychain → `$GIPHY_API_KEY` → `~/.giphy/api_key`. Validation, save/clear, source reporting (never the value). |
| `GiphyLibrary.swift` | Local upload history (Giphy's API cannot list your own uploads). |
| `PreviewTarget.swift` | Decides what a preview should load: Discord asset by numeric id, or a Giphy URL. |
| `Migration.swift` | One-time copy of data + Keychain service after the app was renamed. Copy-only, never destructive. |

## `Sources/DiscordRPMac` (app)

| File | Responsibility |
| --- | --- |
| `CustomRPMacApp.swift` | `MenuBarExtra` entry point, `LSUIElement` (no Dock icon). |
| `AppModel.swift` | Observable state: settings, presets, active preset, issues, reconnect, persistence. |
| `MenuContentView.swift` | The menu: status, preset list, quick actions. |
| `ActivityEditorView.swift` | The editor window. Hand-built `label | control` grid — see the comment at the top of the file for why a SwiftUI `Form` was abandoned. |
| `ImagePreview.swift` | `NSImageView`-backed preview so GIFs actually animate (SwiftUI shows frame one). |
| `AssetCatalog.swift` | Lists the user's Discord art assets as `[DiscordAsset]` (name + **numeric id**, the only id the CDN accepts). |
| `LaunchAtLogin.swift`, `SingleInstance.swift` | `SMAppService` registration with a LaunchAgent fallback; single-instance guard. |
| `MenuBarIcon.swift` | Template image loading for the status item. |
| `SelfTest.swift` | Headless CLI: `--self-test`, `--presets`, `--live`, `--giphy-key`, `--giphy-upload`, `--login-item`, `--render-editor`, `--render-menu`. |

## Design rules that came out of debugging

These are the ones worth knowing before changing the UI (the full list lives in the skill that
maintains this app):

- **No `Form` rows with two controls.** SwiftUI pulls a `TextField` into the form's control column but
  leaves a `Picker`/`Button` at the row's trailing edge — three x positions in one card. The editor
  owns its own grid instead.
- **Rows align `.top`, never `.firstTextBaseline`**, because an image preview box has no text baseline
  and gets pushed below its label.
- **Preview images are pinned** (`.frame` + `.clipped()`, low hugging/compression resistance) — an
  `NSImageView` otherwise reports the image's natural size as its fitting size.
- **Verify UI as pixels**: `--render-editor out.png [w h]` renders the real view off-screen, so layout
  can be measured without Screen Recording permission.
- **Discord accepts activity types 0, 2, 3, 5 only.** Type 1 (Streaming) is rejected with a generic
  `code 4000`, so the picker does not offer it.
