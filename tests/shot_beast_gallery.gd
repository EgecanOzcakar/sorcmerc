# Dev-only: every assets/beasts/*.glb in a grid, fitted the way figures3d.gd
# fits them, so a fresh batch from tools/import_beasts.py can be eyeballed —
# facing, scale, and what the decimator did to the silhouette. Render recipe
# (agent shell, X11 + force_draw — see tests/shot_figures.gd):
#   godot --display-driver x11 --path . -s tests/shot_beast_gallery.gd
extends SceneTree

const Figures = preload("res://scenes/figures3d.gd")
const COLS := 9
const CELL := 3.0

func _init() -> void:
	var paths: Array = []
	# SORCMERC_BEASTS="ogre troll ..." narrows it to a fresh batch.
	var only := OS.get_environment("SORCMERC_BEASTS").split(" ", false)
	for f in DirAccess.get_files_at("res://assets/beasts"):
		if f.ends_with(".glb") and (only.is_empty() or only.has(f.get_basename())):
			paths.append("res://assets/beasts/" + f)
	paths.sort()
	var rows: int = ceili(float(paths.size()) / COLS)
	var sub := SubViewport.new()
	sub.size = Vector2i(COLS * 260, rows * 260)
	sub.msaa_3d = Viewport.MSAA_4X
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment = e
	sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sub.add_child(sun)

	for i in paths.size():
		var m: Node3D = load(paths[i]).instantiate()
		var holder := Node3D.new()
		sub.add_child(holder)
		holder.add_child(m)
		Figures.fit_beast(m, paths[i].get_file().get_basename())
		holder.scale = Vector3.ONE * Figures.FIGURE_SCALE
		# Rows are spaced wider than columns: the tilted camera foreshortens depth by sin(theta).
		holder.position = Vector3((i % COLS - (COLS - 1) * 0.5) * CELL, 0, (i / COLS - (rows - 1) * 0.5) * CELL / 0.55)
		var lbl := Label3D.new()
		lbl.text = paths[i].get_file().get_basename()
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, -0.2, 1.2)
		holder.add_child(lbl)

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * CELL + 2.0
	# Same tilt the board camera has (asin(ISO_SQUASH), ~0.55), so facing reads as it will in play.
	cam.look_at_from_position(Vector3(0, 30.0 * 0.55, 30.0 * 0.84), Vector3(0, 0.3, 0), Vector3.UP)
	cam.current = true

	for i in 20:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	sub.get_texture().get_image().save_png("res://beast_gallery.png")
	print("beast_gallery.png: %d beasts" % paths.size())
	quit()
