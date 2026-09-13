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
	check(w.is_explored(Vector2(50, 0)), "revealed within EXPLORE_RADIUS")
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

	print("test_world_fog: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
