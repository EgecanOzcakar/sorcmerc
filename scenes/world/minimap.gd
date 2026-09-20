# T-minimap — the map screen's corner inset: a small TOP-DOWN overview of the
# whole world, drawn straight (no dimetric projection), so the player can read
# the shape of what they've explored without zooming the real camera out. The
# map itself is several thousand units across and scenes/world/world.gd shows a
# few hundred of them at a time; this is the "where am I on the continent"
# answer that the isometric view can't give.
#
#   const Minimap = preload("res://scenes/world/minimap.gd")
#   _minimap = Minimap.new()
#   _minimap.world_map = self       # world.gd: exposes .world, ._pix/._unpix, .size, ._zoom
#   add_child(_minimap)             # ...then set .position/.size from your layout pass
#
# What this does NOT own: any world state. It reads core/world.gd and draws;
# the one thing it writes is a click's marching order, and even that goes
# through World.set_goal() so whatever that clamps (water, bounds) clamps here
# too — there is deliberately no second copy of the "can I walk there" rule in
# this file. It does not own its own placement either: the parent sets
# position/size every layout pass, DEFAULT_SIZE is only the number to reach for.
#
# Fallback contract, same as the rest of this folder: a null world_map, a null
# world, or a world with nothing in it draws an empty framed inset and never
# errors — headless construction with `.new()` and nothing else is legal.
extends Control

const World = preload("res://core/world.gd")
const Icons = preload("res://core/ui_icons.gd")

# Big enough that the explored footprint has a readable shape at ~18x18 fog
# samples, small enough to sit in a corner of the map without covering it.
const DEFAULT_SIZE := Vector2(168, 168)
const PAD := 6.0            # frame thickness: the inset has to read as a panel ON the map, not a hole in it

# --- fit ---------------------------------------------------------------
# Breathing room around the content bounds, as a fraction of the fitted span,
# so the outermost settlement isn't welded to the frame.
const FIT_MARGIN := 0.08
# Floor on the fitted span. Without it a world holding one party and nothing
# else fits a zero-size box and the scale explodes; 2x VISION_RADIUS is "one
# sight circle fills the inset", which is as far in as it's ever worth going.
const MIN_SPAN := World.VISION_RADIUS * 2.0
# Span used when there is no content at all to measure (null/empty world).
const FALLBACK_SPAN := 1000.0

# --- fog -------------------------------------------------------------------
# is_explored() is a per-point query over a waypoint list, so the fog grid is
# sampled at WIDGET resolution, not world resolution: a fixed NxN grid over
# whatever rect we were given, 400 samples per rebuild whether the world is
# 1,000 or 10,000 units across.
#
# A count rather than a pixel size, because the parent shrinks this widget on a
# small window (world.gd caps the side at a third of the shorter viewport
# side): a fixed cell size would hand a 96px inset a 9-cell grid and turn the
# explored footprint into four squares, while the same count draws the same
# shape at every size and costs the same either way. 20 is where the footprint
# of a single VISION_RADIUS circle still reads as a blob on the widest built-in
# map (~3 cells) — finer buys detail the eye can't use at this size and costs
# quadratically, since every cell is a full waypoint-list scan.
const FOG_SAMPLES := 20

# --- marks -----------------------------------------------------------------
# Pixel radii. A settlement outranks a lair outranks a party, because at this
# size relative dot size is the only "which of these matters" signal there is.
const R_CITY := 3.5
const R_TOWN := 2.8
const R_CAMP := 2.2
const R_LAIR := 2.4
const R_PARTY := 2.0
const R_PLAYER := 3.0
const MIN_WATER_PX := 1.5   # a river blob is ~40 units wide; below a pixel it stops reading as water at all

const COL_FOG := Icons.COL_INK         # never explored — the same deep inset fill every panel uses
const COL_LAND := Icons.COL_EDGE       # explored ground: quiet, one step up from the fog
const COL_WATER := Color(Icons.COL_ACCENT, 0.75)
const COL_FRAME := Icons.COL_GOLD_EDGE
# The camera region: a faint wash over what's on screen right now, plus a
# brighter line along whatever of its border genuinely falls inside the inset.
# The wash is what carries the meaning when the border is mostly off-widget.
const COL_VIEW := Color(Icons.COL_HEAD, 0.55)
const COL_VIEW_FILL := Color(Icons.COL_HEAD, 0.07)
# Above this share of the inset, the camera region is "all of it" and the whole
# thing is drawn plain: a wash over the entire widget says nothing the absence
# of one doesn't, and the couple of border lines still clipping the corners
# read as a graphical fault rather than as a camera.
const VIEW_COVERS_ALL := 0.9

var world_map                       # scenes/world/world.gd, or null — see the fallback contract above

# The fit: world point at the widget's centre, and widget pixels per world unit.
var _center := Vector2.ZERO
var _scale := 0.0

# Everything below is cache, rebuilt only when _stamp_* says the inputs moved.
var _land: Array[Rect2] = []        # explored ground, merged into horizontal runs per fog row
var _water := PackedVector3Array()  # visible water: Vector3(centre.x, centre.y, radius) in WIDGET pixels
var _stamp_size := Vector2.ZERO
var _stamp_explored := -1           # World.reveal() only ever appends, so the count is a sufficient change stamp
var _stamp_content := -1            # settlements/lairs/waters, which only a load or a new world changes
var _rebuilds := 0                  # how many times the cache actually rebuilt — the test's handle on it holding

# The camera quad in world space (4 corners), allocated once and written in
# place: this runs inside the map screen's per-frame hot loop. The widget-space
# geometry derived from it (below) is rebuilt only when the camera or the fit
# actually moved, and is a dozen points at most either way.
var _view_world := PackedVector2Array()
var _view_fill := PackedVector2Array()    # camera region clipped to the inset, or empty
var _view_edges := PackedVector2Array()   # its real border, in draw_multiline point pairs
var _view_dirty := true
var _has_view := false
var _last_elapsed := -1.0


func _init() -> void:
	size = DEFAULT_SIZE          # a sane standalone default; the parent overwrites it every layout pass
	clip_contents = true         # a water blob or a marker at the edge is cropped by the frame, not spilled onto the map
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view_world.resize(4)
	set_process(true)


# Redraw on our own initiative (the parent shouldn't have to poke us), but only
# when something actually moved: a paused map with a still camera costs nothing.
# The clock is the cheap proxy for "parties may have moved" — it advances on
# every unpaused tick and on none of the paused ones.
func _process(_delta: float) -> void:
	var w = _world()
	if w == null:
		return
	var dirty := false
	if size != _stamp_size or w.explored.size() != _stamp_explored:
		dirty = true
	var t: float = w.clock.elapsed
	if t != _last_elapsed:
		_last_elapsed = t
		dirty = true
	if _refresh_view():
		dirty = true
	if dirty:
		queue_redraw()


# --- public geometry ---------------------------------------------------
# Both directions of the top-down fit. Safe to call at any time: they bring the
# fit up to date first, so a freshly constructed widget answers sensibly.
func world_to_widget(p: Vector2) -> Vector2:
	_ensure_fit()
	return _to_widget(p)


func widget_to_world(px: Vector2) -> Vector2:
	_ensure_fit()
	return _to_world(px)


# Drop the cache: the next query or draw refits from scratch. For whoever
# swaps the underlying world out from under a live widget (a load, a new game).
func refresh() -> void:
	_stamp_explored = -1
	_stamp_content = -1
	_stamp_size = Vector2.ZERO


# --- fit ---------------------------------------------------------------
func _world():
	if world_map == null:
		return null
	return world_map.world


# The drawing area inside the frame.
func _inner_rect() -> Rect2:
	var inner := Vector2(maxf(size.x - PAD * 2.0, 1.0), maxf(size.y - PAD * 2.0, 1.0))
	return Rect2(Vector2(PAD, PAD), inner)


# Unchecked forms, for use from inside a rebuild (the public ones would recurse
# back into _ensure_fit while it is halfway through computing the fit).
func _to_widget(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _scale


func _to_world(px: Vector2) -> Vector2:
	if _scale <= 0.0:
		return _center
	return _center + (px - size * 0.5) / _scale


func _ensure_fit() -> void:
	var w = _world()
	if w == null:
		_fit_span(Vector2.ZERO, FALLBACK_SPAN)
		return
	var content: int = w.settlements.size() * 1000003 + w.lairs.size() * 1009 + w.waters.size() + w.landmarks.size() * 1013
	if size == _stamp_size and w.explored.size() == _stamp_explored and content == _stamp_content:
		return
	_stamp_size = size
	_stamp_explored = w.explored.size()
	_stamp_content = content
	_rebuilds += 1
	_view_dirty = true          # the widget-space camera region hangs off the fit
	_fit_world(w)
	_build_fog(w)
	_build_water(w)


# The three built-in maps differ by an order of magnitude in span (the small
# map is ~1,200 units across, the procedural one 2,800+), so the extent is
# measured off the content rather than being a constant.
#
# Undiscovered lairs count toward the bounds even though they don't draw: the
# alternative is the whole inset silently rescaling the moment one is found,
# which is a far louder tell than the sliver of extra margin it costs.
func _fit_world(w) -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for s in w.settlements:
		mn = mn.min(s.position); mx = mx.max(s.position)
	for l in w.lairs:
		mn = mn.min(l.position); mx = mx.max(l.position)
	for b in w.waters:
		var c: Vector2 = b["position"]
		var r := Vector2.ONE * float(b["radius"])
		mn = mn.min(c - r); mx = mx.max(c + r)
	# Explored ground is content too — a long walk off the edge of the
	# settled world still belongs on the inset. VISION_RADIUS because a
	# waypoint lights a circle, not a point.
	var vis := Vector2.ONE * World.VISION_RADIUS
	for e in w.explored:
		mn = mn.min(e - vis); mx = mx.max(e + vis)
	# The player is bounded but NOT stamped: their position changes every
	# frame and refitting that often would make the inset swim. It's safe
	# because reveal() drops a waypoint every EXPLORE_STEP units, and that
	# waypoint's VISION_RADIUS footprint (above) always contains them.
	for p in w.parties:
		if p.is_player:
			mn = mn.min(p.position); mx = mx.max(p.position)
	if mn.x > mx.x:
		_fit_span(Vector2.ZERO, FALLBACK_SPAN)
		return
	var centre := (mn + mx) * 0.5
	var span := mx - mn
	var longest := maxf(maxf(span.x, span.y), MIN_SPAN)
	_fit_span(centre, longest * (1.0 + FIT_MARGIN * 2.0))


# Fit a square world span into the inner rect, uniformly — a non-uniform fit
# would stretch the map's shape, which is the one thing the inset is for.
func _fit_span(centre: Vector2, span: float) -> void:
	var inner := _inner_rect().size
	_center = centre
	_scale = minf(inner.x, inner.y) / maxf(span, 1.0)


# --- cached terrain ----------------------------------------------------
# One is_explored() call per grid cell, merged into horizontal runs so the draw
# is a handful of rects instead of a few hundred.
# ponytail: is_explored() is a linear scan of the waypoint list, so this is
# O(cells x waypoints) — fine at 400 cells and a rebuild every EXPLORE_STEP of
# travel, but if explored ever grows into the thousands, index it there.
func _build_fog(w) -> void:
	_land.clear()
	var inner := _inner_rect()
	# Square cells, so the footprint keeps its shape in a non-square widget:
	# the longer side gets FOG_SAMPLES of them and the shorter side fewer.
	var cell := maxf(inner.size.x, inner.size.y) / FOG_SAMPLES
	var cols := maxi(1, int(ceil(inner.size.x / cell)))
	var rows := maxi(1, int(ceil(inner.size.y / cell)))
	var cw := inner.size.x / cols
	var ch := inner.size.y / rows
	for j in rows:
		var y := inner.position.y + j * ch
		var run := -1
		for i in cols:
			var at := Vector2(inner.position.x + (i + 0.5) * cw, y + ch * 0.5)
			var lit: bool = w.is_explored(_to_world(at))
			if lit and run < 0:
				run = i
			elif not lit and run >= 0:
				_land.append(Rect2(inner.position.x + run * cw, y, (i - run) * cw, ch))
				run = -1
		if run >= 0:
			_land.append(Rect2(inner.position.x + run * cw, y, (cols - run) * cw, ch))


# Water is fog-gated like everything else: a lake you haven't walked past is
# not on your map. Tested at the blob's centre rather than per pixel — a blob
# is one hand-placed circle, not a field.
func _build_water(w) -> void:
	_water.clear()
	for b in w.waters:
		var c: Vector2 = b["position"]
		if not w.is_explored(c):
			continue
		var at := _to_widget(c)
		_water.append(Vector3(at.x, at.y, maxf(float(b["radius"]) * _scale, MIN_WATER_PX)))


# --- camera rectangle ------------------------------------------------------
# The four screen corners unprojected into world space: in top-down terms the
# visible region is a rotated parallelogram (the map screen's yaw), not an
# axis-aligned box, so it is kept as a quad. Returns true when it moved.
func _refresh_view() -> bool:
	if world_map == null or not world_map.has_method("_unpix"):
		_has_view = false
		return false
	var vs: Vector2 = world_map.size
	var changed := false
	for i in 4:
		var corner := Vector2(vs.x if i == 1 or i == 2 else 0.0, vs.y if i >= 2 else 0.0)
		var p: Vector2 = world_map._unpix(corner)
		if not p.is_equal_approx(_view_world[i]):
			_view_world[i] = p
			changed = true
	_has_view = true
	if changed:
		_view_dirty = true
	return changed


# The camera region, in widget pixels, clipped to the inset.
#
# Unclipped, this was two bright diagonals across the middle of the widget at
# any zoom where the screen sees more world than the inset spans: the quad's
# corners land far outside, so all that survived was the pair of edges that
# happen to cross, with no corners to make them read as a rectangle. So the
# quad is intersected with the inset and drawn as a region — a wash over the
# part of the world that is on screen, outlined only along the stretch of its
# border that is genuinely inside. Fully zoomed in on a wide map that is the
# whole rectangle, exactly as before; zoomed out past the map's own extent it
# is a wash with an honest edge or two; past VIEW_COVERS_ALL it is nothing.
func _build_view() -> void:
	_view_fill.clear()
	_view_edges.clear()
	if not _has_view:
		return
	var inner := _inner_rect()
	var quad := PackedVector2Array()
	for i in 4:
		quad.append(_to_widget(_view_world[i]))
	var clipped := _clip_poly(quad, inner)
	if clipped.size() < 3:
		return                      # the camera is looking somewhere else entirely
	if absf(_area(clipped)) >= inner.get_area() * VIEW_COVERS_ALL:
		return                      # it covers the map; say that by drawing nothing
	_view_fill = clipped
	for i in 4:
		var seg := _clip_seg(quad[i], quad[(i + 1) % 4], inner)
		if not seg.is_empty():
			_view_edges.append_array(seg)


# Sutherland-Hodgman against the four sides of a rect. Both shapes are convex,
# so the intersection is too — which is what draw_colored_polygon needs.
static func _clip_poly(poly: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var out := poly
	for side in 4:
		var src := out
		out = PackedVector2Array()
		var n := src.size()
		if n == 0:
			return out
		for i in n:
			var a := src[i]
			var b := src[(i + 1) % n]
			var da := _inside(a, r, side)
			var db := _inside(b, r, side)
			if da >= 0.0:
				out.append(a)
			if (da >= 0.0) != (db >= 0.0):
				out.append(a.lerp(b, da / (da - db)))
	return out


# Signed distance into the rect from one of its sides: >= 0 is inside.
static func _inside(p: Vector2, r: Rect2, side: int) -> float:
	match side:
		0: return p.x - r.position.x
		1: return r.end.x - p.x
		2: return p.y - r.position.y
		_: return r.end.y - p.y


# Liang-Barsky: the part of segment a->b inside the rect, as [a', b'], or empty.
static func _clip_seg(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for side in 4:
		# The parameter moves into the half-plane at rate `den`; `num` is how
		# far outside it the segment starts.
		var num := _inside(a, r, side)
		var den := -(_inside(a + d, r, side) - num)
		if absf(den) < 0.00001:
			if num < 0.0:
				return PackedVector2Array()   # parallel and outside
			continue
		var t := num / den
		if den > 0.0:
			t1 = minf(t1, t)
		else:
			t0 = maxf(t0, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# --- input -----------------------------------------------------------------
# Click the inset, march there. Left or right: the map screen itself marches on
# right-click, but on a 168px inset a left-click is what a hand expects, and
# left-drag-to-pan (world.gd's binding) has no meaning in here.
func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	if e.button_index != MOUSE_BUTTON_LEFT and e.button_index != MOUSE_BUTTON_RIGHT:
		return
	var w = _world()
	if w == null:
		return
	var p = w.player()
	if p == null:
		return
	# No water/bounds rule here on purpose — set_goal() is the one place that
	# decides where a party may be sent, and it clamps.
	w.set_goal(p, widget_to_world(e.position))
	accept_event()
	queue_redraw()


# --- drawing -----------------------------------------------------------
func _draw() -> void:
	_ensure_fit()
	var inner := _inner_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Icons.COL_PANEL)
	draw_rect(inner, COL_FOG)
	var w = _world()
	if w != null:
		for r in _land:
			draw_rect(r, COL_LAND)
		for v in _water:
			draw_circle(Vector2(v.x, v.y), v.z, COL_WATER)
		_draw_view()
		_draw_marks(w)
	# Last, over everything: a marker cropped by clip_contents ends at a drawn
	# edge instead of at nothing.
	draw_rect(inner, COL_FRAME, false, 1.0)


func _draw_view() -> void:
	if _view_dirty:
		_build_view()
		_view_dirty = false
	if _view_fill.size() >= 3:
		draw_colored_polygon(_view_fill, COL_VIEW_FILL)
	if _view_edges.size() >= 2:
		draw_multiline(_view_edges, COL_VIEW, 1.0, true)


func _draw_marks(w) -> void:
	# Settlements are permanent beacons (World.SETTLEMENT_BEACON_RADIUS), so
	# they draw fogged or not — same rule world.gd's _draw() uses, for the same
	# reason: they're what a dark map gives you to steer toward.
	for s in w.settlements:
		var r := R_TOWN
		if s.kind == "city":
			r = R_CITY
		elif s.kind == "camp":
			r = R_CAMP
		_draw_square(_to_widget(s.position), r, _faction_color(s.faction))
	# Lairs and roaming parties stay fog-gated: found, not signposted.
	for l in w.lairs:
		if l.discovered and w.is_explored(l.position):
			_draw_diamond(_to_widget(l.position), R_LAIR, Icons.COL_MUTED if l.looted else Icons.COL_FOE)
	for m in w.landmarks:
		if m.found and w.is_explored(m.position):
			_draw_diamond(_to_widget(m.position), R_LAIR - 1, Icons.COL_MUTED if m.spent else Icons.COL_ACCENT)
	var player = null
	for q in w.parties:
		if q.is_player:
			player = q
		elif w.band_seen(q.position):
			draw_circle(_to_widget(q.position), R_PARTY, _faction_color(q.faction))
	if player != null:
		var at := _to_widget(player.position)
		draw_circle(at, R_PLAYER, Icons.COL_GOLD)
		draw_arc(at, R_PLAYER + 2.0, 0.0, TAU, 12, Icons.COL_GOLD, 1.0, true)


func _draw_square(at: Vector2, r: float, col: Color) -> void:
	draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), col)


func _draw_diamond(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), col)


# world.gd owns the faction palette (one hash, no table to maintain). A host
# that doesn't have it falls back to the muted grey, same contract as the rest
# of this file: no crash, just less colour.
func _faction_color(faction: String) -> Color:
	if world_map != null and world_map.has_method("faction_color"):
		return world_map.faction_color(faction)
	return Icons.COL_MUTED
