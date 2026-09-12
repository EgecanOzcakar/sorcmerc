# Tier 0 for settlements: a real 3D diorama standing where World draws a
# settlement's building cluster — same relationship Figures3D has to Board
# (scenes/figures3d.gd), reused almost line for line. One transparent
# SubViewport laid exactly over the World map; the camera is derived from
# World.ISO_SQUASH/ISO_GAIN so a diorama placed at a settlement's map position
# lands on the same pixel World._pix(s.position) produces. Settlements never
# move, so this skips Figures3D's per-frame facing/lunge tracking — only pan
# and zoom change, and _process() re-reads those every frame.
#
# What this layer does NOT own: the shadow ellipse, footprint ring, and name
# label World._draw_settlement() already draws — those stay shared across
# every settlement regardless of tier, same contract as Board's HP bar. This
# only replaces the building-cluster sprite blocks.
extends SubViewportContainer

# One diorama per (faction, kind) — not per settlement instance, so two towns
# of the same race are the same building (that's already true of the 2D
# tier's style/pair hash, just coarser: one look per size now, not a random
# pick per id). Missing entries fall through has_model() to the existing
# BuildingTex sprite tier, same fallback contract as Figures3D/LpcArt.
const MODELS := {
	"dwarf": {"camp": "res://assets/settlements/dwarf_camp.glb", "town": "res://assets/settlements/dwarf_town.glb", "city": "res://assets/settlements/dwarf_city.glb"},
	"elf": {"camp": "res://assets/settlements/elf_camp.glb", "town": "res://assets/settlements/elf_town.glb", "city": "res://assets/settlements/elf_city.glb"},
	"human": {"camp": "res://assets/settlements/human_camp.glb", "town": "res://assets/settlements/human_town.glb", "city": "res://assets/settlements/human_city.glb"},
	"orc": {"camp": "res://assets/settlements/orc_camp.glb", "town": "res://assets/settlements/orc_town.glb", "city": "res://assets/settlements/orc_city.glb"},
}
# Target ground footprint height (world units), auto-fit from each model's own
# AABB so raw Meshy output scale (which varies wildly for a multi-building
# diorama) never needs hand calibration — see figures3d.gd's FIGURE_SCALE
# comment for why that was a trial-and-error constant there; this avoids it.
const TARGET_HEIGHT := {"camp": 0.55, "town": 0.85, "city": 1.3}
const CAM_DIST := 60.0

var world_map: Control
var _sub: SubViewport
var _cam: Camera3D
var _dioramas := {}            # settlement id -> Node3D
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


func _model_path(s) -> String:
	return String(MODELS.get(s.faction, {}).get(s.kind, ""))


func _model(path: String) -> PackedScene:
	if not _model_cache.has(path):
		_model_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _model_cache[path]


func has_model(s) -> bool:
	return _dioramas.has(s.id)


func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	for s in world.settlements:
		var scene := _model(_model_path(s))
		if scene == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		var m := scene.instantiate()
		holder.add_child(m)
		_fit_height(m, float(TARGET_HEIGHT.get(s.kind, 1.0)))
		_dioramas[s.id] = holder


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

	for s in world_map.world.settlements:
		var n: Node3D = _dioramas.get(s.id)
		if n == null:
			continue
		n.position = world_for_screen(world_map._pix(s.position))
