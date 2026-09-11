# O1: the open-world model — clock, settlements, roaming parties, movement.
#   godot --headless --path . -s tests/test_world.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_clock_advances_only_unpaused()
	test_clock_speed()
	test_party_moves_toward_goal_without_overshooting()
	test_nothing_moves_while_paused()
	test_data_shapes_and_container()
	print("test_world: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_clock_advances_only_unpaused() -> void:
	var c = World.WorldClock.new()
	check(not c.is_paused(), "a fresh clock runs")
	for i in 10:
		c.tick(0.1)
	check(is_equal_approx(c.elapsed, 1.0), "ten 0.1s ticks are one world-minute")

	c.pause()
	check(c.is_paused(), "pause() pauses")
	check(c.tick(0.5) == 0.0, "a paused tick advances nothing")
	check(is_equal_approx(c.elapsed, 1.0), "paused time is not banked")

	c.resume()
	check(not c.is_paused(), "resume() resumes")
	check(is_equal_approx(c.tick(0.25), 0.25), "tick reports the time it gave")
	check(is_equal_approx(c.elapsed, 1.25), "the clock picks up where it left off")

func test_clock_speed() -> void:
	var c = World.WorldClock.new()
	check(c.speed == 1.0, "a fresh clock runs at 1x")
	check(is_equal_approx(c.tick(1.0), 1.0), "1x advances a full second per second")

	c.set_speed(4.0)
	check(is_equal_approx(c.tick(1.0), 4.0), "4x advances four world-minutes per real second")
	c.set_speed(99.0)   # not one of the sanctioned rates
	check(c.speed == 1.0, "an unrecognized speed snaps back to 1x rather than accepting anything")

	c.cycle_speed()
	check(c.speed == 2.0, "cycling from 1x goes to 2x")
	c.cycle_speed(); c.cycle_speed()
	check(c.speed == 8.0, "...then 4x, then 8x")
	c.cycle_speed()
	check(c.speed == 1.0, "8x wraps back to 1x")

	c.pause()
	c.set_speed(8.0)
	check(c.tick(1.0) == 0.0, "speed doesn't defeat pause")

func test_party_moves_toward_goal_without_overshooting() -> void:
	var w = World.new()
	var p = w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "soldier", true))
	w.set_goal(p, Vector2(World.SPEED * 2.0, 0))   # exactly 2 world-minutes away

	w.tick(1.0)
	check(is_equal_approx(p.position.x, World.SPEED), "one second of travel is one speed-unit")
	check(not p.at_goal(), "still short of the goal halfway there")

	var toward: float = p.position.distance_to(p.goal)
	w.tick(0.5)
	check(p.position.distance_to(p.goal) < toward, "movement is toward the goal, not past it")

	w.tick(10.0)   # far more time than the trip needs
	check(p.at_goal(), "a long tick arrives")
	check(p.position.is_equal_approx(Vector2(World.SPEED * 2.0, 0)), "and does not overshoot")

	w.tick(1.0)
	check(p.position.is_equal_approx(Vector2(World.SPEED * 2.0, 0)), "an arrived party sits still")

func test_nothing_moves_while_paused() -> void:
	var w = World.new()
	var p = w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "bandit", true))
	var npc = w.add_party(World.RoamingParty.new("raiders", Vector2(10, 10), "bandit"))
	w.set_goal(p, Vector2(500, 0))
	w.set_goal(npc, Vector2(500, 500))

	w.clock.pause()
	w.tick(5.0)
	check(p.position == Vector2.ZERO, "the player does not move while paused")
	check(npc.position == Vector2(10, 10), "nor does an NPC party")
	check(w.clock.elapsed == 0.0, "and no world-time passed")

	w.clock.resume()
	w.tick(1.0)
	check(p.position.x > 0.0, "movement resumes with the clock")
	check(npc.position != Vector2(10, 10), "for every party")

func test_data_shapes_and_container() -> void:
	var w = World.new()
	var s = w.add_settlement(World.Settlement.new("riverhold", Vector2(100, -50), "soldier", "city"))
	w.add_settlement(World.Settlement.new("gorse-camp", Vector2(-20, 80), "bandit"))
	check(s.position == Vector2(100, -50), "a settlement keeps its map position")
	check(s.kind == "city" and w.settlements[1].kind == "town", "kind defaults to town")
	check(s.sname == "Riverhold", "a settlement names itself from its id")
	for st in w.settlements:
		check(Scaler.FACTIONS.has(st.faction), "%s uses the Scaler faction vocabulary" % st.id)

	var player = w.add_party(World.RoamingParty.new("player", Vector2(1, 2), "soldier", true))
	var foe = w.add_party(World.RoamingParty.new("warband", Vector2(9, 9), "goblinoid"))
	check(w.settlements.size() == 2 and w.parties.size() == 2, "the world holds what it was given")
	check(w.player() == player, "player() finds the player party")
	check(not foe.is_player, "an NPC party is not the player")
	check(foe.goal == foe.position and foe.at_goal(), "a new party's goal is where it stands")
	check(Scaler.FACTIONS.has(foe.faction), "parties are faction-tagged from the same list")
