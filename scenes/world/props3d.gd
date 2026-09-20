# Shared base for the layers of things standing on the map — Settlements3D,
# Lairs3D and Party3D.
#
# WHAT CHANGED, AND WHY THIS FILE GOT SMALLER. This used to be world_diorama3d.gd,
# and most of it was a camera. Each layer owned a transparent SubViewport with
# its own Camera3D, its own sun, and its own copy of World's projection, laid
# over the 2D map; a diorama's position was computed by taking the map's world
# position, projecting it to a screen pixel with World._pix(), and projecting
# that back into the layer's private 3D space with world_for_screen(). Three
# copies of one camera, and a round trip through screen space to arrive back at
# the number it started from.
#
# There is one 3D world now (scenes/world/world_view3d.gd) and these are Node3Ds
# inside it. A landmark's position is its position: Vector3(x, 0, y). The round
# trip is gone, the three cameras are one camera, and — the part none of it
# could do before — a figure walking behind a city is behind the city, because
# they are in the same depth buffer.
#
# What a subclass owns: the model lookup, has_model()/reset() (what to show and
# when), and reposition() (which list to walk each frame). What this owns: model
# loading and height normalisation, the fog fade, and the two fog questions
# every layer asks.
extends Node3D

# Models are read through the shared cache rather than a dictionary of this
# layer's own: the player's figure on the map and the same hero in the fight
# are one file, and each layer keeping its own copy read and held it twice.
# See scenes/model_cache.gd.
const ModelCache := preload("res://scenes/model_cache.gd")

var world_map: Control         # scenes/world/world.gd
var view                       # scenes/world/world_view3d.gd — the shared 3D world


func _model(path: String) -> PackedScene:
	return ModelCache.get_scene(path)


# Every model a reset() is about to want, asked for in one go so the loader
# pool reads them in parallel instead of the screen paying for them one at a
# time. Subclasses call this at the top of their reset(), then build as they
# always did — _model() collects each one when it gets there.
func _prefetch(paths: Array) -> void:
	ModelCache.prefetch(paths)


# Uniform-scale `m` so its own mesh AABB is `target` tall, feet at y=0 — a
# diorama's raw scale is whatever Meshy happened to generate it at, unlike a
# rigged character (Meshy normalizes rig height itself), so this can't skip
# straight to a hand-picked constant the way figures3d.gd's FIGURE_SCALE does.
func _fit_height(m: Node3D, target: float) -> void:
	var aabb := _bounds(m)
	if aabb.size.y <= 0.0001:
		return
	var k := target / aabb.size.y
	m.scale = Vector3.ONE * k
	m.position.y -= aabb.position.y * k   # rest the lowest point on y=0


# Every mesh under `m`, merged, in m's own space.
#
# One level of transform, deliberately: `mesh.transform` and not the chain up
# to `m`. Walking the chain looks more correct and is not — a rigged figure's
# meshes hang under a Skeleton3D whose own transform is part of how the pose is
# expressed, so composing it in returns a box that has nothing to do with how
# tall the model is drawn, and _fit_height() then "corrects" a 15-unit figure
# to something several hundred units tall. (Observed, on the first attempt at
# footprint_of() below.) The GLBs this reads are authored flat enough for the
# one-level answer to be the right one.
static func _bounds(m: Node3D) -> AABB:
	var aabb := AABB()
	for mesh in m.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mesh.transform * mesh.get_aabb()
		aabb = a if aabb.size == Vector3.ZERO else aabb.merge(a)
	return aabb


# How much ground a built model actually stands on, in world units: half of its
# widest horizontal span, after whatever scaling it got.
#
# It is measured rather than declared because the footprint ring around a
# landmark has to CLEAR it, and how wide a landmark is depends on which art
# source built it — a rebuilt GLB fitted to a target height and a kit assembled
# from primitives do not come out the same width, and Settlements3D.source
# flips between them. A declared radius is a ring that quietly disappears
# inside the town the day somebody changes the source.
#
# Takes the MODEL, not the holder it hangs under: the scale is on the model.
static func footprint_of(m: Node3D) -> float:
	var b := _bounds(m)
	# _bounds() reads m's own space, so whatever uniform scale _fit_height()
	# gave it is not in there yet. A kit model is built at its final size and
	# has scale 1, so this is a no-op for those.
	var k: float = absf(m.scale.x)
	return k * maxf(
		maxf(absf(b.position.x), absf(b.position.x + b.size.x)),
		maxf(absf(b.position.z), absf(b.position.z + b.size.z)))


# T9x fog of war: a landmark is a real 3D object, drawn independently of the
# ground under it — the ground shader hiding a cell does nothing to the town
# standing on it, so every subclass's reposition() checks this before showing
# its own model.
func _explored(pos: Vector2) -> bool:
	return world_map.world.is_explored(pos)


# T9y: a landmark the party cannot see right now is a memory, and the ground it
# stands on is drawn that way (the fog's "remembered" tier). A full-brightness
# town on faded ground is exactly the mismatch the three-tier fog was meant to
# remove — the model has to fade with it.
#
# GeometryInstance3D.transparency rather than a material tint: it needs no
# material override (the GLBs and the kits bring their own), costs nothing to
# set every frame, and fading toward the dark ground behind it reads the same
# way the ground's own alpha drop does.
# ponytail: this fades, it does not desaturate — the ground does both. Close
# enough at map scale; a real match would mean a shader on every landmark.
#
# Both the mesh list and the last value applied are cached as metadata ON the
# holder: reposition() runs every frame for every landmark on the map, and
# walking a GLB's whole subtree with find_children() that often was measurably
# worse than the fade is worth. Metadata rather than a dictionary in this
# object because it dies with the node — reset() frees every holder, and a
# cache keyed on freed nodes is a leak waiting to be forgotten about.
const REMEMBERED_TRANSPARENCY := 0.55
func _fade(holder: Node3D, remembered: bool) -> void:
	var want: float = REMEMBERED_TRANSPARENCY if remembered else 0.0
	if not holder.has_meta("fade_meshes"):
		holder.set_meta("fade_meshes", holder.find_children("*", "GeometryInstance3D", true, false))
	elif is_equal_approx(float(holder.get_meta("fade_want", -1.0)), want):
		return                                  # already showing this, nothing to walk
	holder.set_meta("fade_want", want)
	for mesh in holder.get_meta("fade_meshes"):
		mesh.transparency = want


# Where the party is standing this frame, for _fade()'s "can they see it now"
# question — Vector2.ZERO on a world with no player, same null-tolerant
# contract as _explored() above.
func _player_pos() -> Vector2:
	var p = world_map.world.player()
	return p.position if p != null else Vector2.ZERO


# The map's 2D coordinates, on the 3D map's floor. core/world.gd calls its axes
# (x, y); the 3D world lays that plane out as (x, z) with y up.
static func at(pos: Vector2) -> Vector3:
	return Vector3(pos.x, 0.0, pos.y)


# Called once per frame by the view, in the same frame the camera was rebuilt.
# Subclasses walk their own list and set each model's .position (and, if it can
# be hidden — a lair, not a settlement — .visible).
func reposition() -> void:
	pass
