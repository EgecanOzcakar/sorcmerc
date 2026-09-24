## Housekeeping from the design audit — dead code, Metamagic that does nothing, rules in scenes, strays (2026-09-24)

The owner's calls on the design audit (`docs/audit-game-design.md`, "The
owner's calls") for §7.5, §8.5, §8.6 and §8.8. One visible change, the
Metamagic picker. The rest is removal and moving code, with behaviour held
by tests.

**Metamagic that does nothing is no longer on offer (§8.5).** The 2024
sorcerer picks two Metamagic options at levels 2, 10 and 17 out of ten, and
the creator offered all ten. Only five work on the board: Quickened,
Twinned, Careful, Subtle and Seeking. A pick of Distant, Empowered,
Extended, Heightened or Transmuted Spell did nothing for the rest of the
run, and nothing said so. `core/metamagic.gd` now holds the one list of
built options (`BUILT`), and three places read it:

- `Combat._metamagic_option` refuses any option word not on the list.
- `ChoicePick.unbuilt(p)` draws the other five on the creator's and the
  level-up page's pickers greyed, with the tooltip "Not on the board yet".
  They stay visible, so a player who knows the book sees they are missing
  on purpose.
- A hireling's auto-picks (`Recruits._auto_picks`) pass over the unbuilt
  five.

`tests/test_metamagic.gd` checks that the list, the `kind: "metamagic"`
verbs in `data/effects/features.json` and the chip lines in
`core/active_effects.gd` all name the same five, so building a sixth in only
one of those places fails. It also checks the greyed picker on the real
level-up page and 24 seeds of level-17 hireling picks.
`tests/test_sorcerer.gd` checks that combat refuses an unbuilt option.
Screenshot: `docs/shots/audit-housekeeping-metamagic-picker.png`.

**Dead code (§7.5, §8.5).** Removed:

- `core/rules/power.gd`'s second `TIER` (0.55/0.85/1.15) and the
  `roster_budget` that read it. Nothing called either, and a TIER that
  nothing uses is a trap for anyone grepping for the real one in
  `core/scaler.gd`.
- `Regions.describe`, which only its own test line called.
- `Regions.label_of`, `RoadSpells.is_road` and `Hex.corner_pixel`.

None of them is called from any script, scene, tool or content pack, and
none is in the mod API snapshot. `FactionOpinion.price_factor` had no
callers either, while `SettlementVisit.market` wrote its formula out
inline. It now takes the opinion number and `market()` calls it.
`test_settlement_visit`'s new `test_market_reads_price_factor` checks that
the markup and every shelf price match the old inline formula exactly. It
covers opinion -100 to 100, four shelf gaps, and with and without a battle.

**Rules out of scenes (§8.6).** `scenes/world/world.gd`'s `_bank` worked
out the post-fight XP split and the Greedy trait's +10% purse inside the
scene. Its `ponytail:` said to move this once `campaign.gd` could be
edited, and it can now. The rule is `Campaign.bank_win(party, result)`:

- the XP split;
- the purse through `fight_purse`, which adds Greedy's cut;
- `result["gold"]` rewritten to the gold actually banked, for the spoils
  page;
- the loot into the stash.

`_bank` keeps what is only the screen's: the delve's running total, the
"Taken from the dead" line and the quest news. `split_xp` is now static.
Eight callers used to build a throwaway `Campaign.new(party)` to reach it,
and none do now. The ponytail is removed. `test_campaign`'s
`test_bank_win` covers the even split with its remainder dropped, the purse
without a Greedy hero, with one, and with two (they do not stack), and the
loot.

The profile's Drink button seeded a potion's road roll with `randi()`, so a
bad Potion of Healing was one reload away from a good one. The roll is now
seeded in core, off the drink itself (`Potions.road_seed`): the hero, the
potion, the world minute, and how many of that potion the stash holds. The
same drink after a reload heals the same. The next bottle, with one fewer
in the stash, rolls again (`test_potions`' `test_road_drink_is_seeded`).

**Strays (§8.8).**

- Six `*.png.import` files at the repo root had no PNG beside them and are
  deleted. The `.gitignore` lines for `figures_idle_*` and the settlement
  gallery now end in `*`, so the next shot run's `.import` stays out too.
- `shots_hiring/` was committed despite `shots_*/` in `.gitignore`. It is
  now untracked.
- `data/lpc/`, four LPC recipes that nothing loaded, is deleted. The design
  bible says so.
- `.github/workflows/update-notes.yml` gives the note-writer the window's
  build-log entries through `tools/plan_log.py`, so it reads `docs/plan/`
  as well as the closed `docs/expansion-plan.md`. This was an
  owner-approved `.github/` edit.

### Still open

- A level-17 sorcerer has six Metamagic picks and five built options, so
  the sixth pick has to repeat one. That lasts until a sixth option is
  built. `core/metamagic.gd`'s header lists the four places a new option
  touches.
- `core/settlement_visit.gd`'s `ponytail:` about reaching the shop catalog
  through a throwaway `Campaign` instance has the same condition as `_bank`
  (`campaign.gd` can now be edited) and is still open. It needs
  `stock_ids` / `service_stock_ids` / `shop_ids` made static on a node, and
  is a separate change.
- The dated design specs under `docs/superpowers/` still mention
  `roster_budget` and `Campaign._split_xp`. They are records of what was
  planned at the time and are left as they are.
- Multiclassing has no way in (§8.5). The owner has noted it for later.
