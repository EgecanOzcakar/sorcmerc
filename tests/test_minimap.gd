# T-minimap: the map screen's corner inset (scenes/world/minimap.gd) — the
# top-down fit (content-derived, so the three built-in maps of wildly
# different spans all land inside the widget), the widget-resolution fog
# sampling and its cache, the fog gating on water/lairs/parties, and the
# click-to-march handoff into World.set_goal().
#
# The widget is driven through a stub host rather than the live world scene:
# minimap.gd's whole contract with its parent is `.world`, `.size`, `._unpix()`
# and `.faction_color()`, so a five-line stand-in exercises all of it without
# booting scenes/world/world.tscn (and without this test breaking every time
# that file moves).
#   godot --headless --path . -s tests/test_minimap.gd
extends SceneTree

const World = preload("res://core/world.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const Minimap = preload("res://scenes/world/minimap.gd")

# Stands in for scenes/world/world.gd: the four members minimap.gd reads.
class Host extends RefCounted:
	var world
	var size := Vector2(900, 600)
	var pan := Vector2.ZERO
	var zoom := 1.0
	var yaw := 0.0

	# A top-down camera with a yaw — not world.gd's exact dimetric math, but
	# the same thing that matters to the inset: the visible region unprojects
	# to a ROTATED quad, so its corners can sit outside the widget while its
	# edges cut across the middle.
	func _unpix(sp: Vector2) -> Vector2:
		return ((sp - size * 0.5) / zoom).rotated(yaw) + pan

	func faction_color(_faction: String) -> Color:
		return Color.WHITE

var _pass := 0
var _fail := 0
# Every widget built here is a Node that never enters the tree, so this test
# owns their lifetime: freed at the end, or Godot reports them as leaks at exit.
var _widgets: Array[Node] = []

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The small built-in map's shape, copied rather than imported: world.gd's
# _small_world() is private to that scene, and what matters here is the span.
func _small_world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_settlement(World.Settlement.new("dun-arrow", Vector2(-360, 260), "dwarf", "camp"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "orc", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "human", true))
	w.add_water(Vector2(-190, -70), 100.0)
	w.add_lair(World.Lair.new("dragon-cave", Vector2(680, -400), "dragon"))
	return w

func _fitted(w) -> Minimap:
	var m := Minimap.new()
	var h := Host.new()
	h.world = w
	m.world_map = h
	m.size = Minimap.DEFAULT_SIZE
	m._ensure_fit()
	_widgets.append(m)
	return m

func _rect(m: Minimap) -> Rect2:
	return Rect2(Vector2.ZERO, m.size)

# A world someone has actually walked across, which is what the fog grid is
# for — one waypoint is a circle, a trail is a shape.
func _walked(w) -> Object:
	for i in 6:
		w.reveal(Vector2(i * World.EXPLORE_STEP, i * World.EXPLORE_STEP * 0.4))
	return w

func _walked_world() -> World:
	return _walked(_small_world())

# What share of the inset reads as explored ground.
func _land_share(m: Minimap) -> float:
	var a := 0.0
	for r in m._land:
		a += r.get_area()
	return a / m._inner_rect().get_area()

func _all_within(pts: PackedVector2Array, r: Rect2) -> bool:
	var grown := r.grow(0.01)   # clipped points land exactly on the edge
	for p in pts:
		if not grown.has_point(p):
			return false
	return true

func _in_land(m: Minimap, px: Vector2) -> bool:
	for r in m._land:
		if r.has_point(px):
			return true
	return false

# Every mark this widget draws has to land inside its own rect, or the fit is wrong.
func _all_inside(m: Minimap, w) -> bool:
	for s in w.settlements:
		if not _rect(m).has_point(m.world_to_widget(s.position)):
			return false
	for l in w.lairs:
		if not _rect(m).has_point(m.world_to_widget(l.position)):
			return false
	for p in w.parties:
		if not _rect(m).has_point(m.world_to_widget(p.position)):
			return false
	return true

func _init() -> void:
	# --- the fallback contract: nothing wired up at all ---------------------
	var bare := Minimap.new()
	_widgets.append(bare)
	check(bare.world_map == null, "constructs with .new() and no host")
	check(bare.size == Minimap.DEFAULT_SIZE, "DEFAULT_SIZE is the standalone default the parent can read")
	bare._process(0.016)
	var origin: Vector2 = bare.world_to_widget(Vector2.ZERO)
	check(_rect(bare).has_point(origin), "a null host still fits something sane (the origin lands in the widget)")
	check(bare.widget_to_world(origin).is_equal_approx(Vector2.ZERO), "...and the inverse round-trips")
	bare._gui_input(_click(Vector2(20, 20)))   # no host, no world, no player: must not error
	check(true, "clicking a hostless widget is a no-op, not a crash")

	var empty := _fitted(World.new())
	empty._process(0.016)
	check(empty._land.is_empty(), "an empty world has no explored ground at all")
	check(empty._water.is_empty(), "...and no water")
	check(_rect(empty).has_point(empty.world_to_widget(Vector2.ZERO)), "an empty world still fits without dividing by zero")

	# --- fit: two maps an order of magnitude apart both land inside ---------
	var small := _small_world()
	var ms := _fitted(small)
	check(_all_inside(ms, small), "every mark on the small map lands inside the widget")
	var large = LargeWorld.build()
	var ml := _fitted(large)
	check(_all_inside(ml, large), "every mark on the large map lands inside the widget too")
	check(ml._scale < ms._scale, "the wider map fits at a smaller scale — the extent is measured, not constant")

	# The extreme corner of the content, not just the settlements.
	var far := Vector2(-INF, -INF)
	for s in large.settlements:
		far = far.max(s.position)
	check(_rect(ml).has_point(ml.world_to_widget(far)),
		"the outermost content corner is inside the frame, margin and all")
	check(not _rect(ml).has_point(ml.world_to_widget(far * 4.0)),
		"...and somewhere well outside the world is outside the widget (the fit isn't just clamping)")
	var probe := Vector2(613, -287)
	check(ml.widget_to_world(ml.world_to_widget(probe)).distance_to(probe) < 1.0,
		"world -> widget -> world round-trips to under a world unit")

	# Uniform scale: the map's shape must not stretch to the widget's.
	var wide := _fitted(_small_world())
	wide.size = Vector2(240, 120)
	wide._ensure_fit()
	var dx: float = wide.world_to_widget(Vector2(100, 0)).x - wide.world_to_widget(Vector2.ZERO).x
	var dy: float = wide.world_to_widget(Vector2(0, 100)).y - wide.world_to_widget(Vector2.ZERO).y
	check(absf(dx - dy) < 0.001, "x and y share one scale in a non-square widget")

	# --- fog sampling -------------------------------------------------------
	var fw := World.new()
	fw.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var mf := _fitted(fw)
	check(mf._land.is_empty(), "an unexplored world is all fog")
	fw.reveal(Vector2.ZERO)
	mf._ensure_fit()
	check(not mf._land.is_empty(), "one revealed waypoint puts explored ground on the inset")
	check(_in_land(mf, mf.world_to_widget(Vector2.ZERO)), "the revealed point itself samples as land")
	check(not _in_land(mf, Vector2(mf.size.x - 1.0, mf.size.y - 1.0)),
		"the far corner of the inset is still fog")
	for r in mf._land:
		check(fw.is_explored(mf.widget_to_world(r.get_center())), "a land run's centre is genuinely explored")
		break
	# Sample budget: a fixed grid, so it grows with neither the world nor the
	# widget. A few hundred samples, not thousands.
	var cells: int = Minimap.FOG_SAMPLES * Minimap.FOG_SAMPLES
	check(cells <= 500, "the fog grid is a few hundred samples, whatever the size (%d)" % cells)
	var mbig := _fitted(large)
	check(mbig._land.size() < cells, "runs are merged, so the draw is fewer rects than samples")

	# The parent shrinks this widget on a small window (world.gd caps the side
	# at a third of the shorter viewport side), so the footprint has to survive
	# that: same shape, same share of the inset, at 96px as at 168px.
	var big := _fitted(_walked_world())
	var small_w := _fitted(_walked_world())
	small_w.size = Vector2(96, 96)
	small_w._ensure_fit()
	check(absf(_land_share(big) - _land_share(small_w)) < 0.05,
		"the explored footprint covers the same share of a 96px inset as a 168px one (%.2f vs %.2f)"
			% [_land_share(big), _land_share(small_w)])
	check(_land_share(big) > 0.02, "a walked trail is a legible blob, not a couple of pixels (%.3f)" % _land_share(big))
	var mlarge := _fitted(_walked(LargeWorld.build()))
	check(_land_share(mlarge) > 0.01,
		"...and the same trail still reads on the large map's much wider span (%.3f)" % _land_share(mlarge))

	# --- the cache ----------------------------------------------------------
	var before: int = mf._rebuilds
	mf._ensure_fit(); mf._ensure_fit(); mf._process(0.016)
	check(mf._rebuilds == before, "nothing moved, nothing rebuilt")
	fw.reveal(Vector2(2000, 2000))
	mf._ensure_fit()
	check(mf._rebuilds == before + 1, "a new explored waypoint rebuilds exactly once")
	before = mf._rebuilds
	mf.size = Vector2(120, 120)
	mf._ensure_fit()
	check(mf._rebuilds == before + 1, "a resize refits (the parent owns our size, and changes it)")
	mf.refresh()
	mf._ensure_fit()
	check(mf._rebuilds == before + 2, "refresh() drops the cache for a swapped-out world")

	# --- water and marks are fog-gated -------------------------------------
	var ww := World.new()
	ww.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	ww.add_water(Vector2(0, 0), 80.0)
	ww.add_water(Vector2(3000, 3000), 80.0)
	ww.reveal(Vector2.ZERO)
	var mw := _fitted(ww)
	check(mw._water.size() == 1, "only the explored lake draws; the unseen one stays off the map")
	check(mw._water[0].z >= Minimap.MIN_WATER_PX, "a drawn blob is at least a readable pixel wide")

	# --- the camera region --------------------------------------------------
	var mv := _fitted(small)
	check(mv._refresh_view(), "the first pass picks up the camera quad")
	check(not mv._refresh_view(), "a still camera reports no change — that's the per-frame redraw guard")
	mv.world_map.pan = Vector2(300, 300)
	check(mv._refresh_view(), "panning the real camera moves the quad")
	check(mv._view_world[0] != mv._view_world[2], "the quad is four distinct corners, not a degenerate point")

	# Zoomed in on a wide map: the whole rectangle is inside the inset, so all
	# four of its edges draw and it covers a small part of the world.
	var mz := _fitted(large)
	mz.world_map.pan = Vector2.ZERO
	mz.world_map.zoom = 4.0
	mz._refresh_view(); mz._build_view()
	check(mz._view_fill.size() == 4, "a camera well inside the map clips to the full quad")
	check(mz._view_edges.size() == 8, "...and all four of its edges draw")
	check(Minimap._area(mz._view_fill) / mz._inner_rect().get_area() < 0.2,
		"...covering only the slice of the world actually on screen")

	# Zoomed out past the whole map: drawing a wash over everything says
	# nothing, so nothing is drawn.
	mz.world_map.zoom = 0.05
	mz._refresh_view(); mz._build_view()
	check(mz._view_fill.is_empty() and mz._view_edges.is_empty(),
		"a camera that already contains the whole map draws no region at all")

	# The shot_world.gd case that produced the two stray diagonals: a rotated
	# quad wider than the fitted world, corners far outside the widget.
	var mp := _fitted(_small_world())
	mp.world_map.yaw = deg_to_rad(35.0)
	mp.world_map.zoom = 0.55
	mp.world_map.pan = mp._center
	mp._refresh_view(); mp._build_view()
	check(not mp._view_fill.is_empty(), "a partly-covering camera still draws its region")
	check(not mp._view_edges.is_empty(), "...with the stretch of border that is really inside")
	check(_all_within(mp._view_fill, mp._inner_rect()) and _all_within(mp._view_edges, mp._inner_rect()),
		"nothing the camera region draws escapes the inset — no diagonals across the map")
	var outside := 0
	for i in 4:
		if not mp._inner_rect().has_point(mp.world_to_widget(mp._view_world[i])):
			outside += 1
	check(outside > 0, "...and this really is the case where the quad's own corners are off-widget")

	# A camera looking at a different continent entirely draws nothing.
	mp.world_map.pan = Vector2(90000, 90000)
	mp.world_map.zoom = 4.0
	mp._refresh_view(); mp._build_view()
	check(mp._view_fill.is_empty() and mp._view_edges.is_empty(), "a camera off the fitted map draws nothing")

	# --- click to march -----------------------------------------------------
	var cw := _small_world()
	var mc := _fitted(cw)
	var target := Vector2(40, 30)
	mc._gui_input(_click(target))
	var p = cw.player()
	check(p.goal.distance_to(mc.widget_to_world(target)) < 1.0,
		"a click sets the player's goal to that world point, via World.set_goal")
	var was: Vector2 = p.goal
	mc._gui_input(_wheel(target))
	check(p.goal == was, "a scroll over the inset is not a marching order")

	# --- it survives a live frame ------------------------------------------
	var live := _fitted(_small_world())
	root.add_child(live)
	live.position = Vector2(10, 10)
	for i in 5:
		live.world_map.world.tick(0.1)
		await process_frame
	check(live.is_inside_tree(), "the widget runs in a real tree, drawing every frame, without erroring")
	root.remove_child(live)

	for n in _widgets:
		n.free()
	print("test_minimap: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e

func _wheel(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	e.position = at
	return e
