#!/usr/bin/env bash
# Render Resources/AppIcon.icns from the designed SVG, with an SF Symbol fallback.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="build/icon-1024.png"
ICONSET="build/AppIcon.iconset"
SOURCE_SVG="${1:-}"

mkdir -p build
if [ -n "$SOURCE_SVG" ] && [ -f "$SOURCE_SVG" ]; then
  ./scripts/svg-to-png.sh "$SOURCE_SVG" "$MASTER" 1024
elif [ -f Resources/logo/c2-appicon-hig.svg ]; then
  echo "==> using Resources/logo/c2-appicon-hig.svg"
  ./scripts/svg-to-png.sh Resources/logo/c2-appicon-hig.svg "$MASTER" 1024
elif [ -f Resources/logo/c2-appicon.svg ]; then
  # Intentional fallback: keep the non-HIG app icon so older logo sheets can still build.
  echo "==> using Resources/logo/c2-appicon.svg"
  ./scripts/svg-to-png.sh Resources/logo/c2-appicon.svg "$MASTER" 1024
else
  # Intentional fallback: no designed logo yet, so use the SF Symbol renderer.
  swift scripts/render-icon.swift "$MASTER"
fi

# The renderer can come out at the backing scale; normalise to exactly 1024 px.
sips -z 1024 1024 "$MASTER" --out "$MASTER" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

emit() { # size, filename
  sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null
}
emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns"
sips -g pixelWidth -g pixelHeight Resources/AppIcon.icns | tail -2
