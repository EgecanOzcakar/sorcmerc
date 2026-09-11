# Dev-only, the same job tests/shot.gd does for the combat board: load the world
# map, let it settle, save a PNG. The O11 art swap is a visual change, so this is
# the check that actually fails when the ground tiles or the town buildings stop
# landing where the projection puts them — the headless tests never see a pixel.
#   godot --path . -s tests/shot_world.gd            # 1x, the default framing
#   SHOT_ZOOM=0.4 godot --path . -s tests/shot_world.gd   # zoomed out
extends SceneTree

func _init() -> void:
	var screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	for i in 30:
		await process_frame
	var z := OS.get_environment("SHOT_ZOOM")
	if z != "":
		screen.set_zoom(float(z))
	screen.queue_redraw()
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://world_screen.png")
	print("saved world_screen.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
