#!/usr/bin/env bash
# Rasterise an SVG to a square PNG at the requested size.
#
#   ./scripts/svg-to-png.sh Resources/logo/c1-mark.svg build/c1-mark.png 512 [background]
#
# The SVGs from a design sheet carry small intrinsic width/height (32 px), so a naive rasteriser
# renders a tiny mark in the corner of a big canvas. We wrap the markup in a page that forces
# `svg { width: 100% }` and screenshot that — headless Chrome is preferred because it also
# resolves `currentColor`-free explicit hex fills exactly as the sheet does.
set -euo pipefail

SVG="${1:?usage: svg-to-png.sh <input.svg> <output.png> [size] [background]}"
PNG="${2:?usage: svg-to-png.sh <input.svg> <output.png> [size] [background]}"
SIZE="${3:-512}"
BACKGROUND="${4:-#ffffff}"

mkdir -p "$(dirname "$PNG")" build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MARKUP="$(cat "$SVG")"
if [ "$BACKGROUND" = "transparent" ]; then
  CSS_BG="transparent"
  CHROME_BG="00000000"
else
  CSS_BG="$BACKGROUND"
  CHROME_BG="FFFFFFFF"
fi
{
  echo "<!doctype html><html><head><meta charset=\"utf-8\"><style>"
  echo "html,body{margin:0;padding:0;background:${CSS_BG}}"
  echo "body>div{width:${SIZE}px;height:${SIZE}px;display:flex;align-items:center;justify-content:center}"
  echo "svg{width:100%;height:100%}"
  echo "</style></head><body><div>"
  echo "$MARKUP"
  echo "</div></body></html>"
} > "$TMP/wrap.html"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color="$CHROME_BG" \
    --screenshot="$PNG" --window-size="${SIZE},${SIZE}" "file://$TMP/wrap.html" >/dev/null 2>&1
elif command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w "$SIZE" -h "$SIZE" "$SVG" -o "$PNG"
else
  echo "no rasteriser available (install Chrome or rsvg-convert)" >&2
  exit 1
fi

sips -z "$SIZE" "$SIZE" "$PNG" --out "$PNG" >/dev/null
echo "==> $PNG"
sips -g pixelWidth -g pixelHeight "$PNG" | tail -2
