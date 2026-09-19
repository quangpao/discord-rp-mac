#!/usr/bin/env bash
# Render Resources/AppIcon.icns from an SF Symbol (no external assets, no design tools).
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="build/icon-1024.png"
ICONSET="build/AppIcon.iconset"

mkdir -p build
swift scripts/render-icon.swift "$MASTER"

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
