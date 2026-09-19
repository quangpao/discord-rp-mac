#!/usr/bin/env bash
# Build the menu bar template image from the canonical logo mark.
#
#   ./scripts/make-menubar-icon.sh [mark.svg]
#
# Canonical mark (Kun's call): the ORIGINAL Activity Spark geometry (`c2-mark.svg`) — the same
# silhouette that sits inside the app icon, so the menu bar and the Dock read as one logo.
# `c2-mark-16.svg` is the optically fattened variant OD drew for 1x menu bars; pass it explicitly
# if a non-retina display ever needs it.
#
# macOS wants a template image: pure alpha shapes, no colour, so it can recolour the glyph for a
# light bar, a dark bar and the selected state. We ship a 22 px @1x and a 44 px @2x PNG and let
# `Bundle.main.image(forResource:)` pick the right one.
set -euo pipefail
cd "$(dirname "$0")/.."

MARK="${1:-Resources/logo/c2-mark.svg}"
[ -f "$MARK" ] || MARK="Resources/logo/c2-mark-16.svg"
[ -f "$MARK" ] || { echo "missing mark: $MARK" >&2; exit 1; }

mkdir -p Resources
./scripts/svg-to-png.sh "$MARK" Resources/MenuBarIcon.png 22 transparent >/dev/null
./scripts/svg-to-png.sh "$MARK" Resources/MenuBarIcon@2x.png 44 transparent >/dev/null

echo "==> Resources/MenuBarIcon.png + MenuBarIcon@2x.png from $MARK"
sips -g pixelWidth -g pixelHeight Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png | grep -E "pixel|/Users"
