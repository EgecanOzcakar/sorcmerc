# Two looks at the overworld, because there are two things worth looking at now
# that the map is 3D: the view it opens on, and the same ground from somewhere
# else. A camera that turns is the feature; a screenshot that only ever shows
# it from the default angle is not evidence of it.
#
# Not headless — the capture hangs without a real rendering driver:
#   godot --path . -s tests/shot_world.gd
extends SceneTree

func _init() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	for i in 40:
		await process_frame
	w.set_zoom(0.55)
	w._pan = Vector2(60, -180)
	await _shoot(w, "res://world_screen.png")
	print("dioramas: %d / %d settlements, %d trees"
		% [w._settlements3d._dioramas.size(), w.world.settlements.size(), w._view.scatter.tree_count()])

	# Round to the far side and up off the ground, centred on a town so there is
	# something with a near and a far side in shot.
	w.set_zoom(1.1)
	w.orbit_by(115.0)
	w.tilt_by(30.0)
	w.center_on(w.world.settlements[0].position)
	await _shoot(w, "res://world_turned.png")
	print("turned: yaw %.0f, pitch %.0f" % [w.yaw(), w.pitch()])
	quit()


func _shoot(w, path: String) -> void:
	for i in 6:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path.get_file())
