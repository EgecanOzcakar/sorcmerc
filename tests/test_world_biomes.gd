# O-biome — the terrain layer under the map's look: the discs, the one reader
# that resolves them, the save round-trip, and the forest rule both the ground
# mask and the trees are grown from. The model only, headless.
#   godot --headless --path . -s tests/test_world_biomes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)


# A point with no disc over it is the default, and that is most of any map.
func _empty_map() -> void:
	var w := World.new()
	check(w.biomes.is_empty(), "a new world has no biome discs")
	check(w.biome_at(Vector2.ZERO) == World.DEFAULT_BIOME, "...and reads as the default everywhere")
	check(w.biome_at(Vector2(9999, -9999)) == World.DEFAULT_BIOME, "...including a long way out")


func _one_disc() -> void:
	var w := World.new()
	w.add_biome(Vector2(100, 0), 50.0, "woods")
	check(w.biome_at(Vector2(100, 0)) == "woods", "the middle of a disc is its kind")
	check(w.biome_at(Vector2(140, 0)) == "woods", "...and so is inside its edge")
	# The edge itself is OUT: biome_at wants distance/radius < 1, so a disc
	# never reaches past its own rim and two touching discs cannot both claim
	# the point where they meet.
	check(w.biome_at(Vector2(150, 0)) == World.DEFAULT_BIOME, "the rim itself is not claimed")
	check(w.biome_at(Vector2(200, 0)) == World.DEFAULT_BIOME, "and outside is the default")


# The overlap rule: of the discs that contain the point, the SMALLEST wins —
# most specific, so a small disc painted inside a big one keeps ALL of its own
# ground rather than a shrunken core of it.
#
# The whole-radius assertions below are the point of this case. An earlier rule
# here picked the smallest distance/radius instead, which reads as "whoever's
# middle is relatively nearest" and looks equivalent until you measure it: it
# gave this marsh about 30 units of its 120, because at (130, 0) the wood scores
# 130/400 = 0.325 against the marsh's 30/60 = 0.5. Painting a small biome inside
# a big one is exactly what the discs are for, so it has to survive doing it.
func _overlap_is_most_specific() -> void:
	var w := World.new()
	w.add_biome(Vector2.ZERO, 400.0, "woods")     # a big wood, first in the list
	w.add_biome(Vector2(100, 0), 60.0, "marsh")   # a small marsh inside it
	check(w.biome_at(Vector2(100, 0)) == "marsh", "the small disc wins at its own middle")
	check(w.biome_at(Vector2(130, 0)) == "marsh", "...and inside its edge")
	check(w.biome_at(Vector2(159, 0)) == "marsh", "...right out to its rim, not a shrunken core")
	check(w.biome_at(Vector2(41, 0)) == "marsh", "...on the side facing the big disc's middle too")
	check(w.biome_at(Vector2(161, 0)) == "woods", "the big disc takes over past the small one's rim")
	check(w.biome_at(Vector2(300, 0)) == "woods", "the big disc still owns the rest of itself")
	check(w.biome_at(Vector2(500, 0)) == World.DEFAULT_BIOME, "and neither owns what is outside both")
	# Order must not decide it: the same two discs the other way round.
	var w2 := World.new()
	w2.add_biome(Vector2(100, 0), 60.0, "marsh")
	w2.add_biome(Vector2.ZERO, 400.0, "woods")
	check(w2.biome_at(Vector2(100, 0)) == "marsh", "list order does not decide an overlap")
	check(w2.biome_at(Vector2(159, 0)) == "marsh", "...out to the rim either way round")
	check(w2.biome_at(Vector2(300, 0)) == "woods", "...and the big one still owns the rest")
	# Same radius: the nearer centre takes it, so the ground is split on the
	# midline rather than on which disc happens to be first in the list.
	var w3 := World.new()
	w3.add_biome(Vector2.ZERO, 100.0, "woods")
	w3.add_biome(Vector2(120, 0), 100.0, "marsh")
	check(w3.biome_at(Vector2(40, 0)) == "woods", "equal discs: the nearer middle takes the point")
	check(w3.biome_at(Vector2(80, 0)) == "marsh", "...on both sides of the midline")


func _round_trips(w, name: String) -> void:
	var back = WorldSave.from_dict(WorldSave.to_dict(w))["world"]
	check(back.biomes.size() == w.biomes.size(), "%s: every disc survives a save" % name)
	var ok := true
	for i in mini(back.biomes.size(), w.biomes.size()):
		if back.biomes[i]["position"] != w.biomes[i]["position"] \
				or not is_equal_approx(float(back.biomes[i]["radius"]), float(w.biomes[i]["radius"])) \
				or String(back.biomes[i]["kind"]) != String(w.biomes[i]["kind"]):
			ok = false
	check(ok, "%s: position, radius and kind all survive" % name)
	# The point of saving them at all: the same ground reads the same way after
	# a resume. A map whose woods move on load is a map that was not saved.
	var same := true
	for probe in [Vector2.ZERO, Vector2(300, -200), Vector2(-700, 450), Vector2(1200, 900)]:
		if back.biome_at(probe) != w.biome_at(probe):
			same = false
	check(same, "%s: the same points read the same kind after a round trip" % name)


# The contract that lets a save written before biomes existed still load.
func _old_save_has_no_biomes() -> void:
	var w := World.new()
	w.add_biome(Vector2.ZERO, 200.0, "woods")
	var d: Dictionary = WorldSave.to_dict(w)
	d.erase("biomes")
	var loaded = WorldSave.from_dict(d)
	check(loaded != null, "a save with no biomes key still loads")
	if loaded == null:
		return
	var back = loaded["world"]
	check(back.biomes.is_empty(), "...with no discs")
	check(back.biome_at(Vector2.ZERO) == World.DEFAULT_BIOME, "...and reads as the default, which is what it was")


# An unknown kind is data this build does not understand, not data to correct:
# it round-trips untouched so a build that knows it can still read the save.
func _unknown_kind_survives() -> void:
	var w := World.new()
	w.add_biome(Vector2.ZERO, 200.0, "tundra")
	var back = WorldSave.from_dict(WorldSave.to_dict(w))["world"]
	check(back.biomes.size() == 1 and String(back.biomes[0]["kind"]) == "tundra",
		"an unknown kind survives a round trip unchanged")
	check(back.biome_at(Vector2.ZERO) == "tundra", "...and is what biome_at reports")


# Every shipped map has some ground that is not the default, or the layer is
# doing nothing; and every disc names a kind this build knows.
func _shipped_maps(w, name: String) -> void:
	check(not w.biomes.is_empty(), "%s: has biome discs" % name)
	var known := true
	var positive := true
	for b in w.biomes:
		if not (String(b["kind"]) in World.BIOMES):
			known = false
		if float(b["radius"]) <= 0.0:
			positive = false
	check(known, "%s: every disc names a kind in World.BIOMES" % name)
	check(positive, "%s: every disc has a positive radius" % name)
	# Not wall-to-wall: the default fill has to survive, or the woods stop
	# reading as woods. Sampled on a coarse grid over the map's own span.
	var claimed := 0
	var total := 0
	var span := 1600.0
	for gx in 17:
		for gy in 17:
			var p := Vector2(gx - 8, gy - 8) / 8.0 * span
			total += 1
			if w.biome_at(p) != World.DEFAULT_BIOME:
				claimed += 1
	check(claimed > 0, "%s: some of the map is not the default" % name)
	check(float(claimed) / float(total) < 0.75, "%s: most of it still is (%d of %d claimed)" % [name, claimed, total])


# Biomes are stamped after every placement decision, so adding them cannot have
# moved anything a seed used to produce. Same seed, same everything.
func _procedural_is_still_deterministic() -> void:
	var a := ProceduralWorld.build(42)
	var b := ProceduralWorld.build(42)
	check(a.biomes.size() == b.biomes.size(), "the same seed makes the same number of discs")
	var same := true
	for i in mini(a.biomes.size(), b.biomes.size()):
		if a.biomes[i]["position"] != b.biomes[i]["position"] \
				or String(a.biomes[i]["kind"]) != String(b.biomes[i]["kind"]):
			same = false
	check(same, "...in the same places, of the same kinds")
	# And the rest of the map is untouched by the draws the biomes added.
	var settlements_same := true
	for i in a.settlements.size():
		if a.settlements[i].position != b.settlements[i].position:
			settlements_same = false
	check(settlements_same, "...and the settlements are where they always were")
	var c := ProceduralWorld.build(43)
	check(a.biomes[0]["position"] != c.biomes[0]["position"], "a different seed moves them")


# The marsh is put against the lake rather than anywhere at all, so it should
# actually touch the water it drains.
func _procedural_marsh_sits_on_the_lake() -> void:
	var ok := 0
	var seeds := [1, 7, 42, 99, 500]
	for s in seeds:
		var w := ProceduralWorld.build(s)
		var lake: Vector2 = w.waters[0]["position"]
		for b in w.biomes:
			if String(b["kind"]) != "marsh":
				continue
			# Its middle sits exactly on the lake's rim, which is the placement
			# rule itself rather than a consequence of it — and since every
			# radius is at least BIOME_R_MIN (220) against a LAKE_RADIUS of 100,
			# that also means the disc always covers the water it drains.
			if is_equal_approx(lake.distance_to(b["position"]), ProceduralWorld.LAKE_RADIUS) \
					and float(b["radius"]) > ProceduralWorld.LAKE_RADIUS:
				ok += 1
	check(ok == seeds.size(), "every seed's marsh touches its lake (%d of %d)" % [ok, seeds.size()])


func _init() -> void:
	_empty_map()
	_one_disc()
	_overlap_is_most_specific()
	_old_save_has_no_biomes()
	_unknown_kind_survives()
	_procedural_is_still_deterministic()
	_procedural_marsh_sits_on_the_lake()

	var proc := ProceduralWorld.build(5)
	_shipped_maps(proc, "procedural(5)")
	_round_trips(proc, "procedural(5)")
	var large := LargeWorld.build()
	_shipped_maps(large, "large")
	_round_trips(large, "large")

	print("test_world_biomes: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
