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

const LairKit := preload("res://scenes/world/lair_kit.gd")

# Which source is PREFERRED for a lair diorama; the other one is the fallback,
# and World._draw_lair()'s skull marker is still the last resort when neither
# covers a lair. Ordering rather than an either/or, because the two sources do
# not cover the same set: sunken-ruins and zombie-graveyard have no GLB at all
# (see assets/lairs/PROVENANCE.md), so under "glb" they still come back as kit
# dioramas instead of dropping to the glyph they render as today.
#
# Unlike Settlements3D.source this is genuinely undecided. A cave and a rock
# hold are the fused organic volumes text-to-3D is good at, which is the
# opposite of a village — see the header of lair_kit.gd.
static var source := "kit"

# One diorama per lair id, not per faction — unlike a settlement, a lair
# isn't a repeatable size tier, it's a unique named location (data/bestiary's
# thin "dragon"/"giant" pools would make faction-keying degenerate anyway).
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
		var m := _build(l)
		if m == null:
			continue
		var holder := Node3D.new()
		_sub.add_child(holder)
		holder.add_child(m)
		holder.visible = l.discovered   # stays hidden — that's the whole mechanic — until found
		_dioramas[l.id] = holder


# Preferred source first, the other as fallback, null (so reset() skips it and
# has_model() stays false) when neither has anything. A kit lair is built in
# World units at its final size and must NOT go through _fit_height(), which
# exists to normalise a GLB whose raw scale is whatever Meshy generated it at.
func _build(l) -> Node3D:
	var kit: bool = LairKit.has(l.id)
	var scene := _model(_model_path(l))
	if source == "kit" and kit:
		return LairKit.build(l.id)
	if scene != null:
		var m := scene.instantiate()
		_fit_height(m, TARGET_HEIGHT)
		return m
	return LairKit.build(l.id) if kit else null


func _reposition() -> void:
	var ppos := _player_pos()
	for l in world_map.world.lairs:
		var n: Node3D = _dioramas.get(l.id)
		if n == null:
			continue
		n.visible = l.discovered and _explored(l.position)   # T9x: also fog of war
		n.position = world_for_screen(world_map._pix(l.position))
		# T9y: and a found lair you have walked away from is a memory, drawn
		# the same washed-out way its 2D marker is.
		_fade(n, not world_map.world.is_visible_now(l.position, ppos))
