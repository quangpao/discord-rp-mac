# Discord setup — make the profile card look intentional

Everything here happens in the Discord Developer Portal; the app only needs the Application ID and
the asset **names** you choose. Files to upload are pre-rendered in `dist/discord/`.

## What the app shows today

| Field | Source | Current demo value |
|---|---|---|
| card name (byline) | the activity `name` field | `CustomRP by quangpao` (overrides the portal app name) |
| big image | `large_image` key **or** an https URL | `https://github.com/quangpao.png` (used because no art asset is uploaded yet) |
| subtitle | `details` (with `status_display_type = details`) | `Đang code` |
| second line | `state` | `customrp-mac` |
| buttons | up to 2 label/URL pairs | `quangpao.dev`, `GitHub` |

If no `large_image` is set, Discord falls back to the **application icon** from the portal — which is
why an app with no uploaded icon shows Discord's grey "?" placeholder.

## Step 1 — General Information

1. Open <https://discord.com/developers/applications> and pick your app (ID `1041550572223995925`).
2. **General Information**:
   - **Name** — this is what Discord shows when the activity has no `name` override. `CustomRP` is the
     clean choice; `CustomRP by quangpao` also works if you want the credit line here instead.
   - **App Icon** — drag `dist/discord/0-app-icon-square-1024.png` (1024×1024, tile filling the frame).
   - **Description / Tags** — fill anything sensible; the portal wants a description before it lets
     you save some fields.
   - **Save Changes**.
3. Wait a few minutes: new icons and assets propagate through Discord's cache.

> The app's `name` field wins over the portal name. To let the portal name show on the card, open the
> editor and clear **“Shown as (Discord app name)”**, then Apply.

## Step 2 — Rich Presence → Art Assets

1. Left sidebar → **Rich Presence** → **Art Assets**.
2. **Add Image(s)** and upload, one at a time. Discord defaults the asset name to the **file name**,
   so the keys currently in use are:
   | File | Asset name Discord assigned (this is the key) | Used as |
   |---|---|---|
   | `dist/discord/2-asset-logo-1024.png` | `2-asset-logo-1024` | `large_image` |
   | `dist/discord/3-asset-small-512.png` | `3-asset-small-512` | `small_image` (small overlay on the big image) |
   Renaming them in the portal (to e.g. `logo` / `mark`) is cosmetic — the card never shows the key —
   but then every preset must be pointed at the new keys.
3. **Save Changes**, then wait a few minutes.
4. Sanity check from the shell — the same call the app's “Load asset names” button makes:
   ```bash
   curl -s https://discord.com/api/oauth2/applications/1041550572223995925/assets
   ```
   Assets appear as `[{"name":"logo",...}]`. An empty `[]` means they have not landed yet.

Portal accepts PNG/JPG at ≥512×512; the files here are 512–1024 px and 10–282 KB, so they pass.

## Step 3 — Point the presets at the assets

Menu bar item → **Edit This Preset…** (or ⌘,):

- **Images → Large key**: `2-asset-logo-1024` · **Large text**: `quangpao` (leave *Large link* empty if
  you do not want the image clickable)
- **Images → Small key**: `3-asset-small-512` · **Small text**: whatever short label you want
- **Load asset names** opens a dropdown of the portal's assets — use it to confirm the key spelling.
- **Apply** pushes immediately; the card updates in about two seconds.

Alternatively set the keys by hand in
`~/Library/Application Support/CustomRPMac/presets.json` (`largeKey` / `smallKey`) and restart the app.

## Animated images (GIF / animated WebP / AVIF)

Discord's rule (docs.discord.com · Rich Presence → Setting Rich Presence):

> Uploaded assets (added via the developer portal) support PNG, JPEG, and WebP only — **animated images
> are not supported for uploaded assets**. Unlike uploaded assets, **external URLs also support GIF,
> animated WebP, and AVIF**.

So an animated card image has exactly one route: an **https URL**, not a portal upload. The app already
ships one, built from our own mark:

```bash
python3 scripts/make-animated-logo.py build/anim 30 512     # 30 frames: sparkle breathes, dot floats
swift scripts/frames-to-gif.swift build/anim dist/discord/customrp-animated-logo.gif 15
```

Then host the file somewhere public and use that URL as the image key. Current host:
`https://raw.githubusercontent.com/quangpao/customrp-assets/main/customrp-animated-logo.gif`
(public repo `quangpao/customrp-assets`; 90 chars, `mp:external` budget ≈ 135/256).

Caveats worth knowing before shipping an animation:

- Discord **caches** external images; a changed file at the same URL may not refresh quickly — version
  the filename (`…-logo-v2.gif`) when you replace it.
- Keep it small and slow: 512×512, ~2 s loop, well under ~1 MB. A 15 fps loop of 30 frames is ~70 KB.
- The URL must stay publicly reachable forever — delete the repo and the card image breaks.
- Uploaded assets remain the better choice for a static image (no external dependency).

## Buttons are invisible to you (by design)

Discord's own documentation, Rich Presence → *Setting Buttons*:

> **Buttons are only visible to other users — you cannot see buttons on your own Rich Presence.**

CustomRP's FAQ says the same thing ("you can't see your own buttons, but others will see them"). So a missing
button on your own profile card is **not** a payload bug — the app sends them correctly
(`buttons:[{label,url}]`, label ≤ 32 UTF-8 bytes, https URL). To verify: have someone else open your
profile, or log in a second account (mobile or web) and look at the main account.

## Step 4 — Verify without looking at Discord

```bash
./build/CustomRPMac --presets        # prints the payload each preset would send + validation issues
cat ~/Library/Logs/CustomRP/last-presence.json   # the payload Discord actually received
```

Expect `"assets":{"large_image":"2-asset-logo-1024","small_image":"3-asset-small-512"}`. External URLs
(`https://…`) stay valid as keys — Discord rewrites them to `mp:external/…`, which must stay under 256
characters.
