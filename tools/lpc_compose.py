#!/usr/bin/env python3
"""Compose an LPC sheet + credits + Godot SpriteFrames (T47 steps 3/4, T50).

    tools/lpc_compose.py [data/lpc/merc_01.json ...]      (no args = all of them)

Reads a loadout, stacks the vendored part sheets from assets/lpc/ and writes
    assets/generated/<id>.png     the composed sheet
    assets/generated/<id>.tres    SpriteFrames, one animation per declared row
    assets/generated/<id>_credits.txt

Two kinds of loadout, same schema, no special cases: a humanoid is 8 layers
off the universal 13x46 rig (merc_01.json), a creature is one layer off a
4-row monster sheet (bat/slime/ghost.json). What makes that work is that
*nothing about the grid is hardcoded* - the loadout names its own rows and
frame counts, because the two rigs do not share them (see below).

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

The [LPC] Monsters pack (opengameart.org/content/lpc-monsters) shares the
64px cell and the n/w/s/e row order and nothing else:

* One file per creature, no layer stack and no zPos anywhere - so a creature
  is simply a one-entry `layers` list; the z-sorting generalizes for free.
* 4 rows total (attack only, rows 0-3 = n/w/s/e), NOT the humanoid's 21/46-row
  universal layout. Verified by pixel-matching the author's own bat_attack-w
  and slime_attack-w GIFs against the sheets: bat_attack-w is exactly row 1,
  cols 1-6. A humanoid row index (slash-e = 14) on these sheets is off-sheet
  or empty, hence the emptiness assert in compose().
* Column count varies per creature AND per row - bat 7, ghost 6, slime 6 on
  n/s but 8 on w/e (the extra frames are the spit projectile). There is no
  one frame-count table to share with the humanoid rig.

ponytail: only 64px cells. Both the humanoid's oversize weapon sheets
(`custom_animation: slash_128 / slash_oversize`, e.g. arming sword) and this
pack's man_eater_flower (768x512 = 128px cells) need a bigger canvas plus
centring offsets; `frame` is already per-loadout, but mixing cell sizes in one
loadout is not handled. Add when the roster needs polearms or the flower.
"""
import csv
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PARTS = ROOT / "assets/lpc"
OUT = ROOT / "assets/generated"

FRAME = 64            # loadouts may override; every sheet vendored so far is 64


def compose(loadout: dict) -> Image.Image:
    frame = loadout.get("frame", FRAME)
    layers = [(l["z"], PARTS / (l["path"] + ".png")) for l in loadout["layers"]]
    imgs = [(z, Image.open(p).convert("RGBA")) for z, p in sorted(layers)]
    w = max(i.width for _, i in imgs)
    h = max(i.height for _, i in imgs)
    assert w % frame == 0 and h % frame == 0, "sheet is not a %d grid: %dx%d" % (frame, w, h)
    sheet = Image.new("RGBA", (w, h))
    for _, img in imgs:
        assert img.width % frame == 0 and img.height % frame == 0, "off-grid layer"
        sheet.alpha_composite(img)     # all LPC layers share the origin, no offsets
    # Every declared frame must exist and have pixels in it - the one check that
    # catches a loadout pointing at the wrong row (a humanoid row index on a
    # creature sheet used to slice silently-empty regions).
    for anim in loadout["animations"]:
        for i in range(anim["frames"]):
            box = (i * frame, anim["row"] * frame, (i + 1) * frame, (anim["row"] + 1) * frame)
            assert box[2] <= w and box[3] <= h, "%s frame %d is off-sheet" % (anim["name"], i)
            assert sheet.crop(box).getbbox(), "%s frame %d is empty" % (anim["name"], i)
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


def sprite_frames(loadout: dict, sheet_res: str) -> str:
    """A SpriteFrames .tres, one animation per row declared by the loadout."""
    frame = loadout.get("frame", FRAME)
    subs, anims, n = [], [], 0
    for anim in loadout["animations"]:
        ids = []
        for i in range(anim["frames"]):
            ids.append("%s_%d" % (anim["name"], i))
            subs.append('[sub_resource type="AtlasTexture" id="%s"]\n'
                        'atlas = ExtResource("1")\n'
                        'region = Rect2(%d, %d, %d, %d)\n'
                        % (ids[-1], i * frame, anim["row"] * frame, frame, frame))
            n += 1
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                     % (", ".join('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % i
                                  for i in ids),
                        "true" if anim.get("loop") else "false",
                        anim["name"], anim.get("speed", 12.0)))
    return ('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n'
            '[ext_resource type="Texture2D" path="%s" id="1"]\n\n%s\n'
            '[resource]\nanimations = [%s]\n'
            % (n + 2, sheet_res, "\n".join(subs), ", ".join(anims)))


def main(path: str) -> None:
    loadout = json.loads(Path(path).read_text())
    name = loadout["id"]
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = compose(loadout)
    sheet.save(OUT / (name + ".png"))
    (OUT / (name + "_credits.txt")).write_text(credits(loadout))
    (OUT / (name + ".tres")).write_text(
        sprite_frames(loadout, "res://assets/generated/%s.png" % name))
    print("%s.png %dx%d  + .tres [%s] + _credits.txt"
          % (name, sheet.width, sheet.height,
             ", ".join("%s x%d" % (a["name"], a["frames"]) for a in loadout["animations"])))


if __name__ == "__main__":
    paths = sys.argv[1:] or sorted(str(p) for p in (ROOT / "data/lpc").glob("*.json"))
    for p in paths:
        main(p)
