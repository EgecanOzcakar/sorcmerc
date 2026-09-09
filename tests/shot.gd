# Dev-only: load the scene, let it settle on a hero turn, save a PNG.
#   godot --path . -s tests/shot.gd
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
	img.save_png("res://combat_screen.png")
	print("saved combat_screen.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
