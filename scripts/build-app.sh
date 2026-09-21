#!/usr/bin/env bash
# Build the native binary, wrap it in a real .app bundle, sign it ad-hoc and (optionally)
# install/run it. No Xcode project, no interpreter, no external runtime.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="Discord RP"
EXECUTABLE="DiscordRPMac"
BUNDLE_ID="dev.quangpao.discordrp"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

RUN=0
INSTALL=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --install) INSTALL=1; RUN=1 ;;
    --dmg) DMG=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$EXECUTABLE"
[ -x "$BIN" ] || { echo "missing binary: $BIN" >&2; exit 1; }

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Menu bar template image (22 px @1x / 44 px @2x). The app falls back to an SF Symbol when absent.
for icon in MenuBarIcon.png MenuBarIcon@2x.png; do
  if [ -f "$ROOT/Resources/$icon" ]; then
    cp "$ROOT/Resources/$icon" "$APP_BUNDLE/Contents/Resources/$icon"
  fi
done

# A status app with a Dock icon is the classic tell that it is not native — refuse to ship that.
if ! /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
  echo "ERROR: Info.plist is missing LSUIElement" >&2
  exit 1
fi

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" >/dev/null
fi

echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'

echo "==> signature"
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier" | sed 's/^/    /'

# A .dmg for people who will not build from source. It is **not notarized**, so Gatekeeper will warn
# on first open — the note inside the disk image says exactly what to do about it. `--dmg` is what the
# release workflow uses on a tag; run it locally to check the packaging without publishing anything.
if [ "$DMG" = "1" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
  DMG_PATH="$BUILD_DIR/DiscordRP-$VERSION.dmg"
  STAGE="$BUILD_DIR/dmg-stage"
  echo "==> packaging $DMG_PATH"
  rm -rf "$STAGE" "$DMG_PATH"
  mkdir -p "$STAGE"
  cp -R "$APP_BUNDLE" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cat > "$STAGE/How to open.txt" <<EOF
Discord RP $VERSION — unsigned build

This app is not notarized by Apple, so macOS will refuse the first launch with
"Apple could not verify ... is free of malware" (or "is damaged").

To open it:
  1. Drag "Discord RP.app" onto the Applications folder in this window.
  2. Open it once from Applications and let macOS refuse.
  3. Go to System Settings > Privacy & Security, scroll down, and click
     "Open Anyway" next to the Discord RP message.
  4. Or, from a terminal:  xattr -dr com.apple.quarantine "/Applications/Discord RP.app"

Building from source avoids all of this:
  git clone https://github.com/quangpao/discord-rp-mac && cd discord-rp-mac
  ./scripts/build-app.sh --install --run
EOF
  hdiutil create -volname "Discord RP" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGE"
  echo "    $(du -h "$DMG_PATH" | cut -f1)  $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
  echo "    $DMG_PATH"
fi

if [ "$INSTALL" = "1" ]; then
  echo "==> installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  APP_BUNDLE="/Applications/$APP_NAME.app"
fi

echo "==> built $APP_BUNDLE"
if [ "$RUN" = "1" ]; then
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  # Replacing the bundle under LaunchServices' feet can make `open` fail with -600
  # (procNotFound). Re-register the bundle and retry once — this bit us twice.
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1
  sleep 1
  if ! open "$APP_BUNDLE" 2>/dev/null; then
    echo "    open failed once, re-registering and retrying"
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1
    sleep 2
    open "$APP_BUNDLE" || true
  fi
  sleep 1
  echo "==> running:"
  pgrep -lx "$EXECUTABLE" || echo "    (not running?)"
fi
