Discord RP for macOS 14 or later. Native Swift menu bar app, MIT licensed.

**This build is not notarized by Apple.** macOS will refuse the first launch — that is expected, and it
is not malware. To open it:

1. Drag **Discord RP.app** onto the Applications folder in the disk image.
2. Open it once from Applications and let macOS refuse.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the
   Discord RP message.
4. Or, from a terminal: `xattr -dr com.apple.quarantine "/Applications/Discord RP.app"`

Or build from source, which avoids Gatekeeper entirely:

```bash
git clone https://github.com/quangpao/discord-rp-mac
cd discord-rp-mac
./scripts/build-app.sh --install --run
```

## Requirements

- macOS 14+
- The **Discord desktop app**, running (Rich Presence is set over a local socket)
- Your own Discord **Application ID** (free — see `docs/discord-setup.md`)
- Your own **Giphy API key** if you want the *Upload to Giphy…* buttons (BYOK; the app ships no key)

## Uninstall

```bash
# quit the app first (menu bar → Quit)
rm -rf "/Applications/Discord RP.app"
rm -rf "$HOME/Library/Application Support/DiscordRPMac"
rm -rf "$HOME/Library/Logs/DiscordRP"
security delete-generic-password -s dev.quangpao.discordrp.giphy -a api-key 2>/dev/null || true
```

Verify the download against the attached `sha256.txt`.

*Not affiliated with Giphy or Discord. See THIRD_PARTY_NOTICES.md.*
