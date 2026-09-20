# Landmarks — places on the map that are not a fight.
#
# Ruins, a shrine, standing stones, a hermit's hut, a wreck, a watchtower: each
# a place the party walks up to and answers with a skill the world barely uses
# elsewhere. Two choices a kind, one visit, rewards that are not fights.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#
# What this owns: the kinds, the names, the cards (the choices and their
# checks), placement, discovery, and the reward doors. What it does not: the
# model (core/world.gd's Landmark), the drawing (scenes/world/), the save.
#
# world.gd load()s this file for a name at call time (never preloads it), so
# this side may preload world.gd for the Landmark class.
extends RefCounted

const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")

const KINDS := ["ruins", "shrine", "stones", "hut", "wreck", "tower"]
const HIDDEN := ["hut", "tower"]   # found the way lairs are; the rest are hard to miss

const NAMES := {
	"ruins": ["the Broken Chapel", "the Old Mill", "Kessel's Folly", "the Fallen Keep", "the Weir House"],
	"shrine": ["the Wayside Shrine", "the Three Saints", "the Drowned Shrine", "Mother Ash's Altar", "the Lantern Stone"],
	"stones": ["the Nine Sisters", "the Giant's Ring", "the Sleeping Stones", "the Moot Ring", "Harrow Stones"],
	"hut": ["Old Marrow's hut", "the Charcoal Hermit's hut", "Wren Hollow", "the Bee-keeper's hut", "Gallow's Hut"],
	"wreck": ["the Broken Wagon", "a wrecked barge", "the Salt Cart", "a tinker's overturned van", "the Lost Wain"],
	"tower": ["the Old Watch", "Beacon Tower", "the Broken Spire", "the Marcher's Tower", "Crow Tower"],
}

static func is_hidden(kind: String) -> bool:
	return HIDDEN.has(kind)

# Stable per id, so a reload names the same stones the same way.
static func name_for(id: String, kind: String) -> String:
	var pool: Array = NAMES.get(kind, ["a landmark"])
	return String(pool[absi(hash("landmark|%s" % id)) % pool.size()])

# --- placement ------------------------------------------------------------

const LANDMARKS_PER_LAIR := 1.5   # the small map's six lairs get nine, the large's ~eighteen
const LANDMARK_GAP := 120.0       # from any settlement, lair or landmark — a thing of its own
const PLACE_TRIES := 200

# The built-in builders call this last: kinds round-robin off the seed, spread
# over the map the settlements span, on dry ground, the gap kept. A pack
# places its own by hand and never comes through here.
static func place(world, seed: int) -> void:
	var rng = RNG.new(maxi(1, seed))
	var count: int = ceili(LANDMARKS_PER_LAIR * world.lairs.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in world.settlements:
		lo = Vector2(minf(lo.x, s.position.x), minf(lo.y, s.position.y))
		hi = Vector2(maxf(hi.x, s.position.x), maxf(hi.y, s.position.y))
	for l in world.lairs:
		lo = Vector2(minf(lo.x, l.position.x), minf(lo.y, l.position.y))
		hi = Vector2(maxf(hi.x, l.position.x), maxf(hi.y, l.position.y))
	lo -= Vector2(LANDMARK_GAP, LANDMARK_GAP)
	hi += Vector2(LANDMARK_GAP, LANDMARK_GAP)
	var start: int = rng.roll_die(KINDS.size()) - 1
	for i in count:
		var kind: String = KINDS[(start + i) % KINDS.size()]
		for _t in PLACE_TRIES:
			var pos := Vector2(lo.x + (hi.x - lo.x) * float(rng.roll_die(1000) - 1) / 999.0,
				lo.y + (hi.y - lo.y) * float(rng.roll_die(1000) - 1) / 999.0)
			if world.is_water(pos) or not _clear(world, pos):
				continue
			world.add_landmark(World.Landmark.new("landmark-%s-%d" % [kind, i], kind, pos))
			break

static func _clear(world, pos: Vector2) -> bool:
	for s in world.settlements:
		if s.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for l in world.lairs:
		if l.position.distance_to(pos) < LANDMARK_GAP:
			return false
	for m in world.landmarks:
		if m.position.distance_to(pos) < LANDMARK_GAP:
			return false
	return true
