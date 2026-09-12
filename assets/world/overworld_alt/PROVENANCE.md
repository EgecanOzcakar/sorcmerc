# T-tiles spike — alternate ground tileset (not the default)

Source: Kenney's "Isometric Tiles Landscape" pack
(https://kenney.nl/assets/isometric-tiles-landscape), 128 assets, CC0 1.0 —
no attribution required, same license class as the pawn token and the
current terrain pack already vendored in `assets/world/`.

## Why this isn't a straight drop-in

Kenney's whole isometric line (Landscape, City, Buildings, Blocks, Roads) is
drawn as raised 3D blocks — a flat colored top face plus visible dirt/stone
side faces, like a floating platform. The current terrain pack
(`assets/world/overworld/`, Screaming Brain Studios) is genuinely flat: a
continuous diamond tileset with no implied elevation, which is what
`World._draw_ground()`'s tiling math assumes (adjacent diamonds share edges
exactly, no gaps).

`terrain_alt.png`/`forest_alt.png`/`water_alt.png` here are built by cropping
just the top face off a few Kenney tiles (`landscapeTiles_010`/`016`/`014`/
`020`) and resizing to the 256x128 cell size the existing sheet layout
expects — same technique, wrong source material. The crop can't fully
remove the block's front-corner dirt sliver (it's baked into where the top
face's own edge-shading ends and the side begins), so tiled together it
reads as a grid of slightly-bevelled tiles with a thin brown seam at each
tile's front corner, instead of one continuous field.

## Verdict

Technically swappable (SORCMERC_ALT_TILES=1 env var, see world.gd), and the
CC0 licensing is as clean as it gets — but the visual result changes the
map's language from "flat painted ground" to "a grid of little raised
platforms," which is a real style shift, not a like-for-like reskin. Kept
as an opt-in comparison, not the new default. If this direction is wanted,
the next step is a Kenney pack (or hand-authored tiles) actually drawn
flat, not this crop-a-block workaround — Kenney's isometric catalog is
uniformly block-style, so that means a different source, not a better crop.
