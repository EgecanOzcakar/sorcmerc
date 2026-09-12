# Dev-only: a goblin figure moves to another hex and turns to face the way it went.
# Captures four frames — before, two mid-slide, arrived — to shots_move/NN.png.
# Render recipe (agent shell): X11 + force_draw, see shot_figures.gd.
#   SORCMERC_SEED=7 godot --display-driver x11 --path . -s tests/shot_move.gd
extends SceneTree

var _n := 0

func _grab(main, label: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://shots_move/%d_%s.png" % [_n, label])
	_n += 1

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_move"))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	if main._mode == "deploy":                       # ambush deployment: begin it
		main._press_hotkey(-1)
		for i in 90:
			await process_frame
	for i in 30:
		await process_frame

	var cb = main.cb
	var fig = main._figures
	var b = main._board
	# a foe with a figure that can take a 2-3 hex step toward the party (stays on screen)
	var hero = cb.current()
	var mover = null
	var dest := Vector2i(-99, -99)
	for c in cb.combatants:
		if not fig.has_figure(c) or not c.conscious():
			continue
		c.econ["move_left"] = 99                       # scripted demo: ignore the action economy
		var field: Dictionary = cb.move_field(c)
		var best := 1e9
		for hx in field:
			var step: int = int(field[hx])
			if step < 2 or step > 3:
				continue
			var d: float = Vector2(hx - hero.pos).length()
			if d < best:
				best = d; dest = hx
		if best < 1e9:
			mover = c
			break
	if mover == null:
		print("no foe could move"); quit(); return

	var n: Node3D = fig._figs[mover.id]
	print("mover %s at %s -> %s   yaw before %.1f deg" % [mover.cname, mover.pos, dest, rad_to_deg(n.rotation.y)])
	await _grab(main, "before")
	cb.move_to(mover, dest)
	await process_frame; await process_frame; await process_frame
	await _grab(main, "slide_a")
	for i in 4:
		await process_frame
	await _grab(main, "slide_b")
	for i in 45:
		await process_frame
	await _grab(main, "arrived")
	print("mover now at %s   tok %s   yaw after %.1f deg" % [mover.pos, b._tok.get(mover.id).round(), rad_to_deg(n.rotation.y)])
	print("saved %d frames to shots_move/" % _n)
	quit()
