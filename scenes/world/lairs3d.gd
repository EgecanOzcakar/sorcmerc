# Every discovered lair on the map, as a diorama standing in the shared 3D
# world. The rig it lives in belongs to scenes/world/world_view3d.gd and the
# shared parts to scenes/world/props3d.gd; this file owns what is lair-specific:
# the per-id model lookup, hiding an undiscovered lair, and which world list to
# walk.
#
# What this layer does NOT own: the footprint under it (scenes/world/
# ground_marks3d.gd) or the name label above it (World._draw()).
#
# The "☠" glyph this used to fall back to is gone with the rest of the 2D prop
# tier. It cannot come back: a flat glyph pasted over a map whose camera turns
# has no place to stand. Every lair the game can produce has a kit (the five ids
# in LairKit.LAIRS, which is also the whole of procedural_world.gd's list), so
# there is nothing left for it to cover.
extends "res://scenes/world/props3d.gd"

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
var _radius := {}              # ...and how much ground it stands on, measured (props3d.footprint_of)


func _model_path(l) -> String:
	return String(MODELS.get(l.id, ""))


func has_model(l) -> bool:
	return _dioramas.has(l.id)


func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	_radius.clear()
	# Only the lairs this source will actually read a file for: with the kit
	# preferred (the default) a lair the kit covers never touches its GLB, and
	# asking for it anyway would read several megabytes to throw them away.
	_prefetch(world.lairs.filter(_wants_model).map(_model_path))
	for l in world.lairs:
		var m := _build(l)
		if m == null:
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(m)
		holder.visible = l.discovered   # stays hidden — that's the whole mechanic — until found
		_dioramas[l.id] = holder
		_radius[l.id] = footprint_of(m)


# Preferred source first, the other as fallback, null (so reset() skips it and
# has_model() stays false) when neither has anything. A kit lair is built in
# World units at its final size and must NOT go through _fit_height(), which
# exists to normalise a GLB whose raw scale is whatever Meshy generated it at.
func _build(l) -> Node3D:
	if not _wants_model(l):
		return LairKit.build(l.id)
	var scene := _model(_model_path(l))
	if scene != null:
		var m := scene.instantiate()
		_fit_height(m, TARGET_HEIGHT)
		return m
	return LairKit.build(l.id) if LairKit.has(l.id) else null


# Whether this lair's GLB is going to be read at all. It used to be loaded
# unconditionally and then discarded when the kit won, which with source ==
# "kit" — the default — meant every lair on the map paid for a model nothing
# ever drew.
func _wants_model(l) -> bool:
	return not (source == "kit" and LairKit.has(l.id))


func reposition() -> void:
	var ppos := _player_pos()
	for l in world_map.world.lairs:
		var n: Node3D = _dioramas.get(l.id)
		if n == null:
			continue
		n.visible = l.discovered and _explored(l.position)   # T9x: also fog of war
		n.position = at(l.position)
		# T9y: and a found lair you have walked away from is a memory, faded
		# the same way the ground it stands on is.
		_fade(n, not world_map.world.is_visible_now(l.position, ppos))


# How much ground this lair's diorama covers, in world units — see
# Settlements3D.footprint(), same contract.
func footprint(l) -> float:
	return float(_radius.get(l.id, 0.0))
