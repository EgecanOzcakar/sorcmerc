# Dev-only: load the scene, let it settle on a hero turn, save a PNG.
#   godot --path . -s tests/shot.gd
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	# nudge to a mid-fight state: run a few AI turns
	var guard = 0
	while main.cb and not main.cb.is_over() and main.cb.round_num < 2 and guard < 40:
		await process_frame
		guard += 1
	var z := OS.get_environment("SHOT_ZOOM")
	if z != "":
		main.set_zoom(float(z))
	await create_timer(0.4).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://combat_screen.png")
	print("saved combat_screen.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
