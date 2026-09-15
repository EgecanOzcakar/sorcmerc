# Lair dioramas

## goblin-warren.glb
Source: Meshy Community feed (meshy.ai/discover), downloaded by the user
directly through the web UI — not generated via our API. Filename as
downloaded: "Meshy AI Goblin Camp Fortifica[tion]_0912210319_texture.glb".
License: CC0 1.0 (Meshy ToS §3.3 — anything published to the Community page
is CC0, no attribution required). Static mesh, no rig/animation (not
needed — lairs are scenery, same as the Meshy-generated settlement
dioramas in assets/settlements/).

## giant-hold.glb / dragon-cave.glb
Meshy chain: preview -> refine (2k, no PBR) -> remesh (80k tris), same as
the settlement dioramas — static, no rig/animation. Generated via
kitbashforge/run_lairs.py, 20 credits each.

## sunken-ruins / zombie-graveyard — no model here, and none needed
These two were deferred on the theory they would turn up on Meshy's Community
feed (kitbashforge/NEXT_BATCH.md). They are named in `Lairs3D.MODELS` with
paths that do not exist, so until recently both rendered as
`World._draw_lair()`'s skull glyph beside three 3D neighbours.

They are now built by `scenes/world/lair_kit.gd` instead: primitives assembled
in code, no asset file, and therefore **not AI-generated** — nothing about
these two carries the README's Steam AI-content disclosure obligation. If a
GLB is ever generated for either, dropping the file in beside the other three
is enough: `Lairs3D._build()` prefers whichever source `Lairs3D.source` names
and falls back to the other, so no registry edit is needed.

The same kit also builds the three above, for comparison only — see
`tests/shot_lair_kit.gd`. On the evidence there the generated models win on all
three, which is the opposite of the settlement result and not a surprise: a
cave and a rock pile are the fused organic volumes text-to-3D is good at.

Not yet wired into any rendering registry — scenes/world/world.gd's
`_draw_lair()` still draws the plain skull marker. A Lairs3D layer
(same pattern as Settlements3D) is the next step now that there are
three lair models (goblin-warren, giant-hold, dragon-cave) to justify it.
