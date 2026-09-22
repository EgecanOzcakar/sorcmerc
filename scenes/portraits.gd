# A face for the turn strip and the party page, cut from the same model that
# stands on the board (#165). No PNGs: a head-and-shoulders bust is rendered
# once per model per size into a SubViewport and kept for the session, so a
# class or beast the art covers gets a portrait for free and one it does not
# keeps its glyph — the same fall-through scenes/figures3d.gd draws by.
#
# The SubViewport stays in the tree and its ViewportTexture is the answer:
# handed back at once (painted on the next draw, UPDATE_ONCE), so a caller
# never waits and never has to ask twice. Headless — every test and robot — answers null always, so nothing there ever
# depends on a renderer. Static state on a RefCounted, the same shape as
# scenes/model_cache.gd; not an autoload.
extends RefCounted

const Figures = preload("res://scenes/figures3d.gd")
const Props3D = preload("res://scenes/world/props3d.gd")
const ModelCache = preload("res://scenes/model_cache.gd")

static var _cache := {}        # key -> Texture2D, or null for a path with no model


# The one cache key builder. A square bust keeps the short "path@px" form it
# has always had; anything else spells out both axes and marks a whole-figure
# framing with "!", since that is a different picture of the same model at the
# same size and must not share a slot with the bust.
static func key(path: String, px: int, py := -1, whole := false) -> String:
	if not whole and (py < 0 or py == px):
		return "%s@%d" % [path, px]
	return "%s@%dx%d%s" % [path, px, maxi(py, px), "!" if whole else ""]


# The bust for a model path, px square, or null: no path, no model, headless.
static func bust(path: String, px := 64) -> Texture2D:
	return _tex(path, Vector2i(px, px), false)


# The WHOLE figure, head to heel, for a card with room to show one
# (scenes/combat_card.gd). Same renderer, same cache, same fall-through — the
# only difference is where the camera stands and how much it takes in, which is
# the one thing that separates "who is that" from "what does it look like".
#
# Taller than wide on purpose: a standing rig is roughly 1:2.6 and a square
# viewport would spend two thirds of itself on empty air either side.
static func figure(path: String, size: Vector2i = Vector2i(88, 150)) -> Texture2D:
	return _tex(path, size, true)


# NOT _get: that is Object's own property-getter virtual (_get(StringName) ->
# Variant), and a static method of that name with any other signature fails to
# COMPILE the whole script — which in a test is a hang rather than a failure,
# because a script that never compiles never reaches quit().
static func _tex(path: String, size: Vector2i, whole: bool) -> Texture2D:
	if path == "" or DisplayServer.get_name() == "headless":
		return null
	var k := key(path, size.x, size.y, whole)
	if _cache.has(k):
		return _cache[k]
	_start(path, size, k, whole)
	return _cache[k]


# Start renders for a roster ahead of the screen that will show them.
static func warm(paths: Array, px := 64) -> void:
	for p in paths:
		bust(String(p), px)


static func _start(path: String, size: Vector2i, k: String, whole := false) -> void:
	var scene := ModelCache.get_scene(path)
	if scene == null:
		_cache[k] = null
		return
	var sub := SubViewport.new()
	sub.size = size
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
	e.ambient_light_color = Color(0.72, 0.74, 0.80)   # brighter than the board's: a face this small reads by its highlights
	env.environment = e
	sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sub.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -25, 0)   # lower than the board's, so the brow does not shade the eyes
	sun.light_energy = 1.3

	var m: Node3D = scene.instantiate()
	sub.add_child(m)
	if path.begins_with(Figures.BEAST_DIR.get_base_dir()):
		Figures.fit_beast(m, path.get_file().get_basename())
	var box: AABB = m.transform * Props3D._bounds(m)
	if box.size.y <= 0.0001:
		box = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.2, 0.6))   # the rig's nominal 1.2 m
	# A standing rig is framed at the head (78% up, half its height in view);
	# a beast has no head to speak of from above, so it is framed whole, from
	# the front and a little higher, the way the board sees it.
	var beast := path.begins_with(Figures.BEAST_DIR.get_base_dir())
	var at := box.get_center() if beast else box.position + Vector3(box.size.x * 0.5, box.size.y * 0.78, box.size.z * 0.5)
	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.y) * 1.15 if beast else box.size.y * 0.5
	cam.near = 0.01
	cam.far = 50.0
	# Models face +Z (figures3d.gd), so the camera sits out on +Z, a little above.
	var eye := Vector3(0, 0.45 if beast else 0.25, 1).normalized()
	if whole:
		# The whole thing in frame, centred on its middle rather than its head,
		# and the KEEP_HEIGHT default means `size` is the vertical extent — so a
		# tall narrow viewport wants the model's HEIGHT plus a margin, and a wide
		# one (a beast) would clip at the shoulders without the width check.
		at = box.get_center()
		cam.size = maxf(box.size.y, box.size.x * float(size.y) / maxf(1.0, float(size.x))) * 1.12
		# Nearly level: a full figure seen from a portrait's downward angle
		# foreshortens into a head on a pair of boots.
		eye = Vector3(0, 0.10, 1).normalized()
	cam.look_at_from_position(at + eye * 10.0, at, Vector3.UP)
	cam.current = true

	Engine.get_main_loop().root.add_child.call_deferred(sub)   # a strip built in _ready finds the root busy
	# The viewport stays in the tree and its texture IS the portrait: a
	# get_image() readback was blank in-game whatever frame it was taken on
	# (probed 2026-09-22), and a ViewportTexture is what figures3d.gd shows
	# the board through anyway. UPDATE_ONCE paints it on the next draw and
	# then costs nothing; ~30 of them at 28-64 px is a rounding error.
	_cache[k] = sub.get_texture()



