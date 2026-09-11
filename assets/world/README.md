# World map art (O11, buildings re-done in O12, party tokens O14)

Everything here is **CC0 1.0 / Public Domain** — no attribution is required;
this note is the paper trail the expansion plan asks for. Each pack's own
`License.txt` is kept next to its files.

| File | Source pack | Author | Original file |
|------|-------------|--------|---------------|
| `overworld/terrain.png` | [Isometric Tiles: Overworld Pack](https://screamingbrainstudios.itch.io/iso-overworld-pack) | Screaming Brain Studios | `Overworld - Large/Flat/Overworld - Terrain 1 - Flat 256x128.png` |
| `overworld/forest.png` | same | same | `Overworld - Large/Flat/Overworld - Forest - Flat 256x128.png` |
| `town/buildings.png` | [Isometric medieval buildings](https://opengameart.org/content/isometric-medieval-buildings) + [part 2](https://opengameart.org/content/isometric-medieval-buildings-2) | rubberduck | the `128x64_shaded` frames `00`–`03` of all 5 buildings, out of both `*_single.zip` downloads |
| `tokens/pawn.png` | [Board Game Pack](https://kenney.nl/assets/boardgame-pack) | Kenney | `PNG/Pieces (White)/pieceWhite_border00.png` |

## The edits made to the files

**Overworld tiles (O11).** The pack ships RGB PNGs with a **colour-key**
background rather than alpha — the keys are declared in its Tiled `.tsx`
(`trans="000000"`). Godot draws alpha, not colour keys, so every pixel exactly
equal to the key colour was set to alpha 0 and the files re-saved as RGBA.
Nothing else was touched: no rescaling, no recolouring, no cropping. To redo it
from a fresh download, key out `#000000` by exact RGB match.

**Buildings (O12).** `tools/pack_buildings.py` builds the 640x480 sheet from the
two packs' single-frame downloads; run it to redo the file. What it does, and
why, in short:

* Each of the 5 buildings ships 8 frames — 4 camera rotations plain (`00`–`03`)
  and the same 4 **snowy** (`04`–`07`) — in **sun-shaded / cloudy / no-shadow**
  variants, at 128x64 and 64x32 tile format. We take **128x64, sun-shaded**
  (`*_shaded`), consistently: the map's own props are lit by a fixed sun
  (`world.gd`'s `LIGHT`) and `_soft_shadow`, so a baked sun shadow is the one
  variant that agrees with them. The snowy frames are skipped — the world has no
  seasons or climate to switch on, so they would be dead art.
* The 5 frames are laid out as one sheet, 5 columns (building) x 4 rows
  (rotation), 128x120 per cell.
* Everything is scaled by **one shared factor** (0.125). The packs render every
  building at the same pixels-per-world-unit but on its own square canvas
  (512–1024px), so normalising each canvas to the cell would make the market
  shed as big as the manor.
* The cells are aligned on the building's **near ground corner**, found per
  frame as the bottom-centre of the *no-shadow* variant's alpha bounding box
  (with the shadow in, the box is skewed towards the sun). The canvases are not
  consistently padded, so this cannot be assumed. That corner is
  `world.gd`'s `BUILDING_ANCHOR`, i.e. the `base` argument of `_draw_building()`.

Unused, and why: the packs' 64x32 renders (we downscale from the large ones
instead, which is sharper at zoom), the cloudy/no-shadow variants, the snowy
variants (above), the `.blend` sources, the Overworld pack's `Thick` variants
(a visible soil edge double-draws at the seams on a tessellated grid) and its
water tiles (`core/world.gd` has no terrain map, so the ground is a hashed
grass/forest mix — water lands with terrain data, not before).

**Party tokens (O14).** O10 left open whether Kenney's board-game art has real
pawn shapes or only dice/card iconography. Both packs were downloaded and
looked at: **Board Game Icons** is pure UI iconography (card/dice/turn symbols,
a flat `pawn.png` glyph among them) — not token art. **Board Game Pack** does
have it: `PNG/Pieces (<colour>)` ships 19 flat-shaded board pieces (pawn, tall
pawn, meeple, house, rook, wagon, boat, plane, train, flag) in 7 colours x 3
variants (`single` plain, `border` with a rim + drop shadow, `multi`).

Taken: the classic pawn, `border` variant, in **White** — its art is flat
`#f3f3f3` with a darker rim, so one file tints to any faction colour via
`draw_texture_rect`'s modulate and the per-colour folders are not needed (the
faction palette in `world.gd`'s `faction_color()` is hash-derived and wouldn't
map onto 7 fixed colours anyway). The only edit is a **crop to the sprite's
alpha bounding box** (64x64 -> 30x53, `PAWN` in `world.gd`), so the draw rect
is the silhouette itself and the token's feet land on the party's ground point.
No rescaling, no recolouring.

Unused, and why: the other 18 piece shapes (nothing in `core/world.gd`
distinguishes a caravan from a warband yet — one silhouette is the whole
vocabulary the map has), the 6 coloured folders and the `single`/`multi`
variants (tinting one white sprite covers it), the Board Game Icons pack
entirely, and the packs' dice/card/chip art (no board-game UI here).
