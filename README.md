# Discord RP

Native macOS menu bar app for **custom Discord Rich Presence** — a from-scratch Swift
implementation, *not* a port of [CustomRP](https://github.com/maximmax42/Discord-CustomRP)
(which is C#/.NET WinForms and Windows-only).

**Status: implemented, building, and used daily.** Native Swift menu bar app, **93 unit tests** green
(`swift test`). Architecture: [docs/architecture.md](docs/architecture.md) · design handoff:
[docs/ui/](docs/ui/README.md) · release process: [docs/release.md](docs/release.md).

![The preset editor](docs/screenshots/editor.png)

<sub>The screenshots are renders of the built-in **demo preset set** (`scripts/seed-demo-presets.py`), not
of anyone's account: the Application ID is a placeholder and the preview images are public placeholder
photos. Regenerate them with the two `--render-*` commands under *Development*.</sub>

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

## Requirements

- macOS 14 or later
- The **Discord desktop app**, running (Rich Presence is set over a local socket)
- To build: a Swift 6-capable toolchain (Xcode 16+ or the Command Line Tools) and `git`

## Setup

1. Create an application at <https://discord.com/developers/applications> and copy its **Application ID**.
   Name it whatever you like — it is *your* application; see [docs/discord-setup.md](docs/discord-setup.md)
   for the portal steps and the image-asset upload.
2. Optionally upload images under *Art Assets* to use as `large_image`/`small_image` keys —
   or paste an https image URL directly (Discord's `mp:external` budget is 256 characters).
3. Build and install:

   ```bash
   git clone https://github.com/quangpao/discord-rp-mac
   cd discord-rp-mac
   ./scripts/build-app.sh --install --run
   ```

4. Enter your Application ID in the app: menu bar item → *Edit This Preset…* → **Connection → Apply**.
   Reconnect (or Apply) is what pushes the activity to Discord; it also works while Discord restarts.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Status stays red / "Invalid Client ID" | Wrong Application ID, or Discord is not running. Discord answers a bad id with an IPC close frame carrying `{"code":4000,"message":"Invalid Client ID"}`. |
| The activity does not show, but a game does | Discord shows one activity in the compact slot and auto-detected games win. Open your own profile to see the Rich Presence. |
| My buttons are invisible | By Discord's design buttons are only shown to *other* users, never to the account that set them. |
| Art asset list is empty | The assets are per-application: upload them under *Art Assets* in the portal, then press *Load from Discord*. |
| "Upload to Giphy…" is greyed out | No Giphy key yet — that is deliberate. Add yours in the *Giphy — bring your own key* card. |
| Giphy upload fails with 401/403 | The key was revoked or is wrong; save a new one. 429 means the 10-uploads-per-day quota. |
| An animated image key shows a still frame | Discord animates GIF/MP4 keys only in some clients; use a Giphy `media.giphy.com` URL or an uploaded MP4/GIF asset. |
| Nothing happens after sleep | The app reasserts the socket on wake; press *Reconnect* if Discord was restarted while asleep. |

## Uninstall / remove your data

```bash
# quit the app first (menu bar → Quit), then:
rm -rf "/Applications/Discord RP.app"
rm -rf "$HOME/Library/Application Support/DiscordRPMac"
rm -rf "$HOME/Library/Logs/DiscordRP"
security delete-generic-password -s dev.quangpao.discordrp.giphy -a api-key 2>/dev/null || true
# and disable it in System Settings → General → Login Items if you enabled launch at login
```

## Bring your own key (Giphy)

The app ships **no API key of any kind**. If you want the "Upload to Giphy…" buttons to work, you
bring your own:

1. Create a key at <https://developers.giphy.com/dashboard/?create=true> (free).
2. Open the app → **Edit This Preset…** → card **“Giphy — bring your own key”** → paste it →
   **Save to Keychain**. Or from the terminal (the key is read from stdin, never from argv):
   `DiscordRPMac --giphy-key set` · check with `--giphy-key status` · remove with `--giphy-key clear`.

Where the key is looked up, in order:

| Source | Who sets it |
| --- | --- |
| macOS Keychain (`dev.quangpao.discordrp.giphy`) | the app, from the field above |
| `$GIPHY_API_KEY` | your shell / CI |
| `~/.giphy/api_key` | hand-written file, kept for scripting |

Notes: the key is **never** logged, never written into this repo, and never shown back to you (the
UI only reports which source supplied it). Uploads use **your** Giphy account, are **public** unless
you tick *Private on Giphy*, and a dashboard key allows **10 uploads per day**. The app keeps a local
history of what it uploaded (`~/Library/Application Support/DiscordRPMac/giphy-uploads.json`) because
Giphy's API cannot list your own uploads — especially not private ones.

**Not affiliated** with CustomRP (the Windows app by maximmax42, whose source was studied for protocol details), with Giphy, or with Discord. CustomRP is MIT-licensed; this is an independent macOS implementation.

## Development

The core library (`Sources/DiscordRP`) builds in **Swift 6 language mode** with strict concurrency.
The SwiftUI/AppKit executable target (`Sources/DiscordRPMac`) currently uses **Swift 5 language mode**
(`Package.swift`), because the SwiftUI/`NSApplication` bridging is not concurrency-clean yet; moving it
is tracked as follow-up work.

```bash
swift build                       # library + app
swift test                        # 93 tests (needs the Xcode-selected toolchain)
./scripts/build-app.sh            # bundle + ad-hoc sign into build/
./scripts/build-app.sh --install --run
swift run DiscordRPMac --self-test # headless checks that work with CommandLineTools only
DiscordRPMac --version | --login-item status | --live --app-id <ID>
DiscordRPMac --presets              # print the exact payload every stored preset would send
python3 scripts/seed-demo-presets.py   # (re)write the demo preset set
./scripts/bump-version.sh 1.0.1 2      # bump both version files (see docs/release.md)
```

The README screenshots are real renders of the real views — no Screen Recording permission needed,
and no personal data involved:

```bash
rm -rf /tmp/discordrp-demo
DISCORD_APP_ID=123456789012345678 \
DEMO_IMAGE_URL="https://picsum.photos/seed/discordrp/400" \
DEMO_SMALL_KEY="https://picsum.photos/seed/discordrp-small/200" \
python3 scripts/seed-demo-presets.py /tmp/discordrp-demo --force
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path('/tmp/discordrp-demo/settings.json'); s = json.loads(p.read_text())
s['appID'] = '123456789012345678'; p.write_text(json.dumps(s, indent=2, sort_keys=True) + '\n')
EOF
DiscordRPMac --render-editor docs/screenshots/editor.png 720 1500 --demo /tmp/discordrp-demo
DiscordRPMac --render-menu  docs/screenshots/menu.png  320  430 --demo /tmp/discordrp-demo
```

## Design / logo

The canonical mark is the **Activity Spark** from the Open Design logo sheet
(`docs/ui/discord-rp-logo-sheet.html`): a four-pointed sparkle with a satellite dot, amber `#F5A524`
on a `#2B1B02` ink. Decision (Kun): the **original geometry** is canonical everywhere — the menu bar
glyph and the silhouette inside the app-icon tile are the same shape, so the Dock and the menu bar
read as one logo.

| Asset | File | Used for |
|---|---|---|
| mark | `Resources/logo/c2-mark.svg` | menu bar template image (22 px / 44 px PNG pair in the bundle) |
| app icon | `Resources/logo/c2-appicon-hig.svg` | `Resources/AppIcon.icns` (squircle + gradient + keyline, mark centred by measurement) |
| micro variant | `Resources/logo/c2-mark-16.svg` | optically fattened version OD drew for 1x menu bars; **not used** — kept for non-retina displays |

Regenerating after a new design run:

```bash
python3 scripts/extract-svgs.py docs/ui/discord-rp-logo-sheet.html Resources/logo
python3 scripts/centre-appicon.py     # re-applies the measured geometry nudge to the icon mark
./scripts/make-menubar-icon.sh        # mark.svg  → MenuBarIcon.png + @2x (template, transparent)
./scripts/make-icns.sh               # appicon-hig.svg → AppIcon.icns
./scripts/build-app.sh --install --run
```

`scripts/svg-to-png.sh` rasterises any of these SVGs (it forces the small intrinsic size to the
requested one — without that, a 32 px viewBox lands as a speck in the corner of a 1024 px canvas).

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

## License

MIT — see [LICENSE](LICENSE). Third-party attribution and the CustomRP/Giphy/Discord disclaimers:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
