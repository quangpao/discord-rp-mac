# Third-party notices

## CustomRP

This project is an **independent macOS implementation**. Discord Rich Presence protocol behaviour and
Discord's own validation rules were studied from the source of CustomRP:

- CustomRP — <https://github.com/maximmax42/Discord-CustomRP> (C#/.NET, Windows only)
- MIT License, copyright its contributors

What was reused: understanding of the `AF_UNIX` IPC transport, frame opcodes, and Discord's field
limits (which are Discord's rules, not CustomRP's invention — the upstream file/line references are
kept in comments so the reasoning stays auditable).

What was **not** reused: no CustomRP code was copied, and this app deliberately does **not** use
CustomRP's public Application ID as a fallback (that would render your activity as *CustomRP* with
*their* assets).

**No affiliation, endorsement, or sponsorship** between this project and CustomRP is implied.

## Giphy

The optional "Upload to Giphy…" feature talks to Giphy's public upload API with **your own** API key.
This project is not affiliated with, endorsed by, or sponsored by Giphy. Uploaded media is subject to
Giphy's own terms and privacy policy, not this project's.

## Discord

This project is not affiliated with, endorsed by, or sponsored by Discord Inc. "Discord" is a
trademark of Discord Inc. Using this app changes what your Discord profile displays; you are
responsible for complying with Discord's Terms of Service.

## Icons and fonts

The app icon, menu bar glyph and logo sheet in `Resources/logo/` and `docs/ui/` were produced for this
project (MIT, same as the rest of the repository). No third-party icon font or clip art is bundled.
