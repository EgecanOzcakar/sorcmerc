# Dev-only: every class model (data/classes.json) standing in a row, idle
# animation playing, so a new GLB can be eyeballed the moment it lands —
# without needing a real combat encounter to field that class. Whatever
# key has no GLB yet on disk is skipped and named in the printed summary.
# Render recipe (agent shell, X11 + force_draw — see tests/shot_figures.gd):
#   godot --display-driver x11 --path . -s tests/shot_class_gallery.gd
extends SceneTree

const CLASSES := ["barbarian", "bard", "cleric", "druid", "fighter", "monk",
	"paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard"]

func _init() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(1600, 420)
	sub.msaa_3d = Viewport.MSAA_4X
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	root.add_child(sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 1.0
	env.environment = e
	sub.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sub.add_child(sun)

	var found: Array = []
	var missing: Array = []
	var slot := 0
	for key in CLASSES:
		var path := "res://assets/figures/%s_idle.glb" % key
		if not ResourceLoader.exists(path):
			missing.append(key)
			continue
		var m: Node3D = load(path).instantiate()
		sub.add_child(m)
		m.position = Vector3(slot * 1.5 - (CLASSES.size() - 1) * 0.75, 0, 0)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap:
			var clip: String = ap.get_animation_list()[0]
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
		found.append(key)
		slot += 1

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 1.0, 6)
	cam.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	cam.current = true

	for i in 20:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	sub.get_texture().get_image().save_png("res://class_gallery.png")
	print("class_gallery.png: %d/%d classes shown — %s" % [
		found.size(), CLASSES.size(), (", ".join(found))])
	if not missing.is_empty():
		print("still missing: %s" % ", ".join(missing))
	quit()
