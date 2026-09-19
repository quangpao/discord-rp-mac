# customrp-mac

Native macOS menu bar app for **custom Discord Rich Presence** — a from-scratch Swift
implementation, *not* a port of [CustomRP](https://github.com/maximmax42/Discord-CustomRP)
(which is C#/.NET WinForms and Windows-only).

**Status: implemented and building.** Native Swift menu bar app, 44 unit tests green, installed at
`/Applications/CustomRP.app`. Implementation notes and deviations: `.hermes/plans/2026-09-20_004459-native-menubar-app.md`.
Menu/editor design spec (Open Design): `docs/ui/customrp-menu-spec.html`.

## What it does

- Real macOS app: single Swift binary in a `.app` bundle, `LSUIElement=1` (menu bar only, no Dock
  icon). No Python / Node / .NET runtime, no Electron.
- Full Rich Presence editor: activity type, status display type, name, details/state (+ links),
  party size, five timestamp modes, large/small image key + text + link, up to two link buttons.
- Named presets, image-asset dropdown fetched from the Discord API, live apply, auto-reconnect
  (15 s keepalive, backoff 2/5/10/30 s), presence cleared on quit, launch at login
  (`SMAppService`, with a LaunchAgent fallback).
- Discord's own rules are enforced with readable reasons: min 2 characters for details/state,
  32-UTF-8-byte button labels, timestamps clamped to `1970-01-01T00:00:01Z … 5138-11-16T09:46:39Z`,
  `mp:external` image budget ≤ 256 characters, party only for *Playing*, no timestamps for
  *Competing*, zero-width-space guard for a leading non-breaking space.

## Why not just CustomRP

CustomRP is Windows-only. The Discord Rich Presence transport is `AF_UNIX` + JSON frames, so a native
Swift app is both feasible and small. Design decisions are documented in the plan, including which
upstream behaviours were read out of its source and reused (and which were deliberately dropped, e.g.
its analytics).

## Setup

1. Create an application at <https://discord.com/developers/applications> and copy its **Application ID**.
2. Optionally upload images under *Art Assets* to use as `large_image`/`small_image` keys —
   or paste an https image URL directly (Discord's `mp:external` budget is 256 characters).
3. Enter the ID in the app: menu bar item → *Edit This Preset…* → **Connection → Apply**.
4. Build and install: `./scripts/build-app.sh --install`. Icon: `./scripts/make-icns.sh`.

## Development

```bash
swift build                       # library + app
swift test                        # 44 tests (needs the Xcode-selected toolchain)
./scripts/build-app.sh            # bundle + ad-hoc sign into build/
./scripts/build-app.sh --install --run
swift run CustomRPMac --self-test # headless checks that work with CommandLineTools only
CustomRPMac --version | --login-item status | --live --app-id <ID>
```

## Known gaps

- **Memory**: ~74 MB resident, not the < 30 MB the plan assumed. That is SwiftUI/AppKit baseline
  (shared framework pages count in RSS). Dropping to that figure means rewriting the menu with a raw
  `NSStatusItem`/`NSMenu` and no SwiftUI in the menu path.
- Image-only *presence appearance* (custom Discord app name/icon in the activity card) depends on
  what the Discord application is named — the app id you supply is what Discord shows.
- Party, secrets and game auto-detection are intentionally out of scope.

## Findings worth keeping

- Discord answers an invalid Application ID with an IPC **CLOSE frame (opcode 2) carrying
  `{"code":4000,"message":"Invalid Client ID"}`** — not the `evt: ERROR` frame the docs describe.
  Verified against the live client; the docs-only implementation silently looked like a timeout.
- The upstream CustomRP ships its own public Application ID as a fallback. This project deliberately
  does **not** reuse it (the activity would render as *CustomRP* with *their* assets).
- CustomRP's rules were transcribed from its source, not guessed: min 2 chars
  (`MainForm.cs:1658`), byte-counted button labels (`:1656`), timestamp window (`:371-376`),
  external-image budget (`:955-958`), type restrictions (`:1607-1616`).

## Disclaimer

This changes what your Discord profile displays. Use it at your own discretion with respect to
Discord's Terms of Service.
