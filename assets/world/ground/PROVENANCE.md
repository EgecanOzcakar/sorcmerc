# assets/world/ground — the overworld's painted ground (SDXL) and its shaders

This directory is **mixed**, an exception to the README's one-origin-per-directory
rule: the three textures are AI-generated, the three shaders beside them are written
by hand. The textures carry the Steam AI-content
disclosure obligation described in the README's "Assets and provenance"; the
shaders do not.

## grass.png, forest.png, water.png — AI-generated

The overworld's ground, three seamless 1024 × 1024 textures blended by
`ground3d.gdshader` under the cell mask `scenes/world/world.gd` builds.

- **Tool:** SDXL through the owner's local ComfyUI, from
  `~/localgen/gen_overworld_ground.py` — "the floor-texture pipeline in the game's
  painterly style" (commit `3317dbf`); the floor-texture pipeline is
  `tools/localgen/gen_floor_textures.py` (`assets/board/PROVENANCE.md`). The ground
  script itself is **not in this repository.**
- **Checkpoint, prompts and seeds: not recorded.** The files carry no metadata, and
  the script that made them is not here. Every SDXL render in the repository that
  records its checkpoint names `sd_xl_base_1.0.safetensors`.
- **Date:** landed 2026-09-16 (commit `3317dbf`, "the overworld ground is painted and
  its fog is soft").

SDXL 1.0 is published under the CreativeML Open RAIL++-M licence. Read it before the
store page is filled in.

## ground3d.gdshader, ground_mark.gdshader, foliage.gdshader — not AI

Written here as source; see `assets/world/README.md` for what each draws.
