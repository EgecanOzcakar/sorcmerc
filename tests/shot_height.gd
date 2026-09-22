# Dev-only: a board with raised ground on it, framed close enough to read the
# shelves. Needs a display (it renders); not part of run_tests.sh.
#   SORCMERC_SEED=424242 godot --path . --resolution 1280x800 -s tests/shot_height.gd
#   -> height_board.png
extends SceneTree

const Settings = preload("res://core/settings.gd")

func _init() -> void:
	Settings.current().reaction_prompts = false   # nobody here to answer one
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	# Past deployment: the camera only starts following once somebody acts.
	var guard := 0
	while guard < 900:
		await process_frame
		guard += 1
		if main.cb == null or main.cb.is_over():
			continue
		if main._busy:
			continue
		if main._mode == "deploy":
			var kids: Array = main._buttons.get_children()
			for i in range(kids.size() - 1, -1, -1):
				if kids[i] is Button and not kids[i].disabled:
					kids[i].pressed.emit()
					break
			continue
		var cur = main.cb.current()
		if main._mode == "idle" and cur != null and cur.team == "party" and cur.conscious():
			if main.cb.round_num >= 2:
				break
			main._end_turn()
	var raised: int = main.cb.board.get("height", {}).size()
	# The whole board, not the close follow: the shelves are a property of the
	# map and this picture is about the map.
	main._cam_follow = false
	main._board._auto_fit = true
	main._pan = Vector2.ZERO
	for _i in 40:
		await process_frame
	await create_timer(0.6).timeout
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://height_board.png")
	print("saved height_board.png  %dx%d  (%d raised hexes on this board)" % [
		img.get_width(), img.get_height(), raised])
	quit()
