# `dist/discord`

These files are **checked in on purpose**: they are the images you upload to your own Discord
application in the Developer Portal (*General Information* → App Icon, *Rich Presence* → Art Assets),
and the animated GIF you would upload to Giphy if you want an animated image key.

Nothing here is loaded by the app at runtime — the app's own icon and menu bar glyph live in
`Resources/`. Keeping them in the repository means a stranger can set up their own application without
drawing anything, and means the icons the README shows are reproducible.

| File | Where it goes |
| --- | --- |
| `0-app-icon-square-1024.png` | Portal → *General Information* → App Icon (1024×1024, tile fills the frame) |
| `1-app-icon-1024.png` | Same, with the icon's own corner radius (use if the portal preview looks too tight) |
| `2-asset-logo-1024.png` | Portal → *Rich Presence* → Art Assets, as a large image key |
| `3-asset-small-512.png` | Same, as a small image key |
| `discord-rp-animated-logo.gif` | Upload to Giphy (or your own host) and paste the URL as an external image key |

Regenerate from the SVGs:

```bash
./scripts/make-icns.sh && ./scripts/make-menubar-icon.sh
python3 scripts/svg-to-png.sh Resources/logo/c2-mark.svg dist/discord/2-asset-logo-1024.png 1024
```

If you fork this and want a different look, replace these files rather than deleting the directory —
`docs/discord-setup.md` refers to them by name.
