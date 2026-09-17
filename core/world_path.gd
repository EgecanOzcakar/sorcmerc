# O16 — routing around the water, for the bands nobody is steering.
#
# O1 does the steering: `World.move_toward_goal()` walks a straight line toward
# `party.goal` and refuses any step from land into a blob, with a one-step
# shoreline slide so a party skimming a bank follows it instead of gluing to
# it. That is enough for the player, who can look at the map and click again,
# and T-water documented it as enough for everyone else too ("no pathfinder is
# involved and none is wanted"). It is not enough for a band nobody is
# steering. A hunter whose prey is across the river walks to the near bank and
# stands there for the rest of the campaign; a patrol whose next waypoint is
# over the water never arrives, so it never advances to the one after it and
# the whole route dies at the first ford. The small map shipped with both: the
# `patrol` band's leg back to (0, 0) crosses the river, and `bandits` hunt the
# player across it.
#
# So: a route, computed here, handed to O3 (core/world_ai.gd) as a list of
# waypoints it feeds to `party.goal` one at a time. This file moves nothing and
# writes no positions — O1 still owns every step a party takes.
#
#   WorldPath.clear_line(world, a, b)    # is the straight march between them dry?
#   WorldPath.route(world, from, to)     # waypoints; [] when it is, or when there is no way round
#   WorldPath.nearest_dry(world, p)      # a point in a lake, pushed out to the bank
#
# The graph. `World.waters` is circles and nothing else, so the obstacles are
# circles, and a shortest path around a circle hugs it: a route only ever bends
# at a bank. The nodes are therefore a ring of points stamped just outside each
# blob, keeping the ones that are not inside some *other* blob — a river is
# overlapping blobs, so that filter leaves exactly its two banks and drops the
# middle. The edges are the node pairs that can see each other over dry ground,
# the path is Dijkstra across them, and a string-pull afterwards drops the
# corners the band could have walked straight past.
#
# Visibility is exact circle geometry, not sampling: a segment is blocked when
# its closest approach to a centre falls inside that radius, which is one
# distance test per blob instead of one per sample step, and cannot miss a thin
# blob between two samples the way a sampled test can.
#
# The graph depends on `waters` alone, and no map adds water after it is built,
# so it is built once per distinct set of blobs and cached (see `_signature`).
extends RefCounted

# How far outside its bank a waypoint sits, and how many are stamped around
# each blob. The two are related: the straight line between neighbours on the
# same ring cuts the corner by `(r + clearance) * (1 - cos(PI / RING_POINTS))`,
# so the clearance has to beat that or a ring is not even connected to itself
# and nothing can walk around a lake. At 16 points that wants > 1.9% of the
# radius; 10% leaves room for a ring point to be dropped as a duplicate and its
# neighbours to still see each other across the gap.
const RING_POINTS := 16
const CLEARANCE_MIN := 6.0
const CLEARANCE_FRAC := 0.1
# Two candidates closer together than this are the same corner as far as a
# party walking past them is concerned. The river's blobs overlap, so their
# rings do too, and keeping every one of them squares the edge count for a
# graph that is no better at rounding anything.
const MERGE := 8.0
# Visibility ignores the first and last half-unit of a segment. A party stopped
# hard against a bank is exactly `radius` from that blob's centre, and without
# the slack every edge leading away from it reads as blocked by the very blob
# it is standing next to — a band on the shore could never be given a route.
const END_SLACK := 0.5
# How many times `nearest_dry` will push a point out of a blob before giving
# up. Blobs overlap, so leaving one can drop you in the next.
const DRY_TRIES := 6
# Graphs are keyed by the water they were built from; a handful covers the
# worlds one process ever sees (a map, a reload, a test's lake or two).
const CACHE_MAX := 4

static var _cache := {}

# --- visibility ------------------------------------------------------

# True when a party can march straight from `a` to `b` without wading.
static func clear_line(world, a: Vector2, b: Vector2) -> bool:
	return _clear(world.waters, a, b)

static func _clear(waters: Array, a: Vector2, b: Vector2) -> bool:
	var span := a.distance_to(b)
	if span <= 0.0001:
		return true
	var dir := (b - a) / span
	var slack := minf(END_SLACK, span * 0.25)
	var p0 := a + dir * slack
	var p1 := b - dir * slack
	var mid := (p0 + p1) * 0.5
	var half := p0.distance_to(p1) * 0.5
	for w in waters:
		var c: Vector2 = w["position"]
		var r: float = float(w["radius"])
		# Cheap reject before the real test: a blob whose centre is further
		# from the midpoint than the segment is long cannot reach it.
		if c.distance_to(mid) > half + r:
			continue
		if Geometry2D.get_closest_point_to_segment(c, p0, p1).distance_to(c) < r:
			return false
	return true

# --- getting out of the water ----------------------------------------

# `p` when it is dry; otherwise pushed straight out to the nearest bank it can
# reach, radially away from whichever blob it is deepest inside, repeated
# because blobs overlap. A point the loop cannot free comes back unchanged and
# the caller falls back to O1's own rule (march at it, stop at the bank), which
# is what happened before this file existed.
static func nearest_dry(world, p: Vector2) -> Vector2:
	if not world.is_water(p):
		return p
	var out := p
	for _try in DRY_TRIES:
		var deepest := {}
		var worst := 0.0
		for w in world.waters:
			var into: float = float(w["radius"]) - out.distance_to(w["position"])
			if into > worst:
				worst = into
				deepest = w
		if deepest.is_empty():
			break
		var c: Vector2 = deepest["position"]
		var r: float = float(deepest["radius"])
		var away := out - c
		if away.length_squared() < 0.0001:
			away = Vector2.RIGHT      # dead centre: any direction is the nearest bank
		out = c + away.normalized() * (r + maxf(CLEARANCE_MIN, r * CLEARANCE_FRAC))
		if not world.is_water(out):
			return out
	return p

# --- the route -------------------------------------------------------

# Waypoints from `from` (exclusive) to `to` (inclusive), each leg dry.
# Empty means "no route was needed or none exists": the straight march is
# already clear, the world has no water, the party is swimming, the goal is in
# a lake, or the far side simply cannot be reached over land. Every one of
# those is the caller's cue to fall back to marching straight at the goal.
static func route(world, from: Vector2, to: Vector2) -> Array[Vector2]:
	var none: Array[Vector2] = []
	if world.waters.is_empty():
		return none
	if _clear(world.waters, from, to):
		return none
	# A party already in the water is O1's business: its swim-out rule lets it
	# move in any direction at all, and no edge could leave a wet node anyway.
	if world.is_water(from) or world.is_water(to):
		return none
	var g := _graph(world)
	var nodes: Array = g["nodes"]
	var adj: Array = g["adj"]
	var n: int = nodes.size()
	if n == 0:
		return none
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	for i in n:
		if _clear(world.waters, from, nodes[i]):
			dist[i] = from.distance_to(nodes[i])
	# Dijkstra, O(V^2) — a couple of hundred corners does not pay for a heap.
	# `to` is not a node: every settled corner is asked whether it can see the
	# goal, and the search stops as soon as the cheapest corner still unsettled
	# already costs more than the best finished path.
	var best_end := -1
	var best_total := INF
	while true:
		var u := -1
		var ud := INF
		for i in n:
			if done[i] == 0 and dist[i] < ud:
				ud = dist[i]
				u = i
		if u < 0 or ud >= best_total:
			break
		done[u] = 1
		var here: Vector2 = nodes[u]
		if _clear(world.waters, here, to):
			var total: float = ud + here.distance_to(to)
			if total < best_total:
				best_total = total
				best_end = u
		for v in adj[u]:
			if done[v] == 1:
				continue
			var step: float = ud + here.distance_to(nodes[v])
			if step < dist[v]:
				dist[v] = step
				prev[v] = u
	if best_end < 0:
		return none
	var back: Array[Vector2] = []
	var cur := best_end
	while cur >= 0:
		back.append(nodes[cur])
		cur = prev[cur]
	back.reverse()
	back.append(to)
	return _string_pull(world.waters, from, back)

# The corners are ring samples, so the raw path visits points it had no reason
# to visit. Pull the string tight: from where you stand, aim at the furthest
# waypoint you can still see, and forget the ones in between.
static func _string_pull(waters: Array, from: Vector2, path: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := from
	var i := 0
	while i < path.size():
		var pick := i
		for j in range(path.size() - 1, i, -1):
			if _clear(waters, at, path[j]):
				pick = j
				break
		at = path[pick]
		out.append(at)
		i = pick + 1
	return out

# --- the graph -------------------------------------------------------

static func _graph(world) -> Dictionary:
	var sig := _signature(world.waters)
	if _cache.has(sig):
		return _cache[sig]
	var g := _build(world)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[sig] = g
	return g

# Keyed by the water itself rather than by the world, because that is what the
# graph is made of: two worlds with the same lakes want the same graph, and a
# world that is freed takes no stale entry with it.
static func _signature(waters: Array) -> String:
	var acc := 0.0
	for w in waters:
		var c: Vector2 = w["position"]
		acc += c.x * 3.0 + c.y * 5.0 + float(w["radius"]) * 7.0
	return "%d:%.3f" % [waters.size(), acc]

static func _build(world) -> Dictionary:
	var nodes: Array[Vector2] = []
	var taken := {}
	for w in world.waters:
		var c: Vector2 = w["position"]
		var r: float = float(w["radius"])
		var clearance := maxf(CLEARANCE_MIN, r * CLEARANCE_FRAC)
		for k in RING_POINTS:
			var angle := TAU * float(k) / float(RING_POINTS)
			var p := c + Vector2(cos(angle), sin(angle)) * (r + clearance)
			# Swallowed by another blob (or hugging its bank too closely to be
			# stood on): this stretch of ring is not a bank, it is the middle
			# of the river.
			if world.water_depth(p) < clearance * 0.5:
				continue
			var cell := Vector2i(int(floor(p.x / MERGE)), int(floor(p.y / MERGE)))
			if taken.has(cell):
				continue
			taken[cell] = true
			nodes.append(p)
	var adj: Array = []
	adj.resize(nodes.size())
	for i in nodes.size():
		adj[i] = PackedInt32Array()
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if _clear(world.waters, nodes[i], nodes[j]):
				adj[i].append(j)
				adj[j].append(i)
	return {"nodes": nodes, "adj": adj}

# Tests and tools only: how big the cached graph for this world's water is.
static func graph_size(world) -> Dictionary:
	var g := _graph(world)
	var edges := 0
	for a in g["adj"]:
		edges += a.size()
	return {"nodes": g["nodes"].size(), "edges": edges / 2}
