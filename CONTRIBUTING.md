# Contributing

Thanks for taking a look. This is a small, single-purpose app: a native macOS menu bar agent that
sets a custom Discord Rich Presence. Bug reports and small, focused pull requests are welcome.

## Ground rules

- **Never commit an API key.** The app is BYOK: no key ships with it, and a Giphy key belongs in the
  macOS Keychain (the app's own UI) or in your own environment. CI fails on anything that looks like
  a 32-character key literal.
- **Never commit personal data.** No real Discord Application IDs, no personal Giphy URLs, no
  screenshots containing your account details. Use placeholders.
- **Commits and PR titles in English, one line, imperative** (`fix: …`, `feat: …`, `docs: …`).
- **Tests come with behaviour changes.** `swift test` must pass; new rules in `ActivityRules` or new
  resolution logic should get a unit test.
- **Keep the alignment rule** in the editor: one `label | control` row primitive, no `HStack`
  holding two controls inside a form row (see the comment at the top of `ActivityEditorView.swift`).

## Build and run

```bash
swift build                 # library + app (no Xcode project needed)
swift test                  # unit tests
./scripts/build-app.sh --install --run   # bundle into /Applications and launch
```

Requirements: macOS 14+, a Swift 6 toolchain (Xcode 16+ or Command Line Tools).

## Trying it without Discord

The protocol layer is tested against a fake IPC server (`Tests/DiscordRPTests/ClientAndEngineTests`),
so you can work on rules, payloads and persistence without the Discord client running. For the real
thing you need the Discord desktop app and your own Application ID (see the README).

## Reporting a bug

Please include: macOS version, whether the Discord client was running, the output of
`"/Applications/Discord RP.app/Contents/MacOS/DiscordRPMac" --self-test`, and the last lines of
`~/Library/Logs/DiscordRP/discord-rp.log`. That log contains the exact payload that was sent — it never
contains your API key.

## Headless CLI

The app binary doubles as a diagnostic tool. Every mode works without a window, and most of them need
no Discord client at all:

```bash
BIN="/Applications/Discord RP.app/Contents/MacOS/DiscordRPMac"
"$BIN" --version
"$BIN" --self-test                 # framing, socket locator, rules, preset store
"$BIN" --presets [support-dir]     # the exact SET_ACTIVITY payload per stored preset
"$BIN" --login-item status         # the real registration, not the stored flag
"$BIN" --giphy-key status|set|clear|migrate    # `set` reads the key from stdin, never argv
"$BIN" --giphy-upload <file> [--hidden]
"$BIN" --render-editor <out.png> [w h] [--demo <dir>] [--no-key]
"$BIN" --render-menu  <out.png> [w h] [--demo <dir>]
"$BIN" --live --app-id <ID>        # push a sample activity to the running client
```

## Regenerating the screenshots in the README

They are real renders of the real views — no Screen Recording permission needed, and no personal data,
because they are drawn from the built-in demo preset set (`--demo` swaps the store and shows a neutral
connected status):

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

The same `--render-editor` mode is how UI changes get verified as pixels instead of assumptions.
