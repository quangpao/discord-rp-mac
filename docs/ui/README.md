# Design artifacts

These files are **design handoff artifacts**, not application source. Nothing here is loaded at
runtime and nothing here is normative for behaviour — if a spec and the app disagree, the app's
behaviour (and its tests) wins, and this directory should be updated. The editor's own handoff spec was
deleted once `ActivityEditorView.swift` had been rebuilt from it and then moved on; the code is the
reference now.

| File | What it is |
| --- | --- |
| `discord-rp-menu-spec.html` | Menu layout handoff. |
| `discord-rp-logo-sheet.html` | Logo exploration sheet (three concepts). Only the canonical **c2** round ships — `scripts/extract-svgs.py` extracts just that one unless you pass `--all`. |

## Canonical assets

The shipped assets are **not** these HTML files — they are:

- `Resources/logo/c2-mark.svg` → `Resources/MenuBarIcon.png` + `@2x` (menu bar template image)
- `Resources/logo/c2-appicon-hig.svg` → `Resources/AppIcon.icns`
- `dist/discord/*` → the PNG/GIF files to upload to your own Discord application (app icon, art
  assets) and to Giphy if you want an animated image key

## Canonical mark and regeneration

The canonical mark is the **Activity Spark** from the logo sheet: a four-pointed sparkle with a
satellite dot, amber `#F5A524` on `#2B1B02` ink. The same geometry is used everywhere on purpose — the
menu bar glyph and the silhouette inside the app-icon tile are one logo, so the Dock and the menu bar
read as the same thing.

| Asset | File | Used for |
| --- | --- | --- |
| mark | `Resources/logo/c2-mark.svg` | menu bar template image (22 px / 44 px PNG pair in the bundle) |
| app icon | `Resources/logo/c2-appicon-hig.svg` | `Resources/AppIcon.icns` (squircle + gradient + keyline, mark centred by measurement) |
| micro variant | `Resources/logo/c2-mark-16.svg` | optically fattened variant for 1x menu bars; not used by default, kept for non-retina displays |

```bash
python3 scripts/extract-svgs.py docs/ui/discord-rp-logo-sheet.html Resources/logo
python3 scripts/centre-appicon.py      # re-applies the measured geometry nudge to the icon mark
./scripts/make-menubar-icon.sh         # mark.svg       → MenuBarIcon.png + @2x (template, transparent)
./scripts/make-icns.sh                 # appicon-hig.svg → AppIcon.icns
./scripts/build-app.sh --install --run
```

`scripts/svg-to-png.sh` rasterises any of these SVGs. It forces the SVG's small intrinsic size up to
the requested one — without that, a 32 px viewBox lands as a speck in the corner of a 1024 px canvas.

