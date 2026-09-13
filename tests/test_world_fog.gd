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

	print("test_world_fog: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
