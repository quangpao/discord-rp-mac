# Discord RP

[![CI](https://github.com/quangpao/discord-rp-mac/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/quangpao/discord-rp-mac/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/quangpao/discord-rp-mac)](https://github.com/quangpao/discord-rp-mac/releases/latest)
[![License: MIT](https://img.shields.io/github/license/quangpao/discord-rp-mac)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Bring your own key](https://img.shields.io/badge/keys-BYOK-informational)

A native macOS menu bar app that sets a **custom Discord Rich Presence**: your activity, images, an
elapsed timer and up to two link buttons, kept alive while you work. Written from scratch in Swift
(SwiftUI + AppKit) — a ~2 MB app bundle, no Electron, no runtime to install.

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

## Development

```bash
swift build && swift test         # unit tests (needs the Xcode-selected toolchain)
./scripts/build-app.sh --dmg      # → build/DiscordRP-<version>.dmg, prints size + sha256
./scripts/bump-version.sh 1.0.1   # bump both version files before tagging
```

Conventions, the headless CLI flags and how the screenshot in this file is regenerated:
[CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

| | |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | module map, and the protocol findings that shaped the code |
| [Wiki](https://github.com/quangpao/discord-rp-mac/wiki) | user guide — [Setup](https://github.com/quangpao/discord-rp-mac/wiki/Setup) · [FAQ](https://github.com/quangpao/discord-rp-mac/wiki/FAQ) · [Giphy key](https://github.com/quangpao/discord-rp-mac/wiki/Giphy-key) · [Images](https://github.com/quangpao/discord-rp-mac/wiki/Images) · [Uninstall](https://github.com/quangpao/discord-rp-mac/wiki/Uninstall) |
| [docs/release.md](docs/release.md) | versioning, tagging, signing and notarization |
| [docs/ui/README.md](docs/ui/README.md) | logo assets, icon pipeline, design artifacts |
| [CHANGELOG.md](CHANGELOG.md) | what changed in each release |
| [SECURITY.md](SECURITY.md) | what is stored, what is sent, how to report a problem |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | attribution and disclaimers |

## Privacy

No telemetry, no analytics, no auto-update, no server. The only network calls are the ones you trigger;
what is stored, and what is sent, is in [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Giphy or Discord; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
