# customrp-mac

Native macOS menu bar app for **custom Discord Rich Presence** — a from-scratch Swift
implementation, *not* a port of [CustomRP](https://github.com/maximmax42/Discord-CustomRP)
(which is C#/.NET WinForms and Windows-only).

**Status: plan stage — no app source yet.** 19-task implementation plan:
`.hermes/plans/2026-09-20_004459-native-menubar-app.md`

## What it will be

- Real macOS app: Swift binary inside a `.app` bundle, `LSUIElement=1` (menu bar only, no Dock icon).
  No Python / Node / .NET runtime.
- Full Rich Presence editor: activity type, name, details/state (+ URLs), party size, five timestamp
  modes, large/small image key + text + URL, up to two link buttons.
- Named presets, asset-name dropdown from the Discord API, live apply (< 2 s), auto-reconnect,
  clear-on-quit, launch at login.
- Discord's own rules enforced with readable reasons (min 2 chars, 32-UTF-8-byte button labels,
  timestamp bounds, `mp:external` 256-char budget).

## Why not just CustomRP

CustomRP is Windows-only. The Discord Rich Presence transport is `AF_UNIX` + JSON frames, so a native
Swift app is both feasible and small. Design decisions are documented in the plan, including which
upstream behaviours were read out of its source and reused (and which were deliberately dropped, e.g.
its analytics).

## Setup (once implemented)

1. Create an application at <https://discord.com/developers/applications> and copy its **Application ID**.
2. Optionally upload images under *Art Assets* to use as `large_image`/`small_image` keys —
   or paste an https image URL directly.
3. Build and install: `./scripts/build-app.sh --install`.

## Disclaimer

This changes what your Discord profile displays. Use it at your own discretion with respect to
Discord's Terms of Service.
