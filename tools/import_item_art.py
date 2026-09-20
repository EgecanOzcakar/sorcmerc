#!/usr/bin/env python3
"""Copy the chosen ComfyUI item render of each id into the project as a 128 px icon.

    python3 tools/import_item_art.py [~/localgen/ComfyUI/output]

tools/item_art_picks.txt says which render ships, one line per item:
    <pick> <weapon|armor|magic> <id>
pick is L (first batch, item_<kind>_<id>), R (single-object re-render,
item2_…), T<n> (one of the re-render's tries, try_…_<n>), P<n> (the
hand-prompted third pass, re_…_<n>), or X (nothing good yet: the id is
skipped and the UI shows a named tile). The picks were made by eye off
side-by-side contact sheets; heuristics (blob count, divider lines,
self-similarity) topped out around 70% on these renders and were dropped.

An id in two categories (armor "shield" and the magic-item "shield") keeps
the weapon/armor line, matching the lookup order the UI uses.
"""
import sys
from pathlib import Path

from PIL import Image

ICON_PX = 128
SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "~/localgen/ComfyUI/output").expanduser()
HERE = Path(__file__).resolve().parent
DST = HERE.parent / "assets" / "art" / "items"
RANK = {"weapon": 0, "armor": 0, "magic": 1}


def render_for(pick: str, kind: str, iid: str) -> Path | None:
    if pick == "L":
        name = f"item_{kind}_{iid}"
    elif pick == "R":
        name = f"item2_{kind}_{iid}"
    elif pick.startswith("T"):
        name = f"try_{kind}_{iid}_{pick[1:]}"
    elif pick.startswith("P"):
        name = f"re_{kind}_{iid}_{pick[1:]}"
    else:
        return None
    p = SRC / f"{name}_00001_.png"
    return p if p.exists() else None


best = {}
skipped = []
for line in (HERE / "item_art_picks.txt").read_text().split("\n"):
    if not line.strip():
        continue
    pick, kind, iid = line.split()
    p = render_for(pick, kind, iid)
    if p is None:
        skipped.append(iid)
        continue
    if iid not in best or RANK[kind] < best[iid][0]:
        best[iid] = (RANK[kind], p)

DST.mkdir(parents=True, exist_ok=True)
for old in DST.glob("*.png"):
    if old.stem not in best:
        old.unlink()
for iid, (_rank, p) in sorted(best.items()):
    Image.open(p).convert("RGB").resize((ICON_PX, ICON_PX), Image.LANCZOS).save(
        DST / f"{iid}.png", optimize=True)
print(f"{len(best)} icons -> {DST}; {len(skipped)} without art: {' '.join(skipped)}")
