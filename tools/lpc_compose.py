#!/usr/bin/env python3
"""Compose one LPC character sheet + credits + Godot SpriteFrames (T47 step 3/4).

    tools/lpc_compose.py data/lpc/merc_01.json

Reads a loadout, stacks the vendored part sheets from assets/lpc/ and writes
    assets/generated/<id>.png     the composed sheet
    assets/generated/<id>.tres    SpriteFrames, slash_right only (spike)
    assets/generated/<id>_credits.txt

Where the numbers come from (all verified against the upstream repo, not the
wiki): sanderfrenken/Universal-LPC-Spritesheet-Character-Generator @ 675e21e.

* Frames are 64x64, 13 columns. Rows are fixed:
  sources/custom-animations.js `animationRowsLayout` gives slash n/w/s/e =
  rows 11/12/13/14, 6 frames each. Hence SLASH_E_ROW/SLASH_FRAMES below.
* Part sheets vary in *height* only (21 or 46 rows, depending on whether the
  part has the extended idle/run/jump/sit set) - the first 21 rows are the
  same universal layout in both, so pasting every layer at (0,0) onto a canvas
  as tall as the tallest layer is correct, no alignment math.
* z-order is NOT a fixed body->torso->weapon list: upstream stores a numeric
  zPos per layer in sheet_definitions/*.json (mirrored in
  scripts/z_positions.csv). Those numbers are copied into the loadout JSON and
  sorted here, which is what puts e.g. the dagger's "behind" sheet (z 9) under
  the body (z 10) while the dagger itself (z 140) sits over everything.

ponytail: only universal 64px layers. Weapons whose slash lives in a separate
oversized sheet (`custom_animation: slash_128 / slash_oversize`, e.g. the
arming sword and longsword) need a 128/192 canvas and are skipped for the
spike - the dagger is universal-only. Add that when the roster needs polearms.
"""
import csv
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PARTS = ROOT / "assets/lpc"
OUT = ROOT / "assets/generated"

FRAME = 64
COLS = 13
SLASH_E_ROW = 14      # animationRowsLayout["slash-e"]
SLASH_FRAMES = 6


def compose(loadout: dict) -> Image.Image:
    layers = [(l["z"], PARTS / (l["path"] + ".png")) for l in loadout["layers"]]
    imgs = [(z, Image.open(p).convert("RGBA")) for z, p in sorted(layers)]
    w = max(i.width for _, i in imgs)
    h = max(i.height for _, i in imgs)
    assert w == FRAME * COLS, "unexpected sheet width %d" % w
    assert h % FRAME == 0 and h // FRAME > SLASH_E_ROW, "sheet too short: %d" % h
    sheet = Image.new("RGBA", (w, h))
    for _, img in imgs:
        sheet.alpha_composite(img)
    return sheet


def credits(loadout: dict) -> str:
    """Longest-prefix match of each layer path against the vendored CREDITS rows."""
    rows = list(csv.DictReader(open(PARTS / "CREDITS.csv")))
    out = []
    for layer in loadout["layers"]:
        hits = [r for r in rows if layer["path"].startswith(r["filename"])]
        assert hits, "no CREDITS.csv row for " + layer["path"]
        row = max(hits, key=lambda r: len(r["filename"]))
        if row in out:
            continue
        out.append(row)
    lines = ["LPC art used by %s" % loadout["id"], ""]
    for r in out:
        urls = [r[k] for k in r if k.startswith("url") and r[k]]
        lines += ["%s" % r["filename"],
                  "  authors:  %s" % r["authors"],
                  "  licenses: %s" % r["licenses"]]
        if r["notes"]:
            lines.append("  notes:    %s" % r["notes"])
        lines += ["  %s" % u for u in urls] + [""]
    return "\n".join(lines)


def sprite_frames(sheet_res: str) -> str:
    """A SpriteFrames .tres with slash_right sliced out of the composed sheet."""
    y = SLASH_E_ROW * FRAME
    subs = "\n".join(
        '[sub_resource type="AtlasTexture" id="slash_right_%d"]\n'
        'atlas = ExtResource("1")\n'
        'region = Rect2(%d, %d, %d, %d)\n' % (i, i * FRAME, y, FRAME, FRAME)
        for i in range(SLASH_FRAMES))
    frames = ", ".join(
        '{\n"duration": 1.0,\n"texture": SubResource("slash_right_%d")\n}' % i
        for i in range(SLASH_FRAMES))
    return ('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n'
            '[ext_resource type="Texture2D" path="%s" id="1"]\n\n%s\n'
            '[resource]\nanimations = [{\n"frames": [%s],\n'
            '"loop": false,\n"name": &"slash_right",\n"speed": 12.0\n}]\n'
            % (SLASH_FRAMES + 2, sheet_res, subs, frames))


def main(path: str) -> None:
    loadout = json.loads(Path(path).read_text())
    name = loadout["id"]
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = compose(loadout)
    sheet.save(OUT / (name + ".png"))
    (OUT / (name + "_credits.txt")).write_text(credits(loadout))
    (OUT / (name + ".tres")).write_text(
        sprite_frames("res://assets/generated/%s.png" % name))
    print("%s.png %dx%d  + .tres (slash_right, %d frames) + _credits.txt"
          % (name, sheet.width, sheet.height, SLASH_FRAMES))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "data/lpc/merc_01.json"))
