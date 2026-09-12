# Troop figures

Generic per-faction troop archetypes (spellcaster / heavy-armored /
light-armored), separate from the per-class hero figures in
`assets/figures/`. Meshy chain: preview -> refine (2k, no PBR) -> remesh
(50k tris) -> rig (1.2m) -> Idle animation. Same pipeline as the class
roster (`kitbashforge/run_troops.py`).

Generated 2026-09-12. 8 of 12 succeeded before the batch ran out of
credits (see `kitbashforge/NEXT_BATCH.md` for the remaining 4 —
orc_heavy, orc_light, orc_spellcaster, human_light — and their prompts).

Present here: dwarf_light, dwarf_spellcaster, dwarf_heavy, elf_spellcaster,
elf_heavy, elf_light, human_spellcaster, human_heavy.

## orc_heavy_idle.glb — different provenance from the rest
Source: Meshy Community feed, downloaded by the user directly ("Meshy AI
Orc Warrior_0912210431_texture.glb"). License: CC0 1.0 (Meshy ToS §3.3).
Remeshed through our own account (kitbashforge/run_community_rig.py) to
get it Meshy-hosted and under our polycount limit, then rigging failed
(HTTP 422, pose estimation) — the community mesh doesn't face +Z the way
our own A-pose generations do, and there's no bpy/Blender step in this
pipeline to reorient it. Kept as a static mesh: no idle animation, same
documented fallback as `ranger_idle.glb`. Visually a clear step up from
what generation produced for the same archetype — worth the 5-credit
remesh cost.

**Not wired into any registry yet.** Two features still need designing
before these do anything in-game:
1. Overworld party representation: a RoamingParty needs an actual troop
   roster (role + level per troop) before "the highest-leveled troop
   picks the model" means anything — RoamingParty currently only carries
   a faction string.
2. Combat use: these are race archetypes, not bestiary factions
   (goblinoid/bandit/soldier/cultist/kobold/undead) — figures3d.gd's
   FOE_MODELS is keyed by the latter. When/whether a race troop stands in
   for a bestiary faction in combat is an open design question, not
   assumed here.
