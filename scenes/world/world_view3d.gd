# The overworld map, as one real 3D scene.
#
# WHAT THIS REPLACES. The map used to be a painting: a canvas_item shader that
# projected each screen pixel back to a world position to decide what ground was
# there, with props drawn over it as sorted 2D sprites, and three SEPARATE
# transparent SubViewports laid on top — one for settlement dioramas, one for
# lairs, one for parties — each carrying its own camera, its own sun, and its
# own copy of the projection. Four cameras that had to be kept in lockstep by
# hand, and nothing in any of them could occlude anything in any other: a
# marching band could not pass behind a town wall, a lair could not stand in a
# wood, and the light on a model had nothing to do with the light on the ground.
#
# There is one world now. One SubViewport, one camera, one sun. The ground is a
# mesh, the towns and lairs and marching bands are models standing on it, and
# the depth buffer decides what is in front of what — which is the whole reason
# the camera can now be turned.
#
# WHAT THE CAMERA IS. Orthographic, and deliberately so. The old map's
# projection was `_iso()`: rotate by ISO_YAW, scale by ISO_GAIN, squash y by
# ISO_SQUASH. That is not an approximation of a 3D camera, it IS one — an
# orthographic camera at yaw ISO_YAW and pitch asin(ISO_SQUASH). So the refactor
# is a strict generalisation: the yaw and the pitch stop being constants and
# become camera state, and world.gd's `_pix()` / `_unpix()` keep working
# unchanged because they were always describing this camera.
#
# Keeping it orthographic rather than switching to perspective is what makes
# that true. An orthographic projection of the ground plane is affine, so it
# stays exactly invertible: `_unpix()` has an answer for every pixel on screen,
# every mechanism built on it (click-to-move, the off-screen chevrons, the
# minimap's view rectangle, the ground mask's visible-cell box) keeps its
# meaning, and there is no horizon for the top of the screen to fall over. A
# perspective camera would take all of that back in exchange for a vanishing
# point nobody asked for on a map.
#
# WHAT LIVES HERE. The viewport, the camera, the sun and ambient, the ground
# mesh, the woods (scatter3d.gd), the footprints lying on the ground
# (ground_marks3d.gd), and `props` — the Node3D every layer of landmarks hangs
# under (scenes/world/props3d.gd and its three subclasses). What does NOT live here is
# any world state or any of the mask arithmetic: world.gd still owns
# `_visible_ground()` / `_build_mask()` and hands the result down through
# `set_ground_mask()`, because that is the fog's memory and it belongs with the
# fog.
extends SubViewportContainer

const GroundShader := preload("res://assets/world/ground/ground3d.gdshader")
const GrassTex := preload("res://assets/world/ground/grass.png")
const ForestGroundTex := preload("res://assets/world/ground/forest.png")
const WaterGroundTex := preload("res://assets/world/ground/water.png")
const Scatter3D := preload("res://scenes/world/scatter3d.gd")
const GroundMarks3D := preload("res://scenes/world/ground_marks3d.gd")
# For Props3D.at() — core/world.gd is a 2D world and calls its axes (x, y),
# and the 3D map lays that plane down as (x, z) with y up. That swap is written
# once, there, so there is nowhere else for the mistake to be.
const Props3D := preload("res://scenes/world/props3d.gd")

# The sun's own numbers, carried over from the old per-layer diorama rigs so a
# model is lit the way it always was. #85: both follow the world clock, and the
# sun keeps a floor — a silhouette with no shading reads as a hole in the map,
# not as night.
const AMBIENT := Color(0.52, 0.55, 0.60)
const SUN_ENERGY := 1.2
# Where the sun stands. Fixed in WORLD space, not camera space: turning the
# camera must not drag the lighting round with it, or the map stops reading as
# a place and starts reading as a turntable.
const SUN_ANGLES := Vector3(-52.0, -35.0, 0.0)

# T9x's two fog tiers. Never explored is flat and near-black; explored but not
# currently visible is a dark tint over the real ground. They belong to the map
# rather than to this rig, but the environment and the ground material both need
# them before world.gd has said anything, so they are named here and world.gd
# reads them back.
const FOG_UNKNOWN := Color(0.03, 0.03, 0.045)
const FOG_REMEMBERED := Color(0.05, 0.05, 0.09, 0.55)

var world_map: Control          # scenes/world/world.gd — the screen that owns the camera state
var props: Node3D               # every landmark layer hangs here
var marks: GroundMarks3D        # the footprints under them
var scatter: Scatter3D          # the woods

var _sub: SubViewport
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE     # clicks and drags belong to the map Control
	# Behind the parent's own _draw(), so what world.gd still paints in 2D —
	# the marching route, the name labels, the off-screen chevrons — reads as
	# annotation ON the map rather than being buried under the ground mesh.
	# Everything that belongs ON THE GROUND (footprint rings, shadows) is
	# geometry now precisely so that the depth buffer, and not the draw order,
	# decides whether the town is in front of its own ring.
	show_behind_parent = true

	_sub = SubViewport.new()
	_sub.own_world_3d = true
	_sub.transparent_bg = false     # this IS the map's background now, not a layer over one
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.gui_disable_input = true
	# A manually-created SubViewport gets no AA by default (the root viewport's
	# project-settings MSAA does not apply here). Screen-space AA needs
	# Forward+/Mobile and this project runs GL Compatibility, so MSAA alone.
	_sub.msaa_3d = Viewport.MSAA_4X
	add_child(_sub)

	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	# Anything the ground mesh does not cover is more unexplored map, so it is
	# painted the unknown fog's own colour rather than a sky: tilting the camera
	# down to the horizon must not open a window out of the world.
	_env.background_color = FOG_UNKNOWN
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT
	_env.ambient_light_energy = 1.0
	we.environment = _env
	_sub.add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = SUN_ANGLES
	_sun.light_energy = SUN_ENERGY
	# No shadow map, and this is a measured decision rather than an omission.
	# A directional shadow's resolution is its range divided by its atlas, and
	# an orthographic camera looking at a map has to stand far enough back to
	# clear the whole ground plane — thousands of units — so the range is
	# thousands of units too and a texel lands at about one world unit. A tree
	# is twenty units and a marching figure is fifteen: at that ratio there are
	# no contact shadows to be had, only acne, and what it actually produced was
	# a scene uniformly darker and dirtier with every model self-shadowing. What
	# grounds a model here is its footprint decal (scenes/world/
	# ground_marks3d.gd), which is what those are for.
	# ponytail: a second, tight shadow camera following the view's centre would
	# buy real shadows for the middle of the screen. It is a rig of its own and
	# the map does not need it to read as 3D.
	_sun.shadow_enabled = false
	_sub.add_child(_sun)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT     # world.gd's px-per-unit is quoted against height
	_cam.current = true
	_sub.add_child(_cam)

	_ground = MeshInstance3D.new()
	# A 1x1 plane, SCALED to the visible ground box every frame rather than
	# resized: changing a PrimitiveMesh's size rebuilds it, and this is two
	# triangles whose fragment shader does all the work anyway. A plane's normal
	# is +Y whatever it is scaled by, so nothing is skewed.
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	_ground.mesh = pm
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # it is the floor; it receives
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GroundShader
	_ground_mat.set_shader_parameter("grass_tex", GrassTex)
	_ground_mat.set_shader_parameter("forest_tex", ForestGroundTex)
	_ground_mat.set_shader_parameter("water_tex", WaterGroundTex)
	_ground_mat.set_shader_parameter("fog_unknown", Vector3(FOG_UNKNOWN.r, FOG_UNKNOWN.g, FOG_UNKNOWN.b))
	_ground_mat.set_shader_parameter("fog_remembered",
		Vector4(FOG_REMEMBERED.r, FOG_REMEMBERED.g, FOG_REMEMBERED.b, FOG_REMEMBERED.a))
	_ground.material_override = _ground_mat
	_sub.add_child(_ground)

	marks = GroundMarks3D.new()
	_sub.add_child(marks)
	scatter = Scatter3D.new()
	_sub.add_child(scatter)
	props = Node3D.new()
	props.name = "Props"
	_sub.add_child(props)

# --- per frame ------------------------------------------------------------
# Driven by world.gd's own _process() rather than this node's, so the camera is
# rebuilt from the same state, in the same frame, that the map was just told to
# use — a camera one frame behind the projection is a map whose labels sit next
# to the thing they name.
func sync() -> void:
	if world_map == null:
		return
	position = Vector2.ZERO
	size = world_map.size
	_sync_light()
	var box := _sync_camera()
	_sync_ground(box)
	marks.rebuild(world_map)
	scatter.rebuild(world_map)
	for layer in props.get_children():
		if layer.has_method("reposition"):
			layer.reposition()


func _sync_light() -> void:
	if world_map.get("world") == null:
		return
	var tint: Color = world_map.world.clock.daylight_tint()
	var d: float = world_map.world.clock.daylight()
	_sun.light_energy = SUN_ENERGY * lerpf(0.45, 1.0, d)
	_sun.light_color = tint / maxf(d, 0.01)
	_env.ambient_light_color = AMBIENT * tint


# Rebuilds the camera from world.gd's yaw / pitch / zoom / pan, and returns the
# box of ground the screen is looking at (world units), which is the same box
# the ground mask and the scatter are cut to.
func _sync_camera() -> Rect2:
	var box := _visible_box()
	# Orthographic: only the direction matters, not how far back the camera
	# stands. It is pushed out past the box so nothing on the map — a city, a
	# wood, a mountain of a lair — can ever fall behind the near plane, and the
	# far plane is set from the same number.
	var dist: float = maxf(box.size.length(), 400.0)
	var th := deg_to_rad(world_map.yaw())
	var ph := deg_to_rad(world_map.pitch())
	var back := Vector3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))
	var target := Props3D.at(world_map._unpix(size * 0.5))
	_cam.near = 1.0
	_cam.far = dist * 2.0 + 2000.0
	_cam.look_at_from_position(target + back * dist, target, Vector3.UP)
	# The one line that ties this camera to world.gd's `_pix()`: KEEP_HEIGHT
	# means `size` is the vertical extent in world units, so pixels per world
	# unit is exactly ISO_GAIN * zoom — which is what `_iso()` scales by.
	_cam.size = maxf(size.y, 1.0) / (world_map.ISO_GAIN * world_map._zoom)
	return box


# The ground the screen covers, as an axis-aligned box in map coordinates: the
# four screen corners projected back down. Exactly what World._update_ground()
# computes for the mask, and for the same reason — it is the only region of an
# unbounded plane worth spending anything on.
func _visible_box() -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		var w: Vector2 = world_map._unpix(corner)
		mn = mn.min(w)
		mx = mx.max(w)
	return Rect2(mn, mx - mn)


# A margin because MSAA and the mask's own soft edge both read slightly outside
# the box, and a ground plane that ends exactly at the corner of the screen
# shows the background colour along it.
const GROUND_MARGIN := 1.12

func _sync_ground(box: Rect2) -> void:
	var c := box.position + box.size * 0.5
	_ground.transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(maxf(box.size.x, 1.0) * GROUND_MARGIN, 1.0,
			maxf(box.size.y, 1.0) * GROUND_MARGIN)),
		Props3D.at(c))
	_ground_mat.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)
	if world_map.get("world") == null:
		return
	var p = world_map.world.player()
	_ground_mat.set_shader_parameter("player", p.position if p != null else Vector2(1e9, 1e9))
	_ground_mat.set_shader_parameter("sight", world_map.world.sight_radius())


# World._update_ground() builds the mask (R forest, G water, B explored) and hands
# it down. This side only has to put it on the material — the arithmetic, and
# the memoisation that keeps a pan from rebuilding it, stay with the fog.
func set_ground_mask(tex: Texture2D, mask_min: Vector2, mask_size: Vector2, texel: Vector2) -> void:
	_ground_mat.set_shader_parameter("mask_tex", tex)
	_ground_mat.set_shader_parameter("mask_min", mask_min)
	_ground_mat.set_shader_parameter("mask_size", mask_size)
	_ground_mat.set_shader_parameter("mask_texel", texel)


# For the layers: adding one parents it into the shared world and wires it back
# to the map screen, which is the whole contract they have with this file.
func add_layer(layer: Node3D) -> void:
	layer.world_map = world_map
	layer.view = self
	props.add_child(layer)


func camera() -> Camera3D:
	return _cam
