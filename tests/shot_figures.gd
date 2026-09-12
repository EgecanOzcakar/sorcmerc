# Dev-only: combat scene with the 3D figure layer, past any stealth-ambush
# deployment phase, with a pinned seed. Prints where every figure is placed so a
# missing one is diagnosable. Render recipe (from an agent shell, X11 + force_draw):
#   SORCMERC_SEED=7 godot --display-driver x11 --path . -s tests/shot_figures.gd
extends SceneTree

func _init() -> void:
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
	await create_timer(0.8).timeout
	var fig = main._figures
	var b = main._board
	print("board rect %s  origin %s  hex_px %.1f  K %.1f" % [b.size, b._origin, main.hex_px, fig.px_per_unit()])
	for c in main.cb.combatants:
		var p: Vector2 = b._tok.get(c.id, b._pix(c.pos))
		var w: Vector3 = fig.world_for_screen(p)
		var has: bool = fig.has_figure(c)
		var n = fig._figs.get(c.id)
		print("  %-22s %-6s hex=%s tok=%s world=%s%s" % [c.cname, c.team, c.pos, p.round(), w.round(),
			("  FIG vis=%s pos=%s" % [n.visible, n.position.round()]) if has else ""])
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://figures_screen.png")
	print("saved figures_screen.png  %dx%d  (zoom %.2f, ISO_SQUASH %.2f, %d figures)" % [
		img.get_width(), img.get_height(), main._zoom, b.ISO_SQUASH, fig._figs.size()])
	# two more frames along the 4 s idle loop so the animation is visible as a diff
	for i in 2:
		await create_timer(1.3).timeout
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://figures_idle_%d.png" % (i + 1))
	quit()
