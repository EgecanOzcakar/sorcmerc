---
name: sorcmerc-balancing
description: SorcMerc's stat set, combat formulas, spell-slot economy, encounter-difficulty model and balance targets, plus the sweep discipline for changing any tuned number. Use before touching a tuned constant (TIER, CURVE, FT_PER_HEX, rest costs, XP/gold per power, region bands), when judging whether a mechanic is too strong or cheap, or when adding a class, spell, monster or feature mechanic. Project-specific only.
---

# SorcMerc balancing

The rules are **D&D 5e 2024 (SRD) on a hex board**, not a bespoke stat model. Fairness is measured as **seeded win rates**, not hand-computed hit tables. Every number below links to the file that owns it, and that file's header comment holds the latest measurement. **Read the header before quoting a number.** These headers are re-measured often, and this skill may be behind them.

## Stat set

- **Heroes** use the 5e sheet, resolved by `core/rules/resolve.gd` into `Resolved`. It has:
  - the six abilities (STR, DEX, CON, INT, WIS, CHA), proficiency bonus, AC, max HP (hit die per class) and saving throws;
  - skills, speed in feet and initiative (d20 + DEX mod);
  - resource pools (Rage, Second Wind, Channel Divinity and so on) and spell slots.
- **Monsters** are `data/bestiary.json` entries (316 of them): `ac`, `max_hp`, `init_mod`, `speed`, `atk_bonus`, `damage`, `saves`, `abilities`, `resist`/`immune`/`vulnerable`/`cond_immune`, `features`, `cr` and `xp`, each tagged with `faction` and `habitat`.
- **Conditions** are the 15 official ones (`data/effects/conditions.json`) plus the engine-only states in `combat.gd` `ENGINE_CONDS`: dodging, hidden, helped, reckless, sapped and slowed. Exhaustion exists, and a long rest clears one level.
- Fatigue, Resolve, Melee/Ranged Skill and Melee/Ranged Defense **don't exist**. The nearest things are AC (defence), attack bonus = proficiency + ability mod (skill), and party opinion/"morale" (`core/party_opinion.gd`), which only touches travel checks and in-fight bonds. It is not a per-merc stat.

## Core formulas (`core/combat.gd`, `core/dice.gd`)

- **Attack:** `d20 + to_hit_bonus(attacker, target)` against `effective_ac(target)`.
  - A natural 20, or anything in `crit_range`, is a crit and always hits. A natural 1 always misses.
  - So an unmodified roll is bounded at 5%/95%. That comes from the dice, not from a clamp. Advantage and disadvantage (2d20, higher or lower) push past both bounds.
- **Crits** double the damage dice, Smite dice included.
- **Board modifiers:**
  - half cover gives +2 AC, and applies to DEX saves only (fixed to RAW 2026-09-24);
  - attacking a target below you gives +2 to hit (`HIGH_GROUND_HIT`, a sorcmerc rule);
  - climbing one level costs one extra movement, and a rise of two levels or more is an impassable cliff (`core/hex.gd`).
- **Spells:** save DC = 8 + PB + casting mod, and spell attack = PB + casting mod (`core/rules/pass_spells.gd`).
- **Distance:** `FT_PER_HEX = 6`, so a 30 ft move is 5 hexes, and ranged attacks are capped at 12 hexes (`core/adapter.gd`). Both are calibration knobs.
- **Death saves** follow RAW: three successes leave a hero stable but down, not back up.

## Spell slots

- **Counts per class and level:** the 2024 tables live in `data/classes.json` (`spellSlots`, `pactMagic`). Eldritch Knight and Arcane Trickster use `data/third-caster-slots.json`.
- **Full casters** are the bard, cleric, druid, sorcerer and wizard. They have 2 slots at level 1, `[4,2]` at level 3 and `[4,3,2]` at level 5.
- **Half casters** are the paladin and ranger. They have 2 slots at level 1 and level 2, 3 at level 3 and `[4,2]` at level 5, as the 2024 PHB does. The export had none at level 1; that gap was fixed 2026-09-24 (`tools/fill_levels.py`; build log "Paladins and rangers cast from level 1").
- **The warlock** has Pact Magic: 1 slot of level 1 at warlock level 1, and 2 slots of level 3 at level 5. All pact slots are one level.
- **Slots have levels 1–9.** Leveled spells can be upcast. Cantrips are free.
- **Multiclass** casters read one class's table, not the 2024 caster-level sum. There is a `ponytail:` note on this in `pass_spells.gd`.
- **Refills** (`Adapter.rest`, `core/settlement_visit.gd`):
  - A **long rest** restores all slots, all pools and full HP. It is allowed at most once per 1440 in-game minutes, costs 480 minutes of clock plus the inn fee or a camp kit, and is unavailable inside a site.
  - A **short rest** restores short-rest pools and half the missing HP. It also restores **warlock slots**. The limit is 2 per long rest, 60 minutes each. An elf's **Trance** banks one more at each long rest, good for 24 hours, taken first and not counted against the 2 (`core/trance.gd`).
  - **Arcane Recovery** gives ceil(wizard level / 2) slot levels back, none above 5th, once per long rest, automatically at the first short rest that finds a slot spent, highest levels first (`Adapter.arcane_recovery_auto`).
  - A long rest's 480 minutes are stepped through the world (`core/world_rest.gd`); downtime's last night refills only if the 1440-minute gate allows. A slot spent on **Rope Trick** or **Alarm** stays spent through the rest of the camp it pays for (`party.camp_holds`).
  - The **linear campaign** allows 2 short rests and 1 long rest per *run* (`core/campaign.gd`).
  - Slots **don't** refill between fights (`Adapter.write_back`).
- **Enemies have no slots.** Their magic is limited-use features in `data/effects/features.json`, for example `monster-innate-bolt` (3d6, DEX save for half, 2 uses) and breath weapons (4d6, 1 use).

## Encounter difficulty

Difficulty is a product of **independent multipliers**, each answering its own question. Don't collapse them into one knob (see `scenes/world/world.gd` `encounter_spec()`):
- **`Scaler.roster_for()`** sets the power budget (`core/scaler.gd`).
  - The budget is `TIER[difficulty]`, currently easy 0.56, normal 0.66 and hard 0.76, times party power raised to `CURVE` 1.15, against `REF_SCORE` 46.6 (the level-3 preset party).
  - The budget buys **body count first**, up to `MAX_FOES` 8 drawn from one faction. A stat `mult` in the range 0.6–2.5 closes whatever gap is left.
  - Party power comes from `core/rules/power.gd`. It reads max HP, not current HP, so remaining slots are the only part of a hero's condition it sees.
- **`WorldThreat.assess(party)`** handles the party's condition. Its wounds curve only ever scales **down**, and open country defaults to "easy". Its `slot_hold` multiplies back out whatever the party's spent slots took off the budget, so only wounds thin a fight.
- **`Regions.power_scale(world, pos, party)`** clamps the fight to the country's level range.
- **Payout follows the roster:** `XP_PER_POWER` is 4.0 and `GOLD_PER_POWER` is 0.6 (`core/encounter.gd`). A smaller fight pays less without extra code. Don't add a separate penalty; it would count twice.

## Balance targets (enforced by tests)

| Target | Value | Where |
|---|---|---|
| Win rate: easy / normal / hard, level-3 presets | **95 / 85 / 75%, each ±10** | `tests/test_scaler.gd` `TARGET`, `BAND` |
| Boss win rate | 15–85% | `test_scaler.gd` `BOSS_BAND` |
| Latest measured (2026-09-24, current autopilot) | 96.5 / 93.0 / 81.5%, about 4 foes (the old autopilot read 96.5 / 90.0 / 79.5) | `core/scaler.gd` header, "RE-MEASURED 2026-09-24: the RULER moved" |
| Fight length, level 3 | about 7–8 rounds (level 8 about 9.6). **Old-autopilot measurements** (the 2026-09-15 retune; level 8 from T-classes-b), not re-measured since the autopilot spends its whole turn | `core/scaler.gd` header |
| Within the party's band, easy | 93.8–100% at every level 3–15 (the ruler party, new autopilot); a built level-10 party: 73.3% (old autopilot) | `core/regions.gd` header |
| One band too deep | level 3 in the Marches: 28.8% (new autopilot; 17.5% under the old); in the Deeps: 2.5% | `core/regions.gd` header |

- Nothing sets a target for early hit rate or for hits-to-kill. The chat's proposed targets (55–70% early hit rate, 3–5 rounds, 3–4 hits to kill) are **not** in the code. Measured fights run longer than 3–5 rounds, and the original MVP brief aimed for 6–15.
- If you want those metrics, add them to a sweep as measurements before turning them into targets.
- What moves win rates most is **action economy** (how many turns each side gets), not any single stat line (`scaler.gd` header). Tougher monsters get priced up, so a hard budget buys fewer bodies.

## Changing a tuned number

1. Numbers in comments are **measured**. The comment names the sweep that produced them, in capitals: `MEASURED`, `RE-MEASURED <date>`, `TUNING`. Changing one is a balance pass, never an eyeballed edit.
2. **Pin the seed** in the fight spec (`spec["seed"]`). An unpinned sweep has already produced a false result once (the "bimodal factions" episode in the `scaler.gd` header).
3. Use **200 seeds per point**, which gives a standard error of about 3 points. Treat moves inside about 1.5 SE as noise.
4. Run the sweep **back to back on master and on your branch**, and quote both columns. A number measured against an older base can credit your change with someone else's work.
5. Prefer fixing the rule over re-tuning `TIER`: "a retune for rules that are now right would only be undone by the next rule that is."
6. Sweep harnesses: `tests/test_scaler.gd`, `tests/sweep_tier.gd`, `tests/sweep_site_depth.gd`, `tests/sweep_built.gd`, `tests/sweep_range_detail.gd`. Set `SORCMERC_SEED` to replay one fight.
7. Write the new measurement into the owning file's header and add a build-log entry: a new file in `docs/plan/` (`docs/plan/README.md`), never an append to `docs/expansion-plan.md`.

## Decided 2026-09-24 (owner's calls, not yet built)

Each of these is a balance change. Build each one with a re-run sweep and quote master against the branch.

- **The ruler spends its whole turn (built 2026-09-24).** The party autopilot (`core/ai.gd` `_party_auto`) swings every attack the economy holds and spends a Bonus Action wherever one is reasonable (`_bonus_after`; `tests/test_autopilot.gd`). Every sweep measures with it. Before, it wasted Extra Attack, so every level-5+ measurement read a party weaker than anyone plays and fights looked harder than their targets: level-8 hard went 58.7% → 79.3% (target 75) with no knob moved. Re-measured the same day with `sweep_regions`' in-band curve: 93.8–100% at easy from level 3 to 15, on target everywhere, so no knob moved. Quote numbers taken before 2026-09-24 as old-ruler numbers.

- **Slot tables stay 2024 RAW — built 2026-09-24.** The export's one data gap is fixed: paladin and ranger get 2 level-1 slots, as the 2024 PHB does (`data/classes.json`; build log "Paladins and rangers cast from level 1").
- **Built: the open world stops pricing spent slots.** `WorldThreat.slot_hold()` sizes a road fight off the party **with every slot back**, as `core/site.gd` already did for sites, and wounds still thin it. Measured with `tests/sweep_spent_slots.gd` (level-3 presets, easy, 200 seeds): a party with no slots left went from 3.3 foes and 100% wins to 4.0 foes and 94.5%. At 50% HP it went from 99.5% to 90.0%. A fresh party is unchanged at 99.5%.
- **Sorcerer features follow 2024 RAW.** Built so far: Innate Sorcery (+1 spell DC, Advantage on spell attacks, 2/long rest) and Font of Magic (slots ↔ sorcery points; made slots persist as negative `slots_used` until a long rest). `power.gd` prices neither. `tests/sweep_sorcerer.gd` measures them at about zero win-rate effect under the autopilot (level 3: 89.5 → 88.5%, level 10: 96.5 → 96.5%). Metamagic (five options) is built and also unpriced; the autopilot never arms it, so no sweep sees it. Price it if a sweep that arms it measures above noise.
- **Enemy casters: built, partly shipped.** The cult fanatic, priest and mage have real slots (`core/enemy_casters.gd`). Foes' area spells are priced against the party's size (`Power.area_targets`), and a caster's highest spell level follows the band (Heartland/Marches 2nd, Frontier 3rd, Deeps any). The ruler still misprices glass cannons (`sqrt(dpr×ehp)` plus the `ROUNDS` cap). So casters are fielded only from the Frontier tier up (the cult's lair boss: level 8 72.7 → 60.0%), and the warband roll ships at 0%. See `tests/sweep_caster.gd` and `tests/sweep_caster_boss.gd`.
- **Armor stays 5e AC.** No damage reduction and no armor HP.
- **Hired mercs** come with class, species, background and scores fixed; the player keeps subclass, spells and level-up choices. Recommended (not yet decided): pre-roll their scores within the creator's point-buy/standard-array budget, so a hire is never stronger than a built hero at the same level.

## Open questions

- None outstanding from the 2026-09-24 pass.
