# Release

## What ships today

**Source-only.** There is no signed or notarized download, no Homebrew cask and no auto-update. A
release is a git tag plus a GitHub Release whose notes tell people to build from source:

```bash
git clone https://github.com/quangpao/discord-rp-mac
cd discord-rp-mac
./scripts/build-app.sh --install --run
```

Unsigned binaries are deliberately **not** attached: an ad-hoc signed `.app` downloaded from a browser
hits Gatekeeper and teaches users to bypass it, which is worse than asking them to build.

## Cutting a release

1. Bump the version in **both** places (they are the only two sources):
   - `Sources/DiscordRP/Version.swift`
   - `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`)
2. `swift test` — must be green (currently 93 tests).
3. `./scripts/build-app.sh --install --run`, then confirm the menu bar item appears and a preset
   applies against a running Discord client.
4. `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`
5. GitHub → Releases → draft a release on that tag. Title `vX.Y.Z`; body: what changed, any migration
   note, and the build-from-source instructions above.

## If signed binaries are added later

Requires a Developer ID certificate and a notarytool keychain profile:

```bash
./scripts/build-app.sh                       # builds build/Discord RP.app (ad-hoc)
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAMID>)" "build/Discord RP.app"
ditto -c -k --keepParent "build/Discord RP.app" "DiscordRP-vX.Y.Z.zip"
xcrun notarytool submit "DiscordRP-vX.Y.Z.zip" --keychain-profile <profile> --wait
xcrun stapler staple "build/Discord RP.app"
spctl -a -vvv -t install "build/Discord RP.app"   # must say: accepted, source=Notarized Developer ID
```

Then a Homebrew cask becomes possible (`url` + `sha256` + `app "Discord RP.app"`), with `zap` entries
for `~/Library/Application Support/DiscordRPMac` and `~/Library/Logs/DiscordRP`.

## Compatibility promise

Before 1.0: only the latest tag and `main` are supported. Presets are plain JSON with no schema
version yet, so a future format change ships with a migration (the rename migration in
`Sources/DiscordRP/Migration.swift` is the pattern: copy, never move).
