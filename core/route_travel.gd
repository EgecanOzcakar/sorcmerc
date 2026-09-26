# #231 phase 1 — a company on the roads. The glue between the two models the
# spike built (core/world_routes.gd, the network; core/route_encounters.gd,
# who the road sends) and the world screen, so scenes/world/world.gd calls a
# handful of lines here instead of learning either model.
#
#   RouteTravel.flag_on()                   # SORCMERC_ROUTES=1: a NEW world is built as a route world
#   RouteTravel.adopt(world)                # ...which is this: the network, and nobody on the map but the company
#   RouteTravel.on(world)                   # a route world? (world.routes != null — a save remembers)
#   RouteTravel.go(world, "settlement:oakford")   # order the march; false when no known road goes there
#   RouteTravel.step(world, from)           # once a frame after the move: what the road did
#   RouteTravel.search(world, party, rng)   # the Survival check at a fork: a lair's track, a hut's path
#   RouteTravel.lead(world, landmark, e)    # a landmark's lead opens a trail (the owner's follow-up)
#   RouteTravel.camp_ambush_pct(world, pos) # a camp anywhere on a road, as risky as that stretch
#   RouteTravel.tick(world, now)            # the towns' bounties on the bands out on their roads
#
# WHAT A ROUTE WORLD IS, and why it is a property of the world rather than of
# the flag. The flag only decides how a world is BORN: a map built while it is
# set is adopted into routes. From then on world.routes is what says so, and
# the save carries it — a route run resumed without the flag is still a route
# run, and a free-roaming save loaded with the flag is still free-roaming,
# because adopting a world mid-run would strand every band, job and raid it
# holds. docs/spike-route-travel.md §6 is the plan this is phase 1 of.
#
# Phase 2 adds the bands something names, pinned to a road (core/route_pins.gd):
# a town's bounty, a raid standing at a gate (core/raids.gd pins it there — on
# the roads a raid is a town state and a band at the gate, not a band walking
# the map), a story's spawn_party, and a pack's world.json parties[] when a
# pack's map is born a route world. step() meets one when the company walks
# past where it stands; forget() puts it back when the meeting leaves it
# standing.
#
# What this does NOT own: the network or the odds (the two models), the pins
# (core/route_pins.gd), the fight (the approach card and _launch_combat,
# unchanged — a met band is an ordinary World.RoamingParty), or any drawing.
# Still left out: the minimap's roads, and co-op (the guest reads the host's
# save, routes and all, but was not driven through it).
extends RefCounted

const World = preload("res://core/world.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RoutePins = preload("res://core/route_pins.gd")
const RNG = preload("res://core/rng.gd")

const FLAG := "SORCMERC_ROUTES"

static func flag_on() -> bool:
	return OS.get_environment(FLAG) == "1"

static func on(world) -> bool:
	return world != null and world.routes != null

# A freshly built map becomes a route world: the network is built from it, every
# band the builder put down is taken off again (the issue: enemy parties do not
# spawn and are not on the map), and the company is set down on the nearest
# known road, which is the only ground it will stand on from now on.
#
# `authored` is a pack's map (world.json parties[]): its bands were put there by
# name, a story may name them, and they are pinned to the nearest road instead
# of dropped (phase 2). A built-in map's bands are the builder's filler, and go.
static func adopt(world, authored := false) -> void:
	world.routes = WorldRoutes.build(world)
	var player = world.player()
	var bands: Array = world.parties.filter(func(q): return not q.is_player)
	world.parties.clear()
	if player != null:
		world.parties.append(player)
		player.position = snap(world, player.position)
		player.goal = player.position
		player.route.clear()
	if authored:
		for b in bands:
			RoutePins.pin(world, b, "pack")
	world.fallen.clear()
	world.route_walked = 0.0

# The nearest point on a known road, or `pos` on a network with none.
static func snap(world, pos: Vector2) -> Vector2:
	var at: Dictionary = world.routes.locate(pos, true)
	return pos if at.is_empty() else at["point"]

# --- the march ------------------------------------------------------------

# Send the company to known place `to` by the known roads: back or on along the
# road it stands on, then the network. False, and nothing changed, when no known
# road goes there — the company never leaves the road (the owner's call).
static func go(world, to: String) -> bool:
	var p = world.player()
	if p == null or not on(world):
		return false
	var way: Dictionary = world.routes.path_from(p.position, to)
	if way.is_empty():
		return false
	var rest: Array[Vector2] = []
	for pt in way["points"]:
		if not pt.is_equal_approx(p.position) and (rest.is_empty() or not pt.is_equal_approx(rest[-1])):
			rest.append(pt)
	if rest.is_empty():
		p.goal = p.position
		p.route.clear()
		return true
	p.goal = rest[0]
	p.route = rest.slice(1)
	return true

# The known place nearest `pos` within `radius` world units, or "" — what a click
# on the map means. Forks are not places; a hidden place is not a place yet.
static func place_near(world, pos: Vector2, radius: float) -> String:
	if not on(world):
		return ""
	var id: String = world.routes.nearest_node(pos, true, true)
	if id == "" or pos.distance_to(world.routes.nodes[id]["position"]) > radius:
		return ""
	return id

# What a place is called, for the lines the screen says.
static func place_name(world, id: String) -> String:
	if not on(world) or not world.routes.nodes.has(id):
		return ""
	var n: Dictionary = world.routes.nodes[id]
	var ref: String = n["ref"]
	match String(n["kind"]):
		"settlement":
			for s in world.settlements:
				if s.id == ref:
					return s.sname
		"lair":
			for l in world.lairs:
				if l.id == ref:
					return l.sname
		"landmark":
			var m = world.landmark(ref)
			if m != null:
				return m.sname
	return ref.capitalize()

# --- a frame on the road ----------------------------------------------------

# Once a frame, after the move, with where the company stood before it. Returns
# what the road did, in order — most frames, nothing:
#   {"kind": "noticed", "edges": [...], "places": [names]}   a path seen leaving the road
#   {"kind": "threat", "spec": {...}, "hostile": bool}       RouteEncounters.roll() fired
#   {"kind": "meet", "spec": {...}, "hostile": false}        RouteEncounters.meet() fired
#   {"kind": "threat"|"meet", "band": band, "hostile": bool} a pinned band was walked up to
# A pinned band stood on this stretch is met first, and whatever the dice say
# — it is what that stretch fields; the road does not roll again that frame.
# Otherwise a roll is made for every RouteEncounters.STEP the odometer crosses,
# keyed on the edge and the odometer (RouteEncounters.step_key): every stretch
# walked is a roll of its own, and a reload — which restores the odometer — is
# not a reroll. The threat stream is rolled first; a meeting only on a quiet
# stretch.
static func step(world, from: Vector2) -> Array:
	var out: Array = []
	var p = world.player()
	if p == null or not on(world):
		return out
	_follow_marks(world)
	var seen: Array = world.routes.notice(p.position)
	if not seen.is_empty():
		out.append({"kind": "noticed", "edges": seen, "places": _sync(world, seen)})
	var moved := from.distance_to(p.position)
	if moved <= 0.0:
		return out
	var before: float = world.route_walked
	world.route_walked += moved
	var pinned = RoutePins.reached(world, from, p.position)
	if pinned != null:
		RoutePins.take(world, pinned)
		var hostile: bool = WorldAI.is_hostile(pinned, p)
		out.append({"kind": "threat" if hostile else "meet", "band": pinned, "hostile": hostile})
		return out
	var steps := int(floor(world.route_walked / RouteEncounters.STEP)) - int(floor(before / RouteEncounters.STEP))
	if steps <= 0:
		return out
	var at: Dictionary = world.routes.locate(p.position, false)
	var key := RouteEncounters.step_key(String(at.get("edge", "off")), world.route_walked)
	var threat := RouteEncounters.roll(world, p.position, key)
	if not threat.is_empty():
		out.append({"kind": "threat", "spec": threat, "hostile": bool(threat["hostile"])})
		return out
	var meeting := RouteEncounters.meet(world, p.position, key)
	if not meeting.is_empty():
		out.append({"kind": "meet", "spec": meeting, "hostile": false})
	return out

# What the road sent, standing on the map where the company is, so the approach
# card, the night jump and _launch_combat take it as they take any band.
static func band_for(world, spec: Dictionary):
	var p = world.player()
	var b = RouteEncounters.band(spec, p.position if p != null else Vector2.ZERO)
	world.add_party(b)
	return b

# A met band goes when the meeting is over, however it ended — fought, talked
# down, slipped, or the company beaten. It was never on the map; it does not
# linger on it, and nothing brings it back (WorldAI.respawn does not run here).
# A pinned band that is still on the map — the meeting did not put it down —
# goes back to where it stands (RoutePins.put_back).
static func forget(world, band) -> void:
	if band == null:
		return
	if RoutePins.is_pinned(band):
		RoutePins.put_back(world, band)
	elif String(band.ai.get("behavior", "")) == "met":
		world.parties.erase(band)

# A meeting the game was closed on ends with it: a save written while a road's
# card was up carries the met band, and on a route world nothing would ever
# move it or meet it again. Called when the world screen opens. A pinned band
# caught mid-meeting goes back on its spot.
static func clear_met(world) -> void:
	if not on(world):
		return
	for q in world.parties.duplicate():
		forget(world, q)

# Once a frame on a route world: the towns' bounties (RoutePins.tick).
static func tick(world, now: float) -> Array:
	return RoutePins.tick(world, now) if on(world) else []

# --- finding what is hidden -------------------------------------------------

# The hidden edges a search from here would find: a lair's track, a hut's or a
# tower's path, leaving a fork the company stands at.
static func searchable(world) -> Array:
	var p = world.player()
	if p == null or not on(world):
		return []
	return world.routes.searchable(p.position)

# The one Survival check there is (WorldLairs.search_roll), made at the fork:
# a pass reveals every hidden edge that leaves it and marks what is at the far
# end found. {} when nobody can make the check. `rng` defaults to one seeded
# off the fork and the day — one try per fork per day, the texture a lair's own
# search has always had.
static func search(world, party, rng = null) -> Dictionary:
	var edges := searchable(world)
	if edges.is_empty():
		return {}
	if rng == null:
		var from: String = world.routes.edges[edges[0]]["notice"][0]
		rng = RNG.new(maxi(1, absi(hash("routesearch|%s|%d" % [from, int(world.clock.elapsed / 1440.0)]))))
	var r: Dictionary = WorldLairs.search_roll(party, rng)
	if r.is_empty() or not r["ok"]:
		return r
	for eid in edges:
		world.routes.reveal(eid)
	r["places"] = _sync(world, edges)
	return r

# The other direction: a lair or a landmark the world has marked found by some
# other door — a rumour bought at the inn, D3's scout, a story's reveal_lair, the
# old landmark lead — gets the hidden way to it revealed too, so a place you are
# told about is a place you can walk to. Whoever marked it already said so.
static func _follow_marks(world) -> void:
	for l in world.lairs:
		if l.discovered:
			var id := WorldRoutes.poi_id("lair", l.id)
			if world.routes.nodes.has(id) and not world.routes.nodes[id]["known"]:
				world.routes.reveal_node(id)
	for m in world.landmarks:
		if m.found:
			var id := WorldRoutes.poi_id("landmark", m.id)
			if world.routes.nodes.has(id) and not world.routes.nodes[id]["known"]:
				world.routes.reveal_node(id)

# Revealed edges make places known; the world's own flags follow, so the lair
# is drawn and attackable, the landmark visitable, by the rules already there.
# Returns the names of places that just became known.
static func _sync(world, edges: Array) -> Array:
	var names: Array = []
	for eid in edges:
		var e: Dictionary = world.routes.edges.get(eid, {})
		for id in [e.get("a", ""), e.get("b", "")]:
			var n: Dictionary = world.routes.nodes.get(id, {})
			if n.is_empty() or not n["known"]:
				continue
			match String(n["kind"]):
				"lair":
					for l in world.lairs:
						if l.id == n["ref"] and not l.discovered:
							l.discovered = true
							names.append(l.sname)
				"landmark":
					var m = world.landmark(String(n["ref"]))
					if m != null and not m.found:
						m.found = true
						names.append(m.sname)
	return names

# A landmark's lead, on the roads: a trail laid from the landmark to wherever
# lead_target() points (the owner's follow-up: a landmark can make a route that
# was on no map), shown at once — the answer is somebody showing you the way.
# True when a trail was laid, and `e` says where; false leaves the caller's own
# lead (Landmarks._lead) to do what it always did.
static func lead(world, landmark, e: Dictionary) -> bool:
	if not on(world):
		return false
	var from := WorldRoutes.poi_id("landmark", landmark.id)
	var to: String = world.routes.lead_target(world, from, "%s|lead" % landmark.id)
	if to == "":
		return false
	var laid: Array = world.routes.open_route(world, from, to, "landmark:%s" % landmark.id, true)
	if laid.is_empty():
		return false
	_sync(world, laid)
	var name := place_name(world, to)
	e["lair"] = name
	e["text"] = String(e.get("text", "")) + " A way to %s that is on no map." % name
	return true

# --- camping on the road ------------------------------------------------------

# A camp can be made anywhere on a road (the owner's call), and is as risky as
# that stretch: WorldCamp's 8% scaled by the road's rate against BASE, held to
# half and three times it. A friendly town's gate is a safer night than a
# lair's doorstep. Taste bounds, spike doc §5.
const CAMP_MIN_MULT := 0.5
const CAMP_MAX_MULT := 3.0

static func camp_ambush_pct(world, pos: Vector2) -> int:
	var mult := clampf(RouteEncounters.rate(world, pos) / RouteEncounters.BASE, CAMP_MIN_MULT, CAMP_MAX_MULT)
	return maxi(1, roundi(WorldCamp.AMBUSH_CHANCE_PCT * mult))
