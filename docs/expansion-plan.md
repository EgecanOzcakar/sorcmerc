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
camera-facing-ball look. Camera: drag pans, wheel zooms about the cursor
(0.25-2.5x clamped), right-click sets the player's goal (goal ringed gold),
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

This is a multi-week build; phases 0–1 are the critical path and land first.
