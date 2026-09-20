#!/usr/bin/env python3
"""One seamless floor texture per combat-board palette, for scenes/main.gd's
hex fill (T9b). SDXL through the local ComfyUI, then made tileable by the
offset-and-blend trick: shift the image by half in both axes so the seams meet
in the middle, and cross-fade a band over them. Writes
sorcmerc/assets/board/floor_<palette>.png at 512 px.

    python3 gen_floor_textures.py [shrine ice ...]
"""
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

import gen_sorcmerc_items as g

OUT = Path("/home/egeo/localgen/ComfyUI/output")
DST = Path("/home/egeo/sorcmerc-work/assets/board")
TAIL = ("seamless tileable texture, top-down view, flat even lighting, no shadows, no objects, "
        "fantasy game ground material, muted dark colours, subtle detail, photorealistic, 4k")
NEG = ("seams, border, frame, objects, creatures, text, watermark, perspective, horizon, sky, "
       "bright, blurry, low quality")
PALETTES = {
    "shrine": "top-down photo of old wet grey stone floor slabs, irregular flagstones, moss in the joints",
    "camp": "trampled dirt and ash of a goblin camp, scattered straw and bones, dark brown",
    "city": "worn cobblestones of a city square, dark grey with faint rain sheen",
    "forest": "top-down photo of a forest floor, dark soil under brown dead leaves and patches of green moss",
    "ice": "cracked frozen cave floor, blue-grey ice with frost, dark",
    "shop": "old oak floorboards of a merchant shop, dark stained wood with dust",
}


def seamless(im: Image.Image, band: float = 0.3) -> Image.Image:
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    # Rolled by half, the image wraps cleanly at its edges and the old seams
    # now form a cross through the middle; the original is continuous exactly
    # there, so fade it back in along the cross and out again before the edges.
    b = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    yy = np.abs(np.arange(h) - h / 2) / (h / 2)
    xx = np.abs(np.arange(w) - w / 2) / (w / 2)
    wa = np.maximum(np.clip(1 - yy / band, 0, 1)[:, None], np.clip(1 - xx / band, 0, 1)[None, :])[..., None]
    out = b * (1 - wa) + a * wa
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


if __name__ == "__main__":
    only = set(sys.argv[1:])
    g.NEG = NEG
    DST.mkdir(parents=True, exist_ok=True)
    for i, (pal, what) in enumerate(PALETTES.items()):
        if only and pal not in only:
            continue
        prefix = f"floor_{pal}"
        g.wait_done(g.queue(f"{what}, {TAIL}", prefix, seed=4300 + i), timeout=240)
        # SaveImage numbers repeats (_00002_...): take the newest
        im = Image.open(max(OUT.glob(f"{prefix}_*.png"), key=lambda q: q.stat().st_mtime))
        seamless(im).save(DST / f"{prefix}.png", optimize=True)
        print(f"[{i+1}/{len(PALETTES)}] {pal}", flush=True)
    print("ALL DONE")
