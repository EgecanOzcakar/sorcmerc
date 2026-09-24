# A design audit against the bible (2026-09-24)

Read-only. The yardstick is the `sorcmerc-design-bible` and `sorcmerc-balancing`
skills; the method is the usual game-design lenses (meaningful choice,
dominant strategies, risk against reward, sources against sinks, attachment,
legibility). Seven passes went over the code at `1bc82a3`: one per pillar, one
on tone, one on balance discipline, one on the economy, and one on scope,
setting and art. Every finding below cites the code it stands on, and the
highest-severity ones were re-read by hand before they went in. Nothing was
changed and no sweep was run. Where a claim is arithmetic from constants
rather than a measurement, it says **estimated**.

The short version: the three pillars are all present in code and each has at
least one system that carries it well (earned traits, the site as an
adventuring day, slots that come back only one way). What undercuts them is a
handful of **side doors** — a free long rest on the character sheet, a free
revive on defeat, a money printer in the lodge garden, a positive-return
gambling table — each of which removes a cost the rest of the design is built
on. Closing those is cheap and does more for the pillars than any new system.

---

## 1. Side doors: costs the bible names that the code lets you skip

These are the highest-priority findings, because each one silently removes a
trade-off that other systems (and the balance sweeps) assume is there.

| # | Sev | What | Evidence | Pillar |
|---|---|---|---|---|
| 1.1 | **High** | **The character sheet is a free long rest, anywhere.** "Long rest (restore all)" clears every pool and sets full HP; HP has ±1/±5/full buttons. The sheet opens from the map's Party page in open country with no gate. A sorcerer can refill sorcery points here and turn them into slots in the next fight — unlimited slots. | `scenes/profile/profile.gd:275-278, 343-348, 362-365`; `scenes/party/party.gd:597-598` | 3 (slots refill on a long rest only) |
| 1.2 | **High** | **A lost fight revives the whole roster for free.** `_retreat()` charges 15% of *carried* gold and calls `Party.auto_revive_all`, which stands up every dead member, benched ones included. On the road this fight's dead stay dead (deaths applied after); in a site they are applied *before* the wipe, so even this fight's dead come back. A raise at the healer is 300 ◉, so below ~2,000 ◉ carried, conceding (the header's "Admit defeat") is cheaper than paying. | `scenes/world/world.gd:1914, 1925, 2330-2337, 2811, 2848`; `core/party.gd:412-417`; `scenes/main.gd:277-292` | 1, 2 |
| 1.3 | **High** | **A lair is priced for the drained party at the door.** `entry_score = Scaler.party_score(...)` counts only the slots left, while the open world uses `Regions.fresh_score` (every slot back). Entering empty, or withdrawing and walking back in, shrinks the remaining rooms and the boss. The bible says `site.gd` holds slots "the same" as `slot_hold()`; it holds them only *within* one entry. | `core/site.gd:174-179, 210`; `core/regions.gd:251-259` | 3 (spent slots never buy an easier fight) |
| 1.4 | **High** | **The lodge garden prints money.** The garden grows `potions-of-healing`, whose rarity is `"varies"`, which prices as *rare*: 25·3⁴ = 2,025 ◉ list, ~1,012 sold. House + garden is 550 ◉, repaid by one potion; after that ~337 ◉ a day for nothing (3 banked max). The same rule makes an ordinary healing potion cost 2,025 at the alchemist, against a 20 ◉ inn night. | `core/lodge.gd:28-45`; `core/campaign.gd:1060-1102` (`VARIES_TIER := 2`) | 2, economy |
| 1.5 | **High** | **Gambling has a positive expected return from +2 up.** Returns 1.5× at DC 12, 2× at DC 17, 3× on a natural 20; the party rolls its best of Insight/Deception/Sleight of Hand. EV is 0.93× at +1, 1.03× at +2, 1.33× at +5, 1.53× at +7. No clock cost; "once a visit" re-arms by stepping out of the gate. Max stake every visit is the only sensible play. | `core/downtime.gd:53-55, 264-296`; `core/settlement_visit.gd:366` | 2 |
| 1.6 | Med | **Rope Trick makes camping free and safe.** It skips both the 150 ◉ kit and the 8% ambush, and the slot it costs comes straight back from the rest it enables. Alarm likewise. | `core/road_spells.gd:20, 62`; `scenes/world/world.gd:3615-3634` | 2, 3 |
| 1.7 | Med | **A long rest doesn't move the world.** The 480 minutes go straight onto `elapsed`; roaming bands only move inside `World.tick`, so nobody walks during the night. Camping doesn't check for a hostile band nearby (the short rest does). | `core/settlement_visit.gd:426`; `scenes/world/world.gd:557-563, 3589, 3609-3614` | 3 (bible: "bands keep walking") |
| 1.8 | Med | **The strongroom zeroes both purse-scaled costs.** The parley toll is `max(15, 12% carried)` and the defeat tax is 15% carried; bank the purse and both round to nothing. Feeds 1.2. | `core/approach.gd:243-244`; `core/lodge.gd:129-132` | 2 |
| 1.9 | Low | Downtime (carouse/craft/train/retrain) calls `Visit.rest` without `can_long_rest`, so a full refill can land ~16 h after the last. | `core/downtime.gd:89-94` | 3 |

**Recommendation.** Treat 1.1–1.5 as bugs against the bible, not as balance
tuning: make the sheet read-only inside a campaign; revive only the *downed*
on defeat (or charge the raise fee); price a lair with `Regions.fresh_score`;
price potions of healing by grade (≈50/150) instead of by "varies"; allow one
game a day and pull its return below 1. None of these moves a measured number
the sweeps rely on, because the sweeps never used any of these doors — which
is also why they have not caught them.

---

## 2. Pillar 1 — every merc is memorable

**Works:** earned traits are seeded saves with a stated reason and a full-screen
moment (`scenes/world/world.gd:2563-2603`, `core/traits.gd:1230-1245`); opinions
show up *in the fight log* ("stand shoulder to shoulder", "get in each other's
way": `core/combat.gd:2662, 2677, 3073, 3232`); callings tie a hero's past to a
real place on the map and pay out a bond with whoever did the deed
(`core/callings.gd:305-323`); recruits arrive with a temperament and a past that
fits their background (`core/recruits.gd:253-255`).

| Sev | Finding | Evidence | Recommendation |
|---|---|---|---|
| **High** | **Death barely registers and often doesn't stick.** One log line ("%s did not get up."); no memorial; the "ally died" hardship fires off *anyone* dying at 50%, so a lover and yesterday's hire weigh the same; no opinion event on a death (the spike doc still lists it as "not an event yet"); a later loss revives earlier dead (1.2); the dead can come back as veterans in the next run; the "Cost of Doing Business" achievement counts only in the linear campaign. | `world.gd:2041-2043`; `core/traits.gd:980-982`; `docs/spike-party-opinions.md:328`; `core/recruits.gd:186-189, 228`; `core/campaign.gd:609` | A guaranteed grief hardship for the bonded, a camp beat, a roll of the fallen at the lodge, dead kept out of the veteran pool, deaths counted in `_apply_deaths`. |
| **High** | **No service record.** `trait_counts` holds kills per faction, wins and downs, but no scene reads it — the player can't see progress toward a bane (10 kills) or Veteran (20 wins). Earned traits store *why* and *when*; the profile shows neither. Spoils list what died, not who killed it, though `result.credit` has it. | `core/character.gd:28-33`; `scenes/profile/profile.gd:418-444`; `world.gd:2100-2119` | A Service panel on the profile; "struck the blow" on spoils. |
| Med | **Party barks are one shared pool** (4–6 lines a trigger, 20% chance), blind to temperament, bonds and name. `"Keep them off Vera!"` names a preset hero any merc can say — including Vera. | `core/barks.gd:10-24` | A pool per temperament (there are 8); a line for a bonded partner going down; name a real ally. |
| Med | **The bench is free and lifeless.** No wages or upkeep (by design), but only the marching four earn XP, camp moments, callings and a place in the relations web. Hires arrive at band level −1, so benched heroes fall behind fresh ones; a hire is cheaper than a 300 ◉ raise until about level 6. The economics say mercs are disposable. | `core/campaign.gd:630-642`; `core/party_opinion.gd:365`; `core/callings.gd:168`; `scenes/party/relations_web.gd:69`; `core/recruits.gd:146` | Keep "no wages" but give the bench a non-gold cost (restless mercs may leave, told as a moment) and a share of XP/training. |
| Med | **Recruits blur together.** 8–16 names a species, duplicates allowed; the inn row shows name/species/class/background/trait names only; a veteran is just "(a veteran)"; one calling per background. | `core/recruits.gd:281-286`; `world.gd:4553-4557`; `core/callings.gd:32` | No duplicate names on a roster; a one-line intro from temperament + background; a veteran's record from earlier runs. |
| Low | Camp relationship lines are few (3 warming, 3 quarrel, 2 courtship) at up to one a long rest. Headers in `party_opinion.gd:26-28` and `callings.gd:3` still say "every member is player-made", no longer true since hiring. | `core/party_opinion.gd:342-357` | More lines, chosen by the pair's temperaments; fix the headers. |

---

## 3. Pillar 2 — hard choices, no perfect answer

**Works:** the approach card's ambush states both halves of the gamble and a
failure hands the enemy round one (`core/approach.gd:74-77`); the site is a
real adventuring day — short rest only, leave between rooms, a full-clear bonus,
a wipe resets the lair and costs a third of the stash (`core/site.gd:79-86,
620-658`); raids put the world clock to work (`core/raids.gd:5-48`); the rescue
objective trades position against speed (`core/objectives.gd:47`); a forced
march trades the chase roll for −2 on road checks (`core/travel.gd:78`).

Beyond the side doors in §1 (1.2, 1.5, 1.6, 1.8 all belong here too):

| Sev | Finding | Evidence | Recommendation |
|---|---|---|---|
| Med | **A failed parley costs nothing extra.** Failure is "a plain, even fight" — exactly Engage. Parley is a free roll before Engage against anything that talks; the file's own header says a gamble with no downside dominates. | `core/approach.gd:15-17, 88, 228` | Failure takes the toll anyway, or gives the foe round one, or costs faction opinion. |
| Med | **Pressing on hurt carries almost no risk on the road.** `power_scale` shrinks road fights to 0.35× by wounds, tuned to hold ~85%; with the soft defeat (1.2) hit points barely count as a resource outside sites. (XP shrinks with the fight, and sites don't scale — both good.) | `core/world_threat.gd:97-123` | Keep the curve, raise the stakes of losing; or show "they will fight you at X%" so pressing on reads as a chosen gamble. |
| Med | **Withdraw, camp, come back is the right answer for deep lairs.** The 2,880-min lair window fits a long rest; cleared rooms stay cleared; re-entry re-prices for the rested party. Costs 150 ◉ — or nothing with Rope Trick. | `core/world_lairs.gd:104`; `core/site.gd:150, 653-661` | A disturbed lair regrows a room or reinforces the next one while the party is away. |
| Low | **Quests never expire.** No time field; the only failure is a lost delivery. Only raids and lair windows use the clock. | `core/quest.gd:1-24, 296-303` | Expiry on bounties and rescues, so downtime days trade against them. |
| Low | **No retreat inside a fight** — only surrender, which is a full loss. | `core/combat.gd:814-835` | A "withdraw off the board edge" that forfeits rewards but is not a defeat. |

**Not a finding:** the party autopilot (`core/ai.gd:481`, "demo / test only")
is not player-facing; it does not hollow out the tactical layer. The design
note it leaves is that balance is tuned so that simple script wins 93.8–100%
of easy fights (`core/regions.gd` header), so a human playing well meets very
little risk on the road — which is where the side doors above bite hardest.

---

## 4. Pillar 3 — magic is powerful but costly

**Works:** `Adapter.rest` is the only code that clears `slots_used`
(`core/adapter.gd:421, 425`); `write_back` carries spent slots between fights;
every open-world fight path — road bands, raid waves, garrisons, the pit — goes
through `encounter_spec` → `WorldThreat.assess` and so gets the slot hold
(`world.gd:1724-1733, 1849, 4759`); the short-rest cap holds on the map and in
sites (`core/settlement_visit.gd:433`, `core/site.gd:587`); Font of Magic cannot
loop (`core/combat.gd:618`); enemy casters are gated as the bible says
(`core/enemy_casters.gd:61`, `core/scaler.gd:402, 524`); the inn explains a
refused rest instead of greying the button (`world.gd:4195-4198`).

Beyond 1.1, 1.3, 1.6, 1.7 and 1.9:

| Sev | Finding | Evidence | Recommendation |
|---|---|---|---|
| Med | **The player can't see their real slots outside a fight.** The sheet's "Level N slots" rows are a separate `pools["slot:N"]` counter nothing else reads; `Party.summary()` holds no slots; combat pips take their maximum from the slots *left at the start of the fight* and hide an empty level. A price you can't see doesn't shape decisions. | `scenes/profile/profile.gd:336`; `scenes/main.gd:637-639, 2141-2143` | Show `Adapter.slots_left()` against the sheet maximum on the sheet, the party rows and the pips. |
| Med | **Arcane Recovery can't be used.** `Adapter.arcane_recovery` is only called from tests; the manual tells players it works on a short rest. | `core/adapter.gd:82`; `core/manual.gd:31, 180` | Wire it into the short-rest action, or correct the manual. |
| Low | Trance's short-rest top-up runs right after a long rest, when everything is full, so it does nothing; the text still promises it. | `core/trance.gd:44-45`; `world.gd:3562` | Run it at the first short rest instead. |
| **Estimated** | **The gold cost of rest shrinks to nothing.** Rooms are 40/20/10 ◉, half at Known, free at Sworn or with a lodge; after that only time costs. With ~60 min of clock per round, two road fights fill a day, so the 24 h gate barely binds outside sites. | `core/settlement_visit.gd:65, 74-83`; `world.gd:1773, 1808` | Sweep it: road fights and slots left per long rest, gold on rest as a share of income, by level (a drive robot). |
| **Estimated** | **Bench rotation as a second slot pool.** Benching is gated only by `roster_locked`; a drained four can swap for a fresh four while the rest is on cooldown. Only XP resists it. | `core/party.gd:575` | Sweep it before acting; if real, a benched hero rests only when the company does. |

---

## 5. The economy

Numbers from constants (**estimated**): easy-fight coin is ~7 ◉ at level 1,
16 at 3, 36 at 6, 53 at 10, 81 at 19; ~6–10 fights a level all the way to 20
(`core/encounter.gd:715-716`, `core/leveling.gd:26-35`). Out-of-band farming is
closed by the band pin (`core/regions.gd:21-24`), and grinding is linear, not
runaway — both good.

| Sev | Finding | Evidence | Recommendation |
|---|---|---|---|
| **High** | **Loot drowns coin, and late gold has nothing to buy.** Loot sells at 50% of list and drop tables climb by CR; a scroll of identification sells for 200 against 16 ◉ for a level-3 fight; a Deeps fight's loot is ~20× its coin (**estimated**). Non-potion magic items have no effect in a fight (`adapter.gd:349-350`; 14 of 264 have entries in `data/effects/`), and every useful sink is flat or one-time. Past level ~8 gold stops mattering. | `core/loot.gd:87-118`; `core/campaign.gd:1060-1102`; `core/adapter.gd:349-350` | Pay loot at a fraction of list, add sinks that scale with level (resurrection by level, attunement/gear, wages or upkeep). |
| Med | **Death is cheapest to undo early, and a hire undercuts it.** A flat 300 ◉ raise is ~19 level-3 fights of coin and ~4 at level 15; below level 6 a replacement hire is cheaper. | `core/party.gd:311`; `core/recruits.gd:85` | Price resurrection by level (≈50·level). |
| Med | **Quest XP ignores region and inflates with renown.** Quest XP is gold × 2, after renown and regard multipliers (up to ×1.75, ×2.6 with a raid). A 200 ◉ job is ~8 level-1–3 fights of XP; the Heartland is outgrown fast. | `core/quest.gd:37, 184`; `core/quest_posting.gd:184` | Base quest XP on the region's fight XP, not on gold. |
| Med | **The Far Deeps hold most of the run** (**estimated**: Heartland ~13 fights, Marches ~25, Frontier ~23, Deeps ~100). Daily lair respawn makes clear–sleep–repeat the obvious loop there. | `core/world_lairs.gd:152`; `core/regions.gd:81-87` | Split the Deeps into sub-bands, slow respawn past the Marches. |
| Low | The meta unlock ladder is still at testing pace: every class opens at 8,000 lifetime XP, partway through a first run (the shipping values are in a comment). Quest/landmark XP also feed lifetime XP, contradicting "only fight XP". | `core/progression.gd:44-66, 104-112`; `core/leveling.gd:55-58` | Restore the shipping values before release. |
| Low | Being liked makes selling worse: sell price is `list × 0.5 × min(1, markup)` and markup falls with opinion. A beloved town pays 30% of list. | `core/settlement_visit.gd:392-394`; `core/faction_opinion.gd:33` | Invert the markup for selling. |

---

## 6. Tone

The authored fiction is on-tone and some of it is the best writing in the
repo: `data/traits.json` camp lines, `core/rumors.gd`, `core/regions.gd`,
`core/site.gd`, `core/travel.gd`, `content/ashen-road`. Five that show the voice:

- "There is laughing out on the flats at night. It is not people." (`core/rumors.gd:60`)
- "Better equipped than you were. It did not help." (`core/site.gd:137`)
- "%s has taken the watch nearest the one they carried out. Nobody said to." (`data/traits.json`, protector)
- "They have nothing left to give but the road, and they give that." (`core/travel.gd:256`)
- "Emberwatch owes you a road, a wall and a season. Take the road; we're keeping the wall." (`content/ashen-road/story.json`)

What breaks it is machine-assembled text, UI messages, and two voices:

| Where | Line | Rewrite |
|---|---|---|
| `core/quest.gd:144`, `core/world_ai.gd:114`, `core/callings.gd:357`, `world.gd:1567, 1681` | Band ids shown as names: "Hunt down the Goblin Raiders 3 band", "The band called Gnoll Pack 2 is asking after you" | Name bands from `EnemyNames` ("Ribsnap's lot"). **The most visible tone problem in the game.** |
| `core/barks.gd:37-38` | "Poke poke!", "OOOH that squirted!" | "Stick it! Stick it!", "That one leaks!" |
| `core/barks.gd:80-81` | "You DARE draw my blood?!", "Impossible… mere… mortals…" | "Blood. You will not do that twice." / "Not… you…" |
| `core/barks.gd:15-16` | "Ha! Perfect.", "Now THAT was a swing." | "Found the gap.", "That went in." |
| `core/quest.gd:160-161` | "Raze %s for good", "Purge %s", "End the %s threat" | "Break the gate at %s", "Clear %s out", "Make sure %s stays empty" |
| `core/callings.gd:91, 210` | "%s are deserters from a company you served in." — can pick a gnoll or kobold band | Limit to bandit/soldier bands. |
| `scenes/game/game.gd:163` | "Random battle (debug)" on the title screen | Hide behind an env var. |
| `core/combat.gd:3178` | "eyes snap open — nat 20, up at 1 HP!" | "A natural 20: up, at 1 HP." |
| `scenes/world/world.gd:3657` | "Nobody's keeping watch — the camp is jumped in the night!" | "Nobody is watching the dark. They are in the camp before anyone can draw." |
| `core/achievements.gd:111, 145, 192` | "Butterfingers" / "Statistically, this is fine.", "Barrel of Laughs", "Death's Revolving Door", "Field Medic" | "Fifty Dropped Blades", "Lamp Oil and a Spark", "Sent Back Five Times", "Bonesetter" |
| `core/ladder.gd:29` | "Famous", "Legends" — stated heroism, mixed parts of speech | e.g. "Asked For by Name", "Sung Wrong in Taverns" |
| `core/enemy_names.gd:10`; `data/recruit-names.json` | "Dresden" (a real city); "Keyleth" (a Critical Role character) | "Dresk", another name |
| `scenes/creator/creator.gd:486`; `core/tips.gd:16` | "real 5.5e builds"; "the engine telling you" | Keep the rules edition and "the engine" out of the fiction. |

Across systems:
- **Currency.** About 114 lines use ◉, but `site.gd:565, 576`, `campaign.gd:599, 895`, `settlement_visit.gd:244`, `approach.gd:84` and `event_card.gd:489` write "+%d gold." Rule: ◉ beside a number, "coin"/"gold" only in prose.
- **Company, party or heroes.** "party" ×~69, "company" ×~27, sometimes on one screen; "hero" in a merc game; "merc" never appears. Rule: "company" in fiction, "party" only where the line is a rule.
- **Two registers.** Authored text writes "is not" and never uses "!"; system messages use contractions and "!", and the dice verdicts shout ("NATURAL 20!", "MADE IT!", `scenes/dice_roll.gd:211-213`). Choose the authored one.

---

## 7. Balance discipline and drift

The skills lag the code in a few places. The file headers win, so these are
edits to the skills, not to the code:

| Claim in the skill/bible | Code says | Where |
|---|---|---|
| Paladin/ranger level-1 slots are "a data gap" (balancing skill; bible) | Fixed: `classes.json` gives `[2]` (build log 2026-09-24, "Paladins and rangers cast from level 1") | `tools/fill_levels.py:76-79` |
| "Latest measured 96.5 / 90.0 / 79.5%" | That is the old-autopilot (master) column; the current code measures **96.5 / 93.0 / 81.5** | `core/scaler.gd:52-54` |
| "One band too deep: level 3 in the Marches 17.5%" | 28.8% with the new autopilot | `core/regions.gd:370` |
| Fight length 7–8 rounds (L8 9.6) | Old-autopilot figures, never re-measured | skill "Balance targets" |
| `CURVE 1.15` "budget grows sublinearly" | 1.15 is superlinear; `scaler.gd:200` still says "CURVE stays 0.90" | `core/scaler.gd:200, 276` |

Every other number checked matches: TIER, REF_SCORE, MAX_FOES, mult range,
XP/gold per power, FT_PER_HEX (though it is hard-coded again at
`core/combat.gd:20`), range cap, cover on DEX saves only, rest limits, camp kit,
every hiring constant, test targets, MAX_ACTIVE, band level ranges.

**Stale measurements, unlabelled** (highest impact first):
- **`core/world_threat.gd:54-104`** — the wounds curve (`WILDERNESS_SCALE`, `HURT_AT`, `CONDITION_FLOOR`) rests on a 2026-09-13 grid taken under TIER easy 0.96 / CURVE 0.90, before the swing fix, the cover fix, RAW death saves and the new autopilot. The newer `sweep_spent_slots` shows fresh parties at 99.5% and half-HP parties at 90–95% on the road, against the header's aim of "near 85%". The road is close to a walkover and the header doesn't say so.
- `core/traits.gd:42-48, 640-667` — trait sweeps from 09-23, before the cover fix, which the build log says invalidated them.
- `core/encounter.gd:194-202` (`BOARD_SHELVES`) and `:700-706` (`SPAWN_GAP`) — pre-cover-fix, pre-autopilot; `SPAWN_GAP` predates the 09-15 board growth.
- `core/campaign.gd:311-319` `BOSS_REF_WIN_RATE 0.86` — its own rule says re-derive on every TIER retune (linear campaign only).

**Tuned knobs with no named sweep:** `core/site.gd:53-67` (`MAX_DEPTH`,
`SUPPORT_CHANCE`, `REST_SHARE` — the attrition of the game's hardest content);
`core/encounter.gd:709-711` (`AC/ATK/DMG_PER_MULT`, up to +6 AC / +8 to hit on
a boss); `core/encounter.gd:713-716` and the XP curve it feeds, which cites a
`tests/_tmp_xp` that isn't in the repo; `core/downtime.gd:62` `PIT_MULT`;
`core/scaler.gd:337-338` `BIGGEST_SHARE`, `ROSTER_KINDS`.

**Unpriced power** (all tilt fights *easier*, never harder): Metamagic
(Quickened is exactly the action-economy lever the scaler header ranks first;
the autopilot never arms it, so no sweep sees it), weapon mastery on recruits
and custom builds, potions as road buffs, party-opinion bonds (+1 AC, rally).
Innate Sorcery/Font of Magic and traits are measured near zero.

**Fragile test bands:** L3 normal at 93.0 against a ceiling of 95 (≈1.1 SE at
200 seeds) and hard at 81.5 against 85 are the checks any easier-making rule
change will trip first; L8 easy at 96.0% is 6 losses from its `< 100` check.

**Dead code:** `core/rules/power.gd:11` holds a second `TIER`
(0.55/0.85/1.15) used only by `roster_budget` (`:319`), which nothing calls — a
trap for anyone grepping for TIER.

---

## 8. Scope, setting and art

_This section is being filled in._

---

## What to do, in order

1. **Close the side doors (§1.1–1.5).** Each is small, none needs a sweep, and
   together they restore the costs the three pillars are built on.
2. **Make the price visible** — real slots on the sheet and the pips (§4),
   a service record on the profile (§2).
3. **Give death weight** — grief for the bonded, a roll of the fallen, the dead
   out of the veteran pool (§2). This is the cheapest big win for pillar 1.
4. **Re-run `world_threat`'s grid and the trait sweeps** under the current
   ruler, then decide whether the road is meant to be as easy as it measures
   (§7). Do the economy fixes (§5) in the same pass, since loot, quest XP and
   resurrection prices all move the same levers.
5. **Name the bands** and do one tone pass on barks, achievements, quest chain
   labels and system messages (§6).
6. **Bring the skills up to date** with the table in §7 so the next change
   starts from today's numbers.
