# #140: the combat board's cached ground layer, and what does and does not
# make it repaint.
#
#   godot --headless --path . -s tests/test_board_ground.gd
#
# The ground (slab, floor texture, mottling, seams, foliage) is ~9 ms of a
# ~11 ms Board redraw, which is why it lives on its own child and is painted
# only when the picture changes. Since #152 the camera pans after every action
# and converges asymptotically, so keying the cache on the view origin meant it
# changed on essentially every frame: measured 410 repaints in 411 frames, i.e.
# the cache never hit once for the whole fight. This pins the contract that
# replaced it — a pan is carried by the layer's position, a zoom and the board
# itself are the only things that repaint it.
extends SceneTree

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	await test_pan_does_not_repaint()
	print("test_board_ground: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_pan_does_not_repaint() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 8:
		await process_frame
	check(main.cb != null, "a fight stood up")
	var board = main._board
	board.size = Vector2(900, 540)     # headless the rect never settles on its own
	# The view is ours to move for the length of this test: no zoom-to-fit
	# snapping the zoom back, and no camera gliding the pan out from under it.
	board._auto_fit = false
	main._cam_follow = false
	board._layout()
	board.tick(1.0 / 60.0)
	var key0: int = board._ground_key

	# A pan: the whole picture moves, none of it is redrawn.
	var repaints := 0
	for i in 60:
		main._pan += Vector2(3.0, -1.5)
		board.tick(1.0 / 60.0)
		if board._ground_key != key0:
			repaints += 1
			key0 = board._ground_key
	check(repaints == 0, "60 frames of panning repaint the ground 0 times (got %d)" % repaints)

	# ...and the layer is carried to where the view now is, so the picture is
	# not merely cached, it is in the right place.
	board._layout(); board._place_layers(Vector2.ZERO)
	check(board._ground.position.is_equal_approx(board._origin - board._ground_at),
		"the cached layer is offset onto the live view")
	check(not board._ground.position.is_equal_approx(Vector2.ZERO),
		"...and that offset is the pan we just applied, not zero")

	# A zoom really does change the picture, so it must repaint.
	var before: int = board._ground_key
	main._zoom *= 1.4
	board.tick(1.0 / 60.0)
	check(board._ground_key != before, "a zoom repaints the ground")
	board._layout(); board._place_layers(Vector2.ZERO)
	check(board._ground.position.is_equal_approx(Vector2.ZERO),
		"a repaint re-bases the layer, so it draws at the origin it was painted in")

	# So does the board under it — a smashed crate is painted into the ground.
	before = board._ground_key
	main.cb.board["objects"] = []
	board.tick(1.0 / 60.0)
	check(board._ground_key != before, "the board changing under it repaints the ground")

	main.queue_free()
	await process_frame
