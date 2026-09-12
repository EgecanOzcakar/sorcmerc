# Tier 0 for lairs: a real 3D diorama standing where World draws a discovered
# lair's skull marker. Shared SubViewport/camera/projection rig lives in
# world_diorama3d.gd (also used by Settlements3D) — this file only owns
# what's lair-specific: the per-id model lookup, hiding an undiscovered
# lair's diorama, and which world list to walk.
#
# What this layer does NOT own: the shadow ellipse, footprint ring, and name
# label World._draw_lair() already draws — those stay shared, same contract
# as Settlements3D. This only replaces the "☠" glyph.
extends "res://scenes/world/world_diorama3d.gd"

# One diorama per lair id, not per faction — unlike a settlement, a lair
# isn't a repeatable size tier, it's a unique named location (data/bestiary's
# thin "dragon"/"giant" pools would make faction-keying degenerate anyway).
# Missing entries fall through has_model() to World._draw_lair()'s skull
# marker, same fallback contract as Settlements3D/Figures3D.
const MODELS := {
	"goblin-warren": "res://assets/lairs/goblin-warren.glb",
	"giant-hold": "res://assets/lairs/giant-hold.glb",
	"sunken-ruins": "res://assets/lairs/sunken-ruins.glb",
	"zombie-graveyard": "res://assets/lairs/zombie-graveyard.glb",
	"dragon-cave": "res://assets/lairs/dragon-cave.glb",
}
const TARGET_HEIGHT := 22.0   # one size fits all — lairs aren't tiered like settlements

var _dioramas := {}            # lair id -> Node3D


func _model_path(l) -> String:
	return String(MODELS.get(l.id, ""))


func has_model(l) -> bool:
	return _dioramas.has(l.id)


func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	for l in world.lairs:
		var scene := _model(_model_path(l))
		if scene == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		var m := scene.instantiate()
		holder.add_child(m)
		_fit_height(m, TARGET_HEIGHT)
		holder.visible = l.discovered   # stays hidden — that's the whole mechanic — until found
		_dioramas[l.id] = holder


func _reposition() -> void:
	for l in world_map.world.lairs:
		var n: Node3D = _dioramas.get(l.id)
		if n == null:
			continue
		n.visible = l.discovered
		n.position = world_for_screen(world_map._pix(l.position))
