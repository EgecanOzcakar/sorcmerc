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
	# advance a few more hero turns so someone is engaged, then aim an attack
	var g2 = 0
	while main.cb and not main.cb.is_over() and main.cb.round_num < 3 and g2 < 60:
		await process_frame
		g2 += 1
	var h = main.cb.current() if main.cb else null
	if OS.get_environment("SHOT_AIM") != "" and h and h.team == "party" and h.conscious():
		if main.cb.enemies_of(h).any(func(f): return main.cb.in_reach(h, f)):
			main._enter_target(h, "attack")
			main._board._hover = main.cb.enemies_of(h).filter(func(f): return main.cb.in_reach(h, f))[0].pos
	await create_timer(0.4).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://combat_screen.png")
	print("saved combat_screen.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
