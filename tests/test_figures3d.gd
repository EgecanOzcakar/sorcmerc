# Headless: the 3D figure layer boots, is wired to the Board, and its camera
# projection is the exact inverse of Board._iso — a figure at hex H lands on _pix(H).
#   godot --headless --path . -s tests/test_figures3d.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	var board = main._board
	var fig = main._figures
	check(fig != null, "Figures3D layer exists on main")
	check(fig.get_parent() == board, "layer is a child of the Board (draws over it, clipped to it)")
	check(fig.mouse_filter == Control.MOUSE_FILTER_IGNORE, "layer ignores mouse so Board still gets input")
	check(is_equal_approx(board.ISO_SQUASH, 0.71), "TFT-style camera: ISO_SQUASH is 0.71 (~45 deg)")
	var el_deg := rad_to_deg(fig.theta())
	check(is_equal_approx(fig.theta(), asin(board.ISO_SQUASH)), "camera elevation is exactly asin(ISO_SQUASH) — one source of truth")
	check(el_deg > 44.0 and el_deg < 46.0, "elevation sits in the TFT-style 44-46 deg band (got %.2f)" % el_deg)

	# has_figure follows the model lookup (class for heroes, faction for foes),
	# not team — coverage is whatever GLBs exist under assets/figures, same
	# design as LpcArt.BY_MONSTER falling through to the vector tier.
	var expect_figs := 0
	for c in main.cb.combatants:
		var path: String = fig._model_path(c)
		if path != "" and ResourceLoader.exists(path):
			expect_figs += 1
	check(fig._figs.size() == expect_figs, "one figure per modeled combatant (%d)" % expect_figs)
	for c in main.cb.combatants:
		var path: String = fig._model_path(c)
		check(fig.has_figure(c) == (path != "" and ResourceLoader.exists(path)),
			"has_figure matches model lookup for %s" % c.cname)

	# Projection round-trip: Board._pix(H) -> world -> back must be the same pixel.
	board._origin = Vector2(311.0, 187.0)     # any non-zero origin, incl. pan
	var worst := 0.0
	for c in main.cb.combatants:
		var p: Vector2 = board._pix(c.pos)
		var w: Vector3 = fig.world_for_screen(p)
		check(is_zero_approx(w.y), "ground point has y == 0 for %s" % c.cname)
		var back: Vector2 = fig.screen_for_world(w)
		worst = maxf(worst, p.distance_to(back))
	check(worst < 1e-3, "screen->world->screen round-trips within 1e-3 px (worst %.6f)" % worst)

	# The squash really is the camera tilt: one unit of depth projects to SQUASH px/K.
	var K: float = fig.px_per_unit()
	var dz: Vector2 = fig.screen_for_world(Vector3(0, 0, 1)) - fig.screen_for_world(Vector3.ZERO)
	check(is_equal_approx(dz.y / K, board.ISO_SQUASH), "1 unit of depth -> ISO_SQUASH px/unit on screen")
	# and height foreshortens by cos(theta), so a 1.9-unit figure is 1.9*K*cos(theta) px tall
	var dy: Vector2 = fig.screen_for_world(Vector3(0, 1, 0)) - fig.screen_for_world(Vector3.ZERO)
	check(is_equal_approx(-dy.y / K, cos(fig.theta())), "1 unit of height -> cos(theta) px/unit on screen")

	# #71/#78: a pan or a zoom moves the whole view at once — the displayed token
	# is carried with it, never walked to its new screen spot (which lagged the
	# drag and turned the figure to face it).
	for i in 20:
		await process_frame   # any opening slide settles
	var c0 = main.cb.combatants[0]
	var yaw_before: float = fig._figs[c0.id].rotation.y if fig._figs.has(c0.id) else 0.0
	main.pan_by(Vector2(300, 120))
	await process_frame; await process_frame
	check(board._tok[c0.id].is_equal_approx(board._pix(c0.pos)), "after a pan the token is already on its hex — no slide")
	main.set_zoom(main._zoom * 1.5)
	await process_frame; await process_frame
	check(board._tok[c0.id].is_equal_approx(board._pix(c0.pos)), "after a zoom the token is already on its hex — no slide")
	if fig._figs.has(c0.id):
		check(is_equal_approx(fig._figs[c0.id].rotation.y, yaw_before), "moving the camera does not turn the figure")

	print("test_figures3d: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
