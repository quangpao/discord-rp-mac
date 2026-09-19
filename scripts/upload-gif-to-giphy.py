#!/usr/bin/env python3
"""Upload an image to Giphy and print the URLs a Rich Presence image key can use.

Giphy docs (developers.giphy.com/docs/api → Upload Endpoint):
  POST https://upload.giphy.com/v1/gifs
  api_key (required) · file (binary) or source_image_url · tags · is_hidden · username (approved apps only)
  Rate-limited dashboard keys: no channel username, max 10 uploads/day. Animated GIF/video up to 100 MB.

The API key is a credential: this script reads it from the environment or from
`~/.giphy/api_key` (chmod 600). It is never written into the repo and never printed.

Usage:
  python3 scripts/upload-gif-to-giphy.py [file.gif] [--hidden] [--tags logo,brand]
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

ENDPOINT = "https://upload.giphy.com/v1/gifs"


def api_key() -> str:
    key = os.environ.get("GIPHY_API_KEY", "").strip()
    if key:
        return key
    path = pathlib.Path.home() / ".giphy" / "api_key"
    if path.exists():
        return path.read_text().strip()
    sys.exit(
        "no Giphy API key.\n"
        "  1. create one: https://developers.giphy.com/dashboard/?create=true\n"
        "  2. store it OUTSIDE this repo, e.g.\n"
        "       mkdir -p ~/.giphy && printf '%s' 'YOUR_KEY' > ~/.giphy/api_key && chmod 600 ~/.giphy/api_key\n"
        "     or export GIPHY_API_KEY=… in your shell\n"
        "  (never paste the key into a chat, issue tracker, or this repo)"
    )


def multipart(fields: dict[str, str], file_field: tuple[str, pathlib.Path]) -> tuple[bytes, str]:
    boundary = f"----customrp{uuid.uuid4().hex}"
    name, path = file_field
    body = bytearray()

    def add(text: str) -> None:
        body.extend(text.encode())

    for key, value in fields.items():
        add(f"--{boundary}\r\n")
        add(f'Content-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n')
    add(f"--{boundary}\r\n")
    add(f'Content-Disposition: form-data; name="{name}"; filename="{path.name}"\r\n')
    add("Content-Type: image/gif\r\n\r\n")
    body.extend(path.read_bytes())
    add(f"\r\n--{boundary}--\r\n")
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    source = pathlib.Path(args[0] if args else "dist/discord/customrp-animated-logo.gif")
    if not source.exists():
        sys.exit(f"missing file: {source}")

    fields = {"api_key": api_key(), "source_post_url": "https://quangpao.dev"}
    if "--hidden" in flags:
        fields["is_hidden"] = "true"
    if "--tags" in flags:
        i = sys.argv.index("--tags")
        fields["tags"] = sys.argv[i + 1]

    body, content_type = multipart(fields, ("file", source))
    request = urllib.request.Request(ENDPOINT, data=body, headers={"Content-Type": content_type})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        sys.exit(f"Giphy rejected the upload: HTTP {error.code} {error.read()[:300]!r}")

    data = payload.get("data") or {}
    gif_id = data.get("id")
    if not gif_id:
        sys.exit(f"unexpected response: {json.dumps(payload)[:400]}")

    print(f"id:        {gif_id}")
    print(f"page:      https://giphy.com/gifs/{gif_id}")
    print(f"media url: https://media.giphy.com/media/{gif_id}/giphy.gif")
    print(f"key length: {len(f'https://media.giphy.com/media/{gif_id}/giphy.gif')} chars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
