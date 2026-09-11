# World map art (O11)

Both packs are by **Screaming Brain Studios** and released under **CC0 1.0 /
Public Domain** — no attribution is required; this note is the paper trail the
expansion plan asks for. Each pack's own `License.txt` is kept next to its files.

| File | Source pack | Original file |
|------|-------------|---------------|
| `overworld/terrain.png` | [Isometric Tiles: Overworld Pack](https://screamingbrainstudios.itch.io/iso-overworld-pack) | `Overworld - Large/Flat/Overworld - Terrain 1 - Flat 256x128.png` |
| `overworld/forest.png` | same | `Overworld - Large/Flat/Overworld - Forest - Flat 256x128.png` |
| `town/buildings.png` | [Isometric Tiles: Town Pack](https://screamingbrainstudios.itch.io/iso-town-pack) | `Building Tiles/Isometric Buildings 3 - 64x96.png` |

## The one edit made to the files

The packs ship as RGB PNGs with a **colour-key** background rather than alpha —
the keys are declared in each pack's Tiled `.tsx` (`trans="000000"` for the
overworld tiles, `trans="008080"` for the town tiles). Godot draws alpha, not
colour keys, so every pixel exactly equal to the key colour was set to alpha 0
and the files re-saved as RGBA. Nothing else was touched: no rescaling, no
recolouring, no cropping. To redo it from a fresh download, key out
`#000000` / `#008080` by exact RGB match.

Unused, and why: the packs' `Thick` variants (tiles with a visible soil edge)
would double-draw at the seams on a tessellated grid, and the Overworld water
tiles have nothing to key off — `core/world.gd` has no terrain map, so the
ground is a hashed grass/forest mix. Water lands with terrain data, not before.
