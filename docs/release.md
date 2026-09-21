# Release

## What ships today

Pushing a tag builds and publishes automatically:

```bash
./scripts/bump-version.sh 1.0.0 1     # tag and Info.plist version must agree — the workflow checks
git tag -a v1.0.0 -m v1.0.0 && git push origin v1.0.0
```

`.github/workflows/release.yml` then runs the tests, builds **`DiscordRP-<version>.dmg`** (with the app
and a `/Applications` symlink), writes a SHA-256 file, and creates the GitHub Release with the notes in
`.github/release-notes.md`.

The disk image is **ad-hoc signed, not notarized**, so Gatekeeper refuses the first launch on someone
else's Mac (`spctl -a -vvv -t exec` says `rejected` — verified locally). The release notes and the
`How to open.txt` inside the image both explain the two ways around it. Building from source is
recommended in the notes as the friction-free path.

To check the packaging without publishing anything:

```bash
./scripts/build-app.sh --dmg        # → build/DiscordRP-<version>.dmg, prints size + sha256
hdiutil attach build/DiscordRP-*.dmg -nobrowse -mountpoint /tmp/drpmount && ls /tmp/drpmount
hdiutil detach /tmp/drpmount
```

There is still no Homebrew cask and no auto-update.

## Cutting a release

1. Bump the version — it lives in two files and they must agree, so use the script:
   `./scripts/bump-version.sh X.Y.Z [BUILD]`
   (that is `Sources/DiscordRP/Version.swift` and `Resources/Info.plist`'s
   `CFBundleShortVersionString` / `CFBundleVersion`). The release workflow refuses a tag that does not
   match `CFBundleShortVersionString`.
2. `swift test` — must be green (currently 101 tests).
3. Optional but recommended: `./scripts/build-app.sh --dmg`, then mount the image and confirm the app
   inside launches and that the version in the Finder/Get Info matches the tag.
4. `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z` — the workflow publishes the release.
5. Read the published release: the notes come from `.github/release-notes.md`, the asset list should be
   `DiscordRP-X.Y.Z.dmg` + `sha256.txt`.

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
