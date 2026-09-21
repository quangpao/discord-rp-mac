#!/usr/bin/env bash
# Bump the app version everywhere it is written down. There is no generated source of truth yet:
# the version lives in Sources/DiscordRP/Version.swift (what the app prints) and in
# Resources/Info.plist (what macOS/Finder shows), and they must agree.
#
#   ./scripts/bump-version.sh 1.2.0        # build number defaults to a timestamp
#   ./scripts/bump-version.sh 1.2.0 7      # explicit build number
#
# Then follow docs/release.md (test, build, tag, release notes).
set -euo pipefail

VERSION="${1:-}"
BUILD="${2:-$(date +%Y%m%d%H%M)}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: bump-version.sh X.Y.Z [BUILD]" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

python3 - "$VERSION" "$BUILD" <<'PY'
import pathlib, re, sys

version, build = sys.argv[1], sys.argv[2]
changed = []

swift = pathlib.Path("Sources/DiscordRP/Version.swift")
text = swift.read_text()
new, count = re.subn(r'(static let string = ")[^"]+(")', rf'\g<1>{version}\g<2>', text, count=1)
if count != 1:
    sys.exit("Version.swift: could not find `static let string = \"…\"`")
swift.write_text(new)
changed.append(f"Version.swift → {version}")

plist = pathlib.Path("Resources/Info.plist")
text = plist.read_text()
new, count = re.subn(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)',
                     rf'\g<1>{version}\g<2>', text, count=1)
if count != 1:
    sys.exit("Info.plist: could not find CFBundleShortVersionString")
new, count = re.subn(r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)',
                     rf'\g<1>{build}\g<2>', new, count=1)
if count != 1:
    sys.exit("Info.plist: could not find CFBundleVersion")
plist.write_text(new)
changed.append(f"Info.plist → {version} ({build})")

print("\n".join(changed))
PY

echo
echo "Both files updated. Verify with:"
echo "  swift build -c release && \"\$(swift build -c release --show-bin-path)/DiscordRPMac\" --version"
