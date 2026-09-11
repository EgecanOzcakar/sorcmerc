# Isometric sprite-art experiment — asset provenance

Everything in this directory is sliced out of **one** upstream pack. Siloed here
on purpose: this is a feasibility spike, not part of the shipping asset set.

## Pack

- **Name:** Tiny Tactics — Battle Kit I (v1.0)
- **Author:** Gabriel "tiopalada" Lima (OpenGameArt user `tiopalada`)
- **Source page:** https://opengameart.org/content/tiny-tactics-battle-kit-i
- **Archive downloaded:** https://opengameart.org/sites/default/files/tinytactics_battlekiti_v1_0.zip
- **License:** CC0 1.0 Universal (public domain dedication)
- **License URL:** https://creativecommons.org/publicdomain/zero/1.0/

License verified two ways, not from a search snippet:

1. The OpenGameArt submission's `License(s):` field reads `CC0`, linking to
   the CC0 1.0 deed.
2. The archive itself ships `license.html`, whose text is:
   *"Tiny Tactics - Battle Kit I by Gabriel \"tiopalada\" Lima is marked with CC0 1.0"*.

CC0 waives copyright to the extent possible worldwide; no attribution is
required. This file exists for our own auditability, not to satisfy a licence
term.

## What was taken, and from where

Ground tiles, sliced out of `20240420tinyTacticsTileset00.png` (512x416, a
16x13 grid of 32x32 cells; coordinates below are column,row):

| file | cell |
|---|---|
| `tile_grass.png` | 12,8 |
| `tile_dirt.png`  | 12,0 |
| `tile_stone.png` | 9,5  |
| `tile_water.png` | 6,2  |
| `tile_tree.png`  | 1,3  |
| `tile_rock.png`  | 0,4  |

Units — frame 0 of each class's south-east walk strip, used as a static idle
pose (`unit_fighter.png`, `unit_mage.png`, `unit_cleric.png`, from
`20240427{fighter,mage,cleric}-walkingSE.png`).

The upstream pack also contains 4 animations x 10 states per character, NE
facings, 6 animated weapons and 200+ terrain tiles — none of that is pulled in
yet. Re-download the archive above to get at it.
