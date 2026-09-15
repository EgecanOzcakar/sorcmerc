# Settlement dioramas ASSEMBLED from modules, instead of generated as one mesh.
#
# WHY THIS EXISTS. The tier-0 dioramas in assets/settlements/ are Meshy
# text-to-3D output put through a remesh: each is a single fused 82k-triangle
# blob with one baked material, and its atlas carries 3.3k-5.3k UV islands
# averaging ~25px across on a 2048 texture. A settlement is drawn 29px (camp),
# 48px (town) or 83px (city) tall at zoom 1 — ISO_GAIN is 1.85 and
# Settlements3D.TARGET_HEIGHT is 15.6/25.7/45 world units — so that atlas is
# sampled around mip 5, where every island collapses below a texel and the
# whole model averages to the one muddy brown the atlas is made of. That is the
# "rough" look, and no amount of texture budget fixes it: the geometry has no
# hard edges to read at 48px either, because reconstruction produces fused
# organic volumes and a village is flat planes and straight ridgelines.
#
# So this builds the opposite thing: ~15-triangle primitives (box bodies, prism
# and cone roofs, posts) placed by a seeded layout, sharing a handful of flat
# untextured materials. A city comes out around 1.2k triangles against 82.5k,
# with a crisp silhouette at the size it is actually drawn, and — because the
# layout is seeded on the settlement's own id — every town is a different town,
# which the twelve fixed GLBs never were.
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
# apron in _ground(), which has its reasons written where it is built.
extends RefCounted

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
const PLANS := {
	"camp": {"height": 15.6, "radius": 12.0, "houses": [3, 5], "house_h": 6.6,
		"house_w": 5.2, "house_cap": 0.72, "wall": ""},
	"town": {"height": 25.7, "radius": 18.0, "houses": [6, 9], "house_h": 10.5,
		"house_w": 6.4, "house_cap": 0.62, "wall": "palisade"},
	"city": {"height": 45.0, "radius": 28.0, "houses": [12, 16], "house_h": 13.0,
		"house_w": 7.6, "house_cap": 0.55, "wall": "stone"},
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
#   ground      the dirt apron the settlement stands on — see _ground().
#   roof        prism = gabled, cone = spire, lean = single-pitch (asymmetric
#               PrismMesh, the crooked orc shed)
#   pitch       roof height as a fraction of the body's, so dwarf reads squat
#               and elf reads steep from the silhouette alone
#   slender     body width multiplier: elf tall and narrow, dwarf broad and low
#   lean_deg    per-building random tilt, orc only — nothing else is crooked
const PROFILES := {
	"human": {
		"wall": Color("e0d2b2"), "roof": Color("9c4d33"), "trim": Color("6b5236"),
		"stone": Color("9a9284"), "post": Color("6d5636"), "ground": Color("6f6446"),
		"roof_kind": "prism", "pitch": 0.62,
		"slender": 1.0, "squat": 1.0, "lean_deg": 0.0,
	},
	"elf": {
		"wall": Color("e6dfc9"), "roof": Color("3f7a64"), "trim": Color("c8a94e"),
		"stone": Color("9fa79a"), "post": Color("8d8a6a"), "ground": Color("5f6a4c"),
		"roof_kind": "cone", "pitch": 0.72,
		"slender": 0.82, "squat": 1.12, "lean_deg": 0.0,
	},
	"dwarf": {
		"wall": Color("bda88c"), "roof": Color("3a352f"), "trim": Color("c47a22"),
		"stone": Color("8d8175"), "post": Color("6b6359"), "ground": Color("6e6252"),
		"roof_kind": "prism", "pitch": 0.34,
		"slender": 1.32, "squat": 0.74, "lean_deg": 0.0,
	},
	"orc": {
		"wall": Color("a89068"), "roof": Color("57432f"), "trim": Color("a83c26"),
		"stone": Color("6a5f4c"), "post": Color("4a3f30"), "ground": Color("5c5340"),
		"roof_kind": "lean", "pitch": 0.5,
		"slender": 1.1, "squat": 0.86, "lean_deg": 5.5,
	},
}

# Three brightness steps per role, picked per building off the seed, so a row of
# houses is not one flat colour. Kept this coarse on purpose: at 48px a
# continuous jitter is noise, three steps still read as "separate buildings".
const SHADES := [-0.10, 0.0, 0.12]

# Rejection sampling for building placement: give up after this many tries and
# take the last position. Bounded so plan() can never hang.
const PLACE_TRIES := 24

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

static var _meshes := {}         # part name -> Mesh, shared by every instance
static var _materials := {}      # "faction:role:shade" -> StandardMaterial3D


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
		var at := Vector2.ZERO
		for attempt in PLACE_TRIES:
			var ang: float = phase[ring] \
				+ TAU * (float(slot) + rng.randf_range(-0.18, 0.18)) / float(slots[ring])
			var dist: float = radius * rng.randf_range(band[0], band[1])
			at = Vector2(cos(ang) * dist, sin(ang) * dist)
			if _clear(at, clearance, taken):
				break
		taken.append([at, clearance])
		_house(parts, faction, at, w, h, d, float(p["height"]) * float(p["house_cap"]),
			rng.randf_range(-PI, PI), rng.randi() % SHADES.size(), rng)

	match String(p["wall"]):
		"palisade": _palisade(parts, faction, radius * 1.02, float(p["house_h"]) * 0.66, rng)
		"stone": _stone_wall(parts, faction, radius * 1.02, float(p["house_h"]) * 0.62, rng)
	_ground(parts, faction, radius)
	return parts


# A shallow dirt apron under the whole settlement. The first render without one
# was the clearest single problem: flat-shaded buildings with nothing beneath
# them read as blocks floating over the terrain, because there is no contact
# edge anywhere. A disc gives every building a line to sit on.
#
# This does cover World._draw_settlement()'s footprint ring, which the header
# above says this layer does not own — but that ring is already covered today:
# a GLB fitted to 45 units tall is 88 units across against a ring of 28, and it
# brings its own baked base plate. So this is the existing behaviour, not a new
# regression, and the ring is still doing its job at the zoom levels where the
# diorama is too small to hide it.
static func _ground(parts: Array, faction: String, radius: float) -> void:
	parts.append({
		"part": "disc", "role": "ground", "shade": 1,
		"pos": Vector3(0, 0.35, 0), "size": Vector3(radius * 2.06, 0.7, radius * 2.06),
		"yaw": 0.0, "tilt": 0.0,
	})


# Is `at` far enough from everything already placed? Circle-vs-circle on the
# ground plane — buildings are boxes, but their yaw is random, so a bounding
# circle is both the honest test and the cheap one.
static func _clear(at: Vector2, clearance: float, taken: Array) -> bool:
	for t in taken:
		if at.distance_to(t[0]) < clearance + float(t[1]):
			return false
	return true


# A body plus its roof, and for the factions that have one, a chimney. The roof
# is 12% wider than the body in both directions: that overhang is what puts a
# dark edge line under every roof, and it is most of what makes these read as
# buildings rather than as coloured boxes once they are 10px tall.
static func _house(parts: Array, faction: String, at: Vector2, w: float, h: float,
		d: float, cap: float, yaw: float, shade: int, rng: RandomNumberGenerator) -> void:
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
		"part": "box", "role": "wall", "shade": shade,
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


# The one tall thing, at the centre: what the eye finds first and what tells the
# factions apart at a glance. Each is the kind's full `height`, so a kit diorama
# occupies exactly the vertical space the GLB it replaces did.
static func _landmark(parts: Array, faction: String, kind: String,
		rng: RandomNumberGenerator) -> void:
	var p: Dictionary = PLANS[kind]
	var prof: Dictionary = PROFILES[faction]
	var top: float = p["height"]
	# The banner's headroom comes out of the landmark's budget rather than being
	# added on top, so the diorama's highest point is exactly PLANS.height and
	# swapping `source` on Settlements3D cannot change how tall a settlement is.
	var spire: float = 0.0 if kind == "town" else top * 0.12
	var solid: float = top - spire
	var roof_h: float = solid * (0.46 if String(prof["roof_kind"]) == "cone" else 0.28)
	var body_h: float = solid - roof_h
	var w: float = float(p["radius"]) * 0.46 * float(prof["slender"])

	parts.append({
		"part": "box", "role": "stone", "shade": 2,
		"pos": Vector3(0, body_h * 0.5, 0), "size": Vector3(w, body_h, w),
		"yaw": rng.randf_range(-0.25, 0.25), "tilt": 0.0,
	})
	parts.append({
		"part": "cone" if String(prof["roof_kind"]) == "cone" else "prism",
		"role": "roof", "shade": 1,
		"pos": Vector3(0, body_h + roof_h * 0.5, 0),
		"size": Vector3(w * 1.2, roof_h, w * 1.2), "yaw": 0.0, "tilt": 0.0,
	})
	# A banner on the two kinds with no palisade to give them a vertical accent,
	# and on the city keep because a keep without a flag is a warehouse.
	if spire > 0.0:
		parts.append({
			"part": "box", "role": "trim", "shade": 2,
			"pos": Vector3(w * 0.30, solid + spire * 0.5, 0),
			"size": Vector3(w * 0.30, spire, w * 0.06), "yaw": 0.0, "tilt": 0.0,
		})


# A ring of posts with a gap for the gate. The gap matters more than it sounds:
# an unbroken ring reads as a solid disc at map size, a broken one reads as a
# wall you could walk through, and that is the difference between "blob" and
# "place".
static func _palisade(parts: Array, faction: String, radius: float, h: float,
		rng: RandomNumberGenerator) -> void:
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
			"part": "post", "role": "post", "shade": i % SHADES.size(),
			"pos": Vector3(at.x, post_h * 0.5, at.y),
			"size": Vector3(h * 0.22, post_h, h * 0.22),
			"yaw": ang, "tilt": 0.0,
		})


# A polygon of wall segments with towers on some corners, again with a gate gap.
# Segment length is the polygon's chord, so the wall closes properly instead of
# leaving the sawtooth an eyeballed length would.
static func _stone_wall(parts: Array, faction: String, radius: float, h: float,
		rng: RandomNumberGenerator) -> void:
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


# --- turning the plan into nodes -------------------------------------------

# One Node3D holding one MeshInstance3D per part, resting on y=0, ready to be
# positioned by Settlements3D._reposition() exactly like an instantiated GLB.
# Meshes and materials are shared statics, so the Nth settlement allocates
# nothing but nodes.
static func build(faction: String, kind: String, id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "kit_%s_%s" % [faction, kind]
	for part in plan(faction, kind, id):
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(String(part["part"]), part["size"])
		mi.material_override = _material(faction, String(part["role"]), int(part["shade"]))
		var b := Basis.from_euler(Vector3(0.0, float(part["yaw"]), float(part["tilt"])))
		mi.transform = Transform3D(b, part["pos"])
		root.add_child(mi)
	return root


# Primitive meshes are sized per part rather than scaled from a unit mesh: a
# non-uniform Node3D scale would skew the normals on the tilted orc buildings,
# and PrimitiveMesh instances with identical parameters are cheap to hold.
# Keyed on the part name and its rounded size so the ~40 distinct sizes in a map
# full of settlements share a handful of resources instead of one each.
static func _mesh(part: String, size: Vector3) -> Mesh:
	var key := "%s:%.1f,%.1f,%.1f" % [part, size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match part:
		"prism":
			var pr := PrismMesh.new()
			pr.size = size
			m = pr
		"lean":
			# Same prism with its ridge pushed to one side: a single-pitch roof,
			# which is the orc shed's whole character.
			var pl := PrismMesh.new()
			pl.size = size
			pl.left_to_right = 0.3
			m = pl
		"cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 8
			c.rings = 1
			m = c
		"disc":
			var g := CylinderMesh.new()
			g.top_radius = size.x * 0.5
			g.bottom_radius = size.x * 0.5
			g.height = size.y
			g.radial_segments = 16
			g.rings = 1
			m = g
		"post":
			var p := CylinderMesh.new()
			p.top_radius = size.x * 0.30
			p.bottom_radius = size.x * 0.5
			p.height = size.y
			p.radial_segments = 5
			p.rings = 1
			m = p
		_:
			var b := BoxMesh.new()
			b.size = size
			m = b
	_meshes[key] = m
	return m


# Flat, unlit-looking, untextured: no albedo map at all, which is the point —
# there is no atlas to mip away. Roughness is high and specular off so the only
# shading is the diorama rig's own sun, and a roof edge stays an edge at 10px.
static func _material(faction: String, role: String, shade: int) -> StandardMaterial3D:
	var key := "%s:%s:%d" % [faction, role, shade]
	if _materials.has(key):
		return _materials[key]
	var base: Color = PROFILES[faction].get(role, Color.MAGENTA)
	var step: float = SHADES[clampi(shade, 0, SHADES.size() - 1)]
	var m := StandardMaterial3D.new()
	m.albedo_color = base.lightened(step) if step > 0.0 else base.darkened(-step)
	m.roughness = 0.92
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[key] = m
	return m


# Tests and the gallery both want this and neither should re-derive it: the
# triangle budget the whole point of this file rests on.
static func triangles(faction: String, kind: String, id: String) -> int:
	var total := 0
	for part in plan(faction, kind, id):
		match String(part["part"]):
			"prism", "lean": total += 8
			"cone": total += 12       # 6 side triangles + a 6-gon base fan
			"disc": total += 60       # 16 segments quadded, two 16-gon caps
			"post": total += 20       # 5 sides quadded + two caps
			_: total += 12
	return total
