# Design artifacts

These files are **design handoff artifacts**, not application source. Nothing here is loaded at
runtime and nothing here is normative for behaviour — if a spec and the app disagree, the app's
behaviour (and its tests) wins, and this directory should be updated.

| File | What it is |
| --- | --- |
| `discord-rp-editor-window-spec.html` (+ `-spec.txt`) | Window/editor layout handoff used to rebuild `ActivityEditorView.swift` (2-tier rows, fixed label column, pinned footer). |
| `discord-rp-menu-spec.html` | Menu layout handoff. |
| `discord-rp-logo-sheet.html` | Logo exploration sheet; the canonical mark geometry was extracted from it. |

## Canonical assets

The shipped assets are **not** these HTML files — they are:

- `Resources/logo/c2-mark.svg` → `Resources/MenuBarIcon.png` + `@2x` (menu bar template image)
- `Resources/logo/c2-appicon-hig.svg` → `Resources/AppIcon.icns`
- `dist/discord/*` → the PNG/GIF files to upload to your own Discord application (app icon, art
  assets) and to Giphy if you want an animated image key

Regeneration commands are in the README ("Design / logo").
