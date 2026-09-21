# Threat clocks and reclaiming — a lair left alone does something about it

Sub-project 3 of the 2026-09-20 content batch (objectives → landmarks →
**threat clocks and reclaiming** → faction ladder and renown → callings with
party relations → downtime → the lodge). Today a lair the party never touches
is a red dot that waits. It costs nothing to ignore, so the map is a list of
dots, not a set of pressures, and *where do we go next* is never a hard
question. This makes the dots move: a lair nobody clears sends raiders at the
nearest town — visibly, a band on the map you can meet on the road — and a
town that gets raided is a worse town until the lair is dealt with: half a
market, a board full of that lair's work, refugees on the road who can tell
you where the raiders came from. Left longer still, the lair seeds a second.
Clearing it lifts all of that; and in the settled country a cleared lair can
be bought and made into a waystation — a bed, a stall and a name where a hole
in the ground used to be, for the rest of the run. The map gets worse if you
ignore it and better because of you, and both are things you can see.

## 0. Scope

**In:** a per-lair clock (`raid_at`, `raids`) that sends a raiding band at
the nearest civilized settlement in reach; the band's march, siege and
return as a `raid` behaviour on the existing world AI; the raid landing
(market halved, the board's premium, the refugees road event, the map
label); a lair that has raided twice spawning one child lair; the lift when
the lair is cleared, however it is cleared; the hold-the-line objective when
the party meets the raiders at the town's edge; the deed for turning a raid;
reclaiming a cleared heartland/marches lair into a `camp` settlement for
gold; save fields for all of it; tests and the robot.

**Out:** sieges that take a town (a settlement never falls — it is raided,
not razed; razing is the faction ladder's war, C3/#4); raids on the player's
lodge (D2); named raid leaders (parked, #135); a HUD clock widget (the label
on the map carries the hours); a lair that grows in depth or roster (its
interior is `site.gd`'s and does not change — the clock changes the *map*,
not the dungeon); reclaiming in the frontier or the deeps.

**Untouched behaviour:** a map with no settlement within `RAID_REACH` of any
lair never raids; the D1 window (`WorldLairs.WINDOW`) and the respawn
(`RESPAWN`) keep their rules; an old save loads with every clock starting at
load time and no settlement raided.

## 1. The model

```gdscript
# core/world.gd
class Lair:
	# ...existing fields...
	var raid_at := 0.0          # world-clock stamp the raid clock counts from: world start,
	                            # the last set-out, or the last raid turned. Never < 0.
	var raids := 0              # raids that have LANDED; the second one spawns the child
	var raid_band := ""         # id of the band out raiding right now, "" when none
	var spawned_from := ""      # parent lair id for a child; a child never spawns

class Settlement:
	# ...existing fields...
	var raided_by := ""         # lair id while the raid stands, "" otherwise
	var raided_at := -1.0       # when it landed, for the label and the board line
```

`core/raids.gd` (new, static, like `world_lairs.gd`; `Raids` — `WorldThreat`
already names the difficulty assessor) owns the clock, the raid, the
spread, the lift and the reclaim. It preloads `world.gd` (for the classes)
and `world_ai.gd`; neither preloads it back. `scenes/world/world.gd` calls
`Raids.tick(world, now)`
once a frame beside `_check_expired_lairs()` and speaks the lines it returns
through `_lair_msg`, exactly as it does for `expire()` and `respawn()`.

`WorldSave` writes the four lair fields and the two settlement fields; an
old save without them loads `raid_at = clock.elapsed` (the clock starts
when the save is opened, not at day 0 — a day-ten save must not send every
lair out at once) and everything else at its default.

## 2. The clock

A lair is **live** while `not looted`, **undisturbed** while `entered_at
< 0` (D1's window is already counting on a disturbed one, and it resolves
without the party in two days), **settled** while its ground is the
heartland or the marches (`Regions.band_of(world, l.position)` — the same
two bands reclaiming takes, §7), and **near** while some civilized
settlement (`not WorldAI.is_monster(s.faction)`) stands within `RAID_REACH`
of it. Only a live, undisturbed, settled, near lair with no band out raids.
The frontier and the deeps do not raid: what lives there is nobody's problem
until you make it yours, and a deeps-level band at a heartland gate on day
two is a raid nobody can turn.

Its raid is due at `raid_at + (RAID_AFTER if raids == 0 else RAID_EVERY) +
jitter`, where `jitter = hash("raid|" + id) % RAID_JITTER` in world-minutes
— so five lairs do not all set out on the same morning, and the same lair
always sets out on the same morning across a reload.

When it is due, `Raids.tick`:

1. picks the target: the nearest civilized settlement within `RAID_REACH`;
2. adds a `RoamingParty` `"%s-raiders" % lair.id` at the lair's position,
   `faction = lair.faction`, `troops` two entries at the region's lower level
   (`Regions.at(world, lair.position).levels[0]`), heavy and light — the same
   shape the procedural builder gives a band;
3. gives it the `raid` behaviour (§3), pointed at the **siege point** —
   `SIEGE_DIST` units out from the settlement on the lair's side (`_steer`
   nudges it onto dry ground if it lands in water);
4. sets `lair.raid_band = band.id`, `lair.raid_at = now`;
5. returns the line *"Raiders are out from the Ash Warren, making for
   Riverhold."* — said whether or not the party can see either. Word travels;
   the point of the clock is that the player knows it is running.

## 3. The raid on the map

`core/world_ai.gd` gains a fourth behaviour:

```gdscript
static func raid(party, to: Vector2, target: String, home: String) -> void:
	party.ai = {"behavior": "raid", "to": to, "phase": "march",
		"target": target, "home": home, "until": -1.0}

static func _raid_step(world, party):
	# At the gate they come for anyone who comes near: the siege is a thing you
	# meet, not a dot you can walk round. RAID_SIGHT = Visit.BATTLE_RADIUS.
	var s: Dictionary = party.ai
	if String(s.get("phase", "")) == "siege":
		var p = world.player()
		if p != null and not in_truce(party, world.clock.elapsed) \
				and party.position.distance_to(p.position) <= RAID_SIGHT:
			return p.position
	return s["to"]
```

The step only names the destination (`to`; `dest` is `_steer()`'s own key,
the dry point it actually aims at); `_steer()` routes it round the water
like every other behaviour, and `move_toward_goal` walks it. The phases are
`Raids.tick`'s to advance, by reading the band each frame
(`WorldAI.arrived(party)`, a public name for `_arrived` that never reads a
truce's break-off point as arriving):

- **march** — walking to the siege point. On arrival (`party.at_goal()`):
  `phase = "siege"`, `until = now + SIEGE`, line *"Raiders from the Ash
  Warren are camped outside Riverhold."*
- **siege** — standing at the siege point. The map label under the
  settlement reads *"Riverhold — raiders at the gate, 6 h"* counting down.
  When `now >= until`: the raid **lands** (§4), `phase = "home"`, `dest =
  the lair's position`.
- **home** — walking back. On arrival the band is erased from
  `world.parties` and `lair.raid_band = ""`. The lair is quiet again until
  `RAID_EVERY` runs out.

A raid band is a monster band like any other, so everything that already
exists applies unchanged: it is hostile on sight (`WorldAI.is_hostile`); the
player's `_check_encounter` offers the approach card when they meet it; a
civilized patrol that crosses it fights it off-screen (`WorldBattle.check`),
and the town's own economy feels the bodies (`Visit.mark_battle`); the board
posts a `hunt_party` job for it automatically (its id capitalizes to
*"Ash Warren Raiders"*), and that job's fight is a *hunt*.

**Turned.** If the band is gone from `world.parties` — the party beat it,
a patrol beat it — `Raids.tick` finds `lair.raid_band` naming nobody:
`raid_band = ""`, `raid_at = now` (they try again in `RAID_EVERY`). The
credit is the world screen's, and only when the party's own fight beat a
band whose phase was `march` or `siege`: `FactionOpinion.credit_fight(world,
at, TURNED_FOR, foe.faction)` (`TURNED_FOR = 2 × FOUGHT_FOR`),
`Ach.bump("raids_turned")`, the line *"The raid on Riverhold is turned."* A
band beaten on its way home is just a band beaten — the raid has landed and
stands until the lair is cleared.

**Hold the line.** When the party fights a raid band whose phase is `march`
or `siege` within `Visit.BATTLE_RADIUS` of its target settlement,
`_road_objective` returns `Objectives.make("hold", {"waves":
Objectives.waves_for(...)})` — the waves drawn like a site's gate room's, at
the band's own power: the town is behind you and more are coming. Anywhere
else on the road it is a plain fight (or a
*hunt*, if the job is taken). A raid band's *hold* takes precedence over the
*escort* a delivery would give.

## 4. What a raid does

When the siege runs out the raid lands on the settlement:

- `s.raided_by = lair.id`, `s.raided_at = now`, `s.battle_at = now`.
- **Market.** `Visit.market(s, gap, battle, opinion)` is called with `battle
  = battle_recent(s, now) or s.raided_by != ""` — the shelf halves and marks
  up ×1.4 (`BATTLE_STOCK_LOSS`, `BATTLE_MARKUP`, the existing numbers) for as
  long as the raid stands, not for four hours. No new market rule.
- **Board.** The lair's own `clear_lair` job pays `RAID_PREMIUM` × its
  reward while the raid stands (`Quest._world_quest_from_pick` reads
  `raided_by` off the giver), and the board page carries one line under its
  header: *"Raiders from the Ash Warren hit the town on day 3. The market is
  half what it was."* `rescue_offer` prefers the raiding lair over a nearer
  one (`Site.pens_ahead` still gates it — a raid takes people, and the pens
  are where they are kept) with the captive *"the people taken in the
  raid"*.
- **Road.** `Travel.EVENTS` gains `refugees` — `needs: "raided"`, skills
  persuasion / insight / medicine, DC 12, kind `good`, bands heartland and
  marches: *"Families on the road with what they could carry."* Pass: *"%s
  gets the story out of them, and the way back to where it came from."* — the
  raiding lair is `discovered` (a raid makes the hidden findable; that is the
  clock giving something back). Fail: *"They have nothing left to give but
  the road, and they give that."* `_needs_met("raided")` is *some settlement
  has `raided_by != ""` and that lair is still undiscovered*, so the event
  only rolls when its pass would do something.
- **Label.** The settlement's map label (`ground_marks()`) reads
  *"Riverhold — raided"* until lifted; the lair's reads *"the Ash Warren —
  raiding"* while its band is out. The minimap has no labels and stays as it
  is.
- `raids += 1`. If `raids == 2` and `spawned_from == ""`, the lair spreads
  (§5).

A settlement holds one raid at a time (`raided_by` is a string, not a list):
a second lair landing on an already-raided town overwrites the id and
refreshes the stamp — worse does not get worse than halved.

## 5. Spread

On its second landing a root lair (one with no `spawned_from`) seeds a
child: `Raids.spread(world, lair, now)` places a new `Lair` of the same
faction between `SPREAD_MIN` and `SPREAD_MAX` units from the parent, on dry
ground (`not world.is_water`), at least `ProceduralWorld.MIN_MONSTER_GAP`
from every settlement and `SPREAD_MIN` from every other lair, trying
`SPREAD_TRIES` seeded angles and giving up (no child) if none fits. Its id is
`"%s-2" % parent.id`, its name *"the Ash Warren's outpost"* (the parent's
`sname` possessive), `spawned_from = parent.id`, `raid_at = now`,
undiscovered. The line: *"Something has dug in near the Ash Warren."* The
world screen resets `_lairs3d` when the list grows, the way it does for a
found landmark.

A child raids on its own clock like any lair but never spreads, so a map
can at most double its lairs and then stop. A child is a real lair: clearing
the parent does not remove it — that is the cost of the second landing, and
it is paid once.

## 6. Lifting it

`WorldLairs.mark_cleared` is already the one place a lair is spent — fought
to the bottom, sneaked past, resolved by D1's window as *cleared* or
*abandoned* — and `Raids.tick` polls for it rather than hooking it: any
settlement whose `raided_by` names a lair that is looted, or gone from the
map, is lifted — `raided_by = ""`, `raided_at = -1.0` — and a band out
raiding for a looted lair (`raid_band`) is erased wherever it stands: its
lair is gone and it has nowhere to go home to; `raid_band = ""`. Polling
keeps every way of spending a lair covered, including the ones an old save
took before this rule existed. The world screen says *"Riverhold breathes again — the Ash Warren is done raiding."* for
each lifted settlement and credits the deed: `FactionOpinion.raise(s.faction,
LIFTED_FOR)` per lifted settlement, `Ach.bump("raids_lifted")`.

A respawned lair (`RESPAWN`, one day after clearing) is a fresh lair:
`respawn()` also sets `raid_at = now`, `raids = 0` — something new moved in,
with its own patience. `spawned_from` is kept; a respawned child still never
spreads.

## 7. Reclaiming

A cleared lair in the settled country can be **settled** instead of waiting
for something to move back in. The window is the respawn's own: while
`looted and cleared_at >= 0` (up to one day), and only for a lair whose
ground is the heartland or the marches (`Regions.band_of(world, l.position)
in ["heartland", "marches"]`) with some civilized settlement on the map to
send settlers. The lair button row gains a third button beside *Attack* and
*Sneak past* while the party stands within `WorldLairs.DISCOVER_RADIUS` of
such a lair: **Settle it (120 ◉)** — `RECLAIM_COST[band]`, heartland 120,
marches 240, greyed with *"not enough gold"* if the purse is short.

`Raids.settle(world, lair, party, now)`:

- takes the gold; erases the lair from `world.lairs` for good (no respawn —
  it is not a hole any more);
- adds `Settlement(id = "way-" + lair.id, position = lair.position, faction
  = the nearest civilized settlement's, kind = "camp", sname = a name from
  `WAYSTATION_NAMES` seeded off the lair id and deduped against the map's
  settlements — Fairstead, Newhold, Hollowell, Whitecross, Longwater,
  Kingsrest, Ashford, Stonebridge, Greenhalt, Oldwell)`, `last_visited =
  now` (a fresh market, not a six-step-stale one);
- pays the deed: `SETTLE_XP × (ring + 1)` through `Campaign._split_xp`, and
  `FactionOpinion.raise(faction, LIFTED_FOR)`; `Ach.collect("waystations",
  id)` with `waystations_1` (*Homesteader*) and `waystations_3` (*Founder*);
- returns the settlement; the world screen resets `_settlements3d` and
  `_lairs3d`, drops `_lair_target`, and says *"Settlers from Riverhold put up
  the first roof at Fairstead."*

What a waystation is, is what a `camp` already is: a bed at `INN_COST.camp`
(10 ◉ — a safe long rest on the road that used to need a kit or a walk
back), the generalist's stall, the generalist's jobs (deliveries, scouting,
the lair down the valley), rumours, a beacon that keeps its stretch of road
explored (`SETTLEMENT_BEACON_RADIUS`), and a settlement's protection from
the night road. It draws with the kit's `camp` plan in the settlers'
faction. It can be raided like any settlement, so a waystation near a
second lair is a reason to clear that one too. Nothing new is built for it;
that is the point — the `camp` kind existed and nothing put one on the map
mid-run.

## 8. Numbers, and how they get checked

| constant | value | why |
|---|---|---|
| `RAID_REACH` | 800 | `clear_lair`'s posting reach — a lair a town would post work about is a lair that can reach it |
| `RAID_AFTER` | 2 days (2880) | the first raid lands inside a session: a day is ~24 real minutes at 1× |
| `RAID_EVERY` | 2 days | ...and keeps landing until dealt with |
| `RAID_JITTER` | 1 day (1440) | five lairs, five mornings |
| `SIEGE` | 8 h (480) | one long rest's worth of warning; the band is at the gate for a real stretch of play, not the forty world-minutes its walk takes |
| `SIEGE_DIST` | 100 | inside `Visit.BATTLE_RADIUS` (140): a fight at the siege point is a fight *at the town* |
| `RAID_PREMIUM` | 1.5 | the lair's job pays half again while it raids |
| `TURNED_FOR` | 10 | `2 × FOUGHT_FOR`: turning a raid is worth two bands put down |
| `LIFTED_FOR` | 10 | `QUEST_DONE`: lifting a raid is a job done, whether or not it was posted |
| `SPREAD_MIN`, `SPREAD_MAX`, `SPREAD_TRIES` | 150, 300, 24 | close enough to read as the same trouble, far enough to be its own dot |
| `RECLAIM_COST` | heartland 120, marches 240 | three and six nights at a town inn: a real sink, once, for a permanent bed |
| `SETTLE_XP` | 60 | a landmark and a half: the biggest deed on the map that is not a fight |

**What it costs to ignore.** Measured on the shipped maps: every lair on
the small map has a town within 800 (the dragon's cave is 341 from
Greenmarch), and four of five on the large — reach alone would have five
raids landing by day 4. The ground gate leaves two raiding lairs on each:
the goblin warren and the Sunken Ruins (heartland and marches on both maps;
the giant's hold, the graveyard and the dragon's cave sit in the frontier
and the deeps). Do nothing for six days and both have raided twice and
spread: two towns at half a market, four lairs where there were two. Clear
one and its town is whole again inside the same visit.

Tests (`tests/test_raids.gd`, pure, no scene): a near, live, undisturbed
lair sets out at its due time and not before; a far, a disturbed and a
looted one never do; the band marches, sieges for `SIEGE`, lands (market
halved, board premium, label, `raids == 1`), walks home and is erased; a
band erased mid-march resets the clock and lands nothing; the second landing
spawns exactly one child on dry ground inside the gaps, and a third does
not; a child never spreads; `mark_cleared` lifts every settlement the lair
raided and erases its band; `respawn` resets the clock; the refugees event
only rolls while some raiding lair is undiscovered and its pass discovers
it; `can_settle` is true only in the window, in the two bands, with gold;
`settle` removes the lair, adds a `camp` of the right faction with a deduped
name, takes the gold, pays the XP; a save round-trips all six fields and an
old save starts its clocks at load. `tests/test_world_save.gd` gains the
round trip; `tests/test_quest_posting.gd` the premium and the rescue
preference. `drive_random.gd` learns the *Settle it* button (one weighted
roll beside *Attack*) and its frame invariants gain "a settled lair is not
in `world.lairs`" and "a raided settlement's market never shows more than
the halved shelf".

## 9. Files

| file | change |
|---|---|
| `core/world.gd` | four `Lair` fields, two `Settlement` fields |
| `core/raids.gd` | new: `tick()`, `spread()`, `settle_cost()`, `settle()`, the tags, the constants, `WAYSTATION_NAMES` |
| `core/world_ai.gd` | `raid()` behaviour, `_raid_step()`, `arrived()`, `RAID_SIGHT` |
| `core/world_lairs.gd` | `respawn` resets the clock |
| `core/world_save.gd` | the six fields in and out; old-save clock start |
| `core/settlement_visit.gd` | `market`'s `battle` flag includes `raided_by` |
| `core/quest.gd`, `core/quest_posting.gd` | `RAID_PREMIUM`; `rescue_offer` prefers the raider |
| `core/travel.gd` | the `refugees` event and `needs: "raided"` |
| `core/achievements.gd` | `raids_turned`, `raids_lifted`, `waystations_1/3` |
| `scenes/world/world.gd` | `Raids.tick` in `_process`; the lines; the *Settle it* button; `hold` in `_road_objective`; the turned credit; labels; the board line |
| `tests/test_raids.gd`, `tests/test_world_raids.gd`, `tests/test_world_save.gd`, `tests/test_quest_posting.gd`, `tests/drive_random.gd` | §8 |
| `docs/expansion-plan.md` | the shipped record |

## 10. Open, decided here unless overruled

- **A raid is a band, not a state flip.** The invisible version (the town
  just wakes up raided) is a tenth of the code and none of the play: the
  band on the road is what makes the clock something you can act on, and it
  costs nothing new — hostility, encounters, patrols, the hunt job and the
  3D figure all already exist for a band.
- **The siege is the warning.** A band walks lair-to-town in twenty world
  minutes; without the eight-hour stand at the gate no player would ever
  meet one. The stand is also what makes *hold the line* the right fight.
- **A settlement is never taken.** Raided is as bad as it gets. A town that
  falls is a war, and wars are the faction ladder's (#4).
- **Reclaiming is bought, at once, by the party, at the lair.** Not
  automatic after N days (nothing the player did), not a job (a job ends —
  this is a purchase that stays). The one-day window is the respawn's own
  clock, so it is one deadline, not two.
- **A child stays when its parent is cleared.** Otherwise the second landing
  costs nothing and the spread is decoration. It is capped at one per root
  and never spreads itself, so the worst map is twice the lairs, not a
  runaway.
- **The lair does not get harder.** Its interior and roster are `site.gd`'s
  and the region's. What escalates is the map around it — a spreading
  problem, not a taller one — which is the pressure this batch is for; a
  taller one is what the ladder's tiers already do to the board's jobs.
- **Raid bands do not loot.** What they carry home is not modelled; the
  town's halved market *is* what they took.
