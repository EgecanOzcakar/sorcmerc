# T-tiles spike — realistic/colorful alternate ground tileset (not the default)

Source: Screaming Brain Studios' "Isometric Tiles - Floor Pack"
(https://screamingbrainstudios.itch.io/isotilepack), the "Large 256x128"
download, Exterior/Grass, Exterior/Flora, Exterior/Elements tile-sets.
License: CC0, confirmed directly by the author in the pack's own comment
thread ("License is CC0, there are no restrictions... commercial or
non-commercial") — same studio, same license class as the current terrain
pack already vendored in `assets/world/overworld/`.

## Why this one is a clean drop-in (unlike the Kenney spike)

Screaming Brain Studios' whole isometric floor line is rendered the same
way the current terrain pack is: genuine flat 2:1 isometric photo-textured
diamonds, magenta chroma-keyed background, one 256x128 diamond per cell in
a 3-column sheet — the *exact* layout `World._draw_ground()` already
expects. No cropping workaround, no leftover bevel/dirt sliver. The three
sheets here (`terrain_sbs.png`, `forest_sbs.png`, `water_sbs.png`) are the
source PNGs used almost as-is: magenta re-keyed to real alpha transparency
(Pillow, exact-match on (255,0,255)), nothing else changed.

## Style

Real photographic grass/moss/flower/water textures instead of flat painted
color — reads as noticeably more "realistic" than either the current pack
or the Kenney spike, with the floral accent tiles (pink blossoms, yellow
dandelions) and vivid blue water giving the colour pop the current muted
palette doesn't have.

## Usage

`SORCMERC_ALT_TILES=sbs` (world.gd) — alongside `=kenney` for the earlier
spike. Neither is the new default.
