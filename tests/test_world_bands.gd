# #163 — the spawn table and the population cap. The model only, headless.
#   godot --headless --path . -s tests/test_world_bands.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBands = preload("res://core/world_bands.gd")
const WorldSave = preload("res://core/world_save.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _seeded(w: World, name: String) -> void:
	var cap := WorldBands.cap(w)
	check(WorldBands.population(w) == cap, "%s: filled to the cap (%d of %d)" % [name, WorldBands.population(w), cap])
	var start: Vector2 = w.player().position
	var spawned := 0
	for p in w.parties:
		if not p.ai.has("kind"):
			continue
		spawned += 1
		check(not w.is_water(p.position), "%s: %s is on dry ground" % [name, p.id])
		check(p.position.distance_to(start) >= WorldBands.START_GAP, "%s: %s clear of the start" % [name, p.id])
		for s in w.settlements:
			check(s.position.distance_to(p.position) >= WorldBands.SETTLEMENT_GAP, "%s: %s clear of %s" % [name, p.id, s.id])
		check(not p.troops.is_empty(), "%s: %s has troops" % [name, p.id])
		if WorldAI.is_monster(p.faction):
			check(Regions.suits(Regions.band_of(w, p.position), p.faction), "%s: %s (%s) is in its own country" % [name, p.id, p.faction])
			check(p.ai["behavior"] == "hunt", "%s: %s hunts" % [name, p.id])
		else:
			var wps: Array = p.ai["waypoints"]
			check(wps.size() >= 2, "%s: %s has >= 2 waypoints" % [name, p.id])
			var own := false
			for wp in wps:
				var on_town := false
				for s in w.settlements:
					if s.position == wp:
						on_town = true
						own = own or s.faction == p.faction
				check(on_town, "%s: %s waypoint on a town" % [name, p.id])
			check(own, "%s: %s walks its own faction's town" % [name, p.id])
	check(spawned >= cap - 7, "%s: most of the population came from the table (%d)" % [name, spawned])

func _init() -> void:
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var small: World = scene._small_world()
	scene.free()
	_seeded(small, "small")
	check(WorldBands.cap(small) >= 3 and WorldBands.cap(small) <= 6, "small map caps near 5 (%d)" % WorldBands.cap(small))
	var large: World = LargeWorld.build()
	_seeded(large, "large")
	check(WorldBands.cap(large) >= 25 and WorldBands.cap(large) <= 38, "large map caps at 25-38 (%d)" % WorldBands.cap(large))
	var proc: World = ProceduralWorld.build(5)
	check(WorldBands.population(proc) == WorldBands.cap(proc), "a generated map is filled to its cap too (%d)" % WorldBands.cap(proc))
	var kinds := {}
	for p in large.parties:
		if p.ai.has("kind"):
			kinds[p.ai["kind"]] = true
	check(kinds.size() >= 6, "the large map shows a spread of kinds (%d)" % kinds.size())

	# no undead in the heartland, ever: 30 seeds on the large map
	var bad := 0
	for s in 30:
		var w: World = LargeWorld.build()
		for p in w.parties:
			if p.faction in ["undead", "cultist", "giant", "monstrosity"] \
					and Regions.at(w, p.position)["index"] < 2:
				bad += 1
	check(bad == 0, "frontier kinds never spawn inside the marches (%d did)" % bad)

	# determinism: same seed, same map
	var a: World = LargeWorld.build()
	var b: World = LargeWorld.build()
	var same := a.parties.size() == b.parties.size()
	for i in a.parties.size():
		same = same and a.parties[i].id == b.parties[i].id and a.parties[i].position == b.parties[i].position
	check(same, "seeding is deterministic by seed")

	# refill: one band per REFILL_MINUTES, never over the cap, far from the party
	var w2: World = LargeWorld.build()
	var pl := w2.player()
	var first: World.RoamingParty = null
	for p in w2.parties:
		if p.ai.has("kind"):
			first = p
			break
	w2.parties.erase(first)
	w2.parties.erase(w2.parties[-1])
	var rng := RNG.new(7)
	var n0 := WorldBands.population(w2)
	check(WorldBands.refill(w2, 100.0, rng) == "" and WorldBands.population(w2) == n0, "no refill before REFILL_MINUTES")
	WorldBands.refill(w2, WorldBands.REFILL_MINUTES, rng)
	check(WorldBands.population(w2) == n0 + 1, "one band after REFILL_MINUTES")
	var newest = w2.parties[-1]
	check(newest.position.distance_to(pl.position) >= WorldBands.REFILL_GAP, "the refill lands far from the party")
	check(not w2.is_explored(newest.position), "...and out of sight")
	WorldBands.refill(w2, WorldBands.REFILL_MINUTES + 1.0, rng)
	check(WorldBands.population(w2) == n0 + 1, "not another one a minute later")
	WorldBands.refill(w2, 2 * WorldBands.REFILL_MINUTES, rng)
	check(WorldBands.population(w2) == n0 + 2 and WorldBands.population(w2) == WorldBands.cap(w2), "back at the cap")
	WorldBands.refill(w2, 3 * WorldBands.REFILL_MINUTES, rng)
	check(WorldBands.population(w2) == WorldBands.cap(w2), "...and it stops there")
	# a raid band does not count
	var raiders := w2.add_party(World.RoamingParty.new("x-raiders", Vector2.ZERO, "goblinoid"))
	WorldAI.raid(raiders, Vector2.ZERO, "t", "x")
	check(WorldBands.population(w2) == WorldBands.cap(w2), "raiders are not population")

	# save round-trip of a spawned band
	var w3 = WorldSave.from_dict(WorldSave.to_dict(w2))["world"]
	var back = null
	for p in w3.parties:
		if p.id == newest.id:
			back = p
	check(back != null and back.position == newest.position and back.troops == newest.troops \
		and back.ai.get("kind") == newest.ai.get("kind") and back.ai["behavior"] == newest.ai["behavior"],
		"a spawned band survives a save")
	check(w3.bands_refilled_at == w2.bands_refilled_at, "the refill clock survives a save")

	print("test_world_bands: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
