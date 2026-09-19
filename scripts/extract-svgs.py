#!/usr/bin/env python3
"""Extract the SVG marks from an Open Design logo-sheet artifact into Resources/logo/.

The artifact keeps the copy-source in `<pre data-code="#id" data-file="name.svg">` (empty, filled
by JS) while the real markup is the rendered `<svg id="id">` element. So: map id → file name from
the `<pre>` attributes, then lift the matching SVG element and write it out prefixed with the
concept number (c1-mark.svg, c2-mark-template.svg, …).

Usage: python3 scripts/extract-svgs.py <artifact.html> [output-dir]
"""
import pathlib
import re
import sys

if len(sys.argv) < 2:
    sys.exit("usage: extract-svgs.py <artifact.html> [output-dir]")

source = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "Resources/logo")
raw = source.read_text(encoding="utf-8")

# id → requested file name, and which concept the id belongs to (c1/c2/c3 prefix in the id).
targets = []
for attrs in re.findall(r"(?is)<pre([^>]*)>", raw):
    code = re.search(r'data-code="#([^"]+)"', attrs)
    name = re.search(r'data-file="([^"]+)"', attrs)
    if code and name:
        targets.append((code.group(1), name.group(1)))

if not targets:
    sys.exit("no data-code/data-file pairs found — is this a logo sheet?")


def svg_element(identifier: str) -> str | None:
    """Return the mark `<svg>` for `identifier`, nesting-aware.

    The id sits on a wrapper (`<span class="svg-box" id="c1-mark">`), so the mark is the FIRST
    `<svg>` *inside* that wrapper — searching backwards would pick up a decorative icon that
    happens to precede it.
    """
    start = raw.find(f'id="{identifier}"')
    if start < 0:
        return None
    start = raw.find("<svg", start)
    if start < 0:
        return None
    depth = 0
    index = start
    while index < len(raw):
        nxt = raw.find("<svg", index)
        close = raw.find("</svg>", index)
        if close < 0:
            return None
        if 0 <= nxt < close:
            depth += 1
            index = nxt + 4
            continue
        depth -= 1
        index = close + len("</svg>")
        if depth == 0:
            return raw[start:index]
    return None


out_dir.mkdir(parents=True, exist_ok=True)
written = []
missing = []

for identifier, name in targets:
    concept = re.match(r"(c\d+)", identifier)
    prefix = f"{concept.group(1)}-" if concept else ""
    markup = svg_element(identifier)
    if not markup:
        missing.append(identifier)
        continue
    target = out_dir / f"{prefix}{name}"
    target.write_text(markup.rstrip() + "\n", encoding="utf-8")
    written.append(target)

for target in written:
    print(f"wrote {target}  ({target.stat().st_size} bytes)")
print(f"{len(written)} file(s)" + (f", missing: {missing}" if missing else ""))
