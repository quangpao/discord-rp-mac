#!/usr/bin/env python3
"""Centre the Activity Spark lockup inside the tile of `c2-appicon-hig.svg`.

Measured on the shipped .icns (512 px render): the mark's bbox centre sat 12 px left and 9 px
below the tile centre — the area centroid was centred, but the *shape* read low-left, which two
independent visual reviews flagged. In the SVG's 1024-unit space that is +23.2 / −19.5 units on
the mark group. Equal margins on all four sides is the target.

Re-run this after any `scripts/extract-svgs.py` refresh of the file (the sheet does not carry the
nudge).
"""
import pathlib
import re
import sys

SVG = pathlib.Path("Resources/logo/c2-appicon-hig.svg")
# Original from the design sheet, then the first nudge, then the final one (vertical top-up).
OLD_VARIANTS = [
    "translate(112.32 161.08) scale(17.2824)",
    "translate(135.52 141.58) scale(17.2824)",
]
NEW = "translate(135.52 134.58) scale(17.2824)"
NOTE = ("<!-- geometry nudge applied by scripts/centre-appicon.py: mark group shifted "
        "+23.2/-26.5 units so the lockup bbox margins are equal (measured on the built .icns). -->")

text = SVG.read_text()
if NEW in text:
    print("nudge already applied")
    sys.exit(0)
matched = next((variant for variant in OLD_VARIANTS if variant in text), None)
if matched is None:
    sys.exit("expected mark transform not found — the design changed, re-measure before patching")

count = text.count(matched)
text = text.replace(matched, NEW)
text = text.replace('              <g id="drpIconArt">',
                    '              ' + NOTE + '\n              <g id="drpIconArt">', 1)
SVG.write_text(text)
print(f"patched {count} mark group(s) and added the note")
