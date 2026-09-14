# T9x: procedural world generation — a seeded alternative to the two
# hand-placed maps (World._small_world()/LargeWorld.build()). Same content
# types (one settlement per civilized race, roaming monster-faction parties,
# all five named lairs, one lake), placed by a deterministic RNG instead of
# by hand. Two real constraints, not just scattered dots: settlements keep a
# minimum distance apart (no two capitals on top of each other), and every
# monster-faction party/lair keeps its own minimum distance from every
# settlement (nothing spawns inside someone's front yard).
#
#   var w := ProceduralWorld.build(12345)   # same seed -> same map, always
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RNG = preload("res://core/rng.gd")
const Regions = preload("res://core/regions.gd")

const SPAN := 1400.0                  # settlements/lairs scatter within +/- this, world units
const MIN_SETTLEMENT_GAP := 500.0     # no two settlements closer than this
const MIN_MONSTER_GAP := 300.0        # lairs/roaming bands keep this far from every settlement
const RACES := ["human", "elf", "dwarf", "orc"]
const SETTLEMENT_KINDS := ["city", "town", "camp"]
# (id, faction, display name — "" lets Lair derive one from the id, same as
# every hand-placed world already does for goblin-warren/giant-hold).
const LAIRS := [
	["goblin-warren", "goblinoid", ""],
	["giant-hold", "giant", ""],
	["sunken-ruins", "undead", "Sunken Ruins"],
	["zombie-graveyard", "undead", "Zombie Graveyard"],
	["dragon-cave", "dragon", "Dragon's Cave"],
]
const LAKE_RADIUS := 100.0            # the one lake, same size the small map's has
const MIN_WATER_GAP := 60.0           # dry margin between the lake's edge and anything placed
const MONSTER_FACTIONS := ["bandit", "goblinoid"]
const MONSTER_BAND_COUNT := 4

static func _randf(rng) -> float:
	return float(rng.roll_die(10000) - 1) / 10000.0

static func _point(rng) -> Vector2:
	return Vector2(_randf(rng) * 2.0 - 1.0, _randf(rng) * 2.0 - 1.0) * SPAN

# Rejection-sample a point at least `gap` from everything in `taken`.
# ponytail: bounded retries, not a real spatial solver — at this map's scale
# (a handful of points across a 2800x2800 span) a miss streak long enough to
# matter would need a pathological seed; ship the last try rather than loop
# forever chasing one.
static func _place(rng, taken: Array, gap: float) -> Vector2:
	for i in 50:
		var p := _point(rng)
		var ok := true
		for t in taken:
			if p.distance_to(t) < gap:
				ok = false
				break
		if ok:
			return p
	return _point(rng)

# The same rejection sampling as _place(), but drawing from one ring around the
# anchor instead of from the whole square — how a lair ends up in the country
# its faction belongs to (D6). Falls back to the last try for the same reason
# _place() does; a ring is a smaller target, so it gets more of them.
static func _place_in_ring(rng, taken: Array, gap: float, anchor: Vector2,
		fracs: Array, ext: float) -> Vector2:
	var lo: float = float(fracs[0]) * ext
	var hi: float = maxf(lo + 1.0, float(fracs[1]) * ext)
	var p := anchor
	for i in 80:
		var ang: float = _randf(rng) * TAU
		var r: float = lo + _randf(rng) * (hi - lo)
		p = anchor + Vector2(cos(ang), sin(ang)) * r
		var ok := true
		for t in taken:
			if p.distance_to(t) < gap:
				ok = false
				break
		if ok:
			return p
	return p

static func build(seed_v: int = 0) -> World:
	var rng := RNG.new(seed_v)
	var w := World.new()
	w.origin = {"kind": "procedural", "seed": seed_v}   # the seed IS the map; keep it

	# Faction balance: exactly one settlement per civilized race, spaced apart.
	var settlement_pos: Array = []
	for race in RACES:
		var pos := _place(rng, settlement_pos, MIN_SETTLEMENT_GAP)
		settlement_pos.append(pos)
		var kind: String = SETTLEMENT_KINDS[rng.roll_die(SETTLEMENT_KINDS.size()) - 1]
		w.add_settlement(World.Settlement.new(race + "-hold", pos, race, kind))

	# The player starts next to the human settlement — same convention every
	# hand-placed world uses.
	var human_pos: Vector2 = settlement_pos[RACES.find("human")]
	w.add_party(World.RoamingParty.new("player", human_pos + Vector2(40, 40), "human", true))

	for i in MONSTER_BAND_COUNT:
		var faction: String = MONSTER_FACTIONS[rng.roll_die(MONSTER_FACTIONS.size()) - 1]
		var pos := _place(rng, settlement_pos, MIN_MONSTER_GAP)
		var band := w.add_party(World.RoamingParty.new("%s-%d" % [faction, i], pos, faction))
		band.troops = [
			{"role": "heavy", "level": 1 + rng.roll_die(3)},
			{"role": "light", "level": 1 + rng.roll_die(3)},
		]
		WorldAI.hunt(band)

	# D6: a lair goes in its faction's own country. Scattering them uniformly is
	# what made a generated map a bag of difficulty spikes — a dragon three
	# minutes from the starting town, a goblin warren out past everything. The
	# rings are anchored on the human settlement (core/regions.gd) and measured
	# against the settlements alone, which is what keeps the extent stable: every
	# lair is placed INSIDE that extent, so placing them cannot move the seams
	# they were placed against.
	var anchor: Vector2 = settlement_pos[RACES.find("human")]
	var ext := Regions.MIN_EXTENT
	for p in settlement_pos:
		ext = maxf(ext, anchor.distance_to(p))
	for entry in LAIRS:
		var band := Regions.home_band(String(entry[1]))
		var pos := _place_in_ring(rng, settlement_pos, MIN_MONSTER_GAP, anchor,
			Regions.ring_fracs(band), ext)
		w.add_lair(World.Lair.new(String(entry[0]), pos, String(entry[1]), String(entry[2])))

	# One lake — same "water is a hand-placed blob" vocabulary the other two
	# worlds use, just at a generated spot. It is placed last and against
	# everything already on the map, not only the settlements: water blocks
	# movement now (core/world.gd), so a lair or a band that happened to land
	# inside the blob would spawn unreachable, in a puddle of its own.
	var occupied: Array = settlement_pos.duplicate()
	for p in w.parties:
		occupied.append(p.position)
	for l in w.lairs:
		occupied.append(l.position)
	w.add_water(_place(rng, occupied, LAKE_RADIUS + MIN_WATER_GAP), LAKE_RADIUS)
	return w
