# Dev-only: look at the modular lair dioramas (scenes/world/lair_kit.gd) and
# compare them against the GLB tier where one exists.
#   godot --display-driver x11 --path . -s tests/shot_lair_kit.gd
# (needs a display — same force_draw recipe as tests/shot_settlement_kit.gd;
# under a headless box, `xvfb-run -a` in front of it.)
#
# Two outputs:
#
#   lair_kit_gallery.png   all five, close up, at true relative scale.
#   lair_kit_vs_glb.png    the money shot: both sources under the map's OWN
#                          projection at the map's OWN pixel size, upscaled 4x
#                          nearest. The two right-hand columns have no GLB at
#                          all — sunken-ruins and zombie-graveyard render as
#                          World._draw_lair()'s skull glyph today — so their
#                          GLB row is left as empty background on purpose.
#                          That gap IS the result for those two.
extends SceneTree

const Kit = preload("res://scenes/world/lair_kit.gd")
const Lairs3D = preload("res://scenes/world/lairs3d.gd")
const MapView = preload("res://scenes/world/world.gd")

const IDS := ["goblin-warren", "giant-hold", "dragon-cave", "sunken-ruins",
	"zombie-graveyard"]

const PX_PER_UNIT := 1.85            # MapView.ISO_GAIN
const SQUASH := 0.38                 # MapView.ISO_SQUASH
const UPSCALE := 4


func _init() -> void:
	assert(is_equal_approx(PX_PER_UNIT, MapView.ISO_GAIN))
	assert(is_equal_approx(SQUASH, MapView.ISO_SQUASH))
	await _gallery()
	await _compare()
	quit()


func _rig(w: int, h: int, shadows := false) -> Array:
	var sub := SubViewport.new()
	sub.size = Vector2i(w, h)
	sub.msaa_3d = Viewport.MSAA_4X
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.23, 0.26, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.55, 0.60)
	e.ambient_light_energy = 1.0
	env.environment = e
	sub.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = shadows
	sub.add_child(sun)

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 4000.0
	cam.current = true
	return [sub, cam]


func _aim(cam: Camera3D, centre: Vector3, view_height_units: float) -> void:
	var th := asin(SQUASH)
	cam.size = view_height_units
	cam.look_at_from_position(centre + Vector3(0.0, sin(th), cos(th)) * 900.0,
		centre, Vector3.UP)


func _gallery() -> void:
	var rig := _rig(1700, 420, true)
	var sub: SubViewport = rig[0]
	var cam: Camera3D = rig[1]
	var x := -2.0 * 46.0
	for id in IDS:
		var n := Kit.build(id)
		sub.add_child(n)
		n.position = Vector3(x, 0, 0)
		x += 46.0
	_aim(cam, Vector3(0, 9, 0), 58.0)
	for i in 12:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	sub.get_texture().get_image().save_png("res://lair_kit_gallery.png")
	print("lair_kit_gallery.png: %s" % ", ".join(IDS))
	sub.queue_free()
	await process_frame


# Both sources at 1:1 map pixels — a lair is 22 units * 1.85 px/unit, i.e. 41px
# tall, and that is the entire argument. Rows: glb, kit, glb+shadow, kit+shadow,
# so the shared rig's missing shadow can be judged separately from the sources.
func _compare() -> void:
	var cell := Vector2i(130, 96)
	var full := Image.create(cell.x * IDS.size(), cell.y * 4, false, Image.FORMAT_RGBA8)
	# Pre-fill with the rig's own background, or the cells with no GLB come out
	# as Image.create()'s transparent black and read as a broken render rather
	# than as "there is nothing here", which is the actual finding.
	full.fill(Color(0.23, 0.26, 0.17))
	var row := 0
	for shadows in [false, true]:
		for source in ["glb", "kit"]:
			var col := 0
			for id in IDS:
				var img = await _one(id, source, shadows, cell)
				if img != null:
					full.blit_rect(img, Rect2i(Vector2i.ZERO, cell),
						Vector2i(col * cell.x, row * cell.y))
				col += 1
			row += 1
	full.resize(full.get_width() * UPSCALE, full.get_height() * UPSCALE,
		Image.INTERPOLATE_NEAREST)
	full.save_png("res://lair_kit_vs_glb.png")
	print("lair_kit_vs_glb.png  rows: glb / kit / glb+shadow / kit+shadow, "
		+ "cols: %s, 1:1 map pixels upscaled %dx "
		% [", ".join(IDS), UPSCALE]
		+ "(blank glb cells = no model exists)")


# null when this source has nothing for this lair — the caller leaves the cell
# empty rather than substituting the other source, because the empty cell is
# the honest picture of what ships today.
func _one(id: String, source: String, shadows: bool, cell: Vector2i):
	var path := String(Lairs3D.MODELS.get(id, ""))
	if source == "glb" and not ResourceLoader.exists(path):
		return null
	var rig := _rig(cell.x, cell.y, shadows)
	var sub: SubViewport = rig[0]
	var cam: Camera3D = rig[1]
	var n: Node3D
	if source == "kit":
		n = Kit.build(id)
	else:
		n = load(path).instantiate()
		_fit_height(n, Kit.HEIGHT)
	sub.add_child(n)
	_aim(cam, Vector3(0, Kit.HEIGHT * 0.42, 0), float(cell.y) / PX_PER_UNIT)
	for i in 12:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := sub.get_texture().get_image()
	sub.queue_free()
	await process_frame
	return img


# lairs3d.gd's own _fit_height, copied — that one is a method on the
# SubViewportContainer layer and this script has no map to hang one off.
func _fit_height(m: Node3D, target: float) -> void:
	var aabb := AABB()
	for mesh in m.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mesh.transform * mesh.get_aabb()
		aabb = a if aabb.size == Vector3.ZERO else aabb.merge(a)
	if aabb.size.y <= 0.0001:
		return
	var k := target / aabb.size.y
	m.scale = Vector3.ONE * k
	m.position.y -= aabb.position.y * k
