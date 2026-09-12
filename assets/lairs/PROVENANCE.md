# Lair dioramas

## goblin-warren.glb
Source: Meshy Community feed (meshy.ai/discover), downloaded by the user
directly through the web UI — not generated via our API. Filename as
downloaded: "Meshy AI Goblin Camp Fortifica[tion]_0912210319_texture.glb".
License: CC0 1.0 (Meshy ToS §3.3 — anything published to the Community page
is CC0, no attribution required). Static mesh, no rig/animation (not
needed — lairs are scenery, same as the Meshy-generated settlement
dioramas in assets/settlements/).

Not yet wired into any rendering registry — scenes/world/world.gd's
`_draw_lair()` still draws the plain skull marker. A Lairs3D layer
(same pattern as Settlements3D) is the next step once there's more than
one lair model to justify it.
