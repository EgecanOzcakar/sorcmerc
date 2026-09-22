# A face for the turn strip and the party page, cut from the same model that
# stands on the board (#165). No PNGs: a head-and-shoulders bust is rendered
# once per model per size into a SubViewport and kept for the session, so a
# class or beast the art covers gets a portrait for free and one it does not
# keeps its glyph — the same fall-through scenes/figures3d.gd draws by.
#
# A render takes a frame. bust() therefore never waits: the first ask for a
# model starts it and answers null, and the caller keeps its glyph until its
# next rebuild (the strip is rebuilt every turn, the party page on open).
# Headless — every test and robot — answers null always, so nothing there ever
# depends on a renderer. Static state on a RefCounted, the same shape as
# scenes/model_cache.gd; not an autoload.
extends RefCounted

const Figures = preload("res://scenes/figures3d.gd")
const Props3D = preload("res://scenes/world/props3d.gd")
const ModelCache = preload("res://scenes/model_cache.gd")

static var _cache := {}        # key -> Texture2D, or null for a path with no model
static var _pending := {}      # key -> [SubViewport, frames drawn since it was added]


static func key(path: String, px: int) -> String:
	return "%s@%d" % [path, px]


# The bust for a model path, px square, or null: no path, no model, headless,
# or not rendered yet (ask again next rebuild).
static func bust(path: String, px := 64) -> Texture2D:
	if path == "" or DisplayServer.get_name() == "headless":
		return null
	var k := key(path, px)
	if _cache.has(k):
		return _cache[k]
	if not _pending.has(k):
		_start(path, px, k)
	return null


# Start renders for a roster ahead of the screen that will show them.
static func warm(paths: Array, px := 64) -> void:
	for p in paths:
		bust(String(p), px)


static func _start(path: String, px: int, k: String) -> void:
	var scene := ModelCache.get_scene(path)
	if scene == null:
		_cache[k] = null
		return
	var sub := SubViewport.new()
	sub.size = Vector2i(px, px)
	sub.transparent_bg = true
	sub.own_world_3d = true
	sub.msaa_3d = Viewport.MSAA_4X
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub.gui_disable_input = true

	# The board's light, so the face matches the figure below it.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.50, 0.53, 0.60)
	env.environment = e
	sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sub.add_child(sun)
	sun.rotation_degrees = Vector3(-55, -35, 0)

	var m: Node3D = scene.instantiate()
	sub.add_child(m)
	if path.begins_with(Figures.BEAST_DIR.get_base_dir()):
		Figures.fit_beast(m, path.get_file().get_basename())
	var box: AABB = m.transform * Props3D._bounds(m)
	if box.size.y <= 0.0001:
		box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.2, 0.6))   # the rig's nominal 1.2 m
	# ponytail: "head" is the top of the bounds — right for a standing rig,
	# a wolf shows its back; per-model framing if a beast portrait matters.
	var head := box.position + Vector3(box.size.x * 0.5, box.size.y * 0.78, box.size.z * 0.5)
	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = box.size.y * 0.5
	cam.near = 0.01
	cam.far = 50.0
	# Models face +Z (figures3d.gd), so the camera sits out on +Z, a little above.
	cam.look_at_from_position(head + Vector3(0, 0.25, 1).normalized() * 10.0, head, Vector3.UP)
	cam.current = true

	Engine.get_main_loop().root.add_child(sub)
	if _pending.is_empty():
		RenderingServer.frame_post_draw.connect(_collect)
	_pending[k] = [sub, 0]


# One frame in the tree is not enough when the ask came mid-frame: the
# viewport draws on the next pass, so grab on the second post-draw.
static func _collect() -> void:
	for k in _pending.keys():
		_pending[k][1] += 1
		if _pending[k][1] < 2:
			continue
		var sub: SubViewport = _pending[k][0]
		_cache[k] = ImageTexture.create_from_image(sub.get_texture().get_image())
		sub.queue_free()
		_pending.erase(k)
	if _pending.is_empty():
		RenderingServer.frame_post_draw.disconnect(_collect)
