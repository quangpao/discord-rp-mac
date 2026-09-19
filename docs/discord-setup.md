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
2. **Add Image(s)** and upload, one at a time:
   | File | Suggested asset name (this is the key you type in the app) | Used as |
   |---|---|---|
   | `dist/discord/2-asset-logo-1024.png` | `logo` | `large_image` |
   | `dist/discord/3-asset-small-512.png` | `mark` | `small_image` (small overlay on the big image) |
3. **Save Changes**, then wait a few minutes.
4. Sanity check from the shell — the same call the app's “Load asset names” button makes:
   ```bash
   curl -s https://discord.com/api/oauth2/applications/1041550572223995925/assets
   ```
   Assets appear as `[{"name":"logo",...}]`. An empty `[]` means they have not landed yet.

Portal accepts PNG/JPG at ≥512×512; the files here are 512–1024 px and 10–282 KB, so they pass.

## Step 3 — Point the presets at the assets

Menu bar item → **Edit This Preset…** (or ⌘,):

- **Images → Large key**: `logo` · **Large text**: `quangpao` (leave *Large link* empty if you do not
  want the image clickable)
- **Images → Small key**: `mark` · **Small text**: whatever short label you want
- **Load asset names** opens a dropdown of the portal's assets — use it to confirm the key spelling.
- **Apply** pushes immediately; the card updates in about two seconds.

Alternatively set the keys by hand in
`~/Library/Application Support/CustomRPMac/presets.json` (`largeKey` / `smallKey`) and restart the app.

## Step 4 — Verify without looking at Discord

```bash
./build/CustomRPMac --presets        # prints the payload each preset would send + validation issues
cat ~/Library/Logs/CustomRP/last-presence.json   # the payload Discord actually received
```

Expect `"assets":{"large_image":"logo","small_image":"mark"}`. External URLs (`https://…`) stay valid
as keys — Discord rewrites them to `mp:external/…`, which must stay under 256 characters.
