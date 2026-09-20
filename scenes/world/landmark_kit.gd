# Landmark dioramas — small, cheap, one palette: the kit's parts arranged six
# ways. Half a lair's footprint, because a shrine is not a warren.
#   scenes/world/lair_kit.gd is the pattern; kit_parts.gd the vocabulary.
extends RefCounted

const KitParts = preload("res://scenes/world/kit_parts.gd")

const RADIUS := 8.0
const HEIGHT := 12.0
const PALETTE := {
	"ground": Color("5a5540"), "stone": Color("8f8a7b"), "dark": Color("3a352c"),
	"wood": Color("5a4630"), "moss": Color("5a6340"), "cloth": Color("8c5a3c"),
}

static func has(kind: String) -> bool:
	return kind in ["ruins", "shrine", "stones", "hut", "wreck", "tower"]

static func plan(kind: String) -> Array:
	if not has(kind):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("landmark/%s" % kind)
	var parts: Array = []
	match kind:
		"ruins": _ruins(parts, rng)
		"shrine": _shrine(parts)
		"stones": _stones(parts, rng)
		"hut": _hut(parts)
		"wreck": _wreck(parts, rng)
		"tower": _tower(parts)
	KitParts.apron(parts, "ground", RADIUS * 1.1)
	return parts

static func build(kind: String) -> Node3D:
	return KitParts.assemble(plan(kind), PALETTE, "landmark-" + kind)

static func triangles(kind: String) -> int:
	return KitParts.triangles(plan(kind))

static func _box(parts: Array, role: String, shade: int, pos: Vector3, size: Vector3, yaw := 0.0, tilt := 0.0) -> void:
	parts.append({"part": "box", "role": role, "shade": shade, "pos": pos, "size": size, "yaw": yaw, "tilt": tilt})

# Two broken walls and a fallen lintel.
static func _ruins(parts: Array, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(-0.4, 0.4)
	_box(parts, "stone", 1, Vector3(-3.5, 2.5, 0), Vector3(1.2, 5.0, 6.0), yaw)
	_box(parts, "stone", 1, Vector3(3.0, 1.5, -1.0), Vector3(1.2, 3.0, 4.0), yaw + 0.3)
	_box(parts, "stone", 2, Vector3(0.5, 0.6, 2.5), Vector3(6.0, 1.0, 1.2), yaw + 1.2, 0.15)

# An altar under a little roof.
static func _shrine(parts: Array) -> void:
	_box(parts, "stone", 1, Vector3(0, 1.0, 0), Vector3(2.4, 2.0, 1.6))
	_box(parts, "wood", 0, Vector3(-1.6, 2.2, -1.2), Vector3(0.4, 4.4, 0.4))
	_box(parts, "wood", 0, Vector3(1.6, 2.2, -1.2), Vector3(0.4, 4.4, 0.4))
	parts.append({"part": "prism", "role": "wood", "shade": 1, "pos": Vector3(0, 4.9, -0.6),
		"size": Vector3(4.4, 1.4, 3.2), "yaw": 0.0, "tilt": 0.0})

# Nine uprights in a ring, one fallen.
static func _stones(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 9:
		var a := TAU * float(i) / 9.0
		var at := Vector2(cos(a), sin(a)) * RADIUS * 0.7
		var h := rng.randf_range(2.6, 4.2)
		if i == 4:
			_box(parts, "stone", 2, Vector3(at.x, 0.5, at.y), Vector3(1.4, 1.0, h), a, 0.0)
		else:
			_box(parts, "stone", 1, Vector3(at.x, h * 0.5, at.y), Vector3(1.4, h, 1.0), a, rng.randf_range(-0.08, 0.08))

# A hut with a cone of thatch and a woodpile.
static func _hut(parts: Array) -> void:
	_box(parts, "wood", 0, Vector3(0, 1.6, 0), Vector3(4.6, 3.2, 4.0))
	parts.append({"part": "cone", "role": "moss", "shade": 1, "pos": Vector3(0, 4.4, 0),
		"size": Vector3(6.0, 2.6, 6.0), "yaw": 0.0, "tilt": 0.0})
	_box(parts, "wood", 1, Vector3(3.6, 0.6, -1.5), Vector3(1.6, 1.2, 2.4))

# A wagon on its side, wheels off.
static func _wreck(parts: Array, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(-0.3, 0.3)
	parts.append({"part": "lean", "role": "wood", "shade": 0, "pos": Vector3(0, 1.4, 0),
		"size": Vector3(5.5, 2.4, 2.8), "yaw": yaw, "tilt": 0.9})
	parts.append({"part": "disc", "role": "dark", "shade": 1, "pos": Vector3(3.6, 0.2, 1.8),
		"size": Vector3(2.0, 0.3, 2.0), "yaw": 0.0, "tilt": 0.0})
	_box(parts, "cloth", 0, Vector3(-2.5, 0.3, -1.5), Vector3(2.4, 0.5, 1.8), yaw + 0.5)

# A square tower, the top broken.
static func _tower(parts: Array) -> void:
	_box(parts, "stone", 1, Vector3(0, HEIGHT * 0.5, 0), Vector3(3.6, HEIGHT, 3.6))
	_box(parts, "stone", 2, Vector3(0.9, HEIGHT + 0.8, 0.9), Vector3(1.6, 1.6, 1.6))
	_box(parts, "dark", 0, Vector3(0, 1.2, 1.9), Vector3(1.0, 2.0, 0.3))
