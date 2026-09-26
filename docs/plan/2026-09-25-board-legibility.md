## Board legibility — one wash per tile, a board that keeps up with its figures, bars inside the board, ash that is not a shadow (2026-09-25)

Four reports against the combat view, filed with 4K screenshots this session
could not open (#195, #239, #242, #243). Each was reproduced from its title
with a new dev shot script, `tests/shot_board_legibility.gd`, which zooms and
pans through the same two calls the mouse wheel and a drag make. Where the
cause could be seen in a picture it was fixed; where a title could mean more
than one thing, the entry says which reading this is.

**#242 — "height difference shows the overlap color, just keep the high and
visible color".** The ground has painted back to front since #156, so a raised
tile hides the ground behind it. The per-frame overlays on top of the ground
did not: the move field, a spell's reach, a lingering zone, the night, the
exit road, the edge rims and the target rings were drawn per hex in board
order at the full size of the hex. So the wash of a low tile behind a shelf
spilled up over the shelf's top face, and where that face had its own wash the
two stacked into a deeper third colour in a band across the step. Board now
works out, once per board, which higher tiles stand in front of each hex
(`_covering`: only a higher tile in front can cover one, and only by its top
face), and every overlay goes through `_fill_seen` / `_ring_seen`, which cut it
by those faces with `Geometry2D.clip_polygons` / `clip_polyline_with_polygon`
before drawing. A flat board has no list and draws exactly what it did.
Picture: `docs/shots/issue-242-height-overlay.png` (before left, after right).

**#239 — "z fighting shown in combat".** Read as: two copies of the same
thing on screen, disagreeing about depth. The one found was the board's own
layer falling behind. The figures (Figures3D) and the HP bars (the HUD layer)
are placed every frame; Board's `_draw()` only runs when something queues it,
and a view that moved inside a `_layout()` — the pan clamp, the rect settling,
a zoom the follow-cam finished — queued nothing. Every token's shadow disc and
the gold active ring then stayed where the tokens used to be: dark rings on
empty tiles under nobody, stacked on the floor texture, and a ring with no one
in it. `_rebase_view()`, which already notices the view moving to carry the
tokens, now queues the repaint as well (the same family as #194 was for the
ground). The #242 fix covers the other place two tiles' colours were being
drawn over one spot. Picture: `docs/shots/issue-195-239-hud-and-stale-board.png`
(before top, after bottom: the empty gold ring and the two dark discs on the
right are gone).

**#195 — "Z fighting bug exists in the health bars on fighting screen".**
T-hud moved HP bars onto a CanvasLayer above everything, and that layer was
the whole window. A body panned or zoomed off the board's edge, or standing on
its bottom row, painted its bar and "21/21" over the log, the order strip, the
actor line and the skill bar — two health readouts in one green fighting for
one spot. The bars are on their own Control now (`main._hud_bars`), sized to
the board's rect every frame and clipping to it; the odds chip, barks, damage
numbers and the roll reveal stay on the unclipped overlay above it. And the
bars were painted in roster order, so where two overlapped the one fielded
first went under; they are painted back to front now, the order the figures
stand in. Same picture as #239.

**#243 — "ash model is too dark, it is mistaken as erroneous shadow".** The
goblin camp's rough is the Meshy `ash` model, a low mound whose albedo averages
0.157 — darker than the camp's dirt and the exact look of a stray shadow blob.
`BoardProps.build` now multiplies that model's material (`MODEL_TINT`, a
shared per-kind duplicate, never the cached scene) to the grey of a cold
hearth, and lays two charred logs and three embers over it (`dressing()`, also
part of the kit's own ash plan, which moves from the `dark` role to a new pale
`ash` one). A glow on the mound itself was tried first and turned every pile
into an orange disc that read as the campfire's hazard tile, so it was taken
out. Everything stays under rough's 0.55 and inside the kit's 420-triangle
budget (`tests/test_board_props.gd`). Picture:
`docs/shots/issue-243-ash.png` (before left, after right).

`tests/test_board_legibility.gd` pins what can be read back headless: a wash
behind a raised tile loses exactly the part the tile's face covers and none of
it lands on that face, a flat board's washes are whole; a view moved inside the
layout repaints the board (fails with the one-line fix taken out); the bars'
Control is the board's rect, clipped, under the overlay; the ash's lifted mean
is at least 0.45, its dressing is laid over the model, and the shared model
keeps its own material. No rule, save field, balance number or content-pack
surface changed.

### Still open

- **#239 may be more than this.** The reporter's screenshot could not be read.
  Two other candidates were looked at and not changed, for want of evidence in
  a picture: the sun's shadows in the figures' SubViewport (shadow acne on the
  figures and props — none visible at 3x zoom on llvmpipe, with the shadows on
  and off side by side), and a hex that carries two props at once (the
  shrine's mirror, `Encounter._widen`, lands rough on a cover hex and on a
  pillar's hex in every one of 59 seeds tried, so rubble stands inside a
  pillar; they interpenetrate, but no coplanar faces were seen flickering). If the report
  was either, the fix is `directional_shadow_mode` / bias on the figures' sun,
  or one prop per hex in `Figures3D._reset_props`.
- **Nothing 3D is hidden by a shelf.** A figure or prop standing on low ground
  behind a raised tile is drawn over that tile's face, because the whole 3D
  layer sits above the 2D board. The fix is depth-only occluders for raised
  tiles in the figures' world, which needs a colour-less depth write the
  Compatibility renderer does not make easy; revisit if shelves get taller
  than one or two levels.
- **The hazard tile still repaints unclipped.** A pulsing hazard hex is
  repainted each frame with `_paint_tile`, which is not cut by the shelves in
  front of it, so a brazier's hex directly behind a shelf still paints its
  glow over the shelf's face. `_paint_tile` draws a dozen primitives, so the
  clip is more than a wrapper; do it when a shot shows it.
