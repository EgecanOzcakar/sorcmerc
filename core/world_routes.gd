# #231 — the route network: the roads the company walks, once the map stops
# being a field you can click anywhere in.
#
# The open world today is a free plane. A click anywhere is an order to go
# there, WorldPath (O16) finds the way round the water, and the only things
# that make one stretch of ground different from another are the four rings
# (core/regions.gd) and the bands walking about on it. The owner's call on
# #231 is to keep the map and drop the free plane: the company travels along
# distinct, fixed paths between the places on it, some of which are plain to
# see from the start and some of which only show themselves to a company that
# is out on the road. This file is that network. It moves nobody and draws
# nothing; docs/spike-route-travel.md is the design it is the first slice of,
# and says which later slice wires what.
#
#   var net = WorldRoutes.build(world)           # deterministic off the map alone
#   net.path("settlement:riverhold", "lair:goblin-warren")   # over known roads only
#   net.path_from(party.position, "settlement:oakford")      # from partway down one
#   net.notice(party.position)                   # hidden paths a passer-by spots
#   net.reveal_node("landmark:landmark-ruins-0") # a lead: the place, and the way to it
#   net.open_route(world, from_id, to_id, why)   # a trail nobody laid: see "routes nobody laid"
#   WorldRoutes.from_dict(net.to_dict())         # the save's round trip
#
# THE SHAPE, and why each tier is what it is.
#
#  1. ROADS, known from the start, between the settlements. Two towns get a
#     road when no third town is closer to both of them than they are to each
#     other — the relative neighbourhood graph, which is the graph people draw
#     when asked to join towns by road. It is sparse (a road does not run past
#     one town to reach the next), it has loops once there are enough towns
#     for a loop to be the short way round, it never crosses itself, and it
#     contains the minimum spanning tree, so it is connected by construction.
#
#  2. TRACKS, hidden, to the lairs. The issue first named lairs among the
#     obvious places; the owner's call (2026-09-25) is that a lair stays hidden
#     the way it is today, found by the Survival check (core/world_lairs.gd),
#     so its track is a `search` edge: walking past the fork does not show it,
#     a search from there does (searchable() / reveal()). A lair already found
#     (Lair.discovered) is on the map with its track from the start. The
#     geometry was first built as a neighbourhood graph over towns AND
#     lairs, which put a lair on the only road between two towns (Riverhold to
#     Greenmarch ran past the goblin warren's door on every trip) and left the
#     small map two town-to-town roads out of eleven edges. A lair is where you
#     go on purpose, so each now hangs off the network as a spur leaving at a
#     FORK, a node cut into the road at the point nearest it. What a lair does
#     to the roads near it is core/route_encounters.gd's business (its lure —
#     which a hidden lair casts too: a road that keeps turning up gnolls is
#     how a company learns there is something out there to search for), not
#     the geometry's.
#
#  3. PATHS, hidden, to the landmarks. A landmark is not a place anybody builds
#     a road to; it is something a company notices off the one it is on. It
#     hangs off the network the way a lair does, and its path is revealed when
#     the company walks past the fork (notice()) — "available while taking the
#     route, and showing themselves as we did in landmarks", as the issue puts
#     it. The two landmark kinds that are hidden today (Landmarks.HIDDEN: the
#     hut, the tower) keep that: their path has `search` set like a lair's
#     track, found by the same Survival roll.
#
#     Spurs hang Prim-style: of everything still to hang, the one nearest the
#     network as it now stands goes first, so a landmark past another hangs off
#     the other's path rather than off a road twice as far away.
#
#  4. BYWAYS, hidden. Tiers 2 and 3 make a tree hanging off a graph, and
#     a tree has exactly one way between two of its leaves. A byway is a
#     straight dry shortcut between two places the network makes you walk a
#     long way round to join (a detour of BYWAY_DETOUR or worse), noticed from
#     either end. Found, it is a reason to have gone out there: the next trip
#     is shorter.
#
#  5. TRAILS, laid at runtime. The four tiers above are all there on the first
#     day, found or not. A trail is not: a landmark's answer or a decision's
#     outcome opens it where none was (open_route(), open_place()), and a
#     trail that crosses a road makes a crossroads there. See "routes nobody
#     laid" below.
#
# WHAT THIS DOES NOT OWN. Who you meet on a road (core/route_encounters.gd);
# walking it (core/world.gd's move_toward_goal already walks a waypoint list,
# which is what path() returns); the drawing; the save (core/world_save.gd
# will carry to_dict() in phase 1 — a save without it rebuilds, which is the
# same network, because build() reads nothing but the map).
#
# ponytail: the network is built from where things stand at build(). A lair
# added later (core/raids.gd seeds a child) must come through attach(), which
# hangs it off the existing network like a landmark rather than re-running the
# neighbourhood graph — rebuilding would move roads the player has already
# walked. A save that carries to_dict() keeps those spurs; one that does not
# rebuilds without them and attaches them again, in the order the world lists
# them, which is the same answer as long as nothing was attached out of order.
extends RefCounted

const WorldPath = preload("res://core/world_path.gd")
const Regions = preload("res://core/regions.gd")
const Landmarks = preload("res://core/landmarks.gd")
const RNG = preload("res://core/rng.gd")

# A spur that would leave the road this close to one of the road's own ends
# leaves from that end instead: a fork a stone's throw from a town is the town.
# The same order as the visit radius (world.gd's VISIT_RADIUS, 34) so a fork is
# never so close to a town that arriving at one is arriving at the other.
const FORK_SNAP := 40.0
# How close a company has to pass to a fork to see the path leaving it. The
# encounter trigger's own radius (world.gd's ENCOUNTER_RADIUS, 24) plus a
# frame's slack at 8x: a party on the road walks straight over every fork on
# it, so this only has to survive the step size, not reach out for anything.
const NOTICE_RADIUS := 30.0
# Byways: a shortcut is only worth a hidden track when the network makes the
# trip at least this much longer than the crow flies, and only between places
# within this fraction of the map's extent of each other (a shortcut across the
# whole map is not a shortcut, it is a second road network). BYWAY_PER is the
# cap: one byway per this many places.
const BYWAY_DETOUR := 1.8
const BYWAY_REACH := 0.35
const BYWAY_PER := 6

const KINDS := ["road", "track", "path", "byway", "trail"]

var nodes := {}   # id -> {id, kind, ref, position: Vector2, known: bool, why: String}
var edges := {}   # id -> {id, a, b, kind, points: PackedVector2Array, length, known, notice: Array, search: bool, why: String}
var _adj := {}    # node id -> Array of edge ids
var _forks := 0   # the next fork's number; saved, so a spur attached after a load cannot reuse one

static func poi_id(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]

static func edge_id(a: String, b: String) -> String:
	return "%s~%s" % [a, b] if a < b else "%s~%s" % [b, a]

# --- building --------------------------------------------------------------

# load(), not new(): a script without a class_name cannot name itself in a
# static function, and preloading its own path is a cycle.
static func build(world):
	var net = load("res://core/world_routes.gd").new()
	var towns: Array = []
	for s in world.settlements:
		towns.append(net._add_node(poi_id("settlement", s.id), "settlement", s.id, s.position, true))
	net._neighbourhood(world, towns)
	net._join_components(world, towns)
	for l in world.lairs:
		net._add_node(poi_id("lair", l.id), "lair", l.id, l.position, l.discovered)
	net._attach_all(world, world.lairs.map(func(l): return poi_id("lair", l.id)))
	for m in world.landmarks:
		net._add_node(poi_id("landmark", m.id), "landmark", m.id, m.position, m.found)
	net._attach_all(world, world.landmarks.map(func(m): return poi_id("landmark", m.id)))
	net._byways(world)
	return net

func _add_node(id: String, kind: String, ref: String, pos: Vector2, known: bool, why := "") -> String:
	nodes[id] = {"id": id, "kind": kind, "ref": ref, "position": pos, "known": known, "why": why}
	if not _adj.has(id):
		_adj[id] = []
	return id

# The polyline a party walks from `a` to `b`: the straight line when it is dry,
# else WorldPath's way round the water; empty when there is none.
static func _route_points(world, a: Vector2, b: Vector2) -> PackedVector2Array:
	if WorldPath.clear_line(world, a, b):
		return PackedVector2Array([a, b])
	var way: Array[Vector2] = WorldPath.route(world, a, b)
	if way.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array([a])
	for p in way:
		pts.append(p)
	return pts

static func _length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

# `why` is empty for the map's own network and names what opened a trail
# ("landmark:landmark-ruins-3", "event:smugglers-cut") for one that was not.
func _link(id: String, a: String, b: String, kind: String, pts: PackedVector2Array,
		known: bool, notice: Array, search := false, why := "") -> String:
	# Stored a -> b in id order, so an edge reads the same whichever end built it.
	if a > b:
		var t := a; a = b; b = t
		pts.reverse()
	edges[id] = {"id": id, "a": a, "b": b, "kind": kind, "points": pts, "length": _length(pts),
		"known": known, "notice": notice, "search": search, "why": why}
	for n in [a, b]:
		if not (_adj[n] as Array).has(id):
			_adj[n].append(id)
	return id

func _unlink(id: String) -> void:
	var e: Dictionary = edges[id]
	_adj[e["a"]].erase(id)
	_adj[e["b"]].erase(id)
	edges.erase(id)

func _connect(world, a: String, b: String, kind: String, known: bool, notice: Array, search := false) -> bool:
	var pts := _route_points(world, nodes[a]["position"], nodes[b]["position"])
	if pts.is_empty():
		return false
	_link(edge_id(a, b), a, b, kind, pts, known, notice, search)
	return true

static func _kind_between(ka: String, kb: String) -> String:
	return "road" if ka == "settlement" and kb == "settlement" else "track"

# Tier 1: the relative neighbourhood graph over the known places. O(n^3) over
# a dozen or so places, built once.
func _neighbourhood(world, ids: Array) -> void:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var pa: Vector2 = nodes[ids[i]]["position"]
			var pb: Vector2 = nodes[ids[j]]["position"]
			var d := pa.distance_to(pb)
			var blocked := false
			for k in ids.size():
				if k == i or k == j:
					continue
				var pk: Vector2 = nodes[ids[k]]["position"]
				if maxf(pa.distance_to(pk), pb.distance_to(pk)) < d:
					blocked = true
					break
			if not blocked:
				_connect(world, ids[i], ids[j], _kind_between(nodes[ids[i]]["kind"], nodes[ids[j]]["kind"]), true, [])

# The neighbourhood graph is connected, but an edge WorldPath could not route
# (a place walled in by water on one side) is dropped, and that can split it.
# Join the pieces by their closest routable pair until one is left or none of
# the remaining pairs can be walked at all.
func _join_components(world, ids: Array) -> void:
	while true:
		var comp := _components(ids)
		if comp.values().max() == 0:
			return
		var best := []
		var best_d := INF
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				if comp[ids[i]] == comp[ids[j]]:
					continue
				var d: float = nodes[ids[i]]["position"].distance_to(nodes[ids[j]]["position"])
				if d < best_d and not _route_points(world, nodes[ids[i]]["position"], nodes[ids[j]]["position"]).is_empty():
					best_d = d
					best = [ids[i], ids[j]]
		if best.is_empty():
			return
		_connect(world, best[0], best[1], _kind_between(nodes[best[0]]["kind"], nodes[best[1]]["kind"]), true, [])

# id -> component index (0 for the one holding ids[0]), over every edge.
func _components(ids: Array) -> Dictionary:
	var comp := {}
	var n := 0
	for start in ids:
		if comp.has(start):
			continue
		var stack: Array = [start]
		comp[start] = n
		while not stack.is_empty():
			var u: String = stack.pop_back()
			for eid in _adj[u]:
				var e: Dictionary = edges[eid]
				var v: String = e["b"] if e["a"] == u else e["a"]
				if not comp.has(v):
					comp[v] = n
					stack.append(v)
		n += 1
	return comp

# Tier 2, Prim-style: of everything still to hang, the one nearest the network
# as it now stands goes first, so a landmark past another hangs off the other's
# path rather than off a road twice as far away. Ties go to the id.
func _attach_all(world, pending: Array) -> void:
	pending = pending.duplicate()
	pending.sort()
	while not pending.is_empty():
		var pick := ""
		var pick_at := {}
		for id in pending:
			var at := _nearest_on_network(world, nodes[id]["position"], id)
			if at.is_empty():
				continue
			if pick == "" or float(at["distance"]) < float(pick_at["distance"]):
				pick = id
				pick_at = at
		if pick == "":
			return   # nothing left can reach the network over dry ground
		pending.erase(pick)
		_hang(world, pick, pick_at)

# A place added after build() — a lair a raid seeded, a landmark a story put
# down. Hung off the network the way the builder hangs one: `known` is whether
# the place (and its spur) is on the map already, and a lair's track or a
# hidden landmark kind's path is a search either way.
func attach(world, kind: String, ref: String, pos: Vector2, known: bool) -> String:
	var id := poi_id(kind, ref)
	if nodes.has(id):
		return id
	_add_node(id, kind, ref, pos, known)
	var at := _nearest_on_network(world, pos, id)
	if not at.is_empty():
		_hang(world, id, at)
	return id

# The closest point on any edge that `pos` can walk to over dry ground, as
# {edge, seg, point, offset, distance}; {} when there is none. Points on a
# spur the node itself would own are skipped (`self_id`), and with
# `known_only` so is every edge the company has not found — a place an outcome
# shows the company hangs off a road it can walk, not off a lair's hidden track.
func _nearest_on_network(world, pos: Vector2, self_id: String, known_only := false) -> Dictionary:
	var cands: Array = []
	for eid in edges:
		var e: Dictionary = edges[eid]
		if e["a"] == self_id or e["b"] == self_id or (known_only and not e["known"]):
			continue
		var at := _closest_on(e, pos)
		at["edge"] = eid
		cands.append(at)
	cands.sort_custom(func(x, y): return float(x["distance"]) < float(y["distance"]) \
		or (float(x["distance"]) == float(y["distance"]) and String(x["edge"]) < String(y["edge"])))
	for at in cands:
		var pts := _route_points(world, at["point"], pos)
		if not pts.is_empty() and not _crosses(pts):
			return at
	return {}

# Nothing crosses. A spur or a byway that would cut across an edge already laid
# is laid somewhere else or not at all: two lines drawn over each other with no
# junction where they meet is a crossroads the player can see and the network
# cannot walk. Touching at either end is a join, not a crossing.
func _crosses(pts: PackedVector2Array) -> bool:
	for eid in edges:
		var q: PackedVector2Array = edges[eid]["points"]
		for i in range(1, pts.size()):
			for j in range(1, q.size()):
				var hit = Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], q[j - 1], q[j])
				if hit == null or hit.distance_to(pts[0]) < 1.0 or hit.distance_to(pts[-1]) < 1.0:
					continue
				return true
	return false

# The point of edge `e` nearest `pos`: {seg, point, offset (along from a), distance}.
static func _closest_on(e: Dictionary, pos: Vector2) -> Dictionary:
	var pts: PackedVector2Array = e["points"]
	var best := {}
	var walked := 0.0
	for i in range(1, pts.size()):
		var q := Geometry2D.get_closest_point_to_segment(pos, pts[i - 1], pts[i])
		var d := q.distance_to(pos)
		if best.is_empty() or d < float(best["distance"]):
			best = {"seg": i - 1, "point": q, "offset": walked + pts[i - 1].distance_to(q), "distance": d}
		walked += pts[i - 1].distance_to(pts[i])
	return best

# Hang node `id` off the network at `at`: from the nearer end when the point is
# within FORK_SNAP of it, else from a fork cut into the edge there.
func _hang(world, id: String, at: Dictionary) -> void:
	var e: Dictionary = edges[at["edge"]]
	var hub: String
	if float(at["offset"]) <= FORK_SNAP:
		hub = e["a"]
	elif float(e["length"]) - float(at["offset"]) <= FORK_SNAP:
		hub = e["b"]
	else:
		hub = _split(e, int(at["seg"]), at["point"])
	var kind: String = nodes[id]["kind"]
	var known: bool = nodes[id]["known"]
	var search := kind == "lair" or (kind == "landmark" and Landmarks.is_hidden(_landmark_kind(id)))
	# A fork cut into a hidden path is itself hidden until that path is (_split
	# gives it the edge's own `known`), so a chain of paths is found one at a time.
	_connect(world, hub, id, "track" if kind == "lair" else "path", known, [hub], search)

# Landmark ids are "landmark-<kind>-<n>" (Landmarks.place); a pack's own may not
# be, and then it is simply not one of the hidden kinds.
func _landmark_kind(id: String) -> String:
	var ref: String = nodes[id]["ref"]
	for k in Landmarks.KINDS:
		if ref.begins_with("landmark-%s-" % k):
			return k
	return ""

# Cut edge `e` at `point` (on segment `seg`) into two, joined by a new fork
# node that is known exactly when the edge was. Returns the fork's id.
func _split(e: Dictionary, seg: int, point: Vector2) -> String:
	var fork := _add_node("fork:%d" % _forks, "fork", "", point, e["known"])
	_forks += 1
	var pts: PackedVector2Array = e["points"]
	var first := pts.slice(0, seg + 1)
	first.append(point)
	var second := PackedVector2Array([point])
	second.append_array(pts.slice(seg + 1))
	var a: String = e["a"]
	var b: String = e["b"]
	var kind: String = e["kind"]
	var known: bool = e["known"]
	var notice: Array = e["notice"]
	var search: bool = e["search"]
	var why: String = e.get("why", "")
	_unlink(e["id"])
	# The half nearer the notice point keeps it; the other half is found by
	# walking the first, so it is noticed from the fork.
	var na: Array = notice.filter(func(n): return n == a)
	var nb: Array = notice.filter(func(n): return n == b)
	_link(edge_id(a, fork), a, fork, kind, first, known, na if not na.is_empty() or notice.is_empty() else [fork], search, why)
	_link(edge_id(fork, b), fork, b, kind, second, known, nb if not nb.is_empty() or notice.is_empty() else [fork], search, why)
	return fork

# Tier 3: shortcuts. Candidates are pairs of places (never forks) within reach,
# with a dry straight line between them, that the network joins only the long
# way round; the worst detours go first, and each is re-measured before it is
# laid, since an earlier byway may already have fixed it.
func _byways(world) -> void:
	var places: Array = nodes.keys().filter(func(id): return nodes[id]["kind"] != "fork")
	places.sort()
	var reach: float = BYWAY_REACH * Regions.extent(world)
	var cands: Array = []
	for i in places.size():
		var dist := _distances(places[i], false)
		for j in range(i + 1, places.size()):
			var a: String = places[i]
			var b: String = places[j]
			var d: float = nodes[a]["position"].distance_to(nodes[b]["position"])
			if d > reach or edges.has(edge_id(a, b)) or not WorldPath.clear_line(world, nodes[a]["position"], nodes[b]["position"]) \
					or _crosses(PackedVector2Array([nodes[a]["position"], nodes[b]["position"]])):
				continue
			var around: float = dist.get(b, INF)
			if around >= BYWAY_DETOUR * d:
				cands.append({"a": a, "b": b, "d": d, "saves": around - d})
	cands.sort_custom(func(x, y): return float(x["saves"]) > float(y["saves"]) \
		or (float(x["saves"]) == float(y["saves"]) and String(x["a"]) + String(x["b"]) < String(y["a"]) + String(y["b"])))
	var cap: int = maxi(1, floori(places.size() / float(BYWAY_PER)))
	var laid := 0
	for c in cands:
		if laid >= cap:
			break
		if float(_distances(c["a"], false).get(c["b"], INF)) < BYWAY_DETOUR * float(c["d"]) \
				or _crosses(PackedVector2Array([nodes[c["a"]]["position"], nodes[c["b"]]["position"]])):
			continue
		_link(edge_id(c["a"], c["b"]), c["a"], c["b"], "byway",
			PackedVector2Array([nodes[c["a"]]["position"], nodes[c["b"]]["position"]]), false, [c["a"], c["b"]])
		laid += 1

# --- routes nobody laid ------------------------------------------------------
#
# Everything above is the map's own network: built from where the places stand,
# some of it hidden, all of it there from the first day and found by walking.
# The owner's follow-up on #231 (2026-09-25): a landmark and a decision must
# also be able to OPEN a way that was never on the map and was not waiting to be
# found — the hermit shows you the goat track over the ridge, the smugglers' cut
# runs where no road does, following the tracks leads to a camp that was not
# there yesterday. So a TRAIL is an edge an outcome lays at runtime:
#
#   net.open_route(world, "landmark:landmark-ruins-3", "lair:giant-hold", "landmark:landmark-ruins-3")
#   net.lead_target(world, from_id, key)      # where a lead from here should go
#   net.scout_spot(world, from_id, key)       # a dry spot for a place nobody placed
#   net.open_place(world, "landmark", "smugglers-cave", spot, from_id, "event:smugglers")
#
# A trail goes where the outcome says, not where the neighbourhood graph or the
# Prim hang would have put a road, so it is the one tier allowed to cross
# another edge — and where it does, it makes a CROSSROADS there (both edges cut,
# a node where they meet), keeping the rule the rest of the network holds:
# nothing crosses without a node. It is saved with its `why`, and only the save
# keeps it: build() cannot re-derive what a decision did.
#
# What this does not own: WHICH landmark answer or event outcome opens a trail,
# or the new place's own world object (a World.Landmark or World.Lair the caller
# adds) — the network only needs the node. docs/spike-route-travel.md §3.1 says
# which phase wires which door.
const TRAIL := "trail"
# A lead points somewhere within this fraction of the map's extent...
const LEAD_REACH := 0.5
# ...that the known roads join at least this badly (or not at all): a trail to
# a place already a short walk away is not a discovery.
const LEAD_DETOUR := 1.4
# The pick is seeded among the best this many, so two leads read at one place
# on two occasions (two keys) need not point the same way.
const LEAD_PICK := 3
# A place nobody placed keeps this far from every node — Landmarks.LANDMARK_GAP,
# "a thing of its own" — and is looked for this many times before giving up.
const SPOT_GAP := 120.0
const SPOT_TRIES := 60
const SPOT_NEAR := 200.0
const SPOT_FAR := 450.0

# Lay a trail from node `from` to node `to`: dry (WorldPath round the water), a
# crossroads cut wherever it crosses an edge already laid. Known at once by
# default — it was shown to the company, and both ends become known with it;
# `known = false` lays it hidden, noticed from `from` like a path. Returns the
# edge ids laid in walking order ([] when there is no dry way, or when the two
# are the same node). An edge already joining the two is revealed and returned
# instead of laid twice.
func open_route(world, from: String, to: String, why := "", known := true) -> Array:
	if not nodes.has(from) or not nodes.has(to) or from == to:
		return []
	var existing := edge_id(from, to)
	if edges.has(existing):
		if known:
			reveal(existing)
		return [existing]
	var pts := _route_points(world, nodes[from]["position"], nodes[to]["position"])
	if pts.is_empty():
		return []
	var laid: Array = []
	var start := from
	var rest := pts
	for _guard in 64:
		var hit := _first_crossing(rest)
		if hit.is_empty():
			laid.append(_link(edge_id(start, to), start, to, TRAIL, rest, known, [] if known else [start], false, why))
			break
		var cross: String = hit["node"]
		if cross == "":
			var crossed: Dictionary = edges[hit["edge"]]
			cross = _split(crossed, int(_closest_on(crossed, hit["point"])["seg"]), hit["point"])
		nodes[cross]["known"] = nodes[cross]["known"] or known
		var piece := rest.slice(0, int(hit["seg"]) + 1)
		piece.append(hit["point"])
		laid.append(_link(edge_id(start, cross), start, cross, TRAIL, piece, known, [] if known else [start], false, why))
		var tail := PackedVector2Array([hit["point"]])
		tail.append_array(rest.slice(int(hit["seg"]) + 1))
		start = cross
		rest = tail
	if known:
		nodes[from]["known"] = true
		nodes[to]["known"] = true
	return laid

# The first place along `pts` where it crosses an edge, as {edge, seg, point,
# node}: `node` is the crossed edge's own end when the crossing lands on it
# (then no cut is needed), else "". Touching at either end of `pts` is a join.
func _first_crossing(pts: PackedVector2Array) -> Dictionary:
	for i in range(1, pts.size()):
		var best := {}
		var best_d := INF
		for eid in edges:
			var e: Dictionary = edges[eid]
			var q: PackedVector2Array = e["points"]
			for j in range(1, q.size()):
				var hit = Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], q[j - 1], q[j])
				if hit == null or hit.distance_to(pts[0]) < 1.0 or hit.distance_to(pts[-1]) < 1.0:
					continue
				var d: float = pts[i - 1].distance_to(hit)
				if d < best_d:
					best_d = d
					var on_end := ""
					for n in [e["a"], e["b"]]:
						if hit.distance_to(nodes[n]["position"]) < 1.0:
							on_end = n
					best = {"edge": eid, "seg": i - 1, "point": hit if on_end == "" else nodes[on_end]["position"], "node": on_end}
		if not best.is_empty():
			return best
	return {}

# Where a lead read at node `from` should point: a place (never a fork) within
# LEAD_REACH of the extent, with a dry way to it, that the known roads join
# LEAD_DETOUR times worse than the crow flies or not at all — worst first, then
# seeded among the best LEAD_PICK by `key` (the landmark and the answer, the
# event and the choice). "" when nothing qualifies: the lead has nowhere to go,
# and the caller falls back to whatever the answer paid before.
func lead_target(world, from: String, key: String) -> String:
	if not nodes.has(from):
		return ""
	var here: Vector2 = nodes[from]["position"]
	var reach: float = LEAD_REACH * Regions.extent(world)
	var known_d := _distances(from, true)
	var cands: Array = []
	for id in nodes:
		var n: Dictionary = nodes[id]
		if id == from or n["kind"] == "fork" or edges.has(edge_id(from, id)):
			continue
		var d: float = here.distance_to(n["position"])
		if d > reach or d < 1.0:
			continue
		var ratio: float = float(known_d.get(id, INF)) / d
		if ratio < LEAD_DETOUR or _route_points(world, here, n["position"]).is_empty():
			continue
		cands.append({"id": id, "ratio": ratio})
	if cands.is_empty():
		return ""
	cands.sort_custom(func(x, y): return float(x["ratio"]) > float(y["ratio"]) \
		or (float(x["ratio"]) == float(y["ratio"]) and String(x["id"]) < String(y["id"])))
	var top: int = mini(LEAD_PICK, cands.size())
	return String(cands[absi(hash("lead|%s" % key)) % top]["id"])

# A dry spot SPOT_NEAR..SPOT_FAR from node `from`, SPOT_GAP clear of every node,
# seeded off `key` — for a place an outcome puts on the map that no builder
# placed. Vector2.INF when SPOT_TRIES spots all fail.
func scout_spot(world, from: String, key: String) -> Vector2:
	if not nodes.has(from):
		return Vector2.INF
	var rng = RNG.new(maxi(1, absi(hash("spot|%s" % key))))
	var here: Vector2 = nodes[from]["position"]
	for _t in SPOT_TRIES:
		var angle := TAU * float(rng.roll_die(3600) - 1) / 3600.0
		var dist := lerpf(SPOT_NEAR, SPOT_FAR, float(rng.roll_die(1000) - 1) / 999.0)
		var pos := here + Vector2.RIGHT.rotated(angle) * dist
		if world.is_water(pos) or _route_points(world, here, pos).is_empty():
			continue
		var clear := true
		for id in nodes:
			if pos.distance_to(nodes[id]["position"]) < SPOT_GAP:
				clear = false
				break
		if clear:
			return pos
	return Vector2.INF

# Put a place on the network that was not there, with a trail to it from node
# `from` ("" hangs it off the nearest point instead, the way attach() does).
# Returns the node id; a place already on the network is left where it is.
func open_place(world, kind: String, ref: String, pos: Vector2, from := "", why := "", known := true) -> String:
	var id := poi_id(kind, ref)
	if nodes.has(id):
		return id
	_add_node(id, kind, ref, pos, known, why)
	if from == "" or open_route(world, from, id, why, known).is_empty():
		var at := _nearest_on_network(world, pos, id, known)
		if not at.is_empty():
			_hang(world, id, at)
	return id

# --- walking it ------------------------------------------------------------

func neighbours(id: String, known_only := true) -> Array:
	var out: Array = []
	for eid in _adj.get(id, []):
		var e: Dictionary = edges[eid]
		if known_only and not e["known"]:
			continue
		out.append(e["b"] if e["a"] == id else e["a"])
	return out

# Shortest network distance from `from` to every node it reaches.
func _distances(from: String, known_only: bool) -> Dictionary:
	return _dijkstra(from, "", known_only)["dist"]

# Dijkstra, O(V^2): a map holds a few dozen nodes. Stops early at `to` when one
# is given. Ties settle in id order so two equal routes always pick the same.
func _dijkstra(from: String, to: String, known_only: bool) -> Dictionary:
	var dist := {from: 0.0}
	var prev := {}
	var done := {}
	while true:
		var u := ""
		var ud := INF
		for n in dist:
			if done.has(n):
				continue
			var d: float = dist[n]
			if d < ud or (d == ud and n < u):
				u = n
				ud = d
		if u == "" or u == to:
			break
		done[u] = true
		for eid in _adj.get(u, []):
			var e: Dictionary = edges[eid]
			if known_only and not e["known"]:
				continue
			var v: String = e["b"] if e["a"] == u else e["a"]
			var nd: float = ud + float(e["length"])
			if nd < float(dist.get(v, INF)):
				dist[v] = nd
				prev[v] = eid
	return {"dist": dist, "prev": prev}

# The way from node `from` to node `to`: {nodes, edges, points, length}, where
# `points` is the whole polyline in walking order (World.move_toward_goal walks
# exactly this), or {} when the known roads do not join them.
func path(from: String, to: String, known_only := true) -> Dictionary:
	if not nodes.has(from) or not nodes.has(to):
		return {}
	var r := _dijkstra(from, to, known_only)
	if not r["dist"].has(to):
		return {}
	var node_ids: Array = [to]
	var edge_ids: Array = []
	var cur := to
	while cur != from:
		var eid: String = r["prev"][cur]
		edge_ids.push_front(eid)
		var e: Dictionary = edges[eid]
		cur = e["a"] if e["b"] == cur else e["b"]
		node_ids.push_front(cur)
	var pts := PackedVector2Array([nodes[from]["position"]])
	for i in edge_ids.size():
		var e: Dictionary = edges[edge_ids[i]]
		var seg: PackedVector2Array = e["points"]
		if e["a"] != node_ids[i]:
			seg = seg.duplicate()
			seg.reverse()
		pts.append_array(seg.slice(1))
	return {"nodes": node_ids, "edges": edge_ids, "points": pts, "length": float(r["dist"][to])}

# Where on the network `pos` is: the nearest point of the nearest edge, as
# {edge, point, offset, distance}; {} on an empty network.
func locate(pos: Vector2, known_only := true) -> Dictionary:
	var best := {}
	for eid in edges:
		var e: Dictionary = edges[eid]
		if known_only and not e["known"]:
			continue
		var at := _closest_on(e, pos)
		if best.is_empty() or float(at["distance"]) < float(best["distance"]):
			at["edge"] = eid
			best = at
	return best

# The way from wherever the company stands — partway down a road, after a
# fight stopped it there — to node `to`: back or on along the edge it is on,
# whichever is shorter, then the network. Same shape as path(); `points` starts
# at `pos` itself.
func path_from(pos: Vector2, to: String, known_only := true) -> Dictionary:
	var at := locate(pos, known_only)
	if at.is_empty() or not nodes.has(to):
		return {}
	var e: Dictionary = edges[at["edge"]]
	var best := {}
	var best_len := INF
	for end in [e["a"], e["b"]]:
		var rest := path(end, to, known_only)
		if rest.is_empty():
			continue
		var partial := _partial(e, at, end)
		var total: float = pos.distance_to(at["point"]) + _length(partial) + float(rest["length"])
		if total < best_len:
			best_len = total
			var pts := PackedVector2Array([pos])
			pts.append_array(partial)
			pts.append_array((rest["points"] as PackedVector2Array).slice(1))
			best = {"nodes": rest["nodes"], "edges": [e["id"]] + rest["edges"], "points": pts, "length": total}
	return best

# The piece of edge `e` from the located point `at` to its end node `end`.
static func _partial(e: Dictionary, at: Dictionary, end: String) -> PackedVector2Array:
	var pts: PackedVector2Array = e["points"]
	var seg: int = at["seg"]
	var out := PackedVector2Array([at["point"]])
	if end == e["b"]:
		out.append_array(pts.slice(seg + 1))
	else:
		var back := pts.slice(0, seg + 1)
		back.reverse()
		out.append_array(back)
	return out

# The known node nearest `pos`, or "" on a network with none.
func nearest_node(pos: Vector2, known_only := true, places_only := true) -> String:
	var best := ""
	var best_d := INF
	for id in nodes:
		var n: Dictionary = nodes[id]
		if (known_only and not n["known"]) or (places_only and n["kind"] == "fork"):
			continue
		var d: float = pos.distance_to(n["position"])
		if d < best_d or (d == best_d and id < best):
			best = id
			best_d = d
	return best

# --- finding the hidden ones -------------------------------------------------

# Called with the company's position as it walks: every hidden edge that is
# noticed from a known node within `radius` of it is revealed, and so is the
# place at its far end. Returns the ids revealed, in id order, so the scene can
# say "a path leaves the road here" once per path. A `search` path is skipped:
# it is found by a check (reveal()), not by walking past.
func notice(pos: Vector2, radius := NOTICE_RADIUS) -> Array:
	var out: Array = []
	var ids: Array = edges.keys()
	ids.sort()
	for eid in ids:
		var e: Dictionary = edges[eid]
		if e["known"] or e["search"]:
			continue
		for n in e["notice"]:
			if nodes[n]["known"] and pos.distance_to(nodes[n]["position"]) <= radius:
				reveal(eid)
				out.append(eid)
				break
	return out

# The hidden edges a search from here could find: the `search` ones noticed
# from a known node within `radius`. The scene offers the check while this is
# not empty, the way _check_lairs offers "Search for a lair" today.
func searchable(pos: Vector2, radius := NOTICE_RADIUS) -> Array:
	var out: Array = []
	for eid in edges:
		var e: Dictionary = edges[eid]
		if e["known"] or not e["search"]:
			continue
		for n in e["notice"]:
			if nodes[n]["known"] and pos.distance_to(nodes[n]["position"]) <= radius:
				out.append(eid)
				break
	out.sort()
	return out

# One edge, and both of its ends, known from now on. True if anything changed.
func reveal(eid: String) -> bool:
	if not edges.has(eid):
		return false
	var e: Dictionary = edges[eid]
	var changed: bool = not e["known"] or not nodes[e["a"]]["known"] or not nodes[e["b"]]["known"]
	e["known"] = true
	nodes[e["a"]]["known"] = true
	nodes[e["b"]]["known"] = true
	return changed

# A lead (the ruins' "read the stones", a rumour bought at the inn, D3's scout
# who spots a lair): the place itself, and the hidden stretch between it and
# the nearest known node, so a place you are told about is a place you can
# walk to. Returns the edges revealed.
func reveal_node(id: String) -> Array:
	if not nodes.has(id):
		return []
	var out: Array = []
	nodes[id]["known"] = true
	var r := _dijkstra(id, "", false)
	var target := ""
	var target_d := INF
	for n in r["dist"]:
		if n != id and nodes[n]["known"] and _joined_known(n) and float(r["dist"][n]) < target_d:
			target = n
			target_d = r["dist"][n]
	var cur := target
	while cur != "" and cur != id:
		var eid: String = r["prev"][cur]
		if reveal(eid):
			out.append(eid)
		var e: Dictionary = edges[eid]
		cur = e["a"] if e["b"] == cur else e["b"]
	return out

# A known node that a known edge touches — somewhere a revealed trail can join
# the roads the company already has, not a fellow island.
func _joined_known(id: String) -> bool:
	for eid in _adj.get(id, []):
		if edges[eid]["known"]:
			return true
	return false

# --- reading it --------------------------------------------------------------

func node_for(kind: String, ref: String) -> Dictionary:
	return nodes.get(poi_id(kind, ref), {})

# Every known node reachable from `from` over known edges.
func reachable(from: String) -> Array:
	var out: Array = _distances(from, true).keys()
	out.sort()
	return out

func stats() -> Dictionary:
	var out := {"nodes": nodes.size(), "forks": 0, "edges": edges.size(), "known_edges": 0,
		"length": 0.0, "known_length": 0.0}
	for k in KINDS:
		out[k] = 0
	for id in nodes:
		if nodes[id]["kind"] == "fork":
			out["forks"] += 1
	for eid in edges:
		var e: Dictionary = edges[eid]
		out[e["kind"]] += 1
		out["length"] += float(e["length"])
		if e["known"]:
			out["known_edges"] += 1
			out["known_length"] += float(e["length"])
	return out

# --- the save ------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ns: Array = []
	for id in nodes:
		var n: Dictionary = nodes[id]
		ns.append({"id": id, "kind": n["kind"], "ref": n["ref"],
			"x": n["position"].x, "y": n["position"].y, "known": n["known"], "why": n.get("why", "")})
	var es: Array = []
	for eid in edges:
		var e: Dictionary = edges[eid]
		var pts: Array = []
		for p in e["points"]:
			pts.append([p.x, p.y])
		es.append({"a": e["a"], "b": e["b"], "kind": e["kind"], "points": pts,
			"known": e["known"], "notice": e["notice"].duplicate(), "search": e["search"], "why": e.get("why", "")})
	return {"nodes": ns, "edges": es, "forks": _forks}

# Missing keys read as defaults, the rule every *_save.gd follows.
static func from_dict(d: Dictionary):
	var net = load("res://core/world_routes.gd").new()
	for n in d.get("nodes", []):
		net._add_node(String(n["id"]), String(n.get("kind", "fork")), String(n.get("ref", "")),
			Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0))), bool(n.get("known", false)), String(n.get("why", "")))
	for e in d.get("edges", []):
		var a := String(e["a"])
		var b := String(e["b"])
		if not net.nodes.has(a) or not net.nodes.has(b):
			continue
		var pts := PackedVector2Array()
		for p in e.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() < 2:
			pts = PackedVector2Array([net.nodes[a]["position"], net.nodes[b]["position"]])
		net._link(edge_id(a, b), a, b, String(e.get("kind", "road")), pts, bool(e.get("known", true)),
			Array(e.get("notice", [])), bool(e.get("search", false)), String(e.get("why", "")))
	net._forks = int(d.get("forks", 0))
	return net
