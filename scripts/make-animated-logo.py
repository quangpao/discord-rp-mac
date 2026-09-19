#!/usr/bin/env python3
"""Render the frames of an animated Activity Spark: the mark breathes, the satellite dot orbits.

Frames are written as PNGs (Chrome-rendered from generated SVG) ready for GIF/WebP assembly.
Usage: python3 scripts/make-animated-logo.py [outdir] [frames] [size]
"""
import pathlib
import subprocess
import sys

outdir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/anim")
frames = int(sys.argv[2] if len(sys.argv) > 2 else 30)
size = int(sys.argv[3] if len(sys.argv) > 3 else 512)
outdir.mkdir(parents=True, exist_ok=True)

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# Palette from the logo sheet: amber tile, deep ink mark.
TILE_TOP, TILE_BOTTOM, INK = "#F5A524", "#C97C10", "#2B1B02"

# Source geometry of the mark (32-unit space, from c2-mark.svg).
SPARKLE = "M16 3 Q18.4 13.6 29 16 Q18.4 18.4 16 29 Q13.6 18.4 3 16 Q13.6 13.6 16 3 Z"
DOT = (25.5, 5.5, 3.2)  # cx, cy, r


def frame_svg(index: int, total: int) -> str:
    import math

    phase = index / total * 2 * math.pi
    # breathing: 100% → 94% → 100%, around the mark's own centre
    scale = 1.0 - 0.06 * (0.5 - 0.5 * math.cos(phase))
    # the dot floats a little around its rest position (1.3 units on a 32-unit canvas) so nothing
    # ever leaves the tile: rest (25.5, 5.5) → x 24.2…26.8, y 4.2…6.8.
    dot_x = 1.3 * math.cos(phase)
    dot_y = 1.3 * math.sin(phase)
    # mark fills 55% of the tile, centred — same proportion as the app icon
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{TILE_TOP}"/>
      <stop offset="1" stop-color="{TILE_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect width="32" height="32" fill="url(#tile)"/>
  <g transform="translate(7.2 7.2) scale(0.55)">
    <g transform="translate(16 16) scale({scale:.4f}) translate(-16 -16)">
      <path d="{SPARKLE}" fill="{INK}"/>
    </g>
    <circle cx="{DOT[0] + dot_x:.3f}" cy="{DOT[1] + dot_y:.3f}" r="{DOT[2]}" fill="{INK}"/>
  </g>
</svg>'''


wrap = outdir / "frame.html"
(  # rendered once per frame, inline
    outdir / "frame.svg"
).write_text(frame_svg(0, frames))

for index in range(frames):
    (outdir / "frame.svg").write_text(frame_svg(index, frames))
    (outdir / "frame.html").write_text(
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        "html,body{margin:0;background:transparent}svg{display:block;width:100%;height:100%}"
        "</style></head><body>"
        + frame_svg(index, frames)
        + "</body></html>"
    )
    target = outdir / f"frame-{index:02d}.png"
    # Chrome needs an absolute file:// URL — a relative path silently renders an error page,
    # which is how the first GIF ended up being 30 screenshots of ERR_INVALID_URL.
    page = (outdir / "frame.html").resolve()
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
         "--force-device-scale-factor=1", "--default-background-color=00000000",
         f"--screenshot={target.resolve()}", f"--window-size={size},{size}",
         f"file://{page}"],
        check=False, capture_output=True,
    )
    if not target.exists():
        sys.exit(f"frame {index} failed to render")

print(f"{frames} frames → {outdir} ({size}×{size})")
