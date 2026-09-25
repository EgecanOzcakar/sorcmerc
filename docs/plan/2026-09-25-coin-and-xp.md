## Coin and XP — gold that matters to the end (2026-09-25)

Eight of the owner's calls on the economy half of the design audit
(docs/audit-game-design.md §5, "The owner's calls" 5.1–5.6). The audit's
finding was that loot drowned coin, late gold had nothing to buy, quest XP
followed the purse rather than the country, and most of a run was spent in
the Far Deeps clearing the same lairs. None of this moves a win rate: no fight
is built differently, so no win-rate sweep was re-run. Every number below that
is not a test's is **estimated** — arithmetic on the numbers a fight is built
and paid from, re-runnable as `tests/sweep_economy.gd` (a new harness, not in
`run_tests.sh`), and quoted in the file that owns it.

**Loot sells for a fifth of list (§5.1a).** `Campaign.SELL_RATE` 0.5 → 0.2,
the top of the owner's 10–20%, because the other half of this pass makes a
magic item worth wearing, so selling one now costs something. Two prices were
fixed first, because they were most of early loot: the Scroll of
Identification priced at 400 ◉ (the export files it uncommon) while
`core/loot.gd` drops it from the common band, and is now 100 ◉, the 2024 DMG's
common price, still dearer than the librarian's 60 ◉ identify; and the potion
of healing moved down to the common band, which resolves the `ponytail:` the
defeat-lairs-coin entry left for this pass. Coin and loot per easy
open-country fight, the ruler trio, 200 pinned rosters a row:

| level | coin | loot at list | sold at 0.5 | sold at 0.2 |
|---|---|---|---|---|
| 1 | 7 ◉ | 18 | 9 (1.2x coin) | 4 (0.5x) |
| 3 | 18 | 29 | 14 (0.8x) | 6 (0.3x) |
| 6 | 41 | 51 | 26 (0.6x) | 10 (0.2x) |
| 10 | 62 | 230 | 115 (1.9x) | 46 (0.7x) |
| 15 | 91 | 567 | 284 (3.1x) | 113 (1.2x) |
| 19 | 118 | 788 | 394 (3.4x) | 158 (1.3x) |

(Before the two price fixes, a level-1 fight's loot sold for 5.6x its coin.)

**Friendly towns pay more (§5.6).** The sale read `min(1, markup)`, and the
markup carries opinion, so being liked made every sale worse: a beloved town
paid 30% of list. `SettlementVisit.sell_price` now reads opinion on its own
and the right way round (`FactionOpinion.sell_factor`: x1.4 at +100, x0.6 at
−100); a thin shelf or a fight nearby still pays no premium; and a won haggle
now raises what they pay as well as lowering what they charge. What the bench
crafts at half list still never sells above its cost (0.2 x 1.4 x 1.15 < 0.5).

**Sinks that scale with level (§5.1b, §5.2).** A raise costs 50 ◉ a level
(`Party.revive_cost`), through the healer, Revivify or a scroll alike: 50 at
level 1, 300 at 6 (RAW's diamond), 950 at 19 — about eight fights' coin at
every level, where the flat 300 was ~16 at level 3 and ~3 at 15. The healer's
row, the party card's tooltip, the linear run's fallen panel and the defeat
line ("A healer can raise the dead for 150 ◉") all quote it. The trainer now
takes a hero once per four levels — a feat at 4, 8, 12, 16 and 20 — at 150 +
100 ◉ a level (550 at 4 up to 2,150 at 20, ~17–26 fights' coin each), where it
used to take a hero once, ever, and was spent by level 5. The save's `trained`
list simply holds a hero's id once per feat, so an old save reads as the
first tier's feat. The extra feats are real power and are priced, since a feat
lands on the sheet `power.gd` reads. A gear-upgrade path was considered and
left: the smith's back room already sells the next grade, so trading up is
buy-and-sell there today (Still open).

**Magic items work in a fight (§5.1c).** Until now a magic item put on at the
profile sat in `equipped` as an inert "unknown" row. `data/effects/items.json`
(new, 21 entries) and `core/rules/pass_items.gd` (new) are the first tranche:
+1/+2/+3 weapons, armor and shields, the cloak and ring of protection, the
luckstone, bracers of defense and of archery, the gauntlets, headband and
amulet that set a score, the wand of the war mage, and the brooch of shielding
— the items loot and the back room hand out most whose whole mechanic is a
flat number the sheet already has a place for. Everything lands on the
Resolved sheet (AC, saves, checks, attacks, spell attack, resistances, a
score), so the adapter carries it into the fight with no combat code, and
**`power.gd` prices it through the sheet**: a geared Vera (+2 weapon, +1
armor, a cloak) reads more than 5% stronger, so a company in better gear is
sent a bigger fight. It prices AC, attacks, HP and resistances; saves and
ability checks are unpriced. RAW limits hold: one of each id, the best
weapon/armor/shield enchantment, three attuned items. A +1 shield is a shield;
a weapon or armor enchantment rides whatever the hero wields or wears (a
`ponytail:` in pass_items.gd — the export's +N weapon has no base). The
tooltip leads with what an item does ("Worn: +1 AC and +1 to every saving
throw") or says plainly "Worn: does nothing in a fight yet", and now says
"attunement" at all (it compared a JSON bool to "True"). A worn magic item is
now a "magic" row the profile can take back off.

`effects/items.json` is pack-writable the compat way: added to
`Manifest.DATA_FILES` and `EFFECT_FILES` (nothing renamed, API stays 1),
validated in `registry.gd` (unknown slot, key or ability is an error),
documented in `docs/modding.md` §5.1, its slots and keys held as two new
vocabularies in `tests/test_mod_api.gd`, and the snapshot regenerated.

**Quest XP is the country's fights (§5.3).** It was the purse x2, after renown
and regard, so fame taught more and a Heartland errand was eight level-1
fights of XP. Now a posting stamps `reward.xp` = N fights (`Quest.XP_FIGHTS`:
a delivery or scouting ride 2, a lair or rescue 3, a raid 4, a counter's order
1, +1 a chain tier) of `Regions.fight_xp` at the level the posting's country
pins a fight to — the ruler's easy budget x `XP_PER_POWER`, exactly how a road
fight is paid. Renown and regard multiply the gold only. A clear-lair job pays
~140 XP at level 1 (was ~300), ~370 at 3 (about the same), ~1,240 in the Deeps
at 10 (was ~300). The board shows it ("Pays 135 ◉ and 366 XP"). A job with no
stamp — an old save's, the linear run's curated ones, a pack's story quest —
pays the old rate. Quest XP still feeds lifetime XP (the owner's call). The
`ponytail:` on `Contracts.STANDING_PAY` about contract XP is resolved and gone.

**The shipping unlock costs are back (§5.5).** Species 1,500–7,500, classes
10,000–40,000, a paid subclass 2,500 class XP, from the numbers
`core/progression.gd`'s header kept. On a first trio's climb (fight XP only):
the gnome opens around level 4, the rogue around 9, the sorcerer about one
whole run to 20. `tests/test_progression.gd`'s testing-pace test is now a
shipping-pace test pinned to where each rung falls. Quest and landmark XP keep
counting; `core/leveling.gd`'s "only fight XP" comment is corrected. No test
or robot leaned on the cheap ladder (the ones that need unlocks already pin a
profile or set `SORCMERC_PLAYTEST`); the header now says that is the rule.

**The Deeps go faster, and their lairs come back slower (§5.4b, §5.4c).**
Past level 10 every level costs what level 10 did, a flat 1,000
(`Leveling.LATE_LEVEL`); levels 1–11 read exactly as before, so no banked
total changes level. Fights to the next level (easy fight XP split three ways):

| level | 1 | 3 | 5 | 8 | 10 | 12 | 14 | 16 | 18 | 19 | 10→20 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| before | 6.2 | 7.4 | 6.6 | 7.0 | 7.3 | 7.3 | 7.3 | 7.7 | 7.2 | 7.3 | ~73 |
| after | 6.2 | 7.4 | 6.6 | 7.0 | 7.3 | 6.0 | 5.2 | 4.8 | 4.0 | 3.8 | ~52 |

A lair respawns in a day in the Heartland and the Marches, three on the
Frontier and five in the Far Deeps (`WorldLairs.RESPAWN_BY_BAND`, taste
numbers), read off where it stands, so clear–sleep–repeat is no longer the
Deeps' loop.

Tests: `tests/test_items.gd` (new: every entry, each slot, the RAW limits, the
combatant and `power.gd` seeing it, the tooltip, pack validation);
`test_party` (raise by level, all three doors, the defeat line);
`test_settlement_visit` (the inverted sale, the rate, the haggle);
`test_quest_posting` (the stamp, renown leaving it, turn-in, the fallback);
`test_leveling` (the table, the late step, the pace); `test_progression`
(shipping pace); `test_lair_respawn` (a lair in each band); `test_downtime`
(training tiers); `test_campaign`, `test_traits_road`, `test_achievements`
updated for the new prices; `test_mod_api` with the new vocabularies.

Screenshots (`tests/shot_coin_and_xp.gd`, under xvfb): Vera in a +1 shield,
a +1 sword and a cloak of protection — AC 20, longsword +6 1d8+4
(`docs/shots/coin-and-xp-sheet.png`); the same pack priced by a neutral town
(`coin-and-xp-sell.png`) and a friendly one (`coin-and-xp-sell-friendly.png`,
plate 300 → 396 ◉); the notice board quoting XP beside each purse
(`coin-and-xp-board.png`).

### Still open

- **The rest of the magic items.** 21 of 264 have a mechanic; the rest are
  found, worn and sold and say they do nothing yet. Next: items that need a
  verb or a pool (periapt of wound closure, wand of magic missiles, javelin of
  lightning, a staff), crit immunity (adamantine armor), magic ammunition, the
  belt of giant strength (a "varies" item), and item proficiencies (the
  bracers of archery's bows).
- **A +N weapon is not magical to a wraith.** Its attacks are not marked
  magical, so "nonmagical weapon" resistances still halve it and the
  qualified immunities stay demoted to resistance for everyone (the
  `ponytail:` in `core/adapter.gd`'s `_damage_types_split`). Needs a per-attack
  flag through combat.gd's damage path and the co-op hash.
- **An enchantment has no base.** A +1 weapon rides whatever the hero wields
  (the `ponytail:` in `pass_items.gd`); a +1 longbow as one item needs a base
  picked at drop time.
- **Saves and checks from items are unpriced** by `power.gd`; price them if a
  sweep sees a cloak or luckstone above noise.
- **No re-forge row.** Trading a +1 up to a +2 is buy-and-sell at the back
  room; a smith's upgrade row (pay the difference) would fit there if players
  want it.
- **Loot drops are unchanged in shape.** The rate and two prices moved, not
  the tables; a Deeps fight still drops a very-rare item 15% of the time a
  roll hits.
- **The lair respawn windows and training's price are taste numbers**, and
  the fights-per-level and loot tables are estimates. An open-world sweep that
  plays days of a run would measure all three (the audit's §7.3 XP-pacing
  sweep).
- **Old saves:** a job taken before this pays its old purse-rate XP; a hero
  past level 11 may find a level-up waiting; a hero who trained before now
  reads as having trained once.
