# Changelog

Notable changes per release. Dates are the release/tag dates.

## [1.2.1] - 2026-09-23

### Fixed

- Reconnect now recovers a card whose application id Discord rejected with code `4000`. The worker had
  kept its paused state, so the card stayed failed until the id changed or the app restarted, even though
  Reconnect is exactly the button for that situation.
- Stopping a worker no longer blocks the main thread. Clearing, disabling or removing a card used to wait
  for socket I/O (up to a few seconds per card, one after another); the goodbye is now sent in the
  background, so the interface stays responsive.
- A peer that closes the socket no longer kills the app with `SIGPIPE`; the write path reports the
  connection as closed and cleans up instead.
- The manual release workflow (`workflow_dispatch`) used the dispatch ref instead of the tag it was given,
  so it could never publish. One resolved tag now drives the checkout, the version check and the release.
- `forceReconnect()` no longer wakes an idle worker, which could have opened a connection with a stale
  application id.

## [1.2.0] - 2026-09-23

### Fixed

- **Only one of two cards appeared on the profile.** Discord renders a single activity per activity
  *name*, so two cards whose presets share the same `Shown as` value collide and one of them is
  dropped — the client keeps whichever arrived last, which is why the visible card could change
  between restarts. Settings → Cards now warns which cards collide and offers **Make unique**, which
  appends that card's name to its preset's value. The presence log also records what Discord answers,
  not just what was sent, so a refused or replaced card can no longer look like a working one, and the
  editor's `Shown as` tooltip states the rule.


### Changed

- The menu bar panel dropped its `Presets ▸` submenu and the `Edit This Preset…` row: choosing a card's
  preset and editing presets happen in Settings → Cards and Settings → Presets, so the panel keeps only
  daily actions (status line · Settings… · Reapply Now · Clear Presence · Quit).

- **Preset editing moved into Settings → Presets**: a preset list on the left (each row saying which
  card uses it) and the full editor form on the right, so editing no longer means opening a separate
  window. The editor window is gone; the menu's `Edit This Preset…` (`⌘E`) opens Settings on the active
  card's preset.

- Configuration moved into a **Settings** window (Cards · Presets · General · Network): the application
  id, pipe index, Reconnect, Launch at Login, the Giphy key and the update check left the menu, and the
  editor now edits one preset's content only. The menu bar menu keeps its daily actions — one status
  line that reports every card, one submenu, ≤ 11 rows — and `⌘,` is Settings while the editor is `⌘E`.
- The editor explains itself with **hover tooltips** instead of a caption line under every control:
  placeholders carry the essence, tooltips the detail, and a line of text is spent only on a warning,
  an error or a status. The form is about 226 px shorter.

### Added

- **Several presence cards at once.** One card is the activity shown for one Discord application, and
  Discord renders exactly one card per application — so a second card needs a **second Discord
  application** (its own name, icon and assets). Settings → Cards adds, enables and verifies them, each
  card gets its own IPC connection, and a card that fails never takes the others down. Existing installs
  migrate to a single card on first launch, and the settings file keeps mirroring it so an older build
  still pushes the right presence.
- **Check for Updates…** in Settings: it compares the running version with the latest GitHub
  release and offers the download page when one is newer. Manual on purpose — nothing polls on a timer,
  so the app still only makes the network calls you trigger (`SECURITY.md` lists the new endpoint).

## [1.1.0] — 2026-09-22

### Added

- **Works with no setup.** A fresh install now uses this project's Discord application, so the activity
  can be pushed immediately. The Connection card gained a *Use the default application* button (disabled
  while it already applies) and a hint that names the state the field is in. Clearing the Application ID
  still means "send nothing to Discord".

### Changed

- The README is now an entry point (features, requirements, install, configure, development, privacy);
  the user guide lives in the [wiki](https://github.com/quangpao/discord-rp-mac/wiki).
- `docs/discord-setup.md` moved into the wiki as **Setup**, and the troubleshooting table became the
  wiki **FAQ**.

## [1.0.0] — 2026-09-21

First release.

### Fixed

- **Startup hang / launch at login doing nothing.** `AppModel.init` read the Keychain, and a legacy-ACL
  item made macOS block inside `mach_msg` while it showed a prompt. Startup now performs file-only
  migration; the Keychain move runs on a background queue. `kSecUseAuthenticationUIFail` does not
  suppress that prompt.
- **Reconnect was a no-op** when the connection values had not changed; it now re-applies the connection
  and the active preset.
- **Upload to Giphy** no longer sends tags or a source URL along with your key.
- The `--live` and `--giphy-upload` CLI paths no longer used the old working name.
- Tests no longer print key material and no longer write to the real log or data directory.
- `customrp.log` was renamed to `discord-rp.log`, keeping the existing history.

[1.1.0]: https://github.com/quangpao/discord-rp-mac/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/quangpao/discord-rp-mac/releases/tag/v1.0.0
