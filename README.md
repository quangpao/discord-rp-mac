# Discord RP

[![CI](https://github.com/quangpao/discord-rp-mac/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/quangpao/discord-rp-mac/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/quangpao/discord-rp-mac)](https://github.com/quangpao/discord-rp-mac/releases/latest)
[![License: MIT](https://img.shields.io/github/license/quangpao/discord-rp-mac)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Bring your own key](https://img.shields.io/badge/keys-BYOK-informational)

A native macOS menu bar app that sets a **custom Discord Rich Presence**: your activity, images, an
elapsed timer and up to two link buttons, kept alive while you work. Written from scratch in Swift
(SwiftUI + AppKit) — a ~2 MB app bundle, no Electron, no runtime to install.

![The preset editor](docs/screenshots/editor.png)

## Features

- **Full activity editor** — type, display type, name, details and state with links, party size, five
  timestamp modes, large/small images with text and link, up to two buttons.
- **Named presets**, switched from the menu bar; image keys are listed from your own Discord
  application.
- **Keeps the presence alive** — 15 s keepalive, backoff 2/5/10/30 s, reconnects after sleep, clears
  the presence when you quit.
- **Menu bar only** (`LSUIElement`, no Dock icon), single instance, optional launch at login.
- **Discord's own limits enforced up front**, with readable reasons instead of silent failures.
- **No telemetry, no account, no bundled keys** — presence travels over the local Discord IPC socket.

## Requirements

- macOS 14 or later
- The **Discord desktop app**, running
- To build from source: a Swift 6 toolchain (Xcode 16+ or the Command Line Tools) and `git`

## Install

**Download** — take the `.dmg` from [Releases](https://github.com/quangpao/discord-rp-mac/releases/latest)
and drag the app to Applications. The build is **not notarized**, so macOS asks once before the first
launch — the exact steps are in the [wiki FAQ](https://github.com/quangpao/discord-rp-mac/wiki/FAQ).

**Build from source** — no Gatekeeper involvement:

```bash
git clone https://github.com/quangpao/discord-rp-mac
cd discord-rp-mac
./scripts/build-app.sh --install --run
```

## Configure

The app works immediately: a fresh install uses this project's application, so pressing **Apply** in
**Edit This Preset… → Connection** is all it takes to push the activity to Discord (it also recovers a
connection Discord dropped).

For your own name, icon and art assets, create an application in the
[Discord Developer Portal](https://discord.com/developers/applications) and paste its **Application
ID** in the same card — the walkthrough, including art assets, is in **[wiki: Setup](https://github.com/quangpao/discord-rp-mac/wiki/Setup)**.

![The menu bar menu](docs/screenshots/menu.png)

## Giphy key

The app ships **no API keys**. *Upload to Giphy…* needs your own free key
(<https://developers.giphy.com/dashboard/?create=true>), pasted in **Edit This Preset… → “Giphy —
bring your own key” → Save to Keychain**; `$GIPHY_API_KEY` and `~/.giphy/api_key` also work. The key is
never logged, never committed and never shown back — **[wiki: Giphy key](https://github.com/quangpao/discord-rp-mac/wiki/Giphy-key)** covers the
lookup order, what an upload sends, quota and the local upload history.

## Troubleshooting

Check the status line in the app (green means connected) and press **Apply** once. The common cases —
one activity slot, a red status or *Invalid Client ID*, buttons invisible to you, a greyed-out Giphy
upload, sleep, Gatekeeper, whether it is safe — are answered in **[wiki: FAQ](https://github.com/quangpao/discord-rp-mac/wiki/FAQ)**.

## Uninstall

Quit it from the menu bar, delete the app, then remove its data and its Keychain item — the commands,
plus what was stored where, are in **[wiki: Uninstall](https://github.com/quangpao/discord-rp-mac/wiki/Uninstall)**.

## Limitations

- Around 75 MB resident. That is the SwiftUI/AppKit baseline, not a leak; getting under 30 MB would
  mean rebuilding the menu with a raw `NSStatusItem`/`NSMenu`.
- The name and icon on the activity card come from *your* Discord application — the app only fills the
  fields Discord exposes.
- Party size, secrets and game auto-detection are intentionally out of scope.

## Development

```bash
swift build && swift test         # unit tests (needs the Xcode-selected toolchain)
./scripts/build-app.sh --dmg      # → build/DiscordRP-<version>.dmg, prints size + sha256
./scripts/bump-version.sh 1.0.1   # bump both version files before tagging
```

Conventions, the headless CLI flags and how the screenshots in this file are regenerated:
[CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

| | |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | module map, and the protocol findings that shaped the code |
| [Wiki](https://github.com/quangpao/discord-rp-mac/wiki) | user guide: setup, FAQ, Giphy key, images, uninstall |
| [docs/release.md](docs/release.md) | versioning, tagging, signing and notarization |
| [docs/ui/README.md](docs/ui/README.md) | logo assets, icon pipeline, design artifacts |
| [SECURITY.md](SECURITY.md) | what is stored, what is sent, how to report a problem |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | attribution and disclaimers |

## Privacy

No telemetry, no analytics, no auto-update and no server run by this project. Rich Presence goes over
the local Discord IPC socket; the only network calls are the ones you trigger — listing your own
application's assets, loading an image preview, and uploading to Giphy with your key. What is stored,
and where, is listed in [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Giphy or Discord; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
