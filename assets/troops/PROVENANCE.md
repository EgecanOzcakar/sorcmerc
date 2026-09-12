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
