# assets/board — combat-board props and floors (AI-generated, two tools)

**Everything in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Two sets,
from two different generators.

## The 22 props — Meshy

`ash`, `barrel`, `bramble`, `brazier`, `campfire`, `crate`, `crate-low`,
`crate-stack`, `floe`, `fountain`, `gorse`, `icicle`, `lamp`, `menhir`, `pillar`,
`reeds`, `rubble`, `shelf`, `stakes`, `torch`, `tree`, `tussock` — each a `.glb`
plus its albedo texture, `<kind>_albedo.jpg`. `scenes/board_props.gd` draws
the model where one exists and fits it to the primitive kit's box.

- **Tool:** Meshy. The batch was downloaded by the owner as "1.5 GB of Meshy output
  at 1-5M triangles a file", `bush` standing in for `bramble` (build log, "Board
  props from models, fitted to the kit", 2026-09-23).
- **Model version, prompts, and whether each was the owner's own generation or a
  Community-feed download: not recorded.** The downloads lived in a gitignored
  folder; only the converted output is committed.
- **Date:** landed 2026-09-23 (commit `dda308d`). The generation date is not recorded.
- **Processing (not AI):** `tools/import_beasts.py` with `DST=assets/board
  TRIS=10000 --force` — gltfpack to 10k triangles, albedo only, resampled to 1024 by
  `tools/shrink_glb.py`.

Licence: Meshy output. Commercial rights depend on the Meshy plan the owner generated
under (a Community download is CC0 under Meshy ToS §3.3); see the Meshy ToS before
shipping.

## The 8 floors — SDXL

`floor_<theme>.png`, 512 × 512, one per `Encounter.THEMES` board, drawn on every hex
by `scenes/main.gd`. Made by `tools/localgen/gen_floor_textures.py` through a local
ComfyUI, then made tileable by that script's `seamless()` (a half-offset cross-fade,
not AI).

- **Model and settings:** `sd_xl_base_1.0.safetensors`, 512 × 512 latent, KSampler
  `euler` / `normal`, 18 steps, CFG 7.0 (the workflow in
  `tools/localgen/gen_sorcmerc_items.py`, which the floor script calls).
- **Prompt:** `<subject>, ` + the script's `TAIL`: "seamless tileable texture, top-down
  view, flat even lighting, no shadows, no objects, fantasy game ground material,
  muted dark colours, subtle detail, photorealistic, 4k".
- **Negative:** the script's `NEG`: "seams, border, frame, objects, creatures, text,
  watermark, perspective, horizon, sky, bright, blurry, low quality".
- The files themselves carry no metadata (`seamless()` re-saves them), so this is
  read from the script as committed; the seed is `4300 + index` in its `PALETTES`.

| File | Landed | Seed | Subject |
|---|---|---|---|
| `floor_shrine.png` | 2026-09-15 `61f6c1c` | 4300 | top-down photo of old wet grey stone floor slabs, irregular flagstones, moss in the joints |
| `floor_camp.png` | 2026-09-15 `61f6c1c` | 4301 | trampled dirt and ash of a goblin camp, scattered straw and bones, dark brown |
| `floor_city.png` | 2026-09-15 `61f6c1c` | 4302 | worn cobblestones of a city square, dark grey with faint rain sheen |
| `floor_forest.png` | 2026-09-15 `61f6c1c` | 4303 | top-down photo of a forest floor, dark soil under brown dead leaves and patches of green moss |
| `floor_ice.png` | 2026-09-15 `61f6c1c` | 4304 | cracked frozen cave floor, blue-grey ice with frost, dark |
| `floor_shop.png` | 2026-09-15 `61f6c1c` | 4305 | old oak floorboards of a merchant shop, dark stained wood with dust |
| `floor_downs.png` | 2026-09-22 `b0992f8` | 4306 | extreme close-up macro photo of dry turf surface, dense fine grass blades and moss at ground level, flat material swatch, no horizon, no landscape, no paths, muted olive grey-green |
| `floor_marsh.png` | 2026-09-22 `b0992f8` | 4307 | top-down photo of marsh ground, dark peat water between mats of reed and sedge, silt and rotting leaves, muted brown-green |

The downs prompt took three tries (`b0992f8`); the two that failed asked for "open
moorland", and only the third is recorded.

SDXL 1.0 is published under the CreativeML Open RAIL++-M licence. Read it before the
store page is filled in.
