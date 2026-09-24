# assets/art/items — AI-generated item icons (SDXL)

**Every icon in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". 315 PNGs at
128 × 128, one per item id in `data/weapons.json`, `data/armor.json` and
`data/magic-items.json` (an id in two lists keeps its weapon/armor picture). The
inventory and the market draw them as tiles (`core/ui_icons.gd`).

## What ships: the repaint of 2026-09-16

All 315 files were last written by commit `44315c6` (2026-09-16, "every item icon
repainted in the game's hand"). What that commit records, and all there is:

- **Tool:** ComfyUI, run locally, from `~/localgen/regen_sorcmerc_items.py`. That
  script is **not in this repository.**
- **Model:** SDXL — "the same SDXL" as the first pass below, whose script names
  `sd_xl_base_1.0.safetensors`.
- **Settings:** a 1024 latent, 26 `dpmpp` steps, per-item seeds.
- **Prompt:** in the painted style of the counter portraits and road scenes
  (`assets/generated/PROVENANCE.md`), with "fuller nouns" ("a suit of chain mail on
  a stand" rather than "Chain Mail") and canvas / frame / concept-sheet in the
  negative.
- **Per-item prompts and seeds: not recorded.** The files carry no metadata: the
  downscale to 128 px dropped ComfyUI's `tEXt` chunk.

## The first pass, which no longer ships

The scripts that *are* in the repository made the first pass of 2026-09-15 (commits
`aa93d4c`, `02352d3`). Every one of those pictures was overwritten by `44315c6`, so
they describe how the set began, not what is in it now. Re-running
`tools/import_item_art.py` would put the first pass back.

| Script | What it made | Prompt | Seed |
|---|---|---|---|
| `tools/localgen/gen_sorcmerc_items.py` | `item_<kind>_<id>`, every item | `<name>, <category hint>, <rarity glow>, ` + `ICON_TAIL` ("fantasy RPG item icon, … digital painting, game asset, highly detailed, dramatic lighting") | 2000 + index |
| `tools/localgen/gen_single.py` | `try_<kind>_<id>_<n>`, three tries, the keeper copied to `item2_…` | `one single <name>, <hint>, ` + its `TAIL` | 7000 + 10 × index + try |
| `tools/localgen/gen_reroll.py` | `re_<kind>_<id>_<n>`, four each for 30 hard ids | its hand-written `SUBJECT` + `gen_single.TAIL` | 9000 + 10 × index + n |

All three: `sd_xl_base_1.0.safetensors`, 512 × 512 latent, KSampler `euler` /
`normal`, 18 steps, CFG 7.0 (`gen_sorcmerc_items.workflow()`). The pick per id is
`tools/item_art_picks.txt`, made by eye; `tools/import_item_art.py` copied the pick
in at 128 px.

## Licence

SDXL 1.0 is published under the CreativeML Open RAIL++-M licence. Read it before the
store page is filled in.
