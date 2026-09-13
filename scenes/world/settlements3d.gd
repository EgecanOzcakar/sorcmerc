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
# Target screen height in px at zoom 1 (matching the 2D sprite tier's own
# h = r * factor in World._draw_settlement — 26/17/12 * 3.2/2.8/2.4), divided
# by World.ISO_GAIN to convert to world units. World's map coordinates are a
# totally different scale from Board's hex units (K ~= 1.85 px/unit here vs
# Board's ~46-94), so this can't reuse figures3d.gd's FIGURE_SCALE intuition —
# first render came out at 2px tall because of exactly that assumption.
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
		var scene := _model(_model_path(s))
		if scene == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		var m := scene.instantiate()
		holder.add_child(m)
		_fit_height(m, float(TARGET_HEIGHT.get(s.kind, 1.0)))
		_dioramas[s.id] = holder


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
