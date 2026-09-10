# sorcmerc → CRPG expansion — plan

Turns the tactical-combat prototype into a roguelite: build characters on D&D
5.5e rules, form a party, cross a node map (combat / treasure / merchant / rest),
drop into the existing combat screen for fights, carry results back.

## The source

`~/dnd-maintainer` is a 2024 5.5e **campaign manager** (React / TS / Supabase).
Its `src/lib/` is a ~30k-line **grant + resolver engine**: classes / species /
backgrounds / feats emit typed *grants* (hit-die, proficiency, feature,
resource-pool, spell, choice); a resolver materializes a character (HP, AC,
speed, skills, spellcasting, resource pools) from a build + those grants. Data
is in `src/lib/sources/*.ts` and `scripts/data/5e-SRD-*.json`.

It is not a library we can import — it's TS, coupled to React/Zod/Supabase, and
covers 20 levels / multiclassing / hundreds of feats & spells that a small-party
tactical game will never use.

## The fork — how much of D&D to bring over

**A. Full port.** Reimplement the grant/resolver engine in GDScript, extract all
data. Faithful, enormous, most of it dead weight here. Weeks, high risk.

**B. Curated subset.** Extract only the *data we use* to JSON (the classes,
species, spells, gear the game ships with, levels 1–~6), and write a *small*
GDScript character model + level-up chooser that reads it. dnd-maintainer becomes
a data source, not a code dependency. Days–weeks.

**C. Curated subset, extensible schema (recommended).** B, but the exported JSON
schema mirrors dnd-maintainer's grant shape closely enough that adding a class or
raising the level cap later is a data change, not a code change. Same effort as B.

## Sub-projects & dependency graph

```
F1 export ─┬─> F2 character model ─┬─> F3 action economy ─┬─> T7 combat↔campaign
           │                       ├─> T1 character creator │
           │                       ├─> T2 level-up          │
           │                       ├─> T3 profile manager    │
           │                       └─> T4 party manager ─> T5 campaign map ─> T6 node types ─┘
```

| ID | Sub-project | Owns | Depends on |
|----|-------------|------|------------|
| **F1** | **Data export** — a Node script in dnd-maintainer emitting `sorcmerc/data/{classes,species,backgrounds,feats,skills,weapons,armor,spells}.json` with mechanical fields (hit die, proficiencies, per-level features & resources, spell slots, weapon dice/properties, spell save/damage/shape). | `dnd-maintainer/scripts/export-sorcmerc.mjs`, `sorcmerc/data/*.json` | — |
| **F2** | **Character model** — `core/character.gd` + `core/rules.gd`: abilities, proficiency bonus, skills, class/level, features (a set), resources, inventory; derived AC/HP/init/speed/attacks computed from F1 data. Replaces the ad-hoc fields in `combatant.gd`; a `Character` *is* a `Combatant` for the resolver. | `core/character.gd`, `core/rules.gd`, `core/combatant.gd` | F1 schema |
| **F3** | **Action economy** — real action / bonus / reaction / move per turn in `combat.gd`; feature- and resource-driven verbs (Rage, Action Surge, Sneak Attack, spell slots) sourced from the character's features; conditions from data. | `core/combat.gd`, `core/ai.gd` | F2 |
| **T1** | **Character creator** — Godot scene, steps species → class → abilities (point-buy / standard array) → skills → background → equipment, driven by F1 data; outputs a `character.gd`. | `scenes/creator/*` | F2 |
| **T2** | **Level-up** — given character + target level, surface the choices in F1 data (ASI/feat, subclass at 3, skill/expertise, spells) and apply grants. | `core/leveling.gd`, `scenes/creator/levelup.gd` | F2, F1 |
| **T3** | **Profile manager** — scene: view/edit stats, view/equip inventory, spend/restore resources. | `scenes/profile/*` | F2 |
| **T4** | **Party manager** — a roster (built via T1), pick the active ≤4, shared gold + stash. | `core/party.gd`, `scenes/party/*` | F2 (T1 for the create button) |
| **T5** | **Campaign map** — node graph (start → branching combat/treasure/merchant/rest → boss), party token moves node→node, per-node resolution; combat nodes hand off to the combat scene and await an outcome. | `core/campaign.gd`, `scenes/campaign/*` | T4 |
| **T6** | **Node types** — merchant (buy/sell vs SRD prices), treasure (loot tables), rest (short/long rest recovery). | `core/nodes/*`, `scenes/campaign/*` | T5, F1 |
| **T7** | **Combat ↔ campaign integration** — `encounter.gd` builds an encounter from a spec + the live party instead of hardcoding; combat returns deaths / loot / XP; the combat UI takes party characters. | `core/encounter.gd`, `scenes/main.gd` | F3, T5 |
| **T8** | **Encounter scaler / difficulty** — given the live party (levels, gear, features, resources → a power budget), generate the enemy roster for a node. Difficulty tiers tuned so autopilot party win-rate is ~90% (easy) / ~75% (normal) / ~50% (hard); tune enemy count, HP, AC, to-hit, damage, and kit, verified against the 200-seed sweep in `tests/test_combat.gd`. | `core/scaler.gd`, `core/encounter.gd` | F2, F3, T7 |

## Realistic phasing (what can actually run in parallel)

1. **F1** — 1 agent. Standalone (a script in the other repo). Defines the schema everything else reads.
2. **F2** — 1 agent. Everything waits on the character model.
3. **F3 · T1 · T3 · T4** — 4 agents in parallel (disjoint files once F2's interface is fixed).
4. **T2 · T5** — 2 agents (T5 after T4).
5. **T6 · T7** — 2 agents.

Not "12 agents now" — the shared character model forces phases 1–2 to be serial.
Each phase ends with a review gate before the next starts.

## Scope decisions (locked 2026-09-10)

- **Port scope: A — full port.** Reimplement the grant + resolver engine in
  GDScript; export dnd-maintainer's entire catalog.
- **Roster: all 12 PHB classes, ~6 species** (Human, Elf, Dwarf, Halfling, Orc,
  Tiefling), all backgrounds, the full feat & spell catalog dnd-maintainer carries.
- **Level cap: 20** (multiclassing an open question — default single-class unless
  cheap to include).
- **Heroes:** Vera / Pike / Ilsa are rebuilt through the creator as preset builds;
  a new game starts by building your own party.

## Execution

Phase 0 (now, parallel):
- **F1** — full data export (agent, works in `~/dnd-maintainer`).
- **A0** — GDScript rules-engine architecture spec (agent): how grants / choice
  keys / resolver passes map to GDScript, `Character` vs `Combatant`, the data
  schema F1 must hit. Output: `docs/superpowers/specs/*-rules-engine-design.md`.

Phase 1: **F2** implement the engine against A0 + F1. Review gate.

Phase 2+: F3 / T1 / T3 / T4 parallel, then T2 / T5, then T6 / T7 / T8 — per the
graph above. Each phase gated on review.

### Status log
- 2026-09-10: Phase 0 dispatched — F1 (data export) and A0 (engine architecture
  spec) running as parallel background agents.
- 2026-09-10: F1 complete, committed (`25b8d06`) — `data/*.json` + `SCHEMA.md`.
- 2026-09-10: A0 complete, committed (`329c3ec`) —
  `docs/superpowers/specs/2026-09-10-rules-engine-design.md`.
- 2026-09-10: F2 (engine implementation, 9-step build sequence per the spec's
  §10, each step tested + committed) dispatched as a background agent.
- 2026-09-10: F2 complete — all 9 steps done and committed (`680202d`..`dfb0bf1`).
  `core/rules/*` (catalog, grants, choice, bundles, resolved, resolve, 7 passes,
  effects, power), `core/character.gd`, `core/adapter.gd`, `core/presets.gd`,
  `data/monsters.json`, `data/third-caster-slots.json`, `data/effects/*.json`,
  `tests/test_rules.gd` (499 assertions). Full suite green: hex 66 / combat 597 /
  rules 499. Sheet-built party vs hand-authored: 187W/13L @ 8.4 rounds (93.5%) vs
  186W/14L @ 8.8 (93.0%) — close enough to call re-baselined, not regressed.
  Fixed the two §11 structural debts (combat.gd no longer preloads encounter.gd;
  board is now a required Combat.new arg carrying reach_melee/cone_burning_hands/
  region_at). `Combatant` kept, not replaced — `Adapter.to_combatant` /
  `from_monster` / `write_back` are the seam T7/T8 build on.
  Pushed to origin (`github.com/EgecanOzcakar/sorcmerc`, private).

This is a multi-week build; phases 0–1 are the critical path and land first.
