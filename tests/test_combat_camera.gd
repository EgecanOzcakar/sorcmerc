# #152: the combat camera follows the action. The fit-all view is what the
# board opens on; the first focus glides it in to ZOOM_FOLLOW over the actor
# (or holds a pair in frame), a pan or zoom of the player's own holds the view
# until the next action, and Home toggles between following and the whole
# board. The chrome scales by the player's zoom, never the camera's.
#   godot --headless --path . -s tests/test_combat_camera.gd
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
	var ilsa = null
	var foe = null
	for c in main.cb.combatants:
		if c.cname == "Ilsa Vane":
			ilsa = c
		elif c.team == "foe" and foe == null:
			foe = c
	check(ilsa != null and foe != null, "a hero and a foe to look at")
	var fit: float = main._zoom
	check(main._cam_follow and fit < main.ZOOM_FOLLOW, "the fight opens fit-all, at less than the follow zoom (%.2f)" % fit)
	var bar_u: float = main._buttons.get_child(0).custom_minimum_size.x if main._buttons.get_child_count() > 0 else -1.0

	# The camera goes to the actor: FAST lands it in a frame or two.
	main.focus_cam([ilsa.id])
	for i in 6:
		await process_frame
	check(is_equal_approx(main._zoom, main.ZOOM_FOLLOW), "focused, the camera is at ZOOM_FOLLOW (%.2f)" % main._zoom)
	var at: Vector2 = board._pix(ilsa.pos)
	check(at.distance_to(board.size * 0.5) < 4.0, "...centred on the actor (%.0f px off)" % at.distance_to(board.size * 0.5))
	check(main._buttons.get_child_count() == 0 or main._buttons.get_child(0).custom_minimum_size.x == bar_u,
		"the chrome did not move with the camera")
	main.set_zoom(main._zoom * 1.3)
	check(main._buttons.get_child_count() == 0 or main._buttons.get_child(0).custom_minimum_size.x == bar_u,
		"...nor with the player's own zoom: the chrome is Settings.chrome_scale()'s alone")

	# A pair is kept in frame, the midpoint centred, the zoom lowered if it must.
	main.focus_cam([ilsa.id, foe.id])
	for i in 6:
		await process_frame
	var a: Vector2 = board._pix(ilsa.pos)
	var b: Vector2 = board._pix(foe.pos)
	check(((a + b) * 0.5).distance_to(board.size * 0.5) < 4.0, "a pair is centred on its midpoint")
	check(Rect2(Vector2.ZERO, board.size).grow(-board.CAM_MARGIN + 8.0).has_point(a)
		and Rect2(Vector2.ZERO, board.size).grow(-board.CAM_MARGIN + 8.0).has_point(b),
		"...and both are inside the margin")
	check(main._zoom <= main.ZOOM_FOLLOW + 0.001, "never past ZOOM_FOLLOW")

	# The player's own pan holds the view; the next action takes it back.
	main.pan_by(Vector2(200, 0))
	for i in 4:
		await process_frame
	check(main._cam_hold and board._pix(ilsa.pos).distance_to(a) > 150.0, "a pan of the player's own sticks")
	main.focus_cam([ilsa.id])
	for i in 6:
		await process_frame
	check(not main._cam_hold and board._pix(ilsa.pos).distance_to(board.size * 0.5) < 4.0, "...until the next action")

	# Home: the whole board again, and the chrome with it; Home again follows.
	main.toggle_cam()
	for i in 6:
		await process_frame
	check(not main._cam_follow and is_equal_approx(main._zoom, fit),
		"Home fits the whole board again (%.2f)" % main._zoom)
	main.toggle_cam()
	for i in 6:
		await process_frame
	check(main._cam_follow and is_equal_approx(main._zoom, main.ZOOM_FOLLOW), "Home again is back on the action")

	# A turn is framed with the enemies near the actor, not the actor alone.
	var ctx: Array = main._cam_context(ilsa)
	check(ctx[0] == ilsa.id and ctx.size() > 1, "a turn's frame holds the actor and the enemies within reach (%d)" % ctx.size())
	check(ctx.all(func(id): return id == ilsa.id or main.cb.combatants.any(func(c): return c.id == id and c.team == "foe" and c.pos.distance_to(ilsa.pos) < 40)),
		"...only enemies, only near ones")

	print("test_combat_camera: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
