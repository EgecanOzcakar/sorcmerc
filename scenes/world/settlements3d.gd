# Tier 0 for settlements: a real 3D diorama standing where World draws a
# settlement's building cluster. Shared SubViewport/camera/projection rig
# lives in world_diorama3d.gd (also used by Lairs3D) — this file only owns
# what's settlement-specific: the (faction, kind) model lookup and which
# world list to walk.
#
# What this layer does NOT own: the shadow ellipse, footprint ring, and name
# label World._draw_settlement() already draws — those stay shared across
# every settlement regardless of tier, same contract as Board's HP bar. This
# only replaces the building-cluster sprite blocks.
extends "res://scenes/world/world_diorama3d.gd"

const SettlementKit := preload("res://scenes/world/settlement_kit.gd")

# Which tier-0 source builds a diorama, with the same graceful fallback either
# way — whatever neither source covers drops through has_model() to the 2D
# BuildingTex sprite tier, exactly as before.
#
#   "glb"  the twelve dioramas in assets/settlements/, REBUILT low-poly:
#          8k flat-faceted triangles carrying their old atlas as vertex colour
#          (tools/lowpoly_glb.py). Real building shapes, twelve fixed looks.
#   "kit"  settlement_kit.gd assembles one from primitives, seeded per
#          settlement id. ~2k triangles for a city, no texture at all, and a
#          different village per id — the thing twelve fixed models cannot do.
#
# "glb" is the default because at the size a settlement is drawn the rebuilt
# models read as buildings and the kit reads as blocks; the kit stays because
# it is the only source with per-settlement variety, and because it is what
# covers a faction or size the twelve models do not.
#
# A static var rather than a const because it is a comparison switch, not a
# setting: tests/shot_settlement_kit.gd flips it to shoot both sources through
# the same rig, which is the only honest way to look at the two side by side.
static var source := "glb"

# The GLB lookup, one model per (faction, kind) — not per settlement instance,
# so under "glb" two towns of the same race are the same building (that's
# already true of the 2D tier's style/pair hash, just coarser: one look per
# size now, not a random pick per id).
const MODELS := {
	"dwarf": {"camp": "res://assets/settlements/dwarf_camp.glb", "town": "res://assets/settlements/dwarf_town.glb", "city": "res://assets/settlements/dwarf_city.glb"},
	"elf": {"camp": "res://assets/settlements/elf_camp.glb", "town": "res://assets/settlements/elf_town.glb", "city": "res://assets/settlements/elf_city.glb"},
	"human": {"camp": "res://assets/settlements/human_camp.glb", "town": "res://assets/settlements/human_town.glb", "city": "res://assets/settlements/human_city.glb"},
	"orc": {"camp": "res://assets/settlements/orc_camp.glb", "town": "res://assets/settlements/orc_town.glb", "city": "res://assets/settlements/orc_city.glb"},
}
# The one material every rebuilt model wears. The low-poly pass threw the 2048
# atlas away and baked it into COLOR_0, and glTF's own material does not say
# "use those" — without this the whole settlement imports flat white. It is also
# where the kit's look comes from: no albedo map, high roughness, no specular,
# so the only shading is the diorama rig's sun and an edge stays an edge at 10px.
static var _flat_material: StandardMaterial3D = null

static func _flat() -> StandardMaterial3D:
	if _flat_material == null:
		_flat_material = StandardMaterial3D.new()
		_flat_material.vertex_color_use_as_albedo = true
		_flat_material.roughness = 0.92
		_flat_material.metallic = 0.0
		_flat_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _flat_material


# Public because anything that instantiates one of these models has to do it —
# the gallery shot (tests/shot_settlement_kit.gd) included. Forgetting it is not
# subtle: the settlement renders flat white.
static func dress(m: Node3D) -> void:
	for mesh in m.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = _flat()


# Target screen height in px at zoom 1 (matching the 2D sprite tier's own
# h = r * factor in World._draw_settlement — 26/17/12 * 3.2/2.8/2.4), divided
# by World.ISO_GAIN to convert to world units. World's map coordinates are a
# totally different scale from Board's hex units (K ~= 1.85 px/unit here vs
# Board's ~46-94), so this can't reuse figures3d.gd's FIGURE_SCALE intuition —
# first render came out at 2px tall because of exactly that assumption.
#
# Used by the "glb" source only — the kit builds at these heights itself
# (SettlementKit.PLANS mirrors them, deliberately, so swapping source doesn't
# change how big a settlement is on the map).
const TARGET_HEIGHT := {"camp": 15.6, "town": 25.7, "city": 45.0}

var _dioramas := {}            # settlement id -> Node3D


func _model_path(s) -> String:
	return String(MODELS.get(s.faction, {}).get(s.kind, ""))


func has_model(s) -> bool:
	return _dioramas.has(s.id)


func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	for s in world.settlements:
		var m := _build(s)
		if m == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		holder.add_child(m)
		_dioramas[s.id] = holder


# The one place the two sources differ. A kit diorama is built in World units at
# its final size, so it must NOT go through _fit_height() — that exists to
# normalise a GLB, whose raw scale is whatever Meshy happened to generate it at.
# Running it on the kit would undo the deliberate height/footprint ratio in
# SettlementKit.PLANS.
func _build(s) -> Node3D:
	if source == "kit" and SettlementKit.has(s.faction, s.kind):
		return SettlementKit.build(s.faction, s.kind, s.id)
	var scene := _model(_model_path(s))
	if scene == null:
		return null
	var m := scene.instantiate()
	_fit_height(m, float(TARGET_HEIGHT.get(s.kind, 1.0)))
	dress(m)
	# There are twelve models and a map has more settlements than that, so two
	# towns of the same faction ARE the same model. A seeded yaw is the cheapest
	# thing that stops them reading as copy-paste: enough to change which gable
	# faces the camera, not enough to swing a diorama's lit side away from the
	# sun the whole map shares.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%s" % [s.id, s.faction])
	m.rotate_y(deg_to_rad(rng.randf_range(-22.0, 22.0)))
	return m


func _reposition() -> void:
	var ppos := _player_pos()
	for s in world_map.world.settlements:
		var n: Node3D = _dioramas.get(s.id)
		if n == null:
			continue
		# T9x: settlements are landmarks, always shown regardless of fog —
		# matches World._draw()'s own 2D layer (both changed together).
		n.visible = true
		n.position = world_for_screen(world_map._pix(s.position))
		_fade(n, not world_map.world.is_visible_now(s.position, ppos))
