# The board-legibility pass (2026-09-25): four reports that the combat view
# was showing the player something that was not there.
#
#   #242  a raised tile showed its own wash AND the wash of the lower tile
#         behind it, stacked into a third colour across the step
#   #239  "z fighting": after a zoom or a pan the board's own layer (every
#         token's shadow disc, the active ring) stayed where the tokens used to
#         be while the figures and HP bars moved on
#   #195  HP bars painted over the log, the order strip and the skill bar, and
#         in roster order rather than depth order
#   #243  the camp's ash was a near-black mound, read as a stray shadow
#
# What a picture looks like is tests/shot_board_legibility.gd's; this pins the
# claims underneath each one that can be read back headless.
#
#   godot --headless --path . -s tests/test_board_legibility.gd
extends SceneTree

const Hex = preload("res://core/hex.gd")
const BoardProps = preload("res://scenes/board_props.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 8:
		await process_frame
	check(main.cb != null, "a fight stood up")
	var board = main._board
	board.size = Vector2(900, 540)     # headless the rect never settles on its own
	board._auto_fit = false
	main._cam_follow = false
	board._layout()
	board.tick(1.0 / 60.0)
	test_overlay_stays_on_its_own_tile(main, board)
	await test_view_move_repaints_the_board(main, board)
	await test_bars_live_inside_the_board(main, board)
	test_ash_is_not_a_shadow()
	print("test_board_legibility: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _total(polys: Array) -> float:
	var t := 0.0
	for p in polys:
		t += _area(p)
	return t


# #242. Raise one hex on this board by hand — so the test does not depend on
# which seed grew which shelf — and ask about the hex directly behind it.
func test_overlay_stays_on_its_own_tile(main, board) -> void:
	var cb = main.cb
	var on := {}
	for h in cb.board["hexes"]:
		on[h] = true
	var depth := func(h: Vector2i) -> float: return board._flat_pix(h).y
	var front := Vector2i.ZERO
	var back := Vector2i.ZERO
	var found := false
	for h in cb.board["hexes"]:
		for n in Hex.neighbors(h):
			# the neighbour straight behind: the most depth between the two
			if on.has(n) and depth.call(h) - depth.call(n) > main.hex_px * 1.5:
				front = h
				back = n
				found = true
				break
		if found:
			break
	check(found, "the board has a hex with one straight behind it")
	var saved = cb.board.get("height", null)
	var heights := {}
	cb.board["height"] = heights
	board.tick(1.0 / 60.0)   # the board changed: the ground key moves and so does the cache
	var s: float = main.hex_px
	var wash: PackedVector2Array = board._hex_poly(board._pix(back), s - 2.0)
	check(board._seen(back, wash).size() == 1 and is_equal_approx(_total(board._seen(back, wash)), _area(wash)),
		"on a flat board a wash is drawn whole, as it always was")

	heights[front] = 2
	cb.board["height"] = heights.duplicate()
	board.tick(1.0 / 60.0)
	wash = board._hex_poly(board._pix(back), s - 2.0)
	var top: PackedVector2Array = board._hex_poly(board._pix(front), s)
	check(not Geometry2D.intersect_polygons(wash, top).is_empty(),
		"the raised tile's top face really does stand over the tile behind it")
	var seen: Array = board._seen(back, wash)
	check(_total(seen) < _area(wash) - 1.0,
		"the wash behind the shelf loses the part the shelf hides (%.0f of %.0f px)" % [_total(seen), _area(wash)])
	var bleed := 0.0
	for p in seen:
		bleed += _total(Geometry2D.intersect_polygons(p, top))
	check(bleed < 0.5, "and none of it lands on the raised tile's face (%.1f px)" % bleed)
	var own: PackedVector2Array = board._hex_poly(board._pix(front), s - 2.0)
	check(is_equal_approx(_total(board._seen(front, own)), _area(own)),
		"the raised tile's own wash is whole: nothing in front of it is higher")
	check(board._covering(front).is_empty(), "...and nothing is listed as covering it")
	check(front in board._covering(back), "the hex behind lists the shelf as what covers it")
	if saved == null:
		cb.board.erase("height")
	else:
		cb.board["height"] = saved
	board.tick(1.0 / 60.0)


# #239. Move the view the way a _layout() does — _pan written directly, which
# is what the follow-cam and the pan clamp do, with nothing queuing a redraw —
# and the board's own layer has to be painted again in the new view.
func test_view_move_repaints_the_board(main, board) -> void:
	var draws := [0]
	var count := func(): draws[0] += 1
	board.draw.connect(count)
	for _i in 3:
		await process_frame
	var before: int = draws[0]
	main._pan += Vector2(37.0, -21.0)
	for _i in 3:
		await process_frame
	check(draws[0] > before, "a view that moved inside the layout repaints the board (%d draws)" % (draws[0] - before))
	board.draw.disconnect(count)


# #195. The bars are on a Control of their own that is the board's rect and
# clips to it, so a body off the edge cannot paint over the chrome.
func test_bars_live_inside_the_board(main, board) -> void:
	for _i in 2:
		await process_frame
	var bars: Control = main._hud_bars
	check(bars != null and bars.get_parent() == main._hud_layer, "the bars are on the HUD layer")
	check(bars.clip_contents, "and clipped")
	check(bars.position.is_equal_approx(board.global_position) and bars.size.is_equal_approx(board.size),
		"to exactly the board's rect (%s %s vs %s %s)" % [bars.position, bars.size, board.global_position, board.size])
	check(bars.get_index() < main._hud_overlay.get_index(),
		"under the odds chips and damage numbers, which stay unclipped")


# #243. The model's own albedo averages ~0.157 — shadow-dark. Lifted, the
# mound's mean has to land clearly above the camp's floor as the board draws it
# (PALETTES camp 0x2a2a26 under a FLOOR_TONE'd texture: ~0.2), and something
# has to stand on it.
func test_ash_is_not_a_shadow() -> void:
	var n: Node3D = BoardProps.build("ash", 7)
	var lifted := 0.0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_surface_override_material(0) as BaseMaterial3D
		if m != null and m.albedo_texture != null:
			lifted = maxf(lifted, 0.157 * m.albedo_color.r)
	check(lifted >= 0.45, "the ash mound's mean albedo is lifted to %.2f, want >= 0.45" % lifted)
	check(n.find_children("kit_boardprop", "Node3D", true, false).size() >= 1,
		"the charred logs and embers are laid over the model")
	var reds := 0
	for part in BoardProps.dressing("ash", 7):
		if String(part["role"]) == "fire":
			reds += 1
	check(reds >= 1, "with at least one ember in them")
	n.free()
	# ...and the cached scene everyone else instantiates is untouched.
	var fresh: Node3D = load(BoardProps.MODEL_DIR % "ash").instantiate()
	for mi in fresh.find_children("*", "MeshInstance3D", true, false):
		check((mi as MeshInstance3D).get_surface_override_material(0) == null,
			"the shared model keeps its own material")
	fresh.free()
