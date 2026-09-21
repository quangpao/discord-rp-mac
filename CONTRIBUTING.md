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
`~/Library/Logs/DiscordRP/customrp.log`. That log contains the exact payload that was sent — it never
contains your API key.
