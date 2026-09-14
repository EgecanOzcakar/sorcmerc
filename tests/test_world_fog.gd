# T9x: fog of war. World.reveal()/is_explored() — a permanent-once-seen
# waypoint trail, not a per-cell grid — plus the round-trip through
# world_save.gd (an old save with no "explored" key still loads, fully
# fogged, same missing-key contract as lairs).
#   godot --headless --path . -s tests/test_world_fog.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var w := World.new()
	check(not w.is_explored(Vector2(1000, 1000)), "nothing explored yet")
	w.reveal(Vector2(0, 0))
	check(w.is_explored(Vector2(0, 0)), "revealed at the exact point")
	check(w.is_explored(Vector2(50, 0)), "revealed within VISION_RADIUS")
	check(not w.is_explored(Vector2(500, 0)), "far away stays fogged")
	check(w.explored.size() == 1, "one waypoint so far")
	w.reveal(Vector2(1, 1))
	check(w.explored.size() == 1, "a nearby reveal doesn't add a second waypoint (EXPLORE_STEP dedup)")
	w.reveal(Vector2(1000, 1000))
	check(w.explored.size() == 2, "a distant reveal adds a new waypoint")
	check(w.is_explored(Vector2(1000, 1000)), "the new area is now explored")

	var d := WorldSave.to_dict(w)
	check(d["explored"].size() == 2, "explored waypoints round-trip into the save dict")
	var loaded = WorldSave.from_dict(d)["world"]
	check(loaded.is_explored(Vector2(0, 0)) and loaded.is_explored(Vector2(1000, 1000)),
		"a loaded world keeps what was explored")

	var old_save := {"format": "sorcmerc-world", "version": 1, "settlements": [], "parties": []}
	var old_world = WorldSave.from_dict(old_save)["world"]
	check(old_world.explored.is_empty(), "an old save with no explored key loads fully fogged, not a crash")

	# --- T9x: three-tier fog — currently visible vs. remembered vs. never ---
	var w2 := World.new()
	w2.reveal(Vector2(0, 0))
	check(w2.is_visible_now(Vector2(0, 0), Vector2(0, 0)), "standing right on it is currently visible")
	check(w2.is_visible_now(Vector2(200, 0), Vector2(0, 0)), "within VISION_RADIUS of the live position counts as visible now")
	check(not w2.is_visible_now(Vector2(1000, 0), Vector2(0, 0)), "far from the live position is not currently visible")
	# The player has moved on — (0,0) is remembered (explored) but no longer
	# where they're currently standing, so it's not "visible now" from there.
	check(w2.is_explored(Vector2(0, 0)), "a place the player left is still remembered")
	check(not w2.is_visible_now(Vector2(0, 0), Vector2(2000, 2000)),
		"...but isn't currently visible once the player has walked far away")

	# --- T9x: settlements are a permanent beacon, unexplored or not ---
	var w3 := World.new()
	w3.add_settlement(World.Settlement.new("home", Vector2(500, 500), "human", "town"))
	check(not w3.is_explored(Vector2(500, 500) + Vector2(w3.SETTLEMENT_BEACON_RADIUS + 20, 0)),
		"just outside the beacon radius is still fogged")
	check(w3.is_explored(Vector2(500, 500)), "a settlement's own spot reads as explored, sight unseen")
	check(w3.near_settlement(Vector2(500, 500) + Vector2(w3.SETTLEMENT_BEACON_RADIUS - 5, 0)),
		"the beacon covers a small radius around the settlement, not just its exact point")
	check(w3.explored.is_empty(), "the beacon is settlement-derived, not a waypoint the player actually walked to")

	# --- T9y: the trail is indexed, and the index agrees with the scan ------
	# is_explored() runs once per ground cell per frame, so the flat scan over
	# every waypoint it used to do was the map's hot loop. A hash grid answers
	# the same question; these checks are that "the same question" is literal.
	var w4 := World.new()
	var trail := World.new()          # same waypoints, queried the slow way
	for i in 400:
		var step := Vector2(i * 60.0, sin(i * 0.3) * 900.0)
		w4.reveal(step)
		trail.explored.append(step)
	check(w4.explored.size() > 50, "a long walk really does bank a long trail (%d)" % w4.explored.size())
	check(w4._buckets.size() > 1, "...spread across more than one bucket (%d)" % w4._buckets.size())

	var disagreements := 0
	for i in 600:
		var probe := Vector2(sin(i * 1.7) * 26000.0, cos(i * 2.3) * 4000.0)
		if w4.is_explored(probe) != _brute_explored(w4, probe):
			disagreements += 1
	check(disagreements == 0, "the bucketed answer matches a full scan on every probe")

	# reveal()'s own dedupe went through the same index, so it has to keep the
	# same spacing rule: a waypoint is only banked when nothing is closer than
	# EXPLORE_STEP already.
	var w5 := World.new()
	w5.reveal(Vector2.ZERO)
	w5.reveal(Vector2(World.EXPLORE_STEP * 0.5, 0))
	check(w5.explored.size() == 1, "a step inside EXPLORE_STEP banks no new waypoint")
	w5.reveal(Vector2(World.EXPLORE_STEP + 1.0, 0))
	check(w5.explored.size() == 2, "...one past it does")

	# A loaded save appends to `explored` directly rather than calling reveal()
	# (see core/world_save.gd), so the index must notice a list it never saw
	# being written — otherwise a resumed world is fogged everywhere it walked.
	var w6 := World.new()
	w6.explored.append(Vector2(4000, 4000))
	check(w6.is_explored(Vector2(4000, 4000)), "a trail appended straight onto the list is still indexed")
	w6.explored.clear()
	check(not w6.is_explored(Vector2(4000, 4000)), "...and a cleared list really is forgotten")

	print("test_world_fog: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# What is_explored() used to do: the flat scan the hash grid replaced. Kept
# here as the oracle the index is checked against, not as live code.
func _brute_explored(w, pos: Vector2) -> bool:
	if w.near_settlement(pos):
		return true
	for e in w.explored:
		if e.distance_to(pos) <= World.VISION_RADIUS:
			return true
	return false
