# Encounter Objectives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five encounter objectives (hold, rescue, breakout, hunt, escort) that ride in the encounter spec and change what a fight is for, each reachable from one place in the open world, with a spec without an objective behaving exactly as today.

**Architecture:** `spec["objective"] = {kind, ...}` is copied onto `Combat.objective` by `Encounter.build()`, which also places the two bystander tokens (captive, carter), marks the quarry, and computes the far-edge exit. The rules of each kind (round hook, adjacency/exit checks, escape, win/fail) live in `core/combat.gd`; what a kind *is* (knobs, builders, briefs, spoils text) lives in the new `core/objectives.gd`. The world (`scenes/world/world.gd`, `core/site.gd`, quests) only sets the objective on a spec and reads `result["objective"]` back.

**Tech Stack:** Godot 4.7.2 (flatpak `godot` on PATH), GDScript, headless tests via `tools/run_tests.sh` / `godot --headless --path . -s tests/<file>.gd`.

**Spec:** `docs/superpowers/specs/2026-09-20-encounter-objectives-design.md`

## Global Constraints

- A spec without `objective` is today's fight, byte for byte: `tests/test_combat.gd`, `tests/test_encounter.gd`, `tests/test_fight_invariants.gd`, `tests/test_scaler.gd` must pass unchanged after every task.
- Nothing in `core/scaler.gd` changes. Objective difficulty is tuned only by the kind's own knob in `core/objectives.gd` (rounds, deadline, carter HP, wave power, quarry threshold).
- The objective dict in a spec must stay JSON-clean (ints, floats, strings, arrays, dicts) — it crosses the co-op wire. `exit` (an array of `Vector2i`) is written onto `Combat.objective` at build time, never into the spec.
- Preload graph: `scaler.gd` preloads `encounter.gd`; `encounter.gd`, `combat.gd` and `ai.gd` will preload `objectives.gd`; therefore `objectives.gd` must not preload `scaler.gd`, `encounter.gd`, `combat.gd`, `quest.gd` or `site.gd` — use `load()` at call time where one of those is needed (the codebase's existing idiom: "load(), not preload — X preloads this file").
- Ids of wave spawns are prefixed (`w<round>-`) so every combatant id stays unique (`Coop.find`, `main._combatant` look up by id).
- Never call `pkill -f "<pattern>"` from the tool shell with a pattern that appears in the command itself.
- Commit after each task with the message shown; every commit message ends with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- Work on branch `claude/objectives` (already exists, holds the spec).

---

### Task 1: The contract and the bystanders

**Files:**
- Create: `core/objectives.gd`
- Modify: `core/combat.gd` (fields near line 47; `_roll_initiative` ~211; `enemies_of` ~427; `legal_target` ~777; `_apply_damage` ~2354; `_kill` ~2414; `_team_out` ~408)
- Create: `tests/test_objectives.gd`

**Interfaces:**
- Produces: `Objectives.KINDS`, the knob constants, `Objectives.bystander(id, cname, pos, ac, hp, extra) -> Combatant`, `Objectives.captive(pos)`, `Objectives.carter(pos, level)`.
- Produces on `Combat`: `var objective: Dictionary`, `var objective_done: bool`, `var objective_failed: bool`, `func objective_kind() -> String`, `func with_status(s: String)`, `func heroes() -> Array`.
- Bystander semantics: status `bystander` = not in `order`, not counted by `_team_out`, dies outright at 0 HP, never in `downed`; status `captive` additionally = never an enemy target.

- [ ] **Step 1: Write the failing test**

Create `tests/test_objectives.gd`:

```gdscript
# Encounter objectives — the same fight, asked a different question.
#   docs/superpowers/specs/2026-09-20-encounter-objectives-design.md
#   godot --headless --path . -s tests/test_objectives.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_bystander()
	print("test_objectives: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# A fight from a spec, the way scenes/main.gd builds one: board from the theme
# and seed, starts from the objective, presets at level 3 for the party.
func _fight(spec: Dictionary, seed: int) -> Combat:
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), seed)
	var starts: Array = Encounter.starts_for(sp, board, seed) if Encounter.has_method("starts_for") \
		else Encounter.party_starts(board, seed)
	var chars: Array = Presets.party()
	var party_c: Array = []
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", starts[i]))
	return Encounter.build(sp, party_c, board)

func _autoplay(cb: Combat) -> void:
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1

func _goblins(n: int) -> Dictionary:
	return {"monsters": [{"id": "snik", "count": n}], "theme": "goblin-camp"}

# --- Task 1: the contract and the bystanders --------------------------------

func test_bystander() -> void:
	var cb := _fight(_goblins(2), 5)
	check(cb.objective.is_empty() and cb.objective_kind() == "", "no objective on the spec = rout")
	check(cb.order.size() == cb.combatants.size(), "rout: everybody who is in the fight has a turn")

	var car = Objectives.carter(Vector2i(0, 1), 3)
	check(car.team == "party" and car.has("bystander") and car.hp == 12 and car.ac == 11,
		"a carter is a party-side bystander with 6 + 2/level HP")
	var cap = Objectives.captive(Vector2i(8, 0))
	check(cap.has("bystander") and cap.has("captive") and cap.hp == 4, "a captive is a bystander that is also a captive")

	# Stood in a fight: never in the order, never a target for a foe, no death saves.
	var party_c: Array = []
	var chars: Array = Presets.party()
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	party_c.append(car)
	party_c.append(cap)
	var foe = Encounter.spawn("snik", 1.0, "foe", Vector2i(7, 0))
	var cb2 = Combat.new(RNG.new(3), party_c + [foe], Encounter.board())
	check(cb2.order.size() == 4, "the two bystanders are not in the initiative order (%d)" % cb2.order.size())
	check(cb2.with_status("carter") == car and cb2.with_status("captive") == cap, "with_status finds them")
	check(cb2.heroes().size() == 3, "heroes() is the conscious party without bystanders")
	check(not cb2.enemies_of(foe).has(cap), "a captive is never an enemy for a foe")
	check(cb2.enemies_of(foe).has(car), "...but a carter is fair game")
	check(not cb2.legal_target(foe, cb2.attack_verb(), cap), "legal_target refuses the captive")
	cb2._apply_damage(car, 50)
	check(car.is_dead() and not car.is_down(), "a bystander at 0 HP is dead, not down")
	check(not cb2.downed.has("carter"), "...and is not in the downed list")
	for h in cb2.heroes():
		cb2._apply_damage(h, 500)
	check(cb2._team_out("party"), "a party with only a bystander standing is out")
	check(cb2.is_over() and cb2.outcome() == "Defeat", "...and that is a defeat")
```

- [ ] **Step 2: Run it to see it fail**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -5`
Expected: parse errors — `res://core/objectives.gd` does not exist; `objective_kind` not found.

- [ ] **Step 3: Create `core/objectives.gd`**

```gdscript
# Encounter objectives — the same fight, asked a different question.
#
#   spec["objective"] = {"kind": "hold", "rounds": 5, "waves": [[{"id": "snik", "count": 2}]]}
#
# Absent or empty means rout (kill everyone), which is every fight the game had
# before this file. What a kind MEANS inside the fight lives in core/combat.gd
# (_objective_round / _objective_touch / _objective_over / objective_result);
# this file is what a kind IS: the knobs the sweep tunes, the tokens, the
# builders the world calls, and the words the screen shows.
#   docs/superpowers/specs/2026-09-20-encounter-objectives-design.md
#
# Preloads nothing that preloads core/encounter.gd (scaler.gd does): this file
# is preloaded by encounter.gd, combat.gd and ai.gd, so anything heavier goes
# through load() at call time.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")
const Hex = preload("res://core/hex.gd")

const KINDS := ["hold", "rescue", "breakout", "hunt", "escort"]

# --- knobs: the only things the sweep in tests/test_objectives.gd may turn ----
const HOLD_ROUNDS := 5          # hold: Victory at the top of round HOLD_ROUNDS + 1
const WAVE_ROUNDS := [2, 4]     # hold: a wave arrives at the top of each of these rounds
const WAVE_SCALE := 0.4         # hold: a wave's budget, as a share of an easy roster's
const RESCUE_DEADLINE := 4      # rescue: unfreed at the top of round RESCUE_DEADLINE + 1, the captive dies
const CAPTIVE_AC := 10
const CAPTIVE_HP := 4
const EXIT_W := 4               # breakout / hunt: how many far-edge hexes are the road out
const QUARRY_CORNERED := 3      # hunt: a hero this close makes the quarry fight rather than run
const CARTER_AC := 11
const CARTER_HP_BASE := 6
const CARTER_HP_PER_LEVEL := 2
const BONUS_XP_SHARE := 0.5     # an objective done pays this share of the whole roster's worth in XP

# --- tokens -----------------------------------------------------------------

# A bystander stands on the party's side of the board and does nothing: no
# turn, no orders, no death saves. Everything in combat.gd that keys on the
# `bystander` status is listed in the spec's §3.
static func bystander(id: String, cname: String, pos: Vector2i, ac: int, hp: int, extra: Array = []):
	var c = Combatant.new()
	c.id = id
	c.cname = cname
	c.short = cname
	c.team = "party"
	c.pos = pos
	c.ac = ac
	c.max_hp = hp
	c.hp = hp
	c.speed = 0
	c.statuses["bystander"] = true
	for s in extra:
		c.statuses[s] = true
	return c

static func captive(pos: Vector2i):
	return bystander("captive", "The captive", pos, CAPTIVE_AC, CAPTIVE_HP, ["captive"])

static func carter(pos: Vector2i, level: int):
	return bystander("carter", "The carter", pos, CARTER_AC, CARTER_HP_BASE + CARTER_HP_PER_LEVEL * maxi(1, level))
```

- [ ] **Step 4: Add the fields and the bystander rules to `core/combat.gd`**

Near the other fields (after `var downed: Dictionary = {}`, ~line 51):

```gdscript
# --- objectives (core/objectives.gd; the spec is docs/superpowers/specs/
# 2026-09-20-encounter-objectives-design.md). {} = rout: the fight every fight
# was before. `exit` is written here by Encounter.build, never into the spec.
const Objectives = preload("res://core/objectives.gd")
var objective: Dictionary = {}
var objective_done := false      # the deed is done: the gate held, the road reached, the quarry down
var objective_failed := false    # the captive killed, the carter dead, the quarry gone — the fight goes on

func objective_kind() -> String:
	return String(objective.get("kind", ""))

# The one combatant carrying a status (captive, carter, quarry), or null.
func with_status(s: String):
	for c in combatants:
		if c.has(s):
			return c
	return null

# The conscious party without its bystanders: who can act, who must reach the road.
func heroes() -> Array:
	return combatants.filter(func(c): return c.team == "party" and c.conscious() and not c.has("bystander"))
```

In `_roll_initiative()` replace `order = combatants.duplicate()` with:

```gdscript
	# A bystander (a captive, a carter) has no turn: it stands where it is put.
	order = combatants.filter(func(c): return not c.has("bystander"))
```

In `_team_out()` add the bystander clause:

```gdscript
func _team_out(team: String) -> bool:
	for c in combatants:
		if c.team == team and c.conscious() and not c.has("illusion") and not c.has("bystander"):
			return false
	return true
```

In `enemies_of()` exclude the captive (a bound captive is worthless dead until the deadline — the executioner rule in Task 3 is the only thing that harms it):

```gdscript
func enemies_of(c) -> Array:
	return combatants.filter(func(o): return o.team != c.team and o.conscious() and not o.has("hidden") \
		and not o.has("captive"))
```

In `legal_target()`, inside `"enemy":` right after the `illusion` check:

```gdscript
			if c.has("captive"):
				return false  # bound and worthless dead: not a target, and not shovable
```

In `_apply_damage()`'s `if target.hp <= 0:` branch:

```gdscript
		if target.team == "party" and not target.has("bystander"):
			downed[target.id] = true
		if target.team == "foe" or target.has("bystander") or overkill >= target.max_hp:
```

(the `Ach.unlock("overkill")` line inside is unchanged — it already tests `target.team == "foe"`).

In `_kill()`, after `c.hp = 0`:

```gdscript
	if c.has("bystander"):
		objective_failed = true   # whoever it was, they were the point
```

- [ ] **Step 5: Run the test and the guard suites**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: `test_objectives: 14 passed, 0 failed`

Run: `for t in test_combat test_encounter test_fight_invariants test_ai; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done`
Expected: every line ends `0 failed` (or `OK`).

- [ ] **Step 6: Commit**

```bash
git add core/objectives.gd core/combat.gd tests/test_objectives.gd
git commit -m "Objectives: the contract on Combat, and the bystanders

spec.objective lands on Combat.objective; a bystander (captive, carter) is
a party-side token with no turn, no death saves and no weight in
_team_out; a captive is never a foe's target.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Placement — starts, spots, tokens, the exit

**Files:**
- Modify: `core/encounter.gd` (`build()` ~380; new statics beside `party_starts` ~337 and `_foe_spots` ~452)
- Modify: `core/objectives.gd` (add `make()`, `brief()`, `party_level()`)
- Test: `tests/test_objectives.gd`

**Interfaces:**
- Produces: `Encounter.starts_for(spec, board, seed) -> Array`, `Encounter.far_hexes(board, taken: Array, n: int) -> Array`, `Encounter.deepest_hex(board, party_c, taken) -> Vector2i`, `Encounter.huddle_hex(board, party_c) -> Vector2i`, `Encounter.middle_starts(board, seed) -> Array`, `Encounter.surround_spots(board, party_c, exclude) -> Array`, `Encounter.mark_quarry(foes: Array, party_c: Array) -> void`.
- Produces: `Objectives.make(kind, extra := {}) -> Dictionary`, `Objectives.brief(o) -> String`, `Objectives.party_level(party_c) -> int`.
- `Encounter.build()` now: copies `spec.objective` to `cb.objective`; for breakout/hunt writes `cb.objective["exit"]` (an `Array` of `Vector2i`); appends the captive / carter to the combatants before `Combat.new`; marks the quarry; appends `Objectives.brief()` to the log.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_objectives.gd` (and call them from `_init` after `test_bystander()`):

```gdscript
func test_make_and_brief() -> void:
	var h := Objectives.make("hold")
	check(h["kind"] == "hold" and int(h["rounds"]) == Objectives.HOLD_ROUNDS and h["waves"] == [], "hold has its defaults")
	check(int(Objectives.make("rescue")["deadline"]) == Objectives.RESCUE_DEADLINE, "rescue has its deadline")
	check(Objectives.make("hold", {"rounds": 9})["rounds"] == 9, "extra overrides a default")
	for k in Objectives.KINDS:
		check(Objectives.brief(Objectives.make(k)) != "", "%s has a brief" % k)
	check(Objectives.brief({}) == "", "rout has no brief")

func test_placement() -> void:
	# rescue: the captive is the deepest free hex, and foes are not on top of it
	var cb := _fight(_goblins(3).merged({"objective": Objectives.make("rescue")}), 7)
	var cap = cb.with_status("captive")
	check(cap != null and cap.pos in cb.board["hexes"], "rescue puts a captive on the board")
	var nearest := 99
	for h in cb.heroes():
		nearest = mini(nearest, Hex.distance(h.pos, cap.pos))
	check(nearest >= Encounter.SPAWN_GAP, "...well beyond the party (%d)" % nearest)
	check(cb.combatants.filter(func(c): return c.pos == cap.pos).size() == 1, "...on a hex of its own")
	check(cb.log[cb.log.size() - 1] == Objectives.brief(cb.objective) or cb.log.has(Objectives.brief(cb.objective)),
		"the brief is in the log")

	# escort: the carter is in among the party
	cb = _fight(_goblins(3).merged({"objective": Objectives.make("escort")}), 7)
	var car = cb.with_status("carter")
	var far := 0
	for h in cb.heroes():
		far = maxi(far, Hex.distance(h.pos, car.pos))
	check(car != null and far <= 3, "escort puts the carter in among the party (farthest hero %d)" % far)
	check(car.max_hp == Objectives.CARTER_HP_BASE + Objectives.CARTER_HP_PER_LEVEL * 3, "...with HP for a level-3 party")

	# breakout: the party in the middle, foes both sides, the exit at the far edge and free of foes
	cb = _fight(_goblins(6).merged({"objective": Objectives.make("breakout")}), 7)
	var exit: Array = cb.objective.get("exit", [])
	check(exit.size() == Objectives.EXIT_W, "breakout has %d exit hexes" % Objectives.EXIT_W)
	var max_q := -99
	for h in cb.board["hexes"]:
		max_q = maxi(max_q, h.x)
	check(exit.all(func(e): return e.x >= max_q - 2), "...at the far (high-q) edge")
	check(cb.team_of("foe").all(func(f): return not (f.pos in exit)), "...and nobody spawns on the road")
	var qs: Array = cb.heroes().map(func(h): return h.pos.x)
	var lo: int = cb.team_of("foe").filter(func(f): return f.pos.x < qs.min()).size()
	var hi: int = cb.team_of("foe").filter(func(f): return f.pos.x > qs.max()).size()
	check(lo > 0 and hi > 0, "foes stand on both sides of the party (%d behind, %d ahead)" % [lo, hi])

	# hunt: the strongest foe is the quarry and it starts nearest the party — it has the whole board to cross
	cb = _fight({"monsters": [{"id": "snik", "count": 3}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}, 7)
	var q = cb.with_status("quarry")
	check(q != null and q.src_id == "grull", "the quarry is the strongest foe")
	check(cb.objective.get("exit", []).size() == Objectives.EXIT_W, "hunt has an escape edge")
	var qd := 99
	for h in cb.heroes():
		qd = mini(qd, Hex.distance(h.pos, q.pos))
	for f in cb.team_of("foe"):
		var fd := 99
		for h in cb.heroes():
			fd = mini(fd, Hex.distance(h.pos, f.pos))
		check(fd >= qd, "no foe starts nearer the party than the quarry (%s %d vs %d)" % [f.cname, fd, qd])

	# starts_for: breakout is the only kind that moves the party
	var board: Dictionary = Encounter.board_for("goblin-camp", 7)
	check(Encounter.starts_for(_goblins(3), board, 7) == Encounter.party_starts(board, 7), "rout starts where it always did")
	check(Encounter.starts_for({"objective": Objectives.make("hunt")}, board, 7) == Encounter.party_starts(board, 7), "so does a hunt")
	check(Encounter.starts_for({"objective": Objectives.make("breakout")}, board, 7) != Encounter.party_starts(board, 7), "a breakout starts elsewhere")
```

- [ ] **Step 2: Run it to see it fail**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: fails on `Objectives.make` / `starts_for` not found.

- [ ] **Step 3: Add `make()`, `brief()`, `party_level()` to `core/objectives.gd`**

```gdscript
# --- builders ---------------------------------------------------------------

# An objective dict with the kind's defaults; `extra` overrides (a site passes
# its waves, a story its own deadline). Stays JSON-clean: it rides the spec
# over the co-op wire.
static func make(kind: String, extra: Dictionary = {}) -> Dictionary:
	var o := {"kind": kind}
	match kind:
		"hold":
			o["rounds"] = HOLD_ROUNDS
			o["waves"] = []
		"rescue":
			o["deadline"] = RESCUE_DEADLINE
	o.merge(extra, true)
	return o

# The carter's HP scales with the party; `party_c` are combatants, whose sheet
# (null for a preset-less test party) carries the level.
static func party_level(party_c: Array) -> int:
	var total := 0
	var n := 0
	for c in party_c:
		if c.sheet != null:
			total += int(c.sheet.level)
			n += 1
	return maxi(1, roundi(float(total) / n)) if n > 0 else 1

# --- words ------------------------------------------------------------------

# One line, read before the board comes up: the question this fight asks.
static func brief(o: Dictionary) -> String:
	match String(o.get("kind", "")):
		"hold":
			return "Hold the passage for %d rounds. More of them will come from the far side." % int(o.get("rounds", HOLD_ROUNDS))
		"rescue":
			return "A captive is bound at the back of the room. Reach them by the end of round %d, or the captors will make sure you cannot." % int(o.get("deadline", RESCUE_DEADLINE))
		"breakout":
			return "Surrounded. Get everyone still standing to the road at the far edge — or cut your way through the lot of them."
		"hunt":
			return "Their leader will run for the far edge. Drop them before they reach it and the rest will scatter."
		"escort":
			return "The carter stands with you. If the carter dies, the delivery dies with them."
	return ""

const TITLES := {"hold": "Hold the line", "rescue": "Rescue", "breakout": "Break out",
	"hunt": "The hunt", "escort": "Escort"}

static func title(kind: String) -> String:
	return String(TITLES.get(kind, ""))
```

- [ ] **Step 4: Add the placement statics to `core/encounter.gd`**

Add `const Objectives = preload("res://core/objectives.gd")` beside the other preloads at the top. Then, after `party_starts()`:

```gdscript
# Where the party stands for this spec: the low-q edge as always, or — for a
# breakout — the middle of the board with the foes on both sides. The one
# place scenes/main.gd and the co-op guest ask, so both peers agree.
static func starts_for(spec: Dictionary, b: Dictionary, seed: int) -> Array:
	if String(spec.get("objective", {}).get("kind", "")) == "breakout":
		return middle_starts(b, seed)
	return party_starts(b, seed)

# Open = on the board, not blocked by an object, not in `taken`.
static func _open(b: Dictionary, taken: Array) -> Array:
	var blocked: Array = b.get("objects", []).filter(
		func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
	return b["hexes"].filter(func(h): return not (h in blocked) and not (h in taken))

# party_starts' shape, anchored near the board's centre instead of its low-q edge.
static func middle_starts(b: Dictionary, seed: int) -> Array:
	var open: Array = _open(b, [])
	if open.size() < 8:
		return PARTY_STARTS
	var cx := 0.0
	var cy := 0.0
	for h in open:
		cx += h.x
		cy += h.y
	var mid := Vector2i(roundi(cx / open.size()), roundi(cy / open.size()))
	var near: Array = open.duplicate()
	near.sort_custom(func(a, c): return Hex.distance(a, mid) < Hex.distance(c, mid))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchor: Vector2i = near[rng.randi() % mini(6, near.size())]   # a little seeded jitter, as party_starts has
	near.sort_custom(func(a, c): return Hex.distance(a, anchor) < Hex.distance(c, anchor))
	var cluster: Array = near.slice(0, 4)
	cluster.sort_custom(func(a, c): return a.x > c.x or (a.x == c.x and a.y < c.y))
	return cluster

# The n open hexes nearest the far (high-q) end: the road out of a breakout,
# the treeline a quarry runs for, where a wave comes in. Deterministic order,
# so both co-op peers hold the same hexes.
static func far_hexes(b: Dictionary, taken: Array, n: int) -> Array:
	var open: Array = _open(b, taken)
	open.sort_custom(func(a, c): return a.x > c.x or (a.x == c.x and a.y < c.y))
	return open.slice(0, n)

# The open hex farthest from every party member (ties: higher q, then lower r):
# where a captive is chained.
static func deepest_hex(b: Dictionary, party_c: Array, taken: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := -1
	for h in _open(b, taken):
		var d := 1 << 30
		for c in party_c:
			d = mini(d, Hex.distance(h, c.pos))
		if d > best_d or (d == best_d and (h.x > best.x or (h.x == best.x and h.y < best.y))):
			best_d = d
			best = h
	return best

# The free hex closest to everyone in the party at once: where the carter huddles.
static func huddle_hex(b: Dictionary, party_c: Array) -> Vector2i:
	var taken: Array = party_c.map(func(c): return c.pos)
	var best := Vector2i.ZERO
	var best_s := 1 << 30
	for h in _open(b, taken):
		var s := 0
		for p in taken:
			s += Hex.distance(h, p)
		if s < best_s or (s == best_s and (h.x < best.x or (h.x == best.x and h.y < best.y))):
			best_s = s
			best = h
	return best

# Breakout: foes on both sides of a party standing in the middle — ahead and
# behind alternating, nearest first, never on the road out (`exclude`).
static func surround_spots(b: Dictionary, party_c: Array, exclude: Array) -> Array:
	var taken: Array = party_c.map(func(c): return c.pos)
	var front := -(1 << 30)
	var back := 1 << 30
	for p in taken:
		front = maxi(front, p.x)
		back = mini(back, p.x)
	var open: Array = _open(b, taken + exclude)
	# Bucket by side at a gap; a board too narrow for the full gap on one side
	# takes half of it there — surrounded means both sides, closer if it must be.
	var bucket := func(gap: int) -> Array:
		var ahead: Array = []
		var behind: Array = []
		var rest: Array = []
		for h in open:
			var d := 99
			for p in taken:
				d = mini(d, Hex.distance(h, p))
			if d >= gap and h.x > front:
				ahead.append([d, h])
			elif d >= gap and h.x < back:
				behind.append([d, h])
			else:
				rest.append([-d, h])   # overflow: the least-bad remaining hexes, as _foe_spots does
		return [ahead, behind, rest]
	var sides: Array = bucket.call(SPAWN_GAP)
	if sides[0].is_empty() or sides[1].is_empty():
		sides = bucket.call(SPAWN_GAP / 2)
	var ahead: Array = sides[0]
	var behind: Array = sides[1]
	var rest: Array = sides[2]
	ahead.sort_custom(func(a, c): return a[0] < c[0])
	behind.sort_custom(func(a, c): return a[0] < c[0])
	rest.sort_custom(func(a, c): return a[0] < c[0])
	var out: Array = []
	while not ahead.is_empty() or not behind.is_empty():
		if not ahead.is_empty():
			out.append(ahead.pop_front()[1])
		if not behind.is_empty():
			out.append(behind.pop_front()[1])
	for e in rest:
		out.append(e[1])
	return out

# Hunt: the strongest foe is the quarry, and it trades places with whichever foe
# stands nearest the party — it has the whole board to cross, and the party has
# a chance to close before it does.
static func mark_quarry(foes: Array, party_c: Array) -> void:
	if foes.is_empty():
		return
	var quarry = foes[0]
	for f in foes:
		if float(Power.estimate(f)["score"]) > float(Power.estimate(quarry)["score"]):
			quarry = f
	quarry.statuses["quarry"] = true
	var nearest = foes[0]
	var nd := 1 << 30
	for f in foes:
		var d := 1 << 30
		for c in party_c:
			d = mini(d, Hex.distance(f.pos, c.pos))
		if d < nd:
			nd = d
			nearest = f
	var p: Vector2i = quarry.pos
	quarry.pos = nearest.pos
	nearest.pos = p
```

Then change `build()`:

```gdscript
static func build(spec: Dictionary, party_combatants: Array, board: Dictionary = {}) -> Combat:
	var b: Dictionary = board if not board.is_empty() else board_for(String(spec.get("theme", "")), int(spec.get("seed", 0)))
	if spec.get("night", false):
		b["night"] = true   # #85
	var o: Dictionary = spec.get("objective", {}).duplicate(true)
	var kind := String(o.get("kind", ""))
	var all_c: Array = party_combatants.duplicate()
	# The road out / the treeline: the far edge, held free of spawns.
	var exit: Array = far_hexes(b, [], Objectives.EXIT_W) if kind in ["breakout", "hunt"] else []
	var spots: Array = surround_spots(b, party_combatants, exit) if kind == "breakout" else _foe_spots(b, party_combatants)
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else PARTY_STARTS[0]
			var c = spawn(e["id"], mult, "foe", pos, n + 1 if count > 1 else 0, e.get("features", []))
			if c != null:
				all_c.append(c)
			i += 1
	var foes: Array = all_c.filter(func(c): return c.team == "foe")
	match kind:
		"rescue":
			all_c.append(Objectives.captive(deepest_hex(b, party_combatants, all_c.map(func(c): return c.pos))))
		"escort":
			all_c.append(Objectives.carter(huddle_hex(b, party_combatants), Objectives.party_level(party_combatants)))
		"hunt":
			mark_quarry(foes, party_combatants)
	var RNG = load("res://core/rng.gd")
	var sd: int = int(spec.get("seed", 0))
	var cb := Combat.new(RNG.new(sd if sd > 0 else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)),
		all_c, b)
	if kind != "":
		o["exit"] = exit
		cb.objective = o
		cb.log.append(Objectives.brief(o))
	return cb
```

- [ ] **Step 5: Run the tests**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: `0 failed`.

Run: `for t in test_combat test_encounter test_fight_invariants test_scaler; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done`
Expected: all `0 failed`. (`test_scaler` takes ~1 min.)

- [ ] **Step 6: Commit**

```bash
git add core/objectives.gd core/encounter.gd tests/test_objectives.gd
git commit -m "Objectives: placement — starts, spots, the captive, the carter, the quarry, the exit

Encounter.build reads spec.objective: a captive at the deepest hex, a
carter in the huddle, the quarry swapped to the front of the roster, a
breakout's party in the middle with foes both sides and the far edge
held as the road out.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The rules of each kind, inside the fight

**Files:**
- Modify: `core/combat.gd` (`end_turn` ~351; `is_over`/`outcome` ~404; `move_to` ~2560; `_kill` ~2414; new functions beside `objective_kind()`)
- Test: `tests/test_objectives.gd`

**Interfaces:**
- Produces on `Combat`: `func objective_line() -> String` (the HUD line), `func objective_result() -> bool` (was the deed done — read by `resolve_outcome` in Task 5), `func _objective_round()`, `func _objective_touch(c)`, `func _objective_over() -> bool`, `func _spawn_wave(roster: Array)`, `func _quarry_escape(q)`.
- Statuses written: `freed` on the captive, `escaped` (+ `dead`) on a quarry that got away.
- `is_over()` is also true when `_objective_over()`; `outcome()` says Victory then.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_objectives.gd` and call from `_init`:

```gdscript
# Walk the order until `who` is current, beginning turns and letting the AI
# take everyone else's. Returns false if the fight ended first.
func _until_turn_of(cb: Combat, who) -> bool:
	var g := 0
	while not cb.is_over() and g < 200:
		var a = cb.current()
		cb.begin_turn()
		if a == who:
			return true
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return false

# Nobody moves and nobody dies: for the rule tests that place tokens by hand.
func _freeze(cb: Combat) -> void:
	for c in cb.combatants:
		if not c.has("bystander"):
			c.speed = 0
			c.max_hp = 100000
			c.hp = 100000

func _rounds_until_over(cb: Combat, cap := 40) -> int:
	while not cb.is_over() and cb.round_num <= cap:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
	return cb.round_num

func test_hold() -> void:
	# An unkillable wall of goblins: the only way this ends is the clock.
	var spec := {"monsters": [{"id": "snik", "count": 2, "mult": 6.0}], "theme": "goblin-camp",
		"objective": Objectives.make("hold", {"rounds": 3, "waves": [[{"id": "snik", "count": 2}], [{"id": "snik", "count": 1}]]})}
	var cb := _fight(spec, 11)
	var opening: int = cb.team_of("foe").size()
	_freeze(cb)   # nothing dies either way: only the clock can end this
	_rounds_until_over(cb, 10)
	check(cb.round_num == 4, "hold ends at the top of round rounds + 1 (%d)" % cb.round_num)
	check(cb.outcome() == "Victory" and cb.objective_done, "...and it is a victory with foes standing")
	check(cb.team_of("foe").size() == opening + 3, "two waves arrived (%d foes)" % cb.team_of("foe").size())
	check(cb.team_of("foe").any(func(f): return f.id.begins_with("w2-")), "wave ids are prefixed by their round")
	check(cb.objective_result(), "the deed is done")
	check(cb.objective_line().begins_with("Hold — round"), "HUD: %s" % cb.objective_line())

func test_rescue() -> void:
	var spec := _goblins(1).merged({"objective": Objectives.make("rescue", {"deadline": 2})})
	var cb := _fight(spec, 13)
	var cap = cb.with_status("captive")
	_freeze(cb)   # nobody can walk to the captive, so the deadline is what happens
	check(cb.objective_line() == "Captive — 2 rounds left", "HUD counts down: %s" % cb.objective_line())
	_rounds_until_over(cb, 4)
	check(cap.is_dead() and cb.objective_failed, "unfreed at the top of round deadline + 1, the captive is killed")
	check(not cb.is_over(), "...and the fight goes on")
	check(cb.objective_line() == "Captive — lost", "HUD says so")

	# freed by adjacency, no action needed, before the deadline
	cb = _fight(spec, 13)
	cap = cb.with_status("captive")
	_freeze(cb)
	var h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "it is a hero's turn")
	h.pos = Hex.neighbors(cap.pos)[0]
	cb.end_turn()
	check(cap.has("freed") and not cb.objective_failed, "ending a turn adjacent frees the captive")
	check(cb.objective_result(), "...which is the deed")
	for i in 6:
		cb.begin_turn(); cb.end_turn()
	check(not cap.is_dead(), "the deadline no longer applies")

func test_breakout() -> void:
	var spec := _goblins(2).merged({"objective": Objectives.make("breakout")})
	var cb := _fight(spec, 17)
	var exit: Array = cb.objective["exit"]
	_freeze(cb)
	var heroes: Array = cb.heroes()
	check(cb.objective_line() == "Road — 0 of %d heroes there" % heroes.size(), "HUD: %s" % cb.objective_line())
	check(_until_turn_of(cb, heroes[0]), "a hero's turn")
	heroes[0].pos = exit[0]
	cb.end_turn()
	check(not cb.is_over(), "one hero on the road is not a breakout")
	for i in heroes.size():
		heroes[i].pos = exit[i]
	cb._objective_touch(heroes[1])
	check(cb.objective_done and cb.is_over() and cb.outcome() == "Victory", "everyone on the road ends it, a victory, foes standing")

func test_hunt() -> void:
	var spec := {"monsters": [{"id": "snik", "count": 2}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	var cb := _fight(spec, 19)
	_freeze(cb)
	var q = cb.with_status("quarry")
	var exit: Array = cb.objective["exit"]
	check(_until_turn_of(cb, q), "the quarry's turn")
	q.pos = exit[0]
	cb.end_turn()
	check(q.has("escaped") and q.is_dead() and cb.objective_failed, "ending its turn on the far edge, the quarry is gone")
	check(not cb.is_over(), "...and the escort is still there to fight")
	check(cb.objective_line() == "Quarry — gone", "HUD: %s" % cb.objective_line())

	cb = _fight(spec, 19)
	q = cb.with_status("quarry")
	cb._apply_damage(q, 999)
	check(q.is_dead() and cb.objective_done and cb.is_over() and cb.outcome() == "Victory",
		"the quarry down ends the fight as a victory with the escort standing")
	check(cb.objective_result(), "...and the deed is done")

func test_escort() -> void:
	var spec := _goblins(2).merged({"objective": Objectives.make("escort")})
	var cb := _fight(spec, 23)
	var car = cb.with_status("carter")
	check(cb.objective_line() == "Carter — %d HP" % car.hp, "HUD: %s" % cb.objective_line())
	check(cb.objective_result(), "alive = the deed, so far")
	cb._apply_damage(car, 99)
	check(car.is_dead() and cb.objective_failed and not cb.is_over(), "the carter dead fails the objective and the fight goes on")
	check(not cb.objective_result() and cb.objective_line() == "Carter — dead", "HUD: %s" % cb.objective_line())
```

- [ ] **Step 2: Run to see it fail**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: fails on `objective_line` / `_objective_touch` / `objective_result` not found.

- [ ] **Step 3: Implement the rules in `core/combat.gd`**

After `heroes()`:

```gdscript
# --- the rules of each kind ---------------------------------------------------
#
# hold     Victory at the top of round `rounds` + 1 with anyone standing; a
#          wave arrives at the top of each Objectives.WAVE_ROUNDS round.
# rescue   a hero adjacent to the captive frees it (no action); unfreed at the
#          top of round `deadline` + 1, the captors kill it. The fight goes on.
# breakout every conscious hero on an exit hex ends the fight, a Victory.
# hunt     the quarry ending its turn on an exit hex is gone (objective failed,
#          fight goes on vs the escort); the quarry dead ends the fight, a Victory.
# escort   the carter dead fails the objective; the fight goes on.

# The top of a new round: waves, and the captors' deadline.
func _objective_round() -> void:
	match objective_kind():
		"hold":
			var waves: Array = objective.get("waves", [])
			var i: int = Objectives.WAVE_ROUNDS.find(round_num)
			if i >= 0 and i < waves.size():
				_spawn_wave(waves[i])
			if round_num > int(objective.get("rounds", 0)) and not _team_out("party") and not objective_done:
				objective_done = true
				log.append("The way behind is barred — the passage held.")
		"rescue":
			var cap = with_status("captive")
			if cap != null and not cap.has("freed") and not cap.is_dead() \
					and round_num > int(objective.get("deadline", 0)):
				log.append("Nobody reached %s in time. The captors make sure of it." % cap.cname)
				_kill(cap)

# A wave comes in from the far side and rolls its own initiative (_join_order),
# on the fight's own stream so both co-op peers see the same arrivals.
func _spawn_wave(roster: Array) -> void:
	var Enc = load("res://core/encounter.gd")   # load: encounter.gd preloads this file
	var taken: Array = combatants.filter(func(c): return not c.is_dead()).map(func(c): return c.pos)
	var spots: Array = Enc.far_hexes(board, taken, 12)
	var i := 0
	var names: Array = []
	for e in roster:
		var count: int = maxi(1, int(e.get("count", 1)))
		for n in count:
			if i >= spots.size():
				break
			var c = Enc.spawn(String(e["id"]), float(e.get("mult", 1.0)), "foe", spots[i],
				n + 1 if count > 1 else 0, e.get("features", []))
			if c == null:
				continue
			c.id = "w%d-%s" % [round_num, c.id]
			combatants.append(c)
			_join_order(c)
			names.append(c.cname)
			i += 1
	if not names.is_empty():
		log.append("More of them, from the far side: %s." % ", ".join(names))

# The deeds that are a matter of standing somewhere — reaching the captive,
# reaching the road — checked after every hero move and at every turn's end.
func _objective_touch(c) -> void:
	if c == null or c.team != "party" or not c.conscious() or c.has("bystander"):
		return
	match objective_kind():
		"rescue":
			var cap = with_status("captive")
			if cap != null and not cap.has("freed") and not cap.is_dead() and Hex.distance(c.pos, cap.pos) <= 1:
				cap.statuses["freed"] = true
				log.append("%s cuts %s loose." % [c.cname, cap.cname])
		"breakout":
			if objective_done:
				return
			var exit: Array = objective.get("exit", [])
			for h in heroes():
				if not (h.pos in exit):
					return
			objective_done = true
			log.append("The party is through — the road is under their feet, and the rest can chase.")

# The quarry ending its turn on the far edge is off the board: not killed (no
# loot, no XP — it took those with it), but `dead` is what `order` carries
# for a gap, the same reason _fade_if_expired leaves a body.
func _quarry_escape(q) -> void:
	q.statuses["escaped"] = true
	q.statuses["dead"] = true
	q.hp = 0
	objective_failed = true
	log.append("%s is into the trees and gone." % q.cname)

func _objective_over() -> bool:
	return objective_done and objective_kind() in ["hold", "breakout", "hunt"]

# Was the deed done — for the spoils page and the pay. The kinds that end the
# fight themselves are judged the moment they do; rescue and escort at the end.
func objective_result() -> bool:
	match objective_kind():
		"rescue":
			var cap = with_status("captive")
			return cap != null and cap.has("freed") and not cap.is_dead()
		"escort":
			var car = with_status("carter")
			return car != null and not car.is_dead()
		"hold", "breakout":
			return objective_done or _team_out("foe")   # a rout holds the gate and clears the road too
		"hunt":
			return objective_done
	return false

# The HUD's one line under the round counter.
func objective_line() -> String:
	match objective_kind():
		"hold":
			var r: int = int(objective.get("rounds", 0))
			return "Hold — round %d of %d" % [mini(round_num, r), r]
		"rescue":
			var cap = with_status("captive")
			if cap == null or cap.is_dead():
				return "Captive — lost"
			if cap.has("freed"):
				return "Captive — freed"
			var left: int = maxi(0, int(objective.get("deadline", 0)) - round_num + 1)
			return "Captive — %d round%s left" % [left, "" if left == 1 else "s"]
		"breakout":
			var exit: Array = objective.get("exit", [])
			var hs: Array = heroes()
			var there: int = hs.filter(func(h): return h.pos in exit).size()
			return "Road — %d of %d heroes there" % [there, hs.size()]
		"hunt":
			var q = with_status("quarry")
			if q == null:
				return ""
			if q.has("escaped"):
				return "Quarry — gone"
			if q.is_dead():
				return "Quarry — down"
			var d := 1 << 30
			for e in objective.get("exit", []):
				d = mini(d, Hex.distance(q.pos, e))
			return "Quarry — %d hex%s from the treeline" % [d, "" if d == 1 else "es"]
		"escort":
			var car = with_status("carter")
			if car == null:
				return ""
			return "Carter — dead" if car.is_dead() else "Carter — %d HP" % car.hp
	return ""
```

Wire the hooks. In `end_turn()`:

```gdscript
func end_turn() -> void:
	var c0 = current()
	c0.has_acted = true
	_repeat_saves(c0, "end_turn")
	_rage_upkeep(c0)
	_objective_touch(c0)
	if c0.has("quarry") and c0.conscious() and c0.pos in objective.get("exit", []):
		_quarry_escape(c0)
	for _i in order.size() + 1:
		turn_idx += 1
		if turn_idx >= order.size():
			turn_idx = 0
			round_num += 1
			_objective_round()
		var c = current()
		if c.is_dead() or c.is_stable():
			continue
		return
```

In `is_over()` and `outcome()`:

```gdscript
func is_over() -> bool:
	return surrendered or round_num > MAX_ROUNDS or _team_out("party") or _team_out("foe") or _objective_over()

func outcome() -> String:
	if _team_out("foe"):
		return "Victory"
	if surrendered or _team_out("party"):
		return "Defeat"
	if _objective_over():
		return "Victory"   # the gate held, the road reached, the quarry down — with foes still standing
	return "ongoing"
```

At the end of `move_to()`, after `_release_grapples()`:

```gdscript
	_objective_touch(mover)
```

In `_kill()`, beside the bystander line added in Task 1:

```gdscript
	if c.has("quarry") and not c.has("escaped"):
		objective_done = true
		log.append("The quarry is down — the rest break and run.")
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: `0 failed`.

Run: `for t in test_combat test_encounter test_fight_invariants test_combat_rules test_coop; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done`
Expected: all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/combat.gd tests/test_objectives.gd
git commit -m "Objectives: the rules of each kind — waves, the deadline, the road, the escape

hold ends itself at the top of round N+1; rescue frees on adjacency and
executes on the deadline; breakout ends when every conscious hero is on
the road; a quarry on the far edge is gone and a quarry down scatters
the rest; the carter dead fails the escort and the fight goes on.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The AI — the quarry runs, and the autopilot tries

**Files:**
- Modify: `core/ai.gd` (`_foe_turn` ~215, `_party_auto` ~281)
- Test: `tests/test_objectives.gd`

**Interfaces:**
- Produces: `AI._quarry_runs(cb, m, pcs) -> bool`, `AI._objective_move(cb, h) -> bool`.
- Consumes: `Combat.objective`, `objective_kind()`, `with_status()`, `heroes()` (Task 1/3); `Objectives.QUARRY_CORNERED`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_objectives.gd` and call from `_init`:

```gdscript
func test_quarry_runs() -> void:
	var spec := {"monsters": [{"id": "snik", "count": 1}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	var cb := _fight(spec, 29)
	var q = cb.with_status("quarry")
	var exit: Array = cb.objective["exit"]
	var far := func(p: Vector2i) -> int:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(p, e))
		return d
	# nobody near (the party starts SPAWN_GAP away, past QUARRY_CORNERED): it runs, and swings at nobody
	for c in cb.combatants:
		if c.team == "party":
			c.speed = 0   # the heroes stay put, so it is the quarry's own choice being tested
	check(_until_turn_of(cb, q), "the quarry's turn")
	var before: int = far.call(q.pos)
	var hp_before: Array = cb.heroes().map(func(h): return h.hp)
	AI.take_turn(cb, q)
	check(far.call(q.pos) < before, "with nobody within %d, the quarry runs for the treeline (%d -> %d)" % [Objectives.QUARRY_CORNERED, before, far.call(q.pos)])
	check(cb.heroes().map(func(h): return h.hp) == hp_before, "...and attacks nobody")
	# a hero on its heels: it fights
	cb = _fight(spec, 29)
	q = cb.with_status("quarry")
	check(_until_turn_of(cb, q), "the quarry's turn again")
	var h = cb.heroes()[0]
	h.pos = Hex.neighbors(q.pos)[0]
	var at: Vector2i = q.pos
	var log_n: int = cb.log.size()
	AI.take_turn(cb, q)
	check(cb.log.size() > log_n and (q.pos == at or Hex.distance(q.pos, h.pos) <= 1),
		"cornered, it stands and fights (%s)" % str(cb.log.slice(log_n)))

func test_autopilot_rules() -> void:
	# rescue: the hero nearest the captive closes on it before anything else
	var cb := _fight(_goblins(1).merged({"objective": Objectives.make("rescue")}), 31)
	var cap = cb.with_status("captive")
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var runner = AI._nearest(cap.pos, cb.heroes())
	check(_until_turn_of(cb, runner), "the runner's turn")
	var d0: int = Hex.distance(runner.pos, cap.pos)
	AI.take_turn(cb, runner)
	check(Hex.distance(runner.pos, cap.pos) < d0, "rescue: the nearest hero moves toward the captive (%d -> %d)" % [d0, Hex.distance(runner.pos, cap.pos)])

	# breakout: heroes head for the road and do not chase
	cb = _fight(_goblins(2).merged({"objective": Objectives.make("breakout")}), 31)
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var exit: Array = cb.objective["exit"]
	var near_exit := func(p: Vector2i) -> int:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(p, e))
		return d
	var h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "a hero's turn")
	var e0: int = near_exit.call(h.pos)
	AI.take_turn(cb, h)
	check(near_exit.call(h.pos) < e0, "breakout: a hero moves toward the road (%d -> %d)" % [e0, near_exit.call(h.pos)])

	# escort: a hero that has drifted comes back to the carter
	cb = _fight(_goblins(1).merged({"objective": Objectives.make("escort")}), 31)
	for f in cb.team_of("foe"):
		f.speed = 0; f.max_hp = 100000; f.hp = 100000
	var car = cb.with_status("carter")
	h = cb.heroes()[0]
	check(_until_turn_of(cb, h), "a hero's turn")
	h.pos = Encounter.far_hexes(cb.board, cb.combatants.map(func(c): return c.pos), 1)[0]
	var c0: int = Hex.distance(h.pos, car.pos)
	AI.take_turn(cb, h)
	check(Hex.distance(h.pos, car.pos) < c0, "escort: a hero more than 2 away closes on the carter (%d -> %d)" % [c0, Hex.distance(h.pos, car.pos)])
```

- [ ] **Step 2: Run to see it fail**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -4`
Expected: the quarry does not run; heroes do not head for the captive/road/carter.

- [ ] **Step 3: Implement in `core/ai.gd`**

Add `const Objectives = preload("res://core/objectives.gd")` beside `const Hex`.

In `_foe_turn()`, the `pcs` filter excludes the captive, and the quarry runs before anything else:

```gdscript
	var pcs: Array = cb.combatants.filter(func(c): return c.team == "party" \
		and c.conscious() and not c.has("illusion") and not c.has("captive"))
	if pcs.is_empty():
		return
	if m.has("quarry") and _quarry_runs(cb, m, pcs):
		return
	_use_kit(cb, m)
```

Add after `_foe_turn()`:

```gdscript
# hunt: the quarry runs for the far edge unless a hero is close enough that
# running is the worse choice — then it fights this turn like anybody else.
# Ending a turn on the edge is the escape (combat.gd's end_turn).
static func _quarry_runs(cb, m, pcs: Array) -> bool:
	if cb.objective_kind() != "hunt" or m.has("escaped"):
		return false
	for c in pcs:
		if Hex.distance(c.pos, m.pos) <= Objectives.QUARRY_CORNERED:
			return false
	var exit: Array = cb.objective.get("exit", [])
	if exit.is_empty():
		return false
	var away := _away(pcs)
	var score := func(h: Vector2i) -> float:
		var d := 1 << 30
		for e in exit:
			d = mini(d, Hex.distance(h, e))
		return -3.0 * float(d) + float(away.call(h))
	_move_by(cb, m, score)
	return true
```

In `_party_auto()`, replace the top through the "close distance" block:

```gdscript
static func _party_auto(cb, h) -> void:
	var foes: Array = cb.enemies_of(h)
	if foes.is_empty():
		return
	_use_kit(cb, h)

	# healer: a downed ally in range comes first
	var heal := _pick(cb, h, func(v): return v.has("heal_count") or v["kind"] == "heal_ally")
	if not heal.is_empty():
		for c in cb.combatants:
			if c.team == h.team and c.is_down() and cb.legal_target(h, heal, c):
				cb.perform(h, heal, c)
				break

	# the objective's one rule for where to stand (spec §7), before any chasing
	var moved := _objective_move(cb, h)

	# close distance if nothing is in reach and we're not a shooter
	var reach: Array = foes.filter(func(c): return cb.in_reach(h, c))
	if reach.is_empty() and not h.ranged and not moved:
		var t = _nearest(h.pos, foes)
		_move_by(cb, h, _toward(t.pos))
		reach = cb.enemies_of(h).filter(func(c): return cb.in_reach(h, c))
```

and replace the targets block near the end:

```gdscript
	var targets: Array = reach if not reach.is_empty() else foes
	if targets.is_empty():
		return
	if cb.objective_kind() == "breakout" and reach.is_empty():
		return   # heading for the road: swing only at what is already in the way
	if cb.objective_kind() == "hunt":
		var q: Array = reach.filter(func(c): return c.has("quarry"))
		if not q.is_empty():
			targets = q
	targets.sort_custom(func(a, b): return a.hp < b.hp)
```

Add after `_party_auto()`:

```gdscript
# One movement preference per kind — not to make the autopilot good, but so
# the sweep in tests/test_objectives.gd measures a party that is trying.
# Returns true if it spent the move, so the caller does not chase as well.
static func _objective_move(cb, h) -> bool:
	match cb.objective_kind():
		"rescue":
			var cap = cb.with_status("captive")
			if cap == null or cap.has("freed") or cap.is_dead():
				return false
			if _nearest(cap.pos, cb.heroes()) != h or Hex.distance(h.pos, cap.pos) <= 1:
				return false
			_move_by(cb, h, _toward(cap.pos))
			return true
		"breakout":
			var exit: Array = cb.objective.get("exit", [])
			if exit.is_empty() or h.pos in exit:
				return false
			var goal: Vector2i = exit[0]
			for e in exit:
				if Hex.distance(h.pos, e) < Hex.distance(h.pos, goal):
					goal = e
			_move_by(cb, h, _toward(goal))
			return true
		"escort":
			var car = cb.with_status("carter")
			if car == null or car.is_dead() or Hex.distance(h.pos, car.pos) <= 2:
				return false
			_move_by(cb, h, _toward(car.pos))
			return true
	return false
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: `0 failed`.

Run: `for t in test_ai test_combat test_scaler test_fight_invariants; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done`
Expected: all `0 failed` — a rout fight never enters `_objective_move` or `_quarry_runs`, so the scaler's pinned rates are untouched.

- [ ] **Step 5: Commit**

```bash
git add core/ai.gd tests/test_objectives.gd
git commit -m "Objectives: the quarry runs, and the autopilot learns one rule per kind

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rewards — the objective row and the deed's XP

**Files:**
- Modify: `core/encounter.gd` (`resolve_outcome` ~531)
- Modify: `core/objectives.gd` (add `spoils_line()`)
- Test: `tests/test_objectives.gd`

**Interfaces:**
- Produces: `result["objective"] = {"kind": String, "done": bool, "xp": int}` on every `resolve_outcome()` (kind `""` for rout). `result["xp"]` includes the bonus. An `escaped` quarry is not in `kills`, pays nothing, drops nothing.
- Produces: `Objectives.spoils_line(o: Dictionary) -> String`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_objectives.gd`, call from `_init`:

```gdscript
func test_rewards() -> void:
	# rout: the row is there and empty
	var cb := _fight(_goblins(1), 37)
	for f in cb.team_of("foe"):
		cb._apply_damage(f, 999)
	var res: Dictionary = Encounter.resolve_outcome(cb, Presets.party())
	check(res["objective"] == {"kind": "", "done": false, "xp": 0}, "rout: an empty objective row")

	# hunt won: the escort's power counts for the bonus though it never died
	var spec := {"monsters": [{"id": "snik", "count": 2}, {"id": "grull", "count": 1}], "theme": "goblin-camp",
		"objective": Objectives.make("hunt")}
	cb = _fight(spec, 37)
	var q = cb.with_status("quarry")
	cb._apply_damage(q, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	var roster := 0.0
	for f in cb.team_of("foe"):
		roster += float(Encounter.Power.estimate(f)["score"])
	var quarry_xp: int = roundi(float(Encounter.Power.estimate(q)["score"]) * Encounter.XP_PER_POWER)
	var bonus: int = roundi(roster * Encounter.XP_PER_POWER * Objectives.BONUS_XP_SHARE)
	check(res["outcome"] == "Victory" and res["objective"]["done"], "the hunt is won")
	check(int(res["objective"]["xp"]) == bonus and bonus > 0, "the bonus is half the whole roster's worth (%d)" % bonus)
	check(int(res["xp"]) == quarry_xp + bonus, "xp = the kill + the bonus (%d = %d + %d)" % [res["xp"], quarry_xp, bonus])
	check(res["kills"] == ["grull"], "only the dead are kills")

	# hunt lost to an escape: no kill, no loot, no bonus for the one that got away
	cb = _fight(spec, 37)
	q = cb.with_status("quarry")
	cb._quarry_escape(q)
	for f in cb.team_of("foe"):
		if f != q:
			cb._apply_damage(f, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	check(res["outcome"] == "Victory" and not res["objective"]["done"] and int(res["objective"]["xp"]) == 0,
		"escort routed, quarry gone: a victory with the objective failed and no bonus")
	check(not res["kills"].has("grull"), "the escaped quarry is not a kill")

	# a dead bystander is not a death
	cb = _fight(_goblins(1).merged({"objective": Objectives.make("escort")}), 37)
	cb._apply_damage(cb.with_status("carter"), 99)
	for f in cb.team_of("foe"):
		cb._apply_damage(f, 999)
	res = Encounter.resolve_outcome(cb, Presets.party())
	check(res["deaths"] == [] and not res["downed"].has("carter"), "the carter is in neither deaths nor downed")
	check(not res["objective"]["done"], "...and the escort failed")

	check(Objectives.spoils_line({"kind": "hunt", "done": true, "xp": 40}) == "Objective — the quarry is down  (+40 XP)", "spoils line, done")
	check(Objectives.spoils_line({"kind": "escort", "done": false, "xp": 0}) == "Objective — the carter is dead", "spoils line, failed")
```

- [ ] **Step 2: Run to see it fail**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3`
Expected: `res["objective"]` missing.

- [ ] **Step 3: Implement**

In `core/encounter.gd`'s `resolve_outcome()`, the foe loop and the return:

```gdscript
	var power := 0.0
	var roster := 0.0
	var loot: Array = []
	var kills: Array[String] = []
	for c in cb.team_of("foe"):
		roster += float(Power.estimate(c)["score"])
		if not c.is_dead() or c.has("escaped"):   # the quarry that got away took its loot with it
			continue
		kills.append(c.src_id)
		power += float(Power.estimate(c)["score"])
		loot.append_array(Catalog.monster(c.src_id).get("loot", []))   # a pack author's explicit drops, always
```

and, after `_score_fight(cb, res == "Victory")`:

```gdscript
	# Spec §4: an objective done pays half the whole roster's worth in XP on
	# top of the kills — dead or standing, because holding against them,
	# slipping past them or dropping their leader is the deed. Gold and loot
	# stay kills-only: a foe you did not kill did not drop anything.
	var done: bool = res == "Victory" and cb.objective_result()
	var bonus: int = roundi(roster * XP_PER_POWER * Objectives.BONUS_XP_SHARE) if done else 0
	return {
		"outcome": "Victory" if res == "Victory" else "Defeat",   # a round-cap timeout is not a win
		"xp": roundi(power * XP_PER_POWER) + bonus,
		"gold": roundi(power * GOLD_PER_POWER),
		"loot": loot,
		"deaths": deaths,
		"kills": kills,   # source monster ids, for T9's kill-count quests
		"downed": cb.downed.keys(),   # T19: party ids that hit 0 HP, even if they got back up
		"rounds": cb.round_num,       # world.gd bills the clock an hour a round
		"objective": {"kind": cb.objective_kind(), "done": done, "xp": bonus},
	}
```

In `core/objectives.gd`:

```gdscript
# The spoils page's row.
static func spoils_line(o: Dictionary) -> String:
	var done := bool(o.get("done", false))
	var text := ""
	match String(o.get("kind", "")):
		"hold": text = "the passage held" if done else "the passage was lost"
		"rescue": text = "the captive is out" if done else "the captive was not saved"
		"breakout": text = "the party got clear" if done else "nobody got clear"
		"hunt": text = "the quarry is down" if done else "the quarry got away"
		"escort": text = "the carter lived" if done else "the carter is dead"
	var xp := int(o.get("xp", 0))
	return "Objective — %s%s" % [text, ("  (+%d XP)" % xp) if done and xp > 0 else ""]
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_encounter test_campaign test_world_spoils test_loot; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/encounter.gd core/objectives.gd tests/test_objectives.gd
git commit -m "Objectives: the deed pays half the roster's worth, and the spoils row

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The sweep — 80 seeds a kind, 40–75% done, tuned by the knob

**Files:**
- Modify: `tests/test_objectives.gd`
- Modify: `core/objectives.gd` (knob values and the measured grid in the header)

**Interfaces:**
- Produces: the measured done-rate grid in `core/objectives.gd`'s header comment.

- [ ] **Step 1: Write the sweep**

Add to `tests/test_objectives.gd`, call from `_init` last (before the summary print):

```gdscript
const SWEEP_SEEDS := 80
const DONE_MIN := 40.0
const DONE_MAX := 75.0

# Spec §8: at normal, the autopilot trying, a kind's done rate must land in
# 40–75%. Tuned ONLY by the kind's own knob in core/objectives.gd — never the
# roster, which is scaler.gd's promise.
func test_sweep() -> void:
	print("  objective sweep, %d seeds a kind at normal:" % SWEEP_SEEDS)
	for kind in Objectives.KINDS:
		var done := 0
		var won := 0
		for s in range(1, SWEEP_SEEDS + 1):
			var chars: Array = Presets.party()
			var spec: Dictionary = Scaler.roster_for(chars, "normal", {}, "", s)
			spec["theme"] = "goblin-camp"
			var extra := {}
			if kind == "hold":
				extra["waves"] = Objectives.waves_for(chars, "", s, 1.0)
			spec["objective"] = Objectives.make(kind, extra)
			var cb := _fight(spec, s)
			_autoplay(cb)
			var res: Dictionary = Encounter.resolve_outcome(cb, chars)
			if res["outcome"] == "Victory":
				won += 1
			if res["objective"]["done"]:
				done += 1
		var rate := 100.0 * done / SWEEP_SEEDS
		print("    %-9s done %2d/%d (%.1f%%)   won %2d/%d" % [kind, done, SWEEP_SEEDS, rate, won, SWEEP_SEEDS])
		check(rate >= DONE_MIN and rate <= DONE_MAX, "%s: done rate %.1f%% is inside %d–%d%%" % [kind, rate, DONE_MIN, DONE_MAX])
```

Add `waves_for()` to `core/objectives.gd` (used by the sweep now and by `site.gd` in Task 8):

```gdscript
# hold's reinforcements: one easy roster per WAVE_ROUNDS entry at WAVE_SCALE of
# its budget, on its own seed. `chars` are Characters (what Scaler wants).
static func waves_for(chars: Array, theme: String, seed: int, power_scale: float, exclude: Array = []) -> Array:
	var Scaler = load("res://core/scaler.gd")   # load: scaler.gd preloads encounter.gd, which preloads this file
	var out: Array = []
	for i in WAVE_ROUNDS.size():
		out.append(Scaler.roster_for(chars, "easy", {}, theme, seed + 17 * (i + 1), power_scale * WAVE_SCALE, exclude)["monsters"])
	return out
```

- [ ] **Step 2: Run it and read the grid**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | grep -A7 "objective sweep"`
Expected: five rate lines. Some will be outside 40–75%.

- [ ] **Step 3: Tune, one knob per kind, until every kind is inside the band**

Only these may move, each in the direction shown, re-running the sweep after each change:

| kind too easy (> 75%) | kind too hard (< 40%) |
|---|---|
| hold: raise `WAVE_SCALE` (0.4 → 0.6 → 0.8), then `HOLD_ROUNDS` (5 → 6) | lower `WAVE_SCALE` (0.4 → 0.3), then `HOLD_ROUNDS` (5 → 4) |
| rescue: lower `RESCUE_DEADLINE` (4 → 3) | raise `RESCUE_DEADLINE` (4 → 5 → 6) |
| breakout: lower `EXIT_W` (4 → 3) — fewer road hexes, a tighter squeeze | raise `EXIT_W` (4 → 6) |
| hunt: lower `QUARRY_CORNERED` (3 → 2) — it runs unless a hero is nearly on it | raise `QUARRY_CORNERED` (3 → 4 → 5) — it stands and fights sooner |
| escort: lower `CARTER_HP_PER_LEVEL` (2 → 1) | raise `CARTER_HP_BASE` (6 → 10), then `CARTER_HP_PER_LEVEL` (2 → 3) |

Do not touch `Scaler`, the roster difficulty in the sweep, or the AI rules.

- [ ] **Step 4: Record the grid in `core/objectives.gd`'s header**

Below the file's opening comment, add the measured table, e.g.:

```gdscript
# Measured (tests/test_objectives.gd test_sweep, 80 seeds a kind, presets at
# level 3, normal roster, autopilot with ai.gd's one rule per kind):
#   hold      done NN/80 (NN.N%)   won NN/80
#   rescue    done NN/80 (NN.N%)   won NN/80
#   breakout  done NN/80 (NN.N%)   won NN/80
#   hunt      done NN/80 (NN.N%)   won NN/80
#   escort    done NN/80 (NN.N%)   won NN/80
# The band is 40–75%: an objective nearly free is a modifier, one nearly
# impossible is a trap. Tuned by the knobs below and never by the roster.
```

with the real numbers.

- [ ] **Step 5: Run the whole file once more, then the guard suites**

Run: `godot --headless --path . -s tests/test_objectives.gd 2>&1 | tail -8` → `0 failed`.
Run: `for t in test_scaler test_site test_coop; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add core/objectives.gd tests/test_objectives.gd
git commit -m "Objectives: the sweep — 80 seeds a kind, each inside 40–75% done

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The combat screen — starts, the HUD line, the road, the bystander token

**Files:**
- Modify: `scenes/main.gd` (`_new_game` ~495; `_refresh` ~1757; `_deploy_menu` ~579; `deploy_swappable` ~646; `Board._draw` ~3363 tile loop and ~3430 token base; colour consts ~155)
- Modify: `core/ui_icons.gd` (`combatant_glyph` ~ line found by `grep -n "static func combatant_glyph"`)
- Create: `tests/test_objectives_ui.gd`

**Interfaces:**
- Consumes: `Encounter.starts_for()`, `Combat.objective`, `objective_line()`, statuses `bystander`.
- Produces: `main.COL_EXIT`, `main.COL_BYSTANDER`; `Icons.combatant_glyph(c)` returns `"⚑"` for a bystander.

- [ ] **Step 1: Write the failing test**

Create `tests/test_objectives_ui.gd`:

```gdscript
# The combat screen with an objective on the spec: the party starts where the
# objective says, the header carries the objective's line, the road is known
# to the board, and a bystander is drawn but never offered as a hero.
#   godot --headless --path . -s tests/test_objectives_ui.gd
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Objectives = preload("res://core/objectives.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _open(spec: Dictionary):
	var main = load("res://scenes/main.tscn").instantiate()
	main.spec = spec
	root.add_child(main)
	for i in 20:
		await process_frame
	return main

func _init() -> void:
	OS.set_environment("SORCMERC_SEED", "7")
	var main = await _open({"monsters": [{"id": "snik", "count": 4}], "theme": "goblin-camp",
		"objective": Objectives.make("breakout")})
	check(main.cb.objective_kind() == "breakout", "the objective reached the fight")
	check("Road — " in main._header.text, "the header carries the objective line: %s" % main._header.text)
	var board: Dictionary = main.cb.board
	var mids: Array = Encounter.middle_starts(board, 7)
	check(main.cb.heroes().all(func(h): return h.pos in mids), "a breakout's party stands in the middle")
	check(main.cb.log.has(Objectives.brief(main.cb.objective)), "the brief is the fight's first line")
	check(main.COL_EXIT.a > 0.0 and main.COL_BYSTANDER.a > 0.0, "the road and the bystander have colours")
	main.queue_free()
	await process_frame

	main = await _open({"monsters": [{"id": "snik", "count": 2}], "theme": "goblin-camp",
		"objective": Objectives.make("escort")})
	var car = main.cb.with_status("carter")
	check(car != null and not main.cb.order.has(car), "the carter is on the board and off the order strip")
	check(Icons.combatant_glyph(car) == "⚑", "a bystander's token mark is the flag")
	check(not main.deploy_swappable(car), "the deploy phase never offers the carter")
	check("Carter — " in main._header.text, "escort's line: %s" % main._header.text)
	main.queue_free()
	await process_frame

	main = await _open({"monsters": [{"id": "snik", "count": 2}], "theme": "goblin-camp"})
	check(main.cb.objective.is_empty(), "rout: no objective")
	check(not ("Road" in main._header.text or "Carter" in main._header.text or "Hold" in main._header.text),
		"rout: the header has no objective line: %s" % main._header.text)
	print("test_objectives_ui: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run to see it fail**

Run: `SORCMERC_FAST=1 godot --headless --path . -s tests/test_objectives_ui.gd 2>&1 | tail -4`
Expected: `COL_EXIT` not found; the header lacks the line; the party stands at the edge.

- [ ] **Step 3: Implement in `scenes/main.gd`**

Colour constants, beside `COL_MOVE`:

```gdscript
const COL_EXIT := Color(0.85, 0.72, 0.30, 0.32)      # objectives: the road out / the treeline
const COL_BYSTANDER := Color("d8cfae")               # objectives: a captive's or carter's token
```

In `_new_game()`, the build line becomes:

```gdscript
	cb = Encounter.build(sp, party.to_combatants(Encounter.starts_for(sp, board, _seed)), board)   # #114; objectives pick the starts
```

In `_refresh()`, after the co-op room line:

```gdscript
	if not cb.objective.is_empty():
		_header.text += "  ·  " + cb.objective_line()
```

In `_deploy_menu()`:

```gdscript
	var heroes: Array = cb.heroes()
```

In `deploy_swappable()`:

```gdscript
func deploy_swappable(c) -> bool:
	return _mode == "deploy" and c != null and c.team == "party" and c.conscious() and not c.has("bystander")
```

In `Board._draw()`, before the tile loop (`for hx in cb.board["hexes"]:`), read the road:

```gdscript
		# objectives: the road out of a breakout, the treeline a quarry runs for
		var road := {}
		for e in cb.objective.get("exit", []):
			road[e] = true
```

and inside the loop, right after the `field.has(hx)` line:

```gdscript
			if road.has(hx):
				draw_colored_polygon(poly, main.COL_EXIT)
```

In the token loop, after `var base: Color = main.COL_PARTY if c.team == "party" else main.COL_FOE`:

```gdscript
			if c.has("bystander"):
				base = main.COL_BYSTANDER
```

In `core/ui_icons.gd`, `combatant_glyph()`:

```gdscript
static func combatant_glyph(c) -> String:
	if c.has("bystander"):
		return "⚑"   # objectives: a captive, a carter — somebody the fight is about
	if c.sheet != null:
		return class_glyph(primary_class(c.sheet))
	var mtype := String(Catalog.monster(c.src_id).get("type", ""))
	return String(FOE_GLYPHS.get(mtype, "➶" if c.ranged else "⚔"))
```

- [ ] **Step 4: Run the UI test and the screen suites**

Run: `SORCMERC_FAST=1 godot --headless --path . -s tests/test_objectives_ui.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_hud_layer test_action_bar test_order_aim test_summons test_coop; do SORCMERC_FAST=1 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.
Run: `SORCMERC_FAST=1 godot --headless --path . -s tests/drive_ui.gd 2>&1 | tail -1` → passes.

- [ ] **Step 5: Commit**

```bash
git add scenes/main.gd core/ui_icons.gd tests/test_objectives_ui.gd
git commit -m "Objectives on the combat screen: the starts, the header line, the road, the bystander token

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Sites — the gate and the pens

**Files:**
- Modify: `core/site.gd` (`COMBAT_ROOMS` ~96; `combat_spec()` ~314; new static `pens_ahead()`)
- Test: `tests/test_site.gd`

**Interfaces:**
- Produces: two `COMBAT_ROOMS` entries with an `"objective"` key (`"hold"` on `gate`, `"rescue"` on `pens`); `Site.pens_ahead(lair) -> bool`; `combat_spec()` sets `spec["objective"]` for those rooms.
- Consumes: `Objectives.make()`, `Objectives.waves_for()`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_site.gd` (a new function, called from `_init` before the summary print — find the line `print("test_site: ...` and call `test_objective_rooms()` above it):

```gdscript
# Objectives: a gate room holds, a pens room rescues, and a rescue job can only
# be posted about a lair whose pens the party has not yet fought past.
func test_objective_rooms() -> void:
	var Objectives = load("res://core/objectives.gd")
	var ids: Array = Site.COMBAT_ROOMS.map(func(r): return String(r["id"]))
	check(ids.has("gate") and ids.has("pens"), "the gate and the pens are combat rooms")
	# find a lair id whose interior has a pens room, and one whose has not
	var with_pens = null
	var without = null
	for i in 400:
		var l = World.Lair.new("warren-%d" % i, Vector2(100, 100), "goblinoid")
		if Site.pens_ahead(l):
			if with_pens == null: with_pens = l
		elif without == null:
			without = l
		if with_pens != null and without != null:
			break
	check(with_pens != null and without != null, "some lairs hold captives and some do not")
	var w := _world()
	var p := _party()
	var s = Site.for_lair(with_pens, p, w)
	var pens := {}
	var gate := {}
	for depth in s.rooms:
		for r in depth:
			if String(r.get("objective", "")) == "rescue": pens = r
			if String(r.get("objective", "")) == "hold": gate = r
	check(not pens.is_empty(), "the pens are in there")
	s.room = pens
	s.state = "combat"
	var spec: Dictionary = s.combat_spec()
	check(spec.get("objective", {}).get("kind", "") == "rescue", "the pens room's spec carries a rescue")
	if not gate.is_empty():
		s.room = gate
		spec = s.combat_spec()
		check(spec["objective"]["kind"] == "hold" and spec["objective"]["waves"].size() == Objectives.WAVE_ROUNDS.size(),
			"the gate's spec carries a hold with one wave per wave round")
	# fought past: a lair whose pens are behind the party no longer qualifies
	var deep: int = 0
	for d in s.rooms.size():
		if s.rooms[d].has(pens):
			deep = d
	with_pens.depth_cleared = deep + 1
	check(not Site.pens_ahead(with_pens), "pens the party has fought past do not count")
	with_pens.depth_cleared = 0
```

- [ ] **Step 2: Run to see it fail**

Run: `godot --headless --path . -s tests/test_site.gd 2>&1 | tail -3`
Expected: `pens_ahead` not found / rooms missing.

- [ ] **Step 3: Implement in `core/site.gd`**

Add `const Objectives = preload("res://core/objectives.gd")` beside the other preloads. Two rooms at the end of `COMBAT_ROOMS`:

```gdscript
	# Objectives (core/objectives.gd): the room asks a different question.
	{"id": "gate", "title": "The gate", "difficulty": "normal", "objective": "hold",
		"desc": "Hold the passage while the way behind is barred. More of them will come from the far side."},
	{"id": "pens", "title": "The pens", "difficulty": "normal", "objective": "rescue",
		"desc": "Somebody is chained at the back, and their keepers know exactly how long you will take to reach them."},
```

In `combat_spec()`, before `spec["theme"] = ...`:

```gdscript
	# Objectives: the gate holds against waves drawn from the same faction at
	# WAVE_SCALE of an easy roster; the pens hold a captive on a deadline.
	match String(room.get("objective", "")):
		"hold":
			spec["objective"] = Objectives.make("hold", {"waves": Objectives.waves_for(
				party.party_characters(), theme, seed_v, band, _boss_lead_exclusion())})
		"rescue":
			spec["objective"] = Objectives.make("rescue")
```

After `depth_for()`:

```gdscript
# Whether a rescue job about this lair can still be done: a pens room at a
# depth the party has not yet fought past. core/quest_posting.gd asks before
# posting, so a job is only ever posted about captives that are actually
# reachable. Same seed as for_lair(), so it is the same interior.
static func pens_ahead(lair) -> bool:
	var rooms: Array = _build(lair, RNG.new(maxi(1, absi(hash("site|%s" % lair.id)))))
	for d in range(int(lair.depth_cleared), rooms.size()):
		for r in rooms[d]:
			if String(r.get("objective", "")) == "rescue":
				return true
	return false
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --path . -s tests/test_site.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_site_screen test_lair_kit test_world_lairs test_lair_respawn; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/site.gd tests/test_site.gd
git commit -m "Sites: the gate holds, the pens hold a captive

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Quests — the rescue job, and a delivery that can be lost

**Files:**
- Modify: `core/quest.gd` (`KINDS`/`TARGET_FIELD` ~39; new `record_rescued()`, `fail_deliveries()` beside `record_lair_cleared` ~271)
- Modify: `core/quest_posting.gd` (`PLACEMENT` ~60; `_build` ~182; `_target_position` ~221; new `rescue_offer()` beside `deliver_offer` ~291)
- Test: `tests/test_quest.gd`, `tests/test_quest_posting.gd`

**Interfaces:**
- Produces: kind `"rescue"` with `target_lair_id`; `Quest.record_rescued(party, lair_id)`; `Quest.fail_deliveries(party) -> Array` (titles of the deliveries removed); `Posting.rescue_offer(s, world, party) -> Dictionary`; `Posting.PLACEMENT["rescue"]`.
- Consumes: `Site.pens_ahead()` via `load()`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_quest.gd` (call from `_init`):

```gdscript
func test_rescue_and_failed_delivery() -> void:
	check(Quest.KINDS.has("rescue") and Quest.TARGET_FIELD["rescue"] == "target_lair_id", "rescue is a kind that names a lair")
	var p := _party()
	Quest.accept(p, {"id": "rescue:t:warren", "kind": "rescue", "state": "offered", "target_lair_id": "warren",
		"required": 1, "progress": 0, "title": "Bring back the miller's boy from the warren", "reward": {"gold": 90}})
	Quest.record_rescued(p, "other-lair")
	check(Quest.get_quest(p, "rescue:t:warren")["state"] == "active", "a rescue elsewhere is not this one")
	Quest.record_rescued(p, "warren")
	check(Quest.get_quest(p, "rescue:t:warren")["state"] == "complete", "the captive out of that lair completes the job")

	Quest.accept(p, {"id": "deliver:a:b", "kind": "deliver_goods", "state": "offered", "target_settlement_id": "b",
		"required": 1, "progress": 0, "title": "Run a crate of goods to B", "reward": {"gold": 40}})
	Quest.accept(p, {"id": "look-out-2", "kind": "scout_region", "state": "offered", "target_region_id": "deeps",
		"required": 1, "progress": 0, "title": "Scout", "reward": {"gold": 60}})
	var lost: Array = Quest.fail_deliveries(p)
	check(lost == ["Run a crate of goods to B"], "the delivery is the one that fails: %s" % str(lost))
	check(Quest.get_quest(p, "deliver:a:b").is_empty(), "...and it is gone from the log, so the board can post it again")
	check(Quest.get_quest(p, "look-out-2")["state"] == "active", "the scouting job is untouched")
	check(Quest.fail_deliveries(p) == [], "nothing to fail twice")
```

Add to `tests/test_quest_posting.gd` (call from `_init`):

```gdscript
func test_rescue_offer() -> void:
	var Site = load("res://core/site.gd")
	var w := _world()
	var p := _party()
	# a lair with captives in it, near the city, and a spent one beside it
	var held = null
	for i in 400:
		var l = World.Lair.new("pens-%d" % i, Vector2(120, 60), "goblinoid")
		if Site.pens_ahead(l):
			held = l
			break
	check(held != null, "a lair with pens exists")
	w.add_lair(held)
	var city = w.settlements[0]
	var q: Dictionary = Posting.rescue_offer(city, w, p)
	check(q["kind"] == "rescue" and q["target_lair_id"] == held.id and q["title"].begins_with("Bring back "),
		"the city posts a rescue about it: %s" % q.get("title", ""))
	check(int(q["reward"]["gold"]) >= Posting.RESCUE_BASE, "...that pays at least the base")
	check(_kinds(_at(city, p, w)).has("rescue"), "...on its board")
	held.looted = true
	check(Posting.rescue_offer(city, w, p).is_empty(), "a spent lair holds nobody")
	held.looted = false
	held.position = Vector2(0, Posting.PLACEMENT["rescue"]["reach"] + 50.0)
	check(Posting.rescue_offer(city, w, p).is_empty(), "out of reach, out of mind")
```

- [ ] **Step 2: Run to see them fail**

Run: `godot --headless --path . -s tests/test_quest.gd 2>&1 | tail -2; godot --headless --path . -s tests/test_quest_posting.gd 2>&1 | tail -2`
Expected: `rescue` missing; `test_kinds_are_declared_once` will also fail the moment `KINDS` gains `rescue` without a `PLACEMENT` rule — both land in this task.

- [ ] **Step 3: Implement in `core/quest.gd`**

```gdscript
const KINDS := ["kill_count", "collect_item", "hunt_party", "raid_settlement",
	"clear_lair", "supply_item", "deliver_goods", "scout_region", "rescue"]
const TARGET_FIELD := {
	"kill_count": "target_monster_id", "collect_item": "target_monster_id",
	"hunt_party": "target_party_id", "raid_settlement": "target_settlement_id",
	"clear_lair": "target_lair_id", "supply_item": "target_item_id",
	"deliver_goods": "target_settlement_id", "scout_region": "target_region_id",
	"rescue": "target_lair_id",
}
```

After `record_lair_cleared()`:

```gdscript
# rescue — somebody chained in a lair's pens (core/site.gd's pens room, an
# objective in core/objectives.gd). Completes when the rescue objective is done
# in that lair; scenes/world/world.gd calls this off the fight's result.
static func record_rescued(party, lair_id: String) -> void:
	_complete_world_target(party, "rescue", "target_lair_id", lair_id)

# The carter is dead (the escort objective failed), or the party was beaten with
# the crate on the road: every live delivery is lost. Removed from the log rather
# than marked, so the board can post the run again. Returns the titles, for the
# spoils page.
static func fail_deliveries(party) -> Array:
	var lost: Array = []
	for q in party.quests.duplicate():
		if q["kind"] == "deliver_goods" and q["state"] == "active":
			lost.append(String(q["title"]))
			party.quests.erase(q)
	return lost
```

- [ ] **Step 4: Implement in `core/quest_posting.gd`**

In `PLACEMENT`, after `clear_lair`:

```gdscript
	# Somebody taken to a lair down the valley: the innkeeper hears it first,
	# the generalist where there is no inn.
	"rescue": {"counters": ["innkeeper", "generalist"], "kinds": [], "reach": 800.0},
```

In `_build()`'s match:

```gdscript
		"rescue":
			var q: Dictionary = rescue_offer(s, world, party)
			return [q] if not q.is_empty() else []
```

In `_target_position()`, make the lair branch cover both kinds:

```gdscript
		"clear_lair", "rescue":
```

After `deliver_offer()`:

```gdscript
const RESCUE_BASE := 90
const RESCUE_PER_UNIT := 8.0      # map units of road per extra gold piece
const CAPTIVES := ["the miller's boy", "a carter's daughter", "the reeve's clerk",
	"a pedlar off the north road", "two charcoal-burners"]

# Somebody was taken to a lair near here and is still alive in it: the nearest
# unlooted lair with a pens room the party has not yet fought past
# (core/site.gd's pens_ahead — a job is only posted when it can still be done).
# `party` is unused for now and kept so the signature matches the other offers.
static func rescue_offer(s, world, _party) -> Dictionary:
	if world == null:
		return {}
	var Site = load("res://core/site.gd")   # load: site.gd preloads settlement_visit.gd, which preloads this file
	var reach: float = float(PLACEMENT["rescue"]["reach"])
	var best = null
	var best_d := INF
	for l in world.lairs:
		var d: float = s.position.distance_to(l.position)
		if l.looted or d > reach or d >= best_d or not Site.pens_ahead(l):
			continue
		best = l
		best_d = d
	if best == null:
		return {}
	var who: String = CAPTIVES[absi(hash("%s|%s" % [s.id, best.id])) % CAPTIVES.size()]
	return {
		"id": "rescue:%s:%s" % [s.id, best.id],
		"giver_node_id": s.id, "kind": "rescue", "state": "offered",
		"target_lair_id": best.id, "required": 1, "progress": 0,
		"title": "Bring back %s from %s" % [who, best.sname],
		"reward": {"gold": RESCUE_BASE + int(best_d / RESCUE_PER_UNIT)},
	}
```

- [ ] **Step 5: Run the tests**

Run: `for t in test_quest test_quest_posting test_world_panels test_mod_packs test_story; do godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed` (`test_story` / `test_mod_packs` validate quest kinds in packs; an added kind must not break them).

- [ ] **Step 6: Commit**

```bash
git add core/quest.gd core/quest_posting.gd tests/test_quest.gd tests/test_quest_posting.gd
git commit -m "Quests: a rescue job about a lair with captives, and a delivery that can be lost

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The world — one source per kind, and what comes back

**Files:**
- Modify: `scenes/world/world.gd` (`encounter_spec` ~1329; `_launch_combat` ~1398; `_show_spoils` ~1486; `_on_site_room_chosen` ~1956; `_open_approach` ~2080; `_take_quest` ~2760; preloads at the top)
- Modify: `tests/drive_random.gd` (`_watch()` ~261)
- Create: `tests/test_world_objectives.gd`

**Interfaces:**
- Produces: `world._road_objective(foe, forced_ambush: bool) -> Dictionary`, `world.encounter_spec(foe, difficulty := "")`.
- Consumes: `Objectives.make/title/spoils_line`, `Quest.record_rescued/fail_deliveries`, `WorldAI.truce`, `result["objective"]`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_world_objectives.gd`:

```gdscript
# Objectives on the map: a delivery makes the road fight an escort, a hunt job
# makes the band a hunt, a jumped camp is a breakout; and what comes back —
# the chief that got away keeps the band and the job, the dead carter loses
# the crate, the spoils page says what the objective came to.
#   godot --headless --path . -s tests/test_world_objectives.gd
extends SceneTree
const World = preload("res://core/world.gd")
const Quest = preload("res://core/quest.gd")
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

func _open_fight(main, foe, forced_ambush := false) -> bool:
	main._launch_combat(foe, false, forced_ambush)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	return main._combat != null

func _finish(main, result: Dictionary) -> void:
	main._combat.result = result
	for i in 8:
		await process_frame

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var p = main.world.player()

	# --- escort: a delivery on the road, and the carter dies ---------------
	Quest.accept(main.party, {"id": "deliver:t:x", "kind": "deliver_goods", "state": "offered",
		"target_settlement_id": "x", "required": 1, "progress": 0,
		"title": "Run a crate of goods to X", "reward": {"gold": 40}})
	var foe = World.RoamingParty.new("bandits-a", p.position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe)
	check(await _open_fight(main, foe), "the fight opened")
	check(main._combat.spec.get("objective", {}).get("kind", "") == "escort", "with a delivery on the road, the fight is an escort")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "escort", "done": false, "xp": 0}})
	check(Quest.get_quest(main.party, "deliver:t:x").is_empty(), "the carter dead, the delivery is lost")
	check(main._spoils_panel != null and said(main._spoils_panel, "carter is dead"), "the spoils page says so")
	check(said(main._spoils_panel, "delivery"), "...and names the lost job")
	main._close_spoils()
	await process_frame

	# --- hunt: the band a job names; its chief gets away ---------------------
	var foe2 = World.RoamingParty.new("raiders-b", main.world.player().position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe2)
	Quest.accept(main.party, {"id": "world:hunt_party:raiders-b:0", "kind": "hunt_party", "state": "offered",
		"target_party_id": "raiders-b", "required": 1, "progress": 0,
		"title": "Hunt down the raiders-b band", "reward": {"gold": 100}, "chain_faction": "bandit", "chain_tier": 0})
	check(await _open_fight(main, foe2), "the second fight opened")
	check(main._combat.spec["objective"]["kind"] == "hunt", "a band a job names is a hunt")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "hunt", "done": false, "xp": 0}})
	check(main.world.parties.has(foe2), "the chief got away: the band stays on the map")
	check(main._slipped.get(foe2.id, false), "...marked slipped, so the card does not reopen at once")
	check(Quest.get_quest(main.party, "world:hunt_party:raiders-b:0")["state"] == "active", "...and the job stays open")
	check(said(main._spoils_panel, "quarry got away"), "the spoils page says so")
	main._close_spoils()
	await process_frame

	# ...and then does not
	main._slipped.erase(foe2.id)
	check(await _open_fight(main, foe2), "the rematch opened")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "hunt", "done": true, "xp": 15}})
	check(not main.world.parties.has(foe2), "the quarry down: the band is gone")
	check(Quest.get_quest(main.party, "world:hunt_party:raiders-b:0")["state"] == "complete", "...and the job is done")
	check(said(main._spoils_panel, "+15 XP"), "the bonus is shown as its own number")
	main._close_spoils()
	await process_frame

	# --- breakout: a jumped camp ---------------------------------------------
	var foe3 = World.RoamingParty.new("camp-ambush-t", main.world.player().position, "bandit")
	check(await _open_fight(main, foe3, true), "the ambush opened")
	check(main._combat.spec["objective"]["kind"] == "breakout", "a failed watch is a breakout")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "breakout", "done": true, "xp": 20}})
	check(said(main._spoils_panel, "party got clear"), "the spoils page says so")
	main._close_spoils()
	await process_frame

	# --- rout: nothing on the spec, nothing on the page -----------------------
	var foe4 = World.RoamingParty.new("bandits-d", main.world.player().position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe4)
	check(await _open_fight(main, foe4), "a plain fight opened")
	check(not main._combat.spec.has("objective"), "no job, no delivery, no ambush: no objective")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "", "done": false, "xp": 0}})
	check(not said(main._spoils_panel, "Objective"), "no objective row for a rout")
	main._close_spoils()

	print("test_world_objectives: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run to see it fail**

Run: `SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_objectives.gd 2>&1 | tail -6`
Expected: the spec carries no objective; the delivery survives; the band is erased.

- [ ] **Step 3: Implement in `scenes/world/world.gd`**

Add `const Objectives = preload("res://core/objectives.gd")` beside the other preloads at the top of the file.

`encounter_spec()` takes an override — the signature and the `roster_for` call become:

```gdscript
func encounter_spec(foe, difficulty := "") -> Dictionary:
	...
	var spec: Dictionary = Scaler.roster_for(
		party.party_characters(), difficulty if difficulty != "" else String(threat["difficulty"]),
		{}, theme, seed_v,
		float(threat["power_scale"]) * Regions.power_scale(world, foe.position, party))
```

(everything else in the function is unchanged).

Add before `_launch_combat()`:

```gdscript
# The objective a road fight carries, by precedence: jumped at camp is a
# breakout whatever else is going on; a band a job names is a hunt; a delivery
# on the road makes every fight an escort. {} is today's fight.
func _road_objective(foe, forced_ambush: bool) -> Dictionary:
	if forced_ambush:
		return Objectives.make("breakout")
	for q in party.quests:
		if q["state"] == "active" and q["kind"] == "hunt_party" and String(q.get("target_party_id", "")) == foe.id:
			return Objectives.make("hunt")
	for q in party.quests:
		if q["state"] == "active" and q["kind"] == "deliver_goods":
			return Objectives.make("escort")
	return {}
```

`_launch_combat()` becomes:

```gdscript
func _launch_combat(foe, scouted_ahead := false, forced_ambush := false) -> Dictionary:
	if party.scouted_next:   # Potion of Clairvoyance, spent on this fight
		scouted_ahead = true
		party.scouted_next = false
	var threat: Dictionary = WorldThreat.assess(party)
	var objective: Dictionary = _road_objective(foe, forced_ambush)
	var kind := String(objective.get("kind", ""))
	# A breakout is a fight you are not meant to win by standing: the roster is
	# the tier's hard one whatever the party's condition.
	var spec: Dictionary = encounter_spec(foe, "hard" if kind == "breakout" else "")
	if kind != "":
		spec["objective"] = objective
	var result: Dictionary = await _run_combat(spec,
		String(threat["difficulty"]), scouted_ahead, forced_ambush)
	if result.is_empty():
		return {}
	var obj: Dictionary = result.get("objective", {})
	var got_away: bool = String(obj.get("kind", "")) == "hunt" and not bool(obj.get("done", false))
	if String(result.get("outcome", "")) == "Victory":
		_bank(result)
		if got_away:
			# The band is beaten but its chief is not: it stays on the map, breaks
			# off a day's march, and the job that named it stays open.
			_slipped[foe.id] = true
			WorldAI.truce(foe, world.player(), world.clock.elapsed)
			_quest_news.append("Their leader got away — the job is still open.")
		else:
			world.parties.erase(foe)      # beaten; O5 will do the same for NPC-vs-NPC
			# T91: a no-op for the settlement-guard/lair-raid stand-ins below (their
			# synthetic ids never match a live hunt_party quest's target), correct
			# for an actual hostile roaming party from _check_encounter.
			Quest.record_party_defeated(party, foe.id)
		# O7 raise/lower event: putting down a monster band is a favour to whoever
		# lives near the bodies; putting down a faction's own band is not.
		if WorldAI.is_monster(foe.faction):
			FactionOpinion.credit_fight(world, foe.position, FactionOpinion.FOUGHT_FOR, foe.faction)
		else:
			FactionOpinion.lower(foe.faction, FactionOpinion.KILLED_THEIRS)
	else:
		_retreat()
		# The band that beat them is still where the fight was. Left un-slipped
		# it would ask "fight/parley/ambush?" again the frame the map came back
		# whenever the nearest settlement was inside its trigger radius — the
		# same card the beaten party had just answered.
		_slipped[foe.id] = true
	# The carter dead, or the party beaten with the crate on the road: the
	# delivery is lost either way, and the board can post the run again.
	if String(obj.get("kind", "")) == "escort" and not bool(obj.get("done", false)):
		for title in Quest.fail_deliveries(party):
			_quest_news.append("%s — the delivery is lost with the carter." % title)
	_apply_deaths(result)
	world.clock.resume()
	_autosave()   # O13 autosave: a fight is the biggest thing that
	                               # happens to a run — never re-fight it after a crash
	_show_spoils(result)
	return result
```

In `_show_spoils()`, after the loot rows (before `for line in _quest_news:`):

```gdscript
	var obj: Dictionary = result.get("objective", {})
	if String(obj.get("kind", "")) != "":
		rows.append([Objectives.spoils_line(obj), Icons.COL_GOLD if bool(obj.get("done", false)) else Icons.COL_FOE])
```

In `_on_site_room_chosen()`, right after `_site.finish_combat(result)`:

```gdscript
		var obj: Dictionary = result.get("objective", {})
		if String(obj.get("kind", "")) == "rescue" and bool(obj.get("done", false)):
			Quest.record_rescued(party, _site.lair.id)
			var line := "The captive is out of %s." % _site.lair.sname
			_site.say(line)
			if not _delve_haul.is_empty():
				(_delve_haul["quests"] as Array).append(line)
```

In `_open_approach()`, the label carries the objective's title:

```gdscript
	var kind := String(_road_objective(foe, false).get("kind", ""))
	_approach_card.show_approach(Approach.options(party, foe, hostile),
		"%s (%d)%s" % [foe.id.capitalize(), foe.troops.size(), ("  ·  " + Objectives.title(kind)) if kind != "" else ""])
```

In `_take_quest()`, the discovery note covers both lair kinds:

```gdscript
	if String(q["kind"]) in ["clear_lair", "rescue"]:
```

In `tests/drive_random.gd`'s `_watch()`, after the `fighting` lines:

```gdscript
	# Objectives: a bystander (a captive, a carter) is never given a turn.
	if fighting and screen._combat.cb != null and not screen._combat.cb.order.is_empty():
		var cur = screen._combat.cb.current()
		if cur != null and cur.has("bystander"):
			fail("a bystander (%s) was given a turn" % cur.cname)
```

- [ ] **Step 4: Run the tests**

Run: `SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_objectives.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_world_spoils test_world_camp_integration test_approach_card test_world_defeat test_world_panels test_site_screen; do SORCMERC_FAST=1 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.
Run: `SORCMERC_FAST=1 SORCMERC_SEED=5 godot --headless --path . -s tests/drive_random.gd 2>&1 | tail -2` → passes.
Run: `SORCMERC_FAST=1 SORCMERC_SEED=5 godot --headless --path . -s tests/drive_world.gd 2>&1 | tail -1` → passes.

- [ ] **Step 5: Commit**

```bash
git add scenes/world/world.gd tests/test_world_objectives.gd tests/drive_random.gd
git commit -m "Objectives on the map: a delivery is an escort, a hunt job is a hunt, a jumped camp is a breakout

The chief that got away keeps the band on the map and the job open; a
dead carter loses the crate; the pens' captive completes a rescue job;
the spoils page carries the objective's row.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Co-op — the same objective on both peers

**Files:**
- Modify: `tests/test_coop.gd` (`build()` ~53; `lockstep_fight()` ~69; `_init` ~32)

**Interfaces:**
- Consumes: `Encounter.starts_for()`, `Objectives.make/waves_for`.
- Nothing in `core/coop.gd` or `scenes/main.gd`'s co-op path should need to change: the objective is a key on the spec `Coop.setup_for()` already sends, and both peers build the fight with the same `Encounter.build()`.

- [ ] **Step 1: Extend the lockstep test**

In `tests/test_coop.gd`, `build()` uses the objective-aware starts:

```gdscript
	var cb = Encounter.build(sp, party.to_combatants(Encounter.starts_for(sp, board, sd)), board)
```

`lockstep_fight()` takes an objective:

```gdscript
func lockstep_fight(sd: int, prompted := false, objective: Dictionary = {}) -> void:
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var spec: Dictionary = Scaler.roster_for(party.party_characters(), "normal")
	spec["seed"] = sd
	if not objective.is_empty():
		spec["objective"] = objective
```

and, at the end of the fight loop, one more check when an objective was set:

```gdscript
	if not objective.is_empty():
		check(Coop.state_hash(host) == Coop.state_hash(guest) and host.objective_done == guest.objective_done \
			and host.objective_failed == guest.objective_failed,
			"seed %d: a %s ends the same way on both peers" % [sd, objective["kind"]])
```

In `_init()`, after the prompted loop:

```gdscript
	# Objectives ride the spec: both peers place the same captive, roll the
	# same waves, and watch the same quarry run.
	var Objectives = load("res://core/objectives.gd")
	var chars: Array = Presets.party()
	var i := 0
	for kind in Objectives.KINDS:
		var extra := {}
		if kind == "hold":
			extra["waves"] = Objectives.waves_for(chars, "", 40 + i, 1.0)
		lockstep_fight(40 + i, false, Objectives.make(kind, extra))
		i += 1
```

- [ ] **Step 2: Run it**

Run: `godot --headless --path . -s tests/test_coop.gd 2>&1 | tail -3`
Expected: `0 failed`. If a kind drifts, the divergence is in something rolled outside the fight's `rng` or ordered by a `Dictionary`/hash iteration — look at `_spawn_wave` (must use `cb.rng` via `_join_order`) and `far_hexes` (must sort).

- [ ] **Step 3: Commit**

```bash
git add tests/test_coop.gd
git commit -m "Co-op: an objective on the spec plays out the same on both peers

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: The record, the whole suite, the PR

**Files:**
- Modify: `docs/expansion-plan.md` (append a section)

- [ ] **Step 1: Append the shipped record to `docs/expansion-plan.md`**

At the end of the file:

```markdown
## Objectives — the same fight, asked a different question (2026-09-20)

Sub-project 1 of the content batch (objectives → landmarks → threat clocks and
reclaiming → faction ladder and renown → callings with party relations →
downtime → the lodge). Spec: `docs/superpowers/specs/2026-09-20-encounter-objectives-design.md`;
plan: `docs/superpowers/plans/2026-09-20-encounter-objectives.md`.

Every fight was "kill everyone". Five objectives now ride the encounter spec
(`spec["objective"] = {kind, ...}`, absent = the fight as it was) and change
what the fight is for on the same board, roster, AI and dice: **hold** (the
top of round N+1 with anyone standing is a win; waves from the far side),
**rescue** (a bound captive at the deepest hex; adjacency frees it; the
captors kill it on the deadline; foes never target it), **breakout** (the
party in the middle, foes both ends, every conscious hero on the far-edge
road ends it), **hunt** (the roster's strongest is the quarry; it runs for the
treeline unless a hero is within QUARRY_CORNERED; on the edge it is gone; down,
the rest scatter), **escort** (a carter in the huddle; the AI already hits the
weakest adjacent target, so the puzzle is body-blocking). Outcomes stay
two-valued: "Victory, objective failed" is a real spoils row.

One reward rule: an objective done pays half the whole roster's worth in XP on
top of the kills — the batch's "XP for deeds" rule in its first form. Gold and
loot stay kills-only; an escaped quarry drops nothing.

One world source per kind, so all five are reachable from this PR: the *gate*
site room (hold), the *pens* room and a `rescue` board job posted only about a
lair whose pens the party has not fought past (rescue), a failed camp watch at
the tier's hard roster (breakout), `hunt_party` jobs — a chief that gets away
keeps the band on the map and the job open (hunt), `deliver_goods` jobs — the
carter dead loses the crate (escort).

Measured, `tests/test_objectives.gd` `test_sweep`, 80 seeds a kind, presets at
level 3, normal roster, the autopilot with `ai.gd`'s one movement rule per
kind (the grid is also in `core/objectives.gd`'s header):

| kind | done | won | knob it was tuned by |
|---|---|---|---|
| hold | NN/80 | NN/80 | `WAVE_SCALE` = N |
| rescue | NN/80 | NN/80 | `RESCUE_DEADLINE` = N |
| breakout | NN/80 | NN/80 | `EXIT_W` = N |
| hunt | NN/80 | NN/80 | `QUARRY_CORNERED` = N |
| escort | NN/80 | NN/80 | `CARTER_HP_BASE` = N, per level N |

The band is 40–75%: an objective that is nearly free is a modifier, one that
is nearly impossible is a trap. Nothing in `scaler.gd` moved; a spec without an
objective is the fight it was, and the 200-seed sweep's numbers are unchanged.

Co-op needed no wire change: the objective is a key on the spec `setup`
already carries, bystanders and waves are built from the seed on both peers,
and `test_coop.gd` replays each kind to the same hash.

### Still open

- A story cannot yet author an objective — the M9 seam, one key away.
- Raids (C1) will be the second source for hold; callings (B3) the second for rescue.
- The freed captive is a line, not a person who walks home with the party.
```

with the real numbers from Task 6 in place of `NN` / `N`.

- [ ] **Step 2: Run the whole suite**

Run: `tools/run_tests.sh --unit 2>&1 | tail -5`
Expected: every unit test green.

Run: `tools/run_tests.sh --drive 2>&1 | tail -5`
Expected: every robot green (this takes several minutes).

- [ ] **Step 3: Commit and open the PR**

```bash
git add docs/expansion-plan.md
git commit -m "Objectives: the shipped record

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin claude/objectives
gh pr create --title "Encounter objectives: hold, rescue, breakout, hunt, escort" --body "$(cat <<'PRBODY'
Sub-project 1 of the content batch. Five objectives on the encounter spec — the same board, roster, AI and dice, a different question — each reachable from one place in the open world. A spec without an objective is the fight it was.

- `core/objectives.gd`: the knobs, the tokens, the builders, the words. Rules per kind in `core/combat.gd`; placement in `core/encounter.gd`; the quarry runs and the autopilot learns one rule per kind in `core/ai.gd`.
- Reward: an objective done pays half the roster's worth in XP on top of kills; gold/loot stay kills-only.
- Sources: the *gate* and *pens* site rooms, a `rescue` board job, a failed camp watch, `hunt_party` and `deliver_goods` jobs.
- Measured: 80 seeds a kind, every kind inside 40–75% done (grid in `core/objectives.gd` and `docs/expansion-plan.md`). `scaler.gd` untouched.
- Co-op: no wire change; `test_coop.gd` replays each kind to the same hash.

Spec: `docs/superpowers/specs/2026-09-20-encounter-objectives-design.md`. Plan: `docs/superpowers/plans/2026-09-20-encounter-objectives.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PRBODY
)"
```
