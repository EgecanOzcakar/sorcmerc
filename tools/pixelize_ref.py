#!/usr/bin/env python3
"""Pixelize a background-removed reference image to LPC-compatible sprite scale.

Technique: palette-quantized nearest-neighbor downscale (the same algorithm
github.com/giventofly/pixelit uses, confirmed MIT-licensed at
github.com/giventofly/pixelit — reimplemented in Pillow rather than run as JS,
matching this project's tools/pack_buildings.py convention).

Steps: downscale with a box/area filter (cheap anti-alias so tiny detail
doesn't alias into noise) to fit within a 64x64 box (aspect preserved, not
stretched), then quantize to a small adaptive palette so flat color regions
read as pixel-art rather than a shrunk photo. Alpha is thresholded (not
downsampled with the RGB) so edges stay crisp, not translucent-fringed.
"""
import sys
from PIL import Image

MAX_SIDE = 64      # LPC frame grid ceiling
PALETTE_COLORS = 24


def pixelize(src_path, out_path, max_side=MAX_SIDE, colors=PALETTE_COLORS):
    im = Image.open(src_path).convert("RGBA")
    alpha = im.getchannel("A")

    scale = max_side / max(im.width, im.height)
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))

    small = im.resize((w, h), Image.BOX)
    small_alpha = alpha.resize((w, h), Image.BOX).point(lambda a: 255 if a >= 128 else 0)

    rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(small_alpha)
    rgb.save(out_path)
    return rgb.size


if __name__ == "__main__":
    size = pixelize(sys.argv[1], sys.argv[2])
    print("wrote", sys.argv[2], size)
