#!/usr/bin/env python3
"""Turn a Meshy text-to-3D diorama into a low-poly, vertex-coloured model.

    python3 tools/lowpoly_glb.py assets/settlements/*.glb          # in place
    python3 tools/lowpoly_glb.py in.glb --out out.glb --faces 12000

WHAT IS WRONG WITH THE INPUT. Meshy output is photogrammetry-shaped: one fused
82k-triangle blob with no hard edges anywhere, wrapped in a 2048 atlas carrying
3.3k-5.3k UV islands about 25px across. A settlement is drawn 29-83px tall on
the world map, so that atlas is sampled around mip 5, where every island falls
below a texel and the whole model averages to the one brown the atlas is made
of. The geometry cannot save it either: a village is flat planes and straight
ridgelines, and reconstruction produces neither.

THE FOUR STEPS, IN THIS ORDER, BECAUSE EACH ONE NEEDS THE LAST:

1. WELD. Meshy splits a vertex at every UV seam — 67,847 vertices for 82,219
   faces. Decimating that collapses nothing and shreds the model into confetti;
   welding first takes it to 41,269 shared vertices. Colour is sampled from the
   atlas BEFORE the weld, while the UVs still exist, and rides along afterwards
   as a per-vertex attribute. That is also what retires the atlas: the .jpg and
   its mip chain go away, and the colour is in the mesh.

2. SMOOTH (Taubin). The reconstruction fuzz has to come off before decimation,
   or the decimator spends its triangle budget describing noise. Taubin's
   alternating shrink/inflate passes do it without deflating the building the
   way plain Laplacian does.

3. DECIMATE (quadric). 82k -> 4k. Quadric error collapses flat regions first,
   which is exactly right here: a roof slope becomes two triangles and the
   ridge line between slopes survives, because collapsing across it is what
   costs error.

   THE FACE BUDGET IS THE SMOOTHING CONTROL, which is not obvious and was
   measured rather than guessed. Taubin converges: 14, 35 and 60 iterations of
   it render identically, and raising lambda to 0.75 changes almost nothing
   either. What visibly takes the lumps out is decimating harder — the same
   noisy wall described with a quarter of the triangles IS fewer, bigger,
   flatter planes. 8k still reads busy up close; 4k is where a roof becomes a
   roof; 3k starts rounding the shapes off a tent.

4. FACET, and punch the colour. One normal and one colour per TRIANGLE. This is
   the step that makes it look sharp rather than melted — a smoothed, decimated
   mesh with interpolated normals is a lump of clay, and the same mesh faceted
   reads as planes meeting at a line, which is why the primitive kit
   (scenes/world/settlement_kit.gd) is legible at 48px in the first place. The
   colour punch is saturation and contrast about the model's own mean, because
   the atlas is one dim brown and three steps of it.

Godot needs `vertex_color_use_as_albedo` on the material to show any of this;
scenes/world/settlements3d.gd sets a flat one on every instance it builds.
"""
import argparse
import os

import numpy as np
import trimesh
import fast_simplification
from scipy.spatial import cKDTree

FACES = 4000
SMOOTH = 25
SAT = 1.35
CONTRAST = 1.15


def punch(c: np.ndarray, sat: float, contrast: float) -> np.ndarray:
    grey = c.mean(axis=1, keepdims=True)
    c = grey + (c - grey) * sat
    mean = c.mean()
    return np.clip(mean + (c - mean) * contrast, 0, 255)


def lowpoly(src: str, out: str, faces=FACES, smooth=SMOOTH, sat=SAT,
            contrast=CONTRAST, lamb=0.53, nu=0.51) -> None:
    scene = trimesh.load(src)
    m = scene.to_mesh() if hasattr(scene, "to_mesh") else scene
    cols = trimesh.visual.color.uv_to_color(m.visual.uv, m.visual.material.baseColorTexture)
    w = trimesh.Trimesh(vertices=m.vertices, faces=m.faces, vertex_colors=cols,
                        process=True, validate=True)
    w.merge_vertices()
    c = np.asarray(w.visual.vertex_colors, dtype=np.float64)[:, :3]
    rough = np.asarray(w.vertices, dtype=np.float32).copy()
    if smooth:
        trimesh.smoothing.filter_taubin(w, lamb=lamb, nu=nu, iterations=int(smooth))
    v = np.asarray(w.vertices, dtype=np.float32)
    f = np.asarray(w.faces, dtype=np.int32)
    v2, f2 = fast_simplification.simplify(v, f, max(0.0, 1.0 - float(faces) / len(f)))
    # Look the colour up against the pre-smoothing positions: smoothing moved
    # the surface, and a lookup against the moved cloud drags roof colour down
    # walls wherever a ridge got rounded.
    c2 = punch(c[cKDTree(rough).query(v2, k=6)[1]].mean(axis=1), sat, contrast)
    vf = v2[f2].reshape(-1, 3)
    ff = np.arange(len(vf), dtype=np.int64).reshape(-1, 3)
    cf = np.repeat(c2[f2].mean(axis=1), 3, axis=0)
    flat = trimesh.Trimesh(vertices=vf, faces=ff, process=False,
        vertex_colors=np.hstack([cf, np.full((len(cf), 1), 255.0)]).astype(np.uint8))
    flat.vertex_normals = np.repeat(flat.face_normals, 3, axis=0)
    was = os.path.getsize(src)
    flat.export(out)
    print("%-22s %6d -> %5d faces   %5.1f MB -> %4.2f MB" % (
        os.path.basename(out), len(m.faces), len(f2), was / 1e6,
        os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="+")
    ap.add_argument("--out", default="")
    ap.add_argument("--faces", type=int, default=FACES)
    ap.add_argument("--smooth", type=int, default=SMOOTH)
    ap.add_argument("--sat", type=float, default=SAT)
    ap.add_argument("--contrast", type=float, default=CONTRAST)
    ap.add_argument("--lamb", type=float, default=0.53)
    ap.add_argument("--nu", type=float, default=0.51)
    a = ap.parse_args()
    if a.out and len(a.src) > 1:
        raise SystemExit("--out takes one source")
    for path in a.src:
        lowpoly(path, a.out or path, a.faces, a.smooth, a.sat, a.contrast, a.lamb, a.nu)
