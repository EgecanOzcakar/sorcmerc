#!/usr/bin/env python3
"""Re-render items as ONE object each. The first batch (gen_sorcmerc_items.py)
came back as sets and panel sheets for about half the ids — "item icon" pulls
SDXL toward a sprite sheet. Same workflow, the prompt now leads with "one
single", the negative names every kind of set, and the filename prefix is
item2_ so the first batch stays for comparison.

    python3 gen_single.py                 # every item
    python3 gen_single.py longsword hide  # just these ids
"""
import sys
import time

import gen_sorcmerc_items as g
from count_objects import count

TRIES = 3
OUT = "/home/egeo/localgen/ComfyUI/output"

NEG = ("multiple objects, several, set, collection, pair, duplicates, grid, panels, sprite sheet, "
       "collage, split screen, tiled, ornamental border, glowing backdrop, spotlight circle, "
       "blurry, low quality, text, watermark, cropped, hands, person, deformed")
TAIL = ("shown once, alone, centered, on a plain dark empty background, "
        "fantasy RPG item, ornate detailed design, polished metal and fine engraving, "
        "sharp well-defined silhouette, digital painting, highly detailed, dramatic lighting")


def single_prompt(kind: str, name: str, meta: str) -> str:
    return f"one single {name}, {meta}, {TAIL}"


def load():
    import json
    out = []
    for w in json.load(open(f"{g.SORCMERC}/weapons.json")):
        out.append(("weapon", w["id"], single_prompt("weapon", w["name"], f"a {w['category']} {w.get('range', 'melee')} weapon")))
    for a in json.load(open(f"{g.SORCMERC}/armor.json")):
        out.append(("armor", a["id"], single_prompt("armor", a["name"], f"one piece of {a['category']} armor")))
    for m in json.load(open(f"{g.SORCMERC}/magic-items.json")):
        hint = g.CATEGORY_HINT.get(m["category"], "a magical item")
        glow = g.RARITY_GLOW.get(m["rarity"], "a magical shimmer")
        out.append(("magic", m["id"], single_prompt("magic", m["name"], f"{hint}, {glow}")))
    return out


if __name__ == "__main__":
    only = set(sys.argv[1:])
    items = [it for it in load() if not only or it[1] in only]
    g.NEG = NEG
    t0 = time.time()
    for i, (kind, iid, text) in enumerate(items):
        # one render per try under its own prefix; the keeper is copied to item2_<kind>_<id>
        best = None
        for t in range(TRIES):
            prefix = f"try_{kind}_{iid}_{t}"
            try:
                g.wait_done(g.queue(text, prefix, seed=7000 + 10 * i + t), timeout=240)
            except Exception as e:
                print(f"[{i+1}/{len(items)}] FAILED {prefix}: {e}", flush=True)
                continue
            path = f"{OUT}/{prefix}_00001_.png"
            n = count(path)
            if best is None or n < best[0]:
                best = (n, path)
            if n == 1:
                break
        if best is None:
            continue
        import shutil
        shutil.copy(best[1], f"{OUT}/item2_{kind}_{iid}_00001_.png")
        avg = (time.time() - t0) / (i + 1)
        print(f"[{i+1}/{len(items)}] {iid}: {best[0]} object(s) after {t+1} tries  (avg {avg:.1f}s, ~{avg*(len(items)-i-1)/60:.0f}min left)", flush=True)
    print("ALL DONE")
