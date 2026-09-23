# Code-review triage — 2026-09-23

An external review of this repository raised twelve findings. Each one was checked against the source
before anything was changed; the table records what was actually true. Three were real defects and are
fixed in this branch — the rest are recorded here so they are not lost, with the reason for leaving
them alone.

| Finding | Verdict | Evidence | Action |
| --- | --- | --- | --- |
| Reconnect cannot recover a worker that Discord rejected with code `4000` | **real (high)** | `Worker.update()` returned before clearing `paused`, and Reconnect passes the unchanged settings, so the card stayed failed until the id changed or the app restarted | **fixed** — the worker has an unconditional `forceReconnect()`; Reconnect and `reassert()` use it |
| Stopping a worker blocks the main actor | **real (medium)** | `Worker.stop()` used `queue.sync` for the goodbye `SET_ACTIVITY` and the close, with a 3 s socket timeout per read and two reads per frame, serialised across cards | **fixed** — teardown is asynchronous; the worker is marked stopped synchronously |
| The manual release workflow is broken | **real (medium)** | the checkout honoured `inputs.tag` while the version check and `gh release create` used `GITHUB_REF_NAME` | **fixed** — one `RELEASE_TAG` value drives the checkout, the check and the release |
| Deleting the last card silently recreates a "Main" card | false | the Remove button only exists while more than one card remains (`SettingsWindowController`), and the re-seed only runs for an already-empty list (hand-edited or legacy file, or first launch) | none needed |
| `commandReply()` accepts a response whose command matches but whose nonce does not | real (low) | `DiscordIPCClient` matches on `nonce || cmd` | **kept** — the `cmd` fallback exists because the client's own replies are not guaranteed to carry a nonce; removing it risks dropping a legitimate reply. Only the diagnostics are affected |
| `normalizedURL()` validates and then truncates to 512 characters | partly real (low) | the order is as described, but a truncated URL still parses — the real effect is a silently shortened URL, not an invalid one | deferred |
| Several workers write one log file without serialisation | real (low) | `PresenceLog.append` seeks and writes per call with no shared queue | deferred — `last-presence.json` is written atomically, so only diagnostic lines can interleave |
| A second corrupt file overwrites the previous `.bak` | real (low) | `PresetStore.quarantine` removes the old backup first | deferred |
| `GiphyUploader` reads the whole file and then copies it into the multipart body | real (low) | whole-file `Data(contentsOf:)` plus a second buffer, bounded at 100 MB | deferred |
| The version comparator ignores pre-release suffixes | real (low) | `UpdateCheck` strips everything after `-` | **intentional** — documented in the code; a numerically newer pre-release is still reported |
| `Migration.didStartKeychainMigration` is an unsynchronised static | partly real (low) | `nonisolated(unsafe)` with an unguarded check-then-set, but the only production caller is the main-actor launch path | deferred |

Two claims in the review did not survive checking: the "last card" behaviour and the impact of the URL
truncation. The review was written from the source alone and had not been built or run, so its severity
ratings were inference rather than observation — which is why each finding was verified here first.
