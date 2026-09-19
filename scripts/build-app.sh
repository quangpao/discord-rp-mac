#!/usr/bin/env bash
# Build the native binary, wrap it in a real .app bundle, sign it ad-hoc and (optionally)
# install/run it. No Xcode project, no interpreter, no external runtime.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="CustomRP"
EXECUTABLE="CustomRPMac"
BUNDLE_ID="dev.kun.customrp"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

RUN=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --install) INSTALL=1; RUN=1 ;;
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

if [ "$INSTALL" = "1" ]; then
  echo "==> installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
  APP_BUNDLE="/Applications/$APP_NAME.app"
fi

echo "==> built $APP_BUNDLE"
if [ "$RUN" = "1" ]; then
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  open "$APP_BUNDLE"
  sleep 1
  echo "==> running:"
  pgrep -lx "$EXECUTABLE" || echo "    (not running?)"
fi
