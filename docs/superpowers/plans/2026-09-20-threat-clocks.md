# Threat Clocks and Reclaiming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lair in the settled country that nobody clears sends a visible raiding band at the nearest town; a raided town is half a market and a board full of that lair's work until the lair is cleared; the second raid seeds a child lair; a cleared heartland/marches lair can be bought into a `camp` settlement.

**Architecture:** One new static module, `core/raids.gd` (`Raids`), owns the clock, the set-out, the phases, the landing, the spread, the lift and the reclaim — polled once a frame by the world screen the way `WorldLairs.expire/respawn` already are. The raid band is an ordinary `RoamingParty` with a new `raid` behaviour in `core/world_ai.gd`, so hostility, encounters, off-screen battles, hunt jobs and the 3D figure all come for free. Six new save fields; the market, the board, the road table and the world screen each get one small hook.

**Tech Stack:** Godot 4.7 / GDScript. Tests are plain `SceneTree` scripts run headless: `timeout 120 godot --headless --path . -s tests/<file>.gd` (exit 0 = pass; every check prints `FAIL:` on failure). Run one file per step; the whole suite is `tools/run_tests.sh --unit` and is for the final review only.

**Spec:** `docs/superpowers/specs/2026-09-20-threat-clocks-design.md`

## Global Constraints

- Every godot invocation is `--headless`. Never open a window.
- `Array[Dictionary]` fields (`RoamingParty.troops`) are typed: `.append` entries, never assign a literal array.
- `core/raids.gd` preloads `core/world.gd` and `core/world_ai.gd`; neither of those, nor `core/world_lairs.gd`, `core/settlement_visit.gd`, `core/quest.gd`, `core/quest_posting.gd` or `core/travel.gd`, may preload `core/raids.gd` (cycles). Use `load()` at call time if one of them ever needs it — none does in this plan.
- The module is `Raids` in `core/raids.gd`. `core/world_threat.gd` (`WorldThreat`) already exists and is the difficulty assessor — do not touch it, do not name anything `Threat`.
- Constants, verbatim from the spec: `RAID_REACH 800.0`, `RAID_AFTER 2880.0`, `RAID_EVERY 2880.0`, `RAID_JITTER 1440`, `SIEGE 480.0`, `SIEGE_DIST 100.0`, `RAID_SIGHT 140.0` (lives in `world_ai.gd`), `RAID_PREMIUM 1.5`, `TURNED_FOR 10.0`, `LIFTED_FOR 10.0`, `SPREAD_MIN 150.0`, `SPREAD_MAX 300.0`, `SPREAD_TRIES 24`, `SPREAD_TOWN_GAP 300.0`, `RECLAIM_COST {"heartland": 120, "marches": 240}`, `SETTLE_XP 60`.
- Copy, verbatim from the spec: set-out *"Raiders are out from %s, making for %s."*; siege *"Raiders from %s are camped outside %s."*; landing *"%s is raided — the market is half what it was, and %s wants it answered."*; spread *"Something has dug in near %s."*; lift *"%s breathes again — %s is done raiding."*; turned *"The raid on %s is turned."*; settle *"Settlers from %s put up the first roof at %s."*; labels *" — raided"*, *" — raiders at the gate, %d h"*, *" — raiding"*; board line *"Raiders from %s hit the town on %s. The market is half what it was."*; refugees title *"Families on the road with what they could carry."*, pass *"%s gets the story out of them, and the way back to where it came from."*, fail *"They have nothing left to give but the road, and they give that."*
- `WAYSTATION_NAMES`: Fairstead, Newhold, Hollowell, Whitecross, Longwater, Kingsrest, Ashford, Stonebridge, Greenhalt, Oldwell.
- A raid band's id is `"%s-raiders" % lair.id`; a child lair's id is `"%s-2" % parent.id`, its name `"%s's outpost" % parent.sname`; a waystation's id is `"way-" + lair.id`.
- Commit after every task with a message in the repo's voice (a sentence about what changed and why, no conventional-commit prefixes), ending with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- Match the comment density and voice of the file you are in (`core/world_lairs.gd` is the model). New tests follow `tests/test_world_lairs.gd`'s shape: `extends SceneTree`, `check(cond, label)`, a final `print("<name>: %d passed, %d failed")` and `quit(1 if _fail > 0 else 0)`.

---

### Task 1: The model and the save — six fields, and a respawn that resets the clock

**Files:**
- Modify: `core/world.gd` (`class Lair` ~127–158, `class Settlement` ~100–125)
- Modify: `core/world_save.gd` (`to_dict` ~74–101, `from_dict` ~142–175)
- Modify: `core/world_lairs.gd` (`respawn` ~178–190)
- Test: `tests/test_world_save.gd`, `tests/test_lair_respawn.gd`

**Interfaces:**
- Produces: `Lair.raid_at: float` (default `0.0`), `Lair.raids: int` (`0`), `Lair.raid_band: String` (`""`), `Lair.spawned_from: String` (`""`); `Settlement.raided_by: String` (`""`), `Settlement.raided_at: float` (`-1.0`). Every later task reads these by name.

- [ ] **Step 1: Write the failing save round-trip test**

Open `tests/test_world_save.gd`, find the `_init()` body, and add before its final `print(` line:

```gdscript
	# --- raids: six fields ride the save; an old save starts its clocks at load
	var wr := World.new()
	var sr := wr.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	var lr := wr.add_lair(World.Lair.new("warren", Vector2(300, 0), "goblinoid"))
	wr.clock.elapsed = 5000.0
	lr.raid_at = 4000.0
	lr.raids = 2
	lr.raid_band = "warren-raiders"
	lr.spawned_from = "root"
	sr.raided_by = "warren"
	sr.raided_at = 4500.0
	var dr: Dictionary = WorldSave.to_dict(wr)
	var back = WorldSave.from_dict(dr)
	var lb = back.lairs[0]
	var sb = back.settlements[0]
	check(lb.raid_at == 4000.0 and lb.raids == 2 and lb.raid_band == "warren-raiders" and lb.spawned_from == "root",
		"a lair's four raid fields round-trip")
	check(sb.raided_by == "warren" and sb.raided_at == 4500.0, "a settlement's two raid fields round-trip")
	dr["lairs"][0].erase("raid_at")
	dr["lairs"][0].erase("raids")
	dr["settlements"][0].erase("raided_by")
	var old = WorldSave.from_dict(dr)
	check(old.lairs[0].raid_at == 5000.0, "an old save's clock starts at load time, not day 0 (%s)" % old.lairs[0].raid_at)
	check(old.lairs[0].raids == 0 and old.settlements[0].raided_by == "", "...and nothing is raided")
```

(Check the file's existing `const` block: it already preloads `World` and `WorldSave`; if the names differ, use the file's own.)

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_world_save.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: a SCRIPT ERROR — `raid_at` is not a member of `Lair`.

- [ ] **Step 3: Add the fields**

In `core/world.gd`, inside `class Lair`, after the `cleared_at` field:

```gdscript
	# Raids (core/raids.gd): the clock a lair left alone runs against the
	# nearest town. raid_at is what it counts from — world start, the last
	# set-out, or the last raid turned — and is never < 0; raids counts the ones
	# that LANDED (the second seeds a child); raid_band names the band out
	# raiding right now; spawned_from names a child's parent, and a child never
	# spawns one of its own.
	var raid_at := 0.0
	var raids := 0
	var raid_band := ""
	var spawned_from := ""
```

Inside `class Settlement`, after `pending_opinion_delta`:

```gdscript
	# Raids: the lair whose raid stands on this town, "" when none. The market
	# reads it (halved shelf), the board reads it (that lair's job pays more),
	# the road reads it (refugees). Lifted when that lair is spent.
	var raided_by := ""
	var raided_at := -1.0
```

- [ ] **Step 4: Save and load them**

In `core/world_save.gd` `to_dict`, in the settlement dictionary add after `"pending_opinion_delta": s.pending_opinion_delta,`:

```gdscript
			"raided_by": s.raided_by, "raided_at": s.raided_at,
```

In the lair dictionary add after `"entered_at": l.entered_at, "resolved_as": l.resolved_as,`:

```gdscript
			"raid_at": l.raid_at, "raids": l.raids, "raid_band": l.raid_band,
			"spawned_from": l.spawned_from,
```

In `from_dict`, after `s.pending_opinion_delta = ...`:

```gdscript
		s.raided_by = String(sd.get("raided_by", ""))
		s.raided_at = float(sd.get("raided_at", -1.0))
```

After `l.cleared_at = float(ld.get("cleared_at", -1.0))`:

```gdscript
		# A save from before the clocks starts them now, not at day 0 — a day-ten
		# save must not send every lair on the map out at once on load.
		l.raid_at = float(ld.get("raid_at", world.clock.elapsed))
		l.raids = int(ld.get("raids", 0))
		l.raid_band = String(ld.get("raid_band", ""))
		l.spawned_from = String(ld.get("spawned_from", ""))
```

(`world.clock.elapsed` is set from `d["elapsed"]` before the settlement loop — verify it is; it is on line ~141.)

- [ ] **Step 5: Run the save test**

Run: `timeout 120 godot --headless --path . -s tests/test_world_save.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `test_world_save: N passed, 0 failed`.

- [ ] **Step 6: Write the failing respawn test**

In `tests/test_lair_respawn.gd`, before the final `print(`:

```gdscript
	# raids: something new moved in, with its own patience — the clock restarts
	var wq := World.new()
	var lq := wq.add_lair(World.Lair.new("q", Vector2.ZERO, "goblinoid"))
	lq.raids = 2
	lq.raid_at = 100.0
	WorldLairs.mark_cleared(lq, 1000.0)
	var came: Array = WorldLairs.respawn(wq, 1000.0 + WorldLairs.RESPAWN)
	check(came.size() == 1 and lq.raids == 0 and lq.raid_at == 1000.0 + WorldLairs.RESPAWN,
		"a respawned lair's raid clock restarts at the respawn (%s, %d)" % [lq.raid_at, lq.raids])
```

(Use the file's own preload names for `World` and `WorldLairs`; add them if missing.)

- [ ] **Step 7: Run it to see it fail, then make it pass**

Run: `timeout 120 godot --headless --path . -s tests/test_lair_respawn.gd 2>&1 | grep -E "FAIL|passed" | head`
Expected: `FAIL: a respawned lair's raid clock restarts...`

In `core/world_lairs.gd` `respawn()`, after `l.resolved_as = ""`:

```gdscript
		l.raid_at = now           # raids: something new moved in, with its own patience
		l.raids = 0
```

Run again. Expected: `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add core/world.gd core/world_save.gd core/world_lairs.gd tests/test_world_save.gd tests/test_lair_respawn.gd
git commit -m "Raids: six fields on the model, saved, and a respawned lair's clock starts over"
```

---

### Task 2: `core/raids.gd` — the clock, the band, the phases, the landing, the lift

**Files:**
- Create: `core/raids.gd`
- Modify: `core/world_ai.gd` (`update` ~132–146, after `hunt` ~94, after `_arrived` ~176)
- Test: `tests/test_raids.gd` (new), `tests/test_world_ai.gd`

**Interfaces:**
- Consumes: Task 1's fields; `WorldAI.in_truce(party, now)`, `WorldAI._arrived(party)`, `WorldAI._steer` (sets `ai["dest"]`); `Regions.at(world, pos)` → `{"id", "levels": [lo, hi], "index", ...}`; `World.RoamingParty.new(id, pos, faction)`, `world.add_party`, `world.parties.erase`; `FactionOpinion.raise(faction, amount)`; `Ach.bump(key)`.
- Produces:
  - `WorldAI.raid(party, to: Vector2, target: String, home: String) -> void`; `WorldAI.arrived(party) -> bool`; `WorldAI.RAID_SIGHT := 140.0`.
  - `Raids.tick(world, now: float) -> Array` of String lines; `Raids.due_at(lair) -> float`; `Raids.is_settled(world, lair) -> bool`; `Raids.target_for(world, lair)` → Settlement or null; `Raids.set_out(world, lair, s, now)` → RoamingParty; `Raids.band_of(world, lair)` → RoamingParty or null; `Raids.lair_of(world, id)`; `Raids.settlement_of(world, id)`; `Raids.land(world, lair, s, now) -> Array`; `Raids.turnable(foe) -> bool`; `Raids.settlement_tag(world, s, now) -> String`; `Raids.lair_tag(lair) -> String`. (`spread`, `settle_cost`, `settle` come in Tasks 3 and 6 — leave a `spread()` stub returning `null` here so `land()` compiles; Task 3 fills it.)

- [ ] **Step 1: Write the failing world_ai test**

In `tests/test_world_ai.gd`, before the final `print(`:

```gdscript
	# raid: a destination-only behaviour; at the gate it comes for a player in sight
	var wr := World.new()
	var town := wr.add_settlement(World.Settlement.new("t", Vector2.ZERO, "human", "town"))
	var pl := wr.add_party(World.RoamingParty.new("player", Vector2(2000, 0), "human", true))
	var rb := wr.add_party(World.RoamingParty.new("w-raiders", Vector2(300, 0), "goblinoid"))
	WorldAI.raid(rb, Vector2(100, 0), "t", "w")
	check(rb.ai["behavior"] == "raid" and rb.ai["phase"] == "march" and rb.ai["to"] == Vector2(100, 0)
		and rb.ai["target"] == "t" and rb.ai["home"] == "w", "raid() sets the whole state")
	WorldAI.update(wr)
	check(rb.goal == Vector2(100, 0), "marching: the goal is the siege point")
	check(not WorldAI.arrived(rb), "not there yet")
	rb.position = Vector2(100, 0)
	check(WorldAI.arrived(rb), "arrived() is public and true on the steered destination")
	rb.ai["phase"] = "siege"
	pl.position = Vector2(100, 50)
	WorldAI.update(wr)
	check(rb.goal == pl.position, "at the gate, a player inside RAID_SIGHT is chased")
	pl.position = Vector2(100, 1000)
	WorldAI.update(wr)
	check(rb.goal == Vector2(100, 0), "...and out of sight, it stands at the gate again")
	pl.position = Vector2(100, 50)
	WorldAI.truce(rb, pl, wr.clock.elapsed)
	WorldAI.update(wr)
	check(rb.goal != pl.position, "a truced raid band does not chase")
```

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_world_ai.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: SCRIPT ERROR — `raid` not found in `WorldAI`.

- [ ] **Step 3: Add the behaviour**

In `core/world_ai.gd`, after `const REPLAN_RETRY_MINUTES := 5.0`:

```gdscript
# How near the player has to come to a band standing siege for it to come
# for them: the siege is a thing you meet at the town's edge, not a dot you
# can walk round. The same 140 as settlement_visit.gd's BATTLE_RADIUS, so a
# fight it starts is a fight "at the town".
const RAID_SIGHT := 140.0
```

After `static func hunt(party) -> void:` (and its body):

```gdscript
# A lair's raiders (core/raids.gd): walk to `to`, stand there, walk home.
# The band only ever names where it is going; raids.gd advances `phase` and
# rewrites `to` by reading the band each frame. `to` is deliberately not
# `dest` — that key is _steer()'s own, the dry point it actually aims at.
static func raid(party, to: Vector2, target: String, home: String) -> void:
	party.ai = {"behavior": "raid", "to": to, "phase": "march",
		"target": target, "home": home, "until": -1.0}
```

After `static func _arrived(party) -> bool:` (and its body):

```gdscript
# The same test, for the module that advances a raid's phases.
static func arrived(party) -> bool:
	return _arrived(party)
```

In `update()`, add a fourth match arm:

```gdscript
				"raid": dest = _raid_step(world, p)
```

After `_hunt_step` at the end of the file:

```gdscript
# At the gate they come for anyone who comes near, truce permitting; on the
# road there and back they keep to their own business.
static func _raid_step(world, party):
	var s: Dictionary = party.ai
	if String(s.get("phase", "")) == "siege":
		var p = world.player()
		if p != null and not in_truce(party, world.clock.elapsed) \
				and party.position.distance_to(p.position) <= RAID_SIGHT:
			return p.position
	return s["to"]
```

- [ ] **Step 4: Run the world_ai test**

Run: `timeout 120 godot --headless --path . -s tests/test_world_ai.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `0 failed`.

- [ ] **Step 5: Write the failing raids test**

Create `tests/test_raids.gd`:

```gdscript
# Raids (core/raids.gd): a lair left alone sends a band at the nearest town,
# the band marches, stands siege, lands the raid and walks home; clearing the
# lair lifts it. Pure, no scene.
#   godot --headless --path . -s tests/test_raids.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ach = preload("res://core/achievements.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Riverhold at the origin (the anchor), a lair 300 out: heartland ground on a
# map whose extent is Regions.MIN_EXTENT (700). A player far away.
func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(0, -600), "human", true))
	w.add_lair(World.Lair.new("warren", Vector2(300, 0), "goblinoid", "the Ash Warren"))
	return w

# One frame of the world without the screen: steer, walk, then the raids poll —
# the same order scenes/world/world.gd's _process keeps.
func _frame(w: World, minutes := 1.0) -> Array:
	WorldAI.update(w)
	w.tick(minutes)
	return Raids.tick(w, w.clock.elapsed)

func _run(w: World, minutes: int) -> Array:
	var lines: Array = []
	for i in minutes:
		lines.append_array(_frame(w))
	return lines

func _init() -> void:
	# A scratch save dir, so the deed counters below never touch the real
	# achievements file (the same isolation tests/test_landmarks.gd uses).
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/raids-%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	test_gates()
	test_march_siege_land_home()
	test_turned()
	test_lift()
	print("test_raids: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_gates() -> void:
	var w := _world()
	var l = w.lairs[0]
	var due: float = Raids.due_at(l)
	check(due >= Raids.RAID_AFTER and due < Raids.RAID_AFTER + Raids.RAID_JITTER,
		"the first raid is due RAID_AFTER plus under a day of jitter (%s)" % due)
	check(Raids.due_at(l) == due, "...and the same time every time it is asked")
	check(Raids.is_settled(w, l), "300 from the anchor on a 700 map is settled country")
	check(Raids.target_for(w, l) == w.settlements[0], "the town is its target")
	w.clock.elapsed = due - 1.0
	check(Raids.tick(w, w.clock.elapsed).is_empty() and l.raid_band == "", "a minute early: nothing")
	w.clock.elapsed = due
	var lines: Array = Raids.tick(w, w.clock.elapsed)
	check(lines.size() == 1 and "Raiders are out from the Ash Warren, making for Riverhold." in lines[0],
		"on the minute: the band sets out, and it is said (%s)" % str(lines))
	var b = Raids.band_of(w, l)
	check(b != null and b.id == "warren-raiders" and b.faction == "goblinoid" and l.raid_band == b.id,
		"the band is on the map and the lair names it")
	check(b.troops.size() == 2 and int(b.troops[0]["level"]) == 1, "two troops at the region's floor level")
	check(b.ai["behavior"] == "raid" and b.ai["target"] == "riverhold" and b.ai["home"] == "warren", "...with the raid behaviour")
	check(Vector2(b.ai["to"]).distance_to(Vector2.ZERO) == Raids.SIEGE_DIST
		and Vector2(b.ai["to"]).x > 0.0, "the siege point is SIEGE_DIST out on the lair's side")
	check(l.raid_at == due, "the clock counts from the set-out now")
	check(Raids.tick(w, w.clock.elapsed).is_empty(), "a lair with a band out does not send another")

	# the three gates that stop a raid
	var w2 := _world()
	w2.lairs[0].looted = true
	w2.clock.elapsed = 99999.0
	check(Raids.tick(w2, 99999.0).is_empty(), "a looted lair never raids")
	var w3 := _world()
	w3.lairs[0].entered_at = 10.0
	check(Raids.tick(w3, 99999.0).is_empty(), "a disturbed lair never raids (D1's window has it)")
	var w4 := _world()
	w4.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))   # extent 2000
	var deep = w4.add_lair(World.Lair.new("deep", Vector2(1900, 0), "undead"))
	check(not Raids.is_settled(w4, deep), "1900 of 2000 is the deeps")
	check(Raids.tick(w4, 99999.0).size() == 1 and deep.raid_band == "", "the deeps lair sits it out; the warren goes")
	var w5 := World.new()
	w5.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w5.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))
	var lonely = w5.add_lair(World.Lair.new("lonely", Vector2(900, 0), "goblinoid"))
	check(Raids.is_settled(w5, lonely) and Raids.target_for(w5, lonely) == null,
		"heartland ground, but no town inside RAID_REACH: no target")
	check(Raids.tick(w5, 99999.0).is_empty(), "...so it never raids")
	var w6 := _world()
	w6.settlements[0].faction = "orc"
	check(Raids.target_for(w6, w6.lairs[0]) == null, "a monster settlement is not a target")

func test_march_siege_land_home() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	w.clock.elapsed = Raids.due_at(l)
	Raids.tick(w, w.clock.elapsed)
	var b = Raids.band_of(w, l)
	# 200 units at 40/minute: five minutes to the gate
	var lines: Array = _run(w, 4)
	check(b.ai["phase"] == "march" and lines.is_empty(), "four minutes in, still marching")
	lines = _run(w, 2)
	check(b.ai["phase"] == "siege", "at the siege point the phase turns")
	check(lines.size() == 1 and "Raiders from the Ash Warren are camped outside Riverhold." in lines[0],
		"...and it is said (%s)" % str(lines))
	var until: float = float(b.ai["until"])
	check(absf(until - (w.clock.elapsed + Raids.SIEGE)) < 1.5, "the siege runs SIEGE from arrival")
	check(Raids.settlement_tag(w, s, w.clock.elapsed) == " — raiders at the gate, 8 h", "the label counts the hours (%s)" % Raids.settlement_tag(w, s, w.clock.elapsed))
	check(Raids.lair_tag(l) == " — raiding", "the lair's label says its band is out")
	check(s.raided_by == "" and l.raids == 0, "nothing has landed yet")
	check(Raids.turnable(b), "a band at the gate can still be turned")
	# stand the siege out
	w.clock.elapsed = until - 1.0
	lines = _frame(w, 0.5)
	check(s.raided_by == "" and lines.is_empty(), "half a minute short: not yet")
	lines = _frame(w, 1.0)
	check(s.raided_by == "warren" and s.raided_at == w.clock.elapsed and s.battle_at == w.clock.elapsed,
		"on the hour the raid lands: the town names the lair, and the market feels it")
	check(l.raids == 1, "the lair counts a landing")
	check(lines.size() == 1 and "Riverhold is raided" in lines[0] and "the Ash Warren wants it answered" in lines[0],
		"...and it is said (%s)" % str(lines))
	check(b.ai["phase"] == "home" and Vector2(b.ai["to"]) == l.position, "then it heads home")
	check(not Raids.turnable(b), "a band on its way home is not a raid to turn")
	check(Raids.settlement_tag(w, s, w.clock.elapsed) == " — raided", "the label now says raided")
	lines = _run(w, 6)
	check(Raids.band_of(w, l) == null and l.raid_band == "" and not w.parties.has(b), "home, and gone inside")
	check(Raids.lair_tag(l) == "", "...and the lair's label is quiet")
	check(Raids.due_at(l) >= l.raid_at + Raids.RAID_EVERY, "the next raid is RAID_EVERY out")
	check(s.raided_by == "warren", "the raid stands on the town after the band is gone")
	# a second lair landing on the same town overwrites, never stacks
	var l2 = w.add_lair(World.Lair.new("den", Vector2(-300, 0), "bandit"))
	Raids.land(w, l2, s, w.clock.elapsed + 5.0)
	check(s.raided_by == "den" and s.raided_at == w.clock.elapsed + 5.0 and l2.raids == 1,
		"one raid at a time: the later lair takes the town over")

func test_turned() -> void:
	var w := _world()
	var l = w.lairs[0]
	w.clock.elapsed = Raids.due_at(l)
	Raids.tick(w, w.clock.elapsed)
	var b = Raids.band_of(w, l)
	_run(w, 2)
	w.parties.erase(b)                       # the party, or a patrol, beat it on the road
	var now: float = w.clock.elapsed + 10.0
	w.clock.elapsed = now
	var lines: Array = Raids.tick(w, now)
	check(l.raid_band == "" and l.raid_at == now and l.raids == 0 and w.settlements[0].raided_by == "",
		"a band gone before it landed: the clock resets, nothing landed, no line (%s)" % str(lines))
	check(lines.is_empty(), "the lair says nothing about a band it has lost")
	check(Raids.due_at(l) - now >= Raids.RAID_EVERY and Raids.due_at(l) - now < Raids.RAID_EVERY + Raids.RAID_JITTER,
		"the next try is RAID_EVERY plus the lair's own jitter (%s)" % (Raids.due_at(l) - now))

func test_lift() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	FactionOpinion.reset()
	Raids.land(w, l, s, 100.0)
	check(s.raided_by == "warren", "raided")
	var before: int = Ach.count("raids_lifted")
	var op: float = FactionOpinion.get_opinion("human")
	WorldLairs.mark_cleared(l, 200.0)
	var lines: Array = Raids.tick(w, 200.0)
	check(s.raided_by == "" and s.raided_at == -1.0, "clearing the lair lifts the raid")
	check(lines.size() == 1 and "Riverhold breathes again — the Ash Warren is done raiding." in lines[0],
		"...and it is said (%s)" % str(lines))
	check(FactionOpinion.get_opinion("human") == op + Raids.LIFTED_FOR, "the town's faction thanks you")
	check(Ach.count("raids_lifted") == before + 1, "the deed is counted")
	check(Raids.tick(w, 201.0).is_empty(), "lifted once")
	# a band out for a lair that gets cleared under it has nowhere to go
	var w2 := _world()
	var l2 = w2.lairs[0]
	w2.clock.elapsed = Raids.due_at(l2)
	Raids.tick(w2, w2.clock.elapsed)
	var b2 = Raids.band_of(w2, l2)
	WorldLairs.mark_cleared(l2, w2.clock.elapsed)
	Raids.tick(w2, w2.clock.elapsed)
	check(not w2.parties.has(b2) and l2.raid_band == "", "its band is gone from the map")
	# a lair gone from the map (settled) lifts too
	var w3 := _world()
	Raids.land(w3, w3.lairs[0], w3.settlements[0], 100.0)
	w3.lairs.clear()
	Raids.tick(w3, 200.0)
	check(w3.settlements[0].raided_by == "", "a lair no longer on the map lifts its raid")
```

- [ ] **Step 6: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: SCRIPT ERROR — `res://core/raids.gd` does not exist.

- [ ] **Step 7: Write `core/raids.gd`**

```gdscript
# Raids — a lair left alone does something about it.
#
# Every lair in the settled country runs a clock against the nearest town.
# When it runs out a band sets out (a RoamingParty like any other, so
# hostility, encounters, patrols and the hunt job all apply for free), walks
# to the town's edge, stands there for SIEGE so the player can meet it, and
# then the raid LANDS: the town's market halves (settlement_visit.gd reads
# `raided_by`), its board pays more for that lair's work (quest.gd), refugees
# walk the roads (travel.gd). The second landing seeds a child lair. Clearing
# the lair — however it is cleared — lifts all of it; this module polls for
# that rather than hooking mark_cleared, so every way of spending a lair is
# covered. Pure data + math, no scene: scenes/world/world.gd calls tick()
# once a frame and says the lines it returns.
#
#   Raids.tick(world, now)          # -> [String]; sets out, advances, lands, lifts
#   Raids.settle_cost(world, lair)  # -> gold, 0 when it cannot be settled
#   Raids.settle(world, lair, party, now)   # a cleared lair becomes a camp settlement
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ach = preload("res://core/achievements.gd")
const Campaign = preload("res://core/campaign.gd")

# How far a lair's raiders will walk: quest_posting.gd's clear_lair reach — a
# lair a town would post work about is a lair that can reach it.
const RAID_REACH := 800.0
# The first raid is due this long after the clock starts (world start, or the
# respawn), every later one this long after the last; each lair adds under a
# day of its own jitter so five lairs are five mornings. A day is 1440.
const RAID_AFTER := 2880.0
const RAID_EVERY := 2880.0
const RAID_JITTER := 1440
# The stand at the gate. A band walks lair-to-town in twenty world-minutes;
# without this nobody would ever meet one. Eight hours is one long rest's
# worth of warning.
const SIEGE := 480.0
# Where it stands: this far out from the town on the lair's side — inside
# settlement_visit.gd's BATTLE_RADIUS (140), so a fight there is a fight at
# the town, and the hold-the-line objective applies.
const SIEGE_DIST := 100.0
# Only lairs on this ground raid. The frontier and the deeps are nobody's
# problem until you make them yours — and a deeps-level band at a heartland
# gate on day two is a raid nobody can turn.
const SETTLED_BANDS := ["heartland", "marches"]
# What the deed is worth to the town's faction: turning a raid before it
# lands is two bands put down (2 × FactionOpinion.FOUGHT_FOR); lifting one by
# clearing the lair is a job done (QUEST_DONE), posted or not.
const TURNED_FOR := 10.0
const LIFTED_FOR := 10.0

static func is_settled(world, lair) -> bool:
	return Regions.band_of(world, lair.position) in SETTLED_BANDS

# The nearest civilized settlement inside reach, or null.
static func target_for(world, lair):
	var best = null
	var best_d := INF
	for s in world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		var d: float = s.position.distance_to(lair.position)
		if d <= RAID_REACH and d < best_d:
			best_d = d
			best = s
	return best

# Seeded off the lair, so the same warren always sets out on the same morning.
static func due_at(lair) -> float:
	var gap: float = RAID_AFTER if lair.raids == 0 else RAID_EVERY
	return lair.raid_at + gap + float(absi(hash("raid|%s" % lair.id)) % RAID_JITTER)

static func lair_of(world, id: String):
	for l in world.lairs:
		if l.id == id:
			return l
	return null

static func settlement_of(world, id: String):
	for s in world.settlements:
		if s.id == id:
			return s
	return null

static func band_of(world, lair):
	if lair.raid_band == "":
		return null
	for p in world.parties:
		if p.id == lair.raid_band:
			return p
	return null

# The band itself: two troops at the region's floor level, the shape the
# procedural builder gives every band, pointed at the siege point.
static func set_out(world, lair, s, now: float):
	var b = world.add_party(World.RoamingParty.new("%s-raiders" % lair.id, lair.position, lair.faction))
	var lv: int = int(Regions.at(world, lair.position)["levels"][0])
	b.troops.append({"role": "heavy", "level": lv})
	b.troops.append({"role": "light", "level": lv})
	var dir: Vector2 = (lair.position - s.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	WorldAI.raid(b, s.position + dir * SIEGE_DIST, s.id, lair.id)
	lair.raid_band = b.id
	lair.raid_at = now
	return b

# A band that can still be turned: out, and not yet landed.
static func turnable(foe) -> bool:
	var st: Dictionary = foe.ai if "ai" in foe else {}
	return String(st.get("behavior", "")) == "raid" and String(st.get("phase", "")) in ["march", "siege"]

# The raid lands: the town names the lair, the market feels it (battle_at is
# what settlement_visit.gd's four-hour markup reads; raided_by is what keeps
# the shelf halved after that), and the second landing seeds a child.
static func land(world, lair, s, now: float) -> Array:
	s.raided_by = lair.id
	s.raided_at = now
	s.battle_at = now
	lair.raids += 1
	var lines: Array = ["%s is raided — the market is half what it was, and %s wants it answered."
		% [s.sname, lair.sname]]
	if lair.raids == 2 and lair.spawned_from == "":
		var child = spread(world, lair, now)
		if child != null:
			lines.append("Something has dug in near %s." % lair.sname)
	return lines

# Task 3 fills this in: the second landing's child lair.
static func spread(_world, _parent, _now: float):
	return null

# Once a frame. Order matters: lifts first, so a lair cleared this frame does
# not also set out; then every band out is advanced or, if it is gone from the
# map (beaten on the road by the party or a patrol), the clock resets; then
# any lair whose time has come sets out.
static func tick(world, now: float) -> Array:
	var lines: Array = []
	for s in world.settlements:
		if s.raided_by == "":
			continue
		var l = lair_of(world, s.raided_by)
		if l != null and not l.looted:
			continue
		s.raided_by = ""
		s.raided_at = -1.0
		FactionOpinion.raise(s.faction, LIFTED_FOR)
		Ach.bump("raids_lifted")
		lines.append("%s breathes again — %s is done raiding." % [s.sname, l.sname if l != null else "the lair"])
	for l in world.lairs:
		if l.raid_band == "":
			continue
		var b = band_of(world, l)
		if b != null and l.looted:
			world.parties.erase(b)   # its lair is gone; it has nowhere to go home to
			b = null
		if b == null:
			l.raid_band = ""
			l.raid_at = now
			continue
		_advance(world, l, b, now, lines)
	for l in world.lairs:
		if l.looted or l.entered_at >= 0.0 or l.raid_band != "" or now < due_at(l):
			continue
		if not is_settled(world, l):
			continue
		var s = target_for(world, l)
		if s == null:
			continue
		set_out(world, l, s, now)
		lines.append("Raiders are out from %s, making for %s." % [l.sname, s.sname])
	return lines

# march -> siege on arrival; siege -> home when the stand runs out (the raid
# lands wherever the band is standing — it may be chasing the player);
# home -> gone on arrival. Phase changes take effect on the NEXT frame's
# steer, which is why arrival is only read at the start of a phase.
static func _advance(world, lair, b, now: float, lines: Array) -> void:
	var st: Dictionary = b.ai
	if String(st.get("behavior", "")) != "raid":
		return
	match String(st.get("phase", "")):
		"march":
			if WorldAI.arrived(b):
				st["phase"] = "siege"
				st["until"] = now + SIEGE
				var s = settlement_of(world, String(st["target"]))
				lines.append("Raiders from %s are camped outside %s." % [lair.sname, s.sname if s != null else "the town"])
		"siege":
			if now >= float(st.get("until", now)):
				var s = settlement_of(world, String(st["target"]))
				if s != null:
					lines.append_array(land(world, lair, s, now))
				st["phase"] = "home"
				st["to"] = lair.position
		"home":
			if WorldAI.arrived(b):
				world.parties.erase(b)
				lair.raid_band = ""

# What the map label says after the settlement's name: the standing raid, or
# the hours left on a siege, or nothing.
static func settlement_tag(world, s, now: float) -> String:
	if s.raided_by != "":
		return " — raided"
	for l in world.lairs:
		var b = band_of(world, l)
		if b == null or String(b.ai.get("target", "")) != s.id or String(b.ai.get("phase", "")) != "siege":
			continue
		return " — raiders at the gate, %d h" % int(ceil((float(b.ai["until"]) - now) / 60.0))
	return ""

static func lair_tag(lair) -> String:
	return " — raiding" if lair.raid_band != "" else ""
```

- [ ] **Step 8: Run the raids test**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head -20`
Expected: `test_raids: N passed, 0 failed`. If the *"four minutes in, still marching"* check fails because the band arrives one frame earlier or later than expected, adjust the `_run` counts in the test by one — the point is march→siege happens on arrival, not the exact minute.

- [ ] **Step 9: Run the two neighbours**

Run: `for t in test_world_lairs test_lair_respawn test_world_battle; do timeout 120 godot --headless --path . -s tests/$t.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR"; done`
Expected: all `0 failed`.

- [ ] **Step 10: Commit**

```bash
git add core/raids.gd core/world_ai.gd tests/test_raids.gd tests/test_world_ai.gd
git commit -m "Raids: a lair in the settled country sends a band at the nearest town, and it stands at the gate before the raid lands"
```

---

### Task 3: Spread — the second landing seeds a child lair

**Files:**
- Modify: `core/raids.gd` (replace the `spread` stub)
- Test: `tests/test_raids.gd`

**Interfaces:**
- Consumes: `world.is_water(pos)`, `world.add_lair`, `World.Lair.new(id, pos, faction, sname)`.
- Produces: `Raids.spread(world, parent, now) -> Lair or null`; constants `SPREAD_MIN`, `SPREAD_MAX`, `SPREAD_TRIES`, `SPREAD_TOWN_GAP`.

- [ ] **Step 1: Write the failing test**

In `tests/test_raids.gd`, add `test_spread()` to `_init()`'s call list (after `test_lift()`), and the function:

```gdscript
func test_spread() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	Raids.land(w, l, s, 100.0)
	check(w.lairs.size() == 1, "the first landing seeds nothing")
	var lines: Array = Raids.land(w, l, s, 200.0)
	check(w.lairs.size() == 2, "the second landing seeds a child")
	check(lines.size() == 2 and "Something has dug in near the Ash Warren." in lines[1], "...and says so (%s)" % str(lines))
	var c = w.lairs[1]
	check(c.id == "warren-2" and c.sname == "the Ash Warren's outpost" and c.faction == "goblinoid",
		"named after its parent, same faction (%s / %s)" % [c.id, c.sname])
	check(c.spawned_from == "warren" and c.raid_at == 200.0 and c.raids == 0 and not c.discovered and not c.looted,
		"a child: parent named, clock started at the landing, hidden, live")
	var d: float = c.position.distance_to(l.position)
	check(d >= Raids.SPREAD_MIN and d <= Raids.SPREAD_MAX, "placed SPREAD_MIN..SPREAD_MAX from the parent (%.0f)" % d)
	check(c.position.distance_to(s.position) >= Raids.SPREAD_TOWN_GAP, "...and clear of the town")
	check(not w.is_water(c.position), "...on dry ground")
	var again = Raids.spread(w, l, 300.0)
	check(again == null and w.lairs.size() == 2, "a root spreads once, even asked again")
	Raids.land(w, l, s, 400.0)
	check(w.lairs.size() == 2, "the third landing seeds nothing")
	# a child never spreads
	Raids.land(w, c, s, 500.0)
	Raids.land(w, c, s, 600.0)
	check(w.lairs.size() == 2 and c.raids == 2, "a child's second landing seeds nothing")
	# determinism: the same parent puts its child in the same place
	var w2 := _world()
	Raids.land(w2, w2.lairs[0], w2.settlements[0], 100.0)
	Raids.land(w2, w2.lairs[0], w2.settlements[0], 200.0)
	check(w2.lairs[1].position == c.position, "seeded off the parent's id")
	# no room: a town on every side of the parent
	var w3 := _world()
	for i in 12:
		var a := deg_to_rad(float(i) * 30.0)
		w3.add_settlement(World.Settlement.new("ring-%d" % i, w3.lairs[0].position + Vector2(cos(a), sin(a)) * 220.0, "human", "camp"))
	Raids.land(w3, w3.lairs[0], w3.settlements[0], 100.0)
	var lines3: Array = Raids.land(w3, w3.lairs[0], w3.settlements[0], 200.0)
	check(w3.lairs.size() == 1 and lines3.size() == 1, "nowhere to dig in: no child, no line")
```

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed" | head`
Expected: `FAIL: the second landing seeds a child` and following.

- [ ] **Step 3: Replace the stub**

In `core/raids.gd`, add after `LIFTED_FOR`:

```gdscript
# Where a child lair goes: close enough to read as the same trouble, far enough
# to be its own dot; clear of every town by the procedural builder's own
# MIN_MONSTER_GAP (300, scenes/world/procedural_world.gd) and of every lair by
# SPREAD_MIN. SPREAD_TRIES seeded angles, then give up — no child is better
# than one in a lake or a front yard.
const SPREAD_MIN := 150.0
const SPREAD_MAX := 300.0
const SPREAD_TRIES := 24
const SPREAD_TOWN_GAP := 300.0
```

Replace the `spread` stub with:

```gdscript
# The second landing's child: same faction, named after its parent, hidden,
# with a clock of its own that starts now. One per root, ever — a respawned
# parent counts its landings from zero again, and the id check is what keeps
# it from digging a second child on the same ground. A child never spreads
# (land() checks spawned_from), so a map at most doubles its lairs and stops.
static func spread(world, parent, now: float):
	var id := "%s-2" % parent.id
	if lair_of(world, id) != null:
		return null
	var rng = RNG.new(maxi(1, absi(hash("spread|%s" % parent.id))))
	for i in SPREAD_TRIES:
		var angle := deg_to_rad(float(rng.roll_die(360)))
		var dist: float = SPREAD_MIN + float(rng.roll_die(int(SPREAD_MAX - SPREAD_MIN)))
		var pos: Vector2 = parent.position + Vector2(cos(angle), sin(angle)) * dist
		if world.is_water(pos) or not _room_for(world, pos):
			continue
		var child = world.add_lair(World.Lair.new(id, pos, parent.faction, "%s's outpost" % parent.sname))
		child.spawned_from = parent.id
		child.raid_at = now
		return child
	return null

static func _room_for(world, pos: Vector2) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < SPREAD_TOWN_GAP:
			return false
	for l in world.lairs:
		if l.position.distance_to(pos) < SPREAD_MIN:
			return false
	return true
```

- [ ] **Step 4: Run the test**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `0 failed`. (`rng.roll_die(n)` returns 1..n — check `core/rng.gd` if unsure; `SPREAD_MAX - SPREAD_MIN` is 150, so `dist` is 151..300; the test's `>= SPREAD_MIN` holds.)

- [ ] **Step 5: Commit**

```bash
git add core/raids.gd tests/test_raids.gd
git commit -m "Raids: the second landing digs in a child lair near the parent, once"
```

---

### Task 4: What a raid does to the town — the market, the board's premium, the rescue

**Files:**
- Modify: `core/settlement_visit.gd` (`visit` ~283–291)
- Modify: `core/quest.gd` (`_world_quest_from_pick` ~167–181; a new `const RAID_PREMIUM`)
- Modify: `core/quest_posting.gd` (`rescue_offer` ~330–355)
- Test: `tests/test_settlement_visit.gd`, `tests/test_quest_posting.gd`

**Interfaces:**
- Consumes: `Settlement.raided_by`.
- Produces: `Quest.RAID_PREMIUM := 1.5`; `Visit.visit(s, world)["battle"]` true while raided; `Posting.rescue_offer` prefers `s.raided_by`'s lair with captive *"the people taken in the raid"*.

- [ ] **Step 1: Write the failing market test**

In `tests/test_settlement_visit.gd`, before the final `print(`:

```gdscript
	# raids: a raided town's shelf is the battle shelf for as long as the raid stands
	var wv := World.new()
	var sv := wv.add_settlement(World.Settlement.new("raided", Vector2.ZERO, "human", "town"))
	wv.clock.elapsed = 10000.0
	sv.battle_at = -1.0
	sv.raided_by = "warren"
	var mv: Dictionary = Visit.visit(sv, wv)
	check(bool(mv["battle"]), "a raided town reads as a battle market with no battle_at at all")
	sv.raided_by = ""
	sv.last_visited = -1.0
	check(not bool(Visit.visit(sv, wv)["battle"]), "...and not once lifted")
```

(Use the file's own preload names; it has `World` and `Visit`.)

- [ ] **Step 2: Run it to see it fail, then fix**

Run: `timeout 120 godot --headless --path . -s tests/test_settlement_visit.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `FAIL: a raided town reads as a battle market...`

In `core/settlement_visit.gd` `visit()`, change the market line to:

```gdscript
	# A raid that stands on the town (core/raids.gd) is the battle shelf for as
	# long as it stands — half the stock, the markup — not for four hours.
	var m := market(s, gap, battle_recent(s, now) or s.raided_by != "", FactionOpinion.get_opinion(s.faction))
```

Run again. Expected: `0 failed`.

- [ ] **Step 3: Write the failing posting tests**

In `tests/test_quest_posting.gd`, add `test_raid_premium_and_rescue()` to `_init()`'s call list (after `test_rescue_offer()`), and:

```gdscript
func test_raid_premium_and_rescue() -> void:
	var Site = load("res://core/site.gd")
	var w := _world()
	var p := _party()
	var city = w.settlements[0]
	var warren = w.lairs[0]
	var rng_a = RNG.new(7)
	var plain: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": warren.id, "name": warren.sname, "faction": warren.faction}, city, p, rng_a)
	city.raided_by = warren.id
	var rng_b = RNG.new(7)
	var dear: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": warren.id, "name": warren.sname, "faction": warren.faction}, city, p, rng_b)
	check(int(dear["reward"]["gold"]) == int(int(plain["reward"]["gold"]) * Quest.RAID_PREMIUM),
		"the raiding lair's job pays RAID_PREMIUM (%d -> %d)" % [plain["reward"]["gold"], dear["reward"]["gold"]])
	var rng_c = RNG.new(7)
	var other: Dictionary = Quest._world_quest_from_pick(
		{"kind": "clear_lair", "id": "far-barrow", "name": "Far Barrow", "faction": "undead"}, city, p, rng_c)
	check(int(other["reward"]["gold"]) == int(plain["reward"]["gold"]), "another lair's job does not")
	# the rescue names the raider, even when a nearer lair has pens too. The
	# interior is seeded off the lair's id (core/site.gd), so each is found by
	# trying ids until one has pens — never renamed after the fact.
	var near = null
	var far = null
	for i in 400:
		var l = World.Lair.new("pens-%d" % i, Vector2(120, 60), "goblinoid")
		if Site.pens_ahead(l):
			near = l
			break
	for i in 400:
		var l = World.Lair.new("raider-%d" % i, Vector2(500, 0), "goblinoid", "the Raider Hole")
		if Site.pens_ahead(l):
			far = l
			break
	check(near != null and far != null, "two lairs with pens")
	w.add_lair(near)
	w.add_lair(far)
	city.raided_by = far.id
	var q: Dictionary = Posting.rescue_offer(city, w, p)
	check(q["target_lair_id"] == far.id and q["title"] == "Bring back the people taken in the raid from the Raider Hole",
		"the rescue is from the raiding lair, and says who (%s)" % q.get("title", ""))
	city.raided_by = ""
	check(Posting.rescue_offer(city, w, p)["target_lair_id"] == near.id, "lifted, the nearest pens win again")
```

Add `const RNG = preload("res://core/rng.gd")` to the file's preloads if it is not there.

- [ ] **Step 4: Run it to see it fail, then implement**

Run: `timeout 120 godot --headless --path . -s tests/test_quest_posting.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: SCRIPT ERROR on `Quest.RAID_PREMIUM`, or the premium FAIL.

In `core/quest.gd`, near `CHAIN_LABELS`:

```gdscript
# A lair whose raid stands on the giver's town (core/raids.gd) pays this much
# more for its own job: the town wants it answered, and says so in gold.
const RAID_PREMIUM := 1.5
```

In `_world_quest_from_pick`, after the `match kind:` block and before `return out`:

```gdscript
	if "raided_by" in giver_settlement and String(giver_settlement.raided_by) == String(pick["id"]):
		out["reward"]["gold"] = int(int(out["reward"]["gold"]) * RAID_PREMIUM)
```

In `core/quest_posting.gd` `rescue_offer`, replace the loop and the `who` line:

```gdscript
	for l in world.lairs:
		var d: float = s.position.distance_to(l.position)
		# The lair raiding this town (core/raids.gd) is where the people it took
		# are: it wins the posting outright, pens permitting.
		var rank: float = 0.0 if l.id == s.raided_by else d
		if l.looted or d > reach or rank >= best_d or not Site.pens_ahead(l):
			continue
		best = l
		best_d = rank
	if best == null:
		return {}
	var who: String = ("the people taken in the raid" if best.id == s.raided_by
		else CAPTIVES[absi(hash("%s|%s" % [s.id, best.id])) % CAPTIVES.size()])
```

Keep the `reward` line using the real distance: replace `best_d` there with `s.position.distance_to(best.position)`.

Run again. Expected: `0 failed`.

- [ ] **Step 5: Run the quest test too**

Run: `timeout 120 godot --headless --path . -s tests/test_quest.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/settlement_visit.gd core/quest.gd core/quest_posting.gd tests/test_settlement_visit.gd tests/test_quest_posting.gd
git commit -m "Raids: a raided town is half a market, pays more for the lair's own job, and its rescue names the raiders"
```

---

### Task 5: Refugees on the road — the event whose pass finds the raiders' lair

**Files:**
- Modify: `core/travel.gd` (`EVENTS` ~149–214, `_needs_met` ~357–361, `_apply` ~412+)
- Modify: `core/achievements.gd` (`every_road_event` goal ~312–314)
- Test: `tests/test_travel.gd`, `tests/test_achievements.gd`

**Interfaces:**
- Consumes: `Settlement.raided_by`, `Lair.discovered`.
- Produces: the `refugees` row in `Travel.EVENTS`; `Travel.EVENTS.size()` is 15 and `every_road_event`'s goal is 15.

- [ ] **Step 1: Write the failing travel test**

In `tests/test_travel.gd`, before the final `print(`:

```gdscript
	# --- refugees: only on a raided road, and their pass finds the lair --------
	var wf := _world()
	var pf := _party()
	var raided_town = wf.settlements[0]
	var hidden = wf.add_lair(World.Lair.new("raider-hole", raided_town.position + Vector2(300, 0), "goblinoid", "the Raider Hole"))
	var fired := false
	for seed_v in range(1, 300):
		if String(Travel.check(pf, wf, RNG.new(seed_v)).get("id", "")) == "refugees":
			fired = true
	check(not fired, "no raid on the map: no refugees")
	raided_town.raided_by = "raider-hole"
	var passed := {}
	for seed_v in range(1, 400):
		hidden.discovered = false
		var e: Dictionary = Travel.check(pf, wf, RNG.new(seed_v))
		if String(e.get("id", "")) != "refugees":
			continue
		passed[bool(e["ok"])] = e
		check(bool(e["ok"]) == hidden.discovered, "a pass finds the lair, a fail does not (ok=%s)" % e["ok"])
	check(passed.has(true) and passed.has(false), "both outcomes reachable")
	check("on the map now" in String(passed[true]["text"]) and String(passed[true].get("lair", "")) == "the Raider Hole",
		"the pass says where they came from: %s" % passed[true]["text"])
	hidden.discovered = true
	fired = false
	for seed_v in range(1, 300):
		if String(Travel.check(pf, wf, RNG.new(seed_v)).get("id", "")) == "refugees":
			fired = true
	check(not fired, "the lair already found: nothing left for them to tell, no event")
```

Check the file's `_world()` fixture puts the party in the heartland or the marches (the event is banded); if its settlements are all at the origin it does. Also update the existing check `seen_ids.size() >= 12` label's expectation only if it fails — it should not (refugees is gated off there).

In `tests/test_achievements.gd`, the existing check `Ach.find("every_road_event")["goal"] == Travel.EVENTS.size()` is the test for the goal; nothing to add.

- [ ] **Step 2: Run both to see them fail**

Run: `for t in test_travel test_achievements; do timeout 120 godot --headless --path . -s tests/$t.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR"; done`
Expected: travel FAILs on `both outcomes reachable`; achievements passes still (goal 14 == 14).

- [ ] **Step 3: Add the event**

In `core/travel.gd`, append to `EVENTS` after the `carter` row:

```gdscript
	# Raids (core/raids.gd): the people a raided town lost, on the road. Their
	# pass is the one thing the clock gives back — the lair the raiders came
	# from goes on the map. Gated (needs "raided") on there being a lair left
	# to find, so the card never promises what the map cannot show.
	{"id": "refugees", "role": "", "skills": ["persuasion", "insight", "medicine"], "dc": 12, "kind": "good",
		"bands": ["heartland", "marches"], "needs": "raided",
		"title": "Families on the road with what they could carry.",
		"pass": "%s gets the story out of them, and the way back to where it came from.",
		"fail": "They have nothing left to give but the road, and they give that."},
```

In `_needs_met`, add an arm:

```gdscript
		"raided": return _raiders_lair(world) != null
```

Add next to `_reveal_nearest_lair`:

```gdscript
# The lair behind a raid that stands on some town, while it is still hidden —
# what the refugees can tell the party. null when every raider is known, or
# nothing is raided.
static func _raiders_lair(world):
	for s in world.settlements:
		if s.raided_by == "":
			continue
		for l in world.lairs:
			if l.id == s.raided_by and not l.discovered and not l.looted:
				return l
	return null
```

In `_apply`, add an arm (next to `"tracks"`):

```gdscript
		"refugees":
			if ok:
				var from = _raiders_lair(world)
				if from != null:
					from.discovered = true
					out["lair"] = from.sname
					out["text"] = "%s  %s is where they came from — it is on the map now." % [
						out["text"], from.sname]
```

In `core/achievements.gd`, change `every_road_event`'s `"goal": 14` to `"goal": 15`.

- [ ] **Step 4: Run both again**

Run: `for t in test_travel test_achievements; do timeout 120 godot --headless --path . -s tests/$t.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR"; done`
Expected: both `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/travel.gd core/achievements.gd tests/test_travel.gd
git commit -m "Raids: refugees on the road, and the way back to where they came from"
```

---

### Task 6: Reclaiming — a cleared lair in the settled country becomes a camp

**Files:**
- Modify: `core/raids.gd`
- Test: `tests/test_raids.gd`

**Interfaces:**
- Consumes: `Regions.band_of`, `Regions.at(...)["index"]`, `party.spend_gold(n) -> bool`, `party.gold`, `Campaign.new(party)._split_xp(n)`, `Ach.collect(key, member)`, `FactionOpinion.raise`, `World.Settlement.new(id, pos, faction, kind, sname)`, `world.add_settlement`, `world.lairs.erase`.
- Produces: `Raids.settle_cost(world, lair) -> int` (0 = cannot); `Raids.settlers_from(world, pos)` → the nearest civilized settlement or null; `Raids.waystation_name(world, lair) -> String`; `Raids.settle(world, lair, party, now)` → the new Settlement or null; constants `RECLAIM_COST`, `SETTLE_XP`, `WAYSTATION_NAMES`.

- [ ] **Step 1: Write the failing test**

Add `test_settle()` to `_init()`'s list and:

```gdscript
func test_settle() -> void:
	var Party = load("res://core/party.gd")
	var w := _world()
	var l = w.lairs[0]
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.gold = 500
	check(Raids.settle_cost(w, l) == 0, "a live lair cannot be settled")
	WorldLairs.mark_cleared(l, 1000.0)
	check(Raids.settle_cost(w, l) == 120, "cleared, in the heartland: 120")
	l.cleared_at = -1.0                                   # spent before the respawn rule: no window
	check(Raids.settle_cost(w, l) == 0, "no respawn window, no settling")
	l.cleared_at = 1000.0
	var w2 := _world()
	w2.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))
	var m = w2.add_lair(World.Lair.new("m", Vector2(1100, 0), "orc"))   # 1100/2000 = marches
	WorldLairs.mark_cleared(m, 1000.0)
	check(Raids.settle_cost(w2, m) == 240, "the marches cost 240")
	var deep = w2.add_lair(World.Lair.new("d", Vector2(1900, 0), "undead"))
	WorldLairs.mark_cleared(deep, 1000.0)
	check(Raids.settle_cost(w2, deep) == 0, "the deeps cannot be settled")
	var w3 := _world()
	w3.settlements[0].faction = "orc"
	WorldLairs.mark_cleared(w3.lairs[0], 1000.0)
	check(Raids.settle_cost(w3, w3.lairs[0]) == 0, "nobody civilized to send settlers: no settling")
	# the purchase
	check(Raids.settlers_from(w, l.position) == w.settlements[0], "settlers come from the nearest civilized town")
	var name := Raids.waystation_name(w, l)
	check(name in Raids.WAYSTATION_NAMES, "named off the list (%s)" % name)
	w.add_settlement(World.Settlement.new("taken", Vector2(5000, 5000), "human", "camp", name))
	check(Raids.waystation_name(w, l) != name and Raids.waystation_name(w, l) in Raids.WAYSTATION_NAMES,
		"a name already on the map is skipped")
	w.settlements.pop_back()
	p.gold = 100
	check(Raids.settle(w, l, p, 1500.0) == null and w.lairs.has(l), "short of gold: nothing happens")
	p.gold = 500
	FactionOpinion.reset()
	var xp_before: int = p.party_characters()[0].xp
	var ways_before: int = Ach.count("waystations")
	var s = Raids.settle(w, l, p, 1500.0)
	check(s != null and not w.lairs.has(l), "settled: the lair is gone for good")
	check(w.settlements.has(s) and s.id == "way-warren" and s.kind == "camp" and s.faction == "human"
		and s.position == Vector2(300, 0) and s.sname == name, "a camp of the settlers' faction stands where it was")
	check(s.last_visited == 1500.0, "with a fresh market")
	check(p.gold == 380, "120 paid")
	check(p.party_characters()[0].xp == xp_before + Raids.SETTLE_XP / p.party_characters().size(),
		"SETTLE_XP x (ring 0 + 1), split (%d -> %d)" % [xp_before, p.party_characters()[0].xp])
	check(FactionOpinion.get_opinion("human") == Raids.LIFTED_FOR, "the settlers' faction thanks you")
	check(Ach.count("waystations") == ways_before + 1, "the deed is collected")
	check(Raids.settle(w, l, p, 1600.0) == null, "a lair no longer on the map cannot be settled twice")
```

(`Party.demo_roster()` is what `tests/test_quest_posting.gd` uses; if `party_characters()[0].xp` is not the field's name, use what `core/campaign.gd`'s `_split_xp` writes — read it.)

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: SCRIPT ERROR — `settle_cost` not found.

- [ ] **Step 3: Implement**

In `core/raids.gd`, after the spread constants:

```gdscript
# Reclaiming. A cleared lair on settled ground can be bought into a camp
# settlement inside the respawn's own one-day window — the one deadline there
# already is. Priced as nights at a town inn (three and six): a real sink,
# once, for a permanent bed. SETTLE_XP is a landmark and a half — the biggest
# deed on the map that is not a fight — times (ring + 1) like every deed.
const RECLAIM_COST := {"heartland": 120, "marches": 240}
const SETTLE_XP := 60
const WAYSTATION_NAMES := ["Fairstead", "Newhold", "Hollowell", "Whitecross", "Longwater",
	"Kingsrest", "Ashford", "Stonebridge", "Greenhalt", "Oldwell"]
```

At the end of the file:

```gdscript
# --- reclaiming --------------------------------------------------------------

# The nearest civilized settlement to a point, any distance — where the
# settlers come from, and whose faction the camp flies. null on a map with none.
static func settlers_from(world, pos: Vector2):
	var best = null
	var best_d := INF
	for s in world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		var d: float = s.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best

# Gold to settle this lair, or 0 when it cannot be: live, spent before the
# respawn rule (no window), on frontier or deeps ground, or nobody to send.
static func settle_cost(world, lair) -> int:
	if not lair.looted or lair.cleared_at < 0.0 or not world.lairs.has(lair):
		return 0
	var band := Regions.band_of(world, lair.position)
	if not RECLAIM_COST.has(band) or settlers_from(world, lair.position) == null:
		return 0
	return int(RECLAIM_COST[band])

# Seeded off the lair, stepping past any name already on the map.
static func waystation_name(world, lair) -> String:
	var n := WAYSTATION_NAMES.size()
	var start: int = absi(hash("way|%s" % lair.id)) % n
	for i in n:
		var name: String = WAYSTATION_NAMES[(start + i) % n]
		var taken := false
		for s in world.settlements:
			if s.sname == name:
				taken = true
				break
		if not taken:
			return name
	return "%s Halt" % lair.sname.trim_prefix("the ")

# The purchase: the lair is gone for good (not a hole any more — no respawn),
# a camp of the settlers' faction stands where it was with a fresh market, and
# the deed pays. null when it cannot be settled or the purse is short.
static func settle(world, lair, party, now: float):
	var cost := settle_cost(world, lair)
	if cost <= 0 or not party.spend_gold(cost):
		return null
	var home = settlers_from(world, lair.position)
	var ring: int = int(Regions.at(world, lair.position)["index"])
	world.lairs.erase(lair)
	var s = world.add_settlement(World.Settlement.new("way-" + lair.id, lair.position, home.faction, "camp",
		waystation_name(world, lair)))
	s.last_visited = now
	Campaign.new(party)._split_xp(SETTLE_XP * (ring + 1))
	FactionOpinion.raise(home.faction, LIFTED_FOR)
	Ach.collect("waystations", s.id)
	return s
```

- [ ] **Step 4: Run the test**

Run: `timeout 120 godot --headless --path . -s tests/test_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/raids.gd tests/test_raids.gd
git commit -m "Raids: a cleared lair in the settled country can be bought into a camp, once, inside the respawn's day"
```

---

### Task 7: The world screen — the poll, the lines, the labels, the board line, the gate fight, the deed, the Settle button

**Files:**
- Modify: `scenes/world/world.gd` (preloads ~1–60; bottom bar ~776–792; `_process` ~452–493; `_road_objective` ~1472–1481; `_launch_combat` Victory branch ~1502–1523; `_check_lairs` ~1933–1972; `_check_expired_lairs` ~1975–1988; `_build_board_page` ~3392–3400; `ground_marks` ~3824–3850)
- Test: `tests/test_world_raids.gd` (new)

**Interfaces:**
- Consumes: everything `Raids` produces; `Objectives.make("hold")`; `FactionOpinion.credit_fight(world, at, amount, skip_faction)`; `Ach.bump`; `_settlements3d.reset(world)`, `_lairs3d.reset(world)`; `_autosave()`; `_quest_news`.
- Produces: `_lair_settle_btn: Button`, `_settle_target`, `_lair_settle_action()`, `_check_raids()`.

- [ ] **Step 1: Write the failing screen test**

Create `tests/test_world_raids.gd`:

```gdscript
# Raids on the world screen: the band sets out and it is said, the siege shows
# on the label, the landing shows on the board, clearing lifts it, and a
# cleared lair can be settled from the lair button row.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_raids.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const Objectives = preload("res://core/objectives.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func _label_for(main, id: String) -> String:
	for m in main.ground_marks():
		if String(m.get("label", "")).begins_with(id):
			return String(m["label"])
	return ""

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	var town = w.settlements[0]     # Riverhold, at the origin, where the party starts
	# a lair of our own 300 out, due now; the map's own lairs are not due for two days
	# 220 out: inside the fog the party has already lifted (VISION_RADIUS 260
	# from where it stands), so the lair's label draws; still heartland ground.
	var l = w.add_lair(World.Lair.new("t-warren", town.position + Vector2(220, 0), "goblinoid", "the Test Warren"))
	l.discovered = true
	l.raid_at = w.clock.elapsed - Raids.RAID_AFTER - Raids.RAID_JITTER
	main._lairs3d.reset(w)
	w.clock.resume()
	for i in 3:
		await process_frame
	var b = Raids.band_of(w, l)
	check(b != null, "the band set out on the screen's poll")
	check("Raiders are out from the Test Warren" in main._lair_msg.text, "...and it is said: %s" % main._lair_msg.text)
	check(_label_for(main, "the Test Warren").ends_with(" — raiding"), "the lair's label says so: %s" % _label_for(main, "the Test Warren"))
	# jump it to the gate
	b.position = Vector2(b.ai["to"])
	for i in 3:
		await process_frame
	check(b.ai["phase"] == "siege", "at the gate")
	check("camped outside" in main._lair_msg.text, "...said: %s" % main._lair_msg.text)
	check(" — raiders at the gate, " in _label_for(main, town.sname), "the town's label counts the hours: %s" % _label_for(main, town.sname))
	# the fight at the gate is a hold; on the road it is not
	check(String(main._road_objective(b, "").get("kind", "")) == "hold", "meeting the raiders at the gate is hold the line")
	b.position = town.position + Vector2(600, 0)
	check(main._road_objective(b, "").is_empty(), "...and out on the road it is a plain fight")
	b.position = Vector2(b.ai["to"])
	# stand it out
	b.ai["until"] = w.clock.elapsed - 1.0
	for i in 3:
		await process_frame
	check(town.raided_by == "t-warren", "landed")
	check(_label_for(main, town.sname).ends_with(" — raided"), "the label says raided: %s" % _label_for(main, town.sname))
	# the board says it
	w.clock.pause()
	main._open_visit(town)
	main._goto_page("board")
	await process_frame
	check(said(main, "Raiders from the Test Warren hit the town on Day") and said(main, "The market is half what it was."),
		"the board page carries the line")
	main._close_visit()
	await process_frame
	# clearing lifts it
	WorldLairs.mark_cleared(l, w.clock.elapsed)
	w.clock.resume()
	for i in 3:
		await process_frame
	check(town.raided_by == "" and "breathes again" in main._lair_msg.text, "cleared, lifted, said: %s" % main._lair_msg.text)
	# settle it: stand on it, pay
	p.position = l.position
	p.goal = l.position
	main.party.gold = 50
	for i in 3:
		await process_frame
	check(main._lair_settle_btn.visible and main._lair_settle_btn.disabled and "Settle it (120 ◉)" in main._lair_settle_btn.text,
		"the button is there, priced, and greyed on a short purse: %s" % main._lair_settle_btn.text)
	main.party.gold = 500
	for i in 2:
		await process_frame
	check(not main._lair_settle_btn.disabled, "...and live with the gold")
	var n_settlements: int = w.settlements.size()
	main._lair_settle_btn.pressed.emit()
	for i in 3:
		await process_frame
	check(not w.lairs.has(l) and w.settlements.size() == n_settlements + 1 and w.settlements[-1].id == "way-t-warren",
		"settled: the lair is gone and a camp stands")
	check("Settlers from Riverhold put up the first roof at" in main._lair_msg.text, "said: %s" % main._lair_msg.text)
	check(not main._lair_settle_btn.visible, "the button is gone with the lair")
	check(main._settlements3d.footprint(w.settlements[-1]) > 0.0, "the camp is on the 3D map")
	print("test_world_raids: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

Check `tests/test_world_landmarks.gd` for how it names the settlements/player on the small map and whether `w.settlements[0]` is Riverhold at the origin there (it is in `scenes/world/world.gd`'s small world: `riverhold` at `Vector2(0, 0)`); and for the exact helper names `_open_visit`, `_goto_page`, `_close_visit` (all exist, used by `tests/shot_landmarks.gd`).

- [ ] **Step 2: Run it to see it fail**

Run: `SORCMERC_FAST=1 timeout 180 godot --headless --path . -s tests/test_world_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: FAILs from `the band set out on the screen's poll` on (nothing polls yet) — or a SCRIPT ERROR on `_lair_settle_btn`.

- [ ] **Step 3: The poll and the lines**

In `scenes/world/world.gd`, add to the preload block (next to `WorldLairs`):

```gdscript
const Raids = preload("res://core/raids.gd")
```

In `_process`, after `_check_expired_lairs()`:

```gdscript
	_check_raids()
```

After `_check_expired_lairs()`'s definition:

```gdscript
# Raids (core/raids.gd): the clock every lair in the settled country runs
# against the nearest town. Said out loud as it happens, like the expiry and
# the respawn are; a landing can add a lair to the map, so the dioramas are
# rebuilt whenever the poll had anything to say.
func _check_raids() -> void:
	if _combat != null or _site != null:
		return
	var lines: Array = Raids.tick(world, world.clock.elapsed)
	if lines.is_empty():
		return
	for line in lines:
		_lair_msg.text = String(line)
	_lairs3d.reset(world)
	_autosave()
```

- [ ] **Step 4: The labels**

In `ground_marks()`, change the settlement entry's `"label": s.sname` to:

```gdscript
			"label": s.sname + Raids.settlement_tag(world, s, world.clock.elapsed),
```

and the lair entry's `"label": l.sname` to:

```gdscript
			"label": l.sname + Raids.lair_tag(l),
```

- [ ] **Step 5: The board line**

In `_build_board_page`, after `box.add_child(mood)`:

```gdscript
	if s.raided_by != "":
		var raider = Raids.lair_of(world, s.raided_by)
		var hit := Label.new()
		hit.text = "Raiders from %s hit the town on %s. The market is half what it was." % [
			raider.sname if raider != null else "the hills", WorldSave.day_clock(s.raided_at).split("  ")[0]]
		hit.theme_type_variation = "Serif"
		hit.add_theme_color_override("font_color", Icons.COL_FOE)
		hit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hit)
```

(`WorldSave` and `Icons` are already preloaded in this file — check the const block; `day_clock` returns `"Day 3  08:01"`, so `.split("  ")[0]` is `"Day 3"`.)

- [ ] **Step 6: The gate fight and the deed**

In `_road_objective`, after the `jumped` check and before the hunt loop:

```gdscript
	# Raiders on their way to a town, or standing at its gate: the town is
	# behind you and more are coming. Anywhere else on the road they are a
	# band like any other (or a hunt, if the job is taken).
	if Raids.turnable(foe):
		var target = Raids.settlement_of(world, String(foe.ai.get("target", "")))
		if target != null and foe.position.distance_to(target.position) <= Visit.BATTLE_RADIUS:
			return Objectives.make("hold")
```

In `_launch_combat`, before `var result: Dictionary = await _run_combat(...)`:

```gdscript
	var raid_target = Raids.settlement_of(world, String(foe.ai.get("target", ""))) if Raids.turnable(foe) else null
```

In the Victory branch, inside the `else:` that erases the foe (after `Quest.record_party_defeated(party, foe.id)`):

```gdscript
			if raid_target != null:
				# A raid turned before it landed: worth two bands put down to the
				# town it was going to hit. raids.gd resets the lair's clock on its
				# next poll when it finds the band gone.
				FactionOpinion.credit_fight(world, raid_target.position, Raids.TURNED_FOR, foe.faction)
				Ach.bump("raids_turned")
				_quest_news.append("The raid on %s is turned." % raid_target.sname)
```

- [ ] **Step 7: The Settle button**

In the bottom-bar build, after `bar.add_child(_lair_sneak_btn)`:

```gdscript
	_lair_settle_btn = Button.new()
	_lair_settle_btn.visible = false
	_lair_settle_btn.pressed.connect(_lair_settle_action)
	bar.add_child(_lair_settle_btn)
```

Next to `var _lair_target: World.Lair = null`:

```gdscript
var _lair_settle_btn: Button
var _settle_target: World.Lair = null   # a cleared lair in range the party could settle (core/raids.gd)
```

In `_check_lairs`, every early return that hides the two buttons also hides this one — add `_lair_settle_btn.visible = false` beside each `_lair_sneak_btn.visible = false` in the first two returns (combat/visit/overlay, and no player). Then, replace the `if target == null:` return block (the third one) with:

```gdscript
	# A cleared lair the party is standing on, inside the respawn's day, on
	# settled ground: it can be bought into a camp (core/raids.gd). Its own
	# button, since _lair_btn is already two-state and hides on a looted lair.
	_settle_target = null
	for l in world.lairs:
		if l.looted and l.position.distance_to(p.position) <= WorldLairs.DISCOVER_RADIUS \
				and Raids.settle_cost(world, l) > 0:
			_settle_target = l
			break
	_lair_settle_btn.visible = _settle_target != null
	if _settle_target != null:
		var cost := Raids.settle_cost(world, _settle_target)
		_lair_settle_btn.text = "Settle it (%d ◉)" % cost
		_lair_settle_btn.disabled = party.gold < cost
		_lair_settle_btn.tooltip_text = "" if party.gold >= cost else "not enough gold"
	if target == null:
		_lair_btn.visible = false
		_lair_sneak_btn.visible = false
		return
```

After `_lair_sneak_action()`:

```gdscript
func _lair_settle_action() -> void:
	var l: World.Lair = _settle_target
	if l == null:
		return
	var home = Raids.settlers_from(world, l.position)
	var s = Raids.settle(world, l, party, world.clock.elapsed)
	if s == null:
		return
	_lair_msg.text = "Settlers from %s put up the first roof at %s." % [home.sname, s.sname]
	_settle_target = null
	_lair_target = null
	_settlements3d.reset(world)
	_lairs3d.reset(world)
	_autosave()
```

- [ ] **Step 8: Run the screen test**

Run: `SORCMERC_FAST=1 timeout 180 godot --headless --path . -s tests/test_world_raids.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head -20`
Expected: `0 failed`.

- [ ] **Step 9: Run the screen neighbours**

Run: `for t in test_world_lairs test_world_landmarks test_world_objectives test_world_visit_pages test_world_markers; do SORCMERC_FAST=1 timeout 180 godot --headless --path . -s tests/$t.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR"; done`
Expected: all `0 failed`.

- [ ] **Step 10: Commit**

```bash
git add scenes/world/world.gd tests/test_world_raids.gd
git commit -m "Raids on the world screen: the poll and its lines, the labels, the board's line, hold the line at the gate, and the Settle button"
```

---

### Task 8: The achievements, the robot, and the record

**Files:**
- Modify: `core/achievements.gd` (`DEFS`, the `road` group, after `landmarks_12`)
- Modify: `tests/drive_random.gd` (the lair block ~845–855; the frame invariants ~262–310)
- Modify: `docs/expansion-plan.md` (append a record after the landmarks one)
- Test: `tests/test_achievements.gd`

**Interfaces:**
- Consumes: counters `raids_turned`, `raids_lifted`, `waystations`; `screen._lair_settle_btn`, `screen._visit`.

- [ ] **Step 1: Write the failing achievements test**

In `tests/test_achievements.gd`, before the final `print(`:

```gdscript
	# raids: four deeds on the road
	for id in ["raid_turned", "raids_lifted_3", "waystations_1", "waystations_3"]:
		check(not Ach.find(id).is_empty(), "%s is defined" % id)
	check(int(Ach.find("waystations_3")["goal"]) == 3 and Ach.find("waystations_3")["counter"] == "waystations",
		"Founder counts three waystations")
```

- [ ] **Step 2: Run it to see it fail, then add the entries**

Run: `timeout 120 godot --headless --path . -s tests/test_achievements.gd 2>&1 | grep -E "FAIL|passed|SCRIPT ERROR" | head`
Expected: `FAIL: raid_turned is defined`.

In `core/achievements.gd`, after the `landmarks_12` entry:

```gdscript
	{"id": "raid_turned", "group": "road", "title": "Held the Line",
		"desc": "Turn a raid before it reaches the town.", "counter": "raids_turned", "goal": 1},
	{"id": "raids_lifted_3", "group": "road", "title": "Relief",
		"desc": "Lift three raids by clearing the lairs behind them.", "counter": "raids_lifted", "goal": 3},
	{"id": "waystations_1", "group": "road", "title": "Homesteader",
		"desc": "Settle a cleared lair.", "counter": "waystations", "goal": 1},
	{"id": "waystations_3", "group": "road", "title": "Founder",
		"desc": "Settle three of them.", "counter": "waystations", "goal": 3},
```

Run again. Expected: `0 failed`. (If the test file asserts a total `DEFS.size()`, bump it by four.)

- [ ] **Step 3: The robot**

In `tests/drive_random.gd`, after the lair block (the one ending `screen._lair_btn.pressed.emit(); return`), add:

```gdscript
	# A cleared lair under the party's feet, for sale: a careful robot buys it.
	if screen._lair_settle_btn != null and screen._lair_settle_btn.visible \
			and not screen._lair_settle_btn.disabled and _chance(20 + _me["care"] / 2):
		_saw["lair:settle"] = true
		_acts += 1
		screen._lair_settle_btn.pressed.emit()
		return
```

In the frame invariants (the function with `fail("the purse went negative...")`), add:

```gdscript
	for s in w.settlements:
		if s.id.begins_with("way-"):
			for l in w.lairs:
				if l.id == s.id.trim_prefix("way-"):
					fail("%s stands on a lair that is still on the map" % s.sname)
	if not screen._visit.is_empty():
		var vs = screen._visit.get("settlement")
		if vs != null and vs.raided_by != "" and not bool(screen._visit.get("battle", false)):
			fail("a raided town's market is not the halved shelf")
```

(`w` and `screen` are what that function already calls the world and the screen — match its names.)

Run: `SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/drive_random.gd 2>&1 | tail -5`
Expected: the robot's normal summary, no `FAIL`.

- [ ] **Step 4: The record**

Append to `docs/expansion-plan.md`, after the landmarks record's Pictures table (the file's last section):

```markdown
## Threat clocks and reclaiming — a lair left alone does something about it (2026-09-20)

Sub-project 3 of the content batch. Spec:
`docs/superpowers/specs/2026-09-20-threat-clocks-design.md`; plan:
`docs/superpowers/plans/2026-09-20-threat-clocks.md`.

A lair the party never touched used to be a red dot that waited. Now every
lair on heartland or marches ground runs a clock (`core/raids.gd`) against
the nearest town inside 800: two days in, plus under a day of its own
jitter, a band sets out — a `RoamingParty` like any other, with a `raid`
behaviour on the world AI — walks to the town's edge, stands there eight
hours (and comes for anyone who comes near), and then the raid lands: the
town's market is the halved battle shelf for as long as the raid stands,
its board pays half again for that lair's own job, its rescue names the
people taken, and refugees walk the roads of the settled country — whose
pass puts the raiders' lair on the map. The second landing digs a child
lair in beside the parent, once. Clearing the lair, however it is cleared,
lifts every town it raided; a raid met on its way in is *hold the line*,
and turning one is worth two bands put down to the town. Measured on the
shipped maps, two lairs a map raid — the goblin warren and the Sunken
Ruins; the giant, the graveyard and the dragon sit in country that is
nobody's problem until you make it yours.

And the other direction: a cleared lair on settled ground can be bought
inside the respawn's own day — *Settle it*, 120 in the heartland, 240 in
the marches — and is gone for good, a `camp` settlement of the nearest
town's faction standing where it was, with a name off a list and a fresh
market. The `camp` kind had existed all along; nothing had ever put one on
the map mid-run.

### Still open

- No pictures yet.
- A raid band carries nothing home; the halved market is what it took.
- Towns are never taken. A town that falls is the faction ladder's war (#4).
```

- [ ] **Step 5: Commit**

```bash
git add core/achievements.gd tests/test_achievements.gd tests/drive_random.gd docs/expansion-plan.md
git commit -m "Raids: four deeds on the road, the robot buys a lair when it can, and the record"
```
