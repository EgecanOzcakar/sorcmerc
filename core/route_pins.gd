# #231 phase 2 — a band with a name, standing on a road.
#
# On a route world nothing walks the map: the road decides who the company
# meets (core/route_encounters.gd), and a met band is gone when the meeting is.
# That is right for the road's own traffic and wrong for every band something
# NAMES — a town's bounty (a hunt_party job points at a band by id), a raid at
# a town's gate (core/raids.gd), a band a story's spawn_party or a pack's
# world.json parties[] puts down. Those have to be somewhere, and have to stay
# there until they are dealt with. This file is where: a pinned band stands at
# one point of one road, undrawn, and the road meets it when the company walks
# past that point — whatever the dice say, because it is what that stretch
# fields. A meeting that does not put it down (a slip, a parley, a lost fight,
# a hunt whose chief got away) leaves it standing where it was, held until the
# company has walked clear, so standing on the spot does not reopen the card
# every frame. The job that names it still finds it by id (World.band()), and
# its map mark points at the road it stands on — a bounty names where.
#
#   RoutePins.pin(world, band, "story")        # stand it on the nearest known road
#   RoutePins.reached(world, from, to)         # the pinned band the company just walked up to, or null
#   RoutePins.take(world, band)                # ...onto the map for its meeting
#   RoutePins.put_back(world, band)            # ...and back on its spot if the meeting left it standing
#   RoutePins.tick(world, now)                 # the towns' bounties, posted and re-posted
#
# Kept in world.pinned, apart from world.parties, on purpose: every system
# that walks `parties` — WorldAI's steering and flight, WorldBattle's
# band-on-band fights, the fog's sightings, the figures — would otherwise have
# to learn to leave a pinned band alone. For the length of its meeting a band
# is on the map like the road's own (take()), because the approach card and
# _launch_combat take any band that is.
#
# What this does NOT own: when a raid sets out and lands (core/raids.gd, which
# pins its band at the gate), the road's odds (core/route_encounters.gd), the
# network (core/world_routes.gd), the meeting and the fight (the world screen,
# unchanged), or what a job pays (core/quest.gd).
extends RefCounted

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")

# How close the company's walk must pass a pinned band's spot to meet it: the
# map's own ENCOUNTER_RADIUS (24, scenes/world/world.gd) with room for a road's
# corner cut. Measured against the whole frame's walk, not its end point, so
# an 8x clock cannot step over a band.
const REACH := 40.0
# A band met and left standing is not met again until the company has been
# this far from it — out of the town's gate, off down the road.
const HOLD_CLEAR := 120.0

# The towns' bounties. Only towns on settled ground post them — the country
# core/raids.gd's SETTLED_BANDS names (not preloaded: raids.gd preloads this
# file). A town has one band priced at a time; the next is posted BOUNTY_EVERY
# after that one is put down, the two days WorldAI.respawn gives a band on a
# free-roaming map, plus under a day of the town's own jitter. The first goes
# up inside the first day. Taste numbers, spike doc §5.
const BOUNTY_BANDS := ["heartland", "marches"]
const BOUNTY_EVERY := 2880.0
const BOUNTY_JITTER := 1440
# Where the band stands: on a known road, this far from the town and from any
# other town, nearer its own town than any other (it is this board's problem),
# and clear of every other pinned band. BOUNTY_FAR is inside
# quest_posting.gd's hunt_party reach (700), so the town's own board posts it.
const BOUNTY_NEAR := 150.0
const BOUNTY_FAR := 500.0
# The known roads are sampled every BOUNTY_STEP for a spot that fits; one of
# those is picked, seeded. A spot that fits can be a short stretch — a town
# with one road out, and the next town not far down it.
const BOUNTY_STEP := 20.0

static func is_pinned(band) -> bool:
	return band != null and band.ai.has("pin")

# Why it stands there: "bounty", "raid", "story" or "pack".
static func why(band) -> String:
	return String(band.ai.get("pin", {}).get("why", "")) if band != null else ""

# Stand `band` on the nearest known road (any road, when none is known near
# enough to matter — a pack's band put down before the company knows a single
# way) and take it off the map. `extra` rides in its pin (a bounty's town).
# False when the world has no network at all.
static func pin(world, band, why_v: String, extra := {}) -> bool:
	if world.routes == null:
		return false
	var at: Dictionary = world.routes.locate(band.position, true)
	if at.is_empty():
		at = world.routes.locate(band.position, false)
	if at.is_empty():
		return false
	place(world, band, at["point"], String(at["edge"]), why_v, extra)
	return true

# Stand `band` at `point` on edge `edge` — for a caller that has chosen the
# spot itself (a raid at the gate, a bounty). pin() finds the spot and calls this.
static func place(world, band, point: Vector2, edge: String, why_v: String, extra := {}) -> void:
	band.position = point
	band.goal = point
	band.route.clear()
	var info := {"edge": edge, "why": why_v, "at": point}
	info.merge(extra)
	band.ai["pin"] = info
	# Nothing steers a pinned band. A raid keeps its own behavior: core/raids.gd
	# reads its phase, and Raids.turnable() the objective at the gate.
	if String(band.ai.get("behavior", "")) != "raid":
		band.ai["behavior"] = "pinned"
	world.parties.erase(band)
	if not world.pinned.has(band):
		world.pinned.append(band)

# The first pinned band whose spot the company's walk this frame (from -> to)
# passed within REACH of, or null. A held band is skipped, and let go once the
# company is HOLD_CLEAR from it. Only a walk meets one: a band pinned beside a
# company standing still waits for it to move.
static func reached(world, from: Vector2, to: Vector2):
	var hit = null
	for b in world.pinned:
		var d := _dist_to_walk(b.position, from, to)
		var info: Dictionary = b.ai["pin"]
		if bool(info.get("held", false)):
			if d > HOLD_CLEAR:
				info.erase("held")
			continue
		if hit == null and d <= REACH and from.distance_to(to) > 0.0:
			hit = b
	return hit

static func _dist_to_walk(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))

# Onto the map for its meeting, where it stands.
static func take(world, band):
	world.pinned.erase(band)
	if not world.parties.has(band):
		world.parties.append(band)
	return band

# The meeting is over. A band still on the map was not put down (put down is
# erased by whoever put it down): back on its spot, held until the company has
# walked clear. A truce's walk-away is dropped — it has nowhere to walk.
static func put_back(world, band) -> void:
	if not world.parties.has(band):
		return
	var info: Dictionary = band.ai["pin"]
	world.parties.erase(band)
	band.ai.erase("break_off")
	band.position = info.get("at", band.position)
	band.goal = band.position
	band.route.clear()
	info["held"] = true
	if not world.pinned.has(band):
		world.pinned.append(band)

# Off the map and off the road — gone home, or its reason gone.
static func drop(world, band) -> void:
	world.pinned.erase(band)
	world.parties.erase(band)

# --- the towns' bounties ------------------------------------------------------

# Once a frame on a route world: every town on settled ground whose time has
# come prices a band on its roads; a town whose band is gone starts its clock
# again. Returns the bands posted this call (the board says it; the screen need
# not).
static func tick(world, now: float) -> Array:
	var out: Array = []
	if world.routes == null:
		return out
	for s in world.settlements:
		if WorldAI.is_monster(s.faction) or not (Regions.band_of(world, s.position) in BOUNTY_BANDS):
			continue
		var due: float = float(world.bounty_due.get(s.id, _jitter(s.id, "first")))
		if due < 0.0:
			if bounty_of(world, s.id) == null:
				world.bounty_due[s.id] = now + BOUNTY_EVERY + _jitter(s.id, str(int(now)))
			continue
		if now < due:
			continue
		var b = post_bounty(world, s, now)
		if b != null:
			world.bounty_due[s.id] = -1.0
			out.append(b)
		else:
			world.bounty_due[s.id] = now + BOUNTY_EVERY   # nowhere to put one: try again later
	return out

static func _jitter(sid: String, salt: String) -> float:
	return float(absi(hash("bounty|%s|%s" % [sid, salt])) % BOUNTY_JITTER)

# The town's live bounty band — pinned, or on the map for its meeting.
static func bounty_of(world, sid: String):
	for b in world.bands():
		if why(b) == "bounty" and String(b.ai["pin"].get("town", "")) == sid:
			return b
	return null

# Price a band on one of the town's roads: a spot on a known road BOUNTY_NEAR
# to BOUNTY_FAR out, seeded off the town and the time; the band is who that
# stretch would send (RouteEncounters' monster sources there, weighted as the
# road weights them), hostile by construction. null when no spot or nobody fits.
static func post_bounty(world, s, now: float):
	var rng = RNG.new(maxi(1, absi(hash("bounty|%s|%d" % [s.id, int(now)]))))
	var spots: Array = []   # [point, edge]
	var ids: Array = world.routes.edges.keys()
	ids.sort()   # a reload's network may list its edges in another order
	for eid in ids:
		var e: Dictionary = world.routes.edges[eid]
		if not e["known"]:
			continue
		var pts: PackedVector2Array = e["points"]
		for i in range(1, pts.size()):
			var seg: float = pts[i - 1].distance_to(pts[i])
			var t := 0.0
			while t < seg:
				var pt: Vector2 = pts[i - 1].lerp(pts[i], t / seg)
				var d: float = pt.distance_to(s.position)
				if d >= BOUNTY_NEAR and d <= BOUNTY_FAR and _clear(world, pt, d):
					spots.append([pt, eid])
				t += BOUNTY_STEP
	if spots.is_empty():
		return null
	var pick_spot: Array = spots[rng.roll_die(spots.size()) - 1]
	var spot: Vector2 = pick_spot[0]
	var edge: String = pick_spot[1]
	var cands: Array = RouteEncounters.candidates(world, spot).filter(
		func(c): return WorldAI.is_monster(String(c["faction"])) and String(c["source"]) in ["country", "lair", "grudge"])
	var total := 0.0
	for c in cands:
		total += float(c["rate"])
	if total <= 0.0:
		return null
	var pick := float(rng.roll_die(10000) - 1) / 10000.0 * total
	var chosen: Dictionary = cands[-1]
	for c in cands:
		pick -= float(c["rate"])
		if pick < 0.0:
			chosen = c
			break
	var spec: Dictionary = RouteEncounters.compose(world, spot, chosen, rng, "bounty|%s|%d" % [s.id, int(now)])
	var b = RouteEncounters.band(spec, spot)
	b.id = "bounty-%s-%d" % [s.id, int(now)]
	b.ai = {}
	place(world, b, spot, edge, "bounty", {"town": s.id})
	return b

# Not on top of a town, not nearer another town than its own (`own_d` away),
# and not on top of another pinned band.
static func _clear(world, pt: Vector2, own_d: float) -> bool:
	for x in world.settlements:
		var d: float = x.position.distance_to(pt)
		if d < BOUNTY_NEAR or d < own_d:
			return false
	for b in world.bands():
		if is_pinned(b) and b.position.distance_to(pt) < HOLD_CLEAR:
			return false
	return true
