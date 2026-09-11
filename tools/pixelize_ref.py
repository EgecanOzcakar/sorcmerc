#!/usr/bin/env python3
"""Cut the background off a reference image and pixelize it to LPC-compatible
sprite scale (T52 in docs/expansion-plan.md).

Technique: palette-quantized nearest-neighbor downscale, the same algorithm
github.com/giventofly/pixelit uses (confirmed MIT-licensed on its repo page)
-- reimplemented in Pillow rather than run as JS, matching this project's
tools/pack_buildings.py convention.

Background removal has no single method that works for every source, so this
picks per-image (see data/monster_refs/manifest.json's "bg_removal" field for
which one was used on each monster):

  rembg      ML segmentation (rembg/BiRefNet, MIT). Best for real photos
             with a busy background it can find a genuine subject in.
  lineart    For white-background line art where the subject's own "white"
             areas are literally the same color as the page (a plain
             background-color match would eat straight through them):
             mask the ink strokes, morphologically close small gaps in the
             outline, then fill the enclosed interior solid. Independent of
             interior color.
  floodfill  Connected-component removal of a near-uniform (not necessarily
             pure white) background reachable from the image border.
  colorkey   Exact-color removal (flat-colored source, e.g. a palette PNG).
  bright     Alpha = brightness above a dark floor (a flame with no hard
             edge; the bright subject stays, the dim background fades).
  radial     Soft circular vignette (a texture with no distinct subject at
             all, e.g. open water - turns a rectangular crop into a blob).

Usage:
    pixelize_ref.py <in> <out> --method rembg|lineart|floodfill|colorkey|bright|radial
        [--crop L,T,R,B] [--tint R,G,B] [--colors N] [--max-side N]
"""
import argparse
import numpy as np
from PIL import Image


def lineart_alpha(im, ink_thresh=235, close_px=18):
    from scipy import ndimage
    im = im.convert("RGBA")
    pad = close_px + 5
    arr0 = np.array(im).astype(int)
    h0, w0 = arr0.shape[:2]
    arr = np.full((h0 + 2 * pad, w0 + 2 * pad, 4), 255, dtype=int)
    arr[pad:pad + h0, pad:pad + w0] = arr0
    lum = arr[:, :, :3].mean(axis=2)
    ink = lum < ink_thresh
    closed = ndimage.binary_closing(ink, structure=np.ones((close_px, close_px)))
    filled = ndimage.binary_fill_holes(closed)
    # Background is now guaranteed one connected region (the padding is
    # plain and touches every edge) - subtract it rather than guess which
    # blob is "the subject".
    labels, _ = ndimage.label(~filled)
    is_bg = labels == labels[0, 0]
    filled = ndimage.binary_dilation(~is_bg, iterations=max(1, close_px // 2))
    arr[:, :, 3] = np.where(filled, 255, 0)
    arr = arr[pad:pad + h0, pad:pad + w0]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def floodfill_bg(im, tol=45):
    from scipy import ndimage
    im = im.convert("RGBA")
    arr = np.array(im).astype(int)
    rgb = arr[:, :, :3]
    corners = np.array([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    bgcolor = np.median(corners, axis=0)
    near_bg = np.abs(rgb - bgcolor).sum(axis=2) < tol
    labels, _ = ndimage.label(near_bg, structure=np.ones((3, 3)))
    border_labels = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    border_labels.discard(0)
    bg_mask = np.isin(labels, list(border_labels))
    arr[:, :, 3] = np.where(bg_mask, 0, arr[:, :, 3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def colorkey_bg(im, key=(0, 0, 0), tol=10):
    im = im.convert("RGBA")
    arr = np.array(im).astype(int)
    dist = np.abs(arr[:, :, :3] - np.array(key)).sum(axis=2)
    arr[:, :, 3] = np.where(dist <= tol, 0, arr[:, :, 3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def bright_alpha(im, floor=60, ceil=200):
    im = im.convert("RGBA")
    arr = np.array(im).astype(int)
    lum = arr[:, :, :3].max(axis=2)
    arr[:, :, 3] = np.clip((lum - floor) * 255 / (ceil - floor), 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def radial_alpha(im):
    im = im.convert("RGBA")
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    alpha = np.clip((1.15 - r) * 255 / 0.6, 0, 255)
    arr = np.array(im).astype(int)
    arr[:, :, 3] = np.minimum(arr[:, :, 3], alpha)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def rembg_bg(im):
    from rembg import remove
    return remove(im.convert("RGB"))


METHODS = {
    "lineart": lineart_alpha, "floodfill": floodfill_bg, "colorkey": colorkey_bg,
    "bright": bright_alpha, "radial": radial_alpha, "rembg": rembg_bg,
}


def tint(im, rgb, strength=0.35):
    """Multiply-tint toward a target color (e.g. turning a generic dragon
    line art into a 'red' one without redrawing it)."""
    im = im.convert("RGBA")
    arr = np.array(im).astype(float)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * (1 - strength) + np.array(rgb, dtype=float) * strength, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def pixelize(im, max_side=64, colors=24, alpha_thresh=128):
    im = im.convert("RGBA")
    alpha = im.getchannel("A")
    scale = max_side / max(im.width, im.height)
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    small = im.resize((w, h), Image.BOX)
    small_alpha = alpha.resize((w, h), Image.BOX).point(lambda a: 255 if a >= alpha_thresh else 0)
    rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(small_alpha)
    return rgb


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("out")
    p.add_argument("--method", choices=METHODS, default="rembg")
    p.add_argument("--crop", help="L,T,R,B")
    p.add_argument("--tint", help="R,G,B")
    p.add_argument("--colors", type=int, default=24)
    p.add_argument("--max-side", type=int, default=64)
    args = p.parse_args()

    im = Image.open(args.src)
    if args.crop:
        im = im.crop(tuple(int(v) for v in args.crop.split(",")))
    cut = METHODS[args.method](im)
    if args.tint:
        cut = tint(cut, tuple(int(v) for v in args.tint.split(",")))
    px = pixelize(cut, max_side=args.max_side, colors=args.colors)
    px.save(args.out)
    print("wrote", args.out, px.size)


if __name__ == "__main__":
    main()
