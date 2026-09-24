# assets/npcs — named-NPC figures (Meshy Community feed)

**The one model here is AI-generated** (a Meshy Community upload) and carries the
Steam AI-content disclosure obligation described in the README's "Assets and
provenance" for as long as it ships.

Reserved for a specific hero/NPC rather than the generic class or troop
rosters (figures3d.gd's HERO_MODELS/FOE_MODELS are keyed by class/faction,
not by individual character — this directory is for the exception).

## female_mage.glb

- **Source:** Meshy Community feed, downloaded by the user directly ("Meshy AI
  Beautiful female mage_0912194205_texture.glb"). License: CC0 1.0 (Meshy ToS §3.3).
- **Landed:** 2026-09-13 (commit `29ec58a`). Its author, Meshy model, prompt and
  generation date are not recorded.
- Static mesh, no rig/animation — not run through `run_community_rig.py` since there
  is no character or combat use picked for it yet. `female_mage_0.jpg` is the texture
  Godot extracted from it on import.

**Unused.** No script, scene or data file names it (checked 2026-09-24), yet it is in
the export (`export_presets.cfg` exports all resources). Either assign it to a named
character and rig it (remesh -> rig -> Idle through `run_community_rig.py`, the route
`assets/troops/orc_heavy_idle.glb` took, whose rig step failed on pose estimation),
or delete it, and with it the line in the disclosure.
