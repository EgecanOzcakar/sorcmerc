# Dev-only, run in YOUR session (windows launched from an agent shell here do not
# present frames): load the combat scene with the 3D figure layer, settle on a hero
# turn, save a PNG. Mirrors tests/shot.gd.
#   godot --path . -s tests/shot_figures.gd
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	var guard = 0
	while main.cb and not main.cb.is_over() and main.cb.round_num < 2 and guard < 40:
		await process_frame
		guard += 1
	for i in 20:
		await process_frame
	await create_timer(0.8).timeout
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://figures_screen.png")
	print("saved figures_screen.png  %dx%d  (zoom %.2f, ISO_SQUASH %.2f, %d figures)" % [
		img.get_width(), img.get_height(), main._zoom, main._board.ISO_SQUASH, main._figures._figs.size()])
	quit()
