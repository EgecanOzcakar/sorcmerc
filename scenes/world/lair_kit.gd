# Lair dioramas assembled from modules, the same way settlement_kit.gd builds
# settlements — see kit_parts.gd for the plan format and the primitives.
#
# WHY THIS EXISTS, in two parts.
#
# 1. TWO LAIRS HAVE NO MODEL AT ALL. Lairs3D.MODELS names five, and
#    assets/lairs/ holds three: sunken-ruins and zombie-graveyard were deferred
#    (see that directory's PROVENANCE.md) on the theory they would turn up on
#    Meshy's Community feed. Until then both render as World._draw_lair()'s "☠"
#    glyph while their three neighbours are 3D. A kit fills that gap today and
#    costs nothing to keep as the fallback afterwards.
#
# 2. THE OTHER THREE ARE HERE TO BE COMPARED. goblin-warren, giant-hold and
#    dragon-cave all have GLBs, and those GLBs are not obviously worse than a
#    kit the way the settlement ones were — a cave and a rock hold are exactly
#    the fused organic volumes that reconstruction is GOOD at, which is the
#    opposite of a village's flat planes and straight ridgelines. So the kit
#    builds all five and Lairs3D.source switches between them, and the answer
#    is whatever tests/shot_lair_kit.gd shows rather than whatever this comment
#    would like to be true.
#
# SCALE. Lairs3D fits a GLB to TARGET_HEIGHT 22.0 World units, one size for all
# of them ("lairs aren't tiered like settlements"), which lands at 22 * 1.85 =
# ~41px tall at zoom 1. HEIGHT below mirrors that constant so switching source
# changes how a lair looks and not how big it is.
extends RefCounted

const KitParts = preload("res://scenes/world/kit_parts.gd")

# Mirrors Lairs3D.TARGET_HEIGHT. The footprint is deliberately wide against it:
# a lair is a place in a landscape, not a tower, and all five of these read as
# something spread across the ground with one tall thing in it.
const HEIGHT := 22.0
const RADIUS := 15.0

# Per-lair palette and shape. `roles` are the colour keys the builders below
# ask KitParts for; every builder shares "ground" and most share "stone".
const LAIRS := {
	"goblin-warren": {
		"ground": Color("5e5334"), "hide": Color("8c7a4e"), "wood": Color("4e3f2a"),
		"stone": Color("6d6455"), "bone": Color("d8cfae"), "fire": Color("c8541f"),
	},
	"giant-hold": {
		"ground": Color("62604f"), "stone": Color("77705f"), "dark": Color("46423a"),
		"wood": Color("5a4a34"), "moss": Color("5c6b45"), "bone": Color("cfc7a8"),
	},
	"dragon-cave": {
		"ground": Color("534a42"), "stone": Color("655c54"), "dark": Color("14100e"),
		"scorch": Color("3a2a22"), "gold": Color("c8a132"), "bone": Color("cfc4a4"),
	},
	"sunken-ruins": {
		"ground": Color("4a5748"), "stone": Color("b3bcb2"), "dark": Color("5d6a5c"),
		"water": Color("21403f"), "moss": Color("55703f"), "bone": Color("b9c0ad"),
	},
	"zombie-graveyard": {
		"ground": Color("4a4335"), "stone": Color("9a978c"), "dark": Color("2e2a24"),
		"iron": Color("34322e"), "wood": Color("4a3d2c"), "moss": Color("5a6340"),
	},
}


static func has(id: String) -> bool:
	return LAIRS.has(id)


# One lair's parts, in World units, y=0 on the ground. Deterministic in `id`
# alone — and since a lair id IS its kind here (there is one goblin-warren on a
# map, not a tier of them), that means a given lair looks the same every load
# without also meaning every lair looks alike.
static func plan(id: String) -> Array:
	if not has(id):
		return []
	return _plan(id, id)


# `shape` is which of the five builders; `key` seeds it, so two lairs built on
# one shape (a kobold pit and an orc camp, both stockades) are still two places.
static func _plan(shape: String, key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lair/%s" % key)
	var parts: Array = []
	match shape:
		"goblin-warren": _warren(parts, rng)
		"giant-hold": _hold(parts, rng)
		"dragon-cave": _cave(parts, rng)
		"sunken-ruins": _ruins(parts, rng)
		"zombie-graveyard": _graveyard(parts, rng)
	KitParts.apron(parts, "ground", RADIUS * 1.05)
	return parts


static func build(id: String) -> Node3D:
	return KitParts.assemble(plan(id), LAIRS[id], id)


# --- every other lair: a kit by faction --------------------------------------
#
# A lair id this file has no plan for — the ten core/world_homes.gd places
# (2026-09-25), a content pack's own ("ash-warren", "the-crown-vault"), a raid's
# outpost — used to come back null from Lairs3D._build(), and a found lair drew
# nothing at all: a name label over bare ground. Every lair has a faction, so
# the faction picks one of the five shapes and a palette of its own, and the
# lair's id seeds it. Not five more hand-built dioramas; a place that reads as
# its people's until one is authored (the Still open of the 2026-09-25 entry).
#
# `shape` is a key of LAIRS above; `colours` overrides that shape's palette.
# A faction nobody listed gets the ruins, the one shape that belongs to nobody.
const FACTION_KITS := {
	"goblinoid": {"shape": "goblin-warren", "colours": {}},
	"giant": {"shape": "giant-hold", "colours": {}},
	"dragon": {"shape": "dragon-cave", "colours": {}},
	"undead": {"shape": "zombie-graveyard", "colours": {}},
	# Stockades: the camp-builders, told apart by what their hides and fires are.
	"bandit": {"shape": "goblin-warren", "colours": {"ground": Color("5a5238"),
		"hide": Color("6e5a44"), "wood": Color("4a3b2a"), "fire": Color("c8641f")}},
	"kobold": {"shape": "goblin-warren", "colours": {"ground": Color("5c4a36"),
		"hide": Color("a0582e"), "wood": Color("4a3626"), "fire": Color("d8a030")}},
	"orc": {"shape": "goblin-warren", "colours": {"ground": Color("564a34"),
		"hide": Color("5e6a3a"), "wood": Color("3e3122"), "fire": Color("b8421a")}},
	"gnoll": {"shape": "goblin-warren", "colours": {"ground": Color("6a5a3a"),
		"hide": Color("9a8250"), "bone": Color("e0d6b6"), "fire": Color("c0501c")}},
	# Standing stones: the old and the made.
	"beast": {"shape": "giant-hold", "colours": {"ground": Color("4f5a3a"),
		"stone": Color("5f6650"), "moss": Color("4f6b35"), "dark": Color("33382a")}},
	"elemental": {"shape": "giant-hold", "colours": {"ground": Color("4a4640"),
		"stone": Color("8a7a66"), "moss": Color("c8641f"), "dark": Color("3a3530")}},
	"construct": {"shape": "giant-hold", "colours": {"ground": Color("4a4a48"),
		"stone": Color("6e6e6a"), "moss": Color("8a6a3a"), "dark": Color("2c2c2e")}},
	# Ruins: somebody else's building, now used for something worse.
	"cultist": {"shape": "sunken-ruins", "colours": {"ground": Color("3e3a3c"),
		"stone": Color("7a7270"), "water": Color("3a1618"), "moss": Color("4a3a4a")}},
	"fey": {"shape": "sunken-ruins", "colours": {"ground": Color("3f5a3c"),
		"stone": Color("a8b4a0"), "water": Color("2c4a52"), "moss": Color("5e8a3e")}},
	"monstrosity": {"shape": "dragon-cave", "colours": {"gold": Color("8c7a5a"),
		"scorch": Color("2e2a24")}},
}


# The plan for any lair: its own if it has one, else its faction's.
static func plan_for(id: String, faction: String) -> Array:
	if has(id):
		return plan(id)
	return _plan(_faction_kit(faction)["shape"], id)


static func build_for(id: String, faction: String) -> Node3D:
	if has(id):
		return build(id)
	var kit: Dictionary = _faction_kit(faction)
	var palette: Dictionary = LAIRS[kit["shape"]].duplicate()
	palette.merge(kit["colours"], true)
	# The material cache is keyed on this name (KitParts.material_for), so the
	# key is the faction's, not the shape's: an orc camp must not come out in
	# the goblins' hide because a goblin warren was drawn first.
	return KitParts.assemble(_plan(kit["shape"], id), palette, "%s@%s" % [kit["shape"], faction])


static func _faction_kit(faction: String) -> Dictionary:
	return FACTION_KITS.get(faction, {"shape": "sunken-ruins", "colours": {}})


static func triangles(id: String) -> int:
	return KitParts.triangles(plan(id))


# --- the five lairs ---------------------------------------------------------

# A goblin warren: crooked hide lean-tos round a fire, inside a spiked stockade.
# The spikes are the silhouette — at 41px the huts are lumps and the ring of
# uneven points above them is the only thing that says "do not walk in here".
static func _warren(parts: Array, rng: RandomNumberGenerator) -> void:
	var taken: Array = []

	# The totem, dead centre: the warren's one tall thing. Without it the whole
	# diorama topped out at 9.6 units against the 22 a GLB is fitted to, so a
	# warren rendered at half the size of the lair next to it — the first render
	# of this file had exactly that bug, and it is why HEIGHT is asserted.
	parts.append({"part": "post", "role": "wood", "shade": 1,
		"pos": Vector3(0, HEIGHT * 0.46, 0), "size": Vector3(2.0, HEIGHT * 0.92, 2.0),
		"yaw": 0.0, "tilt": deg_to_rad(3.0)})
	for i in 2:
		parts.append({"part": "box", "role": "hide", "shade": 2,
			"pos": Vector3(0, HEIGHT * (0.60 + 0.16 * float(i)), 0),
			"size": Vector3(6.4 - 1.6 * float(i), 0.6, 0.6),
			"yaw": 0.9 * float(i), "tilt": 0.0})
	parts.append({"part": "rock", "role": "bone", "shade": 2,
		"pos": Vector3(0, HEIGHT * 0.95, 0), "size": Vector3(2.6, 2.6, 2.6),
		"yaw": 0.0, "tilt": 0.0})
	taken.append([Vector2.ZERO, 4.2])

	# The fire pit beside it, low and off centre, for the one warm colour on an
	# otherwise brown diorama.
	var fire := Vector2(RADIUS * 0.26, RADIUS * 0.16)
	parts.append({"part": "disc", "role": "stone", "shade": 0,
		"pos": Vector3(fire.x, 0.6, fire.y), "size": Vector3(5.0, 1.2, 5.0),
		"yaw": 0.0, "tilt": 0.0})
	parts.append({"part": "cone", "role": "fire", "shade": 2,
		"pos": Vector3(fire.x, 2.5, fire.y), "size": Vector3(2.8, 3.8, 2.8),
		"yaw": 0.0, "tilt": 0.0})
	taken.append([fire, 3.6])

	# Six to eight lean-tos on a ring, each tilted: goblins do not build level.
	var count := 6 + (rng.randi() % 3)
	for i in count:
		var ang := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(count)
		var dist := RADIUS * rng.randf_range(0.42, 0.62)
		var at := Vector2(cos(ang), sin(ang)) * dist
		var w := rng.randf_range(4.2, 6.0)
		var h := rng.randf_range(3.4, 5.2)
		if not KitParts.clear_of(at, w * 0.6, taken):
			continue
		taken.append([at, w * 0.6])
		var tilt := deg_to_rad(rng.randf_range(-7.0, 7.0))
		parts.append({"part": "box", "role": "wood", "shade": rng.randi() % 3,
			"pos": Vector3(at.x, h * 0.45, at.y), "size": Vector3(w, h * 0.9, w * 0.9),
			"yaw": ang, "tilt": tilt})
		parts.append({"part": "lean", "role": "hide", "shade": rng.randi() % 3,
			"pos": Vector3(at.x, h * 0.9 + h * 0.28, at.y),
			"size": Vector3(w * 1.2, h * 0.56, w * 1.1), "yaw": ang, "tilt": tilt})

	# The stockade: sharpened stakes, uneven, with a gap you could be dragged
	# through. Posts taper (KitParts "post" narrows toward the top), so the
	# ring reads as sharpened rather than as a fence.
	var n := 26
	var gate := rng.randi() % n
	for i in n:
		if i == gate or i == (gate + 1) % n:
			continue
		var a := TAU * float(i) / float(n)
		var at := Vector2(cos(a), sin(a)) * RADIUS * 0.94
		var ph := rng.randf_range(5.0, 8.5)
		parts.append({"part": "post", "role": "wood", "shade": i % 3,
			"pos": Vector3(at.x, ph * 0.5, at.y), "size": Vector3(1.5, ph, 1.5),
			"yaw": a, "tilt": deg_to_rad(rng.randf_range(-9.0, 9.0))})

	# Trophy skulls on two of the stakes. Four triangles of storytelling.
	for i in 2:
		var a := TAU * rng.randf()
		var at := Vector2(cos(a), sin(a)) * RADIUS * 0.94
		parts.append({"part": "rock", "role": "bone", "shade": 2,
			"pos": Vector3(at.x, 8.8, at.y), "size": Vector3(1.6, 1.6, 1.6),
			"yaw": 0.0, "tilt": 0.0})


# A giant's hold: three or four megaliths and one crude shelter, all oversized
# and all sparse. The whole character is scale contrast — a giant's camp should
# look like a human camp built by something that got the measurements wrong.
static func _hold(parts: Array, rng: RandomNumberGenerator) -> void:
	# The shelter: two upright slabs and a lintel across them, a dolmen big
	# enough to sleep under. This is the tallest thing and the landmark.
	var span := 9.0
	var post_h := HEIGHT * 0.62
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		parts.append({"part": "box", "role": "stone", "shade": 1,
			"pos": Vector3(side * span * 0.5, post_h * 0.5, 0),
			"size": Vector3(5.2, post_h, 6.4), "yaw": 0.0,
			"tilt": deg_to_rad(side * rng.randf_range(1.0, 3.5))})
	parts.append({"part": "box", "role": "stone", "shade": 2,
		"pos": Vector3(0, post_h + 2.6, 0), "size": Vector3(span + 7.0, 5.2, 7.6),
		"yaw": 0.0, "tilt": deg_to_rad(rng.randf_range(-2.0, 2.0))})
	# A hide stretched over the top — the one soft thing, and the only clue
	# somebody lives here rather than it being a ruin.
	parts.append({"part": "lean", "role": "wood", "shade": 1,
		"pos": Vector3(0, post_h + 4.8, 0), "size": Vector3(span + 4.0, 2.4, 6.0),
		"yaw": 0.0, "tilt": 0.0})

	# Standing stones round the edge, leaning at different angles.
	var count := 4 + (rng.randi() % 2)
	for i in count:
		var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(count) + 0.6
		var at := Vector2(cos(a), sin(a)) * RADIUS * rng.randf_range(0.66, 0.88)
		var h := rng.randf_range(HEIGHT * 0.30, HEIGHT * 0.52)
		parts.append({"part": "box", "role": "stone", "shade": rng.randi() % 3,
			"pos": Vector3(at.x, h * 0.5, at.y), "size": Vector3(2.8, h, 2.2),
			"yaw": a, "tilt": deg_to_rad(rng.randf_range(-13.0, 13.0))})

	# Boulders and a mossy one, low and wide, to fill the ground between.
	for i in 7:
		var a := TAU * rng.randf()
		var at := Vector2(cos(a), sin(a)) * RADIUS * rng.randf_range(0.30, 0.92)
		var d := rng.randf_range(4.2, 7.4)
		parts.append({"part": "rock", "role": "moss" if i == 0 else "dark",
			"shade": rng.randi() % 3,
			"pos": Vector3(at.x, d * 0.28, at.y), "size": Vector3(d, d * 0.7, d),
			"yaw": a, "tilt": 0.0})

	# A gnawed bone pile, because a giant's hold with no leavings is a rockery.
	parts.append({"part": "rock", "role": "bone", "shade": 2,
		"pos": Vector3(RADIUS * 0.34, 1.0, RADIUS * 0.40),
		"size": Vector3(3.4, 1.8, 3.0), "yaw": 0.6, "tilt": 0.0})


# A dragon's cave: a rock mound with a black mouth in it, scorched ground, and
# enough gold spilling out to be worth the walk. The mouth is the whole read —
# it has to be a hole, not a dark patch, so it is a box sunk INTO the mound
# rather than painted on the front of it.
static func _cave(parts: Array, rng: RandomNumberGenerator) -> void:
	# The mound: three overlapping rocks rather than one, so the skyline has
	# more than a single arc in it.
	parts.append({"part": "rock", "role": "stone", "shade": 1,
		"pos": Vector3(0, HEIGHT * 0.30, -1.5),
		"size": Vector3(RADIUS * 1.5, HEIGHT * 1.36, RADIUS * 1.25),
		"yaw": 0.4, "tilt": 0.0})
	parts.append({"part": "rock", "role": "stone", "shade": 0,
		"pos": Vector3(-RADIUS * 0.42, HEIGHT * 0.20, RADIUS * 0.10),
		"size": Vector3(RADIUS * 0.82, HEIGHT * 0.80, RADIUS * 0.72),
		"yaw": 1.1, "tilt": 0.0})
	parts.append({"part": "rock", "role": "stone", "shade": 2,
		"pos": Vector3(RADIUS * 0.46, HEIGHT * 0.17, -RADIUS * 0.06),
		"size": Vector3(RADIUS * 0.74, HEIGHT * 0.68, RADIUS * 0.66),
		"yaw": 2.2, "tilt": 0.0})

	# The mouth, on the camera-facing side (+Z under the map's fixed pitch).
	parts.append({"part": "box", "role": "dark", "shade": 1,
		"pos": Vector3(0, 4.1, RADIUS * 0.50), "size": Vector3(7.4, 8.2, 6.0),
		"yaw": 0.0, "tilt": 0.0})
	parts.append({"part": "prism", "role": "dark", "shade": 1,
		"pos": Vector3(0, 9.6, RADIUS * 0.50), "size": Vector3(7.4, 3.0, 6.0),
		"yaw": 0.0, "tilt": 0.0})

	# Scorched ground fanning out of it, and the hoard at the lip.
	parts.append({"part": "disc", "role": "scorch", "shade": 0,
		"pos": Vector3(0, 0.75, RADIUS * 0.78), "size": Vector3(15.0, 0.5, 15.0),
		"yaw": 0.0, "tilt": 0.0})
	for i in 3:
		var at := Vector2(rng.randf_range(-3.6, 3.6), RADIUS * rng.randf_range(0.62, 0.86))
		parts.append({"part": "rock", "role": "gold", "shade": 2,
			"pos": Vector3(at.x, 1.2, at.y), "size": Vector3(rng.randf_range(2.2, 3.8),
				1.6, rng.randf_range(2.2, 3.4)), "yaw": rng.randf() * TAU, "tilt": 0.0})

	# Ribs in the scorch. A dragon's doorstep should be littered.
	for i in 3:
		var a := rng.randf() * TAU
		var at := Vector2(cos(a), sin(a)) * RADIUS * rng.randf_range(0.55, 0.95)
		parts.append({"part": "box", "role": "bone", "shade": 2,
			"pos": Vector3(at.x, 0.9, at.y), "size": Vector3(rng.randf_range(3.0, 5.0),
				0.7, 0.7), "yaw": a + 1.2, "tilt": 0.0})


# Sunken ruins: one arch still standing in black water, with the stumps of the
# rest around it. The first pass was a full two-row colonnade of tall thin
# columns, and at 41px that reads as scaffolding — too many verticals of similar
# height, none of them joined to anything. One joined arch plus low broken
# stumps says "this was a building and it fell" in far fewer parts.
static func _ruins(parts: Array, rng: RandomNumberGenerator) -> void:
	# The water, wider than the stonework and sitting just above the apron.
	parts.append({"part": "disc", "role": "water", "shade": 0,
		"pos": Vector3(0, 0.95, 0), "size": Vector3(RADIUS * 1.76, 0.7, RADIUS * 1.76),
		"yaw": 0.0, "tilt": 0.0})

	# The arch: two fat columns and the lintel they still carry. Angled off the
	# map's axes so it does not sit square to the screen.
	var yaw := rng.randf_range(-0.5, 0.5)
	var along := Vector2(cos(yaw), sin(yaw))
	var col_h := HEIGHT * 0.66
	var span := 9.0
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		var at: Vector2 = along * side * span * 0.5
		parts.append({"part": "box", "role": "stone", "shade": 1,
			"pos": Vector3(at.x, col_h * 0.5 + 0.9, at.y), "size": Vector3(4.0, col_h, 4.0),
			"yaw": yaw, "tilt": deg_to_rad(side * rng.randf_range(0.5, 2.5))})
	parts.append({"part": "box", "role": "stone", "shade": 2,
		"pos": Vector3(0, col_h + HEIGHT * 0.11, 0),
		"size": Vector3(span + 5.0, HEIGHT * 0.19, 4.6), "yaw": yaw, "tilt": 0.0})

	# Broken stumps of the rest of the colonnade, all short and all different:
	# a ruin reads as a ruin because the tops do not line up.
	var stumps := [0.40, 0.17, 0.30, 0.11, 0.23, 0.34, 0.14]
	var taken: Array = [[Vector2.ZERO, span * 0.5 + 3.0]]
	for i in stumps.size():
		var a := TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(stumps.size()) + yaw
		var at: Vector2 = Vector2(cos(a), sin(a)) * RADIUS * rng.randf_range(0.48, 0.84)
		if not KitParts.clear_of(at, 3.0, taken):
			continue
		taken.append([at, 3.0])
		var h: float = HEIGHT * float(stumps[i])
		parts.append({"part": "post", "role": "stone", "shade": i % 3,
			"pos": Vector3(at.x, h * 0.5 + 0.9, at.y), "size": Vector3(3.4, h, 3.4),
			"yaw": a, "tilt": deg_to_rad(rng.randf_range(-7.0, 7.0))})

	# Fallen blocks and weed in the shallows, some of them the lintels that came
	# down — long, flat and lying at angles no mason would have left them at.
	for i in 7:
		var a := rng.randf() * TAU
		var at := Vector2(cos(a), sin(a)) * RADIUS * rng.randf_range(0.42, 1.0)
		var long := i % 3 == 0
		parts.append({"part": "box", "role": "moss" if i % 4 == 0 else "dark",
			"shade": rng.randi() % 3,
			"pos": Vector3(at.x, 1.4, at.y),
			"size": Vector3(rng.randf_range(6.0, 9.0) if long else rng.randf_range(2.4, 3.8),
				1.5, rng.randf_range(2.2, 3.2)),
			"yaw": a + rng.randf_range(-1.0, 1.0),
			"tilt": deg_to_rad(rng.randf_range(-9.0, 9.0))})


# A zombie graveyard: tilted headstones, a mausoleum, a dead tree, iron railings.
# The tilt is the point — a graveyard of upright stones reads as a car park, and
# the same stones leaning at ten different angles read as ground that has been
# pushed up from underneath.
static func _graveyard(parts: Array, rng: RandomNumberGenerator) -> void:
	# The mausoleum: the landmark, off centre so the yard is not symmetrical.
	var mx := -RADIUS * 0.30
	var mz := -RADIUS * 0.22
	var body := HEIGHT * 0.50
	parts.append({"part": "box", "role": "stone", "shade": 1,
		"pos": Vector3(mx, body * 0.5, mz), "size": Vector3(8.4, body, 7.2),
		"yaw": 0.35, "tilt": 0.0})
	parts.append({"part": "prism", "role": "dark", "shade": 1,
		"pos": Vector3(mx, body + HEIGHT * 0.11, mz),
		"size": Vector3(9.4, HEIGHT * 0.22, 8.0), "yaw": 0.35, "tilt": 0.0})
	# Its doorway, and a cross on the gable.
	parts.append({"part": "box", "role": "dark", "shade": 0,
		"pos": Vector3(mx + 1.0, body * 0.35, mz + 3.4), "size": Vector3(2.8, body * 0.7, 1.6),
		"yaw": 0.35, "tilt": 0.0})
	parts.append({"part": "box", "role": "stone", "shade": 2,
		"pos": Vector3(mx, HEIGHT * 0.78, mz), "size": Vector3(0.7, HEIGHT * 0.20, 0.7),
		"yaw": 0.35, "tilt": 0.0})
	parts.append({"part": "box", "role": "stone", "shade": 2,
		"pos": Vector3(mx, HEIGHT * 0.82, mz), "size": Vector3(3.0, 0.7, 0.7),
		"yaw": 0.35, "tilt": 0.0})

	# The dead tree: a leaning trunk and three bare limbs. The tallest thing
	# here, and the one irregular shape among all the rectangles.
	var tx := RADIUS * 0.46
	var tz := RADIUS * 0.10
	parts.append({"part": "post", "role": "wood", "shade": 0,
		"pos": Vector3(tx, HEIGHT * 0.34, tz), "size": Vector3(2.4, HEIGHT * 0.68, 2.4),
		"yaw": 0.0, "tilt": deg_to_rad(7.0)})
	var limbs := [[0.5, 0.58, 0.30, 52.0], [2.6, 0.66, 0.22, 34.0], [4.3, 0.72, 0.26, 61.0]]
	for limb in limbs:
		var a: float = limb[0]
		parts.append({"part": "post", "role": "wood", "shade": 1,
			"pos": Vector3(tx + cos(a) * 2.4, HEIGHT * float(limb[1]), tz + sin(a) * 2.4),
			"size": Vector3(1.1, HEIGHT * float(limb[2]), 1.1),
			"yaw": a, "tilt": deg_to_rad(float(limb[3]))})

	# The graves themselves: headstones on rough rows, every one at its own
	# angle, a few with a low mound in front.
	var taken: Array = [[Vector2(mx, mz), 7.0], [Vector2(tx, tz), 4.0]]
	var count := 11 + (rng.randi() % 4)
	var placed := 0
	for i in count:
		var at := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * RADIUS * 0.88
		if at.length() > RADIUS * 0.88 or not KitParts.clear_of(at, 2.6, taken):
			continue
		taken.append([at, 2.6])
		placed += 1
		var h := rng.randf_range(HEIGHT * 0.14, HEIGHT * 0.26)
		var w := rng.randf_range(1.8, 2.8)
		var yaw := rng.randf_range(-0.4, 0.4)
		var tilt := deg_to_rad(rng.randf_range(-16.0, 16.0))
		parts.append({"part": "box", "role": "stone", "shade": rng.randi() % 3,
			"pos": Vector3(at.x, h * 0.5, at.y), "size": Vector3(w, h, 0.7),
			"yaw": yaw, "tilt": tilt})
		# Every third one is a rounded stone rather than a slab, so the rows are
		# not a picket of identical rectangles.
		if placed % 3 == 0:
			parts.append({"part": "cone", "role": "stone", "shade": 2,
				"pos": Vector3(at.x, h + 0.5, at.y), "size": Vector3(w, 1.4, 0.7),
				"yaw": yaw, "tilt": tilt})
		if placed % 4 == 0:
			parts.append({"part": "rock", "role": "ground", "shade": 0,
				"pos": Vector3(at.x, 0.5, at.y + 1.8), "size": Vector3(w * 1.5, 1.4, 3.0),
				"yaw": yaw, "tilt": 0.0})

	# Iron railings, with the gate hanging open.
	var n := 24
	var gate := rng.randi() % n
	for i in n:
		if i == gate or i == (gate + 1) % n:
			continue
		var a := TAU * float(i) / float(n)
		var at := Vector2(cos(a), sin(a)) * RADIUS * 0.97
		parts.append({"part": "box", "role": "iron", "shade": i % 3,
			"pos": Vector3(at.x, 2.1, at.y), "size": Vector3(0.45, 4.2, 0.45),
			"yaw": a, "tilt": deg_to_rad(rng.randf_range(-5.0, 5.0))})
