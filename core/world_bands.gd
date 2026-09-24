# #163 — the roads are busy: a spawn table for roaming bands, and a population
# cap the map is filled to and kept at.
#
# The shipped maps hand-place four (small) or seven (large) bands, and the
# player rarely met one — the large map is ~3000 units across. This file keeps
# every hand-placed band and fills the rest of the map from a table:
#
#   WorldBands.seed(world, 41)          # at build: fill to cap(world)
#   WorldBands.refill(world, now, rng)  # once a frame beside WorldAI.respawn:
#                                       # one band per REFILL_MINUTES until the cap
#
# A kind is a faction, a troop template, a behaviour and a weight — the weight
# IS the frequency the issue asked for. Monster kinds go where core/regions.gd
# says their faction lives (Regions.HOMES: no undead in the heartland), at that
# ring's levels. Civilized kinds — a faction's own patrol, and a merchant
# caravan — are not ring-placed: they walk between towns, so they are put on
# the road between two of them. Combat rosters still come from Scaler
# (core/scaler.gd); `troops` here is the headcount label and the model pick,
# same as every hand-placed band.
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldPath = preload("res://core/world_path.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const EnemyNames = preload("res://core/enemy_names.gd")

# roles: the troop template; weight: relative frequency. `ai` is "hunt",
# "patrol" (own faction's towns) or "caravan" (a town to another town, any
# civilized faction). Rings for a monster kind come from Regions.HOMES.
const KINDS := [
	{"id": "bandit-gang", "faction": "bandit", "ai": "hunt", "weight": 5, "roles": ["heavy", "light", "light"]},
	{"id": "goblin-raiders", "faction": "goblinoid", "ai": "hunt", "weight": 5, "roles": ["heavy", "heavy", "light"]},
	{"id": "gnoll-pack", "faction": "gnoll", "ai": "hunt", "weight": 3, "roles": ["heavy", "light", "light", "light"]},
	{"id": "orc-warband", "faction": "orc", "ai": "hunt", "weight": 3, "roles": ["heavy", "heavy", "spellcaster"]},
	{"id": "beast-pack", "faction": "beast", "ai": "hunt", "weight": 5, "roles": ["light", "light", "light"]},
	{"id": "undead-shamble", "faction": "undead", "ai": "hunt", "weight": 2, "roles": ["heavy", "heavy", "light", "spellcaster"]},
	{"id": "kobold-skulk", "faction": "kobold", "ai": "hunt", "weight": 3, "roles": ["light", "light", "spellcaster"]},
	{"id": "cultist-procession", "faction": "cultist", "ai": "hunt", "weight": 2, "roles": ["spellcaster", "light", "light"]},
	{"id": "giant", "faction": "giant", "ai": "hunt", "weight": 1, "roles": ["heavy", "heavy"]},
	{"id": "monstrosity", "faction": "monstrosity", "ai": "hunt", "weight": 1, "roles": ["heavy", "light"]},
	{"id": "dwarf-patrol", "faction": "dwarf", "ai": "patrol", "weight": 2, "roles": ["heavy", "heavy"]},
	{"id": "elf-patrol", "faction": "elf", "ai": "patrol", "weight": 2, "roles": ["light", "spellcaster"]},
	{"id": "human-patrol", "faction": "human", "ai": "patrol", "weight": 3, "roles": ["heavy", "heavy", "light"]},
	{"id": "caravan", "faction": "", "ai": "caravan", "weight": 4, "roles": ["light", "light"]},
]

# One band per this-by-this square of the map's extent (Regions.extent): the
# large map (~1970) caps at 31, the small (~790) at 5 (plus, on either, the
# hand-placed bands and the lairs' raiders already there). Was 250 — 62 on the
# large map — and the user's look at that map was "a bit dense": every label
# overlapped another.
const CAP_AREA := 350.0
const REFILL_MINUTES := 720.0   # half a day between refills
const SETTLEMENT_GAP := 120.0   # a spawn keeps this far from every town
const START_GAP := 60.0         # ...and from the player, at build
const REFILL_GAP := 400.0       # ...and further, when it appears mid-run
const NEAR := 800.0             # a refill this close to the player is said out loud
const TRIES := 40               # placement attempts per band before giving up on it

static func cap(world) -> int:
	var ext: float = Regions.extent(world)
	return int(ext * ext / (CAP_AREA * CAP_AREA))

# Everybody who counts against the cap: not the player, not a lair's raiders
# (core/raids.gd runs those on its own clock).
static func population(world) -> int:
	var n := 0
	for p in world.parties:
		if not p.is_player and String(p.ai.get("behavior", "")) != "raid":
			n += 1
	return n

# `monster_gap` is the builder's own rule for how far a monster band keeps
# from a town, where it has one (ProceduralWorld.MIN_MONSTER_GAP); the
# civilized kinds always use SETTLEMENT_GAP, they are spawned on the road.
static func seed(world, rng_seed: int, monster_gap := SETTLEMENT_GAP) -> void:
	var rng := RNG.new(rng_seed)
	var pl = world.player()
	var start: Vector2 = Vector2.ZERO if pl == null else pl.position
	var guard := 0
	while population(world) < cap(world) and guard < cap(world) * 4:
		guard += 1
		spawn_one(world, rng, func(pos: Vector2) -> bool: return pos.distance_to(start) >= START_GAP, monster_gap)

# The line to say, or "" — a band that appeared out of sight and far off is
# nobody's news; one within NEAR of the party is.
static func refill(world, now: float, rng) -> String:
	if population(world) >= cap(world) or now - world.bands_refilled_at < REFILL_MINUTES:
		return ""
	world.bands_refilled_at = now
	var pl = world.player()
	var at: Vector2 = Vector2.ZERO if pl == null else pl.position
	var b = spawn_one(world, rng, func(pos: Vector2) -> bool:
		return pos.distance_to(at) >= REFILL_GAP and not world.is_explored(pos))
	if b == null or b.position.distance_to(at) > NEAR:
		return ""
	return "Word on the road: %s, %s of here." % [EnemyNames.band_name(b, world), _compass(b.position - at)]

# The first "<kind>-<n>" nobody holds. The number used to be a count of the
# live bands of that kind plus one, so with bandit-1 dead and bandit-2 alive the
# next spawn was a second bandit-2. A fallen monster band keeps its id to come
# back under (WorldAI.respawn), so the fallen list holds its number too. Two
# bands under one id is two bands a hunt_party job cannot tell apart: every
# lookup takes the first match, and the job could mark or pay for the wrong one.
static func _fresh_id(world, kind_id: String) -> String:
	var taken := {}
	for p in world.parties:
		taken[p.id] = true
	for f in world.fallen:
		taken[String(f["id"])] = true
	var n := 1
	while taken.has("%s-%d" % [kind_id, n]):
		n += 1
	return "%s-%d" % [kind_id, n]

# One band from the table, placed by `ok` and the standing rules; null when
# TRIES spots all failed (a map that is mostly lake, or a cap the roads cannot
# hold). `ai.kind` names the row it came from, so a save says what it was.
static func spawn_one(world, rng, ok: Callable, monster_gap := SETTLEMENT_GAP):
	var kind: Dictionary = _pick(rng)
	var gap: float = monster_gap if kind["ai"] == "hunt" else SETTLEMENT_GAP
	for _t in TRIES:
		var placed: Dictionary = _place(world, rng, kind)
		if placed.is_empty():
			continue
		var pos: Vector2 = placed["position"]
		if world.is_water(pos) or not ok.call(pos) or _near_settlement(world, pos, gap):
			continue
		var b = world.add_party(World.RoamingParty.new(_fresh_id(world, String(kind["id"])), pos, String(placed["faction"])))
		var lv: Array = Regions.at(world, pos)["levels"]
		for role in kind["roles"]:
			b.troops.append({"role": role, "level": int(lv[0]) + rng.roll_die(int(lv[1]) - int(lv[0]) + 1) - 1})
		if kind["ai"] == "hunt":
			WorldAI.hunt(b)
		else:
			WorldAI.patrol(b, placed["waypoints"])
		b.ai["kind"] = kind["id"]
		return b
	return null

static func _pick(rng) -> Dictionary:
	var total := 0
	for k in KINDS:
		total += int(k["weight"])
	var roll: int = rng.roll_die(total)
	for k in KINDS:
		roll -= int(k["weight"])
		if roll <= 0:
			return k
	return KINDS[0]

# Where this kind goes: {position, faction[, waypoints]}, or {} for a kind
# this map cannot hold (a patrol for a race with no town here).
static func _place(world, rng, kind: Dictionary) -> Dictionary:
	if kind["ai"] == "hunt":
		var rings: Array = []
		for b in Regions.BANDS:
			if Regions.suits(String(b["id"]), String(kind["faction"])):
				rings.append(String(b["id"]))
		if rings.is_empty():
			return {}
		var r: Array = Regions.ring(world, rings[rng.roll_die(rings.size()) - 1])
		# sqrt so the annulus is filled by area, not bunched at the inner seam
		var d: float = sqrt(lerpf(float(r[0]) ** 2, float(r[1]) ** 2, _frac(rng)))
		var pos: Vector2 = Regions.anchor(world) + Vector2.RIGHT.rotated(_frac(rng) * TAU) * d
		return {"position": WorldPath.nearest_dry(world, pos), "faction": kind["faction"]}
	# A patrol walks its own faction's towns (plus the nearest friendly one when
	# it has only the one, as the small map's hand-placed patrol does); a caravan
	# leaves any civilized town for another. Spawned on the first leg.
	var towns: Array = []
	for s in world.settlements:
		if s.faction == kind["faction"] or (kind["ai"] == "caravan" and WorldAI.CIVILIZED.has(s.faction)):
			towns.append(s)
	if towns.is_empty():
		return {}
	var home = towns[rng.roll_die(towns.size()) - 1]
	var away = null
	for s in world.settlements:
		if s != home and (kind["ai"] == "caravan" or towns.has(s) or towns.size() < 2) \
				and WorldAI.CIVILIZED.has(s.faction) \
				and (away == null or s.position.distance_to(home.position) < away.position.distance_to(home.position)):
			away = s
	if away == null:
		return {}
	var pos: Vector2 = home.position.lerp(away.position, 0.25 + 0.5 * _frac(rng))
	return {"position": WorldPath.nearest_dry(world, pos), "faction": home.faction,
		"waypoints": [home.position, away.position]}

static func _near_settlement(world, pos: Vector2, gap: float) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < gap:
			return true
	return false

static func _frac(rng) -> float:
	return (rng.roll_die(10000) - 1) / 10000.0

static func _compass(v: Vector2) -> String:
	var ns := "south" if v.y > 0 else "north"
	var ew := "east" if v.x > 0 else "west"
	if absf(v.y) < absf(v.x) * 0.41:
		return ew
	if absf(v.x) < absf(v.y) * 0.41:
		return ns
	return ns + "-" + ew
