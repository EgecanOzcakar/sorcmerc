# Landmark dioramas on the 3D map — lairs3d.gd's shape, on core/world.gd's
# landmarks: hidden until found, faded once out of sight, footprint measured
# so the marker ring fits.
extends "res://scenes/world/props3d.gd"

const LandmarkKit := preload("res://scenes/world/landmark_kit.gd")

var _dioramas := {}   # landmark id -> Node3D
var _radius := {}

func has_model(l) -> bool:
	return _dioramas.has(l.id)

func reset(world) -> void:
	for n in _dioramas.values():
		n.queue_free()
	_dioramas.clear()
	_radius.clear()
	for l in world.landmarks:
		if not LandmarkKit.has(l.kind):
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(LandmarkKit.build(l.kind))
		holder.visible = l.found
		_dioramas[l.id] = holder
		_radius[l.id] = footprint_of(holder)

func reposition() -> void:
	var ppos := _player_pos()
	for l in world_map.world.landmarks:
		var n: Node3D = _dioramas.get(l.id)
		if n == null:
			continue
		n.visible = l.found and _explored(l.position)
		n.position = at(l.position)
		_fade(n, not world_map.world.is_visible_now(l.position, ppos))

func footprint(l) -> float:
	return float(_radius.get(l.id, 0.0))
