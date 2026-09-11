#!/usr/bin/env python3
"""Build assets/world/town/buildings.png from rubberduck's two CC0 packs (O12).

Input: the *_single.zip downloads of
  https://opengameart.org/content/isometric-medieval-buildings      (2 buildings)
  https://opengameart.org/content/isometric-medieval-buildings-2    (3 buildings)
unzipped side by side, e.g.

    unzip building_pack_02_single.zip -d p2 && unzip building_pack_03_single.zip -d p3
    tools/pack_buildings.py p2 p3 assets/world/town/buildings.png

Each building ships 8 128x64-format frames: 4 camera rotations of the plain
building (00-03) and the same 4 snowy (04-07), in sun-shaded / cloudy /
no-shadow variants. We take the 4 plain rotations of the *shaded* (sun) variant
and lay them out as one 5-column (building) x 4-row (rotation) sheet.

Two things the packs do not hand you and this script computes:

* Scale. Every frame is rendered at the same pixels-per-world-unit but on its
  own square canvas (512..1024px), so one shared factor (SCALE) keeps the shed
  smaller than the manor. Do NOT normalise each canvas to the cell.
* The ground anchor. Canvases are not consistently padded, so the near corner of
  the footprint is found per frame as the bottom-centre of the *no-shadow*
  variant's alpha bounding box (with the shadow in, the box is skewed towards
  the sun). Every cell is pasted so that point lands on ANCHOR, which is the
  `base` argument of world.gd's _draw_building().
"""
import sys
from PIL import Image

SCALE = 0.125                 # 1024px canvas -> 128px cell width
CELL = (128, 120)             # fits the widest/tallest frame plus its shadow
ANCHOR = (64, 112)            # where each frame's ground corner lands in its cell
ROTS = 4                      # frames 04-07 are the snowy variant; unused

# (shaded frame pattern, no-shadow frame pattern), relative to the pack roots.
BUILDINGS = [
    (0, "building_1/128x64_shaded/building1_128x64_%02d.png",
        "building_1/128x64_no_shadow/building1_128x64_no_shadow_%02d.png"),
    (0, "building_2/128x64_shaded/building2_128x64_%02d.png",
        "building_2/128x64_no_shadow/building2_128x64_no_shadow_%02d.png"),
    (1, "building_1/128x64_shaded/b1_128x64_shaded_%02d.png",
        "building_1/128x64_no_shadow/b1_128x64_no_shadow_%02d.png"),
    (1, "building_2/128x64_shaded/b2_128x64_shaded_%02d.png",
        "building_2/128x64_no_shadow/b2_128x64_no_shadow_%02d.png"),
    (1, "building_3/128x64_shaded/b3_128x64_shaded_%02d.png",
        "building_3/128x64_no_shadow/b3_128x64_no_shadow_%02d.png"),
]


def main(roots, out):
    sheet = Image.new("RGBA", (CELL[0] * len(BUILDINGS), CELL[1] * ROTS))
    for col, (root, shaded, plain) in enumerate(BUILDINGS):
        for rot in range(ROTS):
            box = Image.open("%s/%s" % (roots[root], plain % rot)).getbbox()
            ax, ay = (box[0] + box[2]) / 2.0, float(box[3])
            im = Image.open("%s/%s" % (roots[root], shaded % rot)).convert("RGBA")
            im = im.resize((round(im.width * SCALE), round(im.height * SCALE)),
                           Image.LANCZOS)
            sheet.alpha_composite(im, (
                col * CELL[0] + ANCHOR[0] - round(ax * SCALE),
                rot * CELL[1] + ANCHOR[1] - round(ay * SCALE)))
    sheet.save(out)
    print("%s  %dx%d" % (out, sheet.width, sheet.height))


if __name__ == "__main__":
    main(sys.argv[1:3], sys.argv[3])
