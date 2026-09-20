# Every footprint on the map — the soft shadow under a landmark, the lit disc
# inside its walls, the ring around it, the gold halo under the player's own
# band — as one MultiMesh of flat quads lying on the ground.
#
# These were screen-space draw calls in World._draw() (_soft_shadow(), _fan(),
# _ring()). They could not stay there. A ring is a circle drawn on the ground,
# and the only reason it used to be an ellipse in screen space is that the map
# had no ground to draw it on; once the camera can turn, an ellipse computed
# from fixed constants is simply the wrong shape. Worse, a 2D ring painted after
# the map is painted over the town it encircles — which is exactly the mismatch
# the whole refactor is about.
#
# So the footprint is geometry: it turns with the camera because it is not in
# screen space, and the town stands in front of its own ring because the depth
# buffer says so.
#
# WHAT IT DOES NOT DECIDE. Not which landmarks have a footprint, not what
# colour, and not whether the party can see them right now — that is the fog's
# business and it stays in world.gd's ground_marks(), one list, rebuilt each
# frame. This file turns that list into instances.
extends MultiMeshInstance3D

const MarkShader := preload("res://assets/world/ground/ground_mark.gdshader")

# How far above the ground the quads lie. Enough that they cannot z-fight the
# ground mesh, little enough that at map scale nothing reads as floating — a
# quarter of a world unit against landmarks 12 to 45 units across.
const LIFT := 0.25

var _mat: ShaderMaterial


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true          # the faction tint, alpha carrying the fog fade
	mm.use_custom_data = true     # ring width / fill / shadow, per instance
	# A unit-diameter-2 plane: the quad spans -1..1 on both axes, so the
	# instance transform's scale IS the footprint's radius in world units, and
	# the shader's UV maps straight onto the circle it draws.
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mm.mesh = pm
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = MarkShader
	material_override = _mat
	# A flat transparent decal has nothing to cast and no business receiving:
	# a shadow falling across a footprint ring reads as a hole in the ring.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


# `world_map` is scenes/world/world.gd. One call per frame; the list is short
# (settlements + discovered lairs + roaming bands) and rebuilding it is cheaper
# than tracking which landmark moved, since one of them — the player — always
# has.
func rebuild(world_map: Control) -> void:
	var marks: Array = world_map.ground_marks()
	var mm := multimesh
	if mm.instance_count != marks.size():
		mm.instance_count = marks.size()
	_mat.set_shader_parameter("light_dir", world_map.LIGHT.normalized())
	for i in marks.size():
		var m: Dictionary = marks[i]
		var r: float = m["radius"]
		var at: Vector2 = m["pos"]
		mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), Vector3(at.x, LIFT, at.y)))
		mm.set_instance_color(i, m["color"])
		mm.set_instance_custom_data(i, Color(m["ring"], m["fill"], m["shadow"], 0.0))
