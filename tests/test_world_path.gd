# T-path: routing round the water. O1 refuses to walk from land into a blob and
# stops at the bank; this is the file that says a band nobody is steering finds
# its way round instead of standing there. Every leg of a route has to be dry,
# the route has to be one a party can actually walk under O1's own stepper, and
# "there is no way round" has to come back as an honest empty answer rather
# than a route through a lake.
#   godot --headless --path . -s tests/test_world_path.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldPath = preload("res://core/world_path.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

const LAKE := Vector2.ZERO
const LAKE_R := 120.0

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _lake_world() -> World:
	var w := World.new()
	w.add_water(LAKE, LAKE_R)
	return w

# A river: overlapping blobs stamped along a line, the same vocabulary the
# hand-placed maps use. Runs north-south through x = 0, from y = -300 to 300,
# so it has two ends and going round one of them is the only way across.
func _river_world() -> World:
	var w := World.new()
	for i in 21:
		w.add_water(Vector2(0, -300.0 + 30.0 * float(i)), 40.0)
	return w

func _init() -> void:
	test_clear_line()
	test_nearest_dry()
	test_a_route_is_only_offered_when_one_is_needed()
	test_a_route_round_a_lake_is_dry_and_short()
	test_a_route_is_pulled_tight()
	test_a_route_round_a_river_is_walkable()
	test_no_way_round_is_an_empty_route()
	test_the_graph_follows_the_water()
	test_the_built_in_maps_are_crossable()
	test_a_big_map_plans_in_reasonable_time()
	print("test_world_path: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_clear_line() -> void:
	var dry := World.new()
	check(WorldPath.clear_line(dry, Vector2(-999, -999), Vector2(999, 999)), "with no water every line is clear")

	var w := _lake_world()
	check(not WorldPath.clear_line(w, Vector2(-300, 0), Vector2(300, 0)), "straight through a lake is not clear")
	check(WorldPath.clear_line(w, Vector2(-300, -400), Vector2(300, -400)), "well clear of it is clear")
	check(not WorldPath.clear_line(w, Vector2(-300, 0), LAKE), "into the middle of it is not clear either")
	# The clip case a sampled test can miss and exact geometry cannot: a line
	# whose ENDS are both dry and whose middle cuts the corner of the blob.
	check(not WorldPath.clear_line(w, Vector2(-200, -100), Vector2(200, -100)),
		"a line whose ends are dry but whose middle clips the blob is blocked")
	check(WorldPath.clear_line(w, Vector2(-200, -140), Vector2(200, -140)), "...and one that just misses it is not")

	# A party stopped hard against the bank is exactly LAKE_R from the centre.
	# Without the end slack every step it could take would read as blocked by
	# the blob it is standing next to, and it could never be given a route.
	var bank := Vector2(-LAKE_R, 0)
	check(WorldPath.clear_line(w, bank, Vector2(-400, 0)), "a band on the bank can walk away from it")
	check(WorldPath.clear_line(w, bank, Vector2(-LAKE_R - 20.0, 200.0)), "...and along it")
	check(not WorldPath.clear_line(w, bank, Vector2(LAKE_R, 0)), "...but not across it")

func test_nearest_dry() -> void:
	var w := _lake_world()
	check(WorldPath.nearest_dry(w, Vector2(300, 0)) == Vector2(300, 0), "a dry point is handed back untouched")
	var out := WorldPath.nearest_dry(w, Vector2(40, 0))
	check(not w.is_water(out), "a point in the lake comes back on land")
	check(out.y == 0.0 and out.x > LAKE_R, "...pushed straight out the near side, not teleported")
	check(not w.is_water(WorldPath.nearest_dry(w, LAKE)), "even dead centre, where no direction is nearer")

	# Overlapping blobs: leaving one can drop you in the next, so it repeats.
	var r := _river_world()
	for y in [-300.0, -120.0, 0.0, 150.0, 300.0]:
		check(not r.is_water(WorldPath.nearest_dry(r, Vector2(0, y))),
			"a point mid-river at y=%d gets out of the water" % int(y))

func test_a_route_is_only_offered_when_one_is_needed() -> void:
	var dry := World.new()
	check(WorldPath.route(dry, Vector2(-300, 0), Vector2(300, 0)).is_empty(), "no water, no route")
	var w := _lake_world()
	check(WorldPath.route(w, Vector2(-300, -400), Vector2(300, -400)).is_empty(),
		"a march that is already dry gets no waypoints")
	check(WorldPath.route(w, LAKE, Vector2(300, 0)).is_empty(),
		"a party in the water is left to O1's swim-out rule")
	check(WorldPath.route(w, Vector2(-300, 0), LAKE).is_empty(),
		"and a goal in the water has no dry point to route to")

func test_a_route_round_a_lake_is_dry_and_short() -> void:
	var w := _lake_world()
	var from := Vector2(-300, 0)
	var to := Vector2(300, 0)
	var r := WorldPath.route(w, from, to)
	check(not r.is_empty(), "a march through the lake earns a route")
	check(r[-1] == to, "...that ends where it was going")
	var at := from
	var walked := 0.0
	for wp in r:
		check(not w.is_water(wp), "every waypoint is on dry land")
		check(WorldPath.clear_line(w, at, wp), "every leg is a dry straight line")
		walked += at.distance_to(wp)
		at = wp
	# Round a circle rather than through it: half the circumference plus the
	# two tangents is ~1.3x the straight line here. Anything near 2x means the
	# path is wandering, and the string-pull is not doing its job.
	check(walked < from.distance_to(to) * 1.6, "the detour is a detour, not a tour (%.0f vs %.0f)"
		% [walked, from.distance_to(to)])
	var again := WorldPath.route(w, from, to)
	check(again.size() == r.size() and again[0].is_equal_approx(r[0]), "the same question gets the same answer")

func test_a_route_is_pulled_tight() -> void:
	var w := _river_world()
	var from := Vector2(-200, 0)
	var to := Vector2(200, 0)
	var r := WorldPath.route(w, from, to)
	check(r.size() >= 2, "rounding a river takes more than one corner")
	# The string-pull aims at the furthest waypoint still in sight, so by
	# construction the one after it cannot be visible from where you stood.
	var at := from
	for i in r.size() - 1:
		check(not WorldPath.clear_line(w, at, r[i + 1]),
			"waypoint %d is not one the band could have skipped" % i)
		at = r[i]

func test_a_route_round_a_river_is_walkable() -> void:
	# The claim that matters: not that a list of points exists, but that a band
	# handed it by world_ai.gd gets to the far bank under O1's own stepper.
	var w := _river_world()
	var band := w.add_party(World.RoamingParty.new("goblins", Vector2(-200, 0), "goblinoid"))
	var target := Vector2(200, 0)
	WorldAI.patrol(band, [target, Vector2(-200, 0)])
	var dry := true
	var arrived := false
	for i in 400:
		WorldAI.update(w)
		w.tick(1.0)
		dry = dry and not w.is_water(band.position)
		if band.position.is_equal_approx(target):
			arrived = true
			break
	check(dry, "the band stayed out of the river the whole way")
	check(arrived, "the band crossed the river by going round its end")
	check(band.position.x > 40.0, "...and really is on the far bank")

func test_no_way_round_is_an_empty_route() -> void:
	# A goal walled in by water. There is no path, and the honest answer is no
	# path — the caller then falls back to O1's march-at-it-and-stop, which is
	# what a band did before there was a pathfinder at all.
	var w := World.new()
	var keep := Vector2(500, 0)
	for i in 24:
		var a := TAU * float(i) / 24.0
		w.add_water(keep + Vector2(cos(a), sin(a)) * 90.0, 30.0)
	check(not w.is_water(keep), "the middle of the ring is dry (there is somewhere to stand)")
	check(WorldPath.route(w, Vector2(-200, 0), keep).is_empty(), "but no route reaches it")
	check(WorldPath.route(w, keep, Vector2(-200, 0)).is_empty(), "and none leaves it either")

	# A band told to go there does the old thing rather than nothing.
	var band := w.add_party(World.RoamingParty.new("beasts", Vector2(-200, 0), "beast"))
	WorldAI.patrol(band, [keep, Vector2(-200, 0)])
	for i in 60:
		WorldAI.update(w)
		w.tick(1.0)
		check(not w.is_water(band.position), "a band with nowhere to go still never wades in")
	check(band.position.x > -200.0, "...it walks as far as the water and stops there")

func test_the_graph_follows_the_water() -> void:
	# The graph is cached on the water it was built from, so a world that grows
	# a lake has to get a new one rather than a stale answer.
	var w := _lake_world()
	var from := Vector2(-300, -400)
	var to := Vector2(300, -400)
	check(WorldPath.route(w, from, to).is_empty(), "the northern line is clear to begin with")
	var before: int = WorldPath.graph_size(w)["nodes"]
	w.add_water(Vector2(0, -400), 90.0)
	check(WorldPath.graph_size(w)["nodes"] > before, "adding a blob adds its bank to the graph")
	var r := WorldPath.route(w, from, to)
	check(not r.is_empty(), "and the line that is now blocked gets routed")
	var at := from
	for wp in r:
		check(WorldPath.clear_line(w, at, wp), "round the new blob as well as the old lake")
		at = wp

func test_the_built_in_maps_are_crossable() -> void:
	_check_map("small", _small_world())
	_check_map("large", LargeWorld.build())
	# Non-zero seeds on purpose: RNG.new(0) means "seed off the clock", so
	# ProceduralWorld.build(0) is a different map every run and this case would
	# quietly assert a different number of things each time.
	for seed_v in [1, 3, 42, 12345]:
		_check_map("procedural(%d)" % seed_v, ProceduralWorld.build(seed_v))

# Every band on the map, aimed at every settlement on it: either the line is
# already dry or there is a route, and every leg of that route is dry. This is
# the reachability claim the hand-placed maps quietly rely on — a hunter whose
# target sits over the river is the bug this whole change is about.
func _check_map(label: String, w) -> void:
	for p in w.parties:
		if w.is_water(p.position):
			continue           # the swim-out rule owns this one
		for s in w.settlements:
			if WorldPath.clear_line(w, p.position, s.position):
				continue
			var r := WorldPath.route(w, p.position, s.position)
			check(not r.is_empty(), "%s: %s can find a way to %s" % [label, p.id, s.id])
			var at: Vector2 = p.position
			for wp in r:
				check(WorldPath.clear_line(w, at, wp), "%s: %s -> %s has only dry legs" % [label, p.id, s.id])
				at = wp
			if not r.is_empty():
				check(r[-1] == s.position, "%s: %s -> %s ends at the town" % [label, p.id, s.id])

# A guard against an accidentally quadratic-in-the-wrong-thing rewrite, not a
# benchmark: the large map's graph measures in tens of milliseconds and every
# query after it in single ones, so a second is room to spare on any machine
# that can run the rest of this suite.
func test_a_big_map_plans_in_reasonable_time() -> void:
	var w = LargeWorld.build()
	var t0 := Time.get_ticks_msec()
	WorldPath.graph_size(w)          # forces the build
	var built := Time.get_ticks_msec() - t0
	check(built < 2000, "the large map's graph builds in well under two seconds (%dms)" % built)
	var t1 := Time.get_ticks_msec()
	for i in 20:
		WorldPath.route(w, Vector2(-860, 610), Vector2(1500, 900))
	var queried := Time.get_ticks_msec() - t1
	check(queried < 2000, "and twenty routes across it take well under two seconds (%dms)" % queried)

func _small_world():
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var w = scene._small_world()
	scene.free()
	return w
