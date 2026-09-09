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

# BFS flood-fill of movement. `passable` is Callable(Vector2i)->bool (board shape),
# `blocked` are hexes you may not enter (occupied). You may still END adjacent to
# a blocked hex — they just aren't steppable. Returns {Vector2i: cost}.
static func reachable(passable: Callable, start: Vector2i, steps: int, blocked: Array) -> Dictionary:
	var seen := {start: 0}
	var frontier := [start]
	while not frontier.is_empty():
		var cur = frontier.pop_front()
		var cost: int = seen[cur]
		if cost >= steps:
			continue
		for n in neighbors(cur):
			if seen.has(n) or n in blocked or not passable.call(n):
				continue
			seen[n] = cost + 1
			frontier.append(n)
	return seen

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
