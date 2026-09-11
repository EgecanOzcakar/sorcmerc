# Dev-only: Settings -> Art credits, the license-required attribution screen.
#   godot --path . -s tests/shot_credits.gd
extends SceneTree

func _init() -> void:
	var s = load("res://scenes/settings/settings.tscn").instantiate()
	root.add_child(s)
	for i in 20:
		await process_frame
	s._show_credits()
	for i in 10:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://lpc_spike_credits.png")
	print("saved lpc_spike_credits.png %dx%d" % [img.get_width(), img.get_height()])
	quit()
