#!/usr/bin/env python3
"""Downscale and re-encode the textures embedded in a .glb (asset budget).

The models in this project arrive from their generator with 2048-4096 square
PNG textures baked into the .glb. That is what a photogrammetry pipeline emits,
and it is roughly twenty times what any of them needs: a figure is ~200px tall
on screen and a settlement diorama ~400px. Left alone, assets/ was 693 MB and
every clone of this repository paid for it.

    python3 tools/shrink_glb.py assets/figures/*.glb          # the defaults below
    python3 tools/shrink_glb.py assets/**/*.glb --max-dim 1024

Measured on the shipped set: 403 MB of .glb -> 180 MB, and the extracted
textures Godot writes beside them 254 MB -> 40 MB, with a mean difference of
about 1/255 per channel once the texture is resampled to the size it is
actually drawn at.

TWO THINGS THAT WILL BITE THE NEXT PERSON:

1. Godot re-extracts the texture on import (gltf/embedded_image_handling=1), and
   when the embedded image is JPEG it writes `foo_texture_0.jpg` and a BRAND NEW
   `.jpg.import` beside it -- leaving the old `foo_texture_0.png` orphaned. Both
   the .jpg and its .import have to be committed, and the stale .png removed.

2. That generated .import comes out with `compress/mode=0` (Lossless), and a
   lossless import bakes full-resolution data into the .pck. That is the exact
   bug commit 9443be1 fixed -- it took the web export over itch.io's hard 200 MB
   per-file cap. After running this, set the flag back and re-import:

       sed -i 's|^compress/mode=0|compress/mode=1|' assets/*/*_texture_*.jpg.import
       godot --headless --path . --import

   Verify with the size of .godot/imported: if it grew, the flag did not take.

Every embedded image in this project is RGB with no alpha channel (checked
across all 47 models), which is why JPEG is unconditionally safe here. A model
that arrives WITH alpha must be re-encoded as PNG instead (--format png), or its
cutouts will come back as opaque boxes.

Stdlib plus Pillow. It rewrites the .glb in place, so work on a clean tree.
"""
import struct, json, io, sys, os
from PIL import Image

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942

def read_glb(path):
    with open(path, 'rb') as f:
        magic, ver, length = struct.unpack('<III', f.read(12))
        assert magic == 0x46546C67, "not a glb"
        chunks = []
        while f.tell() < length:
            h = f.read(8)
            if len(h) < 8: break
            clen, ctype = struct.unpack('<II', h)
            chunks.append((ctype, f.read(clen)))
    j = dict(chunks)[JSON_CHUNK]
    b = dict(chunks).get(BIN_CHUNK, b'')
    return json.loads(j.decode('utf-8')), b

def write_glb(path, j, b):
    jb = json.dumps(j, separators=(',', ':')).encode('utf-8')
    jb += b' ' * ((4 - len(jb) % 4) % 4)          # pad with spaces, per spec
    bb = b + b'\x00' * ((4 - len(b) % 4) % 4)     # pad with zeros, per spec
    total = 12 + 8 + len(jb) + (8 + len(bb) if bb else 0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), JSON_CHUNK)); f.write(jb)
        if bb:
            f.write(struct.pack('<II', len(bb), BIN_CHUNK)); f.write(bb)

def shrink(path, max_dim=2048, quality=88, fmt='jpeg', dry=False):
    j, b = read_glb(path)
    views = j.get('bufferViews', [])
    # Which bufferViews are images, and what each should become.
    new_img = {}
    for img in j.get('images', []):
        if 'bufferView' not in img:
            continue
        bv = views[img['bufferView']]
        off, ln = bv.get('byteOffset', 0), bv['byteLength']
        im = Image.open(io.BytesIO(b[off:off+ln]))
        if max(im.size) > max_dim:
            n = max_dim
            im = im.resize((n, n) if im.width == im.height else
                           (n, int(im.height * n / im.width)) if im.width > im.height else
                           (int(im.width * n / im.height), n), Image.LANCZOS)
        out = io.BytesIO()
        if fmt == 'jpeg':
            im.convert('RGB').save(out, 'JPEG', quality=quality, optimize=True, progressive=False)
            mime = 'image/jpeg'
        else:
            im.save(out, 'PNG', optimize=True)
            mime = 'image/png'
        new_img[img['bufferView']] = (out.getvalue(), mime)
        img['mimeType'] = mime
    if not new_img:
        return None
    # Rebuild the binary chunk in bufferView order, so every offset stays sorted
    # and nothing else in the file has to know an image changed size.
    order = sorted(range(len(views)), key=lambda i: views[i].get('byteOffset', 0))
    buf = bytearray()
    for i in order:
        bv = views[i]
        if i in new_img:
            data = new_img[i][0]
        else:
            off, ln = bv.get('byteOffset', 0), bv['byteLength']
            data = b[off:off+ln]
        pad = (4 - len(buf) % 4) % 4                  # accessors need 4-byte alignment
        buf += b'\x00' * pad
        bv['byteOffset'] = len(buf)
        bv['byteLength'] = len(data)
        buf += data
    j['buffers'][0]['byteLength'] = len(buf)
    if dry:
        return len(buf)
    write_glb(path, j, bytes(buf))
    return len(buf)

if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('paths', nargs='+')
    ap.add_argument('--max-dim', type=int, default=2048)
    ap.add_argument('--quality', type=int, default=88)
    ap.add_argument('--format', default='jpeg', choices=['jpeg', 'png'])
    a = ap.parse_args()
    grand_before = grand_after = 0
    for p in a.paths:
        before = os.path.getsize(p)
        shrink(p, a.max_dim, a.quality, a.format)
        after = os.path.getsize(p)
        grand_before += before; grand_after += after
        print(f"  {p}: {before/1e6:.1f} -> {after/1e6:.1f} MB")
    print(f"total: {grand_before/1e6:.0f} -> {grand_after/1e6:.0f} MB")
