# Dev-only: the raised ground on a combat board, framed close (#197). Needs a
# display; not part of run_tests.sh.
#   SORCMERC_SEED=424242 godot --path . --resolution 1280x800 -s tests/shot_height_close.gd
#   -> height_close.png
#   SHOT_NO_PAN=1 zooms without the pan, so the ground layer's origin stays on
#   screen — the framing that drew a floor even before #194's culling fix.
#   SHOT_NO_ZOOM=1 pans without the zoom: the whole board, shelf in the middle.
extends SceneTree

const Settings = preload("res://core/settings.gd")

func _init() -> void:
	Settings.current().reaction_prompts = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	var guard := 0
	while guard < 900 and main._mode == "deploy":
		await process_frame
		guard += 1
		var kids: Array = main._buttons.get_children()
		for i in range(kids.size() - 1, -1, -1):
			if kids[i] is Button and not kids[i].disabled:
				kids[i].pressed.emit()
				break
	var hs: Dictionary = main.cb.board.get("height", {})
	var mid := Vector2i.ZERO
	var best := -1
	for hx in hs:   # the hex with the most raised ground around it
		var n := 0
		for h2 in hs:
			if (h2 - hx).length() <= 3:
				n += 1
		if n > best:
			best = n
			mid = hx
	main._cam_follow = false
	main._board._auto_fit = false
	for _i in 10:
		await process_frame
	var b = main._board
	if OS.get_environment("SHOT_NO_ZOOM") == "":
		b._zoom_at(b.size * 0.5, 1.9)
	for _i in 5:
		await process_frame
	if OS.get_environment("SHOT_NO_PAN") == "":
		main.pan_by(b.size * 0.5 - b._pix(mid))
	for _i in 40:
		await process_frame
	await create_timer(0.6).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://height_close.png")
	print("saved height_close.png around %s (%d raised hexes)" % [str(mid), hs.size()])
	quit()
