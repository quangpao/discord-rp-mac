# Changelog

Notable changes per release. Dates are the release/tag dates.

## [Unreleased]

### Changed

- The editor explains itself with **hover tooltips** instead of a caption line under every control:
  placeholders carry the essence, tooltips the detail, and a line of text is spent only on a warning,
  an error or a status. The form is about 226 px shorter.

### Added

- **Check for Updates…** in the menu bar menu: it compares the running version with the latest GitHub
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
