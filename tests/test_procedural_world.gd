# T9x: procedural world generation. Same seed -> same map (determinism is
# the whole point of a seeded generator in this codebase); different seeds
# still respect the two real constraints — settlements spaced apart, monster
# factions/lairs kept clear of every settlement.
#   godot --headless --path . -s tests/test_procedural_world.gd
extends SceneTree

const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Regions = preload("res://core/regions.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var w1 := ProceduralWorld.build(42)
	var w2 := ProceduralWorld.build(42)
	check(w1.settlements.size() == 4, "one settlement per race (got %d)" % w1.settlements.size())
	var races := {}
	for s in w1.settlements:
		races[s.faction] = true
	check(races.size() == 4, "all four races present, no dupes/gaps (got %s)" % str(races.keys()))
	# The five named lairs, then one for each of the ten other peoples with a
	# home (core/world_homes.gd, 2026-09-25) — fifteen factions less soldier,
	# which has no home, and less the four the five already house.
	check(w1.lairs.size() == 15, "the five named lairs and ten more (got %d)" % w1.lairs.size())
	for i in ProceduralWorld.LAIRS.size():
		check(w1.lairs[i].id == String(ProceduralWorld.LAIRS[i][0]), "the named five come first (%s)" % w1.lairs[i].id)
	check(w1.player() != null, "has a player party")
	# T-water: provenance — the seed is the map, so a save has to carry it.
	check(String(w1.origin.get("kind", "")) == "procedural"
		and int(w1.origin.get("seed", -1)) == 42, "a generated world records its builder and seed")

	for i in w1.settlements.size():
		check(w1.settlements[i].position.is_equal_approx(w2.settlements[i].position),
			"same seed -> same settlement layout (settlement %d)" % i)
	for i in w1.lairs.size():
		check(w1.lairs[i].position.is_equal_approx(w2.lairs[i].position),
			"same seed -> same lair layout (lair %d)" % i)

	var w3 := ProceduralWorld.build(7)
	check(not w1.settlements[0].position.is_equal_approx(w3.settlements[0].position),
		"a different seed gives a different layout")

	# Constraints, checked on a handful of seeds rather than asserted from the
	# generator's own math — this is what a player actually sees.
	for seed_v in [1, 2, 3, 4, 5]:
		var w := ProceduralWorld.build(seed_v)
		for i in w.settlements.size():
			for j in range(i + 1, w.settlements.size()):
				check(w.settlements[i].position.distance_to(w.settlements[j].position) >= ProceduralWorld.MIN_SETTLEMENT_GAP,
					"seed %d: settlements %d/%d keep their minimum distance" % [seed_v, i, j])
		for p in w.parties:
			if p.is_player or not WorldAI.is_monster(p.faction):
				continue
			for s in w.settlements:
				check(p.position.distance_to(s.position) >= ProceduralWorld.MIN_MONSTER_GAP,
					"seed %d: monster party %s clear of %s" % [seed_v, p.id, s.id])
		for l in w.lairs:
			for s in w.settlements:
				check(l.position.distance_to(s.position) >= ProceduralWorld.MIN_MONSTER_GAP,
					"seed %d: lair %s clear of %s" % [seed_v, l.id, s.id])
		# D6: a generated map is banded, not a bag of difficulty spikes. Every
		# lair lands in the country its faction belongs to, so the dragon is
		# always the long ride and the goblins are always the near thing.
		for l in w.lairs:
			var want: String = Regions.home_band(l.faction)
			# Home is a country: the dragon's cave may sit in either half of the Far
			# Deeps (the Unmapped is their outer half, core/regions.gd).
			var got: String = Regions.band_of(w, l.position)
			check(Regions.within(w, l.position, want), "seed %d: %s (%s) sits in the %s, not the %s" % [
				seed_v, l.id, l.faction, want, got])

	print("test_procedural_world: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
