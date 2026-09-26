# assets/troops — AI-generated troop figures (Meshy)

**Everything in this directory is AI-generated** and carries the Steam AI-content
disclosure obligation described in the README's "Assets and provenance". Generic
per-species troop archetypes (spellcaster / heavy-armoured / light-armoured),
separate from the per-class hero figures in `assets/figures/`. Eleven `.glb` files,
each with the texture Godot extracted from it on import.

**They are wired.** `scenes/world/party3d.gd` `MODELS` picks one for a roaming band
whose faction maps to a species (`RACE_FOR_FACTION`: human, bandit and soldier to
human; orc, dwarf, elf to themselves), by the role of the band's highest-levelled
troop (`RoamingParty.highest_troop()`). A band whose faction maps to no species
uses its faction figure from `assets/figures/`. A species with no figure for a role
wears its heavy troop (`ROLE_STAND_IN`): human has no light troop, so a human,
bandit or soldier band led by a light troop wears `human_heavy_idle.glb`.

## Eleven files

| File | Source | Landed | Notes |
|---|---|---|---|
| `dwarf_heavy_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `dwarf_light_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `dwarf_spellcaster_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `elf_heavy_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `elf_light_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `elf_spellcaster_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `human_heavy_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `human_spellcaster_idle.glb` | generated | 2026-09-12 `6991f20` | |
| `orc_light_idle.glb` | generated | 2026-09-13 `29ec58a` | Community search found nothing suitable first |
| `orc_spellcaster_idle.glb` | generated | 2026-09-13 `29ec58a` | Community search found nothing suitable first |
| `orc_heavy_idle.glb` | **Meshy Community feed, CC0** | 2026-09-13 `665db95` | see below |

The first batch ran out of Meshy credits after eight of twelve; the orc three were
filled in on 2026-09-13 and a human light troop never was. `party3d.gd` named the
missing file until 2026-09-25, when the entry was dropped for the heavy stand-in
above (build log, "Loose ends"). A human light troop generated with the same chain
would go back into `MODELS["human"]` with its own row here.

## The generated ten

- **Tool:** Meshy, through its API from the owner's `~/kitbashforge/` scripts
  (`run_troops.py` for the first eight; not in this repository). Chain: text-to-3D preview -> refine (2k, no PBR) ->
  remesh (50k tris) -> rig (1.2 m) -> the "Idle" animation, the same as the class
  roster in `assets/figures/`.
- **Model version, task ids and credits: not recorded.**
- **Prompts: not recorded.** The original note pointed at
  `~/kitbashforge/NEXT_BATCH.md` for the prompts of the four that were still owed;
  that file is outside the repository too, and no troop prompt is kept here.
- **Dates:** as in the table.

## orc_heavy_idle.glb — different provenance from the rest

Source: Meshy Community feed, downloaded by the user directly ("Meshy AI
Orc Warrior_0912210431_texture.glb"). License: CC0 1.0 (Meshy ToS §3.3).
Remeshed through our own account (kitbashforge/run_community_rig.py) to
get it Meshy-hosted and under our polycount limit, then rigging failed
(HTTP 422, pose estimation) — the community mesh doesn't face +Z the way
our own A-pose generations do, and there's no bpy/Blender step in this
pipeline to reorient it. Kept as a static mesh: no idle animation, same
documented fallback as `assets/figures/ranger_idle.glb`. Visually a clear step up
from what generation produced for the same archetype — worth the 5-credit remesh
cost. Its author, Meshy model, prompt and date of generation are not recorded.

## Licence

The ten generated here are Meshy output from the owner's account: commercial rights
require a paid Meshy plan (free-tier output is CC BY 4.0 with Meshy retaining
ownership; Meshy ToS §3.2). `orc_heavy_idle.glb` is CC0.
