# Settlement dioramas ASSEMBLED from modules, instead of generated as one mesh.
#
# WHY THIS EXISTS. The tier-0 dioramas in assets/settlements/ ARRIVED as Meshy
# text-to-3D output put through a remesh: each a single fused 82k-triangle blob
# whose 2048 atlas carried 3.3k-5.3k UV islands averaging ~25px. A settlement is
# drawn 29px (camp), 48px (town) or 83px (city) tall at zoom 1 — ISO_GAIN is
# 1.85 and Settlements3D.TARGET_HEIGHT is 15.6/25.7/45 world units — so that
# atlas was sampled around mip 5, where every island collapses below a texel and
# the whole model averages to the one muddy brown the atlas is made of.
#
# So this builds the opposite thing: ~15-triangle primitives (box bodies, prism
# and cone roofs, posts) placed by a seeded layout, sharing a handful of flat
# untextured materials. A city comes out around 2k triangles, with a crisp
# silhouette at the size it is actually drawn, and — because the layout is
# seeded on the settlement's own id — every town is a different town, which the
# twelve fixed models never were.
#
# WHAT CHANGED UNDER IT SINCE. Those twelve models were rebuilt low-poly
# (tools/lowpoly_glb.py): welded, smoothed, decimated 82k -> 4k, faceted, with
# the atlas baked into vertex colour and thrown away. That fixed the mud — the
# mip chain it averaged to is gone, and flat facets give the hard edges
# reconstruction never had — so `Settlements3D.source` now defaults to them,
# and this kit is no longer a candidate to replace them. It stays because it is
# still the only source that draws a DIFFERENT town per settlement id, and the
# only one that covers a (faction, kind) the twelve files do not.
#
# TWO HALVES, DELIBERATELY SPLIT. `plan()` is pure data: an Array of part
# dictionaries in world units, no Node, no Mesh, no SceneTree. That is what
# tests/test_settlement_kit.gd asserts on (determinism, footprint, budget) and
# what a future MultiMesh batcher or a real CC0 module kit would consume
# instead. `build()` is the only half that touches Godot resources.
#
# WHAT THIS DOES NOT OWN, same contract as settlements3d.gd's own header: the
# shadow ellipse, the footprint ring and the name label that
# World._draw_settlement() draws underneath. The one exception is the ground
# apron from KitParts.apron(), which has its reasons written where it is built.
extends RefCounted

const KitParts = preload("res://scenes/world/kit_parts.gd")

# Per-kind geometry, in World units (World._pix multiplies by ISO_GAIN * zoom).
#
# `height` is the tallest point and deliberately matches the existing
# Settlements3D.TARGET_HEIGHT, so a kit diorama has the same on-screen presence
# as the GLB it replaces and the two are honestly comparable in the gallery.
#
# `radius` is NOT inherited from the GLBs. Those are ~1.9 wide per 1.0 tall, so
# fitting one to 45 units tall makes it 88 units across against a footprint ring
# of 2 * 26/ISO_GAIN = 28 — the diorama overhangs its own marker by 3x. Here the
# footprint is 2x the ring instead: a settlement still spills past the ring it is
# pinned to (towns are bigger than their map dot), but it stays recognisably the
# thing the ring is drawn around.
#
# `house_cap` is the fraction of `height` an ordinary building may reach, roof
# included. Without it the landmark stops being the tallest thing: elf roofs are
# 0.9 of their body height, so a tall-rolled elf house plus its spire overtopped
# the camp's own centrepiece and the silhouette lost its peak.
#
# `dress` is how many pieces of set dressing go in beside the houses — wells,
# stalls, carts, woodpiles, the things in DRESSING below. A camp gets few
# because a camp IS its dressing (a fire and three tents); a city gets the most
# because the gaps between its houses are otherwise bare apron.
const PLANS := {
	"camp": {"height": 15.6, "radius": 12.0, "houses": [3, 5], "house_h": 6.6,
		"house_w": 5.2, "house_cap": 0.72, "wall": "", "dwelling": "tent", "dress": 3},
	"town": {"height": 25.7, "radius": 18.0, "houses": [6, 9], "house_h": 10.5,
		"house_w": 6.4, "house_cap": 0.62, "wall": "palisade", "dwelling": "house", "dress": 5},
	"city": {"height": 45.0, "radius": 28.0, "houses": [12, 16], "house_h": 13.0,
		"house_w": 7.6, "house_cap": 0.55, "wall": "stone", "dwelling": "house", "dress": 8},
}

# Per-faction look. Colours are the whole faction read at 48px — at that size a
# player resolves palette and silhouette and literally nothing else, which is
# the other half of why twelve brown blobs were indistinguishable.
#
#   wall/roof   the two colours that carry a faction at 48px. They need real
#               value contrast between them, not just different hues: orc's
#               first pass was brown-on-brown and read as one smudge.
#   post        palisade stakes and wall timbers. Its own entry because using
#               the accent colour here turned the orc palisade into a ring of
#               red toothpicks.
#   ground      the dirt apron the settlement stands on — KitParts.apron().
#   roof        prism = gabled, cone = spire, lean = single-pitch (asymmetric
#               PrismMesh, the crooked orc shed)
#   pitch       roof height as a fraction of the body's, so dwarf reads squat
#               and elf reads steep from the silhouette alone
#   slender     body width multiplier: elf tall and narrow, dwarf broad and low
#   lean_deg    per-building random tilt, orc only — nothing else is crooked
#
# WHERE THE COLOURS COME FROM. Read off the game's own painted art with
# tools/palette_from_art.py rather than picked by eye — specifically
# `--ring assets/generated/<faction>-*.png`, which drops the middle of each
# counter portrait and counts only the border. That border is the room behind
# the shopkeeper: stone, timber, roof beams, forge light. It is the only
# painted architecture each faction has, and it is exactly the right subject.
#
# What is taken from the sample is the HUE, not the average. Those interiors
# quantise to a stack of near-blacks and browns (the orc counters average
# #362922), and transplanting that wholesale would rebuild the brown blob at
# the top of this file. Value and saturation stay the deliberate thing they
# were: wall well above roof, and both far enough apart to survive a 48px
# silhouette.
#
#   ember       firelight — the cook fire, the forge mouth, the bonfire. Its
#               own role because every faction's is the same warm orange with
#               a different amount of its own hue in it, and because `trim` is
#               already spoken for by banners and gilding.
#   camp_dwelling  what this faction sleeps under away from home: "tent" for
#               everyone but the dwarves, who cut a stone hut into the hill the
#               moment they stop walking.
const PROFILES := {
	"human": {
		"wall": Color("e6cfa8"), "roof": Color("a5563a"), "trim": Color("6a5239"),
		"stone": Color("9c917c"), "post": Color("6d553d"), "ground": Color("6c563a"),
		"ember": Color("e08a33"), "camp_dwelling": "tent",
		"roof_kind": "prism", "pitch": 0.62,
		"slender": 1.0, "squat": 1.0, "lean_deg": 0.0,
	},
	"elf": {
		"wall": Color("e8e1c4"), "roof": Color("35705c"), "trim": Color("ccae5c"),
		"stone": Color("97a293"), "post": Color("85805e"), "ground": Color("566447"),
		"ember": Color("d9a63f"), "camp_dwelling": "tent",
		"roof_kind": "cone", "pitch": 0.72,
		"slender": 0.82, "squat": 1.12, "lean_deg": 0.0,
	},
	"dwarf": {
		"wall": Color("c2a98b"), "roof": Color("332d28"), "trim": Color("cf8024"),
		"stone": Color("8b7f71"), "post": Color("6a6055"), "ground": Color("6a583f"),
		"ember": Color("f0861c"), "camp_dwelling": "hut",
		"roof_kind": "prism", "pitch": 0.34,
		"slender": 1.32, "squat": 0.74, "lean_deg": 0.0,
	},
	"orc": {
		"wall": Color("a68f62"), "roof": Color("4d3b29"), "trim": Color("b03e28"),
		"stone": Color("665a46"), "post": Color("493e2f"), "ground": Color("575039"),
		"ember": Color("e2622a"), "camp_dwelling": "tent",
		"roof_kind": "lean", "pitch": 0.5,
		"slender": 1.1, "squat": 0.86, "lean_deg": 5.5,
	},
}

# THE KITBASH SET, and the half that turns twelve geometries into twelve
# places. Every name here is a `_dress_*` builder below, assembled out of the
# same seven primitives the houses are: a well is a disc, two posts and a
# lintel; a cart is a box and two cylinders lying on their sides. None of it is
# a new mesh and none of it is a texture.
#
# What a faction stands between its houses is most of what it says about
# itself once the palette has said the rest — a human town has a well and
# market stalls, a dwarf town has ore carts and a mine head, an orc camp has a
# totem and a trophy stake. The list is CYCLED to fill PLANS.dress, so the
# order is the priority: whatever a settlement of that size only has room for
# once should come first.
const DRESSING := {
	"human": {
		"camp": ["fire", "cart", "woodpile"],
		"town": ["well", "stall", "cart", "haystack", "woodpile"],
		"city": ["well", "stall", "stall", "cart", "haystack", "woodpile"],
	},
	"elf": {
		"camp": ["fire", "stone", "tree"],
		"town": ["stone", "tree", "well", "tree", "stall"],
		"city": ["stone", "tree", "well", "tree", "stall", "tree"],
	},
	"dwarf": {
		"camp": ["fire", "minehead", "orecart"],
		"town": ["minehead", "orecart", "woodpile", "well", "orecart"],
		"city": ["minehead", "orecart", "well", "orecart", "woodpile", "stall"],
	},
	"orc": {
		"camp": ["fire", "totem", "trophy"],
		"town": ["totem", "trophy", "fire", "woodpile", "trophy"],
		"city": ["totem", "fire", "trophy", "trophy", "woodpile", "totem"],
	},
}

# What an ordinary HOUSE is allowed to grow, per faction, and how likely each
# is. A box under a prism is a house; a box under a prism with a lean-to on its
# inward side, a jetty over the street and a dark doorway is a BUILDING, and
# that difference is the whole of "it looks too primitive" at close range. Each
# of these is two or three more primitives on a part that is already there, so
# a city pays a few hundred triangles for it, not thousands.
#
#   jetty    an overhanging upper storey, medieval-town style
#   annex    a lean-to shed against the inward wall
#   porch    a covered doorway on two short posts
#   dormer   a window box pushed through the roof slope
#   door     a dark panel on the facade — pure silhouette-noise at 48px, and
#            the cheapest "this thing has a front" there is
#   ridge    a beam along the roof's spine, which catches the sun on its own
const HOUSE_DETAILS := {
	"human": [["door", 0.9], ["ridge", 0.7], ["jetty", 0.45], ["annex", 0.4], ["dormer", 0.35]],
	"elf": [["door", 0.9], ["porch", 0.5], ["ridge", 0.3], ["dormer", 0.2]],
	"dwarf": [["door", 0.9], ["ridge", 0.8], ["annex", 0.55], ["porch", 0.3]],
	"orc": [["door", 0.85], ["annex", 0.6], ["ridge", 0.5], ["jetty", 0.3]],
}

# Where dressing goes, as fractions of the footprint radius. RING_BANDS puts
# houses at 0.44-0.52 and 0.72-0.88, so these are the two gaps: the clearing
# around the landmark, and the lane between the two rings. Alternating between
# them is what keeps a well from ending up in the same place in every town.
const DRESS_BANDS := [[0.22, 0.38], [0.56, 0.68]]

# Rejection sampling for building placement: give up after this many tries and
# take the last position. Bounded so plan() can never hang.
#
# 40 rather than the 24 it was built with: the kitbash set puts a well or a
# totem in the gaps the houses left, so a house that gets pushed out of its
# slot now has fewer places to land, and a bound that used to be generous was
# leaving one city in two hundred with three houses inside each other. plan()
# is called once per settlement per load and the try is a few distance tests.
const PLACE_TRIES := 40

# Buildings go on two concentric rings rather than anywhere on the disc, as
# fractions of the footprint radius. Free scatter on a disc clumps — and a clump
# at 48px is one smudge, which is the problem this file is here to solve. Two
# rings also give the thing a shape: a dense core inside an outer ring, with the
# landmark in the middle of the core.
const RING_BANDS := [[0.44, 0.52], [0.72, 0.88]]

# How much of a building's own width counts as its personal space, for the
# placement test. Under 1.0 on purpose — village houses share walls, and a gap
# wide enough to drive a cart through at every house reads as a car park.
const CLEARANCE := 0.62

static func has(faction: String, kind: String) -> bool:
	return PROFILES.has(faction) and PLANS.has(kind)


# --- the layout, as pure data ----------------------------------------------

# One settlement's parts, in world units, y=0 on the ground. Deterministic in
# `id` alone: the same settlement is the same village every load, across saves
# and across machines, which is the property that lets this replace a fixed
# per-(faction, kind) model without the map flickering between sessions.
#
# RandomNumberGenerator rather than core/rng.gd deliberately — this is cosmetic
# view-layer scatter that needs floats and normals, not a game roll anybody
# could ever want to reproduce from a save. Nothing here feeds the simulation.
static func plan(faction: String, kind: String, id: String) -> Array:
	if not has(faction, kind):
		return []
	var p: Dictionary = PLANS[kind]
	var prof: Dictionary = PROFILES[faction]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%s/%s" % [faction, kind, id])

	var parts: Array = []
	var radius: float = p["radius"]
	var taken: Array = []            # [Vector2 centre, float clearance]

	# The landmark first and at the centre, so the houses below place around it
	# rather than inside it — it is the one part whose position is not negotiable.
	_landmark(parts, faction, kind, rng)
	taken.append([Vector2.ZERO, float(p["height"]) * 0.18])

	# What this faction builds at this size. Everyone but the dwarves sleeps
	# under canvas at a camp; a dwarf camp is stone huts from the first night.
	var dwelling := String(p.get("dwelling", "house"))
	if dwelling == "tent" and String(prof.get("camp_dwelling", "tent")) != "tent":
		dwelling = "house"

	var lo: int = p["houses"][0]
	var hi: int = p["houses"][1]
	var count := lo + (rng.randi() % (hi - lo + 1))
	# A third of the buildings in the core, the rest on the outer ring. Each ring
	# spaces its own slots evenly, so the outer ring can't crowd the inner one.
	var inner: int = maxi(1, count / 3)
	var slots := [inner, count - inner]
	var phase := [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)]
	for i in count:
		var ring: int = 0 if i < inner else 1
		var slot: int = i if ring == 0 else i - inner
		var band: Array = RING_BANDS[ring]
		var w: float = float(p["house_w"]) * float(prof["slender"]) * rng.randf_range(0.85, 1.15)
		var h: float = float(p["house_h"]) * float(prof["squat"]) * rng.randf_range(0.8, 1.2)
		var d: float = w * rng.randf_range(0.95, 1.45)
		var clearance: float = maxf(w, d) * CLEARANCE
		# Two passes at a slot: full size, and then three-fifths of it. A town
		# that has run out of room should end up with a SMALL house squeezed
		# into the gap, which is what a real one does — the old single pass gave
		# up and placed the full-size house anyway, and that is a house standing
		# inside its neighbour. The kitbash set made this matter: a well or a
		# totem in the lane between the rings is one more thing a pushed-out
		# house has to dodge.
		var at := Vector2.ZERO
		var placed := false
		for attempt_pass in 2:
			if attempt_pass == 1:
				w *= 0.6
				h *= 0.6
				d *= 0.6
				clearance = maxf(w, d) * CLEARANCE
			for attempt in PLACE_TRIES:
				var ang: float = phase[ring] \
					+ TAU * (float(slot) + rng.randf_range(-0.12, 0.12)) / float(slots[ring])
				var dist: float = radius * rng.randf_range(band[0], band[1])
				at = Vector2(cos(ang) * dist, sin(ang) * dist)
				if KitParts.clear_of(at, clearance, taken):
					placed = true
					break
			if placed:
				break
		# A DEEP house on the OUTER ring is the one shape that can leave the
		# footprint: `d` runs to 1.45x `w`, the ring sits at 0.88R, and the roof
		# is 1.12x the body — roll all three high and the far gable ends up past
		# 1.35R, standing in the fog beside the town. Trim the depth to what the
		# ring it landed on has room for; nothing else here is clamped, because
		# nothing else can reach.
		d = minf(d, maxf(w, (radius * 1.28 - at.length()) * 2.0 / 1.12))
		taken.append([at, clearance])
		var yaw: float = rng.randf_range(-PI, PI)
		var shade: int = rng.randi() % KitParts.SHADES.size()
		if dwelling == "tent":
			_tent(parts, faction, at, w, h, d, yaw, shade, rng)
		else:
			var built: Vector3 = _house(parts, faction, at, w, h, d,
				float(p["height"]) * float(p["house_cap"]), yaw, shade, rng)
			# Everything a house grows goes on its INWARD side, towards the
			# centre: that is where the street is, it is the side the map's
			# fixed camera angle can see, and it is the one direction that
			# cannot push a part out through the footprint.
			_house_details(parts, faction, at, built, yaw, shade, rng)

	# The wall answers with where it left its gate, and the gateposts go there.
	# A gap in a ring reads as a gap; a gap with two posts and a lintel over it
	# reads as the way in, which is the difference between a fence and a town.
	match String(p["wall"]):
		"palisade":
			var gate_h: float = float(p["house_h"]) * 0.66
			_gatehouse(parts, faction, _palisade(parts, faction, radius * 1.02, gate_h, rng),
				radius * 1.02, gate_h)
		"stone":
			var wall_h: float = float(p["house_h"]) * 0.62
			_gatehouse(parts, faction, _stone_wall(parts, faction, radius * 1.02, wall_h, rng),
				radius * 1.02, wall_h * 1.15)
	_dress(parts, faction, kind, radius, taken, rng)
	KitParts.apron(parts, "ground", radius * 1.03)
	return parts


# A body plus its roof, and for the factions that have one, a chimney. The roof
# is 12% wider than the body in both directions: that overhang is what puts a
# dark edge line under every roof, and it is most of what makes these read as
# buildings rather than as coloured boxes once they are 10px tall.
static func _house(parts: Array, faction: String, at: Vector2, w: float, h: float,
		d: float, cap: float, yaw: float, shade: int, rng: RandomNumberGenerator) -> Vector3:
	var prof: Dictionary = PROFILES[faction]
	var tilt: float = deg_to_rad(rng.randf_range(-1.0, 1.0) * float(prof["lean_deg"]))
	# Body and roof shrink together against the cap, so a capped building is a
	# smaller house and not a house with a squashed roof.
	var full: float = h * (1.0 + float(prof["pitch"]))
	if full > cap:
		var k: float = cap / full
		h *= k
		w *= k
		d *= k
	parts.append({
		"part": "box", "role": "wall", "shade": shade, "tag": "dwelling",
		"pos": Vector3(at.x, h * 0.5, at.y), "size": Vector3(w, h, d),
		"yaw": yaw, "tilt": tilt,
	})
	var roof_h: float = h * float(prof["pitch"])
	var kind := String(prof["roof_kind"])
	parts.append({
		"part": "cone" if kind == "cone" else ("lean" if kind == "lean" else "prism"),
		"role": "roof", "shade": shade,
		"pos": Vector3(at.x, h + roof_h * 0.5, at.y),
		"size": Vector3(w * 1.12, roof_h, d * 1.12), "yaw": yaw, "tilt": tilt,
	})
	# A chimney is four triangles that turn a shed into a house. Not on elf
	# (their roofs are cones, there is nowhere to put one) and not on every
	# building, so the row keeps some variation.
	if kind != "cone" and rng.randf() < 0.55:
		var cw: float = w * 0.16
		parts.append({
			"part": "box", "role": "stone", "shade": shade,
			"pos": Vector3(at.x, h + roof_h * 0.85, at.y),
			"size": Vector3(cw, roof_h * 1.1, cw), "yaw": yaw, "tilt": tilt,
		})
	# The size it was ACTUALLY built at, cap and all — _house_details() hangs
	# things off this body and has to agree with it about how big it is.
	return Vector3(w, h, d)


# What turns a box under a prism into a building. Everything here is optional
# (HOUSE_DETAILS gives each faction its own vocabulary and odds) and everything
# hangs off ONE face of the body: the one looking most towards the middle of the
# settlement, which is where the street is and which the map camera can see.
#
# The face has to be found rather than assumed, because a house's yaw is random:
# the four candidates are the body's own +/-front and +/-right in world XZ, and
# the winner is whichever points most directly at the centre. `face_yaw` then
# turns a part so its local +Z lies along that normal, which is what lets a door
# be a flat panel IN the wall instead of a slab crossing it at an angle.
static func _house_details(parts: Array, faction: String, at: Vector2, body: Vector3,
		yaw: float, shade: int, rng: RandomNumberGenerator) -> void:
	var prof: Dictionary = PROFILES[faction]
	var w: float = body.x
	var h: float = body.y
	var d: float = body.z
	var roof_h: float = h * float(prof["pitch"])
	var gabled: bool = String(prof["roof_kind"]) != "cone"
	var inward: Vector2 = (-at).normalized() if at.length() > 0.001 else Vector2.RIGHT
	var front := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var faces := [[front, d], [-front, d], [right, w], [-right, w]]
	var best: Array = faces[0]
	for face in faces:
		if (face[0] as Vector2).dot(inward) > (best[0] as Vector2).dot(inward):
			best = face
	var n: Vector2 = best[0]
	var out: float = float(best[1]) * 0.5          # half-depth through that face
	var across: float = w if is_equal_approx(float(best[1]), d) else d
	var face_yaw: float = atan2(n.x, n.y)
	var t: float = minf(w, d)

	for entry in HOUSE_DETAILS.get(faction, []):
		if rng.randf() > float(entry[1]):
			continue
		match String(entry[0]):
			"door":
				# `post` and not `trim`: trim is the faction's ACCENT (a dwarf's
				# is forge orange), and a row of accent-coloured doors and ridge
				# beams lights a town up like a fairground. Timber is timber.
				_part(parts, "box", "post", 0,
					Vector3(at.x + n.x * out, h * 0.26, at.y + n.y * out),
					Vector3(across * 0.3, h * 0.52, t * 0.07), face_yaw)
			"ridge":
				if gabled:
					_part(parts, "box", "post", 0,
						Vector3(at.x, h + roof_h * 0.9, at.y),
						Vector3(w * 0.09, roof_h * 0.16, d * 1.06), yaw)
			"jetty":
				_part(parts, "box", "wall", (shade + 1) % KitParts.SHADES.size(),
					Vector3(at.x, h * 0.8, at.y),
					Vector3(w * 1.1, h * 0.3, d * 1.1), yaw)
			"annex":
				var aw: float = t * 0.52
				var ah: float = h * 0.44
				_part(parts, "box", "wall", (shade + 2) % KitParts.SHADES.size(),
					Vector3(at.x + n.x * (out + aw * 0.42), ah * 0.5,
						at.y + n.y * (out + aw * 0.42)),
					Vector3(across * 0.5, ah, aw * 0.84), face_yaw)
				_part(parts, "lean", "roof", 1,
					Vector3(at.x + n.x * (out + aw * 0.42), ah + ah * 0.13,
						at.y + n.y * (out + aw * 0.42)),
					Vector3(across * 0.56, ah * 0.26, aw * 0.94), face_yaw)
			"porch":
				var pd: float = t * 0.34
				var ph: float = h * 0.5
				for side: float in [-1.0, 1.0]:
					var a := Vector2(n.y, -n.x) * across * 0.16 * side
					_part(parts, "box", "post", 1,
						Vector3(at.x + n.x * (out + pd * 0.8) + a.x, ph * 0.5,
							at.y + n.y * (out + pd * 0.8) + a.y),
						Vector3(t * 0.07, ph, t * 0.07), face_yaw)
				_part(parts, "box", "roof", 2,
					Vector3(at.x + n.x * (out + pd * 0.45), ph + h * 0.04,
						at.y + n.y * (out + pd * 0.45)),
					Vector3(across * 0.42, h * 0.08, pd * 1.5), face_yaw, 0.12)
			"dormer":
				if gabled:
					var dw: float = across * 0.24
					_part(parts, "box", "wall", shade,
						Vector3(at.x + n.x * out * 0.55, h + roof_h * 0.34,
							at.y + n.y * out * 0.55),
						Vector3(dw, roof_h * 0.6, dw * 0.8), face_yaw)
					_part(parts, "prism", "roof", 2,
						Vector3(at.x + n.x * out * 0.55, h + roof_h * 0.72,
							at.y + n.y * out * 0.55),
						Vector3(dw * 1.2, roof_h * 0.26, dw), face_yaw)


# The one tall thing, at the centre: what the eye finds first and what tells the
# factions apart at a glance. Every landmark tops out at exactly PLANS.height,
# so a kit diorama occupies the vertical space the GLB it replaces did and
# swapping Settlements3D.source still cannot change how tall a settlement is.
#
# One landmark per faction, not one shape in four palettes — that was the old
# shape of this function, and it is why a dwarf town and an elf town read as the
# same town in different colours. A keep with a side tower, a tiered spire, a
# forge hall under a chimney and a longhouse under a totem are four silhouettes,
# and the silhouette is the half of the read that survives being drawn 48px tall.
static func _landmark(parts: Array, faction: String, kind: String,
		rng: RandomNumberGenerator) -> void:
	var p: Dictionary = PLANS[kind]
	var prof: Dictionary = PROFILES[faction]
	var top: float = p["height"]
	var w: float = float(p["radius"]) * 0.46 * float(prof["slender"])
	if kind == "camp":
		_landmark_mast(parts, prof, top, w, rng)
		return
	match faction:
		"elf": _landmark_spire(parts, prof, top, w, rng)
		"dwarf": _landmark_forge(parts, prof, top, w, rng)
		"orc": _landmark_hall(parts, prof, top, w, rng)
		_: _landmark_keep(parts, prof, top, w, rng)


# A camp has no keep, and giving it one was the old code's worst tell: three
# tents around a cathedral. What a camp of any faction plants first is a
# standard — a mast, a crossbar, the colours — so that is the tall thing here,
# with the fire and the totem/mine head coming from DRESSING instead.
static func _landmark_mast(parts: Array, prof: Dictionary, top: float, w: float,
		rng: RandomNumberGenerator) -> void:
	_part(parts, "post", "post", 1, Vector3(0, top * 0.5, 0),
		Vector3(w * 0.16, top, w * 0.16), rng.randf_range(0.0, TAU))
	_part(parts, "box", "trim", 2, Vector3(w * 0.26, top * 0.82, 0),
		Vector3(w * 0.5, top * 0.16, w * 0.05))
	# Two guys and a crate: the mast needs something at its foot or it reads as
	# a stick pushed into the apron.
	for side: float in [-1.0, 1.0]:
		_part(parts, "box", "post", 0,
			Vector3(w * 0.34 * side, top * 0.16, w * 0.30 * side),
			Vector3(w * 0.06, top * 0.32, w * 0.06), 0.0, 0.32 * side)
	_part(parts, "box", "wall", 1, Vector3(-w * 0.42, w * 0.12, w * 0.22),
		Vector3(w * 0.44, w * 0.24, w * 0.34), rng.randf_range(-PI, PI))


# Human: a keep. A square tower with a gabled roof, a lower tower welded to one
# side, and a banner on the mast — the side tower is the whole silhouette, since
# a single box under a prism is what an ordinary house already looks like.
static func _landmark_keep(parts: Array, prof: Dictionary, top: float, w: float,
		rng: RandomNumberGenerator) -> void:
	var mast: float = top * 0.12
	var solid: float = top - mast
	var roof_h: float = solid * 0.28
	var body: float = solid - roof_h
	_part(parts, "box", "stone", 2, Vector3(0, body * 0.5, 0), Vector3(w, body, w),
		rng.randf_range(-0.25, 0.25))
	_part(parts, "prism", "roof", 1, Vector3(0, body + roof_h * 0.5, 0),
		Vector3(w * 1.2, roof_h, w * 1.2))
	var side: float = body * 0.62
	var sw: float = w * 0.46
	_part(parts, "box", "stone", 1, Vector3(w * 0.62, side * 0.5, w * 0.18),
		Vector3(sw, side, sw))
	_part(parts, "prism", "roof", 2, Vector3(w * 0.62, side + sw * 0.28, w * 0.18),
		Vector3(sw * 1.2, sw * 0.56, sw * 1.2))
	_part(parts, "post", "post", 1, Vector3(0, solid + mast * 0.5, 0),
		Vector3(w * 0.10, mast, w * 0.10))
	_part(parts, "box", "trim", 2, Vector3(w * 0.26, solid + mast * 0.62, 0),
		Vector3(w * 0.42, mast * 0.5, w * 0.05))


# Elf: a tiered spire. Three stages, each narrower than the one below, with a
# gilt band at every join — the taper is what makes it elven at map size, far
# more than the teal is.
static func _landmark_spire(parts: Array, prof: Dictionary, top: float, w: float,
		rng: RandomNumberGenerator) -> void:
	var body: float = top * 0.56
	_part(parts, "box", "wall", 2, Vector3(0, body * 0.5, 0), Vector3(w * 0.74, body, w * 0.74),
		rng.randf_range(-0.25, 0.25))
	_part(parts, "box", "trim", 2, Vector3(0, body, 0), Vector3(w * 0.86, top * 0.02, w * 0.86))
	_part(parts, "cone", "roof", 1, Vector3(0, body + top * 0.08, 0),
		Vector3(w * 0.98, top * 0.16, w * 0.98))
	var neck: float = body + top * 0.16
	_part(parts, "box", "wall", 1, Vector3(0, neck + top * 0.06, 0),
		Vector3(w * 0.46, top * 0.12, w * 0.46))
	_part(parts, "box", "trim", 2, Vector3(0, neck + top * 0.12, 0),
		Vector3(w * 0.54, top * 0.02, w * 0.54))
	_part(parts, "cone", "roof", 2, Vector3(0, neck + top * 0.20, 0),
		Vector3(w * 0.58, top * 0.16, w * 0.58))


# Dwarf: a forge hall. Broad, low, and overtopped by its own chimney — the
# chimney is the tallest thing in a dwarf settlement, which is the joke and also
# the read: everything else here is squat by PROFILES.squat, so a single
# vertical is unmistakable.
static func _landmark_forge(parts: Array, prof: Dictionary, top: float, w: float,
		rng: RandomNumberGenerator) -> void:
	var hall: float = top * 0.52
	var roof_h: float = top * 0.18
	_part(parts, "box", "stone", 2, Vector3(0, hall * 0.5, 0), Vector3(w * 1.3, hall, w * 1.05),
		rng.randf_range(-0.2, 0.2))
	_part(parts, "prism", "roof", 1, Vector3(0, hall + roof_h * 0.5, 0),
		Vector3(w * 1.45, roof_h, w * 1.18))
	# The stack runs the full height FROM THE GROUND, not from the roof: a
	# chimney that starts at the ridge line reads as a box balanced on a house.
	# It is also half the hall's width — the first pass was a third of that and
	# came out a factory smokestack, a needle with nothing dwarven about it.
	_part(parts, "box", "stone", 0, Vector3(w * 0.46, top * 0.5, -w * 0.26),
		Vector3(w * 0.52, top, w * 0.5))
	_part(parts, "box", "stone", 1, Vector3(w * 0.46, top * 0.97, -w * 0.26),
		Vector3(w * 0.62, top * 0.06, w * 0.6))
	# The forge mouth: the one lit thing in the settlement.
	_part(parts, "box", "ember", 2, Vector3(0, hall * 0.28, w * 0.54),
		Vector3(w * 0.42, hall * 0.5, w * 0.06))


# Orc: a longhouse under a totem. The hall is wide and single-pitched like every
# other orc building, so the totem — a bare pole taller than anything else, hung
# with two banners — is what carries the centre.
static func _landmark_hall(parts: Array, prof: Dictionary, top: float, w: float,
		rng: RandomNumberGenerator) -> void:
	var hall: float = top * 0.34
	var roof_h: float = top * 0.2
	var yaw: float = rng.randf_range(-0.3, 0.3)
	_part(parts, "box", "wall", 1, Vector3(0, hall * 0.5, 0), Vector3(w * 1.35, hall, w * 0.82), yaw)
	_part(parts, "lean", "roof", 2, Vector3(0, hall + roof_h * 0.5, 0),
		Vector3(w * 1.5, roof_h, w * 0.94), yaw)
	_part(parts, "post", "post", 0, Vector3(-w * 0.52, top * 0.5, w * 0.34),
		Vector3(w * 0.2, top, w * 0.2), yaw)
	_part(parts, "box", "trim", 2, Vector3(-w * 0.52, top * 0.84, w * 0.34),
		Vector3(w * 0.66, top * 0.14, w * 0.05), yaw)
	_part(parts, "box", "wall", 2, Vector3(-w * 0.52, top * 0.62, w * 0.34),
		Vector3(w * 0.3, top * 0.09, w * 0.3), yaw)


# A ring of posts with a gap for the gate. The gap matters more than it sounds:
# an unbroken ring reads as a solid disc at map size, a broken one reads as a
# wall you could walk through, and that is the difference between "blob" and
# "place".
static func _palisade(parts: Array, faction: String, radius: float, h: float,
		rng: RandomNumberGenerator) -> float:
	var n := 22
	var gate := rng.randi() % n
	for i in n:
		if i == gate or i == (gate + 1) % n:
			continue
		var ang := TAU * float(i) / float(n)
		var at := Vector2(cos(ang), sin(ang)) * radius
		# Height is jittered per post (a palisade is cut stakes, not a fence
		# panel), so the centre has to follow it — pinning the centre at h * 0.5
		# and then varying the length buried every taller stake in the ground.
		var post_h: float = h * rng.randf_range(0.88, 1.12)
		parts.append({
			"part": "post", "role": "post", "shade": i % KitParts.SHADES.size(),
			"pos": Vector3(at.x, post_h * 0.5, at.y),
			"size": Vector3(h * 0.22, post_h, h * 0.22),
			"yaw": ang, "tilt": 0.0,
		})
	return TAU * (float(gate) + 0.5) / float(n)


# A polygon of wall segments with towers on some corners, again with a gate gap.
# Segment length is the polygon's chord, so the wall closes properly instead of
# leaving the sawtooth an eyeballed length would.
static func _stone_wall(parts: Array, faction: String, radius: float, h: float,
		rng: RandomNumberGenerator) -> float:
	var n := 12
	var gate := rng.randi() % n
	var chord: float = 2.0 * radius * sin(PI / float(n))
	for i in n:
		var ang := TAU * (float(i) + 0.5) / float(n)
		var at := Vector2(cos(ang), sin(ang)) * radius * cos(PI / float(n))
		if i != gate:
			# One shade for every segment, not i % SHADES: a wall is one object,
			# and per-segment shading turned it into a row of separate panels.
			parts.append({
				"part": "box", "role": "stone", "shade": 0,
				"pos": Vector3(at.x, h * 0.5, at.y),
				"size": Vector3(chord * 1.04, h, h * 0.34),
				"yaw": -ang, "tilt": 0.0,
			})
		# Towers on the corners either side of the gate and every third corner —
		# enough to break the wall's top line without turning it into a comb.
		if i % 3 == 0 or i == (gate + 1) % n:
			var c := TAU * float(i) / float(n)
			var cat := Vector2(cos(c), sin(c)) * radius
			parts.append({
				"part": "box", "role": "stone", "shade": 2,
				"pos": Vector3(cat.x, h * 0.85, cat.y),
				"size": Vector3(h * 0.5, h * 1.7, h * 0.5), "yaw": c, "tilt": 0.0,
			})
			# The tower's cap follows the faction's own roof, not a fixed prism —
			# an elf city with gabled gatehouses among its spires read as two
			# different settlements sharing a wall.
			parts.append({
				"part": "cone" if String(PROFILES[faction]["roof_kind"]) == "cone" else "prism",
				"role": "roof", "shade": 1,
				"pos": Vector3(cat.x, h * 1.7 + h * 0.19, cat.y),
				"size": Vector3(h * 0.62, h * 0.38, h * 0.62), "yaw": c, "tilt": 0.0,
			})
	return TAU * (float(gate) + 0.5) / float(n)


# --- the kitbash set --------------------------------------------------------
#
# Everything below appends parts around a point, in World units, y=0 on the
# ground, and stays inside a circle about `s` across so _dress() can treat a
# piece as one footprint. `s` is the settlement's own scale (house_h * 0.42),
# so a city's well is a city's well and a camp's fire is a camp's fire.

# The one-line append every builder here uses. Nothing clever — the plan format
# is seven keys and writing them out fourteen times was most of this file.
#
# `tag` is the optional eighth: kit_parts.gd ignores it, and the only thing
# that reads it is a consumer asking which parts are DWELLINGS rather than
# scenery. It exists because "role == wall" used to answer that question by
# accident, and the kitbash set broke the accident — a market stall's counter
# and a totem's skull are wall-coloured too.
static func _part(parts: Array, part: String, role: String, shade: int,
		pos: Vector3, size: Vector3, yaw := 0.0, tilt := 0.0, tag := "") -> void:
	var d := {"part": part, "role": role, "shade": shade,
		"pos": pos, "size": size, "yaw": yaw, "tilt": tilt}
	if tag != "":
		d["tag"] = tag
	parts.append(d)


# Canvas, not walls. A tent is the roof shape resting straight on the ground
# with a pole through it, which is exactly what a house is NOT — and at 29px a
# camp of tents against a camp of little houses is the clearest silhouette
# difference in the whole kit.
static func _tent(parts: Array, faction: String, at: Vector2, w: float, h: float,
		d: float, yaw: float, shade: int, rng: RandomNumberGenerator) -> void:
	var prof: Dictionary = PROFILES[faction]
	var canvas: float = h * 0.62          # a tent is lower than the house it replaces
	_part(parts, "lean" if String(prof["roof_kind"]) == "lean" else "prism",
		"wall", shade, Vector3(at.x, canvas * 0.5, at.y),
		Vector3(w * 1.12, canvas, d * 1.12), yaw,
		deg_to_rad(rng.randf_range(-1.0, 1.0) * float(prof["lean_deg"])), "dwelling")
	# The pole out the front, and the guy rope's peg. Two parts, and without
	# them the prism reads as a wedge of cheese.
	var fwd := Vector2(cos(yaw), sin(yaw)) * w * 0.62
	_part(parts, "post", "post", 1,
		Vector3(at.x + fwd.x, canvas * 0.62, at.y + fwd.y),
		Vector3(w * 0.09, canvas * 1.24, w * 0.09), yaw)
	if rng.randf() < 0.6:
		_part(parts, "box", "post", 0,
			Vector3(at.x - fwd.x * 0.8, canvas * 0.08, at.y - fwd.y * 0.8),
			Vector3(w * 0.4, canvas * 0.16, w * 0.3), yaw + rng.randf_range(-0.4, 0.4))


# Two posts and a lintel in the gap the wall left. Squared gateposts rather than
# round stakes on purpose: it is the one place on the ring where the eye should
# stop, and a different primitive is what stops it.
static func _gatehouse(parts: Array, faction: String, ang: float, radius: float,
		h: float) -> void:
	var at := Vector2(cos(ang), sin(ang)) * radius
	var across := Vector2(-sin(ang), cos(ang))
	# Kept to the wall's own scale: the first pass stood 1.24x the palisade with
	# a lintel 1.6x wide, and a gate that overtops its wall by a quarter reads
	# as a triumphal arch somebody left in a field.
	var gw: float = h * 0.26
	for side: float in [-1.0, 1.0]:
		var off := across * h * 0.5 * side
		_part(parts, "box", "post", 2, Vector3(at.x + off.x, h * 0.55, at.y + off.y),
			Vector3(gw, h * 1.1, gw), -ang)
	_part(parts, "box", "post", 0, Vector3(at.x, h * 1.12, at.y),
		Vector3(h * 1.26, h * 0.15, gw * 0.9), -ang)
	_part(parts, "box", "trim", 2, Vector3(at.x, h * 0.95, at.y),
		Vector3(h * 0.4, h * 0.22, gw * 0.55), -ang)


# What goes in the gaps, and where. The houses are already placed when this
# runs, so its slots have to dodge them: golden-angle spacing (137.5 degrees
# never lines two pieces up, however many there turn out to be) plus the same
# rejection sampling the houses used, against the same `taken` list.
static func _dress(parts: Array, faction: String, kind: String, radius: float,
		taken: Array, rng: RandomNumberGenerator) -> void:
	var names: Array = DRESSING.get(faction, {}).get(kind, [])
	if names.is_empty():
		return
	var p: Dictionary = PLANS[kind]
	var s: float = float(p["house_h"]) * 0.42
	var phase: float = rng.randf_range(0.0, TAU)
	for i in int(p.get("dress", 0)):
		var band: Array = DRESS_BANDS[i % DRESS_BANDS.size()]
		var at := Vector2.ZERO
		for attempt in PLACE_TRIES:
			var ang: float = phase + float(i) * 2.39996 + rng.randf_range(-0.14, 0.14)
			var dist: float = radius * rng.randf_range(band[0], band[1])
			at = Vector2(cos(ang) * dist, sin(ang) * dist)
			if KitParts.clear_of(at, s * 0.7, taken):
				break
		taken.append([at, s * 0.7])
		_dress_one(parts, String(names[i % names.size()]), at, s,
			rng.randf_range(-PI, PI), rng)


# The dispatch. An unknown name draws nothing rather than crashing a map — the
# same call this file makes on a typo'd primitive, one level up.
static func _dress_one(parts: Array, name: String, at: Vector2, s: float,
		yaw: float, rng: RandomNumberGenerator) -> void:
	match name:
		"fire": _dress_fire(parts, at, s, rng)
		"well": _dress_well(parts, at, s, yaw)
		"stall": _dress_stall(parts, at, s, yaw)
		"cart": _dress_cart(parts, at, s, yaw, "post", "post")
		"orecart": _dress_cart(parts, at, s, yaw, "stone", "ember")
		"woodpile": _dress_woodpile(parts, at, s, yaw, rng)
		"haystack": _dress_haystack(parts, at, s, yaw)
		"tree": _dress_tree(parts, at, s, yaw, rng)
		"stone": _dress_standing_stone(parts, at, s, yaw, rng)
		"minehead": _dress_minehead(parts, at, s, yaw)
		"totem": _dress_totem(parts, at, s, yaw)
		"trophy": _dress_trophy(parts, at, s, yaw)


# A ring of stones and a flame. The only `ember` part most settlements have, and
# at map size it is two pixels of orange in a brown town — which is exactly what
# a fire looks like from a hill at dusk.
static func _dress_fire(parts: Array, at: Vector2, s: float, rng: RandomNumberGenerator) -> void:
	_part(parts, "disc", "stone", 0, Vector3(at.x, s * 0.07, at.y),
		Vector3(s * 0.9, s * 0.14, s * 0.9))
	_part(parts, "cone", "ember", 2, Vector3(at.x, s * 0.14 + s * 0.2, at.y),
		Vector3(s * 0.46, s * 0.4, s * 0.46), rng.randf_range(0.0, TAU))


static func _dress_well(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	var rim: float = s * 0.26
	_part(parts, "disc", "stone", 1, Vector3(at.x, rim * 0.5, at.y),
		Vector3(s * 0.74, rim, s * 0.74))
	var across := Vector2(-sin(yaw), cos(yaw)) * s * 0.28
	for side: float in [-1.0, 1.0]:
		_part(parts, "post", "post", 1,
			Vector3(at.x + across.x * side, rim + s * 0.3, at.y + across.y * side),
			Vector3(s * 0.1, s * 0.6, s * 0.1), yaw)
	_part(parts, "box", "roof", 2, Vector3(at.x, rim + s * 0.66, at.y),
		Vector3(s * 0.78, s * 0.12, s * 0.5), yaw)


static func _dress_stall(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	_part(parts, "box", "wall", 0, Vector3(at.x, s * 0.17, at.y),
		Vector3(s * 0.72, s * 0.34, s * 0.34), yaw)
	var across := Vector2(-sin(yaw), cos(yaw)) * s * 0.3
	for side: float in [-1.0, 1.0]:
		_part(parts, "post", "post", 1,
			Vector3(at.x + across.x * side, s * 0.3, at.y + across.y * side),
			Vector3(s * 0.08, s * 0.6, s * 0.08), yaw)
	# The awning is the one bright plane down there, so it gets the roof colour
	# and a tilt: a flat canopy at this size is indistinguishable from a crate.
	_part(parts, "box", "roof", 2, Vector3(at.x, s * 0.64, at.y),
		Vector3(s * 0.88, s * 0.1, s * 0.56), yaw, 0.14)


# A cart, or the same cart full of ore. The wheels are `post` cylinders tilted
# onto their sides — a disc would be 60 triangles each for something 3px across.
static func _dress_cart(parts: Array, at: Vector2, s: float, yaw: float,
		body_role: String, load_role: String) -> void:
	var bed: float = s * 0.7
	_part(parts, "box", body_role, 1, Vector3(at.x, s * 0.34, at.y),
		Vector3(bed, s * 0.28, bed * 0.58), yaw)
	_part(parts, "box", load_role, 2, Vector3(at.x, s * 0.5, at.y),
		Vector3(bed * 0.7, s * 0.14, bed * 0.4), yaw)
	var across := Vector2(-sin(yaw), cos(yaw)) * bed * 0.34
	for side: float in [-1.0, 1.0]:
		_part(parts, "post", "post", 0,
			Vector3(at.x + across.x * side, s * 0.2, at.y + across.y * side),
			Vector3(s * 0.4, s * 0.09, s * 0.4), yaw, PI * 0.5)
	# Shafts tipped up, the way a parked cart's are.
	var fwd := Vector2(cos(yaw), sin(yaw)) * bed * 0.62
	_part(parts, "box", "post", 2, Vector3(at.x + fwd.x, s * 0.52, at.y + fwd.y),
		Vector3(bed * 0.6, s * 0.07, s * 0.07), yaw, -0.45)


static func _dress_woodpile(parts: Array, at: Vector2, s: float, yaw: float,
		rng: RandomNumberGenerator) -> void:
	for i in 3:
		var y: float = s * (0.09 + 0.17 * float(i))
		_part(parts, "box", "post", i % KitParts.SHADES.size(),
			Vector3(at.x, y, at.y), Vector3(s * (0.66 - 0.1 * float(i)), s * 0.16,
			s * (0.4 - 0.05 * float(i))), yaw + rng.randf_range(-0.3, 0.3))


static func _dress_haystack(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	_part(parts, "box", "post", 0, Vector3(at.x, s * 0.07, at.y),
		Vector3(s * 0.62, s * 0.14, s * 0.62), yaw)
	_part(parts, "cone", "wall", 2, Vector3(at.x, s * 0.14 + s * 0.3, at.y),
		Vector3(s * 0.66, s * 0.6, s * 0.66), yaw)


static func _dress_tree(parts: Array, at: Vector2, s: float, yaw: float,
		rng: RandomNumberGenerator) -> void:
	var k: float = rng.randf_range(0.85, 1.25)
	_part(parts, "post", "post", 0, Vector3(at.x, s * 0.35 * k, at.y),
		Vector3(s * 0.14, s * 0.7 * k, s * 0.14), yaw)
	_part(parts, "cone", "roof", 0, Vector3(at.x, s * 0.9 * k, at.y),
		Vector3(s * 0.8 * k, s * 0.7 * k, s * 0.8 * k), yaw)
	_part(parts, "cone", "roof", 2, Vector3(at.x, s * 1.3 * k, at.y),
		Vector3(s * 0.56 * k, s * 0.56 * k, s * 0.56 * k), yaw)


static func _dress_standing_stone(parts: Array, at: Vector2, s: float, yaw: float,
		rng: RandomNumberGenerator) -> void:
	var h: float = s * rng.randf_range(0.9, 1.25)
	_part(parts, "box", "stone", 2, Vector3(at.x, h * 0.5, at.y),
		Vector3(s * 0.3, h, s * 0.22), yaw, rng.randf_range(-0.09, 0.09))
	_part(parts, "box", "trim", 2, Vector3(at.x, h * 0.74, at.y),
		Vector3(s * 0.34, h * 0.1, s * 0.26), yaw)


# The A-frame over a shaft, with the spoil heap beside it. Dwarf camps are
# mining camps; this is the thing they are camped around.
static func _dress_minehead(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	var across := Vector2(-sin(yaw), cos(yaw)) * s * 0.3
	for side: float in [-1.0, 1.0]:
		_part(parts, "box", "post", 1,
			Vector3(at.x + across.x * side, s * 0.46, at.y + across.y * side),
			Vector3(s * 0.11, s * 0.92, s * 0.11), yaw, -0.3 * side)
	_part(parts, "box", "post", 2, Vector3(at.x, s * 0.86, at.y),
		Vector3(s * 0.26, s * 0.1, s * 0.16), yaw)
	_part(parts, "box", "roof", 0, Vector3(at.x, s * 0.06, at.y),
		Vector3(s * 0.44, s * 0.12, s * 0.44), yaw)


static func _dress_totem(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	_part(parts, "post", "post", 0, Vector3(at.x, s * 0.75, at.y),
		Vector3(s * 0.2, s * 1.5, s * 0.2), yaw)
	_part(parts, "box", "wall", 2, Vector3(at.x, s * 1.42, at.y),
		Vector3(s * 0.34, s * 0.3, s * 0.34), yaw)
	_part(parts, "box", "trim", 2, Vector3(at.x, s * 1.02, at.y),
		Vector3(s * 0.62, s * 0.22, s * 0.06), yaw)


static func _dress_trophy(parts: Array, at: Vector2, s: float, yaw: float) -> void:
	_part(parts, "post", "post", 1, Vector3(at.x, s * 0.45, at.y),
		Vector3(s * 0.12, s * 0.9, s * 0.12), yaw, 0.12)
	_part(parts, "box", "wall", 2, Vector3(at.x + s * 0.06, s * 0.96, at.y),
		Vector3(s * 0.24, s * 0.24, s * 0.24), yaw)


# --- turning the plan into nodes -------------------------------------------

# The primitives, materials and caches all live in kit_parts.gd; what stays
# here is the palette this kit hands it. A faction's PROFILES entry is already
# role -> Color plus the shape numbers, and KitParts.material_for() only reads
# the roles it is asked for, so it doubles as the palette unchanged.
static func build(faction: String, kind: String, id: String) -> Node3D:
	return KitParts.assemble(plan(faction, kind, id), PROFILES[faction],
		"%s_%s" % [faction, kind])


static func triangles(faction: String, kind: String, id: String) -> int:
	return KitParts.triangles(plan(faction, kind, id))

# --- the lodge (core/lodge.gd) ----------------------------------------------

# The company's house beside its town: one town-sized house at the origin in
# the town's own style, and per room built a part group around it. The rooms
# go up in LODGE_ROOMS order whatever order they were bought in, so the same
# lodge is the same lodge across saves, and each room's parts carry its tag so
# the map can be read back against party.lodge["rooms"]. Sized off the town
# plan's house, so it is a house among the town's houses and not a second town.
const LODGE_ROOMS := ["strongroom", "yard", "garden", "shrine", "maproom"]

static func lodge_plan(faction: String, rooms: Array, id: String) -> Array:
	if not PROFILES.has(faction):
		return []
	var p: Dictionary = PLANS["town"]
	var prof: Dictionary = PROFILES[faction]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/lodge/%s" % [faction, id])
	var parts: Array = []
	var shade: int = rng.randi() % KitParts.SHADES.size()
	var w: float = float(p["house_w"]) * float(prof["slender"])
	var h: float = float(p["house_h"]) * float(prof["squat"])
	var body: Vector3 = _house(parts, faction, Vector2.ZERO, w, h, w * 1.3,
		float(p["height"]) * float(p["house_cap"]), 0.0, shade, rng)
	_house_details(parts, faction, Vector2.ZERO, body, 0.0, shade, rng)   # the door faces +x
	w = body.x
	h = body.y
	var d: float = body.z
	var u: float = h * 0.1   # about a world unit; everything below is in these
	for room in LODGE_ROOMS:
		if not room in rooms:
			continue
		match room:
			"strongroom":   # a stone annex against the back wall, under its own roof
				var ax: float = -(w * 0.5 + w * 0.22)
				_part(parts, "box", "stone", 1, Vector3(ax, h * 0.2, 0.0), Vector3(w * 0.44, h * 0.4, d * 0.6), 0.0, 0.0, room)
				_part(parts, "prism", "roof", shade, Vector3(ax, h * 0.4 + h * 0.06, 0.0), Vector3(w * 0.5, h * 0.12, d * 0.66), 0.0, 0.0, room)
			"yard":   # four posts in a square, and the training post in the middle
				for sx: float in [-1.0, 1.0]:
					for sz: float in [1.5, 6.0]:
						_part(parts, "post", "post", 1, Vector3(sx * w * 0.35, u * 1.3, d * 0.5 + u * sz), Vector3(u * 0.4, u * 2.6, u * 0.4), 0.0, 0.0, room)
				_part(parts, "post", "post", 0, Vector3(0.0, u * 2.1, d * 0.5 + u * 3.75), Vector3(u * 0.6, u * 4.2, u * 0.6), 0.0, 0.0, room)
			"garden":   # three beds in a row along the far wall
				for i in 3:
					_part(parts, "disc", "stone", 0, Vector3((i - 1) * w * 0.35, u * 0.25, -(d * 0.5 + u * 2.5)), Vector3(u * 2.2, u * 0.5, u * 2.2), 0.0, 0.0, room)
			"shrine":   # a stone at the corner, and the lantern on it
				var sx: float = w * 0.5 + u * 4.0
				var sz: float = -(d * 0.5 + u * 2.0)
				_part(parts, "rock", "stone", 2, Vector3(sx, u * 0.8, sz), Vector3(u * 2.0, u * 1.6, u * 2.0), 0.0, 0.0, room)
				_part(parts, "cone", "ember", 2, Vector3(sx, u * 1.6 + u * 0.5, sz), Vector3(u * 0.8, u * 1.0, u * 0.8), 0.0, 0.0, room)
			"maproom":   # a small tower at the other corner, under a spire
				var tx: float = -(w * 0.5 + u * 2.5)
				var tz: float = d * 0.5 + u * 2.5
				_part(parts, "box", "wall", shade, Vector3(tx, h * 0.55, tz), Vector3(u * 2.6, h * 1.1, u * 2.6), 0.0, 0.0, room)
				_part(parts, "cone", "roof", shade, Vector3(tx, h * 1.1 + h * 0.2, tz), Vector3(u * 3.0, h * 0.4, u * 3.0), 0.0, 0.0, room)
	KitParts.apron(parts, "ground", maxf(w, d) * 0.5 + u * 8.0)
	return parts


# The town's own palette and material cache: it is one of the town's houses.
static func build_lodge(faction: String, rooms: Array, id: String) -> Node3D:
	return KitParts.assemble(lodge_plan(faction, rooms, id), PROFILES[faction], "%s_town" % faction)
