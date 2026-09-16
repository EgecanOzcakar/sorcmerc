#!/usr/bin/env python3
"""What colours is a piece of the generated art actually made of?

Used to pull settlement_kit.gd's PROFILES palettes out of the painted art
instead of guessing them by eye: the map diorama and the visit-screen
illustration are supposed to be the same town, and at 48px the palette is
most of what says which faction you are looking at.

    tools/palette_from_art.py assets/generated/settlement-human-town.png
    tools/palette_from_art.py --ring assets/generated/dwarf-*.png

--ring drops the middle of the frame before counting, which is how you read a
PORTRAIT: the centre is the shopkeeper, the border is the room they are standing
in — stone, timber, roof beams, forge light — and it is the room that says what
that faction builds with.

Several files are pooled into one palette (a faction's seven counters are seven
looks at one architecture), so `--ring assets/generated/orc-*.png` prints the
orc palette, not seven of them. PIL only, same as tools/pack_buildings.py.
"""
import sys
from PIL import Image

SAMPLE = 220          # longest edge each image is scaled to before counting
RING = 0.52           # --ring drops this fraction of width/height from the middle


def pixels(path: str, ring: bool) -> list:
    im = Image.open(path).convert("RGB")
    k = SAMPLE / max(im.size)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    raw = im.tobytes()
    px = [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]
    if not ring:
        return px
    w, h = im.size
    x0, x1 = round(w * (1 - RING) / 2), round(w * (1 + RING) / 2)
    y0, y1 = round(h * (1 - RING) / 2), round(h * (1 + RING) / 2)
    return [px[y * w + x] for y in range(h) for x in range(w)
            if not (x0 <= x < x1 and y0 <= y < y1)]


def palette(px: list, n: int) -> list:
    """Median-cut over the pooled pixels, biggest cluster first."""
    im = Image.new("RGB", (len(px), 1))
    im.putdata(px)
    q = im.quantize(colors=n, method=Image.MEDIANCUT)
    table = q.getpalette()
    counts = sorted(q.getcolors(), reverse=True)
    out = []
    for count, idx in counts:
        r, g, b = table[idx * 3:idx * 3 + 3]
        out.append((count / len(px), (r, g, b)))
    return out


def main(argv: list) -> None:
    ring = "--ring" in argv
    argv = [a for a in argv if a != "--ring"]
    n = 8
    if "--colors" in argv:
        i = argv.index("--colors")
        n = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    px = []
    for path in argv:
        px += pixels(path, ring)
    if not px:
        print(__doc__)
        return
    print("%d file(s), %d px%s" % (len(argv), len(px), ", ring only" if ring else ""))
    for share, (r, g, b) in palette(px, n):
        v = max(r, g, b) / 255.0
        s = 0.0 if max(r, g, b) == 0 else (max(r, g, b) - min(r, g, b)) / max(r, g, b)
        print("  #%02x%02x%02x  %5.1f%%   value %.2f  sat %.2f" % (r, g, b, share * 100, v, s))


if __name__ == "__main__":
    main(sys.argv[1:])
