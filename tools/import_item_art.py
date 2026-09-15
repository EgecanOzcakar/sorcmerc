#!/usr/bin/env python3
"""Copy ComfyUI item renders into the project as small square icons.

    python3 tools/import_item_art.py [~/localgen/ComfyUI/output]

Reads item_<weapon|armor|magic>_<id>_00001_.png, writes assets/art/items/<id>.png
at ICON_PX. An id that exists in two categories (armor "shield" and magic-item
"shield") keeps the weapon/armor render, matching the lookup order the UI uses
(weapons, armor, then magic-items). Re-runnable; overwrites.
"""
import re
import sys
from pathlib import Path

from PIL import Image

ICON_PX = 128
SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "~/localgen/ComfyUI/output").expanduser()
DST = Path(__file__).resolve().parent.parent / "assets" / "art" / "items"
PAT = re.compile(r"^item_(weapon|armor|magic)_(.+)_\d+_\.png$")
RANK = {"weapon": 0, "armor": 0, "magic": 1}

best = {}
for p in SRC.glob("item_*.png"):
    m = PAT.match(p.name)
    if not m:
        continue
    cat, iid = m.groups()
    if iid not in best or RANK[cat] < RANK[best[iid][0]]:
        best[iid] = (cat, p)

DST.mkdir(parents=True, exist_ok=True)
for iid, (cat, p) in sorted(best.items()):
    Image.open(p).convert("RGB").resize((ICON_PX, ICON_PX), Image.LANCZOS).save(
        DST / f"{iid}.png", optimize=True)
print(f"{len(best)} icons -> {DST}")
