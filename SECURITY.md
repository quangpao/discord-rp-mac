# Security & privacy

## What this app stores

| Data | Where | Contains secrets? |
| --- | --- | --- |
| Presets + settings | `~/Library/Application Support/DiscordRPMac/*.json` | no |
| Upload history (Giphy ids/URLs) | `~/Library/Application Support/DiscordRPMac/giphy-uploads.json` | no |
| Your Giphy API key | macOS Keychain, item `dev.quangpao.discordrp.giphy` / `api-key` | **yes** |
| Last presence payload sent to Discord | `~/Library/Logs/DiscordRP/last-presence.json` + `discord-rp.log` | no |

The API key is read from the Keychain first, then `$GIPHY_API_KEY`, then `~/.giphy/api_key`. It is
never logged, never written into this repository, and never displayed back to you — the UI only
reports which source supplied it.

## What it talks to

- **Discord desktop client**, over the local IPC socket (`discord-ipc-0` in `$TMPDIR`). Nothing
  leaves your machine for Rich Presence to work.
- **`discord.com/api/oauth2/applications/<id>/assets`** — read-only, unauthenticated, to list the
  art assets you uploaded to your own Discord application (so the editor can offer them by name).
- **`cdn.discordapp.com`** — only to draw an asset thumbnail in the editor.
- **`upload.giphy.com`** — only when you press an *Upload to Giphy…* button, and only with your key.
  That request contains the file you chose, your Giphy API key, and the *Private on Giphy* flag if you
  ticked it. It contains **no** tags and no source URL: the app used to send a project tag and a
  `source_post_url`, and that was removed so your upload is attributable only to you.
- **`media.giphy.com`** — only to preview an image key that already points at a Giphy URL.

There is no telemetry, no analytics, no auto-update, and no server run by this project. The app
never asks for your Discord token, never automates your Discord account, and never sends anything to
a third party other than the Giphy endpoints listed above (which only run on an explicit click).

## Threat notes

- The app is not sandboxed (it needs the Discord IPC socket) and is ad-hoc signed unless you sign it
  yourself; it is intended to be built from source on your own machine.
- Anything that can read your user's Keychain can read the stored key. Removing the key from the
  Giphy dashboard revokes it immediately.
- Presence data is public by design: Discord shows it to anyone who can see your profile, and a
  Giphy upload is public unless you tick *Private on Giphy*.

## Supported versions

Before 1.0, only the latest release tag and `main` are supported.

## Reporting

Open a GitHub issue for anything non-sensitive. For a vulnerability, please avoid a public issue
until a fix is out — use **GitHub's private vulnerability reporting** on this repository
(*Security* → *Report a vulnerability*).

Please include: the app version (`--version`), your macOS version, your Discord client build, and the
tail of `~/Library/Logs/DiscordRP/discord-rp.log` with anything personal redacted. **Never** include your
Giphy API key, a Discord token, or private image URLs — none of them are needed to investigate.

Acknowledgement within 7 days; a fix or a mitigation plan as soon as the report can be reproduced.
