# O2 — the open-world map screen: draws core/world.gd's free 2D map in the same
# dimetric projection the combat board uses, with a drag-pan / scroll-zoom camera,
# a pause button on the WorldClock, and right-click-to-move for the player party.
# All state lives in core/world.gd; this only draws it and feeds it goals.
#
# Run standalone:  godot --path . scenes/world/world.tscn
#
# The projection math below is a copy of scenes/main.gd's Board._iso/_ring/_fan/
# _soft_shadow (~25 lines). It is duplicated rather than shared because those
# helpers are methods of main.gd's nested `Board extends Control` — they call
# draw_* on themselves and read Board._origin/main.hex_px — so factoring them out
# would mean editing scenes/main.gd, which this phase may not touch. The numbers
# (yaw/squash/gain, light direction) are the contract; keep them equal if either
# side ever changes. ponytail: a shared `core/iso.gd` is the upgrade path, and is
# cheap to do the day main.gd is in scope for edits.
extends Control

const World = preload("res://core/world.gd")
const Icons = preload("res://core/ui_icons.gd")

const ISO_YAW := 35.0
const ISO_SQUASH := 0.38
const ISO_GAIN := 1.85
const LIGHT := Vector2(-0.30, -0.34)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
const CELL := 90.0          # ground patch size, in world units
const MAX_CELLS := 900      # cap the ground loop when zoomed far out

var world: World
var _pan := Vector2.ZERO
var _zoom := 1.0
var _origin := Vector2.ZERO
var _pause_btn: Button
var _clock_lbl: Label

func _ready() -> void:
	if world == null:
		world = _demo_world()
	set_process(true)
	_build_hud()

# Hand-placed stand-ins so the scene has something to render and move. Real
# spawning is a later phase's job (O3 onward).
func _demo_world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "soldier", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "soldier", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "soldier", "town"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "cultist", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "soldier", true))
	w.add_party(World.RoamingParty.new("bandits", Vector2(-250, -120), "bandit"))
	w.add_party(World.RoamingParty.new("goblins", Vector2(380, 300), "goblinoid"))
	w.add_party(World.RoamingParty.new("patrol", Vector2(-120, 380), "soldier"))
	return w

# World.tick() advances the clock itself and gates movement on it, so one call
# per frame is the whole update.
func _process(delta: float) -> void:
	world.tick(delta)
	if _clock_lbl != null:
		_clock_lbl.text = "Day %d  %02d:%02d" % [
			int(world.clock.elapsed / 1440.0) + 1,
			int(world.clock.elapsed / 60.0) % 24, int(world.clock.elapsed) % 60]
	queue_redraw()

# --- HUD ---------------------------------------------------------------
func _build_hud() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	_pause_btn = Button.new()
	_pause_btn.text = "Pause"
	_pause_btn.pressed.connect(_toggle_pause)
	bar.add_child(_pause_btn)
	_clock_lbl = Label.new()
	_clock_lbl.add_theme_color_override("font_color", Icons.COL_GOLD)
	bar.add_child(_clock_lbl)
	var hint := Label.new()
	hint.text = "right-click: march here   ·   drag: pan   ·   wheel: zoom"
	hint.add_theme_color_override("font_color", Icons.COL_MUTED)
	bar.add_child(hint)

func _toggle_pause() -> void:
	if world.clock.is_paused():
		world.clock.resume()
	else:
		world.clock.pause()
	_pause_btn.text = "Resume" if world.clock.is_paused() else "Pause"

# --- projection (see header) -------------------------------------------
func _iso(v: Vector2) -> Vector2:
	var r := v.rotated(deg_to_rad(ISO_YAW)) * ISO_GAIN
	return Vector2(r.x, r.y * ISO_SQUASH)

func _iso_inv(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y / ISO_SQUASH).rotated(-deg_to_rad(ISO_YAW)) / ISO_GAIN

# world point -> screen point
func _pix(w: Vector2) -> Vector2:
	return _origin + _iso(w) * _zoom

# screen point -> world point, the inverse of _pix
func _unpix(sp: Vector2) -> Vector2:
	return _iso_inv((sp - _origin) / _zoom)

func _ring(center: Vector2, r: float, flat := true, closed := false, segs := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var v := Vector2(cos(TAU * i / segs), sin(TAU * i / segs)) * r
		pts.append(center + (_iso(v) if flat else v))
	if closed:
		pts.append(pts[0])
	return pts

func _fan(apex: Vector2, rim: PackedVector2Array, inner: Color, outer: Color) -> void:
	var n := rim.size()
	var cols := PackedColorArray([inner, outer, outer])
	var uv := PackedVector2Array()
	for i in n:
		draw_primitive(PackedVector2Array([apex, rim[i], rim[(i + 1) % n]]), cols, uv)

func _soft_shadow(at: Vector2, r: float, strength := 1.0) -> void:
	for i in 3:
		draw_colored_polygon(_ring(at, r * (1.0 + 0.26 * i)),
			Color(0.02, 0.01, 0.04, strength * (0.20 - 0.05 * i)))

# Stable per-cell noise: same cell, same salt -> same value, every frame.
static func _rand(c: Vector2i, salt: int) -> float:
	var n: int = hash(Vector3i(c.x, c.y, salt))
	return float(n % 4096) / 4096.0 if n >= 0 else float(-n % 4096) / 4096.0

# A faction's colour, straight off its name's hash so no table needs maintaining
# as core/scaler.gd's FACTIONS list grows.
static func faction_color(faction: String, is_player := false) -> Color:
	if is_player:
		return Icons.COL_PARTY
	return Color.from_hsv(float(absi(hash(faction)) % 360) / 360.0, 0.52, 0.78)

# --- camera ------------------------------------------------------------
func set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)

func pan_by(d: Vector2) -> void:
	_pan += d

# zoom keeping the world point under `sp` fixed
func zoom_at(sp: Vector2, factor: float) -> void:
	var anchor := _unpix(sp)
	set_zoom(_zoom * factor)
	_layout()
	pan_by(sp - _pix(anchor))
	_layout()      # _origin follows _pan; keep them in step for the next _unpix

func _layout() -> void:
	_origin = size * 0.5 + _pan

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			pan_by(e.relative)
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(e.position, 1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(e.position, 1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var p := world.player()
			if p != null:
				world.set_goal(p, _unpix(e.position))
		queue_redraw()

# --- drawing -----------------------------------------------------------
func _draw() -> void:
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Icons.COL_BG)
	_draw_ground()
	var p := world.player()
	if p != null and not p.at_goal():
		draw_polyline(_ring(_pix(p.goal), 9.0 * _zoom, true, true, 18), Icons.COL_GOLD, 1.5, true)

	# One painter's-order pass over everything standing on the ground.
	var props: Array = []
	for s in world.settlements:
		props.append({"at": _pix(s.position), "s": s})
	for q in world.parties:
		props.append({"at": _pix(q.position), "p": q})
	props.sort_custom(func(a, b): return a["at"].y < b["at"].y)
	for d in props:
		if d.has("s"):
			_draw_settlement(d["s"], d["at"])
		else:
			_draw_party(d["p"], d["at"])

# The same two-layer treatment the combat board gives a hex — a tinted slab, then
# a lighter blob drifting off-centre — on a coarse grid of the ground plane, so
# neighbouring patches overlap in tone instead of reading as hard-cut diamonds.
func _draw_ground() -> void:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var w := _unpix(corner)
		mn = mn.min(w); mx = mx.max(w)
	var i0 := int(floor(mn.x / CELL)); var i1 := int(ceil(mx.x / CELL))
	var j0 := int(floor(mn.y / CELL)); var j1 := int(ceil(mx.y / CELL))
	if (i1 - i0 + 1) * (j1 - j0 + 1) > MAX_CELLS:   # far-out zoom: don't paint the world
		draw_rect(Rect2(Vector2.ZERO, size), Color("2b3a2a"))
		return
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var cell := Vector2i(i, j)
			var c := _pix(Vector2(i + 0.5, j + 0.5) * CELL)
			var v := _rand(cell, 1)
			var tint := Color("35462f").lightened(0.06 * v).darkened(0.05 * (1.0 - v))
			# The patch itself tessellates exactly (a projected square, like the
			# board's hexes) — anything with a rim would show its own edge where it
			# overlapped its neighbour. The shading is the mottle on top.
			var quad := PackedVector2Array()
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				quad.append(_pix((Vector2(i, j) + corner) * CELL))
			draw_colored_polygon(quad, tint)
			var r := CELL * 0.72 * _zoom
			var blob := c + _iso(Vector2(_rand(cell, 2) - 0.5, _rand(cell, 3) - 0.5) * CELL * 0.7) * _zoom
			var br := r * (0.45 + 0.35 * _rand(cell, 4))
			var wash := tint.lightened(0.10) if v > 0.5 else tint.darkened(0.10)
			for k in 3:   # feathered out, so the patches blend instead of tiling visibly
				draw_colored_polygon(_ring(blob, br * (0.55 + 0.225 * k)),
					Color(wash.r, wash.g, wash.b, 0.09))

# A landmark, not art: a shaded footprint plus one block per building, taller and
# wider for a city than a town.
func _draw_settlement(s, at: Vector2) -> void:
	var col := faction_color(s.faction)
	var big: bool = s.kind == "city"
	var r := (26.0 if big else 17.0) * _zoom
	_soft_shadow(at, r * 0.9)
	_fan(at + _iso(LIGHT) * r * 0.5, _ring(at, r), col.darkened(0.35), col.darkened(0.62))
	draw_polyline(_ring(at, r, true, true), col.darkened(0.15), 1.5, true)
	var blocks := [Vector2(0, 0), Vector2(-0.5, 0.35), Vector2(0.5, 0.3)] if big \
		else [Vector2(0, 0), Vector2(0.45, 0.3)]
	for b in blocks:
		var base: Vector2 = at + _iso(b * r)
		var w := r * (0.38 if big else 0.34)
		var h := r * (1.05 if big else 0.75)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0),
			base + Vector2(w, -h), base + Vector2(-w, -h)]), col.darkened(0.12))
		draw_line(base + Vector2(-w, -h), base + Vector2(w, -h), col.lightened(0.35), 2.0)
	draw_string(ThemeDB.fallback_font, at + Vector2(-r, r * 0.9 + 12.0), s.sname,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Icons.COL_BODY)

# A circular token, the same ball shading the combat board's char tokens use.
func _draw_party(p, at: Vector2) -> void:
	var col := faction_color(p.faction, p.is_player)
	var rad := (11.0 if p.is_player else 9.0) * _zoom
	_soft_shadow(at, rad * 0.8)
	_fan(at + _iso(LIGHT) * rad * 0.62, _ring(at, rad * 1.25),
		col.darkened(0.45), col.darkened(0.70))          # the flat base ring
	_fan(at + LIGHT * rad * 0.62, _ring(at, rad, false),
		col.lightened(0.26), col.darkened(0.20))         # the ball, facing the camera
	draw_polyline(_ring(at, rad, false, true), col.darkened(0.45), 1.5, true)
	if p.is_player:
		draw_polyline(_ring(at, rad * 1.7), Icons.COL_GOLD, 1.5, true)
