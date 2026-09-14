# T-water: water is terrain, not paint. A party never walks from land into a
# blob — not the player, not an NPC band — goals dropped in a lake snap back to
# the bank, a shoreline march slides along it instead of sticking, and a party
# that somehow starts wet can always swim out.
#   godot --headless --path . -s tests/test_world_water.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

# One lake, big enough that a party cannot round it by accident within the
# handful of ticks these cases run for.
const LAKE := Vector2.ZERO
const LAKE_R := 50.0

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _lake_world() -> World:
	var w := World.new()
	w.add_water(LAKE, LAKE_R)
	return w

func _init() -> void:
	test_is_water()
	test_march_stops_at_the_bank()
	test_goal_in_a_lake_snaps_to_land()
	test_shoreline_march_slides()
	test_a_party_in_water_can_leave()
	test_npc_bands_obey_the_bank()
	test_built_in_maps_are_dry_where_they_matter()
	print("test_world_water: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_is_water() -> void:
	var w := _lake_world()
	check(w.is_water(LAKE), "the middle of a lake is water")
	check(not w.is_water(Vector2(LAKE_R + 1.0, 0)), "just past the bank is land")
	check(not w.is_water(Vector2(LAKE_R, 0)), "the bank itself is land, so a snapped goal is standable")
	check(not World.new().is_water(Vector2(1000, 1000)), "a world with no water is dry everywhere")

func test_march_stops_at_the_bank() -> void:
	var w := _lake_world()
	var p := w.add_party(World.RoamingParty.new("player", Vector2(-200, 0), "human", true))
	w.set_goal(p, Vector2(200, 0))   # dry goal, straight through the lake
	check(p.goal == Vector2(200, 0), "a dry goal is taken as given")

	for i in 20:
		w.tick(1.0)
	check(not w.is_water(p.position), "the party never ends up in the water")
	check(p.position.x < -LAKE_R, "it stopped on the near side, it did not cross")
	check(w.water_depth(p.position) < World.WATER_STEP,
		"...and it got within one step of the bank rather than halting early")

	# One absurd tick is the tunnelling case: 8x speed and a fat frame must not
	# teleport a party over a river between two water checks.
	var before := p.position
	w.tick(100.0)
	check(p.position.is_equal_approx(before), "a huge tick does not jump the lake either")

func test_goal_in_a_lake_snaps_to_land() -> void:
	var w := _lake_world()
	var p := w.add_party(World.RoamingParty.new("player", Vector2(-200, 0), "human", true))
	w.set_goal(p, LAKE)
	check(not w.is_water(p.goal), "a goal in the middle of a lake resolves to land")
	check(p.goal.x < 0.0 and p.goal.x >= -200.0, "...on the party's own side of it")
	check(p.goal.distance_to(LAKE) - LAKE_R < World.WATER_STEP, "...right at the bank, not back at the party")

	for i in 20:
		w.tick(1.0)
	check(p.at_goal() and not w.is_water(p.position), "and the party can actually stand there")

func test_shoreline_march_slides() -> void:
	var w := _lake_world()
	# Skimming the southern bank eastward: the straight step dips into the lake,
	# but its x-only half stays dry, which is what keeps the party moving.
	var p := w.add_party(World.RoamingParty.new("player", Vector2(5, -52), "human", true))
	w.set_goal(p, Vector2(120, 0))
	var start := p.position
	for i in 40:
		w.tick(1.0)
		check(not w.is_water(p.position), "a shoreline march stays dry the whole way")
	check(p.position.distance_to(start) > LAKE_R, "the party followed the bank instead of sticking to it")
	check(p.position.x > start.x, "...and the progress was toward the goal")

func test_a_party_in_water_can_leave() -> void:
	var w := _lake_world()
	# A spawn inside a blob: an old save, a hand-placed mistake, or a lake added
	# on top of a party later. Being stuck forever would be the worse bug.
	var p := w.add_party(World.RoamingParty.new("castaway", LAKE, "human", true))
	w.set_goal(p, Vector2(200, 0))
	check(p.goal == Vector2(200, 0), "a swimmer's dry goal is untouched")
	w.tick(0.1)
	check(p.position != LAKE, "a party already in water still moves")
	for i in 20:
		w.tick(1.0)
	check(p.at_goal() and not w.is_water(p.position), "...and reaches dry land")

	# Wet party, wet goal: nothing is snapped, because there is no dry point on
	# the line to snap to — it still has to be allowed to move.
	var q := w.add_party(World.RoamingParty.new("swimmer", LAKE, "human"))
	w.set_goal(q, Vector2(10, 10))
	check(w.is_water(q.goal), "a goal with no dry line to it is left alone")
	w.tick(1.0)
	check(q.position != LAKE, "and the swimmer is not frozen by it")

func test_npc_bands_obey_the_bank() -> void:
	var w := _lake_world()
	# world_ai.gd writes party.goal directly (never through set_goal), so the
	# only thing standing between a hunting band and the lake is move_toward_goal.
	var prey := w.add_party(World.RoamingParty.new("player", Vector2(200, 0), "human", true))
	var band := w.add_party(World.RoamingParty.new("bandits", Vector2(-200, 0), "bandit"))
	WorldAI.hunt(band)
	for i in 20:
		WorldAI.update(w)
		w.tick(1.0)
		check(not w.is_water(band.position), "an NPC band never wades in either")
	check(band.goal == prey.position, "...even though its goal is set straight across the water")
	check(band.position.x < -LAKE_R, "the band is held on its own bank")

# Every map owns its own placement (ProceduralWorld picks the lake's spot; the
# two hand-placed maps stamp theirs by hand), so a band or a lair standing in
# the blob is that builder's bug to prevent — and was invisible for as long as
# water was only a texture. The small map's `bandits` really did start 22 units
# deep in its lake; moving them is what made this assertion pass.
func test_built_in_maps_are_dry_where_they_matter() -> void:
	_check_dry("small", _small_world())
	_check_dry("large", LargeWorld.build())
	for seed_v in [0, 1, 2, 3, 42, 12345]:
		_check_dry("procedural(%d)" % seed_v, ProceduralWorld.build(seed_v))

# The small map is built by the world scene rather than by a builder script, so
# it is reached through a real instance of that scene — cheaper than a second
# copy of the map that could drift out of step with the one the game ships.
func _small_world():
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var w = scene._small_world()
	scene.free()
	return w

func _check_dry(label: String, w) -> void:
	for s in w.settlements:
		check(not w.is_water(s.position), "%s: settlement %s is on dry land" % [label, s.id])
	for l in w.lairs:
		check(not w.is_water(l.position), "%s: lair %s is on dry land" % [label, l.id])
	for p in w.parties:
		check(not w.is_water(p.position), "%s: party %s starts on dry land" % [label, p.id])
