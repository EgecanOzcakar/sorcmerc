# The things standing on a combat board, built rather than modelled.
#
# WHY THIS EXISTS. Issue #167: the board had six object types in it — torch,
# brazier, campfire, lamp, barrel, fountain — and every one of them was a flat
# shape drawn in Board._draw_object, while the figures standing between them
# were real 3D. Cover and rough, which are on EVERY board and are the two
# things a player most needs to see, were a scatter of 2D leaf blobs keyed off
# a hex hash.
#
# WHY A KIT AND NOT GLBs. The issue asks for models and the honest answer is
# that a barrel is not worth a Meshy round trip: kit_parts.gd already builds
# settlements and lairs out of seven primitives at ~1-2k triangles against a
# GLB's ~82k, and a crate IS a box. Everything here is one to six primitives.
# Anything this file has no plan for falls through to a plain box, which is the
# same contract kit_parts.gd's own PARTS table keeps — a typo should draw
# something visibly wrong, not crash a fight.
#
# WHAT THIS DELIBERATELY DOES NOT OWN. Any mechanic whatsoever. Cover, rough,
# hazards, what blocks movement and what can be smashed are core/encounter.gd's
# boards and core/combat.gd's rules; this file reads a hex's role and draws
# something that looks like it. That separation is what lets scenery be added
# to a board without re-running tests/test_scaler.gd — a prop that changed a
# number would be a balance edit wearing a palette.
#
# SCALE is the combat world's: one unit is one hex radius (see figures3d.gd's
# projection note), and a hero stands 1.2 * FIGURE_SCALE = 1.5 units tall. So a
# tree at 2.6 reads as taller than a person and a barrel at 0.7 as waist-high,
# which is what the words mean.
extends RefCounted

const KitParts = preload("res://scenes/world/kit_parts.gd")

# One palette for the whole board rather than one per prop: these are lit by
# the same sun as the figures and sit on the same ground, and a per-prop palette
# made the first render look like a toy box tipped over.
const PALETTE := {
	"wood": Color("5b4630"), "dark": Color("3a2d20"), "stone": Color("6f6a5e"),
	"pale": Color("9a927f"), "iron": Color("3c3a36"), "leaf": Color("41603c"),
	"reed": Color("6b7a45"), "gorse": Color("5c6b33"), "ice": Color("7f9aa8"),
	"fire": Color("c8541f"), "cloth": Color("7a5a3a"), "bone": Color("cfc4a4"),
	"water": Color("2f5560"),
}

# What a cover hex IS, per board palette. Cover is the one piece of terrain a
# player has to read at a glance — tests/test_cover_readable.gd exists for
# exactly that — so every board names something solid rather than sharing one
# generic bush.
const COVER := {
	"forest": "tree", "marsh": "reeds", "downs": "menhir", "city": "crate-stack",
	"shrine": "pillar", "camp": "stakes", "ice": "icicle", "shop": "shelf",
}

# ...and what rough ground is. Lower and wider than cover, always: rough costs
# movement and blocks nothing, so it must never read as something to hide
# behind. Nothing here rises above 0.5 units, which is knee-high on a hero.
const ROUGH := {
	"forest": "bramble", "marsh": "tussock", "downs": "gorse", "city": "rubble",
	"shrine": "rubble", "camp": "ash", "ice": "floe", "shop": "crate-low",
}

const COVER_FALLBACK := "crate"
const ROUGH_FALLBACK := "rubble"


static func cover_kind(palette: String) -> String:
	return String(COVER.get(palette, COVER_FALLBACK))


static func rough_kind(palette: String) -> String:
	return String(ROUGH.get(palette, ROUGH_FALLBACK))


# Every kind this file draws on purpose. Anything else still builds — as a box —
# and tests/test_board_props.gd asserts that every kind any board can ask for is
# in here, so the box is a safety net rather than a shipping state.
# The seven are the object types core/encounter.gd's boards actually place, and
# they are listed rather than read off the boards on purpose: this file must not
# import Encounter (a prop knows nothing about a fight), and the test is what
# holds the two lists together — it walks every board and fails if one places
# something not named here.
static func kinds() -> Array:
	var out: Array = ["torch", "brazier", "campfire", "lamp", "barrel", "fountain", "crate"]
	for k in COVER.values():
		if not k in out:
			out.append(k)
	for k in ROUGH.values():
		if not k in out:
			out.append(k)
	return out


# `seed_v` varies a prop off its own hex so a row of trees is not one tree
# stamped six times — the same trick kit_parts' SHADES plays with colour, one
# level up. A caller passing 0 gets the same prop every time, which is what a
# gallery shot wants.
static func plan(kind: String, seed_v: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("prop/%s/%d" % [kind, seed_v])
	var parts: Array = []
	match kind:
		"tree": _tree(parts, rng)
		"reeds": _reeds(parts, rng)
		"menhir": _menhir(parts, rng)
		"pillar": _pillar(parts, rng)
		"stakes": _stakes(parts, rng)
		"icicle": _icicle(parts, rng)
		"shelf": _shelf(parts, rng)
		"crate": _crate(parts, rng, 0.8)
		"crate-low": _crate(parts, rng, 0.42)
		"crate-stack": _crate_stack(parts, rng)
		"barrel": _barrel(parts, rng)
		"bramble": _scrub(parts, rng, "leaf", 0.34)
		"tussock": _scrub(parts, rng, "reed", 0.40)
		"gorse": _scrub(parts, rng, "gorse", 0.36)
		"floe": _floe(parts, rng)
		"ash": _scrub(parts, rng, "dark", 0.22)
		"rubble": _rubble(parts, rng)
		"torch": _torch(parts, rng)
		"lamp": _lamp(parts, rng)
		"brazier": _brazier(parts, rng)
		"campfire": _campfire(parts, rng)
		"fountain": _fountain(parts, rng)
		_: _crate(parts, rng, 0.7)     # the visible-typo case, same as KitParts' own
	return parts


static func build(kind: String, seed_v: int = 0) -> Node3D:
	return KitParts.assemble(plan(kind, seed_v), PALETTE, "boardprop")


static func triangles(kind: String) -> int:
	return KitParts.triangles(plan(kind, 0))


static func _p(parts: Array, part: String, role: String, shade: int,
		pos: Vector3, size: Vector3, yaw := 0.0, tilt := 0.0) -> void:
	parts.append({"part": part, "role": role, "shade": shade,
		"pos": pos, "size": size, "yaw": yaw, "tilt": tilt})


static func _jit(rng: RandomNumberGenerator, n: float) -> float:
	return rng.randf_range(-n, n)


# --- cover: waist-high or taller, and solid ---------------------------------

# Trunk plus two lobes. Two rather than one because a single ball reads as a
# lollipop at this size, and rather than five because the board fields up to a
# dozen of these and they are 24 triangles each.
static func _tree(parts: Array, rng: RandomNumberGenerator) -> void:
	var h: float = 2.4 + _jit(rng, 0.45)
	_p(parts, "post", "wood", 0, Vector3(0, h * 0.34, 0), Vector3(0.28, h * 0.68, 0.28),
		0.0, _jit(rng, 0.07))
	_p(parts, "rock", "leaf", 2, Vector3(_jit(rng, 0.14), h * 0.78, _jit(rng, 0.14)),
		Vector3(1.22, 1.05, 1.22), rng.randf() * TAU)
	_p(parts, "rock", "leaf", 0, Vector3(_jit(rng, 0.2), h * 0.98, _jit(rng, 0.2)),
		Vector3(0.82, 0.72, 0.82), rng.randf() * TAU)


# Four blades off one clump. Tilted apart rather than parallel: reed that stands
# straight looks like a fence, and this has to read as something you can see
# through but not across.
static func _reeds(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "disc", "water", 0, Vector3(0, 0.05, 0), Vector3(1.5, 0.1, 1.5))
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + _jit(rng, 0.5)
		var h: float = 1.5 + _jit(rng, 0.35)
		_p(parts, "post", "reed", i % 3, Vector3(cos(a) * 0.26, h * 0.5, sin(a) * 0.26),
			Vector3(0.12, h, 0.12), a, deg_to_rad(9.0 + _jit(rng, 6.0)))


# A standing stone, leaning. The downs have no trees and no walls, so this is
# the only thing on that board tall enough to put between you and an archer.
static func _menhir(parts: Array, rng: RandomNumberGenerator) -> void:
	var h: float = 1.9 + _jit(rng, 0.3)
	_p(parts, "box", "stone", 1, Vector3(0, h * 0.5, 0), Vector3(0.62, h, 0.44),
		rng.randf() * TAU, deg_to_rad(5.0 + _jit(rng, 4.0)))
	_p(parts, "rock", "pale", 0, Vector3(0, 0.1, 0), Vector3(1.05, 0.2, 1.05))


static func _pillar(parts: Array, rng: RandomNumberGenerator) -> void:
	var h: float = 2.2 + _jit(rng, 0.25)
	_p(parts, "disc", "pale", 0, Vector3(0, 0.12, 0), Vector3(0.95, 0.24, 0.95))
	_p(parts, "post", "pale", 1, Vector3(0, h * 0.5, 0), Vector3(0.5, h, 0.5))
	_p(parts, "box", "stone", 0, Vector3(0, h + 0.1, 0), Vector3(0.8, 0.2, 0.8),
		rng.randf() * 0.3)


static func _stakes(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var a: float = TAU * float(i) / 3.0 + _jit(rng, 0.3)
		var h: float = 1.5 + _jit(rng, 0.3)
		_p(parts, "cone", "wood", i % 3, Vector3(cos(a) * 0.3, h * 0.5, sin(a) * 0.3),
			Vector3(0.22, h, 0.22), a, deg_to_rad(_jit(rng, 12.0)))


static func _icicle(parts: Array, rng: RandomNumberGenerator) -> void:
	var h: float = 2.0 + _jit(rng, 0.4)
	_p(parts, "cone", "ice", 2, Vector3(0, h * 0.5, 0), Vector3(0.62, h, 0.62),
		rng.randf() * TAU, deg_to_rad(_jit(rng, 5.0)))
	_p(parts, "rock", "ice", 0, Vector3(_jit(rng, 0.25), 0.16, _jit(rng, 0.25)),
		Vector3(0.6, 0.3, 0.6))


static func _shelf(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "box", "wood", 1, Vector3(0, 0.85, 0), Vector3(0.9, 1.7, 0.35), _jit(rng, 0.2))
	for i in 2:
		_p(parts, "box", "dark", 0, Vector3(0, 0.55 + 0.6 * float(i), 0.04),
			Vector3(0.95, 0.07, 0.42), _jit(rng, 0.2))


# --- objects the boards already name ----------------------------------------

static func _crate(parts: Array, rng: RandomNumberGenerator, h: float) -> void:
	_p(parts, "box", "wood", 1, Vector3(0, h * 0.5, 0), Vector3(h * 0.95, h, h * 0.95),
		rng.randf() * TAU, 0.0)
	_p(parts, "box", "dark", 0, Vector3(0, h * 0.52, 0), Vector3(h * 1.0, h * 0.09, h * 1.0),
		rng.randf() * TAU)


# Two crates and a barrel, which is a barricade rather than a box.
#
# The single crate was the city's cover to begin with and
# tests/test_board_props.gd refused it at 0.80 units, which was the test being
# right for a reason worth writing down. RAW half cover IS waist-high — "a low
# wall, a large piece of furniture" — but this board is drawn down a shallow
# isometric with height foreshortened by cos(theta), so a waist-high box reads
# as a mark on the floor rather than as something between you and an archer.
# The board has to say "cover" at the angle it is actually seen from.
static func _crate_stack(parts: Array, rng: RandomNumberGenerator) -> void:
	_crate(parts, rng, 0.82)
	_p(parts, "box", "wood", 2, Vector3(_jit(rng, 0.1), 1.14, _jit(rng, 0.1)),
		Vector3(0.66, 0.64, 0.66), rng.randf() * TAU)
	_p(parts, "post", "wood", 0, Vector3(0.52, 0.32, -0.44), Vector3(0.5, 0.64, 0.5),
		rng.randf() * TAU)


static func _barrel(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "post", "wood", 1, Vector3(0, 0.36, 0), Vector3(0.62, 0.72, 0.62),
		rng.randf() * TAU)
	for i in 2:
		_p(parts, "disc", "iron", 0, Vector3(0, 0.2 + 0.32 * float(i), 0),
			Vector3(0.68, 0.06, 0.68))


static func _torch(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "post", "wood", 0, Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12),
		0.0, deg_to_rad(_jit(rng, 5.0)))
	_p(parts, "cone", "fire", 2, Vector3(0, 1.36, 0), Vector3(0.3, 0.42, 0.3))


static func _lamp(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "post", "iron", 0, Vector3(0, 0.72, 0), Vector3(0.1, 1.44, 0.1),
		0.0, deg_to_rad(_jit(rng, 4.0)))
	_p(parts, "box", "iron", 1, Vector3(0, 1.54, 0), Vector3(0.3, 0.32, 0.3), rng.randf())
	_p(parts, "cone", "fire", 2, Vector3(0, 1.54, 0), Vector3(0.16, 0.22, 0.16))


static func _brazier(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var a: float = TAU * float(i) / 3.0
		_p(parts, "post", "iron", 0, Vector3(cos(a) * 0.22, 0.3, sin(a) * 0.22),
			Vector3(0.08, 0.6, 0.08), a, deg_to_rad(11.0))
	_p(parts, "disc", "iron", 1, Vector3(0, 0.64, 0), Vector3(0.78, 0.18, 0.78))
	_p(parts, "cone", "fire", 2, Vector3(0, 0.92, 0), Vector3(0.5, 0.56, 0.5),
		rng.randf() * TAU)


static func _campfire(parts: Array, rng: RandomNumberGenerator) -> void:
	_p(parts, "disc", "stone", 0, Vector3(0, 0.08, 0), Vector3(1.15, 0.16, 1.15))
	for i in 3:
		var a: float = TAU * float(i) / 3.0 + _jit(rng, 0.3)
		_p(parts, "post", "wood", 1, Vector3(cos(a) * 0.18, 0.26, sin(a) * 0.18),
			Vector3(0.11, 0.52, 0.11), a, deg_to_rad(26.0))
	_p(parts, "cone", "fire", 2, Vector3(0, 0.5, 0), Vector3(0.52, 0.6, 0.52))


static func _fountain(parts: Array, _rng: RandomNumberGenerator) -> void:
	_p(parts, "disc", "pale", 0, Vector3(0, 0.14, 0), Vector3(1.5, 0.28, 1.5))
	_p(parts, "disc", "water", 2, Vector3(0, 0.3, 0), Vector3(1.2, 0.06, 1.2))
	_p(parts, "post", "pale", 1, Vector3(0, 0.6, 0), Vector3(0.24, 0.6, 0.24))


# --- rough: ankle-to-knee, never anything to hide behind --------------------

static func _scrub(parts: Array, rng: RandomNumberGenerator, role: String, h: float) -> void:
	for i in 3:
		var a: float = TAU * float(i) / 3.0 + _jit(rng, 0.7)
		_p(parts, "rock", role, i % 3,
			Vector3(cos(a) * 0.34, h * 0.45, sin(a) * 0.34),
			Vector3(0.6 + _jit(rng, 0.14), h, 0.6 + _jit(rng, 0.14)), rng.randf() * TAU)


static func _rubble(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + _jit(rng, 0.6)
		var s: float = 0.26 + _jit(rng, 0.09)
		_p(parts, "rock", "stone" if i % 2 == 0 else "pale", i % 3,
			Vector3(cos(a) * 0.36, s * 0.4, sin(a) * 0.36),
			Vector3(s * 2.0, s, s * 1.7), rng.randf() * TAU, deg_to_rad(_jit(rng, 14.0)))


static func _floe(parts: Array, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var a: float = TAU * float(i) / 3.0 + _jit(rng, 0.5)
		_p(parts, "box", "ice", i % 3, Vector3(cos(a) * 0.32, 0.09, sin(a) * 0.32),
			Vector3(0.6, 0.18, 0.5), rng.randf() * TAU, deg_to_rad(_jit(rng, 9.0)))
