# Shared base for the "3D diorama over the 2D world map" layers — Settlements3D
# and Lairs3D. Same relationship Figures3D has to Board (scenes/figures3d.gd):
# one transparent SubViewport laid exactly over the map, camera derived from
# World.ISO_SQUASH/ISO_GAIN so a diorama placed at a world position lands on
# the same pixel World._pix(position) produces. Dioramas never move on their
# own (settlements and lairs are both fixed landmarks), so this skips
# Figures3D's per-frame facing/lunge tracking — only pan/zoom change, re-read
# every frame in _process().
#
# Subclasses own: the model lookup, has_model()/reset() (what to show and
# when), and _reposition() (which list to walk each frame). This base owns
# the SubViewport/camera/lighting rig and the projection math — identical
# for both, and was the actual source of the first Settlements3D bug (target
# heights tuned for the wrong coordinate scale), so it's worth not retyping.
extends SubViewportContainer

const CAM_DIST := 400.0

var world_map: Control
var _sub: SubViewport
var _cam: Camera3D
var _model_cache := {}         # path -> PackedScene, or null once if missing


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub = SubViewport.new()
	_sub.transparent_bg = true
	_sub.own_world_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.gui_disable_input = true
	_sub.msaa_3d = Viewport.MSAA_4X   # see figures3d.gd — a runtime SubViewport gets none by default
	add_child(_sub)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.55, 0.60)
	e.ambient_light_energy = 1.0
	env.environment = e
	_sub.add_child(env)

	var sun := DirectionalLight3D.new()
	_sub.add_child(sun)
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2

	_cam = Camera3D.new()
	_sub.add_child(_cam)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.1
	_cam.far = CAM_DIST * 4.0
	_cam.current = true


func _model(path: String) -> PackedScene:
	if not _model_cache.has(path):
		_model_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _model_cache[path]


# Uniform-scale `m` so its own mesh AABB is TARGET_HEIGHT tall, feet at y=0 —
# a diorama's raw scale is whatever Meshy happened to generate it at, unlike
# a rigged character (Meshy normalizes rig height itself), so this can't skip
# straight to a hand-picked constant the way figures3d.gd's FIGURE_SCALE does.
func _fit_height(m: Node3D, target: float) -> void:
	var aabb := AABB()
	for mesh in m.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mesh.transform * mesh.get_aabb()
		aabb = a if aabb.size == Vector3.ZERO else aabb.merge(a)
	if aabb.size.y <= 0.0001:
		return
	var k := target / aabb.size.y
	m.scale = Vector3.ONE * k
	m.position.y -= aabb.position.y * k   # rest the lowest point on y=0


# T9x fog of war: a diorama is a real 3D layer, drawn independently of the 2D
# map below it — hiding an entity's 2D icon (World._draw()'s props filter)
# does nothing to the diorama standing on top of it, so every subclass's
# _reposition() also needs this check before showing its own model.
func _explored(pos: Vector2) -> bool:
	return world_map.world.is_explored(pos)

# T9y: a landmark the party cannot see right now is a memory, and World's own
# 2D layer draws it that way (ring, label and fallback art all fade through
# World._remembered()). A diorama is a separate 3D layer over the top, so a
# full-brightness town standing on a faded footprint is exactly the mismatch
# the three-tier fog was meant to remove — the model has to fade with it.
#
# GeometryInstance3D.transparency rather than a material tint: it needs no
# material override (the GLBs bring their own), costs nothing to set every
# frame, and fading toward the dark map behind it reads the same way the 2D
# layer's alpha drop does.
# ponytail: this fades, it does not desaturate — the 2D side does both. Close
# enough at map scale; a real match would mean a shader on every diorama.
#
# Both the mesh list and the last value applied are cached as metadata ON the
# holder: _reposition() runs every frame for every landmark on the map, and
# walking a GLB's whole subtree with find_children() that often was measurably
# worse than the fade is worth. Metadata rather than a dictionary in this
# object because it dies with the node — reset() frees every holder, and a
# cache keyed on freed nodes is a leak waiting to be forgotten about.
const REMEMBERED_TRANSPARENCY := 0.55
func _fade(holder: Node3D, remembered: bool) -> void:
	var want: float = REMEMBERED_TRANSPARENCY if remembered else 0.0
	if not holder.has_meta("fade_meshes"):
		holder.set_meta("fade_meshes", holder.find_children("*", "GeometryInstance3D", true, false))
	elif is_equal_approx(float(holder.get_meta("fade_want", -1.0)), want):
		return                                  # already showing this, nothing to walk
	holder.set_meta("fade_want", want)
	for mesh in holder.get_meta("fade_meshes"):
		mesh.transparency = want

# Where the party is standing this frame, for _fade()'s "can they see it now"
# question — Vector2.ZERO on a world with no player, same null-tolerant
# contract as _explored() above.
func _player_pos() -> Vector2:
	var p = world_map.world.player()
	return p.position if p != null else Vector2.ZERO

func px_per_unit() -> float:
	return world_map.ISO_GAIN * world_map._zoom

func theta() -> float:
	return asin(world_map.ISO_SQUASH)

func world_for_screen(p: Vector2) -> Vector3:
	var d: Vector2 = p - world_map._origin
	var K := px_per_unit()
	return Vector3(d.x / K, 0.0, d.y / (K * world_map.ISO_SQUASH))

func screen_for_world(w: Vector3) -> Vector2:
	var K := px_per_unit()
	var th := theta()
	return world_map._origin + Vector2(K * w.x, K * (w.z * sin(th) - w.y * cos(th)))


func _process(_dt: float) -> void:
	if world_map == null:
		return
	position = Vector2.ZERO
	size = world_map.size
	var th := theta()
	var target := world_for_screen(world_map.size * 0.5)
	var back := Vector3(0.0, sin(th), cos(th))
	_cam.look_at_from_position(target + back * CAM_DIST, target, Vector3.UP)
	_cam.size = world_map.size.y / px_per_unit()
	_reposition()

# Subclasses walk their own item list and set each diorama's .position (and,
# if it can be hidden — a lair, not a settlement — .visible) here.
func _reposition() -> void:
	pass
