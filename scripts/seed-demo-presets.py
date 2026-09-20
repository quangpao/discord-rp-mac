#!/usr/bin/env python3
"""Write a complete demo preset set for the app (covers every activity field Discord accepts)."""
import json
import os
import pathlib
import subprocess
import sys
import uuid
from datetime import datetime, timedelta

SUPPORT = pathlib.Path.home() / "Library/Application Support/DiscordRPMac"
SUPPORT.mkdir(parents=True, exist_ok=True)

# TimestampMode: 0 off · 1 since connection · 2 since app start · 3 since presence update
#                4 local time · 5 custom (start/end)
# ActivityKind:  0 playing · 1 streaming · 2 listening · 3 watching · 5 competing
# DisplayType:   0 name · 1 details · 2 state
# BYOK / open-source friendly: nothing personal is baked in. Point these at your own uploads, or
# leave empty and set the image keys with the app's “Upload to Giphy…” button instead.
IMAGE = os.environ.get("DEMO_IMAGE_URL", "")
# ↑ animated logo (GIF): Discord renders animation only for EXTERNAL URLs, not for uploaded assets.
#   Static alternative if animation is unwanted: "2-asset-logo-1024" (uploaded portal asset).
SMALL = os.environ.get("DEMO_SMALL_KEY", "")   # a Discord art asset name, if you have one
LINK = "https://quangpao.dev"
GH = "https://github.com/quangpao"

now = datetime.now()
# Epoch MILLISECONDS: PresetStore pins dates to .millisecondsSince1970, so a value written in
# seconds would be read as a date in 1970 (or 2057 the other way round).
start = int((now - timedelta(minutes=42)).timestamp() * 1000)
end = int((now + timedelta(hours=3)).timestamp() * 1000)

# A running app holds its presets in memory and rewrites presets.json on save/quit, which silently
# undoes a seed written underneath it. Refuse unless --force.
if "--force" not in sys.argv:
    running = subprocess.run(["pgrep", "-x", "DiscordRPMac"], capture_output=True, text=True).stdout.split()
    if running:
        raise SystemExit(
            f"Discord RP is running (pid {', '.join(running)}) — quit it first, or pass --force.\n"
            "A running app rewrites presets.json from memory and will undo this seed."
        )


def activity(**overrides):
    base = {
        "name": "Discord RP by quangpao",
        "kind": 0,
        "display": 1,
        "details": "",
        "detailsURL": "",
        "state": "",
        "stateURL": "",
        "partySize": 0,
        "partyMax": 0,
        "timestampMode": 1,
        "customStart": start,
        "customEnd": end,
        "customEndEnabled": False,
        "largeKey": "",
        "largeText": "",
        "largeURL": "",
        "smallKey": "",
        "smallText": "",
        "smallURL": "",
        "buttons": [],
    }
    base.update(overrides)
    return base


presets = [
    {
        "name": "1 · Coding",
        "activity": activity(
            details="Đang code", state="discord-rp-mac",
            largeKey=IMAGE, largeText="quangpao", smallKey=SMALL, smallText="quangpao",
            buttons=[{"label": "quangpao.dev", "url": LINK}, {"label": "GitHub", "url": GH}],
        ),
    },
    {
        "name": "2 · Nghe nhạc",
        "activity": activity(
            kind=2, details="Lo-fi beats to code to", state="Focus mode",
            timestampMode=4, largeKey=IMAGE, largeText="quangpao", smallKey=SMALL, smallText="quangpao",
            buttons=[{"label": "quangpao.dev", "url": LINK}],
        ),
    },
    {
        "name": "3 · Chơi game (party 3/5)",
        "activity": activity(
            kind=0, details="Ranked", state="Đang vào trận",
            partySize=3, partyMax=5, largeKey=IMAGE, largeText="quangpao", smallKey=SMALL, smallText="quangpao",
            buttons=[{"label": "GitHub", "url": GH}],
        ),
    },
    {
        "name": "4 · Đếm ngược deadline",
        "activity": activity(
            kind=0, details="Sprint sắp hết", state="Còn lại",
            timestampMode=5, customEndEnabled=True,
            largeKey=IMAGE, largeText="quangpao", smallKey=SMALL, smallText="quangpao",
            buttons=[{"label": "quangpao.dev", "url": LINK}],
        ),
    },
    {
        "name": "5 · Thi đấu (không timestamp)",
        "activity": activity(
            kind=5, details="Hackathon", state="Vòng 2",
            timestampMode=0,
        ),
    },
]

payload = [{"id": str(uuid.uuid4()).upper(), "name": p["name"], "activity": p["activity"]} for p in presets]
(SUPPORT / "presets.json").write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

settings = json.loads((SUPPORT / "settings.json").read_text()) if (SUPPORT / "settings.json").exists() else {}
settings["activePresetID"] = payload[0]["id"]
# The Application ID belongs to whoever runs this: never hardcode one in the repo.
settings.setdefault("appID", os.environ.get("DISCORD_APP_ID", ""))
settings.setdefault("pipeIndex", 0)
settings["launchAtLogin"] = settings.get("launchAtLogin", False)
(SUPPORT / "settings.json").write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n")

print(f"wrote {len(payload)} presets")
for p in payload:
    print(f"  {p['id']}  {p['name']}")
