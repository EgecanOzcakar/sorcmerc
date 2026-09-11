# O3: roaming-party movement goals — patrol, wander, hunt.
#   godot --headless --path . -s tests/test_world_ai.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_patrol_cycles_waypoints_in_order()
	test_wander_stays_near_home_and_moves_on()
	test_hunt_tracks_the_nearest_hostile()
	test_civilized_parties_never_target_each_other()
	print("test_world_ai: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Run the world until `p` arrives (or we give up), returning how many ticks it took.
func _run_until_arrival(w, p, ticks := 200) -> int:
	for i in ticks:
		WorldAI.update(w, 0.1)
		w.tick(0.1)
		if p.at_goal():
			return i + 1
	return -1

func test_patrol_cycles_waypoints_in_order() -> void:
	var w = World.new()
	var wps := [Vector2(0, 0), Vector2(60, 0), Vector2(60, 60)]
	var p = w.add_party(World.RoamingParty.new("patrol", Vector2(-30, 0), "soldier"))
	WorldAI.patrol(p, wps)
	check(p.goal == wps[0], "patrol starts on its first waypoint")

	var seen: Array[Vector2] = []
	for lap in 7:                      # two full laps and a bit
		check(_run_until_arrival(w, p) > 0, "patrol reaches waypoint %d" % lap)
		seen.append(p.position)
		WorldAI.update(w)              # arrival: pick the next one
	check(seen[0] == wps[0], "first stop is waypoint 0")
	check(seen[1] == wps[1] and seen[2] == wps[2], "then 1, then 2")
	check(seen[3] == wps[0], "and it wraps back to 0")
	check(seen[4] == wps[1] and seen[5] == wps[2] and seen[6] == wps[0], "second lap is the same order")

func test_wander_stays_near_home_and_moves_on() -> void:
	var w = World.new()
	var home = w.add_settlement(World.Settlement.new("riverhold", Vector2(100, 100), "soldier", "city"))
	var p = w.add_party(World.RoamingParty.new("wanderer", home.position, "beast"))
	WorldAI.wander(p, home, 80.0, 1337)

	var goals: Array[Vector2] = []
	for trip in 5:
		WorldAI.update(w)
		goals.append(p.goal)
		check(p.goal.distance_to(home.position) <= 80.0, "wander goal %d is inside the radius" % trip)
		check(_run_until_arrival(w, p) > 0, "wanderer reaches goal %d" % trip)
	check(goals[0] != goals[1] and goals[1] != goals[2], "arriving picks a new point")

	# Same seed, same walk: the wander is reproducible.
	var w2 = World.new()
	var h2 = w2.add_settlement(World.Settlement.new("riverhold", Vector2(100, 100), "soldier", "city"))
	var p2 = w2.add_party(World.RoamingParty.new("wanderer", h2.position, "beast"))
	WorldAI.wander(p2, h2, 80.0, 1337)
	WorldAI.update(w2)
	check(p2.goal.is_equal_approx(goals[0]), "the same seed wanders the same way")

func test_hunt_tracks_the_nearest_hostile() -> void:
	var w = World.new()
	var far = w.add_settlement(World.Settlement.new("faraway", Vector2(900, 900), "soldier"))
	var hunter = w.add_party(World.RoamingParty.new("orcs", Vector2.ZERO, "orc"))
	var prey = w.add_party(World.RoamingParty.new("player", Vector2(200, 0), "soldier", true))
	var wolves = w.add_party(World.RoamingParty.new("wolves", Vector2(10, 0), "beast"))
	WorldAI.hunt(hunter)

	WorldAI.update(w)
	check(hunter.goal == prey.position, "hunts the nearest hostile, not the nearer monster")
	check(hunter.goal != wolves.position, "monsters do not hunt monsters")
	check(hunter.goal != far.position, "and the distant settlement loses to the closer party")

	# The prey moves; the goal follows it.
	prey.position = Vector2(200, 150)
	WorldAI.update(w)
	check(hunter.goal == Vector2(200, 150), "the goal re-reads the target's current position")

	# Remove the prey: the settlement is the next-nearest hostile.
	w.parties.erase(prey)
	WorldAI.update(w)
	check(hunter.goal == far.position, "with no hostile party left it marches on a settlement")

	# And it actually closes the distance under World.tick.
	var before: float = hunter.position.distance_to(hunter.goal)
	for i in 5:
		WorldAI.update(w, 0.1)
		w.tick(0.1)
	check(hunter.position.distance_to(far.position) < before, "hunting actually closes in")

func test_civilized_parties_never_target_each_other() -> void:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(50, 50), "soldier"))
	var guard = w.add_party(World.RoamingParty.new("guard", Vector2.ZERO, "soldier"))
	var other = w.add_party(World.RoamingParty.new("caravan", Vector2(20, 0), "soldier"))
	var player = w.add_party(World.RoamingParty.new("player", Vector2(30, 0), "soldier", true))
	WorldAI.hunt(guard)
	var kept: Vector2 = guard.goal

	WorldAI.update(w)
	check(guard.goal == kept, "a civilized hunter finds no targets and keeps its goal")
	check(not WorldAI.is_hostile(guard, other), "soldier is not hostile to soldier")
	check(not WorldAI.is_hostile(guard, player), "nor to the player")
	check(WorldAI.is_hostile(w.add_party(World.RoamingParty.new("gob", Vector2.ZERO, "goblinoid")), other),
		"but a goblinoid party is hostile to a soldier one")
	check(WorldAI.is_monster("bandit") and not WorldAI.is_monster("soldier"), "the monster/civilized split")
