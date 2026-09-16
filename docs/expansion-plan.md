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

## T32 — a guided tutorial fight (locked 2026-09-11, dispatched now)

A first-time-friendly on-ramp: one small, hand-authored, easy combat encounter,
reachable directly from the title screen, with a step-by-step walkthrough of
the combat GUI before/during the first couple of turns.

**The fight itself:** deliberately simple and safe — a single weak, low-CR
foe (a lone goblin or similar, easy difficulty, no special mechanics the
tutorial hasn't explained yet), a small 1-2 character party (reuse existing
presets rather than inventing new characters), on a plain board. The goal is
a fight nobody can meaningfully lose while they're still reading callouts,
not a real difficulty test.

**Entry point:** `scenes/game/game.gd`'s title screen gets a "Tutorial"
option alongside "New run" that launches straight into the fixed encounter
(no party setup screen — party is pre-made).

**The walkthrough:** a step-based overlay in the combat scene (gated behind
a flag, off by default for every normal fight) that highlights and explains,
in order: the action log (what it's for, where it lives now — left sidebar
per T28), the turn-order strip (whose turn, HP, what the icons mean), the
hex board (movement, targeting, the blue move-field, the odds chip), a
combatant's HP bar/status glyphs, the action button row (hotkeys, cost tags,
the tooltips T29 already added), and the actor status line (action/bonus/
move economy). Each step: a short explanation, a "Next" (and "Skip
tutorial") control, blocking normal play input until dismissed. Once the
walkthrough finishes, the fight plays exactly like a normal one — same
combat.gd, same rules, nothing special about how it resolves.

File ownership: `scenes/game/game.gd` (title screen entry), `scenes/main.gd`
(the walkthrough overlay — additive, gated behind a flag, must not change
default combat behavior), and a small new data/const block for the fixed
tutorial encounter (in campaign.gd or a new small file, agent's call).

- 2026-09-11: **T32 complete.** A "❖ Tutorial" button on the title screen
  launches straight into a fixed, pre-made fight — Vera (fighter) + Ilsa
  (cleric) vs. one 7-HP goblin, on forest-clearing (the one theme with no
  objects/hazards to also explain) — no party setup, skipped entirely. A
  6-step walkthrough overlay dims everything but the region it is
  explaining (action log → turn order → hex board/targeting → reading a
  combatant's HP/status → the action button row/tooltips/hotkeys → the
  actor's action economy line), gold-outlined, blocking input and holding
  the goblin's AI turn until dismissed; Skip drops straight into ordinary
  play at any point, and once finished the fight resolves through the
  exact same combat.gd everything else uses — nothing about resolution is
  tutorial-specific. `core/tutorial.gd` (new) holds the fixed spec/party/
  steps as pure data. **Full suite: 24 test files, 0 failures;
  drive_ui/drive_game both pass.** Pushed.

## T33 — author combat mechanics for the missing spells (locked 2026-09-11, dispatched now)

Of the 146 catalogued spells, only 8 have a hand-authored combat mechanics
override (`data/effects/spells.json`) and 50 more have usable *raw* mechanics
(the regex prose-parse happened to produce something), so a caster's action
bar silently drops roughly 88 spells — several of them common, expected
combat/support picks: Bless, Aid, Shield of Faith, Spiritual Weapon, Magic
Weapon, Fire Shield, Revivify, Mass Cure Wounds, Greater/Lesser Restoration,
Confusion, Faerie Fire, and more. `Effects.spell_verbs_for` already silently
skips anything `Effects.spell()` can't merge into a `cost` + damage/heal/
conditions dict — that's correct behavior for a genuinely non-combat spell
(Message, Scrying, Disguise Self, ...), the bug is that it's ALSO silently
eating spells that should be castable.

Scope this in two tiers:
1. **Straightforward** — damage spells (single-target or AoE, save-or-half
   or spell-attack) and enemy-debuff spells (a save inflicting a real
   condition from `data/effects/conditions.json`'s 15) fit the existing
   `cast()`/`_spell_hit()` shape exactly like `scorching-ray`/`burning-hands`
   already do. Author these directly, following `data/effects/spells.json`'s
   existing entries and its own `_note` header for the schema.
2. **Needs new plumbing, do NOT force it** — ally-targeted buffs (Bless,
   Shield of Faith, Aid raising max HP, Magic Weapon enchanting a weapon for
   its duration) don't fit `cast()`'s current model at all (`_spell_hit`'s
   conditions branch assumes a save-or-suffer effect on an ENEMY, not a
   granted buff on a cast target); summons, and anything with a duration
   that outlives one cast, are the same story. List these explicitly in the
   report rather than half-implementing a buff system under this task's
   scope — that's real design work for a follow-up, not something to
   improvise inside a content-authoring pass.

File ownership: `data/effects/spells.json` (additions only, don't touch the
8 existing entries), and `tests/test_rules.gd`/`tests/test_combat.gd` for
coverage. Touch `core/combat.gd`/`core/rules/effects.gd` ONLY if a
straightforward (tier 1) spell genuinely needs a trivial, already-established
extension (e.g. a new `shape` value already handled elsewhere) — anything
bigger belongs in the tier-2 follow-up list, not this pass.

- 2026-09-11: **T33 complete**, plus a repo-health audit and its fixes. T33
  found a bigger problem than the one it was sent for: the ~50 spells
  believed to already have "usable raw mechanics" actually didn't — the SRD
  export writes `dice`/`halfOnSave`/`area`, `_spell_verb` reads `count`/
  `sides`/`half_on_save`/`shape`, so Lightning Bolt, Blight, Cone of Cold,
  Guiding Bolt and more were silently resolving as 1d6 single-target with no
  shape. Fixed those plus a genuine engine gap (`cast()` ignored `conditions`
  entirely, so no damage-less save-or-condition spell did anything) and
  authored 19 new spells with real SRD numbers — 8 cantrips, 8 leveled
  damage spells (single/AoE, both save types), 3 save-or-condition. Cataloged
  a long, honest tier-2 list of what still needs real new plumbing (ally
  buffs, summons, multi-target heals, resurrection, persistent battlefield
  areas, line-shaped AoE, multi-turn control) rather than forcing any of it
  in. Separately: a read-only repo audit found 5 items, 4 fixed directly (an
  unknown-equipped-item now warns instead of silently going inert, a stale
  progression.gd comment, a fully rewritten README reflecting the actual
  current scope, a superseded-banner on the old pre-expansion improvements.md)
  and 1 confirmed non-issue-for-now and documented (concentration-break
  cleanup — checked against what T33 actually shipped: nothing outlives a
  broken concentration today, since every condition it grants is already
  capped at one round). **Full suite: 24 test files, 0 failures; drive_ui
  passes.** Pushed.

## T34 — let an already-made choice be revisited (locked 2026-09-11, dispatched now)

The request was "enable back stepping during character creation phases."
Checked first, empirically (not just by reading the code): `scenes/creator/
creator.gd`'s top-level step wizard (basics → class → abilities → skills/
background → equipment) ALREADY has a working Back button — verified with a
headless probe that species/state survive going back and forward. That is
not the gap.

The real gap: every generic pending choice (skill-choice, feat-choice,
subclass, ASI, spell-choice, weapon-mastery-choice, ...) is rendered by
iterating `sheet.pending` — the resolver's list of choices NOT YET made.
The moment `ch.decide(key, ...)` records a complete decision, that key drops
out of `pending` and its picker widget vanishes from the screen entirely, in
BOTH `creator.gd`'s step panels and `levelup.gd`'s flat choice form (which
shows every pending choice as a toggle-group already — so within a still-
pending choice you CAN already freely change your pick; the gap is only
choices that have already resolved and disappeared). There is currently no
way to reopen and change an already-made generic choice short of restarting
the whole character.

**The fix has to start below the UI.** `core/rules/resolve.gd`/`grants.gd`
would need to expose the full set of choice points a build has ever
encountered — decided or not — not just the unresolved ones, so creator.gd/
levelup.gd can render an already-decided choice as an editable widget
(pre-populated with the current picks, clicking toggles it the same way an
unresolved one does) instead of it just vanishing. Read `core/rules/
resolve.gd`, `grants.gd`, and `Resolved`'s `pending` field construction
before touching anything — understand exactly how "pending" is computed
today before adding a sibling "all choice points" list next to it.

File ownership: `core/rules/resolve.gd`, `core/rules/grants.gd` (if the
choice-point enumeration genuinely needs to move there), `scenes/creator/
creator.gd`, `scenes/creator/levelup.gd`. Keep the change additive — pending
computation itself must not change, only what ELSE gets exposed alongside it.

## T35 — measure the melee-closes-instantly problem, don't fix it blind (locked 2026-09-11, dispatched now)

Diagnosed directly from the numbers before dispatching anything: standard
speed is 30 ft = 5 hexes/turn (`core/adapter.gd`'s `FT_PER_HEX := 6`), boards
are 5-9 hexes wide (`core/encounter.gd`'s `board_for`/theme boards), foes
spawn only `SPAWN_GAP := 3` hexes from the party at minimum. A single move
can close nearly the whole board, so ranged range (capped at
`RANGE_CAP := 8` hexes) rarely gets a real window before everyone is
adjacent. User's own framing: "most ranged spells and ranged attacks should
work for under 3 hex unit distance, or the combat map can be enlarged" —
and explicitly wants **measured results before deciding**, not a live
balance change picked blind.

This is a measurement spike. Build a small seeded sweep (follow the existing
pattern `tests/test_scaler.gd`/`core/scaler.gd`'s TUNING sweeps already use)
that measures, across ~100+ seeds of real fights (`AI.take_turn` on both
sides, like `autoplay.gd`/the scaler's own win-rate sweeps already do):
how many rounds until every combatant is adjacent to an enemy at least once,
what fraction of a fight's total attacks happen at range 2+ vs. melee range,
and party win rate — for:
1. **Baseline** (current numbers, unchanged) — the control.
2. **Candidate A — tune the hex/foot conversion.** Increasing
   `FT_PER_HEX` shrinks movement speed in hex terms WITHOUT touching
   `RANGE_CAP` (ranged is already cap-bound at 8, so its effective hex
   range barely moves), which should slow how fast melee closes distance
   relative to a board's width — try one or two concrete values and
   measure them, don't guess one number and call it done.
2. **Candidate B — enlarge the boards.** Widen the existing theme board
   layouts (`core/encounter.gd`) by some amount and re-measure with
   `FT_PER_HEX` left at its current value.
3. Optionally, a combination of both, if the two candidates individually
   under-shoot.

Report the measured numbers for baseline vs. every candidate side by side —
this task's job is to hand back data for a decision, not to make the
decision. Whatever candidate code changes were made to take the
measurements should be left in the working tree, clearly separable (or on
their own throwaway commit) so the orchestrating session can pick one,
adjust it, or discard all of them — do not silently land a chosen value as
if it were final.

File ownership: a new measurement script under `tests/` (not a permanent
`test_*.gd` — name it clearly as a one-off, e.g. `tests/sweep_range.gd`),
`core/adapter.gd` (`FT_PER_HEX` only, for candidate A), `core/encounter.gd`
(board hex layouts only, for candidate B). Do not touch combat resolution
logic, weapon/spell data, or anything else — this is range/movement/board-
size tuning only.

- 2026-09-11: **T34 and T35 complete.** T34: `Resolved.choice_points` sits
  alongside `pending` (built by re-running the same pending-resolution pass
  with an empty choices dict and keeping decided-or-pending entries — no new
  enumeration code, `pending` itself untouched byte-for-byte), and creator.gd/
  levelup.gd render an already-decided choice as a `✓`-marked, still-clickable
  widget instead of it vanishing once answered. Verified downstream safety
  empirically (swapping a subclass re-resolves clean) and caught a real
  either-or-pair bug in the process (an ASI and its paired feat-choice could
  otherwise both get satisfied at once). T35 (a measurement spike, explicitly
  not a balance change to ship): 150-seed sweeps found the melee-closes-fast
  problem's premise doesn't hold up — ~80% of attacks by combatants that
  actually HAVE a ranged option already happen at 2+ hexes, at baseline and
  under every candidate tried (FT_PER_HEX 8/10, wider boards, a SPAWN_GAP
  diagnostic). The 32.5% *overall* ranged-attack share is roster composition
  (most bestiary bodies are melee-only), not geometry — confirmed by a 15%
  (forest-clearing, all-beast) to 46% (goblin-camp, archers) per-theme spread
  on the SAME board size. Neither candidate moved the ranged-share needle;
  FT_PER_HEX just made fights longer with a 7-point win-rate cost, wider
  boards were geometrically inert because `_foe_spots` spawns foes at exactly
  `SPAWN_GAP` regardless of how much room exists past that. Real numbers
  handed back, nothing adopted — see the branches `t35-candidate-a-ft8`,
  `t35-candidate-a-ft10`, `t35-candidate-b-wide-boards`,
  `t35-diagnostic-spawn-gap` (each one commit, cherry-pick or discard).
  **Full suite: 25 test files, 0 failures; all four `drive_*` smoke scripts
  pass.** Pushed (T34 + T35's throwaway sweep script only — the candidate
  branches are not merged, by design).

## T36 — measure starting distance alone (locked 2026-09-11, dispatched now)

A follow-up to T35, same rules: measurement only, nothing adopted
automatically. T35's one SPAWN_GAP data point (`t35-diagnostic-spawn-gap`,
3→6) was confounded — it ran ON TOP OF the wider-boards candidate, not in
isolation, and was explicitly flagged as outside that task's own scope. This
task isolates the one variable: increasing `SPAWN_GAP` (`core/encounter.gd`
— how close a foe may spawn to the nearest party member at combat start)
alone, boards and `FT_PER_HEX` left at their current values.

Reuse `tests/sweep_range.gd` (already on master from T35 — do not rebuild
the measurement tooling) exactly as T35 ran it, varying only `SPAWN_GAP`.
Try at least 2-3 values spanning a real range (e.g. 4, 6, 8 — use judgment,
but don't test only one value and call it decided). Report the same metrics
T35 did (rounds to universal adjacency, overall ranged-attack share, ranged
share among attackers who have a ranged option, party win rate, fight
length, and the never-fully-closed fight count) side by side against T35's
already-published baseline row.

File ownership: `core/encounter.gd` (`SPAWN_GAP` only), reusing
`tests/sweep_range.gd` unmodified unless it genuinely needs a small
extension to report the same breakdown cleanly. Leave the tree back at
baseline when done, one commit per value tested on its own branch, matching
how T35 organized its candidates — do not land a chosen value on master.

- 2026-09-11: **T36 complete** (measurement only, nothing adopted). Isolated
  the one variable T35's own SPAWN_GAP diagnostic confounded (that run had
  wider boards active at the same time). Baseline confirmed exact match to
  T35's published numbers on all six metrics — tooling verified sound.
  Tested SPAWN_GAP 4/6/8 alone, boards/FT_PER_HEX untouched: ranged share is
  flat-to-slightly-down as the gap triples (32.5% → 31.4%), confirming T35's
  read cleanly with the confound removed — the low ranged-attack share really
  is roster composition, not geometry. The real, unambiguous effect is a
  **difficulty** one: party win rate jumps 74.7% → 80.7% at gap 4 (more free
  ranged rounds before melee lands), then plateaus by gap 6 (81.3%, no
  further change at gap 8) — current board sizes (5-9 hexes wide) saturate
  past that point; going further needs bigger boards first. Branches
  `t36-spawn-gap-4/6/8`, one commit each, none merged.
  **Full suite: 25 test files, 0 failures.**

## T37 — measure starting distance + slower movement together (locked 2026-09-11, dispatched now)

A further follow-up to T35/T36, same rules: measurement only, nothing
adopted automatically. Individually: T35 found `FT_PER_HEX` (slower
per-turn movement) barely touches ranged share and costs ~7 points of win
rate; T36 found `SPAWN_GAP` (starting distance) alone also barely touches
ranged share but is a genuine difficulty lever (+6-7 points of win rate,
saturating around gap 6 on current board sizes). Neither alone moved the
actual ranged-usage needle. This task measures them TOGETHER — same
mechanism (more approach turns before melee lands) stacking from two
directions might compound differently than either alone, particularly on
the ranged-share metric where both individually landed flat.

Reuse `tests/sweep_range.gd` (on master, unmodified unless it needs a small
extension) exactly as T35/T36 ran it. Combine one of T36's effective
`SPAWN_GAP` values (4 or 6 — pick based on its own findings: gap 6 already
saturates board size on most themes, so consider whether gap 4 + slower
movement is the more informative combination, or test both) with one of
T35's `FT_PER_HEX` values (8 or 10). Measure at least 2 combinations, not
just one, and include T35's and T36's already-published baseline/candidate
rows in your final side-by-side table for direct comparison — the point is
whether the combination is additive, sub-additive, or does something
neither predicts alone.

File ownership: `core/encounter.gd` (`SPAWN_GAP` only) and `core/adapter.gd`
(`FT_PER_HEX` only), reusing `tests/sweep_range.gd`. Leave master at
baseline when done (both constants untouched), one branch/commit per
combination tested, matching how T35/T36 organized their candidates — do
not land a chosen combination on master.

## T38 — retune scaler.gd's TIER after adopting SPAWN_GAP=6 (locked 2026-09-11, dispatched now)

`core/encounter.gd`'s `SPAWN_GAP` was just raised 3 → 6 on master, adopting
T36's measured best single difficulty lever (+6.6 win-rate points, no
fight-length cost, real numbers from a 150-seed sweep — see the T35/T36/T37
entries above). That measurement is honest about what it does: it's a
difficulty shift, and `core/scaler.gd`'s `TIER`/`CURVE` constants were
calibrated (T23) against the OLD gap of 3. `tests/test_scaler.gd`'s
calibrated win-rate sweeps confirm the drift directly: normal now measures
86.5% against a 75%±10 target, hard 68.5% against 50%±10 — both outside
band.

Retune `TIER` (and `CURVE`/`MULT_*` only if `TIER` alone can't bring all
three difficulty bands back in range) the same way T23 did: real 200-seed
sweeps via `tests/test_scaler.gd`'s own existing sweep method (do not
build new tooling, that test file already measures exactly what's needed),
targeting 90/75/50% for easy/normal/hard with SPAWN_GAP now fixed at 6.
Also re-sweep and update every `BOSS_POOL` entry's `win_rate` field in
`core/campaign.gd` (feeds `Campaign.BOSS_REF_WIN_RATE`'s XP-bonus math
directly) since boss fights are affected by the same spawn-distance change.
Update `core/scaler.gd`'s header TUNING comment with the new measured
numbers, matching its own established documentation style.

File ownership: `core/scaler.gd`, `tests/test_scaler.gd`, and ONLY the
`"win_rate"` leaf values inside `core/campaign.gd`'s `BOSS_POOL` entries
(nothing else in that file — it has several other agents' worth of
accumulated work in unrelated regions).

**T36/T38 completion (2026-09-11):** SPAWN_GAP raised 3→6 and TIER retuned
in the same push (`526cc2d`, `0547d51`, pushed to master). 200-seed sweeps
after retune: easy 91.0% (target 90), normal 74.0% (target 75), hard 51.5%
(target 50) — all in band. Level-8 sweep still ordered (91.7/73.3/58.3).
Boss pool 24.0% pooled (in the 15–85% climax band); TIER moved
0.85/1.06/1.50 → 1.00/1.35/1.80, nothing else changed. Full 32-file
headless suite green. Two items flagged, not fixed (outside T38's scope):
`Campaign.BOSS_REF_WIN_RATE` (0.698) is stale against the new easy/hard
average (0.7125) — cosmetic, feeds an XP-bonus comment; and the
`sunken-shrine` boss node measures a real outlier at 6.0% (was 24.5%)
because it maps to no faction and always fields `MAX_FOES` of the
hand-tuned MIX — a `THEME_FACTION`/`MAX_FOES` fix, not a `TIER` one.
Neither blocks anything; picked up later if it matters in play.

## T39 — Surprise + Scouting → deployment control (locked 2026-09-11, dispatched now)

Closes a real 5e rules gap (Surprise was never implemented) and gives T30's
existing scouting flavor a mechanical payoff, per direct user request
("go ahead with 1+2" on the two recommended options together).

**Surprise (5e 2024 rule, adapted):** at the moment a combat node is
entered, roll a single group Stealth check for the party (highest-Stealth
member's roll, matching how other party-wide checks in this codebase are
resolved — reuse whatever pattern T30's scouting check already uses, don't
invent a new one) against the encounter's average foe passive Perception
(10 + their Perception mod, averaged across the spawned roster, matching
how `core/scaler.gd`/`core/encounter.gd` already aggregate roster stats
elsewhere). Beat it: party is unseen at combat start. This is a **surprise
round**, not RAW's "surprised combatants act last" — simplest to build on
this engine's existing initiative/turn-order in `core/combat.gd`: the foe
team skips its first turn entirely (no free attacks against it to hand
back later, no bonus-action edge cases). Miss it: normal combat start, no
effect either way (not a penalty — 5e doesn't punish a failed Stealth
check beyond "no surprise").

**Scouting integration:** if the party already passed T30's Survival
scouting check for this node, that guarantees the Stealth check succeeds
outright (skip the roll, go straight to "party unseen") — a successful
scout should never be worse than not scouting, and this makes scouting
worth doing instead of pure flavor text.

**Deployment control (the actual payoff):** when the party is unseen at
combat start (whether by guaranteed scout or a lucky Stealth roll), let
the player freely place party members among the party's normal starting
hexes (swap positions) before round 1 begins — not new hexes, just control
over which party member stands where relative to the (still-hidden-intent)
foe layout. No UI for arbitrary placement; a simple "swap two party
members" control on the existing pre-combat screen is enough. When the
party is NOT unseen, skip straight to combat as today (no regression).

File ownership: new logic lives in `core/encounter.gd` (the Stealth-vs-PP
check, an `unseen: bool` on the build result) and `core/combat.gd` (skip
the foe team's first turn when unseen) — do not touch `core/scaler.gd` or
`core/campaign.gd`'s `BOSS_POOL` (T38 just landed there). UI: whichever
scene currently handles the pre-combat screen (likely `scenes/main.gd` or
a campaign/encounter-entry scene — locate it, don't guess) gets the swap
control, gated on `unseen`. Add tests alongside the existing
`tests/test_encounter.gd`/`tests/test_combat.gd` suites, seeded like
everything else in this codebase.

## T40 — retune win-rate targets to 95/85/75 (locked 2026-09-11, dispatched now)

Direct user request: raise the calibrated win-rate targets in
`tests/test_scaler.gd`'s `TARGET` (currently `{"easy": 90.0, "normal": 75.0,
"hard": 50.0}`, just re-hit by T38) to **easy 95%, normal 85%, hard 75%**.
Easier across the board, not a shape change — same `BAND := 10.0` unless
the new targets can't fit inside it (report if so rather than silently
widening the band).

Method: identical to T38/T23 — real 200-seed sweeps via
`tests/test_scaler.gd`'s own existing `_sweep`, retune `core/scaler.gd`'s
`TIER` (and `CURVE`/`MULT_*` only if `TIER` alone can't hit all three),
update the header TUNING comment with the new measured numbers. Also
re-sweep and update `core/campaign.gd`'s `BOSS_POOL` `win_rate` leaves
(bosses get relatively easier too) and flag `Campaign.BOSS_REF_WIN_RATE`
(T38 already found this stale — fold the fix in here). Level-8 sweep must
stay ordered and neither end a foregone conclusion, same as `test_win_rates`
requires today.

File ownership: `core/scaler.gd`, `tests/test_scaler.gd` (`TARGET` values
and the sweep), and ONLY the `"win_rate"` leaves + `BOSS_REF_WIN_RATE` in
`core/campaign.gd`. T39 (Surprise/deployment) is running concurrently in
`core/encounter.gd`/`core/combat.gd`/`scenes/main.gd`/
`scenes/campaign/campaign.gd` — disjoint files, no coordination needed;
`test_scaler.gd`'s sweep calls `Encounter.build` directly and never sets
an "unseen" flag, so it doesn't exercise T39's surprise-round logic either
way.

**T39 completion (2026-09-11):** landed as `bba1873`. `core/combat.gd` gained
`unseen`/`skips_turn(c)`/`begin_surprise_round()`, riding the existing
dead/stable skip loop in `end_turn()` so every driver honors it uniformly.
`core/encounter.gd` gained `surprise_check(cb, scouted_ahead)`: best-party
Stealth vs. average foe passive Perception, rolled off a seed-derived
stream so it never perturbs the fight's own RNG; `scouted_ahead` (read from
`Campaign.scouted` before `run.enter()` clears it) auto-succeeds. `scenes/
main.gd` added a `"deploy"` mode with swap-position buttons before combat
starts when unseen. Full 25-file suite green (0 failures); `drive_deploy.gd`
added as a scene-driver smoke test (not in the automated test loop, run
explicitly). One known gap, left out of scope: reloading a saved mid-combat
node loses the guaranteed-ambush-from-scouting, since `Campaign.scouted` is
already cleared by then and isn't persisted separately — flagged, not
blocking, revisit if it matters in play.

**T40 completion (2026-09-11):** landed as `741a91b`. `TIER` moved
1.00/1.35/1.80 → **0.96/1.10/1.32** (from T38's numbers); `CURVE`/`MULT_*`/
`BAND` untouched. 200-seed (level-3) / 60-seed (level-8) measured win
rates: easy 94.5/95.0%, normal 83.5/88.3%, hard 75.0/78.3% — all within
1.5 points of the 95/85/75 target, level-8 order preserved. Boss pool
45.0% pooled (was 24.0%, still inside the 15–85% band); `sunken-shrine`'s
outlier jumped 6.0%→47.0% as a side effect (still not "fixed" per T38's
note — the `THEME_FACTION` gap remains, just less painful at this TIER).
`Campaign.BOSS_REF_WIN_RATE` corrected 0.698→0.8475 with a comment to
re-derive it on every future TIER retune, closing the staleness T38
flagged. Full suite: 25 files, 4930 checks, 0 failures.

## T41 — bug/gap cleanup: drive_campaign failures, shrine outlier, scout persistence (locked 2026-09-11, dispatched now)

Three real, previously-flagged-but-not-fixed items, bundled since they're
small and disjoint:

1. **`drive_campaign`'s 8 failures** — reported "pre-existing" and waved
   through by three separate agents (T34, T38, T40) without ever being
   root-caused. Run `SORCMERC_SEED=5 SORCMERC_FAST=1 godot --headless
   --path . -s tests/drive_campaign.gd` and actually chase why: "the quest
   never made it into the party log as active", "never bought anything",
   "never rested", ending `state=lost` at stage 0/5. Find the real cause
   (a driver script bug vs. an actual campaign-flow bug) and fix it, or
   report back precisely why it can't be fixed if it turns out to be a
   stale/obsolete driver script.
2. **`sunken-shrine` boss node win-rate outlier** — flagged by T38, still
   present after T40 (bounced 6.0%→47.0% purely as a side effect of the
   TIER retune, never actually addressed). It maps to no `THEME_FACTION`
   and so always spawns `Scaler.MAX_FOES` of the hand-tuned `MIX` with the
   whole difficulty budget poured into `mult`. Give it a real faction/
   habitat mapping (or a dedicated smaller roster) so it scales like the
   other boss nodes instead of swinging wildly with every TIER change.
3. **T39 scout-guarantee lost on reload** — `Campaign.scouted` is cleared
   by `run.enter()` before a mid-combat save's reload re-reads it, so a
   guaranteed ambush from a prior successful scout doesn't survive a save/
   load. Persist whatever's needed (likely a small addition to
   `core/campaign_save.gd`) so reloading a scouted combat node still
   guarantees the surprise check.

File ownership: `tests/drive_campaign.gd` (read/diagnose, fix only if the
driver itself is wrong), `core/campaign.gd`, `core/scaler.gd` (item 2
only — coordinate with nothing else since no other agent currently owns
it), `core/campaign_save.gd`. Full suite + all `drive_*` smoke tests green
before reporting done.

**T41 completion (2026-09-11):** landed as `777e0e0`. All three items were
real, root-caused, not just papered over:
1. `drive_campaign`'s 8 failures were the driver's own fault, not a
   campaign bug — its hand-rolled fighter (walk + `] Attack`, no spells,
   no heals) lost the now-unavoidable stage-0 combat (T12 made stage 0
   combat-only) and the run never got past it. Fixed by driving the fight
   with the real `AI.take_turn` instead; also handles T39's deploy mode.
   Now reaches stage 5/5, state=won.
2. `sunken-shrine` had no `THEME_FACTION` entry, so it always fell
   through to the hand-tuned MIX (max foes, full budget into mult) —
   the actual cause of its wild swings across every TIER retune. Mapped
   to `"undead"` (measured against `"cultist"`, rejected): 47.0%→64.5%,
   mid-range against hard's 75% target. `BOSS.win_rate` and both TUNING
   comments updated to match.
3. Scout-guaranteed-ambush now survives save/load: `Campaign.node_scouted`
   is computed before `scouted` is cleared, persisted in
   `campaign_save.gd`, and both combat-launch sites read it directly
   instead of threading a local through a call argument.

Full suite green (25 test files, 0 failures) and all 5 `drive_*` smoke
tests OK, `drive_campaign` included (previously always lost at stage 0).

## Open-world campaign map (locked 2026-09-11) — replaces the linear route as the default

Direct user request: replace the linear node-route campaign (`core/campaign.gd`,
`scenes/campaign/*`, T5/T6/T7/T9/T12 etc.) with a Mount & Blade-style open
world — several settlements across a free 2D map, NPC/monster parties that
roam and fight each other or the player, settlements belonging to factions
whose opinion of the player rises or falls with what the player does near
them. The linear campaign is **not deleted** — it stays wired up behind a
debug flag (same pattern as `SORCMERC_SEED`/`SORCMERC_FAST`) because its
determinism is exactly what the rest of this project's testing discipline
depends on; normal play only ever sees the open world once O8 lands.

Design decisions locked with the user (2026-09-11 Q&A), each with the
alternative considered and rejected:
- **Movement**: real-time with pause, not turn/day ticks — closer to the
  M&B reference; a `WorldClock` node drives it, pausable at any time.
- **Map shape**: a free continuous 2D map (`Vector2` positions, no hex
  grid), not the existing Hex utilities — settlements/parties sit at
  arbitrary points, movement is steering-toward-goal, not hex pathing.
  The hex grid stays exactly where it already is: inside a single combat.
- **Sim depth**: a real economy computed on-visit (not a background tick
  for every settlement every frame) plus roaming monster-faction parties
  that can fight NPCs or the player — explicitly **not** full faction
  diplomacy/war between "civilized" factions; conflict is monsters/bandits
  vs. settlements and the player, not settlements vs. each other.
- **Off-screen battles**: resolved instantly with the existing seeded
  `AI.take_turn` autoplay loop (the same one every `test_scaler.gd` sweep
  already uses) — no visible fight, no new AI to write.
- **Scale**: small first pass — 5-8 settlements, 3-6 roaming parties live
  at once. Grow the roster once the systems work, not before.
- **Visuals**: reuse the isometric projection/tile-painting code the
  combat board already has (`_iso()`/`_pix()`/foliage/tinting in
  `scenes/main.gd`), at a larger scale with a panning/zooming camera —
  not a new abstract schematic map style.
- **Economy**: computed at the moment of a settlement visit from a seeded
  formula (time-since-last-visit + nearby-battle flags), not a live
  background simulation — matches "computed on visit" over "fully live".
- **Faction opinion**: tracked **per faction**, not per individual
  settlement — helping/wronging one settlement moves how every settlement
  and roaming party of that faction treats the player. Effects (all four,
  user picked all): worse prices/refused services, fewer/no quests,
  hostile guards below a threshold, hostile roaming parties of that
  faction. Raised by completed quests and helping in a fight; lowered by
  theft and killing. Decays slowly toward neutral over time rather than
  staying wherever the player last left it.
- **Stealing**: a new settlement-visit action, a skill check in the same
  shape as T30's Survival scouting check (roll vs. a DC, success/failure
  narrated the same way) — not a stealth minigame or a combat-time action.

### Build order (each phase disjoint enough to dispatch separately)

**O1 — world data model + clock + player movement.** `core/world.gd`:
`WorldClock` (real-time `_process(delta)` accumulator, `pause()`/`resume()`),
`Settlement` (position, faction, kind), `RoamingParty` (position, faction,
goal, `is_player`). Player movement: click/hold a direction, moves at a
fixed speed toward the cursor/goal while unpaused. No rendering yet —
built and tested headless, the same way `core/campaign.gd` was. No other
phase can start until this lands (everything else reads its shapes).

**O2 — isometric world rendering + camera.** New `scenes/world/*` scene.
Reuses `scenes/main.gd`'s `_iso()`/`_pix()`/ground-tinting/foliage helpers
(factor them out to a shared autoload/RefCounted if duplicating them
becomes awkward — call this out in the PR rather than deciding it now)
at a larger scale; settlements as landmarks, parties as tokens; camera
pans by drag, zooms by scroll. Depends on O1's shapes.

**O3 — NPC/monster/faction roaming-party AI.** Movement goals: patrol a
fixed route, wander near a settlement, or hunt the nearest hostile party
(monster factions hunting settlements/player; a settlement's own parties
defending or fleeing). Faction-tagged, reuses `core/scaler.gd`'s
`FACTIONS`/`THEME_FACTION` vocabulary rather than inventing a new faction
list. Depends on O1.

**O4 — encounter trigger.** When the player party's position and a
hostile party's position close within a radius, pause the `WorldClock`
and hand off to the existing, **completely unchanged** `scenes/main.tscn`
hex-combat scene — same pattern `scenes/campaign/campaign.gd`'s
`_launch_combat()` already uses (instantiate, set `.party`/`.spec`, await
`.result`). The battle itself does not change; only what puts the player
into it. Depends on O1, O3.

**O5 — off-screen instant battle resolution.** When two non-player
parties' positions close within the same radius, resolve immediately:
build an `Encounter` from each side's roster and run the existing seeded
`AI.take_turn` loop headless (reuse, don't reimplement — this is the exact
loop `tests/test_scaler.gd`'s `_sweep`/`_sweep_boss` already run). Winner
survives (possibly hurt/reduced), loser's party is removed or routed.
Depends on O1, O3.

**O6 — settlement visit: services + economy-on-visit + stealing.**
Visiting a settlement reuses T25's `node_services`/stock pattern, with
prices/stock computed from a seeded formula keyed on time-since-last-visit
(plus a flag if a nearby battle happened recently — feed off O5's
outcomes). Add the new "steal from the market" action: a skill check in
`opportunity_check()`'s shape, success takes gold/goods free, any attempt
(success or failure — lock this down in the phase's own PR, not guessed
here) costs opinion with that settlement's faction. Depends on O1, O5 (for
the battle-aftermath price flag).

**O7 — faction opinion.** `core/faction_opinion.gd` (or similar): one
score per faction, persisted, read by O6 (prices/services/steal-cost),
`core/quest.gd` (quest availability/offers), O3/O4 (guard and roaming-
party hostility thresholds). Quest completion and helping a settlement's
party in a fight (O4/O5) raise it; theft (O6) and killing a faction's
combatants lower it; a slow per-in-game-day drift moves it back toward 0
when nothing happens. Depends on O3, O4, O5, O6 all existing to hook into.

**O8 — New Game mode switch.** The title/party-setup flow
(`scenes/game/game.gd`) offers the open world as the only normal-play
option; the existing linear `Campaign`/`scenes/campaign/*` stays reachable
only via a debug env var (e.g. `SORCMERC_LINEAR_CAMPAIGN=1`), matching how
`SORCMERC_SEED`/`SORCMERC_FAST` already gate test/debug paths — not
deleted, not user-facing, kept exactly because its determinism is what
the test suite leans on. Depends on O1-O7 all being playable end to end.

File ownership per phase will be scoped in each phase's own dispatch
(this entry is the locked design, not a file-ownership grant) — O1 first,
serial with nothing else in flight against `core/world.gd` until it lands,
same "phase 1-2 forces serial" caution the original F1/F2 phasing used.

**O1 completion (2026-09-11):** landed as `0199298`. `core/world.gd` (one
file, ~105 lines): `WorldClock` (`RefCounted`, not a `Node` — a `tick(delta)`
method the caller drives, so it's headless-testable and leaks nothing),
`Settlement` (`id`/`sname`/`position`/`faction`/`kind`), `RoamingParty`
(`id`/`position`/`faction`/`is_player`/`goal`/`speed`/`at_goal()`), and a
`World` container (`clock`/`settlements`/`parties`,
`add_settlement`/`add_party`/`player()`/`set_goal()`/`tick()`/
`move_toward_goal()`). Pause gates movement in exactly one place
(`World.tick()`); `move_toward_goal()` itself is pause-agnostic, a
primitive O3's AI will call directly. `tests/test_world.gd`: 29 passed.
Full suite: 25 files, 0 failures. Nothing else in the game references
`core/world.gd` yet — purely additive, `core/campaign.gd`/`scenes/*`
untouched. No spatial query/serialization added (deliberately — O4/O5
need proximity checks, O7 needs persistence; both are that phase's job,
a linear scan over 3-6 parties needs no index yet).

**O2/O3 completion (2026-09-11, landed together):** both built in parallel
against O1, no collision.

O2 (`e641747`) — `scenes/world/world.tscn`+`.gd`, runnable standalone
(`godot --path . scenes/world/world.tscn`). Isometric ground as tessellating
projected quads (discs like combat's hexes overlapped into domes at this
scale — quads fixed it), tokens matching the combat board's flat-base +
camera-facing-ball look. Camera: right-drag pans, wheel zooms about the cursor
(0.25-2.5x clamped), left-click sets the player's goal (goal ringed gold),
a Pause/Resume button + Day/HH:MM readout. Deliberately duplicated (not
extracted) `scenes/main.gd`'s ~25 lines of iso-projection math rather than
touching that file, which this phase couldn't edit — flagged as the
extract-to-`core/iso.gd` upgrade path once a phase is free to touch
`main.gd`. `tests/drive_world.gd`: OK — caught one real bug along the way
(`zoom_at()` panning without recomputing `_origin`, stale on the next
`_unpix`), fixed before landing.

O3 (`dc4c7a3`) — `core/world_ai.gd`: `WorldAI.patrol/wander/hunt` assign a
party's goal-producing behavior; `WorldAI.update(world, delta)` drives all
of them, called from `_process` next to `world.tick()`. Monster/civilized
split: `CIVILIZED := ["soldier"]`, everything else in `Scaler.FACTIONS`
hunts; hostility is one-directional for now (monsters hunt civilized
parties/settlements/the player, civilized parties never hunt each other) —
defend/flee behaviors are a later addition, not built yet. AI state lives
on `RoamingParty.ai` (one additive field on O1's class), not a side table,
so O5 can remove dead parties without separate cleanup. `tests/
test_world_ai.gd`: 35 passed.

Full suite: 26 test files, 0 failures; all 5 `drive_*` smoke tests
(including the new `drive_world`) OK.

**O4 completion (2026-09-11):** all in `scenes/world/world.gd` — `scenes/main.gd`
and `core/*` untouched. `ENCOUNTER_RADIUS := 24.0` world units: a party token is
~6 world units of radius after ISO_GAIN, so 24 is "the tokens visibly overlap",
and it is wider than one tick's closing distance (two parties at `World.SPEED`
close 8 units per 0.1s step), so nothing tunnels through the trigger. `_process`
now also calls `WorldAI.update()` (O3 shipped it unwired) and `_check_encounter()`.
The hand-off copies `scenes/campaign/campaign.gd`'s `_launch_combat()` exactly:
full-rect overlay, instantiate `main.tscn`, set `.party`/`.spec`/`.difficulty`,
await `.result`, tear down. Roster: `encounter_spec()` maps the encountered
party's faction to a `Scaler.roster_for()` call — `THEME_FACTION` reversed gives
a matching board for the five factions that have one, and for the rest
(soldier/orc/cultist/kobold/gnoll/...) the seed is snapped so
`FACTIONS[seed % size]` lands on that faction, with `DEFAULT_THEME =
forest-clearing` as the board. Verified: cultist/orc/kobold/gnoll specs come back
all-in-faction. Player roster is the same `Party.demo_roster()` fallback
campaign.gd uses, overridable via an injected `party` field (O8 will inject the
real one). Difficulty is fixed `"normal"` — no per-encounter scaling yet.
Victory `world.parties.erase(foe)`; anything else retreats the player to the
nearest settlement and resumes, deliberately with no losses/gold/wound state —
defeat consequences belong to O7 once faction opinion exists. `tests/
drive_world.gd` extended (proximity triggers a real `main.tscn` with a live
`Combat` and 5 foes, map frozen during the fight, winning removes the party,
clock resumes, player marches again). Full suite: 26 test files, 0 failures; all
6 `drive_*` OK.

**O5 completion (2026-09-11):** new `core/world_battle.gd` (~100 lines) plus two
lines in `scenes/world/world.gd`'s `_process`; O4's trigger, `core/world_ai.gd`,
`core/campaign.gd` and `scenes/main.gd` untouched. It lives in `core/` and not in
the map scene because none of it is rendering — it is exactly `test_scaler.gd`'s
`_sweep` loop (`Encounter.build`, `begin_turn`/`AI.take_turn`/`end_turn` to
`is_over()`, `outcome()`), so it is testable without a `Control`. The one thing it
does not own is the faction→roster mapping: O4's `encounter_spec()` comes in as a
`Callable` (`WorldBattle.check(world, ENCOUNTER_RADIUS, encounter_spec)`) rather
than being re-derived, so both sides of an NPC fight roll the same rosters a
player ambush would. `Encounter.build()` only builds the foe side, so side A is
spawned as `"party"`-team combatants on the board's first free hexes (reusing
`Encounter._foe_spots(board, [])`) and `build()` then places side B at least
`SPAWN_GAP` away from them, on the attacker's theme board; a `Victory` is side A's
win. Seed is `hash("a.id|b.id")`, so the same two bands always resolve the same
way. A fight that runs out combat.gd's `MAX_ROUNDS` ("ongoing") is decided on
survivors, then on remaining HP — never a coin flip. The loser is removed from
`world.parties` outright and the winner walks away untouched: no wound/scale
carry-over, deliberately (O7 owns persistent consequences). Hostility is checked
both directions (`world_ai.gd`'s is one-directional), the scan is O(n²) over 3-8
parties once a frame per O1's "no index yet" note, and player-involved pairs are
skipped entirely so O4's trigger still owns them. `tests/test_world_battle.gd`:
16 passed (one survivor removed, deterministic per seed, civilized-vs-civilized
peace, a mixed scene where the player's ambusher is left for O4, out-of-radius
peace). `tests/drive_world.gd` extended with the live case (two NPC bands close
on the map, one dies, no combat scene, clock never pauses). Full suite: 28 test
files, 0 failures; all 6 `drive_*` OK.

**O6 completion (2026-09-11):** new `core/settlement_visit.gd` (~170 lines, the
economy + theft, headless) plus a visit trigger and panel in `scenes/world/
world.gd`; `core/campaign.gd`, `scenes/campaign/*`, `core/world_ai.gd`,
`core/world_battle.gd` and `scenes/main.gd` untouched. `core/world.gd`'s
`Settlement` gained three additive fields: `last_visited`/`battle_at` (world-clock
stamps, < 0 = never) and `pending_opinion_delta`.
- **Visit radius**: its own `VISIT_RADIUS := 34.0`, not O4's `ENCOUNTER_RADIUS` —
  a settlement is a fixed landmark drawn at ~26 world units, not a 6-unit token,
  so "in through the gate" is a wider circle than "tokens overlap". `_check_visit()`
  sits next to `_check_encounter()` in `_process` and is the same linear scan; a
  `_left` guard stops the panel reopening the frame after Leave and clears once
  the party is outside the radius again.
- **Economy**: `market(settlement, gap, battle)` is pure and seeded on
  `hash("id|steps|battle")`. `steps = clamp(gap / RESTOCK(60 world-min), 0, 6)`;
  the shelf is `0.25 + 0.75 * steps/6` of T25's catalog for that settlement
  (`node_services`/`shop_ids` via a synthetic merchant node — no new catalog),
  and a thin shelf is a dear one: `markup = 1 + 0.6 * (1 - steps/6)`, so a full
  restock sells at list price. `visit()` reads the gap off the clock and then
  stamps `last_visited`, so walking straight back in finds the shelf as it was
  left. Sell price is `item_price * SELL_RATE * markup` — the same swing.
- **Battle flag**: `SettlementVisit.mark_battle(world, at, now)` stamps
  `battle_at` on every settlement within `BATTLE_RADIUS := 140.0` of a fight.
  Fed from the one place O5 already returns its results — `world.gd`'s `_process`
  now consumes `WorldBattle.check()`'s return value instead of discarding it; O5's
  own logic is unchanged. A visit inside `BATTLE_WINDOW := 240.0` world-minutes
  halves the shelf again and marks it up x1.4. Not an event log: one timestamp.
- **Stealing**: `steal()` is `opportunity_check()`'s shape — `Dice.d20` + the
  party's best `sleightofhand` (via a throwaway `Campaign` instance for
  `best_at`/`skill_bonus`, which is also how the catalog is reached; `ponytail:`
  noted — make those static the day campaign.gd is in scope) vs `STEAL_DC := 15`,
  narrated the same way. Success takes 5% of the shelf's list value as gold,
  clamped 25-250. Seeded off `"steal|id|hour"` unless an rng is passed.
- **O7 hook**: `Settlement.pending_opinion_delta: float`. Every attempt adds to it
  (`OPINION_STEAL_SUCCESS = -5.0`, `OPINION_STEAL_CAUGHT = -10.0` — both, per the
  phase's own call), keyed by `settlement.faction` when O7 drains and zeroes it.
  O6 never reads it back, so O7 plugs in without touching this phase.
`tests/test_settlement_visit.gd`: 30 passed (determinism, gap, second-visit-vs-
much-later, the battle flag and its locality/ageing, buy/sell, seeded theft and
the hook firing on both branches). `tests/drive_world.gd` extended with the live
case (walking in opens the panel and pauses the clock, buy moves gold/stash and
clears the shelf slot, theft narrates and queues the delta, Leave closes/resumes
and does not reopen on the spot, coming back reopens). Its O4 case moved out to
open country — standing on `(0,0)` is standing in Riverhold now. Full suite: 29
test files, 0 failures; all 6 `drive_*` OK.

**O7 completion (2026-09-11):** new `core/faction_opinion.gd` (~115 lines) plus
small hooks in `core/world_ai.gd`, `core/settlement_visit.gd`, `core/quest.gd`,
`core/world.gd` (`tick()` now returns the world-time it advanced) and
`scenes/world/world.gd`; `core/campaign.gd`, `scenes/campaign/*`,
`scenes/main.gd` and `core/world_battle.gd` untouched.
- **Scale**: one float per faction, -100..100, 0 = neutral/unknown, held in a
  `static var` dictionary — the two hot readers (`WorldAI.is_hostile`,
  `SettlementVisit.market`) are static functions reached from places with no
  handle on the `World`, and there is one live world at a time (`ponytail:`
  noted, hang it on `World` the day two coexist). `reset()` for tests/new game.
- **Thresholds**: `QUEST_MIN -25` (no work for you) < `HOSTILE -50` (guards and
  roaming parties attack) < `REFUSE_TRADE -75` (nobody sells to you), and
  `QUEST_GENEROUS +40`. Spaced so one theft (O6's -5/-10) is noise and a run of
  them — or a fight with the faction's own bands (-8 each) — is what walks the
  score past them. Decay is `2.0`/world-day via `move_toward(0)`, so the worst
  standing heals in ~50 days of leaving them alone; factions already at 0 are
  skipped entirely.
- **Effects**: prices are `markup *= 1 - 0.4 * opinion/100` (x1.4 at -100, x0.6
  at +100) on top of O6's scarcity markup, sell price follows, and at/below
  `REFUSE_TRADE` `market()` returns an empty shelf with `refused: true`;
  `Quest.offer_for(party, node_id, opinion := 0.0)` offers nothing below
  `QUEST_MIN` and hands over another giver's job above `QUEST_GENEROUS` (the
  default keeps T9/the linear campaign byte-identical); `WorldAI.is_hostile()`
  makes a *civilized* party hostile to the player (and only the player) below
  `HOSTILE` — the monster rule is untouched; `_check_visit()` below `HOSTILE`
  launches O4's `_launch_combat()` with a synthetic `"<id>-guard"` garrison
  party instead of opening the market (not on the map, so beating it just ends
  the fight — no second combat path).
- **Raise/lower sites**: `Quest.turn_in(party, quest, faction := "")` raises
  +10; `scenes/world/world.gd`'s O4 victory calls `credit_fight()` (+5 to every
  civilized faction with a settlement inside 140 units of the bodies, never the
  dead band's own faction) for a monster kill, and `lower(+8)` on the faction
  whose own band the player just wiped out. `FactionOpinion.tick(world,
  world.tick(delta))` in `_process` drains O6's `pending_opinion_delta` per
  settlement into its faction and then decays — a paused clock does neither.
- **Persistence**: skipped. Nothing persists world state yet (`campaign_save.gd`
  is the linear campaign's); `all()`/`set_opinion()` are the whole surface a
  future world save needs.
`tests/test_faction_opinion.gd`: 23 passed (raise/lower/clamp, decay drifting
and stopping dead at 0, neutral factions untouched, the drain being per-faction
and one-shot, `credit_fight` locality). Effect tests live with the systems they
change: `test_settlement_visit` 38, `test_quest` 463, `test_world_ai` 43.
`tests/drive_world.gd` extended with the live hostile-settlement case. Full
suite: 30 test files, 0 failures; all 6 `drive_*` OK.

**O8 completion (2026-09-11):** `scenes/game/game.gd` only — `scenes/world/world.gd`,
`core/campaign.gd`, `scenes/campaign/*` and every `core/world*` file untouched.
- **The flow**: no new screen and no new button on the normal path. "New run →
  party setup → Begin the run" is unchanged; only its destination moved, from
  `_show_campaign(Campaign.new(...))` to a new `show_world(party)` that
  instantiates `scenes/world/world.tscn`, sets `.party`, and `_swap`s it in.
  Fewest moving parts: the player sees exactly the same two clicks they always did.
- **The gate**: `Game.linear_campaign()` = `OS.get_environment("SORCMERC_LINEAR_CAMPAIGN") != ""`,
  read live per press so a test can flip it mid-run. Set, Begin routes to the
  linear campaign exactly as before (same seed plumbing). The title's "Resume the
  last run" is gated on the same flag, because the autosave *is* a linear-run
  artifact (`campaign_save.gd`) and nothing in the open world writes one — leaving
  it ungated would have left a normal player one leftover save away from the
  linear route. No debug-only extra button was added; the existing Begin does both.
- **Real starting world**: world.gd's own `_demo_world()` layout (Riverhold/
  Greenmarch/Dun-Arrow/Ashfell, a player token, bandits, goblins, a patrol). Per
  this phase's scope it is the mode switch, not content generation; the one real
  injection is the player's assembled `Party`, which replaces world.gd's
  `Party.demo_roster()` fallback — so encounters, the market and theft all run on
  the characters out of the barracks.
`tests/drive_game.gd` rewalked: default press-through now asserts the open world
(same `Party` object as the party screen assembled, the created character in it,
a live map), that the linear campaign is *not* reached, and that a planted
autosave shows no Resume with the flag unset; then it sets the flag, walks the
same buttons again and gets the campaign map, retire, summary and Resume. Its
`SORCMERC_LINEAR_CAMPAIGN` is set via `OS.set_environment`, next to the
`SORCMERC_FAST` it already set. `tests/test_game_flow.gd` adds the two-way switch
check (51 passed). Full suite: 30 test files, 0 failures; all 6 `drive_*` OK,
including `drive_campaign` (which drives `campaign.tscn` directly and so never
needed the flag).

## O9 — open-world bug/gap fix pass (locked 2026-09-11, dispatched now)

A full review of O1-O8 (merge-reviewer, 2026-09-11) surfaced nine real
issues — the seams between 8 separately-dispatched phases, none caught
individually since each phase only reads a summary of the others. Fix all
nine:

1. **Unlimited gold via repeat-Steal** (`scenes/world/world.gd`'s
   `_steal()`/`core/settlement_visit.gd`). The clock is paused for the
   whole visit, so `elapsed` (the steal RNG's seed input) never changes —
   every press of Steal rolls the identical result. Add a one-shot guard:
   once `_visit` has been stolen from, further presses are refused (and
   the button should read as spent/disabled), same visit until Leave.
2. **The run is a dead end** (`scenes/world/world.gd`'s `_launch_combat()`,
   `scenes/game/game.gd`'s `show_world()`). Victory currently discards
   `result["xp"]`/`result["gold"]`; there is no Rest action anywhere in
   the visit panel; there is no way back to the title screen; nothing
   calls `CharacterSave.save()` outside the linear campaign's summary.
   Fix: award XP/gold on victory (reuse whatever split logic
   `core/campaign.gd`'s `finish_combat()` already uses rather than
   reinventing it), add a Rest option to the settlement-visit panel
   (reuse `Campaign.rest("long-rest")`'s mechanics if that's callable
   without a full `Campaign` instance, otherwise the smallest equivalent),
   and add a Title/exit control that saves every roster member via
   `CharacterSave.save()` before leaving (and calls
   `FactionOpinion.reset()` — see item 9's note on why that matters once
   an exit exists).
3. **Encounter trigger breaks at high time-speed**
   (`scenes/world/world.gd`'s `ENCOUNTER_RADIUS`/`_check_encounter()`).
   At 4x/8x a hunting party's per-tick movement can outrun the fixed
   24-unit trigger radius, so pursuit never actually catches the player
   (confirmed: gap locks at 32 units and stays there). Scale the
   effective trigger distance with the tick's actual travel distance
   (e.g. compare against `maxf(ENCOUNTER_RADIUS, p.speed * dt * 2.0)`
   using the dt `world.tick()` returns) rather than a fixed constant, and
   fix the same stale reasoning in `VISIT_RADIUS`'s comment.
4. **Quests are unreachable** (`core/settlement_visit.gd`/
   `scenes/world/world.gd`'s visit panel). O7 built `Quest.offer_for()`/
   `turn_in()` for exactly this, but nothing in the open world calls
   either — the plan's primary positive-opinion source (completed
   quests) can never fire in normal play. Add an Offer/Turn-in row to
   the settlement-visit panel using those two functions as they already
   exist; do not redesign the quest system itself.
5. **`REFUSE_TRADE` unreachable** (`scenes/world/world.gd`'s
   `_check_visit()`). The hostile-guard-fight gate at `HOSTILE` (-50)
   intercepts and returns before opinion can ever reach `REFUSE_TRADE`
   (-75), so `market()`'s refusal branch is dead code in practice. Give
   the settlement-hostility check its own threshold distinct from (and
   lower than) trade refusal, so both are reachable.
6. **A monster-faction settlement trades peacefully with the player**
   (`scenes/world/world.gd`'s `_check_visit()`). It gates only on
   `FactionOpinion.is_hostile_to_player()`, never on
   `WorldAI.is_monster()`, so the demo map's cultist city (Ashfell) runs
   a friendly market while its own roaming cultist parties attack on
   sight. Gate visits the same way `_check_encounter()` already gates
   combat: `WorldAI.is_monster(s.faction) or FactionOpinion.is_hostile_to_player(s.faction)`.
7. **Pause button desyncs during a settlement visit**
   (`scenes/world/world.gd`'s `_open_visit()`). It pauses the clock but
   never updates `_pause_btn.text`, so the button reads "Pause" while
   already paused; pressing it then resumes the world (parties move,
   NPC battles resolve) underneath the still-open market panel. Set the
   label correctly in `_open_visit()`, or simplest: gate
   `_toggle_pause()`/`_cycle_speed()` on `_visit.is_empty()` so neither
   does anything while a visit panel is open.
8. **`credit_fight` isn't actually civilized-only**
   (`core/faction_opinion.gd`). Its own comment and O7's completion note
   both say "every civilized faction with a settlement nearby", but the
   loop never checks `WorldAI.is_monster()` — killing a goblin band near
   a cultist city currently raises cultist opinion. Add the filter. Also
   cut the unused `radius` parameter (one call site, always the default)
   and the docstring's unused negative-amount example (the real "killing
   a faction's people" path already goes through `lower()` directly at
   its one call site).
9. **World-time unit confusion** (`core/world.gd`'s `elapsed`/`SPEED`
   comments, `tests/test_world.gd`'s matching test label). O1 documents
   `elapsed` as world-*seconds* and asserts "ten 0.1s ticks are one
   world-second" — every phase after it (the HUD's Day/HH:MM readout,
   O6's `RESTOCK`, O7's `DAY := 1440.0`) actually treats it as
   world-*minutes*. Nothing computes wrong today (it's self-consistent
   downstream), but it's a 60x trap for the next constant tuned off
   `world.gd`'s own comments. Fix the two O1 comments and the test
   label to say minutes, matching what's actually been built on top.

Also, lower priority, note-only unless there's time: `World.set_goal()`
is bypassed by `core/world_ai.gd` everywhere in favor of direct
`p.goal = goal` — pick one convention and use it consistently, cheap
cleanup, not worth its own item if it doesn't fit.

File ownership: `scenes/world/world.gd`, `core/settlement_visit.gd`,
`core/world.gd` (comments only, item 9), `core/faction_opinion.gd`, and
their test files. Do not touch `core/campaign.gd`, `scenes/campaign/*`,
`scenes/main.gd`, `core/world_ai.gd`'s hostility logic beyond what item 6
needs, or `core/quest.gd` beyond calling its existing functions (item 4).
Full suite + all `drive_*` smoke tests green before reporting done.

**O9 completion (2026-09-11):** landed as `f34ddb9`. All nine items fixed,
each confirmed at its real location before changing it (the review's line
numbers were accurate). Notably: item 2 turned out worse than reported —
`_launch_combat()` was discarding `kills` too, so quests could never
progress even once reachable; fixed by a `_bank(result)` that reuses
`Campaign._split_xp()` for XP and calls `Quest.record_kills` directly.
Item 4 hit an undocumented snag — `Quest.offer_for()` keys on T25 giver
*node ids*, which settlements don't have — worked around with a new
`giver_node_id()` helper in `core/settlement_visit.gd` rather than
reshaping the quest system. Item 1/3 fixes were verified negatively too
(reverting either reproduces the exact failure the review described).
Full suite: 30 files, 0 failures. All 6 `drive_*` OK (verified with
`SORCMERC_SEED=7` — `drive_campaign` is separately known to be flaky
*unseeded*, pre-existing, unrelated to this pass).

## O10 — asset spike: real art for the overworld map (locked 2026-09-11, dispatched now)

Research-only, same shape as the earlier isometric-view art spikes (the
`feature/isometric-sprite-assets` branch, still live and unmerged, found
CC0 "Tiny Tactics — Battle Kit I" on OpenGameArt for combat). The
overworld map currently reuses `scenes/world/world.gd`'s vector-drawn
projection — functional, not visually rich. Find real, license-clear
assets that would make settlements, roaming-party tokens, and open
terrain read better at the overworld's zoomed-out scale specifically
(distinct from combat-board asset needs — a settlement needs to read as
a landmark from far away, a roaming party as a small silhouette, not a
detailed close-up token).

Scope: search itch.io asset packs, OpenGameArt, Kenney.nl, and similar
CC0/CC-BY marketplaces for isometric or top-down city/town/settlement
sprites (several distinct looks — city vs. town vs. faction-flavored
outposts), small party/caravan tokens (readable at a distance, distinct
per faction), and open-terrain/ground tile sets matching a temperate
fantasy setting. For each candidate: confirm the actual license
(CC0/public-domain preferred; CC-BY is fine if attribution is trivial to
carry; reject anything requiring a paid license or with an ambiguous
grant), note asset count/resolution/style, and a direct link.

Direct user note: the world's ground tiles specifically need more polish
than settlements/parties do — `scenes/world/world.gd`'s ground is
currently a tessellating grid of flat projected quads with hashed
tint/mottle noise (O2's own description), which reads as plain at the
overworld's zoomed-out scale. Weight the search accordingly: prioritize
finding real ground/terrain tile sets (grass, dirt roads, forest edges,
water) over settlement/party assets if trade-offs are needed, and call
out in the report which candidates specifically solve the flat-ground
problem vs. which are "nice to have" on top of it.

This is research and reporting only — no assets downloaded into the repo,
no code changes, no branch. Report a shortlist (3-5 real candidates) with
license confirmation for each, plus a recommendation, back to the user;
the user decides what (if anything) gets integrated next, same as how the
combat-board sprite spike was handled.

**O10 completion (2026-09-11):** research delivered, nothing integrated
(as scoped — this was reporting-only). Five CC0 candidates found, all
license-confirmed directly on their asset pages:
1. Screaming Brain Studios — **Isometric Tiles: Overworld Pack**
   (itch.io/screamingbrainstudios), 360 tiles (grass/forest/water,
   flat+thick renders) — the recommended lead: built specifically for an
   overworld, not combat or generic top-down.
2. Screaming Brain Studios — **Isometric Tiles: Town Pack**, 443 tiles,
   same author/grid/style as #1 — settlements, no style-mismatch risk.
3. Kenney — **Isometric Roads**, 95 files CC0 — fills the road-tile gap
   #1 doesn't cover.
4. Kenney — **Isometric Tiles Landscape**, 128 tiles CC0 — an older,
   flatter-style alternative/backup to #1.
5. Kenney — **Board Game Icons** (or the sibling **Board Game Pack**) for
   party/caravan tokens — CC0 confirmed, but whether either actually
   contains simple colorable pawn shapes vs. just dice/card iconography
   was NOT confirmed from the page alone; flagged as needing a direct
   look at the downloaded sheet before committing.

Recommendation: lead with #1 + #2 (same author, same grid, eliminates
mismatch risk) plus #3 for roads. #5 is the open item — a five-minute
visual check, not a licensing risk. Awaiting user decision on what (if
anything) to integrate; no branch, no download yet.

## O11 — integrate the Overworld + Town packs (locked 2026-09-11, dispatched now)

User approved O10's #1+#2 recommendation ("do 1-2 if licensing is
available"). Re-verified directly against both itch.io pages before
dispatch: both **confirmed CC0** ("released under the Public Domain
(CC0) license... free to use however you like in any project, commercial
or non-commercial"), both **free to download** ("name your own price",
$0 accepted, no purchase required).

- Screaming Brain Studios — **Isometric Tiles: Overworld Pack**
  (screamingbrainstudios.itch.io/iso-overworld-pack) — 360 tiles,
  grass/forest/water, flat+thick renders. Replaces
  `scenes/world/world.gd`'s procedural hashed-tint ground quads.
- Screaming Brain Studios — **Isometric Tiles: Town Pack**
  (screamingbrainstudios.itch.io/iso-town-pack) — 443 tiles (432
  building + 11 roof), same author/grid/style as the Overworld Pack, no
  style mismatch. Replaces the plain settlement-landmark blobs.

Same pattern as the combat board's own art spike
(`feature/isometric-sprite-assets`): build this on its **own branch**,
not master directly, so the actual in-game look can be reviewed before
merging. Downloading itch.io "name your own price" assets programmatically
may hit an auth/session wall the agent can't clear headless — if so, stop
and report back rather than guessing at a workaround; the user can
download manually and hand the files over.

Scope: download both packs into the branch (with their license file/
attribution note kept, even though CC0 needs none, as a paper trail),
wire them into `scenes/world/world.gd`'s ground/settlement rendering in
place of the current procedural quads/blobs, keep the existing
projection math (`ISO_YAW`/`ISO_SQUASH`/`ISO_GAIN`) so it still lines up
with the camera/click-to-move math already tuned against it. Party tokens
stay as they are (O10's #5 token question is unresolved, out of scope
here). Full suite + `drive_world` must stay green — a visual change
should not break the headless logic tests, which don't inspect pixels.

## O12 — swap Town Pack buildings for medieval art + denser ground tiles (locked 2026-09-11, dispatched now)

Direct user feedback on O11's actual rendered result (screenshotted and
reviewed): the Town Pack's buildings read as a modern city (brick
rowhouses, plate-glass), not a fantasy-medieval setting — "too modern."
Separately: the ground tiles should be smaller/denser for a higher-
quality look at the current camera distance.

**Building swap — researched and license-verified 2026-09-11:**
[rubberduck's isometric medieval building series](https://opengameart.org/content/isometric-medieval-buildings)
(part 1, 2 buildings) +
[part 2](https://opengameart.org/content/isometric-medieval-buildings-2)
(3 more) — both CC0 confirmed directly on their pages, hand-painted
digital isometric art (not pixel-art tofu), **128x64 tile format**
(matches the Town Pack's own `BUILDING` tile size already wired into
`_draw_building()`, so the slicing math mostly carries over), each
building shipped with sun/cloudy/no-shadow renders and a snowy variant —
5 distinct medieval building designs total across both packs, same
author/style/quality, no mismatch risk. This replaces
`assets/world/town/buildings.png` (the modern Town Pack) — remove it and
its License.txt, replace with the new pack's files under
`assets/world/town/`, update `assets/world/README.md`'s paper trail.
Rework `_draw_building()`'s tile-picking only as much as the new sheet
layout requires (read the actual downloaded files before assuming the
old `BUILDING_STYLES`/`BUILDING_PAIRS`/slicing constants still apply —
they were sized for the old sheet's 216-type grid, this pack is a
handful of standalone building sprites, not a grid to index into).

**Ground tile density:** `scenes/world/world.gd`'s `CELL := 90.0` (world
units per tile) reads coarse at the default camera distance. Lower it
(try something in the 45-60 range — pick empirically by rendering
`tests/shot_world.gd` and judging the result, don't guess a number and
ship it blind) so more, smaller tiles fill the same view for a denser,
higher-quality look. This roughly quadruples the cell count in the same
viewport at half the CELL size, so `MAX_CELLS` (currently 900, the
far-zoom fallback threshold) needs raising to match — recompute what a
reasonable default-zoom view actually needs (O11's own math: ~255 cells
at `CELL=90`, `_zoom=1.0`) and set `MAX_CELLS` so the fallback still only
triggers when meaningfully zoomed out, not at the new default.

Same branch as O11 (`feature/overworld-art-packs`), same worktree if
still live — this is a direct continuation, not a fresh spike. Re-render
`tests/shot_world.gd` (non-headless: `godot --path . -s tests/
shot_world.gd`, headless mode hangs on the viewport-texture capture here)
at default zoom and at least one zoomed-in level, actually look at the
PNG before calling this done. Full suite + drive_world green. Push the
branch again; still not merged to master without explicit sign-off.

**O12 completion (2026-09-11):** landed as `ec33343` on
`feature/overworld-art-packs` (pushed, still not merged to master —
awaiting sign-off). Rubberduck's two CC0 packs (5 buildings, sun-shadow
variant picked to match the existing fixed `LIGHT` constant; snowy
variant skipped — no season state exists to switch it on) replace the
Town Pack entirely; `_draw_building()` rewritten for standalone sprites
instead of a 216-type grid, `_draw_settlement()`'s faction-ring/city-vs-
town logic kept, only its sprite-scale multiplier changed (a whole house
needs a bigger multiplier than a wall segment did). `CELL` 90→50,
`MAX_CELLS` 900→2850 (computed from the same viewport-cell-count model
O11 used, not guessed). Verified visually, not just by test count: I
personally re-rendered `tests/shot_world.gd` (non-headless — headless
hangs on this specific viewport-texture capture here) at default and 2.5x
zoom and inspected the PNGs myself — the earlier O11 result read as a
modern brick rowhouse; this one reads as an actual half-timbered,
shingle-roofed medieval house cluster, and the ground is visibly denser/
higher-resolution at default zoom. Full suite (30 files) + all 6
`drive_*` green. One cosmetic nit left alone: the house cluster sits
toward the back half of the faction ring rather than centered (the
sprites rise up-and-left from their ground-corner anchor) — not worth
its own pass yet.

**Follow-up fix (2026-09-11):** the ring-centering nit above, fixed
directly (`5d8260c` on `feature/overworld-art-packs`). `BUILDING_ANCHOR`
sits near the sprite's bottom, so a house drawn at its footprint point
reads as mostly rising above it; nudged every base down by a fraction of
the anchor-to-vertical-centre gap. The correction was tuned empirically
against real renders — a full correction overshot the house below the
ring, 0.3 of it reads centered — not derived by formula, since "looks
centered" is a visual call. Full suite + all `drive_*` green.

## O13 — world persistence (locked 2026-09-11, dispatched now)

Leaving the open world (`scenes/world/world.gd`'s `_leave_world()`) today
saves only the roster (`CharacterSave.save()` per member) and resets
`FactionOpinion`. Party position, roaming parties, settlement visit
state (`last_visited`/`battle_at`), and faction opinion all vanish —
resuming means starting the world over. Give it a real save, same
overall shape as `core/campaign_save.gd` (JSON to disk, a `has_save()`/
`load_latest()`/`clear()` surface, autosave on meaningful events rather
than only on exit so a crash doesn't lose everything).

New `core/world_save.gd`: serialize `World` (settlements incl.
`last_visited`/`battle_at`/`pending_opinion_delta`, parties incl.
position/faction/`ai` state, `clock.elapsed`) and `FactionOpinion.all()`
into one save file. `scenes/game/game.gd` gets a "Resume the open world"
option on the title screen (parallel to the existing linear-campaign
Resume, which stays gated on `SORCMERC_LINEAR_CAMPAIGN` — this one is
for normal play) that reconstructs the `World` and re-applies opinion
before showing `world.tscn`. `_leave_world()` still saves the roster the
same way; add the world save alongside it, and autosave periodically
(e.g. on every settlement visit close and every combat resolution —
reuse existing event hooks, don't add a timer/poll).

File ownership: new `core/world_save.gd`, `scenes/game/game.gd`,
`scenes/world/world.gd`'s `_ready()`/`_leave_world()` only (do not touch
its drawing code). Add `tests/test_world_save.gd` (seeded, headless —
round-trip a `World` + opinion through save/load, verify every field
survives). Extend `tests/drive_game.gd`/`tests/drive_world.gd` for the
live Resume path. Full suite + all `drive_*` green.

## O14 — real party/caravan token art (locked 2026-09-11, dispatched now)

O10 flagged Kenney's Board Game Icons / Board Game Pack (both CC0,
confirmed) as an open item: unverified whether either sheet actually
contains simple colorable pawn shapes vs. just dice/card iconography.
Resolve that first — download both, look at the actual sheets. If
neither has usable pawn/token art, search further (same CC0/CC-BY bar as
every prior asset spike) rather than forcing a bad fit; report back and
stop if nothing suitable turns up, don't fabricate placeholder art.

If a usable set exists: replace `scenes/world/world.gd`'s `_draw_party()`
(currently a procedural flat-base + shaded-ball circle, faction-tinted)
with real sprite art, keeping faction color variation (tint the sprite,
or pick a sheet variant per faction if the pack has color options) and
the existing gold ring that marks the player specifically. Party tokens
are small/distant by design (read as a silhouette, not a detailed
figure) — don't pick art that only reads at combat-token scale.

File ownership: `scenes/world/world.gd`'s `_draw_party()` only, plus new
`assets/world/tokens/` art + license file. Re-render `tests/
shot_world.gd` and actually look at it before calling this done, same
discipline as O11/O12. Full suite + `drive_world` green.

## O15 — minimal terrain/coastline so water tiles have somewhere to go (locked 2026-09-11, dispatched now)

O11 deliberately left the Overworld Pack's water tiles unused: ground
cells are picked by hash with no terrain data behind them, so scattering
water would be nonsense — there was nothing for a coastline to be a
coastline *of*. Scope the smallest fix, not a full biome/terrain-
generation system: add a handful of fixed water *regions* (e.g. 1-2 lake
or river shapes, as a list of world-space points/polylines or simple
circles in `core/world.gd`'s `World`, hand-placed in `_demo_world()`
the same way settlements are), and have `scenes/world/world.gd`'s
`_draw_ground()` pick water tiles for cells within some distance of a
region, forest/grass as it already does elsewhere (blend at the edge
via the existing wooded-threshold pattern rather than a hard cutoff).

File ownership: `core/world.gd` (additive: a `WaterRegion` shape or
reuse a plain `Vector2`+radius list, whatever's least new surface),
`scenes/world/world.gd`'s `_draw_ground()` and `_demo_world()` only.
Extend `tests/test_world.gd` if `core/world.gd` gains a real new shape;
re-render `tests/shot_world.gd` and look at it. Full suite +
`drive_world` green. This lands after O13/O14 land (or is at least
rebased on top) since all three touch `scenes/world/world.gd` — check
current master before starting, don't fork stale.

## O16 — per-building footprint sizing (locked 2026-09-11, dispatched now)

O12 flagged this as a known simplification: `_draw_settlement()` scales
every building in a cluster by the same `r * (3.2 if big else 2.8)`
multiplier off the settlement's ring radius, not the building sprite's
own real footprint. Give each of the 5 medieval buildings (see
`tools/pack_buildings.py`'s sheet layout, already built by O12) its own
footprint size read from the source art (or a small hand-tuned per-
building scale table, whichever is less code) so a market shed and a
manor house read as different sizes, not just different skins at the
same scale.

File ownership: `scenes/world/world.gd`'s `_draw_settlement()`/
`_draw_building()` only. Re-render `tests/shot_world.gd`, look at it.
Full suite + `drive_world` green. Land after O13/O14/O15 (same file,
check master before starting).

## T43 — root-cause drive_campaign's unseeded flakiness (locked 2026-09-11, dispatched now)

Confirmed pre-existing across T34/T38/T40/T41's own investigations —
`tests/drive_campaign.gd` occasionally loses when run without
`SORCMERC_SEED` pinned, and it's never actually been root-caused, only
repeatedly waved through as "pre-existing, seeded runs are fine." Chase
it properly this time: run the driver across a range of unseeded/random
seeds, find one that reproduces the loss, and determine whether it's the
driver itself (T41 already found and fixed one real driver bug — a
hand-rolled fighter with no spells/heals — there may be a second one) or
a genuine campaign-balance issue (the stage-0 combat being unwinnable at
some seed/roll combination). Fix the actual cause; if it turns out to be
inherent variance (a bad-luck seed genuinely can lose a difficulty-tuned
fight, which is by design — see T23/T38/T40's calibrated win rates),
say so plainly and adjust the driver/test to tolerate it (e.g. retry
once, or assert on a distribution across N seeds rather than a single
run) rather than pretending it's 100% deterministic when the underlying
combat isn't.

File ownership: `tests/drive_campaign.gd`, and `core/campaign.gd`/
`core/ai.gd` only if the root cause is a genuine engine bug (unlikely,
per T41's finding that the campaign flow itself was fine — verify before
touching either). Full suite + all `drive_*` green.

**T43 completion (2026-09-11):** landed as `35ab371`. Root cause was a
second `tests/drive_campaign.gd` driver bug (T41 fixed the first), not
the engine: the road picker fell back to `pick = 0` on stage 0 (combat-
only since T12), always taking the *first* listed fight regardless of
difficulty — reproduced on seeds 29/44, where it walked into the harder
of two available rosters every time. Fixed by ranking combat roads by
difficulty (easiest first when no non-combat option exists) and, since
some residual loss is genuine calibrated variance (T40's own targets:
94.5% easy, 83.5% normal — not 100%), the driver now retries up to 3
attempts rather than asserting a single run must always fully succeed.
Verified across seeds 1–60 plus unseeded runs (65/65), and again
independently on 6 more unseeded runs post-verification. `core/campaign.gd`/
`core/ai.gd` confirmed untouched — T41's "the flow itself is fine"
conclusion still holds. Full suite green.

**O13 completion (2026-09-11):** landed as `91f49be` + `29729f6`. The
flakiness I caught was real but NOT the autosave hook itself — root-
caused to concurrent `godot` processes on this box sharing one
`user://` save directory (a second process's `drive_campaign` run
clobbering `campaign.json` mid-assertion in a concurrently-running
`drive_game`), confirmed by an A/B: pre- and post-O13 drivers failed at
the same rate under a concurrent load, so this predates O13 and equally
affects T43's own driver. Fixed anyway to the better shape regardless:
autosave moved from a generic `child_exiting_tree` signal (a deferred-
free timing window) to three synchronous calls at the actual events
(`_close_visit()`, `_launch_combat()`, `_leave_world()`) — "the world is
saved" is now true at a defined instant, not eventually. Also fixed a
real nondeterminism the agent's own first pass introduced:
`drive_game.gd`'s resumed map was left mounted and ticking for the rest
of the walk, letting a roaming hunt open combat mid-assertion. Verified
myself: 10/10 `drive_game`, 8/8 `drive_world`, full suite, all other
`drive_*`, nothing else running concurrently. **Flagged, not fixed**:
an env-overridable save directory in `campaign_save.gd`/`world_save.gd`
would eliminate this whole class of cross-process test flakiness for
good — worth doing given how many concurrent background agents this
project runs tests under; scoped separately below as O17 rather than
folded into O13's own diff.

## O17 — per-process test save directories (locked 2026-09-11, dispatched now)

Flagged by O13: `core/campaign_save.gd` and `core/world_save.gd` both
write to a fixed `user://autosave/...` path, which every concurrently-
running `godot` process on the same machine shares — two test runs (or a
test run and manual play) in flight at once can clobber each other's
save file mid-assertion. This session runs many background agents in
parallel, each spawning its own `godot --headless` processes, so this is
a real, recurring source of false test failures (already implicated in
both O13's and T43's flakiness hunts), not a hypothetical.

Fix: make the save directory env-overridable (e.g.
`SORCMERC_SAVE_DIR`, read once, falling back to today's `user://
autosave/` when unset — matching the `SORCMERC_SEED`/`SORCMERC_FAST`/
`SORCMERC_LINEAR_CAMPAIGN` convention already used throughout) in both
`core/campaign_save.gd` and `core/world_save.gd`. Test drivers that need
isolation (`tests/drive_game.gd`, `tests/drive_campaign.gd`, `tests/
drive_world.gd`, and any `test_*_save.gd` that touches disk) set a
unique dir per run (e.g. derived from `OS.get_process_id()`) rather than
sharing the default. CI is unaffected (one process per job already).

File ownership: `core/campaign_save.gd`, `core/world_save.gd`, and the
test files listed above only. Full suite + all `drive_*` green, verified
under an actual concurrent-process repro (run two drivers that touch the
same save type at once, confirm neither fails anymore) — this is the one
place "full suite green" isn't sufficient proof; reproduce the failure
mode first, then prove it's gone.

**O14 completion (2026-09-11):** landed as `ee95bb3`. Board Game Icons
(the other O10 candidate) turned out to be pure UI iconography, not
usable; Board Game Pack has real pawn/piece art (19 shapes, 7 colours,
CC0) — used the classic pawn (`pieceWhite_border00.png`, cropped to its
alpha bbox), tinted per faction via `modulate` rather than needing
per-colour asset variants (faction colours are hash-derived, wouldn't
map onto 7 fixed ones anyway). `_draw_party()` only; ground/settlement/
building code untouched. Verified visually myself (re-rendered `tests/
shot_world.gd`): clean, readable pawn silhouettes per faction, player's
gold ring still visible at its feet, moved to draw before the sprite so
its far arc reads as occluded ground. Full suite + all `drive_*` green.

**O17 completion (2026-09-11):** landed as `2ceb592`. `SORCMERC_SAVE_DIR`
(resolved once, cached, defaults to `user://autosave` unchanged for real
play) added to `core/campaign_save.gd`/`core/world_save.gd`; every save-
touching test driver sets its own unique dir as the first line of
`_init()`. One real finding along the way: `OS.get_process_id()` alone
doesn't isolate anything on this box's flatpak Godot build — every
process reports pid 3 inside its own namespace — so the dir is keyed on
pid+`randi()` instead (auto-randomized per process, verified unique
across 6 concurrent probes). Reproduced the actual failure before
fixing it (a looped `drive_campaign` racing repeated `drive_game` runs:
1/12 failed) and confirmed it's gone after (0/24, plus 6 more
drive_world/drive_game pairs, 0 collisions) — proof, not just "tests
pass." Full suite green sequentially, verified independently by me as
well as by the agent.

**O15 completion (2026-09-11):** landed as `a493557`. `World.waters`
(plain `{position, radius}` blobs, not a new class — `water_depth()` is
the only reader) and a hand-placed lake northwest of Riverhold plus a
river (overlapping blobs along a polyline) draining past it down to
Ashfell. `_draw_ground()` picks the Water sheet's tile pair within a
shoreline band, blended the same way `WOODED` already blends the forest
edge. Landed together with two real UI bugs caught from actually playing
the build (not part of O15's own scope, fixed opportunistically in the
same commit since they were in the same file): the settlement-visit and
quest-log panels were rendering off-screen (`PRESET_CENTER` anchor +
manual centering math double-offsetting — the anchor call re-centers and
resets offsets, then the position line centered it a second time on top),
and the player's token stayed visible on the map while its own market
panel was open. Verified visually (a throwaway script that walks the
player into a settlement and screenshots it): panel now centered with a
working Leave button, player token hidden, water visible. Full suite +
all `drive_*` green.

**Separately (2026-09-11):** a git hook (`.githooks/post-merge`/
`post-checkout`, opt-in per clone via `git config core.hooksPath
.githooks`, documented in README) now runs `godot --headless --import`
automatically after every pull/checkout, so new or changed assets (art
packs, the bundled font) can't silently leave a stale `.godot/imported/`
cache the way the DejaVu font and the O11-O15 art packs did — that
error class shouldn't recur for anyone who's run the one-time opt-in.

**O16 — closed, already satisfied (2026-09-11):** investigated, no code
change needed. `tools/pack_buildings.py` (O12) deliberately scales all 5
buildings by one shared factor rather than normalizing each to its cell
— its own docstring says so — so the packed sheet already carries each
building's true relative size as differing alpha coverage inside
identical cells; `_draw_building()`'s uniform per-cluster `h` scaling
that over non-uniform cell contents already produces real per-building
sizing. Measured off the sheet's alpha (min-max across 4 rotations):
manor ~0.85h tall/102-123px wide vs. market shed ~0.39h/52-54px wide —
2.1-2.2x apart, confirmed with a reverted probe render (no commit,
working tree byte-identical to master afterward). A hand-tuned scale
table on top would have double-applied the differential and shrunk the
shed to a prop.

Two real, smaller follow-ups surfaced along the way, not yet actioned:
1. The manor (sheet column 3) is wider than its packed cell and loses
   pixels off the right edge on some rotations — a `tools/
   pack_buildings.py` re-pack fix (widen the cell, regenerate
   `buildings.png`), not a `world.gd` change.
2. `_draw_settlement()`'s `style + k` always picks consecutive sheet
   columns for a cluster, so — since the sheet is ordered small to large
   — many factions' clusters land on similar-size neighbours and never
   visibly mix small/large in one settlement (`style + k * 2` or similar
   would fix it, deliberately left alone since the brief said keep that
   logic intact).

## T44 — Darkest Dungeon-style combat juice (locked 2026-09-11, dispatched now, own branch)

Direct user request, scoped via Q&A: procedural motion on the *existing*
flat token art (not new hand-painted character art — that needs a paid
AI art service or commissioned work and is explicitly out of scope for
this entry), landing on `scenes/main.gd`'s hex combat board (not the
open-world map). Four beats: melee attack (hit vs. miss reads
differently), spell cast (tinted by school), a successful save/dodge, and
crit/big-hit impact.

**What already exists (read before building — do not duplicate)**:
`scenes/main.gd`'s `Board` class already has real infrastructure this
extends rather than replaces —
- `play_fx(kind, id, from_hx, to_hx, hexes)` + `_draw_fx()`: a melee lunge
  (sine-curve push toward the target and back, `_lunge(id)`), a ranged
  projectile line, and a spell ring/AoE-hex glow. `_attack_fx()` in the
  main script already picks the right `kind` per verb and calls this.
- `_flash` (per-token white flash on hp change) and `_floats` (floating
  damage numbers) already exist and fire on hp changes.
- `show_reveal()` + `REVEAL_PAUSE` already pop a HIT/MISS/CRIT/SAVED/
  FAILED-SAVE readout with a beat to read it, gated on `_fx_on` (off
  under `SORCMERC_FAST`/headless — keep that gate, tests must stay fast).

**What's missing, this entry's actual scope**:
1. **Hit-stop**: a brief (~80-120ms) full animation freeze at the moment
   of impact on a crit (and optionally a solid hit) — DD's signature
   "this one landed" beat. Distinct from `REVEAL_PAUSE`'s slower popup
   read time; this is a snap, not a pause to read text.
2. **Screen/board shake**: a small random-offset jitter applied to the
   board's draw origin for a few frames, scaled by damage (light on a
   normal hit, stronger on a crit) — reuse the same `age`/`ttl` fx-timer
   shape `play_fx`'s entries already use, don't invent a second timer
   system.
3. **Defender recoil**: a small positional nudge away from the attacker
   on a hit (distinct from `_flash`'s color change), similar shape to
   `_lunge()` but for the target, not the attacker, and much smaller.
4. **Dodge/save sidestep**: on a miss or a successful save, the DEFENDER
   gets its own brief motion (a sidestep/duck, not just "nothing drawn")
   so a miss reads as an active dodge, not an absence of an event.
5. **Spell-school tinting**: `play_fx`'s "spell" case currently draws a
   fixed blue-ish color regardless of school — read `core/ui_icons.gd`'s
   `SCHOOL_COLORS` (already used elsewhere for spell UI) and tint the
   cast glow/ring by the spell's actual school instead.

File ownership: `scenes/main.gd`'s `Board` class (`play_fx`/`_draw_fx`/
`_lunge`/`reset`/hp-change handling) and `_attack_fx()` only — this is a
big shared file with many other systems in it, stay inside those
functions. Keep everything gated on `_fx_on` exactly as today (no new
animation may run under `SORCMERC_FAST`/headless, or every existing
timing-sensitive test breaks). Full suite + all `drive_*` (especially
`drive_ui.gd`, which plays out real fights) must stay green — these are
purely cosmetic additions, they must not change combat outcomes, timing
under fast-mode, or any headless-observable state.

**Branch**: own branch, not master directly (`feature/combat-juice` or
similar) — user asked for this explicitly, same review-before-merge
pattern used for the isometric art spikes. Verify by actually running
the game (`godot --path . scenes/main.tscn` or a scripted screenshot
sequence at a few animation-progress timestamps, same discipline O11/O12/
O14 used) and describing what the motion looks like, not just that tests
pass — juice is inherently a visual judgment call tests can't fully cover.

**Scope addition (2026-09-11, mid-dispatch):** a sixth piece, direct from
the user — a camera "focus" punch-in on the attacker/defender pair
during the resolution beat. `scenes/main.gd` already has a real zoom/pan
mechanism (`_zoom`, `_pan`, `set_zoom()`, `_zoom_at()`, already wired
into the board's projection and font scaling for manual scroll-zoom) —
reuse it rather than building a new camera system: tween `_zoom` up and
`_pan` toward the attacker/defender midpoint for the resolution window,
then ease back to whatever the player had set (save/restore or blend
additively, don't clobber their manual view). Same `_fx_on` gate, same
outcome-parity bar as the other five.

**Scrapped (2026-09-11):** built, verified (hit-stop/shake/recoil/dodge/
school-tint/focus-punch-in all confirmed working via real screenshots,
full suite + outcome-parity green), but the user reviewed it and it
wasn't what they wanted — procedural motion on the existing flat tokens
isn't the read they're after. Branch `feature/combat-juice` deleted
(local, remote, worktree), nothing merged to master. T45's portrait-
reveal work is unaffected and continues separately — the two were always
meant to be distinct pieces of "focus," and this closes out the
procedural half without touching the portrait half.

## T45 — attacker/defender portrait reveal (locked 2026-09-11, spike dispatched now)

What the user actually meant by "focus animations on the attacker and
the defender": a large character-portrait popup shown for BOTH combatants
when an attack resolves, in a Darkest-Dungeon-esque painted/illustrated
style (reference image supplied by the user: a full-body armored knight,
ink linework, desaturated muted palette, dramatic side lighting) —
distinct from T44's board-level camera/motion juice, which continues
separately and unblocked by this.

**Phase A (dispatched now) — art spike, CC0/licensed first per user's
choice.** Search itch.io/OpenGameArt/Kenney and similar sources (same
license rigor as every prior asset spike: confirm CC0/CC-BY directly on
the asset page, note count/style/resolution, direct link) for fantasy
character PORTRAIT art — bust or full-body, one look per class/species
archetype (fighter, cleric, rogue, wizard, etc. — the party's own
`core/rules/catalog.gd` class list is the real target set, not an
arbitrary number). Report a shortlist with license confirmation and a
recommendation; do not integrate anything yet — this is research only,
matching O10's shape.

**Style bar loosened (2026-09-11, mid-spike):** the user does not need
an exact Darkest Dungeon style match — "no need about the specific art
theme." Any decent fantasy character-portrait art (any illustration
style — pixel, flat vector, painted, whatever — as long as it reads as
a character bust/figure, not the isometric tile-art style used for the
overworld map) with good class-list coverage and a clear CC0/CC-BY
license is fair game. Don't reject candidates just for stylistic
mismatch to the reference image; the mechanic (a portrait popup on
attack resolution) matters more than the exact look.

**Phase B (after Phase A, not yet dispatched) — wire it in.** Extend
`scenes/main.gd`'s `show_reveal()`/`REVEAL_PAUSE` popup (which already
shows HIT/MISS/CRIT/SAVED text for both hero and monster actions) to
also show attacker + defender portrait art side by side, picked by
class/species the same way `core/ui_icons.gd`'s `combatant_glyph()`
already picks a class/creature-type glyph. Gate on `_fx_on` like
everything else; must not change combat outcomes/timing under
`SORCMERC_FAST`/headless. Own branch, same as T44, reviewed before merge.

**Phase A completion (2026-09-11):** researched, nothing integrated
(research-only as scoped). Real class list confirmed from
`data/classes.json` (12: barbarian/bard/cleric/druid/fighter/monk/
paladin/ranger/rogue/sorcerer/warlock/wizard). Honest finding, even
under the loosened style bar: no clean, ready-made 12-for-12 CC0/CC-BY
class-portrait set exists. Best real candidate — Hyptosis's "200 Free
Lorestrome Portraits" (OpenGameArt, CC0 confirmed) — is a large generic
bust dump with no class tagging; usable but needs ~an hour of manual
curation to hand-pick/crop one look per class, not a drop-in mapping the
way `ui_icons.gd`'s glyph lookup is. Other candidates checked and
rejected: Ravenmore's Fantasy Portrait Pack (CC-BY, real, but a *species*
pack — 4 races, 0/12 classes); Gordy Higgins' Public Domain Fantasy Art
Pack (genuine public domain, but mixed content, not class-focused).
Flagged: a "RPG Class Portrait Pack" that kept surfacing in search
results does not actually exist at the claimed URLs — a search-tool
fabrication, don't chase it again. Recommendation, awaiting user
decision: hand-curate 12 portraits from the Hyptosis CC0 set (free, real
effort, zero license risk) or fall back to a paid AI-generation service
if an exact one-look-per-class set is a hard requirement — no free
source checked delivers that.

## T46 — spike: HEROES 99 animated pixel character pack (locked 2026-09-11, dispatched now)

User-supplied lead: https://au-pixel.itch.io/heroes99. Confirmed by
direct research already: real product, layered composable pixel-art
characters (skin/face/hair/clothing/weapon, 23 hairstyles x 10 palettes,
17 outfits x 8 palettes, 5 weapon types), 32px, Final-Fantasy/Fire-
Emblem-like style, real animations (idle/run/dash/3-combo attack/cast/
block/dodge-roll/crouch/hurt/jump). License: commercial + modification
allowed, no reselling raw assets, explicitly **no AI training** on the
assets — fine for our purposes (we'd be compositing/using them, not
training a model). Full pack: $15 (sale)/$25. A **free** single demo
character exists too — same real animation set (idle/run/dash/attack/
hurt/jump) plus a portrait, genuinely usable, not a teaser.

On "a non-AI API": no hosted/scriptable API exists for this asset —
checked the one companion tool that exists (an unofficial "Character
Assembler," hyperdoxical.itch.io), which is a Windows-only GUI .exe,
interactive one-at-a-time, not automatable. That's not actually needed,
though: the asset itself is just layered transparent PNGs in a known
z-order (skin → face → hair → clothing → weapon). Compositing that
ourselves in a small script is straightforward and genuinely
"non-AI" (pure deterministic image layering) — likely less work than
integrating a third-party tool, and it's exactly the kind of thing a
spike should confirm by actually trying it, not assume.

**Spike scope**: download the FREE demo character (itch.io "name your
own price" — reuse O11's proven headless-download recipe, no purchase
needed for this phase), inspect the actual sheet layout (frame counts/
sizes per animation, confirm license terms hold as researched), and
report back a concrete plan for wiring animated sprite-sheet playback
into `scenes/main.gd`'s combat tokens (currently flat vector-drawn
circles/balls) — what changes, roughly how big a lift, and whether the
full paid pack (for class/hair/weapon variety across the roster) is
worth buying once the pipeline is proven on the one free character.
Research/reporting only — no purchase, no code changes, no branch;
downloading the free demo asset itself for inspection is fine (same as
every prior art spike's "look at the real files" step).

**T46 completion (2026-09-11):** spike done, nothing integrated (research
only, as scoped). Downloaded and inspected the free demo character —
license confirmed clean for our use; 44 real frames across idle(6)/
run(8)/dash(8)/attack(8+2 combo)/hurt(4)/jump(8), one fixed appearance,
faces left only, verified visually (both by the agent's alpha-channel
grid analysis and by me looking at the actual sheet). Integration plan:
`scenes/main.gd`'s `Board` has no per-token nodes at all — everything is
immediate-mode `_draw()` vector shapes over flat per-id state
dictionaries (`_tok`/`_hp`/`_flash`/`_fx`). The natural fit is
`draw_texture_rect_region` (the same primitive O11/O12 already used for
the world map's tiles/buildings) swapped in for the existing `_fan`/
`_ring` "ball" block, with one more per-id `_anim` state dict advanced
in the existing `tick(dt)`, not `AnimatedSprite2D` nodes (would fight
the single-canvas draw model for no benefit). Real event hooks already
exist to drive it: idle = the existing not-sliding branch, run = the
existing slide/lerp branch, attack = `_attack_fx()`'s melee case
(already synced to `_lunge()`/`_fx` timing), hurt = the existing
HP-decrease detection in `tick()`. Estimated small-to-medium, roughly a
day for one character with idle/run/attack/hurt wired.

**Recommendation: hold off on the $15/$25 full pack.** The free demo is
one fixed-appearance character with no team/individual variety — exactly
the opposite of what the paid pack's layering solves. Build and visually
validate the frame-stepping pipeline against the free character first
(cheap, already downloaded, license-clear); only buy the full pack once
that's proven to look good on this game's isometric board, since a
single billboard sprite reading badly on a warped-projection hex board
would be a problem the paid pack's extra variety doesn't fix either.

## T47 — pixel art as the whole game's visual direction (locked 2026-09-11, decided, own branch)

**This is the decision** superseding T44 (scrapped), T45 (portrait
reveal — on hold, may be revisited once real character sprites exist to
portrait-crop from), and T46 (HEROES 99 — passed over in favor of this).
Full character-pipeline spec below is the user's own, given essentially
verbatim; this entry exists to lock it as the record and scope the
dispatches.

**Scope is the whole game, not just combat**, per direct follow-up
("need to adjust all of the visual assets to this pixel art") — the
open-world map's current painted-isometric art (O11's Screaming Brain
Studios ground tiles, O12's rubberduck medieval buildings, O15's water,
O14's Kenney board-game pawn token) is now also slated to move to pixel
art, not just the hex combat board. LPC's asset library is
character-only (no ground/building tiles), so the overworld's
ground/building art needs a *different* pixel-art source — O10's own
research already surfaced one CC0 candidate that was passed over at the
time in favor of the painted look: **Kenney's "Isometric Tiles
Landscape" + "Isometric Roads"** (both confirmed CC0, already
license-checked, no new spike needed for those two specifically). LPC-
composed character sheets are also the natural token art for the
overworld's roaming parties/settlement NPCs, giving one consistent
character-art pipeline across both screens instead of two. This
overworld re-skin is **not dispatched yet** — it's a real, acknowledged
follow-up phase, sequenced after the combat character pipeline (below)
proves out, since that pipeline is the harder/riskier piece and the
overworld's existing art is functional in the meantime (not broken,
just due for a style pass).

Move the hex **combat** board's character representation (`scenes/
main.gd`'s currently flat vector-drawn tokens) to real pixel-art
sprites, sourced from the **Universal LPC Spritesheet Character
Generator** — a large, modular, CC-BY-SA 3.0/GPL 3.0 open asset library
(share-alike, not CC0 — attribution and edited-part republishing
obligations are real and must be honored, not skipped; see step 8).

**1. Get the assets and their license data.** Clone the Universal LPC
Spritesheet Character Generator repo. `spritesheets/` is the parts
library (body, head, hair, torso, legs, weapons, etc.); `CREDITS.csv`
maps every image to its authors and license. Vendor only the parts
actually used into `assets/lpc/`, copying their `CREDITS.csv` rows
alongside — keeps attribution tractable and the repo small.

**2. Understand the grid.** LPC sheets are 64×64 frames, 4 directional
rows per animation (up/left/down/right), fixed frame counts per
animation: walk 9, slash 6, thrust 8, cast 7, shoot 13, hurt 6, plus
extended sets (idle, run, jump, sit, climb). Every layer sheet shares
this layout — stacking is pure pixel-overlay, no alignment math. Some
weapons have oversized variants (192×192 for polearms/greatbows) —
decide early whether to support those or restrict the roster.

**3. Build the compositor (Claude's job).** A Python/Pillow script
taking a loadout JSON, emitting one composed sheet:
```json
{ "id": "merc_01", "layers": [
  "body/male/light", "hair/short/brown", "torso/chain/steel",
  "legs/pants/brown", "feet/boots/leather", "weapon/sword/steel" ] }
```
Stack in LPC's documented z-order (body → feet/legs → torso →
head/hair → hands → weapon; some layers have "behind" variants).
Output `merc_01.png` plus a `credits.txt` generated from the vendored
`CREDITS.csv` rows of those layers. Generated sheets go in
`assets/generated/`, not the source parts.

**4. Generate Godot SpriteFrames.** Same script (or a second one)
writes a `.tres` `SpriteFrames` resource per unit: one animation per
row (`slash_down`, `hurt_left`, etc.) using `AtlasTexture` regions into
the composed sheet. Frame counts come from a small table defined once;
validate by loading the resource in `godot --headless` and asserting
animation names exist.

**5. Hex-grid facing.** LPC has 4 facings; a hex grid has 6 neighbors.
Map: NE/E → right, NW/W → left, N → up, S → down (or left/right plus
the two verticals for attacks along vertical-ish axes). Store `facing`
on the unit, pick the row at animation time.

**6. Play animations from the combat system.** Unit scene:
`AnimatedSprite2D` + `AnimationPlayer`/`Tween` for lunge/shake/flash
juice. Combat resolver emits signals (`attack_started`, `damage_taken`,
`unit_died`) → unit picks `slash_<facing>`, `hurt_<facing>`, returns to
`idle_<facing>` via `AnimatedSprite2D.animation_finished` chaining.
Keep animation names data-driven so weapon type selects
slash/thrust/shoot/cast. (Note for whoever builds this against current
`core/combat.gd`: that layer is presently signal-free, pure return-dict
— `scenes/main.gd` reads results and calls `_attack_fx()` itself. Either
add real signals to `combat.gd`, or keep driving this from `main.gd`'s
existing result-handling call sites; a design call for the implementer,
not pre-decided here.)

**7. Runtime customization (optional, later).** For Battle-Brothers-
style equipment shown live: skip pre-composing, stack multiple
`AnimatedSprite2D` nodes (one per layer) sharing the same frame index —
LPC's uniform grid makes this trivial. Pre-composing is simpler for the
prototype; layered nodes are better once gear matters.

**8. Licensing hygiene.** A Credits screen listing every LPC author
(generated from `credits.txt` per unit, deduplicated), and a
`LICENSES/` folder with CC-BY-SA 3.0 and GPL 3.0 texts. Recolored/edited
parts are share-alike — keep them in a clearly marked, publishable
folder. Code and everything non-LPC stays proprietary. No Steam AI
disclosure needed (this is licensed human-made art, not AI-generated).

**First spike (dispatched now):** steps 1–4 only — one loadout, one
animation (`slash_right`), rendered on a single hex in Godot. Own
branch, not master (`feature/lpc-pipeline` or similar), same review-
before-merge pattern as every other art branch this session. Report
back with an actual screenshot of the composed sheet/rendered frame,
not just "it built" — same visual-proof discipline as O11/O12/T46.

**Monster-coverage plan (locked 2026-09-11):** LPC's rig is humanoid-
only (one body skeleton, layered equipment) — it does not cover most of
the ~316-entry bestiary. Tier the art source by **faction**
(`core/scaler.gd`'s existing `FACTIONS`), not by literal monster id, so
plugging in a second source later is "add a lookup table," not a
rework:
1. **LPC-composed sprites** for humanoid-shaped factions: `goblinoid`,
   `orc`, `kobold`, `gnoll`, `bandit`, `soldier`, `cultist`, and
   humanoid undead (skeleton/zombie, if an LPC fork covers them —
   check during T48 below rather than assuming).
2. **A separate non-humanoid creature pack** (T48, below) for `beast`,
   `giant`, `monstrosity`, `fey`, `elemental`, `construct`, and
   dragon-shaped entries — LPC cannot represent these, forcing them
   onto its rig would look wrong, not just imperfect.
3. **The existing flat vector token stays the permanent fallback**, not
   a temporary stopgap — `core/ui_icons.gd`'s `combatant_glyph()`/
   `FOE_GLYPHS` already picks a creature-type symbol for anything
   without a match. No free source will ever hit 316/316 coverage; ship
   humanoids first, keep the graceful fallback for the rest, iterate.

## T48 — spike: non-humanoid monster art source (locked 2026-09-11, dispatched now)

Companion to T47's monster-coverage plan, tier 2. Research-only (same
shape as O10/T46): search itch.io/OpenGameArt/Kenney for a CC0/CC-BY
pixel-art creature/bestiary pack — beasts (wolves, bears, spiders),
giants, oozes/monstrosities, fey, elementals, constructs, dragon-shaped
things — at a scale/style that can sit next to LPC's 64×64 humanoid
sprites without looking like two different games glued together (doesn't
need to be LPC-compatible frame-for-frame, just a plausible pixel-art
neighbor: similar pixel density, similar palette weight, similar top-
down/RPG-Maker-ish perspective — not painted/photographic like the
overworld's current art, and not isometric tile art).

Cross-reference candidates against `core/scaler.gd`'s actual faction
list and `data/monsters.json`'s creature types for real coverage —
report which factions a candidate pack actually covers, not just "it's
a monster pack." Report a shortlist (aim 3-5) with license confirmation
per candidate, a style-compatibility judgment (does it actually sit
next to LPC characters, or clash), and a coverage table (which of
beast/giant/monstrosity/fey/elemental/construct/dragon it fills). Same
honesty bar as every prior spike: say plainly if coverage is partial or
if the best candidates are a style mismatch, don't oversell. Research/
reporting only — no integration, no branch, no code changes.

**T47 first-spike completion (2026-09-11):** landed on `feature/lpc-pipeline`
(pushed, not merged). Cloned `sanderfrenken/Universal-LPC-Spritesheet-
Character-Generator`; real z-order comes from upstream's own numeric
`zPos` per layer (`sheet_definitions/*.json`), not a fixed prose list —
that's what correctly puts a weapon's "behind" sheet under the body
while the weapon itself sits on top. Grid confirmed empirically (832px
= 13×64 cols; slash = 6 frames at row 14, per-pixel alpha checked, not
assumed). `tools/lpc_compose.py` composites a loadout + writes credits +
a Godot `.tres`; `assets/generated/merc_01.png` renders as a real
chainmail/dagger character. Verified two ways: `test_lpc_spike.gd`
(headless, 9/9 passed: loads, has `slash_right`, 6×64×64 frames) and a
real screenshot on the actual Sunken Shrine combat board (non-headless)
— confirmed by me directly: a crisp 64px pixel character stands on hex
(2,0), feet anchored to the hex ellipse, mid-slash pose, next to the
still-present (unreplaced, as scoped) vector token. Known ceiling for
later: the dagger was chosen specifically because it's the one weapon
using the universal 64px frame — other swords need 128/192px oversize
sheets with offset math, not yet handled.

**T48 completion (2026-09-11):** researched, nothing integrated. Real
target set corrected from the locked entry's assumption:
`data/monsters.json` is a 4-entry test fixture with no `type` field;
`data/bestiary.json` (316 entries) is the real bestiary — beast 87,
humanoid 67, monstrosity 35, dragon 22, undead 17, fiend 16, elemental
14, giant 14, swarm-of-Tiny-beasts 10, fey 8, construct 7, plant 6,
aberration 5, ooze 4, celestial 4. Honest finding: nothing free gives
real coverage at LPC's style weight. The one genuine style match —
**[LPC] Monsters** (CC-BY-SA 3.0/GPL 3.0/OGA-BY 3.0, literally drawn as
an LPC companion set) — only covers a thin slice: small beasts (bat,
bee, worms, snake), one ooze (slime), one undead (ghost). Everything
with real breadth (Tiny Dungeon+Creatures, Kenney Monster Builder,
Hexany's Menagerie) fails the style bar — wrong pixel density (16x16 or
32x16 vs. LPC's 64x64), wrong outline weight, or 1-bit monochrome — and
would read as a different game's art bolted onto LPC humanoids. One
CC0-tagged pack (Pixel Monsters Megapack) was explicitly excluded: its
own page admits "AI generated/modified," contradicting this project's
"licensed human-made art" framing for the LPC pipeline. Recommendation,
now folded into T49 below: use [LPC] Monsters for its narrow real fit,
lean on the vector-glyph fallback (already tier 3) for the rest — giant/
dragon/fey/elemental/construct have no free, style-matched source at
all right now.

## T49 — procedural creature tokens, tier-3 fallback for monster art (locked 2026-09-11, dispatched now, own branch)

Direct user follow-up to the monster-coverage question ("try 1 and 2" —
this is "2"): since real pixel-art creation isn't something Claude can
do (no image-generation tool connected, no hand-drawing capability),
this is a **code-only, deliberately simple** third tier below LPC
(humanoid factions) and T48's sourced pack (non-humanoid factions, once
found) — for whatever's left uncovered by both, or as an immediate
placeholder while T48's pack is evaluated/integrated. Explicitly labeled
placeholder-quality "programmer art," not a peer to hand-drawn LPC
sprites — the point is a real move/attack/death animation beat for
every creature, not visual fidelity.

Build a small procedural creature-shape system: simple geometric/blob
silhouettes (not photorealistic, not trying to look painted — closer to
the existing flat vector combat tokens' own honesty about being simple
shapes) with three real animation beats:
- **Move**: a squash-stretch/bob cycle while sliding toward a position
  (reuse the timing patterns `scenes/main.gd`'s `Board.tick()` already
  established for token interpolation, if useful as a reference — this
  spike doesn't need to touch that file, see below).
- **Attack**: a lunge/snap toward the target, distinct per rough
  creature silhouette if easy (a "bite" snap for beasts vs. a "slam"
  for giants, say) but a single reasonable default animation is fine
  for the spike — don't over-scope shape-specific variety yet.
- **Death**: a collapse/fade-out, not just vanishing.

Scope for this spike: a **standalone module + demo scene**, not wired
into real combat yet (that integration is a later phase, same as T47's
"steps 1-4 only" boundary) — e.g. `core/procedural_creature.gd` (the
shape/animation logic, testable headless) + a small demo scene showing
a handful of creature silhouettes idling/moving/attacking/dying, so the
look can actually be judged. Own branch (`feature/procedural-creatures`
or similar), same review-before-merge pattern as every other art
branch. Render and describe real screenshots, same discipline as every
other visual entry in this doc — "it runs" is not sufficient proof.

**T49 completion (2026-09-11):** landed on `feature/procedural-creatures`
(pushed, not merged). `core/procedural_creature.gd`: a seeded blob body
(radius perturbed by 3 harmonics, no two outlines match) plus one of 6
archetype silhouettes (beast/giant/ooze/dragon/construct/fey) built from
three primitives (blob/tapered-limb/box), keyed off faction/creature-
type via `FACTION_SHAPE` (unknown falls back to beast). Move/attack/
death timing mirrors `Board.tick()`'s existing beat shapes (same lunge
curve as `_lunge()`) so it won't clash in feel once wired in. Verified
visually by me directly, not just the report: idle reads as six clearly
distinct, honestly-simple archetype shapes (winged purple dragon, blocky
grey construct, big-headed pink fey, orange four-legged beast, olive
giant, green ooze skirt) — better than "crude" as feared, genuinely
readable and a little charming. Attack frame confirmed lunging off the
ground shadow, sheared toward the target. One real bug caught by
actually looking at the death frames (not just trusting the code): the
first death pass rotated bodies about their feet, cartwheeling wide
silhouettes into neighbouring tokens — fixed with a shear + capped
spread instead, documented in the file. `tests/test_procedural_creature.gd`:
47/47. Full suite green. Not yet wired into `scenes/main.gd`'s real
combat (out of scope, same "spike only" boundary as T47).

**T49 scrapped (2026-09-12):** reviewed, not what the user wants.
Branch `feature/procedural-creatures` deleted (local, remote, worktree).
No procedural-shape fallback tier — see T50 below for the replacement
direction.

## T50 — extend the LPC codebase itself to cover non-humanoid monsters (locked 2026-09-12, dispatched now, continues feature/lpc-pipeline)

Direct user decision, replacing T49: instead of a separate procedural
fallback system, assess and extend the **LPC pipeline/tooling itself**
so it isn't hard-locked to the one universal bipedal 64×64/21-row rig,
and use that generalized pipeline to bring T48's actual find — the
**[LPC] Monsters** pack (bat, bee, big/small worm, eyeball, man-eater
flower, pumpkin king, slime, snake, ghost — CC-BY-SA 3.0/GPL 3.0/OGA-BY
3.0, a genuine LPC-lineage asset, already license-confirmed) — online as
real, working, non-humanoid coverage, not just a research citation.

**Assess first, don't assume:** read `tools/lpc_compose.py` and the
vendored `sheet_definitions`/`z_positions.csv` data model from T47's
spike. Determine concretely whether [LPC] Monsters' sheets share the
universal grid/z-order convention (T47's own report noted this pack is
"attack + idle only" — confirm whether that means a different row
count/layout, not just a subset of the same one) and whether the
compositor's current assumptions (humanoid part categories: body/head/
hair/torso/legs/weapon; the specific animation-row layout from
`custom-animations.js`) would silently produce garbage output if fed a
non-humanoid sheet, or whether the z-order/stacking model already
generalizes cleanly. Report the real answer before writing code against
an assumption.

**Then extend**, scoped to what the assessment actually finds needed:
- Generalize the compositor/loadout schema so a "creature" loadout
  (fewer/different layer slots, e.g. just "base" + optional overlay,
  not the full humanoid 8-slot stack) is a first-class case alongside
  the humanoid loadout T47 already built — not a special-cased hack.
- Vendor [LPC] Monsters' actual part files into `assets/lpc/` (same
  CREDITS-row-copying discipline as T47's `merc_01`), and compose at
  least 2-3 real creatures from it (e.g. a bat for `beast`, a slime for
  `ooze`, a ghost for `undead`) end to end through the same `.tres`-
  SpriteFrames output T47 built, proving the generalized pipeline
  actually works, not just parses.
- Honestly re-assess and report which bestiary factions remain
  genuinely uncovered after this (giant/dragon/fey/elemental/construct
  are very unlikely to gain coverage from this pack specifically, per
  T48's own findings — confirm rather than assume, but don't force a
  fit that isn't there).

File/repo scope: continue on `feature/lpc-pipeline` (same worktree/
branch T47 used, still live) — this is a direct continuation, not a
fresh branch. Verify with real rendered screenshots of the new
creatures (same discipline as every prior visual entry), plus the
existing `test_lpc_spike.gd`-style headless validation extended for the
new loadouts. Push the branch when done; still not merged to master
without explicit sign-off.

**T50 completion (2026-09-12):** landed on `feature/lpc-pipeline`
(pushed, not merged). Real assessment, not assumed: [LPC] Monsters'
z-order model generalized for free (no layers/zPos on creature sheets,
so a creature loadout is just a one-entry list), but the grid did not —
these are 4-row attack-only sheets with per-row-varying column counts
(e.g. ghost 6 cols n/s but 8 on w/e for a spit projectile), a different
row space from the humanoid's 21/46-row universal layout, not a subset
of it. `tools/lpc_compose.py` now has no hardcoded grid constants;
loadouts declare their own `{row, frames, speed}` per animation, one
code path for both humanoid and creature loadouts. Added a real
on-sheet-and-non-empty frame guard, verified to actually fire three
ways (caught exactly the kind of silent-garbage-output bug the old
fixed-grid assumptions would have produced). `merc_01.png` byte-
identical after the refactor — the regression check that generalizing
didn't disturb T47's humanoid work.

Composed and rendered 3 real creatures (bat/ghost/slime) on the actual
combat board — verified by me directly: ghost reads strongly (pale
wraith, glowing red eyes, tattered hem), slime sits correctly on its
tile, bat is honestly too small/floaty to read as a combatant at hex
scale (flagged, not hidden — flyers need a per-unit anchor/scale, not
the humanoid's foot-anchor, when step 6 wires this into real combat).
`test_lpc_spike.gd` now data-driven over every `data/lpc/*.json`
loadout: 207/207 passed.

**Corrected faction coverage** (T48's "small beasts, one ooze, one
undead" was directionally right but imprecise): real count is ~20 of
316 bestiary entries, concentrated in ooze (3/4 — slime covers Gray
Ooze/Ochre Jelly/Black Pudding by recolor), scattered beast (~8/87:
bat/snake/bee variants), swarm-of-Tiny-beasts (3/10, not previously
credited), undead (~4/17: Ghost outright plus Specter/Shadow/Will-o'-
Wisp recolors — skeletons/zombies belong to the *humanoid* LPC pipeline
instead), and plant (2/6, needs oversize-cell work first, not done).
**Confirmed zero, not assumed**: giant/dragon/fey/elemental/construct/
monstrosity/fiend/celestial (108 entries) — every roster checked by
name against the pack's actual contents, nothing recolors into a fit.
That gap is a sourcing/commissioning problem now, not a pipeline
limitation — the pipeline itself is no longer what's blocking it.

## T51 — wire the LPC pipeline into real combat and merge to master (locked 2026-09-12, dispatched now)

Direct user decision: take what T47/T50 already built and proved
(`merc_01` humanoid, bat/ghost/slime monsters) and make it real —
replace the flat vector tokens in `scenes/main.gd`'s combat board with
the composited sprites, for real gameplay, merged to master. Honest
scope limit stated up front: only ONE humanoid loadout exists right
now, so every party member and humanoid-faction combatant renders with
`merc_01`'s appearance for this pass — per-class/per-character variety
is a real, acknowledged follow-up, not delivered here. Ship what
exists; don't block merging on art variety that doesn't exist yet.

**Coverage for this pass**: `merc_01` for every humanoid-team
combatant (party + humanoid-faction foes); `bat`/`ghost`/`slime` for
their real bestiary matches (Bat/Giant Bat → bat; Ghost/Specter/Shadow/
Will-o'-Wisp → ghost, recolored if that's easy, single color if not;
Gray Ooze/Ochre Jelly/Black Pudding → slime). Everything else keeps the
existing vector token — this is the tiered-fallback design already
locked, not a regression.

**Build, in order**:
1. **Facing** (T47's plan step 5): map relative attacker/defender hex
   position to LPC's 4 rows (up/left/down/right) — left/right for the
   dominant horizontal axis, up/down for the dominant vertical, matching
   the plan doc's own NE/E→right, NW/W→left, N→up, S→down scheme (or a
   simplified 2-facing left/right-only version if the full 4-way mapping
   fights the hex geometry awkwardly — implementer's call, document
   which).
2. **Combat-event wiring** (step 6): idle by default; attack animation
   triggered from the existing `_attack_fx()`/`play_fx()` melee window
   (reuse its `ttl`/timing, don't invent a second clock); a hurt/flinch
   beat on the existing HP-decrease detection hook; death fades/holds on
   the last frame rather than vanishing. Reuse existing token-position
   interpolation (`_tok`) for placement — sprites replace the drawn
   shape, not the positioning system.
3. **Fallback correctness**: any combatant without a matching loadout
   must render exactly as it does today (the vector token path) —
   verify this explicitly with a mixed-roster fight (some LPC, some
   vector) actually rendered and looked at, not just unit-tested.
4. **Licensing hygiene** (step 8, minimum viable): a `LICENSES/` folder
   with the CC-BY-SA 3.0 and GPL 3.0 full texts, and a real, reachable
   in-game credits list (piggyback on the existing Settings screen
   rather than building a new screen) aggregating every vendored LPC
   part's `credits.txt` contents, deduplicated by author. This is a
   real obligation of the license, not optional polish, and must land
   in the same merge — don't ship LPC assets to master without it.

**Non-negotiable constraint**: combat outcomes, RNG consumption, and
timing under `SORCMERC_FAST`/headless must be bit-identical to before
this change — this is a rendering swap, not a rules change. Verify the
same way T44 did: seeded `drive_ui.gd` runs before/after, diffed.

**Process**: continue on `feature/lpc-pipeline` (same branch/worktree).
Full suite + all `drive_*` green, real rendered screenshots of a mixed
LPC/vector-token fight actually looked at and described. Once verified
clean, **merge to master** (the user has explicitly asked for this one
to land, unlike the reviewed-and-parked art spikes) — full outcome-
parity and suite-green verification happens before the merge, same
discipline as every master-bound change all session.

## T52 — source + pixelize reference art for LPC-uncovered monsters (locked 2026-09-12, dispatched now)

T50 confirmed by name, not assumed: giant/dragon/fey/elemental/
construct/monstrosity/fiend/celestial (108 of 316 bestiary entries)
have zero coverage from LPC or its Monsters pack and no recolor gets
there. User-specified pipeline to close part of that gap with real,
individually-licensed reference art converted to pixel style, rather
than another asset-pack search:

**Step 1 — determine the exact uncovered list.** Read `data/bestiary.json`
and cross-reference against T50's confirmed-zero factions to produce
the real, named monster list (not just faction names) that has no LPC
coverage. Report this list before sourcing anything.

**Step 2 — source one reference image per monster** (scope: a
representative first batch, not all 108 at once — pick a sensible
subset, e.g. 1-2 iconic entries per uncovered faction, ~10-15 images
total, to prove the pipeline before scaling it), using, in this order:
1. Google Images with the usage-rights filter set to Creative Commons,
   then verify the ACTUAL license on the source page itself (CC-BY
   needs credit; CC-BY-SA needs share-alike; any "NC" variant is
   off-limits for a commercial game — reject, don't rationalize).
2. Wikimedia Commons, filtered to CC0/public domain.
3. Open-access museum collections (the Met, Rijksmuseum, Smithsonian,
   Art Institute of Chicago — CC0 high-res scans; strong for medieval
   art, heraldry, armor/texture references, dragons/knights/bestiary
   illustrations).
4. Public-domain works (published pre-1929 in the US) — genuine old
   illustrations.
5. CC0 photo sites (Pexels/Pixabay — check each site's own terms;
   Unsplash's license is permissive but explicitly NOT CC0, treat it
   as CC-BY-equivalent, not CC0).
Track and report source URL + exact license for every single image
while working, not after — this is the one place in this pipeline
where sloppy record-keeping becomes a real legal problem later.

**Step 3 — process.** Make the background transparent before
pixelizing if the source has one. Convert to pixel art at a density/
palette weight compatible with the existing LPC sprites (64px-scale
character art) using a permissively-licensed tool or technique —
`github.com/giventofly/pixelit` (confirm its actual license before
using/citing it) is the suggested reference for the algorithm
(palette-quantized nearest-neighbor downscale); reimplementing the same
straightforward technique in Python/Pillow (matching this project's
existing `tools/pack_buildings.py` convention) is equally acceptable if
that's more practical than running pixelit's JS directly — implementer's
call, document which.

**Output**: real converted images + a source/license manifest (one row
per image: monster name, source URL, exact license, attribution text
if required), reported back with actual rendered results for review —
same visual-proof discipline as every art entry in this doc. Research
and image-production only for this dispatch — no integration into
`tools/lpc_compose.py`'s loadout system or `scenes/main.gd` yet, that's
a follow-up once the images are approved.

**Checkpoint (2026-09-12):** user asked for a single example — Baboon
(a `beast`-faction bestiary entry) — before the rest of the batch.
Redirected mid-task: produce just this one monster through the full
pipeline (source, license-record, background removal, pixelize) and
report back for approval before continuing to the other ~10-14.

**T51 completion (2026-09-12): merged to master as `92d1d16`.** Combat
now renders LPC sprites for real, not just on a demo screenshot.
`core/lpc_art.gd` maps combatant → loadout (party/humanoid foes →
`merc_01`; Bat/Ghost/Gray Ooze-family → bat/ghost/slime; everything
else → unchanged vector token — verified in the same frame, side by
side, in the mixed-roster screenshot). Facing resolves off the
*projected* (post-yaw/squash) delta, not the raw hex delta — nearly
always left/right given the board's squash, which is exactly where the
art exists. Combat-event wiring reuses the existing `_fx`/`_lunge()`
melee timing with no second clock; hurt is the existing white-flash tint
applied as sprite modulate (honest gap: the vendored art has no hurt/
death rows, so this is a tint/dim, not a new animation — named with a
`ponytail:` comment). One real bug caught by looking, not by a test: a
negative-width mirror rect doesn't flip in Godot, it normalizes — foes
were rendering a full sprite-width off their own hex. Licensing
hygiene landed in the same merge: `LICENSES/` (full CC-BY-SA 3.0 + GPL
3.0 texts), and a real in-game **Art Credits** panel in Settings listing
all 16 deduplicated LPC artists (two upstream CSV data defects — a
mojibake name and a duplicate-under-two-spellings — fixed so the dedup
actually names each person once). Outcome-parity proven, not asserted:
identical press counts/round counts/outcomes/verb lists across 5 seeds,
`diff` empty, md5s matching, before vs. after the change — verified
independently by me a second time post-merge. Full suite (31 files,
5291 checks) + all 6 `drive_*` green, both pre-merge and again after.

This is a multi-week build; phases 0–1 are the critical path and land first.

## Post-T91 gap note — persistent faction warfare (deferred, 2026-09-13)

Recorded per user instruction while scoping the 3D-diorama/world-size/tile
work (Settlements3D/Lairs3D/Party3D, `_small_world()`/`_large_world()`,
lair persistence): **persistent faction warfare** — settlements and
roaming parties of different "civilized" factions actually fighting each
other over time, territory changing hands, not just monsters/bandits vs.
the player — is explicitly a TODO, not implemented yet. This is a bigger
scope change than it sounds: the locked open-world design (see "Design
decisions locked with the user (2026-09-11 Q&A)" above) deliberately
chose "conflict is monsters/bandits vs. settlements and the player, not
settlements vs. each other" over full diplomacy/war. Revisiting that
would need its own design pass (win/loss conditions for a settlement,
territory-control state, AI faction goals) — no design committed here,
just don't let it get lost. Everything else from this note's source list
(figures-into-Party3D, procedural world gen, fog of war, real defeat
consequences, quest board + chains) was implemented in the same round —
see the T9x/O-series entries or git log around 2026-09-13 for each.

## T9y — a review of the last five commits, and the six things it found (2026-09-13)

Read the five implementation commits that closed out the previous round
(`67afe13` map-figure picker, `ec515c3` player figure + ring, `32c4c88` fog
of war rework, `e3cc910` quick-build no-op, `34300bb` settlement screens),
looking for what they left half-finished rather than for new features. Six
items came out of it; the user picked all six, and they were built in
parallel by five workers against a disjoint file split (one owner per file,
no shared edits), then integrated and verified together.

**1. Water was never saved, and was never terrain.** `world_save.gd`'s
`to_dict` wrote settlements/parties/lairs/explored but not `waters`, and
`from_dict` never called `add_water` — so every lake and river on every map
silently turned to grass the first time a player resumed a save. It had gone
unnoticed because nothing but the renderer read `water_depth()`. Both halves
are fixed: `waters` round-trips (with the usual missing-key-falls-back
contract), and water is now impassable — `World.is_water()`, `set_goal()`
snapping a wet goal back to the last dry point on the line toward the party,
and `move_toward_goal()` walking its travel in `WATER_STEP` hops so nothing
tunnels across a river on a fat delta at 8x, with a one-step shoreline slide
so a party skimming a bank follows it instead of gluing to it. The safety
valve is deliberate and commented: only land→water steps are refused, so a
party already in water (an old save, a spawn inside a blob) swims out rather
than wedging forever. That rule immediately caught a real placement bug —
the small map's `bandits` band started 22 units deep in its own lake — now
moved, and asserted for all three built-in maps plus six procedural seeds.
No pathfinder is involved and none is wanted: clicking across a lake means
"walk to that lake". `World.origin` (`{"kind", "seed"}`) is saved alongside,
so a resumed world can still say which builder made it.

**2. The fog scan was the frame's hot loop, and is now indexed.**
`is_explored()` was a linear scan over every waypoint the party had ever
banked, and `scenes/world/world.gd:_draw_ground()` calls it once per ground
cell per frame — hundreds of cells on screen, up to `MAX_CELLS` (32000)
zoomed out. Tripling `VISION_RADIUS` in 32c4c88 put more of the map on
screen to be scanned, and the existing `ponytail:` note had sized the
compromise for the old radius. `explored` stays the flat, saved list (it is
what `world_save.gd` round-trips), with a hash grid over it keyed at
`BUCKET := VISION_RADIUS`: both queries are "is there a waypoint within R of
this point" and both radii are `<= BUCKET`, so only the 3x3 block of cells
around the point can hold the answer. `reveal()`'s own dedupe scan goes
through the same index. The list is public and `world_save.gd` appends to it
directly on load, so the index reindexes on a size mismatch rather than
assuming `reveal()` is the only writer — a resumed world would otherwise
come back fogged everywhere it had walked. Measured on a 1669-waypoint
trail: **12.6x** faster over 4000 probes (9.6ms vs 121ms), with the two
implementations returning identical answers on every probe — which is what
`tests/test_world_fog.gd` now asserts against the old scan kept as an
oracle. The gap widens with the length of the walk, which was the point.

**3. The map now says where you are.** Two additions on top of the new fog:
off-screen chevrons for the three nearest settlements, pinned to the frame
edge with the faction's colour, the town's name and the travel time to it
(minutes — `World.SPEED` is 40 units per world-minute, so an hours-only
formatter would have labelled every town on the small map alike); and a
top-down minimap inset (`scenes/world/minimap.gd`, new) showing the explored
footprint, water, known settlements, the player and the camera's own view
region, clickable to set a march goal. Three, not all: on the large and
procedural maps every settlement is off screen most of the time and a rim of
chevrons is no more use than none.

**4. Remembered is now drawn as remembered.** 32c4c88 bought a three-tier
fog for the ground but left everything standing on it binary — a town
visited two days ago drew identically to the one you were standing in. Props
now split on the same `is_visible_now()` the ground tint uses: the 2D ring,
label and sprite fade through `World._remembered()` (desaturated toward the
fog colour *and* thinned, because a merely darkened faction colour still
claims full confidence), and the 3D dioramas fade with them via
`GeometryInstance3D.transparency` in the shared rig — a full-brightness town
on a faded footprint was exactly the mismatch to avoid.

**5. The settlement screens got the depth the split was for.** 34300bb
separated town square / market / inn / notice board but left three
unlabelled doors and a one-button inn. The hub's doors now carry live counts
(what is on the shelf, what is posted, whether a room would do anything);
the market is tabbed per counter; the inn shows who is hurt and, when the
once-a-day cooldown blocks a rest, says how long and points at the healer;
Esc/M/I/B navigate. And the two T25 services that stock no goods — Healer
and Librarian — are finally staffed: both existed as priced methods on
`campaign.gd` that the open world could never reach, so they were advertised
in a settlement's services line and then unusable. `settlement_visit.gd` now
has open-world versions (same prices, no campaign autosave, a result dict
instead of `say()`).

**6. Identity, not class, for the map figure — and a walk.** `67afe13`
stored a class id, so two active fighters produced two picker rows that did
the same thing and the staleness check passed if *anyone* shared the class.
It stores a member id now, resolving to a class at render time, with a
self-healing back-compat path for old saves. The troop GLBs are idle-only,
so rather than wait for art the walk is procedural and in-engine: bob, sway
and lean driven by the position delta the layer already tracked, cadence
scaled to real speed (so a party at 8x steps faster rather than floating),
easing back to exactly the idle pose on arrival. Marked in the file header
as a stand-in and what a real walk clip would delete.

**7. The silent-no-op bug class, hunted rather than waited for — and it
immediately caught a regression in the very commit that inspired it.**
`e3cc910` fixed a button whose handler did nothing under a reachable state:
no error, no message. `tests/drive_buttons.gd` (new) generalises that into a
sweep — 38 pages, 794 presses — which rebuilds each screen from scratch
before every press (so no press is judged against the state a previous one
left), fires the control without touching its own widget state (a checkbox
flipping its own tick cannot pass for the screen having done something), and
asserts the Control tree or the underlying model observably moved.

What it found on its first real run: **`e3cc910` had inserted
`func _apply_quick_build()` into the middle of `_build_abilities()`**, so
GDScript ended `_build_abilities` at the blank line above it and the entire
six-ability grid — every array selector, every point-buy stepper, the whole
`→ total` column — became unreachable tail code of the new function. Step 3
of character creation had rendered three buttons and nothing else since that
commit: "Point buy (27)" set all six scores to 8 and then offered no way to
spend a single point. The grid only ever appeared as a side effect of
pressing quick-build. Fixed by moving the definition out below
`_build_abilities` (pure code motion, no logic change).

It is worth being blunt about the lesson: the review that produced this
whole round read `e3cc910` and did not catch this, because the diff read
correctly — the bug was in where the new function landed, not in what it
said. The sweep caught it in one run. Verified non-vacuous by mutation:
re-introducing the indentation bug, the original quick-build no-op, a dead
heal button and a `pass`-wired quest toggle each fail it.

Blind spots are listed in the file header — the world map and party screen
are a deliberate follow-up (one more `sweep()` call each), and combat itself
stays `drive_ui.gd`'s job.

**Honest gaps left:** no pathfinding around water (a march into a lake stops
at the bank, by design); the roaming-band props are drawn at their live
position even when only remembered, because the map keeps no last-known
position to draw instead; the diorama fade fades without desaturating, where
the 2D layer does both; and persistent faction warfare (the note above) is
still untouched.

### How T9y was actually run — five local agents, one working tree

Recorded because the split is the reason this round landed as one coherent
change rather than five conflicting ones, and because two of its failures
are worth not repeating.

**The partition.** Five workers in a single working tree (no git worktrees,
no branches per worker), divided by *file ownership* rather than by feature.
Each brief named the exact files that worker could edit and forbade
everything else, including git itself — nobody committed, nobody branched,
nobody stashed; the parent session integrated and made the single commit.
Ownership was:

| worker | owns | built |
|---|---|---|
| parent | `scenes/world/world.gd`, `core/settlement_visit.gd`, the three diorama layers, docs | items 3-5, integration |
| core | `core/world.gd`, `core/world_save.gd`, the two map builders | item 1 |
| figures | `core/party.gd`, `scenes/party/party.gd`, `scenes/world/party3d.gd` | item 6 |
| minimap | **new files only** — `scenes/world/minimap.gd`, its test | item 3's inset |
| sweep | **new file** `tests/drive_buttons.gd`, plus fixes confined to the screens nobody else held | item 7 |

`scenes/world/world.gd` is 1489 lines and every UI item wanted it, so it was
not split at all — the parent kept it and did items 3-5 itself while the
other four ran. That is the same lesson `docs/improvements.md` recorded for
`scenes/main.gd` back in the MVP plan ("the one contention point"), applied
instead of relearned.

**Contracts agreed before the code existed**, so a worker could write
against something another worker had not written yet: the minimap's public
surface (`world_map`, `DEFAULT_SIZE`, its own placement left to the parent)
was specified in the brief, and the parent wired it before the file landed;
`World.origin`'s exact shape (`{"kind", "seed"}`) was pinned in two briefs
at once. The figures worker was forbidden `world_save.gd` because the core
worker held it — which is *why* `overworld_figure` kept its name and changed
its meaning instead of being renamed, and therefore why old saves still
load.

**Cross-worker findings were reported, not fixed.** The core worker found
the small map's bandit band standing in a lake, in a file it did not own,
and wrote it up with the corrected coordinate instead of reaching for it;
the parent moved the band and added the assertion. The sweep worker found a
bug in `scenes/world/settlements3d.gd` the same way (below). Ownership held
in both directions — no worker silently edited outside its lane, and no
finding was dropped on the floor.

**Two failures, both the parent's:**

1. *A task fell out of a brief.* The core worker's brief was written with
   three tasks; the fog-index work (item 2) was in its title and not in its
   body, so it was never dispatched. It surfaced only when the completion
   report came back without it, and the parent then wrote it directly. The
   brief body is the contract — a task named anywhere else does not exist.
2. *A scripted edit deleted a function.* The parent hoisted `_fade()` into
   the shared diorama base with a Python slice over `settlements3d.gd` whose
   end anchor sat below `reset()`, silently removing it. The system's own
   file-changed excerpt was read as confirmation — it showed only the region
   that survived. It was caught because the sweep worker, running the suite
   against its own files, reported `world.gd` calling a `reset()` that "does
   not currently exist". `git diff` after every scripted edit would have
   caught it in seconds; reading an excerpt of the result would not, and did
   not.

**Two smaller frictions worth knowing:** running the full suite while
workers were still editing produced a transient "Compilation failed" (a file
was read mid-write) and one 4-minute test timeout from five headless Godot
processes competing for the same CPU — neither was a real failure, and both
cost time to rule out. Integration runs belong after the workers are done,
not alongside them. And a finished worker re-notifies when its own
background waiters exit: those repeats carry nothing new and should be read
as such rather than acted on twice.

## Scope revision — open-world sandbox RPG, not a campaign map (locked 2026-09-13)

Supersedes the "Mount & Blade-style open world" lock of 2026-09-11 (above).
The open world itself stays; what it is *for* changes. Direct user direction:
an open-world sandbox RPG with D&D combat, explicitly not M&B's overworld
gameplay.

### Why, in one paragraph — this is mechanical, not a matter of taste

The world layer as built undermines the combat engine it exists to serve.
5e only sings across an **adventuring day**: slots, HP, short-rest pools and
once-per-day abilities draining over several fights before a long rest.
That attrition is where class balance lives, and T38/T40 tuned it
carefully. But open-world fights are sparse and isolated — meet a band,
fight it, walk away, rest. `LONG_REST_COOLDOWN` is the only brake, so
optimal play is one fight per day at full resources. Every fight is a fresh
nova: the Fighter's short-rest economy is inert, the Wizard never rations,
and `scaler.gd`'s difficulty tiers measure a situation the player is never
forced into. Fixing that removes most of the "this feels like M&B" feeling
as a side effect, because the map stops being a corridor between menus and
starts costing something to cross.

### Locked with the user (2026-09-13 Q&A)

- **Core loop: the delve cycle.** Town → wilderness → site → back. Rumors
  and the board point at sites; sites hold treasure and XP; deeper regions
  need higher levels. Rejected: survival-crawl (no safe base), a pure
  reputation sandbox, and a no-central-pull sandbox.
- **Sites have interiors.** A lair becomes 3-6 linked encounters on ONE set
  of resources. This is the adventuring day, and it is the whole point.
  Rejected: the lightweight 2-3 fight version, and keeping one-fight lairs.
- **Travel: keep the 1x-8x fast-forward AND add the decisions and events.**
  The user picked both halves deliberately, and they are only in tension if
  the clock is dumb. The synthesis, and the design this locks:
  - **Standing orders, not per-watch prompts.** Pace (careful / normal /
    forced), who scouts, who keeps watch — set once as a travel policy, not
    asked every few hours. Fast-forward stays fast because there is nothing
    to answer while nothing is happening.
  - **The clock auto-pauses on anything that matters.** An event, a
    sighting, a site coming into view: `world.clock.pause()` (already the
    mechanism `_check_visit`/`_check_encounter`/`_check_lairs` gate on) and
    surface the decision. 8x is then safe rather than a way to skip content
    — it is "nothing is happening, wake me when it does."
  - Standing orders are what *decide* how an event resolves (who rolls,
    with what advantage, what options exist), so the decisions have teeth
    without costing a prompt per watch.
- **Party scale: four heroes, permanently.** Growth is levels, gear and
  reputation — never headcount. `RoamingParty.troops[]` stays cosmetic
  flavour for NPC bands and never becomes a player-facing system.
  Rejected: hirelings, and growing into a warband.

### Keep / reframe / cut

**Keep, unchanged** — all of it serves a delve cycle as well as it served a
campaign map, which is why this pivot is cheap: the free 2D map, three-tier
fog of war, settlement beacons, the minimap and off-screen chevrons (T9y),
water as terrain, settlements with market/inn/board/healer/librarian,
camping with ambush risk, foraging, Trance, the short/long rest economy,
lairs as things found by a Survival check, faction opinion as plumbing.

**Reframe**

| thing | from | to |
|---|---|---|
| lairs | one fight, a flat gold number, spent forever | a site with an interior: several encounters, per-room loot, a boss cache |
| roaming bands | a proximity radius that fires a fight *at* you | an approach you choose: avoid / ambush / parley / engage |
| the clock | a strategy-layer speed control | fast-forward that auto-pauses on anything real |
| faction opinion | a price multiplier | access and people: who hires you, who shuts the gate |
| quest board | kill-count and fetch against monster ids | work that points at sites |

**Cut, and say so out loud**

- **Persistent faction warfare** — the standing deferred note above is now a
  decision, not a gap. It serves a strategy game, not four adventurers, and
  it is the most M&B thing left on the board. Not building it is the
  clearest signal of which game this is.
- **Trade-route economics** (arbitrage, caravans, price spreads) and any
  form of troop recruitment.
- **Off-screen NPC-vs-NPC battles as a feature to grow.** `world_battle.gd`
  stays as world texture; it does not get deeper. Nobody watches them.

### Build order

**D1 — sites: the adventuring day, from a system already written.**
`core/campaign.gd` is a 5-stage route (`STAGE_POSITIONS`, `PICK_MIN/MAX`
branching picks, `SUPPORT_KINDS` treasure/rest nodes, `BOSS_POOL`, and
`short_rests_used`/`long_rests_used` already tracked) with 1140 assertions
and a `drive_campaign.gd` robot, dormant behind `SORCMERC_LINEAR_CAMPAIGN=1`
since the open world landed. **That is a dungeon.** Re-point it as a site
interior rather than writing one: stage count from the site's tier, no
merchant nodes inside a goblin warren, rest nodes offer a short rest only,
long rests forbidden outright (cap `long_rests_used` at 0 — the attrition
is the feature), roster themed from the site's faction through the gating
`scaler.gd` already does. The linear-campaign flag stays working; this is a
second profile over the same engine, not a rewrite of it.

**D2 — lairs become sites.** `world.gd`'s `_lair_action()` enters a D1 site
instead of launching one fight; `world_lairs.gd`'s flat `loot()` gives way
to the site's own caches. A site can be left part-cleared and re-entered,
which is what makes "withdraw" a real choice rather than a loss. Depends D1.

**D3 — travel: standing orders + an event table + auto-pause.** New
`core/travel.gd`: the policy (pace / scout / watch), a seeded event table
rolled on the world clock, and the auto-pause contract above. Events resolve
through the skill-check idiom every overworld check already uses
(`WorldLairs.search`, `WorldCamp.watch_check`, `WorldForage.check`) — name
the check, name the roll, never just "something happened".

**D4 — encounters you choose.** A roaming band in range opens an approach
step instead of a fight: avoid (Stealth), ambush (Survival), parley
(Persuasion), engage. Every one of those idioms exists already
(`sneak_past`, `persuade`, `watch_check`, and T39's surprise/scouting
deployment) — this is wiring, not new mechanics. Depends D3.

**D5 — rumors.** How a site gets onto the map: the inn sells information, a
turned-in job points at the next place, a survivor tells you what is down
there. Replaces "wander until a Survival check pings" as the primary
discovery path (that stays as the secondary one). Depends D2.

**D6 — regions and tiers.** Level-banded areas so "further out" means
something and the delve cycle has somewhere to go. `scaler.gd` already has
tiers; this is placing them on the map. Depends D2, D5.

### Non-goals for this arc

No narrative/dialogue layer yet (still deliberate — see README) — *superseded
by M1–M8 below, which added one as a content-pack API rather than as a
hardcoded campaign*; no crafting;
no settlement building; no mounts; no romance; no simulation of anything the
player cannot see. The party is four people. If a feature only makes sense
for an army or a lord, it is out by construction.

### Not yet decided

- Whether a site's interior is *drawn* (a mapped dungeon the party moves
  through) or stays a node graph like `campaign.gd`'s route screen. D1 works
  either way; the node graph is what already exists and is what D1 assumes.
- Whether withdrawing from a part-cleared site restocks it over time.
- What death means in a sandbox with no run boundary — `world.gd`'s
  `_retreat()` soft landing was written for a campaign map and should be
  revisited once sites exist, because a site is where a party can actually
  be lost.

### Spike — the DMG body-count multiplier (2026-09-13, built, measured, reverted)

Asked for directly after the D1 measurements showed the wilderness draw
producing wildly inconsistent fights under one "easy" label. The diagnosis
was that `Scaler._score()` is linear in monster count — the eighth body is
priced like the first — while 5e's own encounter rules multiply by monster
count precisely because what beats a party is the number of turns the other
side gets. Confirmed empirically first: holding the budget fixed and spending
it on twice as many half-strength monsters took the fey warband from 53% to
27%.

**It works for its purpose.** With the term in and TIER re-calibrated by
measurement, the level-3 faction spread tightened from a 47-point range to
30: fey 53% → 73%, cultist 73% → 90%.

**It was reverted anyway**, because it destabilises the level/tier
calibration. Crowd pricing forces every TIER up by roughly half, and at a
level-8 budget the generator answers a bigger budget with bigger monsters
rather than more of them — which lands squarely on the chunk overpricing
`scaler.gd`'s own "Known ceiling" note already describes. Five
configurations, each with TIER re-calibrated by sweep rather than guessed:

| crowd term | level-3 | level-8 |
|---|---|---|
| DMG table (x1.5 / x2 / x2.5) | 97.0 / 85.0 / 71.5 ✓ | 96.7 / 93.3 / 95.0 — flat, unordered |
| `pow(n, 0.40)` | 86.5 / 82.0 / 72.5 ✓ | 93.3 / 95.0 / 96.7 — **inverted** |
| `pow(n, 0.25)` | — | ordered but flat (94 / 91 …) |
| `pow(min(n,5), 0.40)` | wants TIER ~1.05–2.03 | needs TIER ≥ 2.4 for spread |
| `pow(n, 0.15)` | 88.5 / 82.0 / 63.5 ✗ | 90.0 / 98.3 / 76.7 — unordered |

No single TIER triple satisfies both parties. The knob that reconciles them
is **CURVE** — how fast the budget grows with party power — which was left at
0.90 throughout and is the thing that actually differs between a level-3 and
a level-8 fight.

**For whoever picks this up:** calibrate CURVE and TIER together against both
parties, and fix `estimate()`'s chunk pricing first — the crowd term and the
chunk bias pull in opposite directions and compound, so tuning either alone
chases its own tail. Three knobs, measured, not a one-line addition. The
measurements above are in `core/scaler.gd`'s TUNING header so the next
attempt starts from results rather than from the idea.

Method note, and it cost a full round to learn: `core/encounter.gd` documents
`spec["seed"]` as "omit for a random fight", and `tests/test_scaler.gd`'s own
sweep pins it. A harness that does not pin it produces numbers that move run
to run — an earlier pass in this round reported a faction split that did not
survive re-measurement. Pin the seed, or do not quote the number.

---

## D1–D6, built (2026-09-13)

The build order set out in the scope revision above, as it actually shipped.
Each item names the commit's own claim and the number that backs it; the
per-file headers carry the measured grids in full.

**D1 — sites.** `core/site.gd`: a lair is 3–6 rooms run on ONE set of
resources. No long rests inside, short rests as a room kind, merchant nodes
excluded (nobody is selling potions in a goblin warren). The adventuring day,
from `campaign.gd`'s existing 5-stage route engine rather than from a new
dungeon system. Site defeat takes a third of the loose stash and leaves
equipped gear alone, and the lair resets — the user's own call between the
two options offered.

**D2 — lairs become sites.** `_lair_action()` enters a site; withdrawing
part-cleared is a real choice because `depth_cleared` persists. A lair left
alone resolves without the party after `WorldLairs.WINDOW` (2880 minutes) —
cleared by somebody else or abandoned — and says which, out loud.

**D3 — travel.** `core/travel.gd`: standing orders (pace / scout / watch),
six road events on a seeded table, and the auto-pause contract. Every event
names the check and names the roll, and credits the standing order that put
that character on the job — which is the only place the player ever sees an
order they set hours ago pay off.

**D4 — encounters you choose.** `core/approach.gd`: avoid / parley / ambush /
engage, each priced on the card before it is pressed. Ambush hands the first
round over on a failure, which is what stops it dominating engage. Parley's
deny-list is its own (`MINDLESS`) rather than `WorldAI.CIVILIZED` — by that
list a bandit is a monster, and a bandit wanting paid is the most obviously
bribable thing on the map.

**D5 — rumors.** `core/rumors.gd`: a town sells what its people know, a
turned-in job earns a lead for nothing. The thing pinned hardest is that a
lair heard about in a common room sets the SAME `discovered` flag a Survival
check sets — one flag, one meaning, so nothing downstream learns there is a
second kind of found.

**D6 — regions and tiers.** `core/regions.gd`: four rings anchored on the
human settlement and sized to the map's own extent. The rule is a clamp, not
a replacement — inside its band a fight is still built for the party standing
there, so every win rate in `scaler.gd` still means what it says; outside it,
content stops following. Measured, 80 seeds a cell, fight seed pinned:

| party | content | scale | win |
|---|---|---|---|
| lvl 3 | lvl 3 | x1.00 | 92.5% — in band, untouched |
| lvl 10 | lvl 3 | x0.41 | 100% — the heartland is a memory |
| lvl 3 | lvl 6 | x1.86 | 37.5% — one band out: "not yet" |
| lvl 3 | lvl 10 | x2.45 | 27.5% — the deeps, at level 3 |

That is the destination the delve cycle was missing: the frontier is visible
from the start, genuinely lethal, and the thing that opens it is levels — not
a key, a quest flag, or a wall. It is signposted four ways before anybody
walks into it (HUD band label, the inn's leads, the lair button, and a
one-time card when riding out above your level), because a level-banded map's
one failure mode is a wall you only learn about by hitting it.

**D6.1 — the heartland was a bubble.** The seams shipped at 0.30 / 0.60 / 0.85
of the map's extent, which *sounds* like four comparable countries and is not:
a ring's share of a map goes as the square of its radius, so those seams gave
the four bands 9% / 27% / 36% / 28% of the map. The heartland — the band built
for levels 1-3, which is the whole early game — was a third the size of any of
its neighbours. On the shipped maps it came out 237 units across (small) and
592 (large), and held the starting town and nothing else: the first landmark a
new party could walk to was already Marches content built for level 3-6.

The seams are now equal-area — sqrt(1/4), sqrt(2/4), sqrt(3/4) = 0.50 / 0.71 /
0.87 — so each country really is a quarter of the map. Nothing else in D6
moved: the clamp, the ruler, and every measured win rate above are untouched,
because widening a ring changes *where* a seam is, not what happens either side
of it.

| | old | new |
|---|---|---|
| heartland / marches / frontier / deeps, by area | 9 / 27 / 36 / 28% | 25 / 25 / 25 / 24% |
| heartland radius, small map | 237 | 394 |
| heartland radius, large map | 592 | 986 |
| generated maps placing a lair inside a settlement's 300-unit gap (400 seeds) | 4 | 0 |

Two things fell out of it. Oakford — the second human town, and the obvious
first ride out of Riverhold — is now in the country built for the party that
can reach it. And the goblin warren, whose faction's home band is the heartland
(`Regions.HOMES`), was hand-placed at frac 0.71 on *both* hand-placed maps: two
countries from home, a rule the procedural builder has always enforced and the
hand-placed ones silently broke. Pulled in to 0.45 (small) and 0.39 (large),
clear of every settlement, lair and both banks of the river. That last one is
what actually puts something in the near ring; a wider empty bubble would still
have been an empty bubble.

### Still open

- **The three-knob scaler retune** (CURVE + TIER + `estimate()`'s chunk
  pricing), described in the body-count spike record above. D6 deliberately
  did not touch it: the band clamp reads scaler's existing curve at a
  different point rather than changing its shape, which is why no measured
  number moved.
- **Whether a site's interior is drawn** rather than being a node graph. D1
  works either way and assumes the node graph, which is what exists.
- **Whether withdrawing from a part-cleared site restocks it over time.**
  Currently it does not; the D1 window expires the whole lair instead.

## M1–M8 — the content pack API: worlds, campaigns, and DLC (built 2026-09-14)

The narrative layer landed, and it landed as a public API rather than as a
hardcoded campaign. The ask was three things that turned out to be one thing:
let the community build worlds out of the features the game already has; grow
that into campaigns with stories, quest chains and characters; and ship the
team's own stories through the same route, some free and some paid.

They are one thing because the alternative — a DLC pipeline for us and a mod
pipeline for everyone else — has a known ending: the mod half rots, because
nothing anybody cares about is running through it. So there is one format, one
loader, one validator, and the three packs the game ships (`content/`) are
written against the same API a stranger's zip file uses. `docs/modding.md` is
the authoring guide; this is the record of what was built and why it is shaped
this way.

**M1 manifest / M6 registry.** A pack is a directory with a `pack.json`. Two
roots — `res://content/` (ours) and `user://mods/` (theirs) — one pipeline. A
pack's `official` flag comes from the root it was found in, never from
anything it can write about itself, and the first root wins a duplicate id, so
a mod cannot shadow a DLC by claiming its name. Everything a pack declares is
parsed and checked at **scan** time, not play time: an author learns their
story is broken from the browser, and a player never gets three chapters into
one that cannot finish.

**Data only, and that is the security model.** A pack ships no GDScript, and
there is no hook or script field anywhere in the formats. Community content is
downloaded from strangers and run on a player's machine; a pack that could
carry code would be a way to run that code. Everything is JSON interpreted by
`core/mod/`, which is also what lets official and community content share one
trust level instead of needing two.

**M3 worlds.** `world.json` places everything the three built-in builders
place: settlements, hidden lairs, roaming bands with a behavior and a roster,
water (a `river` polyline is the one piece of sugar, because every hand-placed
river in this project is a for-loop stamping blobs and making an author write
that in JSON means making them write it wrong), and the start. Nothing in it is
a new concept, which is the point.

The thing that makes a pack map read like a designed map is that **it declares
no difficulty at all**. D6's bands are measured off the map's own extent and
anchored on its human settlement, so an author gets the level curve by placing
things — goblins near home, the dragon at the edge. `tests/test_world_pack.gd`
asserts exactly that on the shipped campaign: three lairs, three different
bands, no region data in the pack.

**M4/M5 stories, and the decision the whole layer rests on.** A story is
chapters of beats; a beat fires the first time its condition holds. Conditions
are **predicates over state the game already keeps** — a flag the story set, a
quest's state in the party's own log, where the player is standing, which lairs
are cleared, party level, the day, faction opinion — and the runtime is
*polled*, once a frame, next to the lair and forage and travel checks it sits
beside in `world.gd`.

Events would have been the obvious design and would have been worse: an event
bus means every system in the game has to publish into it before a story can
react to it, which means a modder can only write stories about the systems
somebody remembered to wire. Predicates need nothing. A content pack can tell a
story about systems that have never heard of it, and the integration into a
2278-line world screen is one `_check_story()` call.

The second decision: **a story quest is an ordinary quest**. A quest beat
appends to `party.quests`, and from there the existing machinery — kill
tracking, the turn-in at any merchant, the log panel, the encounter spawn bias
— picks it up with no idea a story is involved. A quest chain is quests that
unlock each other, not a second quest system.

**M2 free and paid.** `"access": "paid"` plus a `product_id`. A paid pack the
player does not own is listed but **not loaded** — not loaded-and-hidden, so a
locked DLC cannot leak a monster, an item name or a line of its story through
some other system that reads the catalog. What is owned lives in
`user://entitlements.json`; a storefront integration calls `Entitlement.sync()`
once at boot and everything downstream keeps working, offline. Playtest builds
own everything, through the same switch `progression.gd` already uses. The game
is not the storefront and has no purchase button.

**M5 data overlays.** A pack's records are folded into `catalog.gd`'s own
parsed arrays, merged by id — so a pack can add a monster *and* retune one of
ours, and the result is a monster to the faction rosters, the encounter builder
and the bestiary screen with nothing anywhere made pack-aware. The one trap
found on the way: `scaler.gd` caches its faction pools off the bestiary, so
changing what the bestiary is has to drop that cache (`Scaler.forget_pools()`),
or a pack's monsters exist everywhere except in a fight.

**M7/M8 the screens.** A browser on the title screen (every pack, its state,
and every problem with the broken ones spelled out in full — an author's only
feedback loop is that list, so a truncated error is a bug report nobody can
act on), a beat card, and a journal. The autosave carries the story's progress
and the id of the pack it belongs to; a resume whose pack has since been
uninstalled, disabled or locked comes back as the map it already is, with the
story simply not being told, rather than as a broken save.

### Shipped content

| Pack | |
|---|---|
| `content/example-world/` | a map and nothing else — the shortest thing that is a working pack, and the one to copy |
| `content/ashen-road/` | free, three chapters, its own map, three cast members, a quest chain, two monsters and two items |
| `content/vault-of-the-ember-crown/` | paid, `requires` the above, and the reason the DLC path is exercised by our own content rather than only by a test |

### Fixed on the way

- `WorldAI.wander()` documented taking a bare point and crashed on one
  (`"position" in <Vector2>` is an error, not a false). The Vector2 half of its
  own contract now works, which is what data-driven placement needs.
- `world.gd` had twelve copies of `WorldSave.save(world, party)`; they are one
  `_autosave()`, which is also where the story now rides along.

### Still open

- **A story cannot yet author a fight.** Beats can hand over quests, move the
  purse, reveal lairs and spawn bands, but a scripted set-piece encounter (this
  roster, on this board, at this moment) goes through the same generated
  pipeline as everything else. `Encounter`'s spec dictionary is the obvious
  seam and is deliberately not exposed yet — designed, not built, in **M9**
  below.
- **Story-only packs have nowhere to be told.** The format allows a pack with a
  story and no world; starting one drops it on the default map, where its
  `near`/`lair_cleared` conditions name places that do not exist. Either they
  should declare a world they attach to, or the browser should ask which map to
  tell them on.
- **No localisation seam.** Every string in a pack is the string the player
  reads.
- **`user://mods/` on the web build.** The browser export has no real user
  directory to drop a zip into, so community packs are a desktop feature for
  now; `res://content/` ships everywhere.

## A new hero joins at the party's level (2026-09-14)

Creating a character mid-game handed you a level-1 hero to walk into content
the rest of the party is levels past — a replacement for a dead veteran was a
liability, and the fifth build you wanted to try was unplayable. The creator
now builds at `Party.active_max_level()`: the highest level among the <= 4 who
fight (1 while nobody does, so the first hero is still a first hero).

`scenes/party/party.gd` injects it with `creator.set_start_level(...)` before
the overlay opens; `Leveling.grant_levels()` appends the levels and banks
exactly `xp_for_level(target)`, so the new arrival is not instantly owed
another one. Nothing else in the creator changed: every grant those levels
bring arrives as a pending choice the way level 1's do, so the Skills &
Background and Review steps ask for the subclass, the ASI-or-feat and the
spells, and Confirm stays blocked until they are all made. The three presets
go the same way — they are level-3 builds with their choices already made, so
they are topped up to the party's level rather than rebuilt.

The catch-up is a gift, not a haul, and the meta-progression must not be able
to tell the difference — so it touches neither side of `core/progression.gd`:
lifetime XP (which buys species and classes) and class XP (which buys
subclasses) are still only ever written by `core/campaign.gd` out of XP earned
in a fight. Milestone achievements stay out for the same reason: being handed
level 5 is not reaching level 5. Covered by `tests/test_leveling.gd`'s
`_catch_up` / `_catch_up_in_creator` (the model, then the real creator scene)
and `tests/test_party.gd`'s `test_active_max_level`.

## M9 (design note, not built) — scripted fights for content packs

The one thing a pack cannot do that a pack author will want on day one: say
*this* fight, with *these* foes, on *this* board, at *this* moment in the
story. Written down now, while the shape of M1–M8 is fresh, so whoever picks
it up is not re-deriving the seam.

### Why it is not already possible

Every fight in the game is generated. `Scaler.roster_for(chars, difficulty,
bias, theme, seed, power_scale)` builds a roster for the party that is standing
there, and hands back a spec:

```gdscript
{"monsters": [{"id": "snik", "count": 3, "mult": 1.2, "features": [...]}],
 "theme": "goblin-camp", "mult": 1.0, "seed": 1234}
```

`Encounter.build(spec, party_combatants, board := {})` turns that into a
`Combat`. Note what that means: **the spec is already exactly the thing an
author would want to write**, and `Encounter.build()` already accepts a
hand-written one — `Tutorial.SPEC` is a hand-authored spec that ships today,
and `core/site.gd` already runs a room off a pre-built spec without going
through the scaler at all. The machinery is there. What is missing is a way for
a *pack* to supply one, and a way for a *story* to trigger it.

### The shape

A `fights` block in the pack, referenced by id — beside `cast`, not inside a
beat, because the same set-piece may be reachable from more than one place:

```json
"fights": [
  {
    "id": "warren-mouth",
    "title": "At the mouth of the Ash Warren",
    "theme": "goblin-camp",
    "monsters": [
      {"id": "warren-firecaller", "count": 1, "mult": 1.4,
       "features": ["monster-surprise-attack"]},
      {"id": "snik", "count": 4}
    ],
    "scale_to_party": false,
    "seed": 91
  }
]
```

and a beat kind that runs one:

```json
{"id": "the-ambush", "kind": "fight", "fight": "warren-mouth",
 "when": {"near": "ash-warren", "within": 90},
 "lines": ["Something has been waiting at the mouth of it."],
 "on_win":  {"flags": ["mouth-cleared"], "gold": 120},
 "on_loss": {"flags": ["driven-off"], "journal": ["You were thrown back down the slope."]}}
```

`on_win` / `on_loss` are the point. A generated encounter is a thing that
happens to you; a beat that branches on its outcome is a thing the story is
about. Both take the ordinary M4 effects block, so nothing new has to be
learned to write one.

### The actual work, and why it is its own pass

The M5 runtime is polled and **never blocks** — rule 2 of
`core/mod/story_runtime.gd` is that it never asks the player anything, which is
what lets a beat fire, apply, and be done inside one `_check_story()` call. A
fight is the first beat that must *suspend*: the world screen has to put
`scenes/main.tscn` up, wait for it, and bring a result back.

That means:

- a new runtime state — "waiting on fight X, from beat Y" — which has to be in
  `to_dict()`, because a reload mid-fight must neither lose the beat nor re-fire
  it;
- `resolve_fight(beat, result)` on the runtime, applying `on_win`/`on_loss`;
- one more branch in `_check_story()`, next to the card, using the
  `_run_combat()` hand-off `world.gd` already has for lairs and bands;
- and a decision about what a *defeat* means, which the open world has never
  settled either (`world.gd`'s `_retreat()` soft landing was written for the
  linear campaign map — see "Not yet decided", above).

None of it is large. It is a new contract for the story layer rather than more
of the existing one, which is exactly why it was not bolted onto M5.

### Two rules it must keep

1. **One combat path.** A scripted fight still goes through
   `Encounter.build()` and the normal combat screen. A pack that could open its
   own fight screen is a pack that can ship a broken one.
2. **`scale_to_party` is the whole difficulty question.** Default `false`: the
   author's numbers are absolute, which is what makes a set-piece a set-piece.
   But an absolute fight is also how a pack hands a level-2 party an
   unwinnable wall — so the validator should price the roster with
   `Power.score()` against the band the trigger sits in (`Regions.at()`) and
   warn when they are a country apart. `true` keeps the numbers as a base and
   lets the scaler adjust, for an author who wants a named encounter that is
   still fair at any level.

### What the validator owes an author

All of it at scan time, like everything else in M1–M8:

- every monster id known — including the pack's own `bestiary.json` overlay,
  which the catalog has not loaded yet at validation time (`_own_item_ids()` in
  `registry.gd` already does this dance for item rewards; it wants a sibling);
- `theme` in `Encounter.THEMES`;
- every id in `features` present in `data/effects/features.json`;
- `count >= 1`, and `mult` inside the range `Scaler` itself uses
  (`MULT_MIN` 0.6 to `MULT_MAX` 2.5) — outside it the numbers stop meaning what
  the bestiary says they mean;
- **total foes within the board's capacity.** `Encounter.build()` falls back to
  `PARTY_STARTS[0]` when it runs out of spawn spots, which stacks every extra
  foe on top of the party's own start hex. Measured capacity, with a four-hero
  party: merchant-shop 15, frozen-cave 18, sunken-shrine 20, goblin-camp 22,
  city-square 22, forest-clearing 23. (Generated fights never hit this —
  `Scaler.MAX_FOES` is 8.)
- a `fight` id a beat references actually existing, and — worth a warning —
  every declared fight being referenced by something.

### Where else it plugs in

A story beat is the first customer, but the same `fights` block would serve two
others already in the code: `core/site.gd`, which builds a spec per lair room
(a pack naming its boss room's fight is the obvious second step), and the
`raid_settlement` quest kind. Neither should be in the first pass.

## CI — the suite runs on pull requests now (2026-09-14)

Nothing checked a branch before this. `release.yml` builds and publishes on a
push to master or a tag; a pull request ran nothing at all, so every "the suite
is green" in a PR description was a claim about somebody's laptop, unverifiable
by the person reading it.

**`tools/run_tests.sh`** is the whole suite in one command, and
`.github/workflows/tests.yml` runs exactly that on every pull request and every
push to master. The script rather than steps in the YAML is the point: a
contributor runs the identical thing locally, so local green and CI green are
the same claim rather than two similar ones.

Three things the script knows that a bare `for f in tests/*.gd` loop does not,
all three learned the hard way today:

1. **Assets must be imported first.** A script that preloads a texture cannot
   *compile* without `.godot/imported/`, so on a fresh checkout half the suite
   fails with parse errors that have nothing to do with any test. Godot's own
   `--import` is incremental, so running it every time costs nothing after the
   first.
2. **The verdict is the exit code, never the output.** Most tests print
   "N passed, M failed"; `test_bestiary.gd` prints `OK`; the drive robots each
   print a line of their own. All of them `quit(1)` on failure.
3. **A failed `assert()` hangs.** The SceneTree never reaches its `quit()`, so
   the process sits in the main loop forever — measured, not guessed. Every
   test therefore runs under `timeout`, and a timeout is reported as a failure
   rather than waited on.

**`tests/check_scripts.gd`** runs first: every `.gd` under `core/`, `scenes/`
and `tests/` is loaded and must compile (170 of them, ~3s). No test can do
this job — a test only compiles the scripts it happens to preload, so a parse
error in a file nothing imports, or in a screen no robot drives, survives a
green suite and is found by running the game. This session shipped exactly that
bug and caught it by accident; now it is a check.

The signal is `can_instantiate()`, **not** a null return: a script that fails to
parse still comes back from `load()` as a GDScript object, so the obvious
`if load(path) == null` check quietly passes everything. Verified by breaking a
file on purpose and watching the null check miss it.

Measured on this machine: the whole suite — import, script check, 64 subsystem
tests, 8 UI robots — is **177 seconds**. That is why the workflow is one job
and not a shard matrix; an earlier 30-minute figure turned out to be three
copies of the runner fighting each other for the CPU, not the suite.

## Five things play found (2026-09-14)

Five reports from actually playing the game, and what each one turned out to
be. Four were bugs; one was a design decision that had drifted into a bug.

### A created ranger vanished off the party page

The one that started as "where did my character go". The barracks is one JSON
file per character at `user://characters/<slug>.json`, and the slug was minted
by slugifying the name at the moment of saving. So a name is an identity, which
is wrong twice over: two heroes called Aria Vale are two heroes, and
`slugify()` is lossy besides — any two names built from the same letters and
punctuation collapse together, and a name with no ASCII letters in it at all
collapses to `character`.

Naming a second hero after one already in the barracks therefore did two silent
things at once. The new build was written **over** the existing one, so the
ranger already on disk was destroyed with no warning; and then `Party.add_member`
refused the new hero for carrying an id the roster already had — silently,
because the refusal was an ignored return value — so the hero you had just
built was not on the page either. One character deleted, one never created,
nothing on screen about either. Reproduced end to end through the real screens:
a ranger in the barracks, a hero built on the pack's party-setup page with the
same name, and afterwards the page still showed a ranger who was now a
barbarian on disk.

The fix is that a new character gets a slug nothing is using —
`CharacterSave.unique_slug()`, called once in the creator's `_confirm()`, so
Aria Vale and Aria Vale are `aria-vale` and `aria-vale-2` — and that the file
name is the identity: `load_slug()` now stamps the slug it loaded from onto the
character, so a hand-copied or renamed save cannot come back wearing somebody
else's id and get dropped. The creator says so when it has to number one. The
refused `add_member` is reported on the party screen rather than swallowed;
it should not be reachable any more, but a hero disappearing without a word is
what this whole entry is about.

### Shove → brazier worked with nothing to shove anyone into

"You can only put somebody in the fire if they are standing next to it" was a
rule of the *button*, not of the verb: `legal_target()` asked it, so the UI
never offered or accepted an illegal target, but `Combat.perform()` would take
the action, roll the contested Athletics, win it, and then quietly do nothing —
`act_shove` returned `{"success": true}` on an empty hazard lookup, without so
much as a line in the log. A turn gone and no explanation. The rule is now
`can_shove_into_hazard()`, asked in both places, and asked in `perform()`
*before* anything is spent.

### Slipping past lair guardians the party had already been fighting

`WorldLairs.sneak_past()` — the Animal Handling alternative to attacking a lair
— checked that the lair was discovered and unlooted, and nothing else. Its own
comment said "one attempt per lair" and world.gd's said "the guardians are
alerted either way now, so there's no third attempt", but neither was true: the
party could kick the door in, fight half-way down, withdraw, come back and then
*talk their way past the guardians they had been killing*, collecting the
sneak-past stash on top of the rooms they had already looted.

`alerted()` is the missing rule, and it needs no new state: `entered_at` is
already stamped the first time the party goes in (it is what starts the D1
window) and already round-trips through `core/world_save.gd`, so a lair that
has been disturbed reads as roused, including in saves written before this
existed. A failed attempt now rouses the lair itself rather than relying on the
fight it falls into, which is what makes it one attempt rather than one per
visit. The button hides once they are up, and says why if it is pressed anyway.

### Barks hidden behind the models

Same bug the HP bar and the odds chip were each fixed for, one tier further
down: a Figures3D model is a **Board child**, so it draws after everything
`Board._draw()` paints, whatever the order within that function. Barks sat
lower over their hex than either of the other two — right at a tall rig's chest
— so what a character said was routinely covered by whoever was standing in
front of them. They paint in `_draw_hud_overlay` now, on the CanvasLayer above
Board and every tier including the figures, with a dropped shadow since they
now land on top of the art rather than behind it. `tests/test_hud_layer.gd`
pins both halves: that `Board._draw` no longer paints them and the overlay
does, and that the two names the overlay reaches across for still exist.

### The ambush deployment, and the action bar that would not hold still

Two UI changes, both of them about the same thing: a control that moves under
the hand reaching for it.

**Deployment** offered one button per *pair* of heroes — six lines of
"Swap Vera ↔ Pike" at four heroes, fifteen at six, none of which say anything
about where on the board anybody is standing. It is a spatial choice, so it is
made on the board now: click a hero to pick them up, click another to trade
places. The swappable hexes are ringed, the held one brighter, and clicking the
held hero again puts them back. The bar still lists them, so the phase is
playable without the map and the robot can still drive it.

**The action bar** re-sorted itself live. `_prioritize()` ordered the badges
most-used-first and ran on every single rebuild, while `_bump_freq` counted
every press — so using a verb could promote it past another and slide every
badge to its right, mid-turn, under a player who was reaching for slot 3. On
top of that the bar was built from `available()`, which only returns what is
usable *this instant*, so spending a bonus action made a badge vanish and
everything after it shift left. The hotkeys are positional, so [3] genuinely
meant something different from one press to the next.

Both halves are fixed. `Combat.all_verbs()` is `available()` without the
can-they-afford-it-right-now filter (the structural half is now `is_button()`),
so the bar is laid out along a character's whole kit and a verb that is merely
spent holds its slot greyed out instead of collapsing the row. And the order is
settled once per character per fight: `_prioritize()` still decides that first
layout — the verbs this player reaches for still claim the low hotkeys — but it
decides it once, and `_bar_order` replays it for the rest of the fight. What
the frequency counter buys is the *next* fight's opening layout, which is all
it was ever really worth.

## Four more from play: loot, the save slot, the dead art, the sound (2026-09-14)

### Winning a fight left nothing on the field

`resolve_outcome()` has always returned a `loot` array, and both banking paths
— `core/campaign.gd`'s `finish_combat` and `scenes/world/world.gd`'s `_bank` —
have always stashed whatever is in it. It was always empty. The array was built
from one source: a monster's own hand-authored `loot` key, and **not one of the
316 entries in `data/bestiary.json` has one**. You could clear a bandit camp and
come away with gold, XP, and nothing you could hold.

`core/loot.gd` fills it, on two axes that are both "appropriate to what you just
killed" rather than a flat table:

- **Who it was decides what it was carrying.** `CARRIED` is keyed on the
  bestiary's `faction` (the axis `core/scaler.gd` builds rosters along) and
  falls back to `type`. A bandit is holding a shortsword and a leather jerkin; a
  goblin a scimitar and a shortbow; a wolf is holding nothing, because a wolf is
  holding nothing. Anything not in the table is a creature you loot rather than a
  person you rob, and its odds are halved — what turns up is what the last person
  it ate was carrying.
- **How dangerous it was decides how often, and how good.** A flat CR ramp
  (12% + 9%/CR, capped at 70%) on the odds, and a cumulative CR band on the
  quality: common under CR 3, uncommon to 6, rare to 9, very-rare above. A CR 10
  kill can still turn up a climbing potion; a CR 1/8 one cannot turn up a potion
  of speed. Past CR 8 a kill is searched twice.

Capped at three drops for the whole fight, because eight goblins should not come
to eight swords. Rolled on the fight's own RNG, so `SORCMERC_SEED` replays the
drops with the fight.

Every id it can hand back is a **real catalog id**. That is load-bearing rather
than tidy: the stash names an item with `Campaign.item_name()`, the shop pays
`Campaign.item_price()` and the rarity colour comes off `Icons.rarity_of()`, and
all three degrade silently — an invented `wolf-pelt` would show as "Wolf-pelt",
worth 0 gp, in common grey, and look like loot while behaving like litter.
`tests/test_loot.gd` checks every id in every hand-written table resolves.

One judgement call worth writing down: `potions-of-healing` sits in the
**uncommon** band rather than the obvious common one. The SRD files
healing/greater/superior under one heading, so its rarity is `varies`, and
`item_price` deliberately prices `varies` as rare — 2025 gp. Handing that over
for a CR 1/8 bandit is not a healing potion, it is a purse.

And it is said out loud in all three places a fight can end: the combat log
names what came off the bodies in its rarity colour, the linear run's journal
says it, and the open world puts it on the same label the lair outcomes use —
the fight log is gone by the time the map comes back, and loot that lands
silently in the stash is loot nobody knows they picked up.

### The autosave slot was invisible

There is exactly one open-world slot and it rolls. Fine, until you look at what
the title screen said about it: `▶ Resume the open world`. Nothing about what
you would be resuming, nothing about `✦ New run` being the thing that writes
over it, and no way to clear it short of deleting a file by hand.

`WorldSave.summary()` reads the slot's JSON without rebuilding a World — the
clock, the map it was built from, who was standing, the purse, the story pack if
there is one, and the file's own mtime. The title prints that under Resume,
says in as many words that there is one slot and a new run takes it, and offers
a Delete that goes through its own confirm screen naming what is about to be
lost (and what is not — the characters are in the barracks, which is a different
file).

### The art credits, and the art

Settings → Art credits listed every Liberated Pixel Cup author whose work went
into the composited sprite sheets. Except the sprite tier had been switched off
when the 3D figures landed (`USE_LPC_SPRITES := false`, "clashed against the 3D
foes") and had been dead ever since — so the screen credited art that is not in
the game.

Removing just the screen was the wrong half: the art was still in the repo and
still in every export, and CC-BY-SA 3.0 / OGA-BY require attribution for
distributing it, not for displaying it. So both halves went — `assets/lpc/`,
`assets/generated/`, `core/lpc_art.gd`, `Board._draw_sprite`, the
`tools/lpc_compose.py` pipeline, `LICENSES/`, the credits screen, and the tests
and shot scripts for all of it. Nothing changes visually, because nothing was
drawing it. The README's provenance table and `assets/figures/PROVENANCE.md`
lose the two rows that no longer describe anything.

### Sound effects

`tools/gen_audio.py` synthesizes all 39 assets offline out of the stdlib, and
that is what makes `assets/audio/` reproducible from source with no network, no
account and no bill. What it cannot do is sound like a recording — it is
oscillators and filters, and several of the stings read as exactly that.

`tools/gen_audio_elevenlabs.py` writes the same file names into the same
directories from the ElevenLabs sound-effects API instead, one sound at a time
(`--only hit,crit`), so the choice is per-sound rather than all-or-nothing: the
synthesized `click` is fine, the synthesized `hit` is not. Output is 16-bit mono
PCM at 44.1 kHz wrapped in a RIFF header, which `core/audio.gd` already handles
— it reads rate and channel count out of each file's `fmt ` chunk rather than
assuming them, so a mono generated file sits beside the synthesized stereo ones.

Two things it deliberately is not. It is not the default: `gen_audio.py` stays
the supported path and can rewrite any of these back. And it is not
deterministic — the same prompt is a different take every run — so the WAVs stay
committed and this is a tool you reach for when a sound needs replacing, never
part of a build.

The prompts describe the *sound*, not the game event: "a single heavy sword
strike landing on chain mail armor, dry, no reverb tail" is something a model has
heard; "hit.wav" is not. Lengths match what the game gives each sting room for,
since `core/audio.gd` fires them as one-shots over live combat.

**All 14 stings are now generated ones** — `assets/audio/sfx/` is the model's,
`assets/audio/music/` and `assets/audio/barks/` are still the synthesized set.
Three things had to be true before a take was drop-in, and none of them were:

1. **The API has a half-second floor** (`duration_seconds` under 0.5 is a 400)
   and overruns whatever it is given by about 2×. A UI click is a tick, not a
   second, so the request is floored and the result trimmed.
2. **Level.** `gen_audio.py` peak-normalizes every sting to 28480 (-1.2 dBFS),
   uniformly, all fourteen. The takes came back anywhere from 2944 to clipping
   at full scale — a tenfold spread, which dropped in unchanged would make some
   sounds inaudible next to their neighbours and others the loudest thing in the
   game. Matched to `gen_audio.py`'s own number rather than a new one, so the
   two sets mix.
3. **Silence.** Trimming is judged on RMS over a 10 ms window rather than per
   sample. The first usable click was over by 200 ms and carried one stray
   sample at 0.8% FS near the end — enough to defeat a per-sample scan and keep
   three quarters of a second of nothing. Window RMS ignores the stray and still
   catches a real decay tail. It took `click` from 0.96s to 0.18s.

And one take came back **silent** (peak 14 of 32767). That is why the tool
measures the peak and says `** silent take, re-run this one **` rather than
writing a dead file and reporting success: a generative API can hand you nothing
with a 200, and the only thing that catches it is looking at the samples.

### The moments that fired silently (2026-09-15)

Everything the game had a sound for fired when something *landed*. Twelve
moments that fired with no audio at all now have one, generated the same way:
a prompt in `tools/gen_audio_elevenlabs.py`, a synthesized recipe of the same
name in `tools/gen_audio.py`, so either tool can still write any id. **All
twelve committed WAVs are the generated takes**, like the 31 stings before
them; the synthesized recipes are the fallback, not what shipped.

All twelve came back usable on the first pass, which is worth recording
because the earlier batch did not: peaks landed between 23464 and 63957 — a
spread of nearly 9 dB, one of them clipping at full scale — and every one was
normalized to `gen_audio.py`'s 28480 so the set mixes with its neighbours.
Lengths came back at roughly 2× what was asked, as before, and trimming took
`quest_complete` from 4.00s to 2.44s and `shop` from 2.40s to 1.11s. `miss`
matters most here and landed at 0.66s — short enough to fire on every other
attack roll without queueing, which is what the half-second API floor and the
window-RMS trim exist to get.

`miss` / `miss_ranged` are the ones that change how a fight reads. A missed
attack was silent, which meant roughly half of all attack rolls resolved into
nothing and the only thing a player ever heard was their own successes — a
fight sounded like it was going better than it was. Misses split melee/ranged
and stop there, not nine ways like hits: what you hear when a blow lands is the
weapon meeting armour, which is what makes an axe and a mace different sounds;
what you hear when it misses is air, and air moved by an axe and a mace is the
same air. `WeaponSfx.for_miss()` is the classifier, same contract as
`for_attack()`. Both takes are deliberately quieter and shorter than `hit`.

`save_made` / `save_failed` are a pair, written to read against each other —
the same moment resolving two ways, bright and glancing off versus dull and
sinking. They fire only when there *was* a save to make; a no-save spell logs
"fails" through the same line and would otherwise get a second sting under
every magic missile.

`down` was `kill`'s asset until now, so a hero dropping sounded exactly like a
foe dying and a party wipe sounded like a victory. Same armour and body, softer
attack, no sub-bass crash: it settles rather than stops.

`condition` fires only on a status that is actually new. Concentration spells
re-apply their status every round to refresh the duration, and a sting on each
refresh would put a buzz under every round of a running Hold Person.

The rest: `burst` (an explosive barrel), `collapse` (exhaustion's last level),
and four for the world between fights — `travel`, `settlement`, `shop`, and
`quest_complete`, which resolves where accepting a quest only reaches. Arrival
at a node picks exactly one sting rather than stacking them, because two
one-shots on the same frame read as one muddy noise rather than two events.

One thing this forced in `core/audio.gd`, and it is the reason the new stings
are safe to fire where they fire: **a sound will not restart within 50 ms of
itself**. An area spell resolves a save per target and a condition per target in
one frame, so a fireball catching five bodies fired five copies of the same
sample on the same frame — phasey, five times as loud, and loud enough to drown
the cast it was answering. The floor is per sound rather than global (a miss and
a hit landing together are still two events) and far shorter than the gap
between two things a player reads as separate, since a second attack is turns or
animation away. `_should_play()` is split out of `_play_one_shot()` so the rule
is testable: headless never builds a voice pool, so the caller cannot run under
the suite at all.

`tools/gen_audio.py` grew `--only`, the same spelling its sibling already had,
and it is load-bearing now rather than a convenience: `assets/audio/` is a
**mixed** set — the stings are the ElevenLabs tool's, the beds and barks are
the synthesized ones — so a bare `gen_audio.py sfx` would quietly overwrite 31
generated takes with their synthesized versions. A bare name is matched across
every group and must be unambiguous, because `settlement` is now both a sting
and a bed; `sfx/settlement` says which.

## Spike — hex distances, spell ranges, ranged↔melee (2026-09-15, measurement only)

Full write-up in `docs/spike-hex-ranges.md`; tooling `tests/sweep_range_detail.gd`
(throwaway). Headlines: `RANGE_CAP` 6/8/10/12 and "spells uncapped" are
byte-identical on current boards (nobody ever shoots past 7 hexes);
`FT_PER_HEX` only rescales the party because the bestiary is hex-native
(FT 5 = +10.7 win-rate points, all from a 3-hex Burning Hands and speed 6);
29 of 53 castable spells have no authored `range_ft` and default to touch
(Hold Person, Web, Hypnotic Pattern…). Recommendation: author the 29 ranges
first, then decide whether range is a 3-tier grammar (cap 5) or needs bigger
boards + a `_foe_spots` fix — no more constant sweeps until that's chosen.

## The open bug reports, worked through (2026-09-16)

Nine issues filed from the in-game reporter over one play session, plus two
follow-up asks. One commit and one test each; the tests all fail against the
code as it was. What each one actually turned out to be:

**#24, "berserker rage needs twice keyboard press"** — it needed four. Rage
burns a pool so it wears the two-press confirm guard `_costly()` puts on every
costly verb, and the guard was right; where it put the second press was not.
Arming rebuilt the MAIN BAR, and Rage lives one level down in the `[3]` Bonus
submenu (a barbarian has two bonus-cost things, Rage and Reckless Attack, so
that slot is a list rather than a straight fire). First press armed Rage and
dropped the player onto a bar with no confirm anywhere on it — second press of
the same key swung the greataxe. 3-1-3-1. The fix is structural: a page's
entries are re-derived on every render (`_menu_entries()`, the old
`_build_hero_menu`'s first half) instead of being carried in the button's
binding, so `_refresh_menu()` can rebuild whichever page is open — main bar,
slot list, or spell tier picker — from what is true after arming.

**#25 / #26, Esc and space on the map** — every other screen answers those two
keys and the open world answered neither, so Settings mid-run meant going back
to the title and losing the map. Esc backs out of whatever light panel is up
and otherwise opens a pause menu; space is the Pause button. The menu holds the
clock the way a market visit does and refuses to open over anything that
already owns the screen.

**#28, "quests page has verticality issue"** — a `ScrollContainer` hands its
child the child's MINIMUM size on any axis it can still scroll, and an
autowrapping `Label`'s minimum width is one pixel. Every quest line measured
1px wide and ~570px tall: eight quests, 4096px of scroll, for text that fits in
eight lines. Horizontal scrolling off is what makes the column stretch to the
container's width and the labels wrap at it. Four lists in `world.gd` were
built this way and now share `_scroll_column()`.

**#33, "quest complete screen stretches and overflows"** — the other end of the
same rope, and a regression #28's fix would otherwise have introduced: with
horizontal scrolling off, a row's own minimum width reaches the panel instead
of being scrolled past, and `_trade_row`'s label had no wrapping, so one long
job title took the settlement counter to 717px where 468 was meant to be. The
floating panels also placed themselves by arithmetic against a size they were
told to expect and then measured whatever they came to; they sit in
`CenterContainer`s now, and a page's list takes the height the window can spare.

**#29** — the turn strip borders every tile the current aim lands on. For a
cone or a burst, which NAMES are standing in the shape is exactly what the
strip knows and the board does not spell out.

**#30, "no loot page"** — the combat screen writes its own after-action lines,
but out on the map it is torn down the frame its `result` is filled, so nobody
ever read them; the linear campaign never had the problem because it holds the
fight screen up behind "Back to the road". The map's version is a page of its
own, since the map has a delve to summarise as well as a single fight: a delve
totals the whole descent and reads its gold off the purse, because a site pays
from room caches, the boss hoard and the fights themselves and only the purse
sees all three.

**#27** — roster rows carry equipped gear and trained skills (best first,
expertise marked) out of `Party.summary()`, so comparing two characters no
longer means opening both sheets. And the roster reshuffled anywhere: the
screen takes a `roster_locked` flag from whoever opens it, so the HUD button
opens it locked and the inn's "Sort out the party" opens it unlocked. The lock
covers benching, recruiting and Create new and nothing else — marching order is
a travel decision, and travel is what you are doing out there.

**#31, the frame-rate drop** — three things, all per cell, per frame, for
answers that do not change per frame. `_draw_ground()` walked every cell of the
VIEWPORT and asked `world.is_explored()` about each one (3.7µs a cell measured,
since that folds in a scan of every settlement), then recomputed each surviving
cell's tile through `world.water_depth()`, another linear scan, at 4.8µs. It
walks the explored ground now — out from each remembered waypoint and each
settlement beacon, clipped to the viewport and memoised on the cell box plus
the trail's length — which reaches exactly the set `is_explored()` would have
said yes to, from the other end. Unexplored cells are one rect for the whole
viewport rather than one each, and the tile pick is cached.

Measured on a large map with a party a good way into a run (900 reveals, 32
waypoints), at the viewport the game actually uses, cold — the memo defeated
on every iteration, so this is the worst case rather than the steady state:

| zoom | viewport cells | painted | before | after |
|---|---|---|---|---|
| 2.00 | 3,575 | 2,617 | 31.3 ms | **4.0 ms** |
| 1.00 | 13,843 | 6,502 | 96.6 ms | **9.4 ms** |
| 0.50 | 54,901 | 7,450 | 4.8 ms (nothing painted) | **8.7 ms** |
| 0.25 | 217,655 | 7,450 | 19.1 ms (nothing painted) | **8.4 ms** |

The `ponytail` note in that function predicted the whole thing ("a spatial
grid is the upgrade if a very long walk makes it drag").

**A correction, recorded because it was published before it was checked.** The
first version of this entry, and of PR #32's description, claimed the reporter's
3840×2118 window tripped `MAX_CELLS` at zoom 1.0 and painted the map as one
flat green rectangle, and guessed that this was what #23 ("overworld tiles
bad") was seeing. That is **wrong**, and the mistake was measuring
`_draw_ground()` against a hand-set `size = Vector2(3840, 2118)` rather than
against what the screen reports. The project stretches `canvas_items`, so the
Control's logical size stays around 1280×800 whatever the window is — 8,455
viewport cells at zoom 1.0 on a 4K window, comfortably under the cap. Rendering
master at 3840×2118 paints its tiles perfectly well, and no zoom reproduced a
flat fill on screen. #23 is still unexplained, and this branch should not be
read as fixing it. What survives is the table above: the per-frame cost, at the
viewport the game really has, is roughly a tenth of what it was.

### Two asks alongside them

**A testing pace for the unlock ladder.** Every `SPECIES_COST` / `CLASS_COST` /
`SUBCLASS_COST` threshold is cut so the ladder can be walked in one sitting —
about one unlock per three fights. The pace is measured rather than guessed: a
fight pays `power * XP_PER_POWER`, which resolves to 55–190 at levels 1–3 and
500–720 by level 12, so a species step is 450 and a class step is 1500. Order
and shape are untouched. This is TEMPORARY and says so: the header carries the
shipping numbers verbatim and `tests/test_progression.gd` pins the claim, so
putting the real ones back is a red test rather than a silent balance change.

**Clearing a lair pays.** Every room on the way down already paid its own XP,
but reaching the bottom paid nothing, which made a delve worth strictly less
than the same number of fights out on the road — the wrong way round for the
one piece of content you commit to blind. `Site.clear_xp()` is flat and scaled
by depth the way the boss hoard beside it is. Only on a clear; withdrawing
keeps what the rooms paid and nothing else.

**A lair does not stay empty.** A spent lair used to sit grey for the rest of
the run — five lairs, five clears, nothing left underground. One in-game day
after it is emptied (however: fought to the bottom, talked past, or resolved
without the party while `WINDOW` ran out) something moves back in. The party
keeps knowing WHERE it is; the rooms they cleared, the clock that was running
and whether the guardians are awake all start over. Every "this is spent" stamp
goes through `WorldLairs.mark_cleared()` so the clock cannot be started in one
place and forgotten in another, and an old save with no stamp stays spent
rather than repopulating on load.

**Weight in the combat animations.** The reported feel was "like they are in
fast mode", and the reported question was which setting would help. The answer
was none: `anim_speed_multiplier` was floored at 1.0 both on load and in
`anim()`, so the only thing the dial could ever do was make the fight quicker.
Both halves are fixed. The setting turns both ways now (`ANIM_MIN` 0.4 to
`ANIM_MAX` 3.0, with `FAST` passing through as a real stored choice), the
checkbox is a five-way pace picker — Weighty / Measured / Normal / Brisk /
Instant — and `SORCMERC_FAST` still wins outright so the headless suite cannot
be slowed by whatever `settings.json` is on the machine.

The animations themselves carry weight at 1x, which is the part that does not
need a setting. Token movement was exponential smoothing at a fixed rate,
`cur.lerp(target, dt * 12)`, which has no idea how far the token is going — a
six-hex dash and a one-hex sidestep both took about a quarter of a second — and
starts at full speed and creeps into the destination, the exact opposite of how
something with mass moves. A token crosses the board at a speed measured in
HEXES now, smoothstepped, clamped between `STEP_MIN` and `STEP_MAX`. `FX_TTL`
went up across the board (melee 0.30 → 0.46; at 0.30 a swing was over before
the eye found it, which is most of the "fast mode" reading), the melee
step-in's curve is skewed to strike out fast and recover slow instead of
`sin(t * PI)`'s symmetric nudge, and the beat before a monster acts went 0.5 →
0.75 so the last swing is off screen before the next turn starts.

## Cover you can see, and benching where you are looking (2026-09-16)

Two asks off the back of playing the branch.

**Cover in the combat map should be more obvious.** Half cover is +2 AC and +2
on Dex saves (`core/combat.gd`'s `effective_ac` and `_saving_throw`) — the
difference between a 55% swing against you and a 45% one, and the reason to
spend a move getting into it. It was announced by a slab two shades off the
ordinary floor (`2a3a3a` against a `COL_HEX` that is barely different) and the
word "cover" in 10px grey-teal at the bottom-LEFT corner of the hex — under the
foliage that always grows on a cover hex, over a textured floor, at whatever
zoom the board happened to auto-fit to. On the Sunken Shrine that is
`hex_px = 15.3`: the label was smaller than the plant standing on top of it.

Cover says it twice now. A rim around the tile in `COL_COVER_EDGE`, a teal
nothing else on the board wears (the test asserts the distance from every other
board colour, so it cannot quietly drift into meaning "selected"), with a faint
inner line so it reads as the lip of something rather than as a selection
outline. And a chip carrying **the number** rather than the noun — `+2`, on a
dark backing plate, because it lands on a textured floor with a plant on it and
without one it is legible on some tiles and not others. The chip scales with
the hex and drops out below 10px; the rim does not, so zooming out loses the
value and keeps the shape, which is the right way round — at board scale you
want to see WHERE the cover is, and close up you want to know what it is worth.

`tests/test_cover_readable.gd` cannot look at a picture, so it checks what is
decidable: the palette really is distinct, the chip states the number the
engine actually applies (it moves a combatant onto a cover hex and compares
`effective_ac`), and the rim is thicker than an ordinary hex seam.

**Clicking somebody who is marching benches them.** The roster column on the
left has always had a Bench button per row. The marching order on the right —
the side of the screen you are actually looking at when you decide somebody
should sit this one out — had no way to do it, so the move was to look away,
find that person's row again on the left, and press the button there.

A marching slot with nothing picked up is now that person, and clicking them
takes them out of the line. With somebody picked up it still places or swaps
them, so the old interaction is untouched; the bench click is the
no-selection case. It respects issue #27's inn lock like every other way of
benching, the tooltip says which of the two things the click will do, and the
hint line leads with it.

## D3.1 — eight more road events, and the gates that keep them honest (2026-09-16)

D3 shipped the road with six events on it. Six was enough to settle the
question it was built to answer — a map with something on it beats a corridor
between menus, and a clock that stops for it beats a fast-forward that skips
the game. It was not enough to ride for an evening. At one roll per six
world-hours the table came round inside a single crossing, and the second time
a stream ran wrong in the same afternoon the card stopped being news.

`core/travel.gd` now carries fourteen. Both of D3's rules are untouched:
standing orders are still set once on the party screen, and an event still
resolves itself against the orders already standing rather than stopping to ask
anything. What changed is how much road there is between repeats, what the road
asks for, and what it deals.

**What it asks for.** The six originals rolled Survival, Perception,
Persuasion, Insight, Investigation and Medicine. Everything else on a sheet —
Athletics, History, Religion, Nature, Animal Handling, and the two lying
skills — was dead weight the moment a fight ended. Each of the eight new events
is anchored on one of those: a ford that wants Athletics, a waystone that wants
History, a crossroads shrine that wants Religion, a storm that wants Nature, a
carter's spooked team that wants Animal Handling, and a toll post that will
take Intimidation, Deception or Persuasion, whichever the party is best at.

**What it deals.** D3's events could cost time, cost HP, pay gold, or reveal a
lair. These add four more payoffs, one event each so that none of them is a
reskin of another: a wound taken off at the shrine (a share of max HP, to
everyone still standing — never the dead, because a shrine by the road must not
look like a cheaper resurrection), gear lost to a river, coin lost at a toll
post, plain sellable salvage out of a dead company's wreck, and goodwill with
the locals' faction for pulling a cart out of a ditch — the one road event whose
payoff is not on the party sheet at all, and the only place `FactionOpinion`
moves outside a town.

**The gates.** A card nobody can argue with had better not describe a world the
player can see is not there. Two optional keys on an event decline the roll
instead:

| key | what it gates on | why |
|---|---|---|
| `bands` | the D6 country underfoot (`core/regions.gd`) | nobody is manning a toll post in the Far Deeps; nobody's company lies dead on a farm road |
| `needs` | a state of the party or the map | the shrine only comes up when somebody is actually hurt; the carter only when there are locals whose goodwill is worth something |

An unknown `needs` fails closed — a requirement this version does not
understand is a card it must not show. A world too small to band, or one with
no player on it (a test harness, a save mid-load), drops the band gate rather
than the event.

**Sizes.** Everything on this table stays small on purpose: a road event is
something that happened between two places, not a fight and not a reward node.
A storm sat out costs less than the worst ground (180 world-minutes against
240); the old straight road hands back more than a clear day does (120 against 90,
because clear running asks for no check at all); the snare's toll is under the
bad water's;
and the `maxi(1, ...)` floor that has always kept foul water from dropping
anybody is now shared by every HP cost on the table, because there is no fight
out there to drop somebody in and nobody to pick them back up. A toll takes
what is in the purse and never more, and says so on the card when the purse
would not cover it.

**The card.** `scenes/world/event_card.gd` grew chips for the new payoffs
(healing, salvage, and who heard about a favour) and — the one fix that was not
new work — gold now renders signed. D4's parley toll has always passed a
negative gold through this card, and the card has always drawn it as
`+-40 gold`. The skill on the roll line is read off the catalog rather than
`capitalize()`d, which is the difference between "Animal Handling" and
"Animalhandling".

`tests/test_travel.gd` pins the gates in both directions (no toll posts in the
deeps, no wrecks in the heartland, no shrines for a party at full HP), the four
new payoffs, and the invariants: the purse never goes negative, the healing
never goes past full, the dead stay dead, and nothing on the road drops
anybody. Two of those tests replay a known seed onto a party in a known state
rather than searching with the party under test — a search spends and earns as
it goes, so by the time it finds a failed toll the purse it was told to empty
has been paid twice over by wayfarers.

## Spike — opinions between party members, and romance (2026-09-16, feasibility)

Full write-up in `docs/spike-party-opinions.md`; model `core/party_opinion.gd`
(plus one `relations` field on `core/party.gd`), test
`tests/test_party_opinion.gd`, throwaway sweep `tests/sweep_party_opinion.gd`.
Nothing in the shipped game calls it. Headlines: every companion is
player-made, so the shape is Wildermyth's (a symmetric score per pair that
drifts toward a baseline read off the two sheets, labelled by band, told in
one-line camp beats), not BioWare's; romance is a camp beat that ASKS through
D4's options card, never a roll, one partner at a time, declined is
remembered. The road is where it pays — a morale point beside the pace bonus
on every D3 check, and the roll feeding back into who the party likes. The
three combat effects at 5e-honest sizes (+1 AC bonded and adjacent, -1 to hit
rivals adjacent, advantage when a partner falls) are all inside the sweep's
±2.7-point noise: a rally every other fight is a moment, not a balance
change. The healer–faller pair bonds too fast at +12 a save (Ilsa+Pike +5.3
per fight); cap saves once per fight before wiring anything. Side finding:
Help's advantage is erased by the ally's own `new_turn()` before it can be
spent — pre-existing, one line, its own PR.

**Appendix A (same doc, added the same day)** — what Darkest Dungeon and its
neighbours do about opinionated characters, and specifically about
uncontrollable actions, which the spike above does not touch. DD1 turns out to
have no relationships at all (stress, a resolve test at 100, nine afflictions
that refuse a command at 33% and act out at ~30-42%; attacking an ally peaks
at 8.3%, and the 6-stress barks make it a contagion model). DD2 is the pair
system: affinity 0-20 from 9, symmetric, resolving into a named relationship
as a chance rather than at a threshold, read off combat behaviour the player
was going to choose anyway, and its control loss force-equips a cursed skill
rather than seizing a turn. Then Wildermyth, RimWorld, Battle Brothers, XCOM 2
bonds, Fire Emblem and Jagged Alliance 2, with a shape table.

Two findings argue against decisions this spike already made, which is the
point of having run it. Rivalry as a combat penalty is the minority
position — Wildermyth, whose characters are player-made like ours, makes
rivalry a damage buff and has no negative relationship state at all — so
`bicker_penalty` should probably be a different bonus, not a malus. And
symmetric storage was the easy call: the two games that model opinion rather
than a bond, RimWorld and Jagged Alliance 2, both went directed, and JA2 buys
a rule ours cannot express (one hated teammate floors the whole squad's
reading). That is a save-format decision, so now or never.

What transfers, in order: DD2's behavioural inputs, Fire Emblem's
affinity-sum-times-rank at a hex radius (one line, and it makes positioning
the expression of the relationship), XCOM's Stand By Me so the relationship
is the CURE for a condition and not only its cause, the cursed-skill shape as
rivals losing the cooperative verbs, DD1's and JA2's town-and-camp control
loss on our inn costs and standing orders, Battle Brothers' mood-caps-morale
coupling, and JA2's learn-to-hate timers as the bridge between authored and
simulated. What does not: a second stress resource, contagion, RimWorld's
real-time social tick, any break that seizes a whole turn, recruitable
children, and anything that can remove or kill a character the player built.
5e's own answer to control loss is a saving throw, and
`data/effects/conditions.json` plus `apply_condition()` already express every
DD act-out category as a condition with a source and a repeat save.
