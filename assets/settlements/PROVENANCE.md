# assets/settlements — AI-generated settlement dioramas (Meshy)

**Every model in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Twelve
`.glb` dioramas, `<species>_<size>.glb` for dwarf, elf, human and orc at camp, town
and city, drawn on the overworld by `scenes/world/settlements3d.gd` (its default
source, `"glb"`; `scenes/world/settlement_kit.gd` builds from primitives instead,
and is not AI).

## Generation — 2026-09-12

- **Tool:** Meshy text-to-3D, through the Meshy API from the owner's
  `~/kitbashforge/run_settlements.py` (commit `3b18f56`). The chain was preview ->
  refine -> remesh, static, no rig (`assets/lairs/PROVENANCE.md` describes the same
  chain for the lairs). That script is **not in this repository.**
- **Model version, task ids and credits: not recorded.**
- **Prompts: not recorded.** Only fragments survive, in the commit messages:
  - `human_city`, `orc_city` (commit `5d18d00`) were regenerated with "the size
    phrase pushed toward 'densely populated... market stalls and crowds... narrow
    streets'". `dwarf_city` and `elf_city` came back from that regeneration as
    rubble, so those two ship their first generation.
  - `dwarf_camp` (commit `9cd872c`) was regenerated with "the stone anchor pushed
    harder (carved into rock, timber only as supports, mining cart)" after the first
    pass read as a wooden workshop.
- **Date:** all twelve generated and committed 2026-09-12.

## Rebuilt low-poly — 2026-09-16 (not AI)

Commit `ff2448f` rebuilt all twelve in place with `tools/lowpoly_glb.py`: weld,
Taubin smooth, quadric decimation to about 4k faces, then one normal and one colour
per triangle, the Meshy texture atlas baked into vertex colour and deleted. The
shapes and colours are still the generated ones, so the rebuild does not change what
the disclosure has to say. The `.glb` generator field now reads trimesh.

Licence: Meshy output, generated through the owner's own account. Commercial rights
depend on the Meshy plan it was generated under; see the Meshy ToS before shipping.
