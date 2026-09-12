# Dev-only: one row per faction (camp/town/city), each saved as its own PNG —
# unambiguous style-consistency check, no grid-position guessing needed.
# Whatever key has no GLB yet is skipped and named in the printed summary.
# Render recipe (agent shell, X11 + force_draw — see tests/shot_figures.gd):
#   godot --display-driver x11 --path . -s tests/shot_settlement_gallery.gd
extends SceneTree

const FACTIONS := ["dwarf", "elf", "human", "orc"]
const SIZES := ["camp", "town", "city"]

func _init() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(1400, 500)
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

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.0
	cam.look_at_from_position(Vector3(0, 9, 13), Vector3(0, 0.5, 0), Vector3.UP)
	cam.current = true

	var missing: Array = []
	for race in FACTIONS:
		var nodes: Array = []
		var shown: Array = []
		for col in SIZES.size():
			var size_key: String = SIZES[col]
			var path := "res://assets/settlements/%s_%s.glb" % [race, size_key]
			if not ResourceLoader.exists(path):
				missing.append("%s_%s" % [race, size_key])
				continue
			var m: Node3D = load(path).instantiate()
			sub.add_child(m)
			var aabb := AABB()
			for mesh in m.find_children("*", "MeshInstance3D", true, false):
				var a: AABB = mesh.transform * mesh.get_aabb()
				aabb = a if aabb.size == Vector3.ZERO else aabb.merge(a)
			var biggest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if biggest > 0.0001:
				var k := 2.0 / biggest
				m.scale = Vector3.ONE * k
				m.position -= Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y,
					aabb.position.z + aabb.size.z * 0.5) * k
			m.position += Vector3(col * 5.5 - 5.5, 0, 0)
			nodes.append(m)
			shown.append("%s_%s" % [race, size_key])
		for i in 15:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		sub.get_texture().get_image().save_png("res://settlement_gallery_%s.png" % race)
		print("settlement_gallery_%s.png: %s" % [race, ", ".join(shown)])
		for n in nodes:
			n.queue_free()
		await process_frame

	if not missing.is_empty():
		print("still missing: %s" % ", ".join(missing))
	quit()
