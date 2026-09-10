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

## Post-T5+T9 gap survey (for later, not all queued)

Asked-for survey of what's still missing for a full-scale CRPG, beyond the T10
items above: bestiary (316 monsters) not wired into the scaler yet, no per-node
combat terrain variety (one hand-authored room), no equip-from-stash link on
the profile screen, no multiclassing, no meta-progression across runs (open
question, not decided), no map variety beyond the one 5-stage route, no
narrative/dialogue layer (quests are mechanical only), no settings/options
screen, no tutorial/onboarding, no magic-item identify mechanic (fine to skip),
status effects stay combat's flag set only (no poison/disease/long-term
conditions). Sound/art remain deliberately deferred.

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

This is a multi-week build; phases 0–1 are the critical path and land first.
