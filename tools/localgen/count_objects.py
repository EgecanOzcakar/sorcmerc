#!/usr/bin/env python3
"""How many separate things are in an item render?  Background is plain and
dark, so: threshold away the background, drop specks, count connected blobs.
Prints one line per file, and a summary of the multi-object ones.

    python3 count_objects.py ComfyUI/output/item_*.png
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

MIN_BLOB = 0.004   # fraction of the image a blob must cover to count


def count(path: str) -> int:
    im = np.asarray(Image.open(path).convert("L").resize((256, 256)), dtype=np.float32)
    # background = the median of the border ring; foreground = clearly brighter or darker
    border = np.concatenate([im[0], im[-1], im[:, 0], im[:, -1]])
    bg = np.median(border)
    mask = np.abs(im - bg) > 40
    mask = ndimage.binary_closing(mask, iterations=3)   # bridge thin gaps inside one object
    mask = ndimage.binary_opening(mask, iterations=1)   # drop specks and glow dust
    labels, n = ndimage.label(mask)
    if n == 0:
        return 0
    sizes = ndimage.sum(mask, labels, range(1, n + 1)) / mask.size
    return int((sizes >= MIN_BLOB).sum())


if __name__ == "__main__":
    multi = []
    for p in sys.argv[1:]:
        n = count(p)
        print(f"{n:2d}  {p}")
        if n > 1:
            multi.append(p)
    print(f"\n{len(multi)} of {len(sys.argv) - 1} show more than one object", file=sys.stderr)
    for p in multi:
        print(p, file=sys.stderr)


# --- T9a: sheets and tiles, which the blob count cannot see -------------------
# A panel sheet joins its panels with border lines; a tiled render repeats
# itself. Neither reads as separate blobs, so two more looks:
#   dividers: an interior row/column whose gradient is high along nearly its
#             whole length (a straight line across the picture).
#   tiled:    the picture correlates strongly with itself shifted by 1/2 or 1/3.
def dividers(im: np.ndarray) -> int:
    n = 0
    for axis in (0, 1):
        g = np.abs(np.diff(im, axis=axis))
        line = g.mean(axis=1 - axis)              # per row (axis 0) or per column
        strong = (g > 25).mean(axis=1 - axis)     # fraction of the line that is an edge
        lo, hi = int(len(line) * 0.15), int(len(line) * 0.85)
        hits = np.where((strong[lo:hi] > 0.7))[0]
        # collapse runs of adjacent rows into one divider
        n += int(np.sum(np.diff(np.concatenate([[-10], hits])) > 3))
    return n


def tiled(im: np.ndarray) -> float:
    im = im - im.mean()
    best = 0.0
    for f in (2, 3):
        for axis in (0, 1):
            s = im.shape[axis] // f
            a = np.take(im, range(0, im.shape[axis] - s), axis=axis)
            b = np.take(im, range(s, im.shape[axis]), axis=axis)
            d = a.std() * b.std()
            if d > 0:
                best = max(best, float((a * b).mean() / d))
    return best


def score(path: str) -> float:
    """0 for one clean object; larger the more it looks like a set or sheet."""
    im = np.asarray(Image.open(path).convert("L").resize((256, 256)), dtype=np.float32)
    return (count(path) - 1) + 2 * dividers(im) + (3 if tiled(im) > 0.55 else 0)
