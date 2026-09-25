# A lair for every people: the map builders' last pass before the roads fill,
# placing one lair in the home country of each faction that has none there.
#
# Until 2026-09-25 every map the game builds held the same five lairs — a
# goblin warren, a giant hold, two graveyards and a dragon's cave — so of the
# fifteen factions core/site.gd has a lair boss for, four could ever be met at
# the bottom of one. The cult's voice, the only enemy that casts from real
# slots (core/enemy_casters.gd), stood at the bottom of a lair no map had. The
# design audit (docs/audit-game-design.md §8.3) asked for a lair per home
# faction; the owner said yes to every one of them.
#
#   WorldHomes.homeless(world)            # home factions with no lair in their home country
#   WorldHomes.fill(world, seed, gap)     # place one for each; returns the new lairs
#   WorldHomes.backfill(world)            # an old save of a built map: fill as its builder would
#
# "Home" is core/regions.gd's word: the shallowest band a faction appears in
# (Regions.home_band), read as a country — a dragon's cave in the Unmapped is
# a dragon at home, because the Unmapped is the Far Deeps' outer half. Only
# factions with a home get one: `soldier` lives nowhere on Regions.HOMES and
# stays a thing met on the road.
#
# Placement is the procedural builder's own shape, a rejection sampler inside
# the home band's ring (Regions.ring), with the constraints every other placed
# thing on the map already keeps: clear of towns by the builder's gap, of other
# lairs and landmarks, and of the water. It samples INSIDE the map's measured
# extent, so filling cannot move the seams it placed against (Regions.extent
# reads lairs). Seeded by the caller — each builder passes its own fixed seed,
# the procedural one its map seed — so the same map is the same map.
#
# Why a pass and not five more rows in each builder's list: the three builders
# place differently (two by hand, one by ring), and a hand-placed row cannot
# know where the seams of a map land until the map is built. Asking "whose
# country has no lair in it" after the fact answers the question the audit
# asked, on any map, including a builder added later.
#
# What this does NOT own: what a lair is or does (core/world_lairs.gd, core/
# site.gd), which faction lives where (core/regions.gd), how a lair draws
# (scenes/world/lairs3d.gd, which falls back to a kit by faction for an id it
# has no model for), or content packs. A pack's map is its author's, and a
# pack that wants a cult lair places one; nothing here runs on a pack world.
extends RefCounted

const World = preload("res://core/world.gd")
const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")
const RNG = preload("res://core/rng.gd")

# One lair per people, named for what is at the bottom of it (core/site.gd's
# FACTION_BOSS, or campaign.gd's BOSS_POOL for a faction with a board). The
# four factions the builders already place keep their own ids; an entry here
# for them is only used on a map that somehow lacks one.
const LAIRS := {
	"bandit": ["cutthroat-hollow", "Cutthroat Hollow"],
	"beast": ["the-tangle", "The Tangle"],
	"kobold": ["scale-pits", "The Scale Pits"],
	"orc": ["tusk-camp", "The Tusk Camp"],
	"gnoll": ["the-boneyard", "The Boneyard"],
	"cultist": ["quiet-chapel", "The Quiet Chapel"],
	"monstrosity": ["the-roost", "The Roost"],
	"elemental": ["restless-hill", "The Restless Hill"],
	"construct": ["silent-foundry", "The Silent Foundry"],
	"fey": ["green-hollow", "The Green Hollow"],
	"goblinoid": ["goblin-warren", ""],
	"giant": ["giant-hold", ""],
	"undead": ["zombie-graveyard", "Zombie Graveyard"],
	"dragon": ["dragon-cave", "Dragon's Cave"],
}

# Clearances, in world units. LAIR_GAP keeps two dioramas (radius ~15, and a
# lair's DISCOVER_RADIUS of 60) from reading as one site; LANDMARK_GAP is
# core/landmarks.gd's own; WATER_GAP is a dry margin past the bank, the
# procedural builder's MIN_WATER_GAP.
const LAIR_GAP := 150.0
const LANDMARK_GAP := 120.0
const WATER_GAP := 60.0
const TRIES := 200
# A hand-placed map's towns sit closer together than a generated one's, and its
# near ring is small (the small map's heartland is ~395 units round the start).
# The builder passes its own gap; this is the default, and the fallback halves
# it once before giving up, the way _place_in_ring() ships its last try rather
# than loop.
const TOWN_GAP := 150.0


static func has_home(faction: String) -> bool:
	for band in Regions.HOMES:
		if Regions.HOMES[band].has(faction):
			return true
	return false


# Whether some lair of this faction stands in its home country.
static func housed(world, faction: String) -> bool:
	var home: String = Regions.home_band(faction)
	for l in world.lairs:
		if l.faction == faction and Regions.within(world, l.position, home):
			return true
	return false


# In Scaler.FACTIONS order, which is the order they are placed in — so adding a
# faction to the end of that list moves no lair that was already placed.
static func homeless(world) -> Array:
	var out: Array = []
	for f in Scaler.FACTIONS:
		if has_home(String(f)) and not housed(world, String(f)):
			out.append(String(f))
	return out


static func fill(world, seed: int, town_gap := TOWN_GAP) -> Array:
	var rng := RNG.new(maxi(1, seed))
	var placed: Array = []
	for f in homeless(world):
		var r: Array = Regions.ring(world, Regions.home_band(f))
		var pos = _spot(world, rng, r, town_gap)
		if pos == null:
			pos = _spot(world, rng, r, town_gap * 0.5)
		if pos == null:
			continue          # no room on this map: tests/test_world_homes.gd says so if it ever happens
		var entry: Array = LAIRS.get(f, ["%s-lair" % f, ""])
		var id: String = _free_id(world, String(entry[0]))
		# A second lair under a taken id takes its name from the id ("Zombie
		# Graveyard 2") rather than sharing the first one's.
		var l = world.add_lair(World.Lair.new(id, pos, f, String(entry[1]) if id == String(entry[0]) else ""))
		# The raid clock starts now, not at day 0 — the rule core/world_save.gd
		# keeps for an old save's lairs, and the one that matters for backfill():
		# ten lairs dug on day ten must not all set out on the first frame.
		l.raid_at = world.clock.elapsed
		placed.append(l)
	return placed


# Which builder made this map, and so what fill() it would have run: its seed
# and its town gap. A pack's map ("pack:<id>") is not here, on purpose.
# PROCEDURAL_TOWN_GAP is ProceduralWorld.MIN_MONSTER_GAP, which core/ may not
# preload (core/raids.gd keeps the same copy, SPREAD_TOWN_GAP).
const PROCEDURAL_TOWN_GAP := 300.0
const BUILT := {"small": [41, TOWN_GAP], "large": [43, TOWN_GAP], "procedural": [3, PROCEDURAL_TOWN_GAP]}

# A save written before this file existed holds the five old lairs and nothing
# else; core/world_save.gd calls this on load, so the peoples it lacks move in.
# On any save written since, every home faction is housed and this is a no-op.
static func backfill(world) -> Array:
	var kind: String = String(world.origin.get("kind", ""))
	if not BUILT.has(kind):
		return []
	var seed: int = int(BUILT[kind][0])
	if kind == "procedural":
		seed += int(world.origin.get("seed", 0))
	return fill(world, seed, float(BUILT[kind][1]))


static func _spot(world, rng, ring: Array, town_gap: float):
	var anchor: Vector2 = Regions.anchor(world)
	var lo: float = float(ring[0])
	var hi: float = float(ring[1])
	for _t in TRIES:
		# sqrt so the annulus is filled by area, as core/world_bands.gd does
		var d: float = sqrt(lerpf(lo * lo, hi * hi, _frac(rng)))
		var p: Vector2 = anchor + Vector2.RIGHT.rotated(_frac(rng) * TAU) * d
		if world.water_depth(p) < WATER_GAP:
			continue
		if _near(world.settlements, p, town_gap) or _near(world.lairs, p, LAIR_GAP) \
				or _near(world.landmarks, p, LANDMARK_GAP):
			continue
		return p
	return null


static func _near(things: Array, p: Vector2, gap: float) -> bool:
	for t in things:
		if t.position.distance_to(p) < gap:
			return true
	return false


# A lair id is its identity everywhere — the save, a quest's target, the
# diorama lookup — so a map that already holds this id (a pack reusing a
# builder's name) gets the next free one rather than a second lair under it.
static func _free_id(world, id: String) -> String:
	var taken := {}
	for l in world.lairs:
		taken[l.id] = true
	if not taken.has(id):
		return id
	var n := 2
	while taken.has("%s-%d" % [id, n]):
		n += 1
	return "%s-%d" % [id, n]


static func _frac(rng) -> float:
	return float(rng.roll_die(10000) - 1) / 10000.0
