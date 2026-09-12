extends SceneTree

func _init() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	for i in 40:
		await process_frame
	w.set_zoom(0.55)
	w._pan = Vector2(60, -180)
	for i in 5:
		await process_frame
	print("dioramas: %d / %d settlements" % [w._settlements3d._dioramas.size(), w.world.settlements.size()])
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://world_screen.png")
	print("saved world_screen.png")
	quit()
