# World map art

Nothing here is licensed from anyone: the ground textures are **AI-generated**
and the shaders are **written by hand**. The CC0 packs that used to be here are
listed under "Retired art" at the bottom.

| File | Origin | Recorded in |
|------|--------|-------------|
| `ground/{grass,forest,water}.png` | **AI-generated**: SDXL through a local ComfyUI (`~/localgen/gen_overworld_ground.py`, not in this repository), made seamless. The overworld's painted ground, blended by `ground/ground3d.gdshader`. Carries the Steam AI-content disclosure obligation. | `ground/PROVENANCE.md` |

The three shaders next to them are written here, not sourced:

* `ground/ground3d.gdshader` — the ground itself, on the 3D map's ground mesh.
  Blends the three textures above by the cell mask `scenes/world/world.gd`
  builds (R forest, G water, B explored) and folds the fog in.
* `ground/ground_mark.gdshader` — the footprint under a landmark: shadow, lit
  disc, faction ring, drawn as one instanced quad per landmark lying on the
  ground.
* `ground/foliage.gdshader` — the woods, which `scenes/world/scatter3d.gd`
  builds out of primitives rather than loading from anywhere.

## Retired art, and why

**Overworld tiles (O11).** The Screaming Brain Studios Overworld pack, and the
Kenney / SBS Floor Pack spikes, drew the ground as per-cell diamonds until the
painted ground shader replaced them; their provenance notes went with the files.

**Buildings (O12) and party tokens (O14).** rubberduck's isometric medieval
buildings (`town/buildings.png`, built by `tools/pack_buildings.py`) and
Kenney's Board Game Pack pawn (`tokens/pawn.png`) were the map's 2D prop tier:
a painted building cluster drawn on a settlement's footprint, and a flat pawn
sprite standing on a party's position, each a fallback for the cases the 3D
models did not cover.

They went with that tier when the map became a real 3D world. A flat sprite
pasted over the map only ever stood in for a model, and a camera that can be
turned walks straight round the back of one. Every landmark is a model now —
`scenes/world/settlements3d.gd`, `lairs3d.gd` and `party3d.gd`, with the
settlement and lair kits building from primitives for anything the generated
GLBs do not cover, and a band with no character figure marching as a 3D pawn —
so there is nothing left for a sprite tier to fall back to. Both packs are CC0
and both are one download away if a 2D map ever wants them again; the sheets
and the packer are in git history at the commit that removed them.
