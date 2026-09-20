# Dev-only: look at the modular settlement dioramas (scenes/world/settlement_kit.gd)
# and compare them against the GLB tier they are a candidate to replace.
#   godot --display-driver x11 --path . -s tests/shot_settlement_kit.gd
# (needs a display — same force_draw recipe as tests/shot_settlement_gallery.gd;
# under a headless box, `xvfb-run -a` in front of it.)
#
# Three outputs, because they answer three different questions:
#
#   kit_gallery_<faction>.png   camp/town/city at TRUE relative scale, close up.
#                               Does each faction read as itself, and does a camp
#                               read as smaller than a city? (The existing
#                               shot_settlement_gallery.gd normalises every model
#                               to the same 2 units, which hides exactly that.)
#   kit_variety.png             five human towns, five different ids. The GLB tier
#                               has one model per (faction, kind), so this is the
#                               shot with no GLB equivalent at all.
#   kit_vs_glb.png              the money shot: both sources under the map's OWN
#                               projection at the map's OWN pixel size, then
#                               upscaled 4x nearest-neighbour. Nothing else in
#                               this file is evidence about how the map looks;
#                               this is.
extends SceneTree

const Kit = preload("res://scenes/world/settlement_kit.gd")
const MapView = preload("res://scenes/world/world.gd")
const Settlements3D = preload("res://scenes/world/settlements3d.gd")

const FACTIONS := ["dwarf", "elf", "human", "orc"]
const SIZES := ["camp", "town", "city"]

# The map's own projection, so the comparison is not a flattering studio render:
# World.ISO_GAIN px per world unit, camera pitched at asin(ISO_SQUASH).
const PX_PER_UNIT := 1.85            # MapView.ISO_GAIN
const SQUASH := 0.38                 # MapView.ISO_SQUASH
const UPSCALE := 4                   # nearest-neighbour, so a pixel stays a pixel


func _init() -> void:
	# Keep the constants above honest: they are duplicated here only so the
	# camera maths reads in one place, and they must not drift from world.gd.
	assert(is_equal_approx(PX_PER_UNIT, MapView.ISO_GAIN))
	assert(is_equal_approx(SQUASH, MapView.ISO_SQUASH))

	await _galleries()
	await _variety()
	await _compare()
	quit()


# --- the rig ----------------------------------------------------------------

# A SubViewport lit the way world_view3d.gd lights the real map, plus the
# shadow the real rig does not turn on — see the note in _compare(), shadows are
# a separate question and this file shows both.
func _rig(w: int, h: int, shadows := false) -> Array:
	var sub := SubViewport.new()
	sub.size = Vector2i(w, h)
	sub.msaa_3d = Viewport.MSAA_4X
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.23, 0.26, 0.17)      # world.gd's own ground average
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


# The map camera: looking down the same pitch World._pix() projects at, far
# enough back that an orthographic frustum never clips a city.
func _aim(cam: Camera3D, centre: Vector3, view_height_units: float) -> void:
	var th := asin(SQUASH)
	cam.size = view_height_units
	cam.look_at_from_position(centre + Vector3(0.0, sin(th), cos(th)) * 900.0,
		centre, Vector3.UP)


func _shoot(sub: SubViewport, path: String, upscale := 1) -> void:
	for i in 12:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := sub.get_texture().get_image()
	if upscale > 1:
		img.resize(img.get_width() * upscale, img.get_height() * upscale,
			Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("%s  (%dx%d)" % [path, img.get_width(), img.get_height()])


# --- one row per faction, camp/town/city, true relative scale ---------------

func _galleries() -> void:
	var rig := _rig(1500, 560, true)
	var sub: SubViewport = rig[0]
	var cam: Camera3D = rig[1]
	for faction in FACTIONS:
		var nodes: Array = []
		var x := -108.0
		for kind in SIZES:
			var n := Kit.build(faction, kind, "%s-%s-gallery" % [faction, kind])
			sub.add_child(n)
			n.position = Vector3(x, 0, 0)
			nodes.append(n)
			x += 108.0
		_aim(cam, Vector3(0, 16, 0), 122.0)
		await _shoot(sub, "res://kit_gallery_%s.png" % faction)
		for n in nodes:
			n.queue_free()
		await process_frame
	sub.queue_free()


# --- five ids, one (faction, kind): the thing 12 fixed models cannot do -----

func _variety() -> void:
	var rig := _rig(1500, 400, true)
	var sub: SubViewport = rig[0]
	var cam: Camera3D = rig[1]
	var x := -176.0
	for id in ["ashfell", "deepmoor", "greyholt", "westmere", "thornwick"]:
		var n := Kit.build("human", "town", id)
		sub.add_child(n)
		n.position = Vector3(x, 0, 0)
		x += 88.0
	_aim(cam, Vector3(0, 12, 0), 58.0)
	await _shoot(sub, "res://kit_variety.png")
	sub.queue_free()


# --- kit vs GLB, at the size the map actually draws them --------------------

# Both sources, both wall-clock-identical rigs, at 1:1 map pixels — a town is
# 25.7 units * 1.85 px/unit, i.e. 48px tall, and that is the entire argument.
# The result is upscaled 4x with NEAREST afterwards so it can be looked at
# without the upscale itself doing any smoothing the renderer did not.
#
# Two rows of light as well as two sources: the top pair uses the current
# world_view3d.gd rig exactly (one directional light, no shadows), the bottom
# pair turns shadows on. That is a change to the shared rig rather than to
# either source, so it is kept visible and separate here instead of being
# smuggled into the comparison.
func _compare() -> void:
	var cell := Vector2i(150, 120)          # world units are ~81 x 65 at this scale
	var cols := FACTIONS.size() * SIZES.size()
	var full := Image.create(cell.x * cols, cell.y * 4, false, Image.FORMAT_RGBA8)

	var row := 0
	for shadows in [false, true]:
		for source in ["glb", "kit"]:
			var col := 0
			for faction in FACTIONS:
				for kind in SIZES:
					var img := await _one(faction, kind, source, shadows, cell)
					full.blit_rect(img, Rect2i(Vector2i.ZERO, cell),
						Vector2i(col * cell.x, row * cell.y))
					col += 1
			row += 1

	full.resize(full.get_width() * UPSCALE, full.get_height() * UPSCALE,
		Image.INTERPOLATE_NEAREST)
	full.save_png("res://kit_vs_glb.png")
	print("kit_vs_glb.png  rows: glb / kit / glb+shadow / kit+shadow, "
		+ "cols: %s x %s, 1:1 map pixels upscaled %dx"
		% [", ".join(FACTIONS), ", ".join(SIZES), UPSCALE])


func _one(faction: String, kind: String, source: String, shadows: bool,
		cell: Vector2i) -> Image:
	var rig := _rig(cell.x, cell.y, shadows)
	var sub: SubViewport = rig[0]
	var cam: Camera3D = rig[1]
	var n: Node3D
	if source == "kit":
		n = Kit.build(faction, kind, "%s-%s-compare" % [faction, kind])
	else:
		var path := "res://assets/settlements/%s_%s.glb" % [faction, kind]
		n = load(path).instantiate()
		_fit_height(n, float(Kit.PLANS[kind]["height"]))
		# The models carry their colour in COLOR_0 since the low-poly rebuild,
		# and glTF's own material ignores it — without this the comparison shoots
		# twelve white blobs and flatters the kit enormously.
		Settlements3D.dress(n)
	sub.add_child(n)
	# 1:1 with the map: the viewport is `cell.y` px tall and the camera shows
	# cell.y / ISO_GAIN world units, so one world unit lands on ISO_GAIN pixels.
	_aim(cam, Vector3(0, float(Kit.PLANS[kind]["height"]) * 0.45, 0),
		float(cell.y) / PX_PER_UNIT)
	for i in 12:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := sub.get_texture().get_image()
	sub.queue_free()
	await process_frame
	return img


# settlements3d.gd's own _fit_height, copied rather than imported: that one is a
# method on the SubViewportContainer layer and this script has no map to hang
# one off. If the real one changes, this is the line to change with it.
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
