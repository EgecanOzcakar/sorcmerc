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
| **T8** | **Encounter scaler / difficulty** — given the live party (levels, gear, features, resources → a power budget), generate the enemy roster for a node. Difficulty tiers tuned so autopilot party win-rate is ~90% (easy) / ~75% (normal) / ~50% (hard); tune enemy count, HP, AC, to-hit, damage, and kit, verified against the 200-seed sweep in `tests/test_combat.gd`. Must accept a quest-bias hint from T9 (see below). | `core/scaler.gd`, `core/encounter.gd` | F2, F3, T7 |
| **T9** | **Quest system + quest log panel** — see design below. A simple, linear, node-scoped quest layer: a merchant node can offer a kill-count or item-collect quest; later combat nodes on the same route bias their spawns toward an unfulfilled quest's target monster; a quest log panel on the campaign screen shows active/complete quests and progress. | `core/quest.gd`, `core/quest_log.gd`, `scenes/campaign/quest_panel.gd` | T4 (party holds the log), T5 (hosts the panel), T7 (spawn bias hook), T8 (folds the bias into the roster) |

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

## T9 design sketch — quests (locked 2026-09-10, kept deliberately simple)

**Quest shape** (`core/quest.gd`, a plain data class, matches the `resolved.gd`/
`grants.gd` style — no inheritance hierarchy for two quest types):
```
id, giver_node_id, title, kind: "kill_count" | "collect_item",
target_monster_id, target_item_id (only for collect_item — the drop the kills yield),
required: int, progress: int, state: "offered" | "active" | "complete" | "turned_in",
reward: {gold: int, item_id: String (optional)}
```
- **kill_count** — progress += 1 per kill of `target_monster_id`, tracked from combat's
  outcome (kill log already exists in `combat.gd`'s log; T7's write-back is where this
  taps in).
- **collect_item** — `target_item_id` drops from `target_monster_id` at a drop chance
  (a new small table, e.g. `data/loot-drops.json`, or a flat rate to start — 50%);
  progress is actual items collected, not kills, so "I killed 5 goblins but only have
  3 ears" is the intended, expected texture, not a bug.

**Offer/turn-in:** merchant nodes (T6) can offer one canned quest from a short curated
list (hand-authored, not procedurally generated — "bring me N goblin ears", "clear N
wolves from the road"); accepting adds it to the party's quest log (`core/party.gd`
gains a `quests: Array` — T4's file, small additive change) in `"active"` state.
Turning in (back at the giver, or a follow-up node) needs `progress >= required`;
pays the reward, sets `"turned_in"`.

**The spawn-bias hook (the part that touches encounter generation):** a node's combat
spec (T7) checks the party's active quests before building its roster; if an active
quest's `target_monster_id` isn't yet fulfilled, the scaler (T8) is told to include
extra copies of that monster in the next 1-2 combat nodes on the route — a bias
weight, not a hard override, so it composes with difficulty tuning rather than
fighting it. `core/scaler.gd` takes an optional `quest_bias: {monster_id: weight}`
parameter; T9 supplies it, T8 just has to honor it.

**Quest log panel** (`scenes/campaign/quest_panel.gd`, part of T5's screen): active
quests with "N/required", complete-but-not-turned-in flagged, a turned-in history
collapsed by default. Programmatic UI, same dark theme as the other new scenes.

**Deliberately not built:** branching dialogue, quest chains/prerequisites, failure
states, timed quests, procedurally generated quest text. If the curated list runs dry
that's a content problem to solve with more entries, not a generator.

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
- 2026-09-10: Phase 2 dispatched — F3 (action economy), T1 (character creator,
  owns the character save/load format), T3 (profile manager, in-memory Character
  input until T1's format lands), T4 (party manager, same caveat) running in
  parallel as background agents. Each instructed not to touch the others' files
  and to report status here rather than editing this doc directly.
- 2026-09-10: Phase 2 complete. T1/T3/T4 landed clean. F3 replaced the whole
  action-economy surface: `Combatant.econ` (action/bonus/reaction/move/attacks),
  `combat.available/legal_target/perform` as the one verb interface (monsters and
  heroes both shop it — nothing in `combat.gd` names a class or spell by id
  anymore), real pool/slot spend + short/long rest, auto-resolved reactions,
  concentration. `scenes/main.gd`'s menu now renders `cb.available(h)` directly.
  Verified locally: 1641 assertions across 6 suites green, `drive_ui` +
  `drive_creator` clean. **200-seed sweep is now 200W/0L @ 8.1 rounds** — the
  party finally using its real kit (actual Cure Wounds, repeatable Second Wind)
  made the hand-tuned Sunken Shrine trivial. This is the headline reason T8
  (scaler) is next, not a follow-up. Pushed.
  Known content gaps carried forward: `healing-word` isn't in the F1 export
  (Ilsa's heal is Cure Wounds — an action at touch range, not a bonus at 60ft);
  hex-targeted AoE spells (Fireball-shaped) are dropped at the adapter for lack
  of an aiming mode; `data/monsters.json` only has the four Sunken Shrine foes —
  T8 scales counts/numbers on those, a real bestiary is future content work.
- 2026-09-10: Phase 3 dispatched — **T7+T8** (encounter-from-spec + difficulty
  scaler, combined for interface coupling: `Encounter.build(spec, party, board)`
  and `Scaler.roster_for(party, difficulty, quest_bias)` are the contracts T5/T9
  build against next) and **T2** (level-up, reusing creator.gd's generic
  pending-choice renderer) running in parallel. T5+T9 (campaign map + quests)
  wait for T7+T8's real interface before dispatch, rather than stubbing a guess.
- 2026-09-10: T2 (level-up) and T7+T8 (encounter/scaler) complete, verified,
  pushed. **1925 assertions across 9 suites green.**
  - T2: `core/leveling.gd` + a level-up overlay reusing the creator's generic
    pending-choice renderer; preview-then-confirm; HP defaults to average.
  - T7: `Encounter.build(spec, party_combatants, board={}) -> Combat` and
    `Encounter.resolve_outcome(cb, party) -> {outcome, xp, gold, loot, deaths,
    kills}` — `kills` is monster ids, added for T9's kill-count quests. `spec =
    {"monsters":[{"id","count","mult"}], "mult", "seed"}`. XP/gold report, don't
    bank (T5's job); loot is `[]` until T6 adds a loot table.
  - T8: `Scaler.roster_for(party_characters, difficulty, quest_bias={}) ->
    spec` (quest_bias weights an id into the mix, doesn't replace it). Tuned:
    L3 preset party — easy 94% / normal 78% / hard 50.5% (targets 90/75/50,
    close enough). L8 — 88% / 66% / 38% (curve degrades with only 4 monster
    archetypes; documented ceiling in `scaler.gd` — a real bestiary fixes it,
    not more constants).
  - `scenes/main.gd` now takes injectable `party` / `spec` / `difficulty` and
    fills `result` on fight end — this is T5's hook to launch combat and read
    the outcome back.

- 2026-09-10: Phase 4 dispatched — **T5+T9** (campaign map + quest system,
  combined; includes a minimal/lite T6 — simple treasure/merchant/rest node
  resolution, not a full SRD shop economy, which stays future content work)
  running as one background agent. This is likely the last agent of this
  session's run; it's the capstone screen exercising the whole game loop.

- 2026-09-10: Dispatched **F1b — bestiary expansion** (background agent): check
  dnd-maintainer for monster/statblock data first; if absent, source a 2024 SRD
  monster dataset from GitHub. Data-only — extracts to a drop-in-compatible
  superset of `data/monsters.json`'s current schema, CR 0–10ish, basic-attack
  numbers for everything with special abilities mapped to `data/effects/
  features.json` only where cheap. Reports (doesn't implement) the wiring change
  `scaler.gd`/`encounter.gd` need to pick it up.
  **Amendment mid-task:** every monster must carry a `faction`/group tag
  (goblinoid, undead, beast, cultist, dragon, etc.) so a future scaler revision
  can compose only ecologically/thematically coherent rosters — no dragon
  sharing a fight with a goblin. This is a requirement for whoever next revises
  `core/scaler.gd`'s monster selection (currently draws from a small flat pool;
  T8's 4-archetype version had nothing to be incoherent about) — record it as
  an open follow-up, not yet implemented.

- 2026-09-10: Rest-mechanics audit (done directly, not dispatched — read-heavy,
  small contained fix). Checked every class's short/long-rest resource against
  the real 2024 rules. Found and fixed a real bug: **Warlock Pact Magic slots
  were computed by `pass_spells.gd` but never read by `adapter.to_combatant`**
  — a Warlock had zero castable leveled spells in combat (cantrips only). Fixed
  by merging pact slots into the normal 9-level slots array at `pact.slotLevel`
  (`Adapter._full_slots()`), and made them refill on a short rest too (the one
  real 5e exception). Also fixed: synthetic pools for features the export gives
  no resource-pool grant for (Second Wind/Action Surge/Channel Divinity/Wild
  Shape — correctly short-rest; Bardic Inspiration/Arcane Recovery — were
  wrongly defaulting to short-rest, now long-rest). Confirmed correct and
  untouched: Rage/Sorcery Points (long-rest), Ki-aka-Focus-Points/Paladin
  Channel Divinity (short-rest, real pool grants in the data). Separate,
  pre-existing gap noted but not built: Bardic Inspiration and Arcane Recovery
  have no mechanical effect at all yet (flavour-only, SCHEMA gap #4). 13 new
  assertions in `tests/test_rest_mechanics.gd`. Pushed.

- 2026-09-10: **T5+T9 complete** — `core/campaign.gd` (5-stage route: combat/
  merchant/rest/treasure nodes, boss at the end) + `core/quest.gd` (4 curated
  quests, kill-count and item-collect, spawn-bias proven end to end through
  `Campaign.combat_spec()`) + `scenes/campaign/campaign.gd` (map, quest log
  panel, shop, rest, combat handoff via `scenes/main.gd`'s injectable party/
  spec/difficulty). `core/party.gd` gained one field, `quests: Array`. Not
  done: XP banked on the run not the character (no xp field on `Character`
  yet — Leveling wiring is the follow-up), no campaign-progress save/load, shop
  is a flat-price stub, no loot rarity, deaths bench rather than kill.
  **F1b complete** — `data/bestiary.json`, 316 SRD monsters (5e-bits/5e-database,
  OGL 1.0a, CR 0–10), every entry tagged `faction`+`habitat` per the coherence
  requirement (no dragon sharing a roster with a goblin). Kept separate from
  `data/monsters.json` (the 4 hand-tuned originals) — wiring one-liner
  documented in `data/SCHEMA.md`, not yet made. `scaler.gd` still only draws
  from the original 4; using the bestiary + faction-gating the draw is a real
  follow-up tuning pass, not done here.
  2455+ assertions green across 12 suites; `drive_ui`/`drive_creator`/
  `drive_campaign` all clean. Pushed.
- 2026-09-10: Researched Bardic Inspiration + Arcane Recovery via the BG3 wiki
  (user's ask) and implemented both per the user's picks: Bardic Inspiration =
  flat use-counts by level tier (3/4/5 at L1/5/10, not Charisma-modifier-based),
  die 1d6→1d8→1d10, long-rest until L5 then short-rest (Font of Inspiration).
  Arcane Recovery = a charge pool (`ceil(wizard level/2)`, long-rest refill, 1
  charge per slot level restored, capped at slot 5) — mathematically identical
  to tabletop RAW, just phrased as BG3's "charges." Along the way, found and
  fixed a second real bug: `combat.gd`'s `perform()` had no case at all for the
  `"ally_buff"` verb kind (it was offerable/targetable but silently did
  nothing) — added, with auto-apply-and-consume on the bearer's next attack/
  save (no reaction prompt, matching the engine's design). Arcane Recovery has
  no UI yet (needs a "pick which slots" control) — flagged for the profile
  screen. 37 assertions in `tests/test_rest_mechanics.gd` (was 13). Pushed.

## T10 — XP economy, death/resurrection, autosave, shop pricing (locked 2026-09-10)

Closes gaps T5+T9 flagged. Decisions:

- **XP** is banked per `Character` (`ch.xp`), split evenly among the party members
  active in that fight when `resolve_outcome.xp` is banked. The real 5e cumulative
  XP table gates `Leveling.can_level_up(ch)` — Level Up is disabled until crossed.
- **Death**: a `Character.dead` flag, set from `resolve_outcome.deaths`. A dead
  character is benched and can't be reactivated into the active party normally.
  Revival: (a) **Revivify** — already in the spell export — cast by any active
  party member who knows it and has a free 3rd-level+ slot, or (b) a new
  **Scroll of Resurrection** consumable (same effect; purchasable at merchants +
  occasional treasure drop). Both cost **300gp** from the party stash (Revivify's
  real material cost, abstracted to gold, no diamond item) and bring the target
  back at 1 HP. **Any character still dead when a run concludes (win or lose)
  is auto-revived for free** — death is a within-run cost, not permanent across
  runs.
- **Shop pricing**: mundane weapons/armor already carry an SRD `cost` that's
  power-correlated within their one rarity tier (common) — reuse it directly
  rather than inventing a parallel power formula. Magic items have no structured
  power data (F1 gap), so they price by **rarity tier alone**, polynomially
  between tiers (tier index → price ∝ index^E for a documented constant E and
  base — tune for plausible gp bands, artifacts not for sale). Sell price stays
  a flat fraction of buy price (`SELL_RATE`, already built).
- **Autosave**: after every state-mutating `Campaign` method (enter/leave a
  node, combat resolved, rest taken, shop transaction, quest accept/turn-in) —
  a single rolling `user://` slot, not a save-slot manager. `CampaignSave.
  load_latest()` for the load path; since there's no top-level hub scene yet,
  `scenes/campaign/campaign.gd` gets a minimal Continue-vs-New-Game choice at
  its own entry point (a real main menu is separate future work).

**T10 amendment, folded in (locked 2026-09-10):** inventory becomes **one pool
for the whole party** (`core/party.gd`'s `stash`, which already exists), not a
per-character list. `Character.inventory` is dropped entirely; `Character.
equipped` stays (what that character currently has worn/wielded). Equip pulls
an item out of the party's shared stash onto the viewed character; unequip
returns it to the shared stash. This is T3's profile-screen inventory panel
rewritten to read/write `party.stash` instead of `ch.inventory`, plus the
matching `character_save.gd` schema change. Bundled into the same T10 dispatch
as the XP/death/shop/autosave work since both already touch `character.gd` and
`party.gd` — two agents editing those concurrently would collide.

## T12 — randomized map routes (locked 2026-09-10, dispatched now that T11 has landed)

`STAGES` becomes a **pool** of node templates per stage-position (early/mid/
late), each tagged with kind (combat/merchant/treasure/rest) and a board theme
(reusing T11's 6 registered themes — including city-square and merchant-shop,
currently authored but unused). `Campaign.new(party, seed)` seed-picks 2-3
eligible templates per stage from the pool (same `RNG` convention as the rest
of the game — deterministic per seed) instead of always offering the one fixed
list. Invariants preserved: 5 stages, the last is always exactly the boss (not
a choice), at least one merchant appears before the boss (quests need a
giver), difficulty/gold/gear flavor stays in the spirit of what T11/T5+T9
authored. Pool should be meaningfully larger than today's node count so two
seeds produce visibly different routes.

## T13 — magic item identification (locked 2026-09-10, dispatched now that T10 has landed)

Unidentified on pickup **from treasure only** — a merchant sells you a labeled
item, so shop purchases are pre-identified; only loot is mysterious.
Unequippable while unidentified (`party.stash` entries for magic items gain an
`identified: bool`; mundane weapons/armor have no such state, always usable).
Two ways to identify: **(a)** the real 5e optional rule — DC 15 Intelligence
(Arcana) check, made "during a short rest spent examining the item," so this
only offers at a **rest node**, using the examining character's real Arcana
skill from their resolved sheet; **(b)** a new **Identification Scroll**
consumable (buyable at merchants + occasional treasure drop, matching the
Scroll of Resurrection precedent T10 just built) — instantly identifies one
item, usable any time, not gated to a rest node. An unidentified item shows as
a mystery (rarity hint only, no name/effect) in the profile's stash panel.

- 2026-09-10: T12 and T13 dispatched in parallel (both blockers, T11 and T10,
  had landed and been verified). Both touch `core/campaign.gd` in different
  functions (T12: route generation/`STAGES`; T13: treasure-loot identification
  flag, rest-node Identify action, shop stock) — same file-sharing discipline
  as the T10/T11 pair, flagged explicitly to both agents.
- 2026-09-10: Identification DC made rarity-dependent (done directly, small):
  target success rate by tier (uncommon 90%, rare 80%, very-rare 60%,
  legendary 35%, artifact 15%), DC solved backward from the target against
  the examining character's real Arcana bonus. Scroll path unaffected
  (always succeeds, no roll). `Campaign.identify_dc(item_id, bonus)`.

## T16 — bestiary special attacks + full bestiary in the scaler (locked 2026-09-10, dispatched now)

Expanded per the user's follow-up ask: almost every monster should have more
than a basic attack, checked against the real source data, not invented —
folded into one dispatch with the scaler wiring since both touch
`data/bestiary.json` and running them concurrently would collide.

**Phase 1 — special/condition-inflicting attacks.** F1b's own extraction
already documents exactly what was flattened away per monster (each entry's
`_notes` field: poison, paralysis, frightful presence, grapple/constrict, web,
stunning, charm, breath weapons, regeneration, pack tactics, etc.) — that's
the worklist. Re-fetch the same source F1b used (`5e-bits/5e-database`, the
commit pinned in `data/SCHEMA.md`'s bestiary section) into `/tmp` to read each
monster's real ability text rather than inventing effects. Don't hand-author
316 bespoke abilities — D&D's own special attacks cluster into a fairly small
set of recurring patterns, so build a **reusable template library** in
`data/effects/features.json` (extending what's already there —
`monster-multiattack-2/3`, `monster-surprise-attack`, `goblin-nimble-escape`)
for the common patterns (poison bite/sting, paralytic touch, frightful
presence, grapple+constrict, web/entangle, stunning strike, charm gaze/song,
regeneration, pack tactics, a simple innate ranged save-attack for casters),
using T14's existing `save_effect`/`apply_condition` machinery — then tag a
broad set of `bestiary.json` entries with the matching template ids in their
`features` array. Report actual coverage achieved honestly rather than
claiming "almost every" if the pass falls short — breadth over exhaustive
depth, matching F1b's own stated ceiling.

**Phase 2 — wire the (now more dangerous) bestiary into the scaler.**
`core/scaler.gd` still only draws from the 4 original hand-tuned monsters.
Wire them in:
- `Scaler.roster_for()` gains an optional faction/theme hint; with none given
  it seed-picks one coherent faction from the bestiary and builds the roster
  from monsters within that faction only (never mixing, e.g., a dragon with a
  goblin) — reusing the existing bodies+multiplier tuning methodology (`power.
  gd`'s estimate, the same win-rate-targeting approach T8 already validated),
  not reinventing it.
- Board theme ↔ faction pairing: T11's per-node `theme` (goblin-camp, frozen-
  cave, city-square, ...) suggests a natural faction filter (goblin-camp →
  goblinoid, etc.) — wire that mapping so a themed board usually gets a
  thematically matching roster.
- **The Sunken Shrine boss fight stays pinned to its original 4 monsters** —
  the 200-seed sweep and every difficulty target this session tuned against
  is anchored there; don't disturb it. Bestiary variety applies to every other
  combat node.
- Re-run and report the difficulty-tier win-rate sweep after wiring this in —
  a broader, multiattack-carrying monster pool changes the curve T8 tuned
  against 4 simple archetypes; retune the multiplier constants if needed.

## T19 — local achievements (locked 2026-09-10, dispatched now, model-only)

Simple, locally-tracked achievements (unlocked/timestamped, persisted to
`user://achievements.json` — this machine's user profile, not per-save, not
online) for milestones like first combat won, a character reaching level 5/20,
equipping a legendary item, resurrecting a fallen ally, identifying a magic
item, completing a full run, winning a hard fight clean (nobody downed), etc.
**Model + a standalone viewer panel only, dispatched now** — building the
model is fully additive (`core/achievements.gd`, a new scene), no collision
risk. **Wiring the actual unlock calls into `combat.gd`/`campaign.gd`/
`leveling.gd`/`party.gd` is deliberately deferred** until T15 and T16 (both
actively editing those files right now) land, to avoid a third concurrent
editor on the same files — the agent reports back the exact trigger points
(file, call site, achievement id) as a worklist for a quick follow-up once
the dust settles.

## T20 — weapon mastery mechanics (locked 2026-09-10, dispatched now)

F2's original port scoped weapon mastery to "which masteries a character
knows" only — the eight 2024 mastery properties (Cleave, Graze, Nick, Push,
Sap, Slow, Topple, Vex) were never mechanically wired. Same shape as T14's
condition engine: a generic reader off each weapon's `mastery` field (already
in the `weapons.json` export), auto-applied on a weapon attack's resolution
(no reaction prompt, matching this engine's whole design) — Cleave (hit a
second adjacent creature), Graze (still deal ability-mod damage on a miss),
Nick (a second light-weapon attack folded into the same Attack action, not a
bonus action), Push (shove 10ft on hit), Sap (disadvantage on the target's
next attack), Slow (-10ft speed until your next turn), Topple (CON save or
prone), Vex (advantage on your next attack against that target). `combat.gd`
is currently free (T16 finished touching it in Phase 1) — safe to run now.

## T21 — AI prioritizes special attacks (locked 2026-09-10, **held until T16 lands**)

`core/ai.gd`'s monster turn logic (`_use_kit`/`_foe_turn`) should reach for a
strong/special verb (a condition-inflicting attack, an AoE, a buff) over a
plain basic attack when one is legally available and tactically sound, not
default to basic-attack-always. **Held until T16's Phase 1 (special-attack
tagging) and Phase 2 (scaler) both fully land** — the AI needs the final,
stable set of what monsters can actually do, not a partial pass still being
authored underneath it.

- 2026-09-10: **T16 complete, both phases.** Phase 1: 20 reusable ability
  templates authored from the real SRD text (re-fetched, not invented),
  250/316 bestiary entries now have something beyond a basic attack (184
  gained a real condition/special attack this pass) — coverage reported
  honestly as short of "almost every," with the remainder mostly CR-0 trivial
  statblocks. Fixed a real bug as a byproduct: `apply_condition` had no
  duration handling at all, so a monster's paralyze/stun could lock a PC out
  permanently — round-durationed conditions now lapse at the bearer's next
  turn. Phase 2: `Scaler.roster_for()` draws one coherent faction from the
  full bestiary, theme-paired to board (goblin-camp→goblinoid, etc.), quest
  bias still gets its named monster mixed in; the Sunken Shrine boss node is
  untouched and the 200-seed sweep is byte-identical (200W/0L, 8.1 rounds).
  Retuned difficulty constants and posted new measured win rates in
  `core/scaler.gd`'s header (the bestiary is meaningfully deadlier per power
  point than the 4 originals were). T20 (weapon mastery) still actively
  editing `combat.gd`/`combatant.gd` — dispatching T17/T18/T21 now since none
  of them touch those two files.

## T22 — progression: species/class/subclass unlocks (locked 2026-09-10, model-only dispatch now)

Full spec from the user, all ids verified against the real data:

**Starting open — species:** `human`, `orc` ("half-orc"), `elf`, `dwarf`, each with
every one of their lineages already open (`elf` has `drow`/`high-elf`/`wood-elf`;
the other three have none, so this is a no-op for them). **Locked, cost lifetime
XP:** `aasimar`, `dragonborn`, `gnome`, `goliath`, `tiefling` — unlocking one opens
all of its lineages too, no separate lineage currency.

**Starting open — classes**, each with exactly 2 of its 4 subclasses pre-chosen:
`cleric` (`lifedomain`, `lightdomain`) · `warlock` (`archfeypatron`, `fiendpatron`)
· `wizard` (`abjurer`, `evoker`) · `barbarian` (`berserker`, `zealot`) · `ranger`
(`gloomstalker`, `hunter`). **Locked, cost lifetime XP:** `bard`, `druid`,
`fighter`, `monk`, `paladin`, `rogue`, `sorcerer` — note Fighter and Rogue (the
original MVP heroes' classes) are *not* in the starting set; the presets/creator
will need to treat them as already-unlocked for existing save compatibility, see
below. **Species cost less than classes** — every species threshold sits below
every class threshold, not just paired lower.

Thresholds (lifetime XP — accumulates across every character/run ever played,
not one character's level track, so these are deliberately multi-run goals):
- Species: 3,000 / 6,000 / 9,000 / 12,000 / 15,000 (order: pick one, document it
  as tunable — no ordering was specified).
- Classes: 20,000 / 30,000 / 40,000 / 50,000 / 60,000 / 70,000 / 80,000 (same).

**Subclass unlocks, two-tier:** unlocking a class for the first time (starting
*or* via lifetime XP) lets the player choose 2 of its 4 subclasses for free, as
part of that same unlock. The other 2 cost a new **class experience** currency —
a per-class counter, separate from lifetime XP, fed by playing that class (a
character's normal XP gain also adds to their class's class-XP pool). Flat
5,000 class-XP per remaining subclass, either order, for every class (the 5
starting classes' un-chosen 2 subclasses included — e.g. Cleric's Trickery/War
domains cost class-XP from the start, even though Cleric itself needs no unlock).

**Scope for this dispatch:** the model and a standalone viewer only —
`core/progression.gd` (lifetime XP tracking is separate from `Character.xp`;
it's a `user://progression.json` local total, same file-format convention as
`core/achievements.gd`), unlock/threshold logic for species/classes, per-class
class-XP tracking and subclass unlock logic, a viewer panel. **Wiring the
actual gates into `scenes/creator/creator.gd`'s pickers (grey out locked
options, "unlocks at N XP") is deferred** until T17 (still in flight, reuses
the creator as a child scene) lands — same deferred-hook pattern T19 used.
Also flag, don't silently fix: existing character saves / the 3 presets use
Fighter (Vera) and Rogue (Pike), which aren't in the starting-open class list —
the model should treat an already-existing character's class as always valid
regardless of unlock state (never retroactively invalidate a save), only the
*creator's* class picker enforces the gate on new characters.

## T18 — a boss pool (locked 2026-09-10, spec'd now, **held until T16 lands**)

`core/campaign.gd`'s `BOSS` is a single fixed node (T12 flagged this itself).
Two boss archetypes, per the user: **(a)** a rarer/stronger bestiary monster
that already carries a real special attack from T16's Phase 1 tagging — picked
from CR bands appropriate to a run's climax, not the same tier as regular
combat nodes; **(b)** an "elite" version of an ordinary monster (their own
example: a goblin archer) pumped up via the scaler's existing `mult` stat-
multiplier mechanism (already how difficulty scaling works — reuse it, don't
build a second buff system) plus maybe an extra action or two, so a familiar
early threat can return as a genuine capstone fight. Build a small boss pool
(mixing both archetypes), seed-picked the same deterministic way the rest of
the route already is, replacing the single fixed `BOSS` node.

**Held until T16 lands** — this needs T16's Phase 1 tagging to know which
bestiary monsters actually carry a special attack worth spotlighting as a
boss, and needs to reuse whatever difficulty-multiplier constants T16's
Phase 2 retunes. Dispatching now would mean rebuilding on top of numbers
that are about to change under it.

## T17 — the New Game flow (locked 2026-09-10, spec'd now, **held until T15 lands**)

Every piece exists (creator, party manager, campaign map, combat) but nothing
routes them into one playable loop — `project.godot`'s entry point is still
the raw combat screen with a demo party. Design: a new top-level scene becomes
the real entry point — Title/Continue (autosave detection, already half-built
in `campaign.gd`'s Resume/New-Run choice, hoisted up a level) → party setup
(create via the creator, or manage an existing roster) → confirm → the
campaign map → play → one of three end states: **Victory** (boss beaten),
**Retire** (a new player-initiated "leave the dungeon with what you have"
option, available only between nodes — a new `Campaign` state, not available
mid-node/mid-combat, banks everything as-is and auto-revives like a win does),
**Defeat** (whole party dead — the existing "lost" state) — all three funnel
to a run-summary screen, then back to the hub with the roster persisted for
next time.

**Held, not dispatched, because T15 (UI polish) is actively editing all five
screens right now** — a routing/navigation pass touches the same five files
for a different reason, and running both concurrently is a much worse
collision than anything managed so far this session. Dispatch once T15 reports.

## T15 — UI/graphics polish pass (locked 2026-09-10)

"Top notch" visual polish across the existing shape-based (no sprites)
language, explicitly **not** character portraits/models — those are added
manually later. Scope: a shared icon/glyph system (`core/ui_icons.gd` or
similar) — a distinct glyph per class (extending the 3-class glyph idea
already in `main.gd`'s combat tokens to all 12), a glyph per spell school (8),
a glyph per condition/status (the 15 from T14, several already have ad-hoc
unicode marks scattered around — consolidate), and a **rarity color ramp**
(common/uncommon/rare/very-rare/legendary/artifact) applied everywhere an
item's name renders (shop, stash, profile) — plus a typography/spacing
consistency pass across all 5 screens (combat, creator, profile, party,
campaign), which were built by different agents across this session and may
have drifted despite sharing `Creator.dark_theme()`.

- 2026-09-10: **T12 and T13 complete.** T12: `STAGES` replaced by a 35-template
  `POOL` + a fixed `BOSS`, seed-generated per run (route RNG is a separate
  stream off the same seed, so it doesn't perturb combat/loot rolls); both
  previously-idle board themes (`city-square`, `merchant-shop`) now see use.
  It also root-caused and fixed T13's flagged flakiness: `scenes/campaign/
  campaign.gd` was building unseeded runs, so routes (and therefore
  `drive_campaign`) weren't reproducible — now reads `SORCMERC_SEED` like
  `main.gd` does. T13: `party.gd` stash entries gained `identified` (defaults
  true; false only for fresh magic-item treasure); identify via DC 15 Arcana
  at a rest node (auto-picks the party's best Arcana, one try per camp) or a
  new 256gp Scroll of Identification (instant, no roll, stocked everywhere).
  **Investigated T12's remaining flag** (an unseeded `drive_campaign` can rarely
  burn its whole step budget inside one fight): ran 14 fresh unseeded attempts,
  0 reproduced a stall. Root cause is understood and benign — the test driver's
  greedy walk-toward-nearest-foe pathing is inefficient on the newer boards'
  obstacles, and the outer loop is bounded (`MAX_STEPS`), so this is a slow,
  self-terminating test run, not a hang or a production combat bug. Logged as
  a low-priority test-driver quality item, not chasing further.
  **Full suite verified clean: 2960 assertions across 16 test files, 0
  failures.** Pushed.

## Post-T5+T9 gap survey — dispositions (locked 2026-09-10)

- **Meta-progression across runs**: explicitly a TODO, not implemented yet.
  Note it as a future roguelike-unlock layer (persistent currency/unlocks that
  survive a run ending) — no design committed, just don't let it get lost.
- **Narrative/dialogue layer**: explicitly a TODO, not implemented yet. Quests
  stay mechanical-only for now.
- **Map variety**: to be randomized — each campaign generates a different
  route/order rather than always playing the one fixed `STAGES` sequence.
  **Queued as T12, dispatched after T11 lands** (T11 is mid-flight authoring
  per-node `theme` keys against the current fixed `STAGES` shape; randomizing
  route generation changes that shape and would collide if run concurrently).
- **Magic item identification**: unidentified on pickup; unequippable until
  identified via a relevant DC check or an Identification Scroll (buyable or
  found as treasure). **Queued as T13, dispatched after T10 lands** (T10 is
  mid-flight rewriting the shared-stash item shape and the profile screen's
  equip flow right now — identification adds an `identified` flag to that same
  shape, so it has to build on T10's landed work, not race it).
- **Settings/options overlay**: toggleable, doesn't touch T10/T11's files —
  dispatched now, in parallel, see below.
- Bestiary→scaler wiring, per-node terrain (T11 is doing this now), equip-from-
  stash (T10 is doing this now), multiclassing, tutorial/onboarding, magic-item
  identify (see above — now scoped), status effects beyond the combat flag set:
  tracked, most already queued into a named sub-project above.

## T14 — status conditions engine (dispatched now, parallel to T10/T11)

The user asked to verify the real 2024 condition meanings and implement the
mechanics. Good news: `data/conditions.json` (F1's export) already holds
exactly the 15 official 2024 conditions with accurate prose, matched against
the real rules by inspection — no re-research needed. Better news:
`data/effects/conditions.json` (sorcmerc-authored, already exists) already has
every condition's *structured* mechanical numbers (attacks-against adv/dis,
own-attacks dis, auto-fail-saves, no-action/bonus/reaction, speed-zero,
resist-all, auto-crit-within-reach, exhaustion's per-level d20/speed penalty).
**What's missing is `combat.gd` actually reading that data** — today only
prone/dodging/hidden/helped are hand-coded ad-hoc; the other 11 conditions'
structured effects are inert. T14 wires them into `_attack_mode`,
`_saving_throw`, action/bonus/reaction gating in `available()`/`perform()`,
speed/movement, damage resistance, and exhaustion's roll penalty + level-6
death — a generic reader over `data/effects/conditions.json`, not per-condition
special-case code. combat.gd isn't touched by T10 or T11, so no file conflict.

## Settings overlay (dispatched now, parallel to T10/T11)

A toggleable panel, reachable from the combat and campaign screens: animation-
speed (the existing `SORCMERC_FAST`-style tween toggle, promoted to a real
in-game setting), default difficulty for new campaigns, a "clear autosave"
utility action. Persisted to `user://settings.json`. No audio settings — there's
no sound system yet, a volume slider would control nothing.

## T11 — combat board variety + interactables (locked 2026-09-10)

Right now every fight uses the one hand-authored Sunken Shrine room. Design:

- **5-6 board themes**, each a hex layout + palette: keep Sunken Shrine (ruin/
  dungeon) as-is; add Goblin Camp (enemy camp — open clearing), City Square
  (urban — stalls as cover), Forest Clearing (trees as cover/blocking, dense
  undergrowth as rough terrain), Frozen Cave (ice as rough/hazard terrain,
  stalactites as cover), Merchant Shop Interior (tight room, shelves as cover)
  — the last matching the user's own example scenes.
- **Interactables**, generalized from the existing brazier: a board carries a
  list of typed objects. **Barrel/crate**: a destructible obstacle (blocks
  movement, has HP, attackable) — an `explosive: bool` flag reuses the existing
  shove-into-brazier fire mechanic (2d6 fire in a radius) when destroyed, so no
  new damage mechanic is invented, just generalized. **Torch**: purely
  decorative (a lit, pulsing hex, matching the brazier's existing glow
  animation) — no new mechanic; a `ponytail:` note flags "could ignite adjacent
  flammable terrain" as a future addition, not built now.
- **Board selection per node**: each combat node in `campaign.gd`'s route gets
  a `theme` hint (simple, authored, not derived dynamically from monster
  habitat — that coupling isn't worth it yet) that `Encounter.build()` uses to
  pick the board instead of always defaulting to the Sunken Shrine.
- Rendering: `Board._draw()` generalizes its single hardcoded brazier-drawing
  path into "draw each interactable by type," with a distinct shape/color per
  type — still shapes, no sprites, matching this project's established look.

Dispatched alongside T10; both touch `core/campaign.gd` in different, additive
regions (T10: autosave calls at the end of state-mutating methods; T11: a
`theme` field read in `combat_spec()`) — flagged to both agents to keep it that
way, reconciled by hand if they collide.

- 2026-09-10: T10 (xp/death/resurrection/shared inventory/shop pricing/autosave)
  and T11 (board variety + interactables) dispatched in parallel — file
  ownership split explicitly (T10: character.gd, party.gd, adapter.gd, profile
  inventory panel, campaign shop/rest/xp/death; T11: encounter.gd boards,
  campaign STAGES theme keys only, main.gd board rendering).
- 2026-09-10: T14 (status conditions engine) and the settings overlay dispatched
  in parallel with T10/T11 — 4 agents running concurrently. Corrected T14
  mid-flight: T11 also touches `combat.gd` (interactables/objects/smash verb),
  not T14 alone as first briefed — sent as an amendment, both should still land
  additively in different regions of the file.
- 2026-09-10: **T11 and T14 complete.** T11: 6 board themes, barrel/torch/
  brazier interactables generalized (`Encounter.board_for(theme)`), a `smash`
  verb; `adjacent_to_brazier` renamed `adjacent_to_hazard`/`adjacent_hazard`
  (API change, noted). T14: all 15 real 2024 conditions wired generically off
  `data/effects/conditions.json`; deafened and blinded's sight-check half are
  legitimately inert (no ability-check system exists to fail). Flagged two open
  design calls rather than deciding silently: prone had no stand-up action
  (closed same day, see below), and "down" is deliberately not aliased to
  "unconscious" (would change death dynamics).
- 2026-09-10: **Prone auto-stand implemented directly** (not dispatched — small,
  well-scoped, combat.gd was free): standing is automatic at the top of your
  turn, costs half speed, discountable via a data-driven `stand_cost_mult` on
  a feature (none grants one yet — a test fixture proves the hook works).
- 2026-09-10: **Settings overlay complete.** `user://settings.json`, reachable
  via `F1` in combat / a footer button in the campaign screen. Animation-speed
  toggle wired into `main.gd`'s real tween timing (env var still wins for
  headless tests). Gracefully degrades its "clear autosave" button while
  `campaign_save.gd` didn't exist yet (T10 was still building it).
- 2026-09-10: **T10 complete** — all 5 sections landed: per-character XP +
  real 5e level-up gating; death/resurrection (Revivify or a new
  Scroll-of-Resurrection item, both 300gp, auto-revive at run end);
  `Character.inventory` deleted, profile screen equips from the shared
  `party.stash`; shop pricing (SRD cost for mundane gear; magic items
  `4 * (tier+1)^6` — sanity-checked: uncommon 256gp, rare 2916gp, very-rare
  16384gp, legendary 62500gp, artifacts not for sale); `core/campaign_save.gd`
  autosaves after every state-mutating `Campaign` method, a Resume/New-Run
  choice on the campaign screen. Caught and fixed one thing T10 correctly
  flagged as not its own bug: a test-fixture feature entry from the same-day
  prone-auto-stand commit failed the effects validator (missing `kind`) —
  fixed by renaming to the established `_`-prefix "not a real entry" convention.
  **Full suite verified clean after all five agents' work merged: 2946
  assertions across 16 test files, 0 failures.** `drive_ui`/`drive_creator`/
  `drive_campaign` all clean. Pushed.

- 2026-09-10: **T17, T18, T20, T21, T22 all complete**, landing in quick
  succession after T16. T17 (new game flow): `scenes/game/game.gd`+`.tscn` is
  now the top-level scene (`project.godot`'s `run/main_scene` repointed),
  routing Title → Party Setup → Campaign → one of Won/Retired/Lost →
  Summary → hub; `Campaign.retire()` added (guarded to `state=="picking"`,
  reuses the existing auto-revive-at-end path). T18 (boss pool): 6 bosses —
  the original Sunken Shrine plus 3 bestiary monsters (oni, assassin,
  mammoth) and 2 "elite simple creature" bosses (arrow chief, shop captain)
  built by buffing an ordinary statblock, reusing the scaler's existing
  multiplier knob (`boss_for()`, `BOSS_LEAD_SHARE`, `BOSS_MULT_MAX`). T20
  (weapon mastery): all 8 2024 mastery properties (Cleave, Graze, Nick*,
  Push, Sap, Slow, Topple, Vex) wired as a rider dispatcher in `combat.gd`;
  *Nick explicitly not implemented — it needs a two-weapon-fighting system
  this codebase doesn't have yet, tracked as a follow-up, not silently
  dropped. T21 (AI special-attack priority): monsters now prefer any
  available non-basic verb (spell/feature/mastery rider) over a plain
  attack; caught its own bug pre-ship — a naive filter let Shove win out
  over real attacks, hard-mode win rate cratered to ~50%, fixed by
  excluding `BASIC` verbs from the "special" candidate pool, back to parity.
  T22 (meta-progression unlocks): `core/progression.gd`, spec exactly as the
  user gave it — human/half-orc/elf/dwarf (+ their existing lineages) and
  cleric(life/light)/warlock(archfey/fiend)/wizard(abjurer/evoker)/
  barbarian(berserker/zealot)/ranger(gloom stalker/hunter) start open;
  everything else costs lifetime XP (species cheaper than classes, gnome
  3000 up through goliath 12000; rogue 20000 up through sorcerer 80000);
  first unlock of a class grants a pick of 2 subclasses free, the rest cost
  a per-class "class experience" resource (5000 each). Model + a standalone
  viewer scene only — **not yet wired into gameplay**: nothing calls
  `add_lifetime_xp`/`add_class_xp` from `campaign.gd`'s XP split, and
  `creator.gd`'s pickers don't gate on it yet. Same for T19 (achievements,
  landed earlier this wave): tracking/persistence exists but no `unlock()`
  call sites exist in combat/campaign/leveling/party yet. Both are the
  natural next dispatch, flagged rather than started.
  **Full suite verified clean with all of T16–T22 merged: 22 test files,
  3754 assertions, 0 failures.** All four `drive_*` headless smoke scripts
  (`drive_ui`, `drive_creator`, `drive_campaign`, `drive_game`) pass against
  the fully-merged tree.

- 2026-09-10: **Boss XP scaling, fantasy enemy names, and both deferred hookups
  complete.** Boss fights now pay bonus XP scaled by how much harder they play
  than the curve's middle (`avg(easy, hard)` measured win rate over the boss's
  own, capped 1.0–2.5x — `Campaign.BOSS_REF_WIN_RATE`/`BOSS_XP_MULT_CAP`).
  Humanoid foes (`data/bestiary.json` `type=="humanoid"`) spawn as
  "<name> the <Species>" out of a faction-keyed fantasy name pool
  (`core/enemy_names.gd`), deterministic per seed/spawn so a reload names the
  same goblin the same thing. T19 (achievements) and T22 (progression) are
  both wired into real gameplay now, not just modeled: victory unlocks
  first_victory/hard_flawless/campaign_clear/etc., death-saves/resurrection/
  identification/spending all fire their achievement ids, and campaign XP
  banks account-wide lifetime XP plus per-class class-XP into `Progression`,
  with `creator.gd` greying out locked species/classes/subclasses and showing
  their real unlock cost, including the "pick 2 free subclasses" flow on a
  class's first unlock. One achievement (`equip_legendary`) still needs a
  one-line hook in `scenes/profile/profile.gd`'s `toggle_equip()`, not yet
  added — flagged, not done. **Full suite: 23 test files (test_bestiary
  reports OK, not a count), 0 failures; all four `drive_*` smoke scripts pass.**

## T23 — power.gd control-underpricing retune (locked 2026-09-10, dispatched now)

Known ceiling since T16/T18: `Power.estimate()` scores raw damage/HP/AC well
but undervalues a save-or-suffer control effect (stun, paralyze, restrain,
frighten, knock-prone, grapple) relative to a monster that just hits harder —
that's why the boss pool's measured win rates spread from 8% (shop-captain,
an escort-heavy elite) to 68% (arrow-chief) despite all being budgeted the
same way. Add a control-effect bonus to the score (scaled by how much of the
target's turn it denies — a full lockout like stun/paralyze scores highest,
a save-negates-half debuff like frightened scores lowest), then re-run the
existing 40-seed sweeps (scaler.gd's own TUNING method) for easy/normal/hard
AND the boss pool, retuning `TIER`/`CURVE`/`MULT_*` and each `BOSS_POOL`
`win_rate` to hit the same 90/75/50% targets with a tighter boss spread.
Update scaler.gd's header comment with the new measured numbers.

File ownership: `core/rules/power.gd`, `core/scaler.gd`, `tests/test_scaler.gd`,
and ONLY the `"win_rate"` leaf values inside `campaign.gd`'s `BOSS_POOL`
entries (feeds `Campaign.BOSS_REF_WIN_RATE`'s XP-multiplier math directly) —
nothing else in campaign.gd, which T25 (settlements) is editing concurrently
in unrelated regions.

## T24 — Nick weapon mastery + two-weapon fighting (locked 2026-09-10, dispatched now)

The last unimplemented 2024 mastery property. Needs minimal two-weapon
fighting first: a character may equip a second *light* weapon off-hand; the
bonus-action off-hand attack deals no ability-mod damage bonus unless a
feature grants one (standard 2024 TWF rule). Nick's actual effect: if the
main-hand weapon has the Nick property, the off-hand attack folds into the
Attack action itself (once per turn) instead of costing the bonus action —
reuse the `opts["free"]` pattern Cleave's second swing already established
in `combat.gd` rather than inventing a new mechanism. Player characters only;
monster statblocks that already hint at two attacks use their own
`attacks` array and don't need this system.

File ownership: `core/combat.gd` (mastery dispatcher + off-hand verb),
`core/character.gd` (an off-hand equip field), `core/adapter.gd` (off-hand
verb generation), a minimal equip-UI touch in `scenes/profile/profile.gd` if
the existing equip flow doesn't already generalize, `tests/test_weapon_mastery.gd`.

## T25 — settlements: sized NPC services (locked 2026-09-10, spec from the user, dispatched now)

The existing "merchant" node kind (`wayside-camp`, `hollow-market`,
`pack-mule`, `tinkers-wagon`, `shuttered-shop`, `caravanserai`) becomes a
sized settlement: every one has a **Generalist** (today's flat `STOCK` list,
unchanged); a **village** adds one specialist; a **town** adds two to three.
Specialists: **Weaponsmith** (full `data/weapons.json`), **Armorsmith** (full
`data/armor.json`), **Alchemist** (`potions-of-healing` + the general potion
list off `data/magic-items.json`), **Librarian** (the three scroll ids, plus
a discounted/no-roll identify-on-request using the existing `identify_check`
flow), **Healer** (flat gold for an instant full heal + clear-all-conditions,
distinct from a free rest node), **Innkeeper** (the quest-giver role —
replaces the hardcoded `GIVER_IDS` constant; any settlement carrying an
Innkeeper can `offer()` a quest, and `_ensure_giver()`'s "one giver before
the boss" invariant, already tested, must keep holding). Hand-author size +
services per existing node to fit its flavor (a "camp" stays a Generalist
only; "hollow-market"/"caravanserai" read as the two towns) — the agent has
discretion on the exact assignment as long as sizes strictly nest
(Generalist ⊂ village's add ⊂ town's add) and at least one Innkeeper survives
early enough for `_ensure_giver()`. Each NPC gets one short hand-authored
flavor line shown in their shop tab — flavor only, no branching, not the
narrative system (still explicitly not being built). UI: the existing
merchant panel gains a tab per service present, Generalist first; buy/sell
still routes through the existing `item_price()`/`buy()`/`sell()`.

File ownership: `core/campaign.gd` (POOL merchant entries, new
service/catalog data, buy/offer logic — but NOT the `BOSS_POOL` `win_rate`
values, T23 owns those), `scenes/campaign/*` (the shop panel), `core/quest.gd`
if the giver check is cleaner to move there, `tests/test_campaign.gd` +
`tests/test_quest.gd`.

## T26 — combat flavor: party/enemy barks (locked 2026-09-10, spec from the user, dispatched now)

One-line, hand-authored bark pools (NOT the narrative system — no branching,
no state) keyed by trigger: landing a hit, a crit, a kill, dropping to low
HP, going down, winning the fight. Separate party/foe pools; foe barks reuse
the T16 faction tags for cheap variety (a goblinoid bark reads differently
from a bandit's). `combat.gd` fires a bark at the relevant trigger points
through a small queue/callback the board scene drains each frame — never
gates or slows combat resolution. Fire probabilistically (~15–25% per
trigger, not every hit — that's spam), seeded off the combat's own RNG
stream so headless/test runs stay reproducible; skip entirely under
`SORCMERC_FAST`/headless, matching how this codebase already gates other
cosmetic-only systems. UI: a short-lived floating label over the
combatant's hex sprite (plain Label, no bubble art — matches the project's
"shapes, not sprites" placeholder aesthetic), a few seconds then cleared.

File ownership: `core/combat.gd` (trigger hookpoints) + a new small bark data
file, and the combat board's rendering script — READ scenes/game/*.gd and
scenes/main.gd first to find which one actually owns hex-sprite rendering
post-T17 rather than assuming; don't touch `core/campaign.gd` (T25's) or
`core/rules/power.gd` (T23's).

## T27 — procedural sound: SFX + adaptive environment/combat music (locked 2026-09-10, dispatched now)

Placeholder audio, generated not sourced (same "shapes, not sprites" ceiling
as every other asset in this project — real audio can replace it later, same
as character models). A one-time Python script (stdlib `wave` only, no deps)
synthesizes short WAV files, committed as binary assets under
`res://assets/audio/{sfx,music}/`.

**SFX** — one-shot stings for: attack hit, crit, kill, spell cast, heal,
level-up, victory fanfare, defeat stinger, UI click/confirm, shop buy,
identify success, quest complete, item pickup, rest chime. Reuse T26's
EXISTING bark trigger points in `combat.gd` (`Combat.bark(c, trigger)` —
hit/crit/kill/low_hp/down/victory) as the SFX trigger points too, rather than
adding a second, parallel set of hookpoints for the same moments — additive
calls alongside the existing bark calls, not a rewrite of them.

**Music** — not N separate full tracks. ONE short ambient loop per
environment (the 6 combat board themes from T11, plus a settlement/hub loop
and a title-screen loop — reuse `Encounter.THEMES` as the theme list, don't
invent a new one) as the constant "bed," plus ONE shared combat-tension
layer (percussion/bass ostinato) that fades in on top of whichever bed is
currently playing when state is actively fighting, and fades out otherwise
— so combat music is "the current place, now under threat," not a hard cut
to a different track. Crossfade beds on a theme change (leaving one node's
board for another's).

**Playback** — an autoload singleton (Godot-idiomatic: register it in
`project.godot`'s `[autoload]` section) since `core/*.gd` is pure logic
exercised headlessly by the test suite and can't itself hold
`AudioStreamPlayer` nodes. MUST no-op safely under a headless test run —
verify this explicitly (Godot's null audio driver should tolerate `play()`
calls with no output, but confirm rather than assume) and MUST NOT change
what any existing test asserts.

**Settings** — `core/settings.gd` gains `sfx_volume`/`music_volume` (0-100,
default ~80 each), persisted the same way `anim_speed_multiplier` already is;
two Godot audio buses ("SFX", "Music") so the sliders just set bus
`volume_db`. Add two sliders to the existing settings overlay next to the
animation-speed control.

File ownership: a new `tools/gen_audio.py` (or `scripts/`, agent's call) +
the generated asset files, a new autoload singleton script (`core/audio.gd`
or similar), `project.godot`'s `[autoload]` section, `core/settings.gd`
(additive fields), the settings overlay scene (2 new sliders), and additive
calls in `core/combat.gd` alongside T26's existing bark call sites (do not
restructure those) plus `core/campaign.gd` for node-arrival music-theme
switching and victory/defeat/level-up stingers — campaign.gd already has 3
agents' worth of accumulated changes this session; keep this diff additive
and narrow, don't reformat surrounding code.

- 2026-09-10: **T23–T27 all complete.** T23: `power.gd` now prices save-or-suffer
  control by denial severity (stun/paralyze full weight down to deafened
  near-zero) instead of a flat constant; retuned `scaler.gd`'s `TIER`/
  `BOSS_LEAD_SHARE` back to the 90/75/50% targets, boss win-rate spread
  tightened from 60 points (8–68%) to 45 (15–60%). Honestly surfaced a new
  ceiling instead of papering over it: mammoth (60%) vs shop-captain (15%) is
  a "chaff vs. chunk" mispricing — a lone tough bruiser prices for a fight it
  doesn't survive — needs a survival/attrition scoring term, logged as the
  next tuning target, not improvised. T24: two-weapon fighting (an off-hand
  light-weapon slot, a no-ability-mod bonus-action off-hand attack) plus Nick
  mastery folding that attack into the Attack action via the same `free`
  mechanism Cleave uses — the last of the 8 2024 weapon masteries. T25: the
  6 merchant nodes are now sized settlements (camp/village/town) with real
  service tabs — Generalist everywhere, Weaponsmith/Armorsmith/Alchemist/
  Librarian/Healer/Innkeeper spread across village/town per node, one
  flavor line per NPC, `GIVER_IDS` replaced by "has an Innkeeper." T26:
  hand-authored one-line combat barks (hit/crit/kill/low-HP/down/victory),
  faction-flavored for foes, floating over the hex sprite in `scenes/main.gd`'s
  `Board`, 20% fire rate off a private reproducible RNG stream so seeded runs
  never desync, fully skipped under headless/fast mode. T27: procedurally
  synthesized placeholder audio (`tools/gen_audio.py`, stdlib only) — 14 SFX
  stings reusing T26's exact bark trigger points, plus one ambient loop per
  environment theme with a shared combat-tension layer that fades in/out on
  top of it; `sfx_volume`/`music_volume` sliders in the settings overlay.
  Also fixed directly: the `equip_legendary` achievement hookup T19 had
  flagged as out of its file scope. **Full suite: 23 test files (test_bestiary
  reports OK), 0 failures; all four `drive_*` smoke scripts pass.** Pushed.

## T28 — combat UI overhaul: layout, icons, animation, log color (locked 2026-09-11, spec from the user, dispatched now)

Five pieces, all in `scenes/main.gd` (one agent, one file — splitting would just
cause merge pain), reported together as one "the combat screen is getting hard
to read" complaint:

1. **Layout, to stop overlap when zoomed.** The action log moves from a
   centered top panel to a **left sidebar** (fixed-width column). The turn
   order bar moves to the **top**, rendered as icons (not the current plain
   name-and-number text) — larger, with each combatant's short name under
   its icon, current turn visually marked. Root layout goes from a single
   `VBoxContainer` to an `HBoxContainer` (log sidebar | right column: order
   bar → board → actor status → action buttons).
2. **Token icons over initials.** The hex board currently draws two-letter
   initials on each token (`_initials(c.cname)`); replace with
   `Icons.class_glyph(class_id)` for party members and
   `Icons.combatant_glyph(c)` for foes — both already exist in
   `core/ui_icons.gd`, this is a rendering swap, not new icon data. Sized
   larger than the initials were.
3. **A more obvious "your turn" indicator.** `Board._draw()` already pulses
   a gold ring around the current combatant (`sin(Time...)`-driven line
   width) — make it a real blink (alpha or scale pulsing on the ring/token
   itself), it reads as too subtle currently.
4. **Attack animations.** Nothing currently animates a hit beyond the
   existing dice-reveal popup and floating damage numbers — enemy actions
   are hard to track turn-to-turn as a result. Add three kinds, keyed off
   whatever `resolve_attack()`/`cast()` already return to the UI layer
   (the same data `show_reveal()` already consumes, extended if needed):
   melee (a brief lunge — tween the attacker's token toward the target and
   back), ranged (a projectile dot/line traveling attacker → target),
   spell (a radial flash at the target, or swept along a cone's hexes for
   an AoE). Keep these cosmetic-only and skip them under
   `SORCMERC_FAST`/headless, matching how T26/T27's cosmetic systems
   already gate on that.
5. **Log colorization.** `_logbox` is already a `RichTextLabel` with
   `bbcode_enabled = true` — a plain line with no bolded/colored word
   (an actor name, a move, a plain narration line) is hard to visually
   parse against ones that already highlight hits/damage. Add a
   presentation-layer colorizer applied when combat's own log lines are
   copied into `_logbox` (wherever `_flush_log()` reads `cb.log` today) —
   NOT in `core/combat.gd`, which stays plain-text/bbcode-free as a model
   layer. Recognize and tint: combatant names, dice notation (`d20[...]`,
   `NdM`), numbers immediately before "damage"/"HP"/"gold", and a small
   set of verbs (hits/misses/CRITS/moves/casts/uses).

File ownership: `scenes/main.gd` only (its `Board` inner class included).
Do not touch `core/combat.gd`'s log content/format — only how the UI layer
renders lines already produced. `core/ui_icons.gd` may gain a helper if
useful but its existing glyph functions should already cover this.

- 2026-09-11: **T28 complete.** Root layout is now an `HBoxContainer`: a
  fixed-width gold-bordered action log sits as a left sidebar (was a
  centered top panel prone to overlap when zoomed), the right column runs
  title → turn-order strip → board → actor status → buttons. The turn
  order strip is icon tiles (class glyph for heroes, a new creature-type
  glyph map for foes — `Icons.combatant_glyph()` extended, 9 types so far,
  falls back to a plain melee/ranged mark) with the name and initiative
  underneath, current turn gold-boxed, dead/downed dimmed. Board tokens
  swapped two-letter initials for the same glyphs, larger. The current-turn
  ring is now a real blink, not just a pulsing line width. Attack FX added
  (melee lunge, ranged projectile, spell ring), cosmetic-only and skipped
  under `SORCMERC_FAST`/headless like T26/T27's systems — AI turns fire one
  FX per combatant that lost HP that turn (a HP-snapshot heuristic, not a
  true per-attack event, flagged as the honest ceiling: AI has no attack
  callback to hook precisely). The log now colorizes combatant names, dice
  notation, damage/HP/gold numbers, and hit/miss/crit/move/cast verbs —
  purely presentational, `core/combat.gd`'s log text is untouched.
  **Full suite: 24 test files (new `test_ui_log.gd`, 25 checks), 0 failures;
  all four `drive_*` smoke scripts pass.** Pushed.

## T29-T31 — feedback batch round 2 (locked 2026-09-11, dispatched now)

A large batch of direct user feedback. Handled directly already (separate
commit): hidden-mover-no-OA, Help-revives-downed-ally-1HP, magic item price
retune (common in 20-30gp, exponent 6→4), opening stage combat-only, rest
capped at 2 short/1 long per run, lifetime/class XP thresholds halved. Also
already-confirmed-correct-as-is, no change needed: ranged disadvantage when
adjacent (already implemented), attack-FX kind already keyed off the verb's
own type not the caster's class, BG3 does not revive on long rest either
(researched — it's a paid NPC/scroll/spell action there too, matching this
project's existing model).

Remaining, split by file ownership into 3 parallel dispatches:

**T29 — combat screen round 2** (`scenes/main.gd`, following directly on
T28's sidebar/icon/animation work):
- Turn-order strip shows current HP instead of initiative number.
- The floating combat-result popup shows HIT/MISS/save-result or the
  damage number as the primary readout, not the raw d20 value (the dice
  breakdown can stay as secondary/smaller if it still fits).
- Action buttons that overflow the bottom bar must stay reachable (scroll
  or wrap) instead of becoming invisible/unplayable past some count.
- Number-key hotkeys must still work to switch between different actions
  while in targeting/aiming mode, not just before it.
- A dramatic defeat animation/effect when the party is wiped (state
  becomes "lost"), not just a plain text/state change.
- Hide the debug-only "Replay seed" / "New encounter" buttons whenever
  `OS.is_debug_build()` is false (a real exported release build).
- Melee vs. ranged attack toggle: a character carrying both a melee and a
  ranged weapon option should be able to pick which one their basic
  Attack verb uses, rather than being locked to whichever one `adapter.gd`
  happened to put in `attacks[0]`.
- General pass on how spellcaster resources (slots, pools) are shown —
  the ask was open-ended ("generally improve"), use judgment.
- Add the missing action/spell tooltip descriptions this session's own
  earlier tooltip pass (`_verb_tooltip`) left uncovered, and make sure
  every tooltip that deals damage shows its actual dice notation, not
  just a mechanical summary with the number buried in it.

**T30 — route variety + post-combat/treasure opportunities**
(`core/campaign.gd`, `core/quest.gd`):
- Much more route/node variety — the `POOL` constant's template count is
  the lever; add meaningfully more combat/merchant/rest/treasure templates
  (varied titles/flavor, following the existing hand-authored style) so a
  route doesn't feel like the same handful of stops reshuffled.
- After combat, or in treasure rooms, add skill-check-gated opportunities
  (a Survival/Perception/etc. check unlocking a bonus find, a shortcut, a
  warning about the next fight, your call on the concrete shape) — reuse
  the existing check-roll patterns already in this file (`identify_check`
  is one) rather than inventing a new one.

**T31 — Don't-Starve-style barks** (`core/audio.gd`, `core/barks.gd`,
whichever scene plays them per T26/T27):
- The existing text barks (T26) get a paired short "symphonic gibberish"
  stinger (procedurally synthesized, matching T27's synthesis approach —
  a brief pitched warble/blip per bark, not real voice acting) instead of
  firing silently. Reuse `tools/gen_audio.py`'s approach for any new
  audio assets needed.

File ownership is split cleanly (main.gd / campaign.gd+quest.gd / audio.gd
+barks.gd) so these three can run fully in parallel with no collision.

- 2026-09-11: **T29-T31 complete**, plus the opportunity-check UI wiring/
  persistence T30 flagged as its own gap. T29: turn-order tiles show
  initiative *and* HP (HP-only was tried, corrected back per direct
  feedback — the strip's actual sequence was always initiative order,
  cb.order, never touched either way), attack-result popups lead with
  HIT/MISS/CRIT/SAVED over the raw d20, action buttons scroll instead of
  overflowing, number hotkeys work mid-targeting, a real defeat animation
  (board shake, red wash, shockwave ring), debug buttons hidden outside
  `OS.is_debug_build()`, a melee/ranged weapon toggle, per-slot-level
  caster resource pips, and tooltips now show prose *and* real damage
  dice for every verb that was missing either. T30: POOL nearly doubled
  (35→62 templates), a Perception/Survival opportunity check after combat
  or in a treasure room (bonus gold, or a preview of the next stage's
  fights), wired into the visiting-node UI and carried by
  campaign_save.gd. T31: every text bark (T26) now pairs with a short
  synthesized "symphonic gibberish" stinger (4 voice archetypes x 3
  variants, Don't Starve-style), reusing T27's synthesis approach and the
  existing bark trigger points — no new hookpoints. **Full suite: 24 test
  files, 0 failures; drive_ui/drive_campaign both pass.** Pushed.

This is a multi-week build; phases 0–1 are the critical path and land first.
