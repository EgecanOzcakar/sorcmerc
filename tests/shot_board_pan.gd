# #159: the combat board's ground is carried onto the moving view instead of
# repainted onto it. A slow pan across the board, one frame each, plus the
# count of ground repaints while it happens — 0 is the contract
# (tests/test_board_ground.gd pins it; this shows what it looks like).
#
# Not headless — the capture hangs without a real rendering driver:
#   godot --path . -s tests/shot_board_pan.gd
extends SceneTree

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_pan"))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	if main._mode == "deploy":
		main._press_hotkey(-1)
		for i in 60:
			await process_frame
	var board = main._board
	main._cam_follow = false      # the pan under test is ours, not the camera's glide
	board._auto_fit = false
	var key: int = board._ground_key
	var repaints := 0
	for i in 30:
		main._pan += Vector2(7.0, -3.0)
		board.tick(1.0 / 60.0)
		if board._ground_key != key:
			repaints += 1
			key = board._ground_key
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://shots_pan/pan_%02d.png" % i)
	print("panned 30 frames, ground repaints: %d" % repaints)
	quit()
