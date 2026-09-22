# Pure hex-grid math. Flat-top axial coords, Vector2i(q, r). No engine/node deps.
# Used by combat.gd, ai.gd, and the renderer.
extends RefCounted

# The 6 unit directions, fixed order (index = "facing").
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2

static func neighbors(p: Vector2i) -> Array:
	var out: Array = []
	for d in DIRS:
		out.append(p + d)
	return out

# Nearest of the 6 directions pointing from a toward b.
static func direction_to(a: Vector2i, b: Vector2i) -> Vector2i:
	var target := _to_pixel_unit(b - a)
	var best := DIRS[0]
	var best_dot := -1e9
	for d in DIRS:
		var dot := _to_pixel_unit(d).dot(target)
		if dot > best_dot:
			best_dot = dot
			best = d
	return best

# Dijkstra flood-fill of movement. `passable` is Callable(Vector2i)->bool (board
# shape), `blocked` are hexes you may not enter (occupied), `rough` hexes cost 2
# to enter. You may still END adjacent to a blocked hex — it just isn't steppable.
# Returns {Vector2i: cost}.
#
# #156: `step` is the one cost that belongs to the STEP rather than to the hex
# it ends on — Callable(from, to) -> extra cost, or STEP_BLOCKED for a pair of
# hexes nothing can walk between. Height is what wanted it (climbing a shelf
# costs, a cliff cannot be climbed at all); every other caller leaves it unset
# and pays one is_valid() per edge for it.
const STEP_BLOCKED := -1

static func _step_cost(step: Callable, from: Vector2i, to: Vector2i) -> int:
	return int(step.call(from, to)) if step.is_valid() else 0

static func reachable(passable: Callable, start: Vector2i, steps: int, blocked: Array,
		rough: Array = [], step: Callable = Callable()) -> Dictionary:
	var dist := {start: 0}
	var q: Array = [start]
	while not q.is_empty():
		var bi := 0
		for i in range(1, q.size()):
			if dist[q[i]] < dist[q[bi]]:
				bi = i
		var cur = q.pop_at(bi)
		var cost: int = dist[cur]
		if cost >= steps:
			continue
		for n in neighbors(cur):
			if n in blocked or not passable.call(n):
				continue
			var extra := _step_cost(step, cur, n)
			if extra == STEP_BLOCKED:
				continue
			var nd: int = cost + (2 if n in rough else 1) + extra
			if nd <= steps and (not dist.has(n) or nd < dist[n]):
				dist[n] = nd
				if not n in q:
					q.append(n)
	return dist

# Shortest-cost path start→dest (inclusive) as a Vector2i list, or [] if none.
# Used for path-aware opportunity attacks.
static func path_to(passable: Callable, start: Vector2i, dest: Vector2i, blocked: Array,
		rough: Array = [], step: Callable = Callable()) -> Array:
	var dist := {start: 0}
	var prev := {}
	var q: Array = [start]
	while not q.is_empty():
		var bi := 0
		for i in range(1, q.size()):
			if dist[q[i]] < dist[q[bi]]:
				bi = i
		var cur = q.pop_at(bi)
		if cur == dest:
			break
		for n in neighbors(cur):
			if n in blocked or not passable.call(n):
				continue
			var extra := _step_cost(step, cur, n)
			if extra == STEP_BLOCKED:
				continue
			var nd: int = dist[cur] + (2 if n in rough else 1) + extra
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = cur
				if not n in q:
					q.append(n)
	if dest != start and not prev.has(dest):
		return []
	var path: Array = [dest]
	while path[0] != start:
		path.push_front(prev[path[0]])
	return path

# Hexes in a ~120° wedge centred on `dir`, out to `length`. Excludes `origin`.
static func cone(origin: Vector2i, dir: Vector2i, length: int) -> Array:
	var facing := _to_pixel_unit(dir)
	var out: Array = []
	for dq in range(-length, length + 1):
		for dr in range(-length, length + 1):
			var off := Vector2i(dq, dr)
			if off == Vector2i.ZERO:
				continue
			if distance(Vector2i.ZERO, off) > length:
				continue
			if _to_pixel_unit(off).dot(facing) >= 0.5:  # within 60° of facing
				out.append(origin + off)
	return out

# Hex line from a to b (inclusive), for push/knockback direction.
static func line(a: Vector2i, b: Vector2i) -> Array:
	var n := distance(a, b)
	if n == 0:
		return [a]
	var out: Array = []
	var ac := _cube(a)
	var bc := _cube(b)
	for i in n + 1:
		var t := float(i) / n
		out.append(_cube_round(ac.lerp(bc, t)))
	return out

# A line of `length` hexes from `origin` through `toward`, origin excluded —
# a lightning bolt: aimed at a hex, it keeps going past it to its full reach.
static func ray(origin: Vector2i, toward: Vector2i, length: int) -> Array:
	var n := distance(origin, toward)
	if n == 0 or length <= 0:
		return []
	var oc := _cube(origin)
	var dir := (_cube(toward) - oc) / float(n)
	var out: Array = []
	for i in range(1, length + 1):
		var h := _cube_round(oc + dir * float(i) + Vector3(1e-6, 2e-6, -3e-6))   # nudge off ties
		if out.is_empty() or out[-1] != h:
			out.append(h)
	return out

# --- corners: an area anchored on a hex vertex ------------------------
#
# A corner is the three hexes that meet at a vertex, sorted so the same vertex
# reached from any of its hexes is the same array. Vertex k of hex `h` sits at
# angle 60°·k (flat-top, matching to_pixel); its two neighbours are the ones
# whose centres are 30° either side of it.
static func corner(h: Vector2i, k: int) -> Array:
	var i: int = (6 - k) % 6
	var out: Array = [h, h + DIRS[i], h + DIRS[(i + 1) % 6]]
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out

# Pixel position of a corner (the mean of its three centres is the vertex).
static func corner_pixel(c: Array, size: float) -> Vector2:
	return (to_pixel(c[0], size) + to_pixel(c[1], size) + to_pixel(c[2], size)) / 3.0

# The corner nearest a pixel point: the containing hex's closest vertex.
static func corner_at(v: Vector2, size: float) -> Array:
	var h := from_pixel(v, size)
	var c := to_pixel(h, size)
	var best := 0
	var best_d := INF
	for k in 6:
		var d := v.distance_squared_to(c + Vector2(cos(deg_to_rad(60.0 * k)), sin(deg_to_rad(60.0 * k))) * size)
		if d < best_d:
			best_d = d
			best = k
	return corner(h, best)

# The hexes a corner-anchored circle covers: the three at the vertex, plus
# `ring` more steps outward.
static func corner_area(c: Array, ring: int = 0) -> Array:
	var out: Array = c.duplicate()
	for _r in ring:
		var grown: Array = out.duplicate()
		for h in out:
			for n in neighbors(h):
				if not (n in grown):
					grown.append(n)
		out = grown
	return out

# Hexes within `r` of `center`, center excluded.
static func within(center: Vector2i, r: int) -> Array:
	var out: Array = []
	for dq in range(-r, r + 1):
		for dr in range(-r, r + 1):
			var off := Vector2i(dq, dr)
			if off != Vector2i.ZERO and distance(Vector2i.ZERO, off) <= r:
				out.append(center + off)
	return out

# --- render / click mapping (flat-top) --------------------------------

static func to_pixel(p: Vector2i, size: float) -> Vector2:
	return Vector2(size * 1.5 * p.x, size * sqrt(3.0) * (p.y + p.x / 2.0))

static func from_pixel(v: Vector2, size: float) -> Vector2i:
	var q := (2.0 / 3.0 * v.x) / size
	var r := (-1.0 / 3.0 * v.x + sqrt(3.0) / 3.0 * v.y) / size
	return _cube_round(Vector3(q, -q - r, r))

# --- internals -------------------------------------------------------

static func _to_pixel_unit(off: Vector2i) -> Vector2:
	var v := Vector2(1.5 * off.x, sqrt(3.0) * (off.y + off.x / 2.0))
	return v.normalized() if v.length() > 0.0 else v

static func _cube(p: Vector2i) -> Vector3:
	return Vector3(p.x, -p.x - p.y, p.y)

static func _cube_round(c: Vector3) -> Vector2i:
	var rx := roundf(c.x)
	var ry := roundf(c.y)
	var rz := roundf(c.z)
	var dx := absf(rx - c.x)
	var dy := absf(ry - c.y)
	var dz := absf(rz - c.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))
