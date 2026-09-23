# Changelog

Notable changes per release. Dates are the release/tag dates.

## [1.2.3] - 2026-09-23

### Fixed

- Clicking **Settings** no longer stacks a new window every time. One settings window is reused: later
  calls bring it to the front and switch it to the requested pane, closing it and opening it again still
  works, and no window is leaked.
- `--self-test` passes again on a clean build. It asserted a settings round trip of a legacy field the
  encoder deliberately stopped writing, so the diagnostic that bug reports are asked to include failed.
  Continuous integration now runs it, so it cannot rot again.
- An unknown `--pane` value is reported instead of silently rendering the Cards pane.
- A render without `--demo` no longer reads the presets in the real application-support directory, so a
  screenshot cannot leak the developer's own data.

### Changed

- Local builds are signed with a stable identity when one is present (see *Signing your build* in
  CONTRIBUTING.md), so macOS stops asking for Keychain access after every rebuild. Ad-hoc signing stays
  the fallback, and published builds remain unsigned until Developer ID plus notarization exists.
- Documentation and assets no longer describe the product as it was before 1.2.0: the README, changelog,
  architecture notes and the menu specification were corrected, the screenshot of the deleted editor
  window was removed, and the menu screenshot was regenerated.
- `--render-settings`, `--pane`, `--preset` and `--demo` are documented, and the `dist` regeneration
  recipe names the commands that actually build each shipped asset.

### Added

- VS Code launch configurations for debugging the app (`.vscode/launch.json`).

## [1.2.2] - 2026-09-23

### Fixed

- The **Competing** activity type can carry timestamps again. The editor disabled its Time card and the
  rules reported "cannot show timestamps", which was an assumption rather than a Discord limit: a live
  check shows Discord keeps the `timestamps` object in its reply and its client renders the elapsed
  timer on a "Competing in …" card. Nothing in the payload changed — the app simply stopped denying a
  field Discord supports.

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
  window. The editor window is gone, and the menu no longer exposes preset-editing rows.

- Configuration moved into a **Settings** window (Cards · Presets · General · Giphy): the application
  id, pipe index, Reconnect, Launch at Login, the Giphy key and the update check left the menu, and the
  preset editor now lives in Settings → Presets. The menu bar menu keeps its daily actions — one status
  line that reports every card, `Settings…` (`⌘,`), `Reapply Now` (`⌘R`), `Clear Presence`, and `Quit`
  (`⌘Q`) — with zero submenus.
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
- Code review triage for this release is linked in
  [docs/reviews/2026-09-23-code-review-triage.md](docs/reviews/2026-09-23-code-review-triage.md).

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

[1.2.2]: https://github.com/quangpao/discord-rp-mac/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/quangpao/discord-rp-mac/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/quangpao/discord-rp-mac/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/quangpao/discord-rp-mac/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/quangpao/discord-rp-mac/releases/tag/v1.0.0
