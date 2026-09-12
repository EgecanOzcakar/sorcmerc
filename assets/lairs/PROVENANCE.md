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
kitbashforge/run_lairs.py, 20 credits each. Remaining two lairs
(sunken-ruins, zombie-graveyard) are still deferred — high likelihood of
already existing on Meshy's Community feed, per kitbashforge/NEXT_BATCH.md.

Not yet wired into any rendering registry — scenes/world/world.gd's
`_draw_lair()` still draws the plain skull marker. A Lairs3D layer
(same pattern as Settlements3D) is the next step now that there are
three lair models (goblin-warren, giant-hold, dragon-cave) to justify it.
