# Landmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six kinds of landmark on the open-world map — ruins, shrine, standing stones, hermit's hut, wreck, watchtower — each a place with two skill-gated choices and *Leave*, answered once, with rewards that are not fights.

**Architecture:** A `Landmark` on the world model (saved under a new key), a static `core/landmarks.gd` that owns the kinds, the option rows, the checks and the reward doors, and a thin world-screen wiring that reuses the approach card and the event card. Placement is one static call at the end of each built-in builder and a `landmarks` array in a pack's `world.json`. Discovery mirrors lairs: visible kinds flip on explore, hidden kinds on the lair's Survival check or an inn lead.

**Tech Stack:** Godot 4.7.2 (flatpak `godot` on PATH), GDScript, headless tests via `godot --headless --path . -s tests/<file>.gd` (always under `timeout` — a failing `assert()` hangs).

**Spec:** `docs/superpowers/specs/2026-09-20-landmarks-design.md`

## Global Constraints

- A map with no landmarks — an old save, a pack that declares none — plays exactly as today. `core/scaler.gd` does not change. Every existing test keeps passing.
- Preload graph: `core/world.gd` never preloads `core/landmarks.gd` (its `Landmark._init` `load()`s it at call time for a name), so `landmarks.gd` may `preload` `world.gd` and the other core files it needs (`approach.gd`, `travel.gd`, `regions.gd`, `rng.gd`, `dice.gd`, `loot.gd`, `campaign.gd`, `faction_opinion.gd`, `achievements.gd`, `world_lairs.gd`, `rules/catalog.gd`). Anything that is itself preloaded by `world.gd`'s preload closure and needs `landmarks.gd` (rumors, world_pack) uses `load()` at call time, with the codebase's "load(), not preload — X preloads this file" comment.
- Every check names its roll the way the road does: the event dict carries `cname, skill, nat, bonus, dc, ok` so `EventCard` prints "Skill nat+bonus vs DC".
- A landmark is spent by a win or a loss on either choice; *Leave* spends nothing. A spent landmark never offers a card again.
- DCs are the base at ring 0 plus the region ring index (`Regions.at(world, pos)["index"]`); the cache is `CACHE_GOLD × (ring + 1)`.
- No HP loss from a landmark may drop anybody: the toll is `max(1, floor(hp × pct))` with `hp` never taken below 1.
- Tabs; match the surrounding comment voice and density; no unrequested abstractions.
- Commit after each task with the message shown; every commit ends with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Branch `claude/landmarks` (holds the spec).
- Godot generates `.uid` sidecars for new scripts; the repo tracks them — stage a new script's `.uid` together with the script when it appears.

---

### Task 1: The model, and the save

**Files:**
- Modify: `core/world.gd` (after `class Lair`, ~line 127; beside `lairs`/`add_lair` ~198/330; a `marked_until` field beside `explored` ~231)
- Create: `core/landmarks.gd` (kinds and names only in this task)
- Modify: `core/world_save.gd` (`to_dict` lair block ~93; `from_dict` lair block ~160; the `road` dict ~209/230)
- Modify: `core/party.gd` (a `blessed` flag beside `scouted_next` ~41)
- Create: `tests/test_landmarks.gd`
- Modify: `tests/test_world_save.gd` (one new check inside its round-trip)

**Interfaces:**
- Produces: `World.Landmark` with `id, kind, sname, position, found, spent`; `World.landmarks: Array[Landmark]`; `World.add_landmark(l) -> Landmark`; `World.landmark(id)` lookup; `World.marked_until: float` (−1 = none; not saved); `Landmarks.KINDS`, `Landmarks.HIDDEN`, `Landmarks.NAMES`, `Landmarks.is_hidden(kind) -> bool`, `Landmarks.name_for(id, kind) -> String`; `Party.blessed: bool` saved under `road.blessed`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_landmarks.gd`:

```gdscript
# Landmarks — places on the map that are not a fight.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#   godot --headless --path . -s tests/test_landmarks.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const Landmarks = preload("res://core/landmarks.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/landmarks-%d-%d" % [OS.get_process_id(), randi()])
	test_model()
	print("test_landmarks: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "human", true))
	w.add_lair(World.Lair.new("goblin-warren", Vector2(330, 130), "goblinoid"))
	w.add_lair(World.Lair.new("giant-hold", Vector2(-520, -260), "giant"))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

# --- Task 1: the model and the save -----------------------------------------

func test_model() -> void:
	check(Landmarks.KINDS == ["ruins", "shrine", "stones", "hut", "wreck", "tower"], "six kinds, in this order")
	check(Landmarks.is_hidden("hut") and Landmarks.is_hidden("tower") and not Landmarks.is_hidden("ruins"),
		"the hut and the tower are hidden; the rest are visible")
	for k in Landmarks.KINDS:
		check(Landmarks.NAMES.has(k) and Landmarks.NAMES[k].size() >= 3, "%s has names to draw from" % k)
	check(Landmarks.name_for("x-1", "shrine") == Landmarks.name_for("x-1", "shrine"), "a name is stable per id")
	var w := _world()
	var l = w.add_landmark(World.Landmark.new("chapel", "shrine", Vector2(200, 40)))
	check(w.landmarks.size() == 1 and w.landmark("chapel") == l and w.landmark("nope") == null, "added and found by id")
	check(l.sname != "" and not l.found and not l.spent, "named on creation, unfound, unspent")
	check(w.marked_until < 0.0, "nothing marked")
	# the save carries them, and an old save without the key loads with none
	var p := _party()
	p.blessed = true
	l.found = true
	l.spent = true
	var d: Dictionary = WorldSave.to_dict(w, p)
	check(d["world"].has("landmarks") and d["world"]["landmarks"].size() == 1, "saved under \"landmarks\"")
	var back: Dictionary = WorldSave.from_dict(d)
	var w2 = back["world"]
	check(w2.landmarks.size() == 1 and w2.landmark("chapel").kind == "shrine" and w2.landmark("chapel").found
		and w2.landmark("chapel").spent and w2.landmark("chapel").sname == l.sname
		and w2.landmark("chapel").position == l.position, "round-trips every field")
	check(back["party"].blessed, "the blessing rides the road dict")
	d["world"].erase("landmarks")
	check(WorldSave.from_dict(d)["world"].landmarks.is_empty(), "an old save loads with none")
```

Add to `tests/test_world_save.gd`, inside its existing round-trip test where the world is built (find the `_world()` helper and the first `to_dict`/`from_dict` pair), one check: after `w.add_landmark(World.Landmark.new("stones-1", "stones", Vector2(90, 90)))` before saving, assert `back["world"].landmarks.size() == 1` after loading (label: "landmarks survive the save"). Keep the rest of that test as it is.

- [ ] **Step 2: Run to see it fail**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3`
Expected: parse error — `res://core/landmarks.gd` does not exist / `Landmark` not found.

- [ ] **Step 3: The model in `core/world.gd`**

After `class Lair` (~line 152, after its last field):

```gdscript
# A place on the map that is not a fight: ruins, a shrine, standing stones…
# (core/landmarks.gd owns the kinds and what happens there). Found = drawn
# and visitable; spent = answered, once, for good.
class Landmark extends RefCounted:
	var id: String
	var kind: String            # one of Landmarks.KINDS
	var sname: String
	var position: Vector2
	var found := false
	var spent := false

	func _init(_id: String, _kind: String, _position: Vector2, _sname := "") -> void:
		id = _id
		kind = _kind
		position = _position
		sname = _sname if _sname != "" else load("res://core/landmarks.gd").name_for(_id, _kind)   # load: landmarks.gd preloads this file
```

Beside `var lairs: Array[Lair] = []`:

```gdscript
var landmarks: Array[Landmark] = []
```

Beside `var explored: Array[Vector2] = []`:

```gdscript
# A watchtower's "keep watch": every band draws as explored while this holds
# (world-minutes; < 0 = nothing marked). Runtime only — it lapses with the day.
var marked_until := -1.0
```

After `add_lair()`:

```gdscript
func add_landmark(l: Landmark) -> Landmark:
	landmarks.append(l)
	return l

func landmark(id: String):
	for l in landmarks:
		if l.id == id:
			return l
	return null
```

- [ ] **Step 4: `core/landmarks.gd` — the kinds and the names**

```gdscript
# Landmarks — places on the map that are not a fight.
#
# Ruins, a shrine, standing stones, a hermit's hut, a wreck, a watchtower: each
# a place the party walks up to and answers with a skill the world barely uses
# elsewhere. Two choices a kind, one visit, rewards that are not fights.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#
# What this owns: the kinds, the names, the cards (the choices and their
# checks), placement, discovery, and the reward doors. What it does not: the
# model (core/world.gd's Landmark), the drawing (scenes/world/), the save.
#
# world.gd load()s this file for a name at call time (never preloads it), so
# this side may preload world.gd for the Landmark class.
extends RefCounted

const World = preload("res://core/world.gd")

const KINDS := ["ruins", "shrine", "stones", "hut", "wreck", "tower"]
const HIDDEN := ["hut", "tower"]   # found the way lairs are; the rest are hard to miss

const NAMES := {
	"ruins": ["the Broken Chapel", "the Old Mill", "Kessel's Folly", "the Fallen Keep", "the Weir House"],
	"shrine": ["the Wayside Shrine", "the Three Saints", "the Drowned Shrine", "Mother Ash's Altar", "the Lantern Stone"],
	"stones": ["the Nine Sisters", "the Giant's Ring", "the Sleeping Stones", "the Moot Ring", "Harrow Stones"],
	"hut": ["Old Marrow's hut", "the Charcoal Hermit's hut", "Wren Hollow", "the Bee-keeper's hut", "Gallow's Hut"],
	"wreck": ["the Broken Wagon", "a wrecked barge", "the Salt Cart", "a tinker's overturned van", "the Lost Wain"],
	"tower": ["the Old Watch", "Beacon Tower", "the Broken Spire", "the Marcher's Tower", "Crow Tower"],
}

static func is_hidden(kind: String) -> bool:
	return HIDDEN.has(kind)

# Stable per id, so a reload names the same stones the same way.
static func name_for(id: String, kind: String) -> String:
	var pool: Array = NAMES.get(kind, ["a landmark"])
	return String(pool[absi(hash("landmark|%s" % id)) % pool.size()])
```

- [ ] **Step 5: The save, and the blessing flag**

In `core/party.gd`, beside `var scouted_next := false`:

```gdscript
var blessed := false        # a shrine's blessing: temp HP for every hero at the next fight (core/landmarks.gd)
```

In `core/world_save.gd` `to_dict()`, after the `lairs` block is built (before `waters`):

```gdscript
	# Landmarks postdate this format like lairs and water did: an old save
	# without the key loads with none (from_dict below).
	var landmarks: Array = []
	for l in world.landmarks:
		landmarks.append({"id": l.id, "kind": l.kind, "sname": l.sname, "position": _v(l.position),
			"found": l.found, "spent": l.spent})
```

and in the returned dictionary, after `"lairs": lairs,`: `"landmarks": landmarks,`.

In `from_dict()`, after the `lairs` loop:

```gdscript
	for md in d.get("landmarks", []):
		var m := World.Landmark.new(String(md["id"]), String(md.get("kind", "ruins")),
			_vec(md.get("position")), String(md.get("sname", "")))
		m.found = bool(md.get("found", false))
		m.spent = bool(md.get("spent", false))
		world.add_landmark(m)
```

In the `road` dict (~line 209) add `"blessed": party.blessed,` and in the reader (~line 230) `party.blessed = bool(road.get("blessed", false))`.

- [ ] **Step 6: Run the tests**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3` → `0 failed`.
Run: `timeout 300 godot --headless --path . -s tests/test_world_save.gd 2>&1 | tail -1` → `0 failed`.
Run: `timeout 300 godot --headless --path . -s tests/test_world.gd 2>&1 | tail -1` → `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add core/world.gd core/landmarks.gd core/landmarks.gd.uid core/world_save.gd core/party.gd tests/test_landmarks.gd tests/test_landmarks.gd.uid tests/test_world_save.gd
git commit -m "Landmarks: the model, the names, and the save

A Landmark on the world — id, kind, name, position, found, spent — saved
under its own key so an old save loads with none; the blessing flag on
the party rides the road dict.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

(If a `.uid` file was not generated, stage without it.)

---

### Task 2: Placement — the builders and the packs

**Files:**
- Modify: `core/landmarks.gd` (`place()`)
- Modify: `scenes/world/world.gd` (`_small_world` ~379 and `_large_world` ~371 — the end of each)
- Modify: `scenes/world/large_world.gd` (the end of `build()`), `scenes/world/procedural_world.gd` (the end of `build()`)
- Modify: `core/mod/world_pack.gd` (the header comment ~16; `validate()` after the lairs loop ~120; `build()` after the lairs loop ~243)
- Modify: `core/mod/registry.gd` (`_world_ids` ~359)
- Modify: `content/example-world/world.json`, `docs/modding.md` (the `world.json` section)
- Test: `tests/test_landmarks.gd`, `tests/test_world_pack.gd`

**Interfaces:**
- Produces: `Landmarks.place(world, seed: int) -> void`; `Landmarks.LANDMARKS_PER_LAIR := 1.5`, `LANDMARK_GAP := 120.0`; `world.json` `"landmarks": [{"id", "kind", "position", "name"?}]`; `Registry._world_ids` maps a landmark id to `"landmark"`.
- Consumes: `World.add_landmark`, `World.is_water(pos)`, `Regions.MIN_EXTENT`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_landmarks.gd` (call from `_init` after `test_model()`):

```gdscript
func test_placement() -> void:
	# count, gap, dry ground, round-robin kinds — on a hundred seeds
	var bad := 0
	for s in range(1, 101):
		var w := _world()
		w.add_water(Vector2(120, 120), 60.0)
		Landmarks.place(w, s)
		var want: int = ceili(Landmarks.LANDMARKS_PER_LAIR * w.lairs.size())
		if w.landmarks.size() != want:
			bad += 1
			continue
		var taken: Array = []
		for st in w.settlements: taken.append(st.position)
		for l in w.lairs: taken.append(l.position)
		for m in w.landmarks:
			if w.is_water(m.position):
				bad += 1
			for t in taken:
				if t.distance_to(m.position) < Landmarks.LANDMARK_GAP:
					bad += 1
			taken.append(m.position)
	check(bad == 0, "100 seeds: the right count, off the water, the gap kept (%d bad)" % bad)
	var w := _world()
	Landmarks.place(w, 7)
	var kinds: Array = w.landmarks.map(func(m): return m.kind)
	check(kinds.size() == 3 and kinds[0] != kinds[1] and kinds[1] != kinds[2], "kinds go round-robin")
	var w2 := _world()
	Landmarks.place(w2, 7)
	check(w2.landmarks.map(func(m): return [m.id, m.position]) == w.landmarks.map(func(m): return [m.id, m.position]),
		"the same seed places the same landmarks")
	check(w.landmarks.all(func(m): return m.id.begins_with("landmark-")), "ids are namespaced")
```

Add to `tests/test_world_pack.gd` (call from `_init`; use its existing `_src(extra)` helper, which returns a valid world.json dict merged with `extra`):

```gdscript
func test_landmarks() -> void:
	var src := _src({"landmarks": [
		{"id": "chapel", "kind": "shrine", "position": [200, 40], "name": "the Broken Chapel"},
		{"id": "ring", "kind": "stones", "position": [-200, 90]}]})
	check(WorldPack.validate(src)["errors"].is_empty(), "two landmarks validate")
	var w = WorldPack.build(src)
	check(w.landmarks.size() == 2 and w.landmark("chapel").sname == "the Broken Chapel"
		and w.landmark("ring").kind == "stones" and w.landmark("ring").sname != "", "...and are built, named when no name is given")
	var bad := _src({"landmarks": [{"id": "x", "kind": "pyramid", "position": [1, 1]}]})
	var errs: Array = WorldPack.validate(bad)["errors"]
	check(errs.any(func(e): return "pyramid" in String(e)), "an unknown kind is a scan-time error: %s" % str(errs))
	var dup := _src({"landmarks": [{"id": "riverhold", "kind": "ruins", "position": [1, 1]}]})
	check(not WorldPack.validate(dup)["errors"].is_empty(), "a landmark cannot reuse a settlement's id")
```

Check the top of `tests/test_world_pack.gd` for how `WorldPack` is referenced (`const WorldPack = preload("res://core/mod/world_pack.gd")` or similar) and use that name.

- [ ] **Step 2: Run to see them fail**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3` — `Landmarks.place` missing.
Run: `timeout 300 godot --headless --path . -s tests/test_world_pack.gd 2>&1 | tail -3` — landmarks not built / unknown kind not rejected.

- [ ] **Step 3: `Landmarks.place()`**

In `core/landmarks.gd` add `const RNG = preload("res://core/rng.gd")` and:

```gdscript
# --- placement ------------------------------------------------------------

const LANDMARKS_PER_LAIR := 1.5   # the small map's six lairs get nine, the large's ~eighteen
const LANDMARK_GAP := 120.0       # from any settlement, lair or landmark — a thing of its own
const PLACE_TRIES := 200

# The built-in builders call this last: kinds round-robin off the seed, spread
# over the map the settlements span, on dry ground, the gap kept. A pack
# places its own by hand and never comes through here.
static func place(world, seed: int) -> void:
	var rng = RNG.new(maxi(1, seed))
	var count: int = ceili(LANDMARKS_PER_LAIR * world.lairs.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in world.settlements:
		lo = Vector2(minf(lo.x, s.position.x), minf(lo.y, s.position.y))
		hi = Vector2(maxf(hi.x, s.position.x), maxf(hi.y, s.position.y))
	for l in world.lairs:
		lo = Vector2(minf(lo.x, l.position.x), minf(lo.y, l.position.y))
		hi = Vector2(maxf(hi.x, l.position.x), maxf(hi.y, l.position.y))
	lo -= Vector2(LANDMARK_GAP, LANDMARK_GAP)
	hi += Vector2(LANDMARK_GAP, LANDMARK_GAP)
	var start: int = rng.roll_die(KINDS.size()) - 1
	for i in count:
		var kind: String = KINDS[(start + i) % KINDS.size()]
		for _t in PLACE_TRIES:
			var pos := Vector2(lo.x + (hi.x - lo.x) * float(rng.roll_die(1000) - 1) / 999.0,
				lo.y + (hi.y - lo.y) * float(rng.roll_die(1000) - 1) / 999.0)
			if world.is_water(pos) or not _clear(world, pos):
				continue
			world.add_landmark(World.Landmark.new("landmark-%s-%d" % [kind, i], kind, pos))
			break

static func _clear(world, pos: Vector2) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for l in world.lairs:
		if l.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for m in world.landmarks:
		if m.position.distance_to(pos) < LANDMARK_GAP:
			return false
	return true
```

`World` here is the `const World = preload("res://core/world.gd")` at the top of `landmarks.gd` (Task 1 added it). If Godot reports a cyclic reference on load, it means something `world.gd` preloads has started preloading `landmarks.gd` — find it with `grep -rn 'preload("res://core/landmarks.gd")' core` and switch that site to `load()`; say so in the report.

- [ ] **Step 4: The builders**

At the end of `_small_world()` in `scenes/world/world.gd`, before `return w`:

```gdscript
	Landmarks.place(w, 41)   # a fixed seed: the small map is hand-placed, and so are its landmarks
```

Same at the end of `_large_world()` — check whether it delegates to `scenes/world/large_world.gd`'s `build()`; put the call at the end of whichever function assembles the world, with seed `43`. In `scenes/world/procedural_world.gd`'s `build(seed)` before its `return`, `Landmarks.place(w, seed_v + 1)` (whatever its seed variable is called). Add `const Landmarks = preload("res://core/landmarks.gd")` where needed (`world.gd` may already preload many core files — put it beside them).

- [ ] **Step 5: The packs**

`core/mod/world_pack.gd` header comment: add after the `lairs` example:

```
#   "landmarks": [
#     {"id": "chapel", "kind": "shrine", "position": [200, 40], "name": "the Broken Chapel"}
#   ],                                              // kind: ruins | shrine | stones | hut | wreck | tower
```

In `validate()`, after the lairs loop:

```gdscript
	var Landmarks = load("res://core/landmarks.gd")
	for m in d.get("landmarks", []):
		if not (m is Dictionary):
			errors.append("a landmark is not an object")
			continue
		seen.call(String(m.get("id", "")), "landmark")
		if not _is_point(m.get("position")):
			errors.append("landmark \"%s\" has no [x, y] position" % m.get("id", "?"))
		if not Landmarks.KINDS.has(String(m.get("kind", ""))):
			errors.append("landmark \"%s\": kind \"%s\" is not one of %s"
				% [m.get("id", "?"), m.get("kind", ""), Landmarks.KINDS])
```

In `build()`, after the lairs loop:

```gdscript
	for m in d.get("landmarks", []):
		var mark := World.Landmark.new(String(m["id"]), String(m.get("kind", "ruins")),
			_vec(m.get("position")), String(m.get("name", "")))
		by_id[mark.id] = mark.position
		w.add_landmark(mark)
```

In `core/mod/registry.gd` `_world_ids()`, the groups list gains `["landmarks", "landmark"]`.

`content/example-world/world.json`: add a `landmarks` array with two entries placed clear of its settlements/lairs (read the file for coordinates; e.g. a `shrine` and `stones` ~150 units from anything).

`docs/modding.md`: in the `world.json` section, one paragraph — the `landmarks` array, the six kinds, that a pack placing none gets none.

- [ ] **Step 6: Run the tests**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_world_pack test_mod_packs test_world test_world_regions; do timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.
Run: `SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/test_world_sizes.gd 2>&1 | tail -1` → `0 failed` (the three builders).

- [ ] **Step 7: Commit**

```bash
git add core/landmarks.gd scenes/world/world.gd scenes/world/large_world.gd scenes/world/procedural_world.gd core/mod/world_pack.gd core/mod/registry.gd content/example-world/world.json docs/modding.md tests/test_landmarks.gd tests/test_world_pack.gd
git commit -m "Landmarks: placed by the builders, declared by the packs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The cards — six kinds, two choices each, and the doors

**Files:**
- Modify: `core/landmarks.gd` (`CARDS`, `options()`, `resolve()`, the doors)
- Modify: `core/party.gd` (`to_combatants()` ~189: the blessing)
- Modify: `core/achievements.gd` (two rows in the `road` group)
- Modify: `scenes/world/event_card.gd` (`_chips()` ~380: an `xp` chip)
- Test: `tests/test_landmarks.gd`

**Interfaces:**
- Produces: `Landmarks.CARDS` (kind → `[choice, choice]`), `Landmarks.LEAVE := "leave"`, `Landmarks.options(l, party, world) -> Array` (rows in `Approach.options()`'s shape plus `{"id": "leave", ...}` last), `Landmarks.resolve(l, choice_id, party, world, rng) -> Dictionary` (an `EventCard.show_event` dict; `{}` for `leave`), `Landmarks.dc_for(choice, world, pos) -> int`, `Landmarks.ring(world, pos) -> int`, constants `CACHE_GOLD := 60`, `LANDMARK_XP := 40`, `SNARE_PCT := 0.15`, `OFFERING_GOLD := 25`, `HOUR := 60.0`.
- Produces on `Party`: `to_combatants()` grants `temp_hp = 2 × level` per hero and clears `blessed`.
- Consumes: `Approach._roller(party, w)`, `Approach.needs(dc, bonus)`, `Travel.pace_bonus(party)`, `Travel.TIME_SAVED`, `Regions.at`, `Loot.items_of_rarity("common")`, `Campaign.item_name`, `Campaign.new(party)._split_xp`, `Campaign._note_identified`, `party.unidentified()`, `party.stash_identify()`, `FactionOpinion.raise`, `Ach.collect/unlock`, `world.reveal`, `World.VISION_RADIUS`, `world.marked_until`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_landmarks.gd` (call `test_cards()`, `test_resolve()` from `_init`):

```gdscript
const Approach = preload("res://core/approach.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Travel = preload("res://core/travel.gd")
const Adapter = preload("res://core/adapter.gd")

func _mark(w, kind: String, pos := Vector2(200, 40)):
	var m = w.add_landmark(World.Landmark.new("m-" + kind, kind, pos))
	m.found = true
	return m

func test_cards() -> void:
	var w := _world()
	var p := _party()
	for k in Landmarks.KINDS:
		var card: Array = Landmarks.CARDS[k]
		check(card.size() == 2, "%s: two choices" % k)
		for c in card:
			for s in c["skills"]:
				check(Catalog.skills().has(s), "%s/%s rolls a real skill (%s)" % [k, c["id"], s])
			check(c.has("win") and c.has("lose") and c.has("label") and c.has("note"), "%s/%s has its words" % [k, c["id"]])
		var m = _mark(w, k)
		var rows: Array = Landmarks.options(m, p, w)
		check(rows.back()["id"] == Landmarks.LEAVE, "%s: Leave is last" % k)
		for r in rows.slice(0, rows.size() - 1):
			if not r.get("skills", []).is_empty():
				check(r.has("cname") and r.has("needs") and r.has("dc"), "%s/%s is priced with who rolls and what they need" % [k, r["id"]])
	# a choice nobody can roll is dropped; a paid choice the purse cannot cover is dropped
	var poor := Party.new()
	var shrine = _mark(w, "shrine", Vector2(300, 300))
	var rows: Array = Landmarks.options(shrine, poor, w)
	check(rows.size() == 1 and rows[0]["id"] == Landmarks.LEAVE, "an empty party can only leave")
	p.gold = 0
	rows = Landmarks.options(shrine, p, w)
	check(not rows.any(func(r): return r["id"] == "offering"), "no purse, no offering")
	p.gold = 500
	rows = Landmarks.options(shrine, p, w)
	check(rows.any(func(r): return r["id"] == "offering"), "...with one, it is offered")
	# DC climbs with the ring
	var far = _mark(w, "ruins", Vector2(4000, 4000))
	var near = _mark(w, "ruins", Vector2(60, 60))
	check(Landmarks.dc_for(Landmarks.CARDS["ruins"][0], w, far.position) > Landmarks.dc_for(Landmarks.CARDS["ruins"][0], w, near.position),
		"further out, the same check is harder")

func _roll(w, kind: String, id: String, p, seed: int) -> Dictionary:
	var m = _mark(w, kind, Vector2(200 + seed, 40))
	return Landmarks.resolve(m, id, p, w, RNG.new(seed))

# Find a seed where the named choice passes (or fails), so each door can be
# opened deliberately — the roll is a d20, so a few tries always find one.
func _seed_where(w, kind: String, id: String, p, ok: bool) -> int:
	for s in range(1, 60):
		var w2 := _world()
		var p2 := _party()
		p2.gold = 500
		var r := _roll(w2, kind, id, p2, s)
		if bool(r.get("ok", false)) == ok:
			return s
	return -1

func test_resolve() -> void:
	# every win pays the deed; a spent landmark is spent; leave spends nothing
	for k in Landmarks.KINDS:
		for c in Landmarks.CARDS[k]:
			var s := _seed_where(null, k, String(c["id"]), null, true)
			check(s > 0, "%s/%s can be passed" % [k, c["id"]])
			var w := _world()
			var p := _party()
			p.gold = 500
			var xp0: int = p.party_characters()[0].xp
			var r := _roll(w, k, String(c["id"]), p, s)
			check(r["ok"] and r.has("cname") and r.has("nat") and r.has("dc") or c["skills"].is_empty(), "%s/%s names its roll" % [k, c["id"]])
			check(int(r.get("xp", 0)) > 0 and p.party_characters()[0].xp > xp0, "%s/%s: the deed pays" % [k, c["id"]])
			check(w.landmark("m-" + k).spent, "%s/%s: spent" % [k, c["id"]])
			check(Landmarks.options(w.landmark("m-" + k), p, w).is_empty(), "...and offers nothing more")
	var w := _world()
	var p := _party()
	var m = _mark(w, "wreck")
	check(Landmarks.resolve(m, Landmarks.LEAVE, p, w, RNG.new(1)).is_empty() and not m.spent, "leave spends nothing")

	# the doors, one by one
	w = _world(); p = _party(); p.gold = 100
	var r := _roll(w, "shrine", "kneel", p, _seed_where(null, "shrine", "kneel", null, true))
	check(p.blessed, "kneel: blessed")
	var cs: Array = p.to_combatants([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	check(cs[0].temp_hp == 2 * p.party_characters()[0].level() and not p.blessed, "the blessing is temp HP at the next fight, once")
	w = _world(); p = _party(); p.gold = 100
	var gold0: int = p.gold
	r = _roll(w, "shrine", "offering", p, 1)
	check(p.gold == gold0 - Landmarks.OFFERING_GOLD and p.blessed and not r.has("nat"), "offering: costs, blesses, no roll")
	w = _world(); p = _party()
	r = _roll(w, "stones", "marks", p, _seed_where(null, "stones", "marks", null, true))
	check(p.scouted_next, "marks: the next fight starts scouted")
	w = _world(); p = _party()
	var t0: float = w.clock.elapsed
	w.clock.elapsed = 1000.0
	r = _roll(w, "stones", "sleep", p, _seed_where(null, "stones", "sleep", null, true))
	check(w.clock.elapsed == 1000.0 - Travel.TIME_SAVED and int(r["minutes"]) < 0, "sleep: the road is quicker")
	w = _world(); p = _party()
	r = _roll(w, "hut", "road", p, _seed_where(null, "hut", "road", null, true))
	check(p.safe_camp, "road: a safe camp tonight")
	w = _world(); p = _party()
	r = _roll(w, "wreck", "salvage", p, _seed_where(null, "wreck", "salvage", null, true))
	check(p.stash_count("camp-kit") == 1 and r["item_name"] != "", "salvage: a camp kit")
	w = _world(); p = _party()
	gold0 = p.gold
	r = _roll(w, "wreck", "search", p, _seed_where(null, "wreck", "search", null, true))
	check(p.gold > gold0 and int(r["gold"]) == p.gold - gold0, "search: a cache")
	w = _world(); p = _party()
	var hp0: int = p.party_characters()[0].sheet().max_hp
	r = _roll(w, "wreck", "search", p, _seed_where(null, "wreck", "search", null, false))
	check(int(r["hurt"]) > 0 and p.party_characters().all(func(ch): return ch.hp_current == -1 or ch.hp_current >= 1), "a snare hurts and never drops")
	w = _world(); p = _party()
	r = _roll(w, "ruins", "read", p, _seed_where(null, "ruins", "read", null, true))
	check(w.lairs.any(func(l): return l.discovered) or w.landmarks.any(func(x): return x.found and Landmarks.is_hidden(x.kind)), "read: a lead marks something")
	w = _world(); p = _party()
	var m2 = _mark(w, "tower", Vector2(900, 900))
	var before: int = w.explored.size()
	r = Landmarks.resolve(m2, "climb", p, w, RNG.new(_seed_where(null, "tower", "climb", null, true)))
	check(w.explored.size() > before and w.is_explored(Vector2(900, 900)), "climb: the map opens")
	w = _world(); p = _party()
	m2 = _mark(w, "tower", Vector2(900, 900))
	r = Landmarks.resolve(m2, "watch", p, w, RNG.new(_seed_where(null, "tower", "watch", null, true)))
	check(w.marked_until > w.clock.elapsed, "watch: bands are marked for the day")
```

`_seed_where` builds its own world/party when passed `null` (as the calls above do); write it that way (ignore its `w`/`p` parameters when null, or drop them). Adjust the `to_combatants` positions to the party size `Party.demo_roster()` gives.

- [ ] **Step 2: Run to see it fail**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3` — `CARDS`/`options`/`resolve` missing.

- [ ] **Step 3: The cards and the doors in `core/landmarks.gd`**

Preloads at the top (none of these preload `world.gd`): `Approach`, `Travel`, `Regions`, `Dice`, `Loot`, `Campaign`, `FactionOpinion`, `Ach`, and `const Catalog = preload("res://core/rules/catalog.gd")`.

```gdscript
# --- the cards --------------------------------------------------------------
#
# Two choices a kind, in Approach.WAYS' shape so the approach card draws them
# and Approach._roller/needs price them. `reward` names the door resolve()
# opens on a win; `snare` is what a loss costs (nothing, an hour, or the toll).

const LEAVE := "leave"
const CACHE_GOLD := 60
const LANDMARK_XP := 40
const SNARE_PCT := 0.15
const OFFERING_GOLD := 25
const HOUR := 60.0

const CARDS := {
	"ruins": [
		{"id": "read", "label": "Read the stones", "skills": ["history", "investigation"], "dc": 13,
			"note": "Somebody wrote what happened here.",
			"win": "A lead — the nearest thing nobody has found yet is marked.", "lose": "An hour, and no wiser.",
			"reward": "lead", "snare": "hour"},
		{"id": "dig", "label": "Dig in the rubble", "skills": ["athletics", "investigation"], "dc": 14,
			"note": "Whatever fell in here is still in here.",
			"win": "A cache.", "lose": "A snare in the rubble — somebody bleeds for it.",
			"reward": "cache", "snare": "toll"},
	],
	"shrine": [
		{"id": "kneel", "label": "Kneel", "skills": ["religion"], "dc": 12,
			"note": "Whoever kept this place, they kept it for travellers.",
			"win": "A blessing: every hero fights the next fight with something extra.", "lose": "Nothing answers.",
			"reward": "blessing", "snare": "none"},
		{"id": "offering", "label": "Leave an offering", "skills": [], "dc": 0,
			"note": "%d ◉ on the stone. No roll.",
			"win": "The blessing, and the people who keep this shrine hear of it.", "lose": "",
			"reward": "offering", "snare": "none"},
	],
	"stones": [
		{"id": "marks", "label": "Read the marks", "skills": ["arcana"], "dc": 14,
			"note": "The ring is older than the road.",
			"win": "The next fight starts scouted.", "lose": "A headache, and nothing else.",
			"reward": "scouted", "snare": "none"},
		{"id": "sleep", "label": "Sleep in the ring", "skills": ["nature"], "dc": 13,
			"note": "The ground here is kinder than it looks.",
			"win": "The road is quicker for a day.", "lose": "An hour, and a stiff neck.",
			"reward": "road", "snare": "hour"},
	],
	"hut": [
		{"id": "knock", "label": "Knock", "skills": ["persuasion", "performance"], "dc": 13,
			"note": "Somebody lives out here on purpose.",
			"win": "A lead for nothing, and the hermit knows what one of your things is.", "lose": "The door stays shut.",
			"reward": "hermit", "snare": "hour"},
		{"id": "road", "label": "Ask about the road", "skills": ["insight"], "dc": 12,
			"note": "They know which hollows are safe.",
			"win": "A safe camp tonight.", "lose": "Nothing they will say.",
			"reward": "safe_camp", "snare": "none"},
	],
	"wreck": [
		{"id": "search", "label": "Search it", "skills": ["investigation"], "dc": 14,
			"note": "Whoever lost it did not come back for it.",
			"win": "A cache.", "lose": "A snare under the boards — somebody bleeds for it.",
			"reward": "cache", "snare": "toll"},
		{"id": "salvage", "label": "Salvage", "skills": ["athletics"], "dc": 13,
			"note": "Canvas, rope, an axle.",
			"win": "A camp kit.", "lose": "An hour, and nothing worth the carrying.",
			"reward": "camp_kit", "snare": "hour"},
	],
	"tower": [
		{"id": "climb", "label": "Climb", "skills": ["athletics"], "dc": 12,
			"note": "The stair is half there.",
			"win": "The country opens up for miles.", "lose": "An hour on a stair that goes nowhere.",
			"reward": "reveal", "snare": "hour"},
		{"id": "watch", "label": "Keep watch", "skills": ["perception"], "dc": 13,
			"note": "An hour at the top, looking.",
			"win": "Every band for two days' walk is marked until tomorrow.", "lose": "Nothing moves.",
			"reward": "marked", "snare": "none"},
	],
}

static func ring(world, pos: Vector2) -> int:
	return int(Regions.at(world, pos)["index"])

static func dc_for(choice: Dictionary, world, pos: Vector2) -> int:
	return int(choice["dc"]) + ring(world, pos)

# The rows the approach card draws. A skill nobody can roll is not offered
# (Approach's rule); an offering the purse cannot cover is not offered.
# A spent landmark offers nothing at all.
static func options(l, party, world) -> Array:
	if l.spent:
		return []
	var out: Array = []
	for c in CARDS[l.kind]:
		var o: Dictionary = {"id": c["id"], "label": c["label"], "note": c["note"],
			"dc": dc_for(c, world, l.position), "win": c["win"]}
		if String(c["lose"]) != "":
			o["lose"] = c["lose"]
		if c["skills"].is_empty():
			var price: int = OFFERING_GOLD * (ring(world, l.position) + 1)
			if party.gold < price:
				continue
			o["note"] = String(c["note"]) % price
			o["toll"] = price
		else:
			var who: Dictionary = Approach._roller(party, c)
			if who.is_empty():
				continue
			var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
			o.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
				"bonus": bonus, "named": bool(who["named"]), "needs": Approach.needs(o["dc"], bonus)}, true)
		out.append(o)
	out.append({"id": LEAVE, "label": "Leave it", "note": "Nothing spent, nothing gained.", "dc": 0, "win": "The road goes on."})
	return out

# One answer: roll the check, open the door, spend the place, pay the deed.
# Returns the event card's dict (core/travel.gd's shape) — the check named,
# the roll named, the reward said — or {} for leave.
static func resolve(l, choice_id: String, party, world, rng) -> Dictionary:
	if choice_id == LEAVE or l.spent:
		return {}
	var c: Dictionary = {}
	for cand in CARDS[l.kind]:
		if String(cand["id"]) == choice_id:
			c = cand
	if c.is_empty():
		return {}
	var e: Dictionary = {"id": "landmark-%s-%s" % [l.kind, choice_id], "title": l.sname, "ok": true}
	if not c["skills"].is_empty():
		var who: Dictionary = Approach._roller(party, c)
		if who.is_empty():
			return {}
		var bonus: int = int(who["bonus"]) + Travel.pace_bonus(party)
		var nat: int = int(Dice.d20(rng)["nat"])
		var dc: int = dc_for(c, world, l.position)
		e.merge({"char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
			"nat": nat, "bonus": bonus, "dc": dc, "ok": nat + bonus >= dc, "named": bool(who["named"])}, true)
	else:
		var price: int = OFFERING_GOLD * (ring(world, l.position) + 1)
		if not party.spend_gold(price):
			return {}
		e["gold"] = -price
	l.spent = true
	if e["ok"]:
		e["kind"] = "good"
		e["text"] = String(c["win"])
		_open(String(c["reward"]), l, party, world, rng, e)
		var xp: int = LANDMARK_XP * (ring(world, l.position) + 1)
		Campaign.new(party)._split_xp(xp)
		e["xp"] = xp
		Ach.collect("landmarks", l.id)
		Ach.collect("landmark_kinds", l.kind)
	else:
		e["kind"] = "bad"
		e["text"] = String(c["lose"])
		match String(c["snare"]):
			"hour":
				world.clock.elapsed += HOUR
				e["minutes"] = HOUR
			"toll":
				e["hurt"] = toll(party.get_member(String(e["char_id"])), SNARE_PCT)
	return e

# The road's rule, for one person: a share of what they have, never below 1.
static func toll(ch, pct: float) -> int:
	if ch == null:
		return 0
	var s = ch.sheet()
	var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
	var after: int = maxi(1, cur - maxi(1, int(floor(cur * pct))))
	ch.hp_current = after
	ch.dirty()
	return cur - after

# --- the doors --------------------------------------------------------------

static func _open(reward: String, l, party, world, rng, e: Dictionary) -> void:
	match reward:
		"cache":
			var gold: int = CACHE_GOLD * (ring(world, l.position) + 1)
			gold = gold * (75 + rng.roll_die(51) - 1) / 100   # ±25 %
			party.add_gold(gold)
			e["gold"] = gold
			if rng.roll_die(3) == 1:
				var pool: Array = Loot.items_of_rarity("common")
				if not pool.is_empty():
					var item: String = String(pool[rng.roll_die(pool.size()) - 1])
					party.stash_add(item)
					e["item_name"] = Campaign.item_name(item)
		"blessing":
			party.blessed = true
		"offering":
			party.blessed = true
			var near = _nearest_settlement(world, l.position)
			if near != null:
				FactionOpinion.raise(near.faction, 2.0)
				e["thanks"] = near.sname
		"scouted":
			party.scouted_next = true
		"road":
			world.clock.elapsed -= Travel.TIME_SAVED
			e["minutes"] = -Travel.TIME_SAVED
		"safe_camp":
			party.safe_camp = true
		"camp_kit":
			party.stash_add("camp-kit")
			e["item_name"] = Campaign.item_name("camp-kit")
		"lead":
			_lead(world, l.position, e)
		"hermit":
			_lead(world, l.position, e)
			var unknown: Array = party.unidentified()
			if not unknown.is_empty():
				var item: String = String(unknown[0])
				party.stash_identify(item)
				Campaign._note_identified(item)
				e["item_name"] = Campaign.item_name(item)
		"reveal":
			world.reveal(l.position)
			for i in 8:
				var a := TAU * float(i) / 8.0
				world.reveal(l.position + Vector2(cos(a), sin(a)) * World.VISION_RADIUS)
		"marked":
			world.marked_until = world.clock.elapsed + FactionOpinion.DAY

# The nearest unfound lair or hidden landmark gets marked, and the card says which.
static func _lead(world, from: Vector2, e: Dictionary) -> void:
	var best = null
	var best_d := INF
	for x in world.lairs:
		var d: float = from.distance_to(x.position)
		if not x.discovered and not x.looted and d < best_d:
			best = x
			best_d = d
	for x in world.landmarks:
		var d: float = from.distance_to(x.position)
		if not x.found and is_hidden(x.kind) and d < best_d:
			best = x
			best_d = d
	if best == null:
		return
	if "discovered" in best:
		best.discovered = true
	else:
		best.found = true
	e["lair"] = best.sname

static func _nearest_settlement(world, from: Vector2):
	var best = null
	var best_d := INF
	for s in world.settlements:
		var d: float = from.distance_to(s.position)
		if d < best_d:
			best = s
			best_d = d
	return best
```

Check these names against the code before relying on them and adjust if one differs: `FactionOpinion.DAY` (the world-minutes day in `core/faction_opinion.gd`), `World.VISION_RADIUS` (a `const` on `core/world.gd`), `Character.level()`, `Character.sheet()`, `Character.hp_current`, `Character.dirty()`, `Loot.items_of_rarity`, `Campaign.item_name`, `Campaign._note_identified`.

- [ ] **Step 4: The blessing's door in `core/party.gd`**

`to_combatants()` becomes:

```gdscript
func to_combatants(positions: Array, team := "party") -> Array:
	var out := []
	var chars := party_characters()
	for i in chars.size():
		var p: Vector2i = positions[i] if i < positions.size() else Vector2i.ZERO
		var c = Adapter.to_combatant(chars[i], team, p)
		if blessed:   # a shrine's blessing (core/landmarks.gd): something extra, at the next fight, once
			c.temp_hp = 2 * chars[i].level()
		out.append(c)
	blessed = false
	return out
```

- [ ] **Step 5: The event card's XP chip, and the badges**

In `scenes/world/event_card.gd` `_chips()`, after the `healed` chip:

```gdscript
	var xp := int(_num("xp"))
	if xp > 0:
		out.append({"text": "+%d XP" % xp, "col": Icons.COL_GOLD})
```

In `core/achievements.gd`, beside `regions_4` in the `road` group:

```gdscript
	{"id": "landmarks_6", "group": "road", "title": "Surveyor",
		"desc": "Answer every kind of landmark once.", "counter": "landmark_kinds", "goal": 6},
	{"id": "landmarks_12", "group": "road", "title": "Antiquary",
		"desc": "Answer twelve landmarks.", "counter": "landmarks", "goal": 12},
```

Check `tests/test_achievements.gd` for a count of rows or groups and update it if it pins the number.

- [ ] **Step 6: Run the tests**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -5` → `0 failed`.
Run: `for t in test_achievements test_party test_event_card test_approach test_encounter test_coop; do SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add core/landmarks.gd core/party.gd core/achievements.gd scenes/world/event_card.gd tests/test_landmarks.gd tests/test_achievements.gd
git commit -m "Landmarks: six kinds, two choices each, and the doors they open

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Discovery — exploring, searching, and the inn

**Files:**
- Modify: `core/landmarks.gd` (`found_on_explore`, `nearby_hidden`, `nearest_open`, `search`)
- Modify: `core/rumors.gd` (`offers` ~66, `buy` ~101, `free_lead` ~122)
- Test: `tests/test_landmarks.gd`, `tests/test_rumors.gd` (if it exists; else in `test_landmarks.gd`)

**Interfaces:**
- Produces: `Landmarks.found_on_explore(world) -> Array` (the landmarks that just became found), `Landmarks.nearby_hidden(world, from: Vector2)` (an unfound hidden landmark within `WorldLairs.DISCOVER_RADIUS`, or null), `Landmarks.nearest_open(world, from: Vector2)` (a found, unspent landmark within `WorldLairs.DISCOVER_RADIUS`, or null), `Landmarks.search(l, party, rng = null) -> Dictionary` (the lair search's shape: `{ok, cname, skill, nat, bonus, dc, char_id}`); rumour offers with `"landmark_id"` at half a lair's base price; `Rumors.buy` and `free_lead` mark a landmark `found`.
- Consumes: `WorldLairs.DISCOVER_SKILL/DISCOVER_DC/DISCOVER_RADIUS`, `WorldLairs.search`'s roller (read `core/world_lairs.gd` `search()` and mirror its shape exactly).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_landmarks.gd` (call `test_discovery()` from `_init`):

```gdscript
const WorldLairs = preload("res://core/world_lairs.gd")
const Rumors = preload("res://core/rumors.gd")

func test_discovery() -> void:
	var w := _world()
	var p := _party()
	var seen = w.add_landmark(World.Landmark.new("m-ruins", "ruins", Vector2(90, 130)))
	var hid = w.add_landmark(World.Landmark.new("m-hut", "hut", Vector2(100, 150)))
	check(Landmarks.found_on_explore(w).is_empty() and not seen.found, "nothing explored, nothing found")
	w.reveal(Vector2(90, 130))
	var just: Array = Landmarks.found_on_explore(w)
	check(just == [seen] and seen.found and not hid.found, "exploring finds the ruins, not the hut")
	check(Landmarks.found_on_explore(w).is_empty(), "...and says so once")
	check(Landmarks.nearby_hidden(w, Vector2(100, 140)) == hid, "the hut is there to search for")
	check(Landmarks.nearby_hidden(w, Vector2(900, 900)) == null, "...within the lair's radius")
	check(Landmarks.nearest_open(w, Vector2(95, 135)) == seen, "the found ruins are open to visit")
	seen.spent = true
	check(Landmarks.nearest_open(w, Vector2(95, 135)) == null, "...until spent")
	# the search is the lair's check, on the same skill and DC
	var found := false
	for s in range(1, 40):
		var r: Dictionary = Landmarks.search(hid, p, RNG.new(s))
		check(r["skill"] == WorldLairs.DISCOVER_SKILL and int(r["dc"]) == WorldLairs.DISCOVER_DC, "seed %d: Survival vs the lair's DC" % s)
		if r["ok"]:
			found = true
			break
	check(found and hid.found, "a passed search finds the hut")
	# the inn sells a hidden landmark, cheaper than a lair
	w = _world()
	var hut = w.add_landmark(World.Landmark.new("m-hut2", "hut", Vector2(150, 150)))
	var offers: Array = Rumors.offers(w.settlements[0], w)
	var mine: Array = offers.filter(func(o): return o.get("landmark_id", "") == "m-hut2")
	check(mine.size() == 1 and int(mine[0]["price"]) < Rumors.PRICE_BASE, "the inn offers the hut, under a lair's price")
	p.gold = 500
	var bought: Dictionary = Rumors.buy(mine[0], p, w)
	check(bought["ok"] and hut.found and bought["text"].contains(hut.sname), "buying it marks it, and says so")
	check(Rumors.offers(w.settlements[0], w).filter(func(o): return o.get("landmark_id", "") == "m-hut2").is_empty(), "...and it is off the list")
	w.add_landmark(World.Landmark.new("m-ruins2", "ruins", Vector2(160, 160)))
	check(Rumors.offers(w.settlements[0], w).filter(func(o): return o.get("landmark_id", "") == "m-ruins2").is_empty(), "a visible kind is never sold — it is found by walking")
```

- [ ] **Step 2: Run to see it fail**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3`.

- [ ] **Step 3: Discovery in `core/landmarks.gd`**

Add `const WorldLairs = preload("res://core/world_lairs.gd")` and:

```gdscript
# --- discovery ----------------------------------------------------------------

# Visible kinds are found by walking: the first frame the fog is off them.
# Returns the ones that just turned, so the screen can say so.
static func found_on_explore(world) -> Array:
	var out: Array = []
	for l in world.landmarks:
		if l.found or is_hidden(l.kind):
			continue
		if world.is_explored(l.position):
			l.found = true
			out.append(l)
	return out

# A hidden landmark in search range — the same radius a lair hides at.
static func nearby_hidden(world, from: Vector2):
	for l in world.landmarks:
		if not l.found and is_hidden(l.kind) and from.distance_to(l.position) <= WorldLairs.DISCOVER_RADIUS:
			return l
	return null

# A found, unspent landmark near enough to walk up to.
static func nearest_open(world, from: Vector2):
	var best = null
	var best_d := INF
	for l in world.landmarks:
		var d: float = from.distance_to(l.position)
		if l.found and not l.spent and d <= WorldLairs.DISCOVER_RADIUS and d < best_d:
			best = l
			best_d = d
	return best

# The lair's Survival check, verbatim (core/world_lairs.gd search()), so there
# is one way to search the ground. A pass marks the place found.
static func search(l, party, rng = null) -> Dictionary:
	var r: Dictionary = WorldLairs.search_roll(party, rng)
	if not r.is_empty() and r["ok"]:
		l.found = true
	return r
```

Read `WorldLairs.search(lair, party, rng)` in `core/world_lairs.gd`: it rolls and then sets `lair.discovered`. Split its roll into `static func search_roll(party, rng = null) -> Dictionary` (the same body minus the `lair.discovered = true` line, returning the same dict) and have `search()` call it and set `discovered` — so both lairs and landmarks share one roll. Keep `search()`'s signature and behaviour identical for lairs.

- [ ] **Step 4: The inn, in `core/rumors.gd`**

In `offers()`, after the lairs loop (before the sort):

```gdscript
	# A hidden landmark is worth a word too — half a lair's base price, and
	# only the hidden kinds: a ruin you can see from the road nobody sells.
	var Landmarks = load("res://core/landmarks.gd")   # load: landmarks.gd preloads nothing of ours, but keep the graph flat
	for m in world.landmarks:
		if m.found or not Landmarks.is_hidden(m.kind):
			continue
		var d: float = settlement.position.distance_to(m.position)
		if d > RANGE:
			continue
		var band: Dictionary = Regions.at(world, m.position)
		out.append({
			"landmark_id": m.id, "distance": d,
			"price": int(round(PRICE_BASE * 0.5 * float(PRICE_BY_KIND.get(settlement.kind, 1.0)))),
			"region": String(band["label"]),
			"text": String(LANDMARK_TALK.get(m.kind, "Somebody out there knows the country.")),
			"where": "%s" % String(band["label"]),
		})
```

with a `const LANDMARK_TALK := {"hut": "There is an old one living out past the trees who sees everything that passes.", "tower": "The old watch still stands, if you know which ridge."}` beside `TALK`.

`buy()` — before the lair lookup:

```gdscript
	if offer.has("landmark_id"):
		var m = world.landmark(String(offer["landmark_id"]))
		if m == null or m.found:
			return {"ok": false, "text": "That is old news now."}
		var lprice := int(offer.get("price", 0))
		if not party.spend_gold(lprice):
			return {"ok": false, "price": lprice, "text": "They will not talk for less than %d ◉." % lprice}
		m.found = true
		return {"ok": true, "price": lprice, "landmark_id": m.id, "sname": m.sname,
			"text": "%s  %s is on the map now (-%d ◉)." % [String(offer.get("text", "")), m.sname, lprice]}
```

`free_lead()` — after `var offer: Dictionary = avail[0].duplicate()`, if `offer.has("landmark_id")`: mark it found and return the same dict shape as the lair branch (`"text": "%s  They mark %s on your map, and will not take anything for it."`). Check `scenes/world/world.gd`'s callers of `buy`/`free_lead` read only `ok/text/price` (they do — `_buy_rumor` and `_turn_in`).

- [ ] **Step 5: Run the tests**

Run: `timeout 300 godot --headless --path . -s tests/test_landmarks.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_world_lairs test_rumors test_world_visit_pages test_quest_posting; do SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed` (skip a file that does not exist).

- [ ] **Step 6: Commit**

```bash
git add core/landmarks.gd core/world_lairs.gd core/rumors.gd tests/test_landmarks.gd
git commit -m "Landmarks: found by walking, by the lair's search, or bought at the inn

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The world screen — the button, the card, the outcome, the markers

**Files:**
- Modify: `scenes/world/world.gd` (preloads ~58; button build ~716; `_check_lairs` region ~1866; the `_process` check list ~469; approach functions ~2131; marker rows ~3757; a spent-say line)
- Modify: `scenes/world/approach_card.gd` (skinnable caption/glyph/hint/art)
- Modify: `scenes/world/minimap.gd` (the lairs pass ~479)
- Create: `tests/test_world_landmarks.gd`

**Interfaces:**
- Produces: `world._place_btn: Button`, `world._place_target`, `world._check_places()`, `world._place_action()`, `world._open_place(l)`, `world._on_place_chosen(id)`; `ApproachCard.caption/glyph/hint/art_stem` vars.
- Consumes: Task 3/4's `Landmarks.options/resolve/found_on_explore/nearby_hidden/nearest_open/search`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_world_landmarks.gd`:

```gdscript
# Landmarks on the world screen: found by walking, a button to visit, the
# approach card asks, the event card answers, and a spent place is quiet.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_landmarks.gd
extends SceneTree
const World = preload("res://core/world.gd")
const Landmarks = preload("res://core/landmarks.gd")
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

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	check(w.landmarks.size() >= 6, "the small map has landmarks (%d)" % w.landmarks.size())

	# a shrine under the party's feet: found by being explored, and a button appears
	var shrine = w.add_landmark(World.Landmark.new("t-shrine", "shrine", p.position + Vector2(20, 0)))
	for i in 3:
		await process_frame
	check(shrine.found, "walked up to, it is found")
	check(main._place_btn.visible and "Visit" in main._place_btn.text and shrine.sname in main._place_btn.text,
		"the button offers a visit: %s" % main._place_btn.text)
	main._place_btn.pressed.emit()
	await process_frame
	check(main._approach_card != null and w.clock.is_paused(), "the card opens and the clock stops")
	# choose the offering (no roll): the event card answers, the place is spent
	main.party.gold = 500
	main._on_place_chosen("offering")
	for i in 3:
		await process_frame
	check(main._event_card != null, "the outcome is on the event card")
	check(shrine.spent and main.party.blessed, "the offering blesses and spends the shrine")
	main._event_card.acknowledged.emit()
	for i in 3:
		await process_frame
	check(not w.clock.is_paused(), "acknowledged, the clock runs")
	check(not main._place_btn.visible or not (shrine.sname in main._place_btn.text), "a spent place offers no visit")

	# leave spends nothing
	var ruins = w.add_landmark(World.Landmark.new("t-ruins", "ruins", p.position + Vector2(-20, 0)))
	for i in 3:
		await process_frame
	main._place_btn.pressed.emit()
	await process_frame
	main._on_place_chosen(Landmarks.LEAVE)
	for i in 3:
		await process_frame
	check(not ruins.spent and main._approach_card == null and not w.clock.is_paused(), "leave closes the card, spends nothing")

	# a hidden hut: the button offers the search instead
	var hut = w.add_landmark(World.Landmark.new("t-hut", "hut", p.position + Vector2(0, 25)))
	ruins.spent = true
	for i in 3:
		await process_frame
	check(main._place_btn.visible and "Search" in main._place_btn.text, "a hidden place offers a search: %s" % main._place_btn.text)

	# markers: found landmarks draw, unfound ones do not
	var rows: Array = main._marker_rows()
	check(rows.any(func(r): return r.get("label", "") == shrine.sname), "a found landmark is a marker")
	check(not rows.any(func(r): return r.get("label", "") == hut.sname), "an unfound one is not")
	print("test_world_landmarks: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

`_marker_rows()` — find the function in `scenes/world/world.gd` that builds the marker dictionaries (the loop over `world.settlements`/`world.lairs` at ~3757 returning `out`) and use its real name in the test; if it is not a standalone function, extract the loop into `func _marker_rows() -> Array` first.

- [ ] **Step 2: Run to see it fail**

Run: `SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/test_world_landmarks.gd 2>&1 | tail -3` — `_place_btn` missing.

- [ ] **Step 3: The approach card's skin (`scenes/world/approach_card.gd`)**

Beside its constants add four vars and use them where the constants were:

```gdscript
# A landmark card is this card with different words: core/landmarks.gd's rows
# are Approach's shape, so only the dressing changes.
var caption := CAPTION
var glyph := GLYPH
var hint := "Choose how to meet them"
var art_stem := ""          # assets/generated/<stem>.png when set; the way's own scene art otherwise
```

- the `CAPTION`/`GLYPH` draw calls (~391-392) read `caption`/`glyph`;
- the hint line (~417) becomes `var hint_line := "%s — click a row, or press 1-%d." % [hint, _opts.size()]` (keep the `NAMED_HINT` append);
- in `show_approach()`, `_art = Icons.scene_art(art_stem, null) if art_stem != "" else Icons.event_art(FRIENDLY_SCENE_ART if _friendly() else SCENE_ART, null)`.

`WAY_GLYPH.get(id, UNKNOWN_GLYPH)` already covers unknown option ids — confirm and leave it.

- [ ] **Step 4: The world screen**

Preload: `const Landmarks = preload("res://core/landmarks.gd")` beside the other core preloads (if Task 2 did not already add it).

Fields, beside `_lair_btn`/`_lair_target`:

```gdscript
var _place_btn: Button                # landmarks: "Visit the Nine Sisters" / "Search the ground (Survival)", or hidden
var _place_target = null              # whichever landmark _check_places() last found in range
var _place_open = null                # the one whose card is up
```

Where `_lair_btn` is built (~716), after it:

```gdscript
	_place_btn = Button.new()
	_place_btn.visible = false
	_place_btn.pressed.connect(_place_action)
	bar.add_child(_place_btn)
```

In `_process`'s check list, after `_check_lairs()`: `_check_places()`.

The functions, after `_check_expired_lairs()`:

```gdscript
# --- landmarks: places on the map that are not a fight -----------------------
# The lair button's shape again: one button, two states. A found place offers a
# visit; a hidden one in range offers the same Survival search a lair does.
func _check_places() -> void:
	for l in Landmarks.found_on_explore(world):
		_lair_msg.text = "%s — a landmark, on the map now." % l.sname
	if _combat != null or not _visit.is_empty() or _overlay_up():
		_place_btn.visible = false
		return
	var p := world.player()
	if p == null:
		_place_btn.visible = false
		return
	var open = Landmarks.nearest_open(world, p.position)
	var hidden = Landmarks.nearby_hidden(world, p.position) if open == null else null
	_place_target = open if open != null else hidden
	if _place_target == null:
		_place_btn.visible = false
		return
	_place_btn.visible = true
	_place_btn.text = ("Visit %s" % open.sname) if open != null else "Search the ground (Survival)"

func _place_action() -> void:
	var l = _place_target
	if l == null or _combat != null:
		return
	if not l.found:
		var roll: Dictionary = Landmarks.search(l, party)
		if roll.is_empty():
			return
		_lair_msg.text = ("%s finds it — %s is here (Survival %d+%d vs DC %d)." % [
			roll["cname"], l.sname, roll["nat"], roll["bonus"], roll["dc"]]) if roll["ok"] else (
			"Nothing this time (Survival %d+%d vs DC %d)." % [roll["nat"], roll["bonus"], roll["dc"]])
		return
	_open_place(l)

func _open_place(l) -> void:
	if _approach_card != null:
		return
	world.clock.pause()
	_pause_btn.text = "Resume"
	_place_open = l
	_approach_card = ApproachCard.new()
	_approach_card.caption = "A   P L A C E   O N   T H E   R O A D"
	_approach_card.glyph = "◆"
	_approach_card.hint = "Choose what to do here"
	_approach_card.art_stem = "landmark-" + l.kind
	add_child(_approach_card)
	_approach_card.chosen.connect(_on_place_chosen)
	_approach_card.show_approach(Landmarks.options(l, party, world), l.sname)

func _on_place_chosen(id: String) -> void:
	var l = _place_open
	_place_open = null
	_close_approach()
	if l == null:
		return
	var e: Dictionary = Landmarks.resolve(l, id, party, world,
		RNG.new(maxi(1, absi(hash("%s|%s|%d" % [l.id, id, int(world.clock.elapsed)])))))
	if e.is_empty():   # leave, or nothing to do
		world.clock.resume()
		_pause_btn.text = "Pause"
		return
	_autosave()
	_event_card = EventCard.new()
	add_child(_event_card)
	_event_card.acknowledged.connect(_on_event_ack)
	_event_card.show_event(e)
```

Check `_close_approach()` does not touch `_approach_foe` in a way that breaks when it is null (it sets it to null — fine). Check `ApproachCard.show_approach` uses `_friendly()` for anything beyond art (if it changes the hint or buttons for friendly rows, the landmark rows' ids are not in `FRIENDLY_WAYS`, so it takes the hostile path — fine).

Markers (~3757 loop), after the lairs loop:

```gdscript
	for m in world.landmarks:
		if not m.found or not world.is_explored(m.position):
			continue
		var live: bool = world.is_visible_now(m.position, ppos)
		out.append({"pos": m.position,
			"radius": _footprint(LANDMARK_RADIUS, _landmarks3d.footprint(m) if _landmarks3d != null else 0.0),
			"color": _remembered(Icons.COL_MUTED if m.spent else Icons.COL_ACCENT, live),
			"ring": RING_WIDTH, "fill": SETTLEMENT_FILL, "shadow": 0.8, "label": m.sname, "live": live})
```

with `const LANDMARK_RADIUS := 10.0` beside `LAIR_RADIUS`, and `var _landmarks3d = null` beside `_lairs3d` (Task 6 fills it; until then the `null` check keeps this line honest). The "marked bands" door: in the parties loop of the same function, treat a band as explored while `world.marked_until > world.clock.elapsed` — change `if not q.is_player and not world.is_explored(q.position): continue` to `if not q.is_player and not world.is_explored(q.position) and world.marked_until <= world.clock.elapsed: continue`.

`scenes/world/minimap.gd`, after the lairs pass:

```gdscript
	for m in w.landmarks:
		if m.found and w.is_explored(m.position):
			_draw_diamond(_to_widget(m.position), R_LAIR - 1, Icons.COL_MUTED if m.spent else Icons.COL_ACCENT)
```

and its content stamp (~192) gains `+ w.landmarks.size() * 1013`.

- [ ] **Step 5: Run the tests**

Run: `SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/test_world_landmarks.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_world_panels test_world_menu test_approach_card test_minimap test_world_markers test_world_spoils test_world_camp_integration; do SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.
Run: `SORCMERC_FAST=1 SORCMERC_SEED=5 timeout 600 godot --headless --path . -s tests/drive_world.gd 2>&1 | tail -1` → OK.

- [ ] **Step 6: Commit**

```bash
git add scenes/world/world.gd scenes/world/approach_card.gd scenes/world/minimap.gd tests/test_world_landmarks.gd
git commit -m "Landmarks on the map: a button to visit, the approach card asks, the event card answers

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: The dioramas

**Files:**
- Create: `scenes/world/landmark_kit.gd`, `scenes/world/landmarks3d.gd`
- Modify: `scenes/world/world.gd` (the layer wiring beside `_lairs3d` ~352; every `_lairs3d.reset(world)` / `reposition()` site)
- Test: `tests/test_lair_kit.gd` (a landmark-kit section) or a new `tests/test_landmark_kit.gd`

**Interfaces:**
- Produces: `LandmarkKit.has(kind)`, `LandmarkKit.plan(kind) -> Array`, `LandmarkKit.build(kind) -> Node3D`, `LandmarkKit.triangles(kind)`; `Landmarks3D` (extends `props3d.gd`) with `reset(world)`, `reposition()`, `footprint(l)`, `has_model(l)`.
- Consumes: `KitParts.assemble/apron/triangles`, `LairKit.RADIUS/HEIGHT` conventions, `props3d.gd`'s `at()`, `_explored()`, `_fade()`, `_player_pos()`, `footprint_of()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_landmark_kit.gd` (copy the header/`check` shape of `tests/test_lair_kit.gd`):

```gdscript
extends SceneTree
const LandmarkKit = preload("res://scenes/world/landmark_kit.gd")
const Landmarks = preload("res://core/landmarks.gd")
var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)
func _init() -> void:
	for k in Landmarks.KINDS:
		check(LandmarkKit.has(k), "%s has a diorama" % k)
		var plan: Array = LandmarkKit.plan(k)
		check(plan.size() >= 3, "%s: a plan with a few parts (%d)" % [k, plan.size()])
		check(LandmarkKit.triangles(k) <= 600, "%s: cheap (%d triangles)" % [k, LandmarkKit.triangles(k)])
		var n := LandmarkKit.build(k)
		check(n != null and n.get_child_count() > 0, "%s: builds" % k)
		n.free()
	check(LandmarkKit.plan("stones") == LandmarkKit.plan("stones"), "a plan is stable")
	print("test_landmark_kit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run to see it fail**

Run: `timeout 300 godot --headless --path . -s tests/test_landmark_kit.gd 2>&1 | tail -3`.

- [ ] **Step 3: `scenes/world/landmark_kit.gd`**

Model it on `lair_kit.gd` (read `_ruins` and `_graveyard` there for the part shapes: `{"part": "box"|"prism"|"lean"|"cone"|"disc", "role": <palette key>, "shade": 0..2, "pos": Vector3, "size": Vector3, "yaw": float, "tilt": float}`), one palette, six small plans, half a lair's radius:

```gdscript
# Landmark dioramas — small, cheap, one palette: the kit's parts arranged six
# ways. Half a lair's footprint, because a shrine is not a warren.
#   scenes/world/lair_kit.gd is the pattern; kit_parts.gd the vocabulary.
extends RefCounted

const KitParts = preload("res://scenes/world/kit_parts.gd")

const RADIUS := 8.0
const HEIGHT := 12.0
const PALETTE := {
	"ground": Color("5a5540"), "stone": Color("8f8a7b"), "dark": Color("3a352c"),
	"wood": Color("5a4630"), "moss": Color("5a6340"), "cloth": Color("8c5a3c"),
}

static func has(kind: String) -> bool:
	return kind in ["ruins", "shrine", "stones", "hut", "wreck", "tower"]

static func plan(kind: String) -> Array:
	if not has(kind):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("landmark/%s" % kind)
	var parts: Array = []
	match kind:
		"ruins": _ruins(parts, rng)
		"shrine": _shrine(parts)
		"stones": _stones(parts, rng)
		"hut": _hut(parts)
		"wreck": _wreck(parts, rng)
		"tower": _tower(parts)
	KitParts.apron(parts, "ground", RADIUS * 1.1)
	return parts

static func build(kind: String) -> Node3D:
	return KitParts.assemble(plan(kind), PALETTE, "landmark-" + kind)

static func triangles(kind: String) -> int:
	return KitParts.triangles(plan(kind))

static func _box(parts: Array, role: String, shade: int, pos: Vector3, size: Vector3, yaw := 0.0, tilt := 0.0) -> void:
	parts.append({"part": "box", "role": role, "shade": shade, "pos": pos, "size": size, "yaw": yaw, "tilt": tilt})

# Two broken walls and a fallen lintel.
static func _ruins(parts: Array, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(-0.4, 0.4)
	_box(parts, "stone", 1, Vector3(-3.5, 2.5, 0), Vector3(1.2, 5.0, 6.0), yaw)
	_box(parts, "stone", 1, Vector3(3.0, 1.5, -1.0), Vector3(1.2, 3.0, 4.0), yaw + 0.3)
	_box(parts, "stone", 2, Vector3(0.5, 0.6, 2.5), Vector3(6.0, 1.0, 1.2), yaw + 1.2, 0.15)

# An altar under a little roof.
static func _shrine(parts: Array) -> void:
	_box(parts, "stone", 1, Vector3(0, 1.0, 0), Vector3(2.4, 2.0, 1.6))
	_box(parts, "wood", 0, Vector3(-1.6, 2.2, -1.2), Vector3(0.4, 4.4, 0.4))
	_box(parts, "wood", 0, Vector3(1.6, 2.2, -1.2), Vector3(0.4, 4.4, 0.4))
	parts.append({"part": "prism", "role": "wood", "shade": 1, "pos": Vector3(0, 4.9, -0.6),
		"size": Vector3(4.4, 1.4, 3.2), "yaw": 0.0, "tilt": 0.0})

# Nine uprights in a ring, one fallen.
static func _stones(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 9:
		var a := TAU * float(i) / 9.0
		var at := Vector2(cos(a), sin(a)) * RADIUS * 0.7
		var h := rng.randf_range(2.6, 4.2)
		if i == 4:
			_box(parts, "stone", 2, Vector3(at.x, 0.5, at.y), Vector3(1.4, 1.0, h), a, 0.0)
		else:
			_box(parts, "stone", 1, Vector3(at.x, h * 0.5, at.y), Vector3(1.4, h, 1.0), a, rng.randf_range(-0.08, 0.08))

# A hut with a cone of thatch and a woodpile.
static func _hut(parts: Array) -> void:
	_box(parts, "wood", 0, Vector3(0, 1.6, 0), Vector3(4.6, 3.2, 4.0))
	parts.append({"part": "cone", "role": "moss", "shade": 1, "pos": Vector3(0, 4.4, 0),
		"size": Vector3(6.0, 2.6, 6.0), "yaw": 0.0, "tilt": 0.0})
	_box(parts, "wood", 1, Vector3(3.6, 0.6, -1.5), Vector3(1.6, 1.2, 2.4))

# A wagon on its side, wheels off.
static func _wreck(parts: Array, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(-0.3, 0.3)
	parts.append({"part": "lean", "role": "wood", "shade": 0, "pos": Vector3(0, 1.4, 0),
		"size": Vector3(5.5, 2.4, 2.8), "yaw": yaw, "tilt": 0.9})
	parts.append({"part": "disc", "role": "dark", "shade": 1, "pos": Vector3(3.6, 0.2, 1.8),
		"size": Vector3(2.0, 0.3, 2.0), "yaw": 0.0, "tilt": 0.0})
	_box(parts, "cloth", 0, Vector3(-2.5, 0.3, -1.5), Vector3(2.4, 0.5, 1.8), yaw + 0.5)

# A square tower, the top broken.
static func _tower(parts: Array) -> void:
	_box(parts, "stone", 1, Vector3(0, HEIGHT * 0.5, 0), Vector3(3.6, HEIGHT, 3.6))
	_box(parts, "stone", 2, Vector3(0.9, HEIGHT + 0.8, 0.9), Vector3(1.6, 1.6, 1.6))
	_box(parts, "dark", 0, Vector3(0, 1.2, 1.9), Vector3(1.0, 2.0, 0.3))
```

Check `KitParts.mesh_for`'s part names (`box`, `prism`, `lean`, `cone`, `disc`) and the `shade` convention (`material_for` reads it) against `kit_parts.gd` before committing; adjust the sizes if a part's size axes are ordered differently from `lair_kit.gd`'s use.

- [ ] **Step 4: `scenes/world/landmarks3d.gd`**

Copy `scenes/world/lairs3d.gd`'s structure, keyed on landmarks:

```gdscript
# Landmark dioramas on the 3D map — lairs3d.gd's shape, on core/world.gd's
# landmarks: hidden until found, faded once out of sight, footprint measured
# so the marker ring fits.
extends "res://scenes/world/props3d.gd"

const LandmarkKit := preload("res://scenes/world/landmark_kit.gd")

var _dioramas := {}   # landmark id -> Node3D
var _radius := {}

func has_model(l) -> bool:
	return _dioramas.has(l.id)

func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	_radius.clear()
	for l in world.landmarks:
		if not LandmarkKit.has(l.kind):
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(LandmarkKit.build(l.kind))
		holder.visible = l.found
		_dioramas[l.id] = holder
		_radius[l.id] = footprint_of(holder)

func reposition() -> void:
	var ppos := _player_pos()
	for l in world_map.world.landmarks:
		var n: Node3D = _dioramas.get(l.id)
		if n == null:
			continue
		n.visible = l.found and _explored(l.position)
		n.position = at(l.position)
		_fade(n, not world_map.world.is_visible_now(l.position, ppos))

func footprint(l) -> float:
	return float(_radius.get(l.id, 0.0))
```

Read `lairs3d.gd` and `props3d.gd` for anything the base expects a layer to implement (a `tick`/`layer_name`, how `world_map` is set by `add_layer`) and mirror it.

In `scenes/world/world.gd`: `const Landmarks3D = preload("res://scenes/world/landmarks3d.gd")` beside `Lairs3D`; where `_lairs3d` is created and added (`_lairs3d = Lairs3D.new(); _view.add_layer(_lairs3d); _lairs3d.reset(world)`), the same three lines for `_landmarks3d` right after; every other `_lairs3d.reset(world)` / `_lairs3d.reposition()` call site (grep them) gets the `_landmarks3d` twin guarded by `if _landmarks3d != null`.

- [ ] **Step 5: Run the tests**

Run: `timeout 300 godot --headless --path . -s tests/test_landmark_kit.gd 2>&1 | tail -3` → `0 failed`.
Run: `for t in test_lair_kit test_world_ground test_world_camera test_world_fog test_world_landmarks; do SORCMERC_FAST=1 timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add scenes/world/landmark_kit.gd scenes/world/landmark_kit.gd.uid scenes/world/landmarks3d.gd scenes/world/landmarks3d.gd.uid scenes/world/world.gd tests/test_landmark_kit.gd tests/test_landmark_kit.gd.uid
git commit -m "Landmarks: six small dioramas on the map

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: A story can stand near a landmark

**Files:**
- Modify: `core/mod/story_runtime.gd` (`near` resolution ~385; the `_lair(world, id)` helper's sibling)
- Modify: `core/mod/story.gd` (the comment naming `world_ids`' kinds ~159)
- Test: `tests/test_story.gd` (one case)

**Interfaces:**
- Produces: `{"near": "<landmark id>"}` resolves to the landmark's position in every place `near` is read (the condition check and the band-spawn effect).

- [ ] **Step 1: Write the failing test**

In `tests/test_story.gd`, find how a `near` condition is tested against a settlement (a world with the player standing at a settlement and a beat `{"when": {"near": "riverhold"}}` firing) and add the same shape for a landmark: a world with `w.add_landmark(World.Landmark.new("chapel", "shrine", Vector2(300, 300)))`, the player moved to `Vector2(300, 300)`, a beat with `{"near": "chapel"}`, asserting it fires; and a validation case where a pack's `story.json` beat says `near: "chapel"` and the pack's `world.json` declares that landmark — `check(errors.is_empty(), ...)`.

- [ ] **Step 2: Run to see it fail**

Run: `timeout 300 godot --headless --path . -s tests/test_story.gd 2>&1 | tail -3`.

- [ ] **Step 3: Implement**

In `core/mod/story_runtime.gd`, beside `_lair(world, id)`:

```gdscript
static func _landmark(world, id: String):
	return world.landmark(id)
```

and everywhere `near` is resolved (`_near`'s condition check and the band-spawn effect's `at` — grep `spec["near"]` / `c["near"]`), after the lair lookup:

```gdscript
		elif _landmark(world, id) != null:
			at = _landmark(world, id).position
```

`core/mod/registry.gd`'s `_world_ids` already maps landmark ids (Task 2), so validation passes. Update the `story.gd` comment listing the id kinds.

- [ ] **Step 4: Run the tests**

Run: `for t in test_story test_mod_packs test_world_pack; do timeout 300 godot --headless --path . -s tests/$t.gd 2>&1 | tail -1; done` → all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add core/mod/story_runtime.gd core/mod/story.gd tests/test_story.gd
git commit -m "Stories: near accepts a landmark

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The robot visits

**Files:**
- Modify: `tests/drive_random.gd` (the lair block ~839; `_watch()` ~261; the coverage assertions at the end)

- [ ] **Step 1: The visit roll**

After the lair block in the decision function:

```gdscript
	# A landmark under the party's nose: visit it (and answer the first row the
	# card offers), or search the ground for a hidden one.
	if screen._place_btn != null and screen._place_btn.visible and _chance(30 + _me["nosy"] / 2):
		_saw["place:" + ("visit" if "Visit" in screen._place_btn.text else "search")] = true
		_acts += 1
		screen._place_btn.pressed.emit()
		return
	if screen._approach_card != null and screen._place_open != null:
		var rows: Array = screen._approach_card._opts
		var pick: Dictionary = rows[_d(rows.size()) - 1]
		_saw["place:" + String(pick["id"])] = true
		_acts += 1
		screen._on_place_chosen(String(pick["id"]))
		return
```

(read how the robot already answers the approach card — it presses a row button by index — and use that path instead of calling `_on_place_chosen` directly if the card exposes buttons; the row buttons emit `chosen` with the option id, which `_open_place` connected to `_on_place_chosen`.)

In `_watch()`:

```gdscript
	# A spent landmark never offers a card.
	if screen._place_open != null and screen._place_open.spent:
		fail("the card is up for a spent landmark: %s" % screen._place_open.sname)
```

- [ ] **Step 2: Run the robot on a few seeds**

Run: `for s in 5 11 23; do SORCMERC_FAST=1 SORCMERC_SEED=$s timeout 600 godot --headless --path . -s tests/drive_random.gd 2>&1 | tail -1; done` → OK each time. Print `_saw` keys at the end (the robot already prints what it exercised) and confirm at least one `place:` key appears on at least one seed; if none does on three seeds, raise the chance to `40 + nosy/2` and say so.

- [ ] **Step 3: Commit**

```bash
git add tests/drive_random.gd
git commit -m "drive_random: the robot visits landmarks

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The record, the whole suite, the PR

**Files:**
- Modify: `docs/expansion-plan.md` (append a section)

- [ ] **Step 1: Append the shipped record**

```markdown
## Landmarks — places on the map that are not a fight (2026-09-20)

Sub-project 2 of the content batch. Spec:
`docs/superpowers/specs/2026-09-20-landmarks-design.md`; plan:
`docs/superpowers/plans/2026-09-20-landmarks.md`.

The map had towns, lairs and bands, and every one of them ended in a menu or
a fight. It now has a fourth thing: six kinds of landmark — ruins, a shrine,
standing stones, a hermit's hut, a wreck, a watchtower — each a place the
party walks up to and answers with a skill the world barely used (History,
Religion, Arcana, Nature, Performance, Insight, Perception, Athletics,
Investigation). Two choices a kind and *Leave*, on the approach card as it
is; the event card names the check and the roll; one visit each. Rewards
that are not fights: a cache, a blessing (temp HP at the next fight), a
lead, a scouted fight, a safe camp, a quicker road, the map opening from a
tower, marked bands, a camp kit, a free identification. The deed pays
`LANDMARK_XP` × (ring + 1); DC and cache climb with the ring.

Visible kinds are found by walking; the hut and the tower the way lairs are
— the same Survival roll (`WorldLairs.search_roll`, split out so there is
one), on their own button, or bought at the inn at half a lair's price. The
three builders place 1.5 per lair; a pack's `world.json` declares its own
under `landmarks`, validated at scan time; a story's `near` can name one.
Saved under `landmarks`; an old save loads with none.

### Still open

- No art yet for the cards (`assets/generated/landmark-<kind>.png`); the card
  draws without it.
- Trainers belong to downtime (B2); a landmark that wakes something to threat
  clocks (C1).
- A landmark never restocks.
```

- [ ] **Step 2: Run the whole suite**

Run: `tools/run_tests.sh 2>&1 | tail -5` → every test green (several minutes).

- [ ] **Step 3: Commit, push, update the PR**

```bash
git add docs/expansion-plan.md
git commit -m "Landmarks: the shipped record

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push
gh pr ready 138
gh pr edit 138 --title "Landmarks: places on the map that are not a fight" --body "$(cat <<'PRBODY'
Sub-project 2 of the content batch. Six kinds of landmark on the open-world map — ruins, shrine, standing stones, hermit's hut, wreck, watchtower — each a place with two skill-gated choices and *Leave*, answered once, with rewards that are not fights.

- `core/landmarks.gd`: the kinds, the cards, the checks, the doors, placement, discovery. The approach card asks; the event card answers with the roll named.
- Found by walking (visible kinds) or the lair's Survival roll / an inn lead (hidden kinds); placed by the three builders and by packs' `world.json`; saved under a new key; a story's `near` can name one; six small dioramas on the 3D map.
- Rewards: cache, blessing (temp HP next fight), lead, scouted, safe camp, quicker road, map reveal, marked bands, camp kit, free identification; milestone XP for the deed; DC and cache scale with the region ring.

Spec: `docs/superpowers/specs/2026-09-20-landmarks-design.md`. Plan: `docs/superpowers/plans/2026-09-20-landmarks.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PRBODY
)"
```
