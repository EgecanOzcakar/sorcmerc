# The primitive vocabulary both kitbash layers are built out of —
# settlement_kit.gd and lair_kit.gd. Extracted when the second one arrived and
# wanted the same five things: the part -> Mesh table, the shared caches, the
# flat material, the plan -> Node3D assembly, and the triangle count.
#
# THE PLAN FORMAT, which is the actual contract between a kit and this file. A
# kit's plan() returns an Array of Dictionaries, each one part, in World units
# with y=0 on the ground:
#
#   part   one of PARTS below — which primitive to build
#   role   a key into the kit's own palette Dictionary; this file never knows
#          what "roof" or "water" means, only that the palette has an entry
#   shade  index into SHADES, a coarse brightness step
#   pos    centre, Vector3
#   size   full extent, Vector3 (not a radius — a "rock" of size.x 4 is 4 across)
#   yaw    rotation about Y, radians
#   tilt   rotation about Z, radians
#
# Nothing here touches a SceneTree, so a kit's plan() stays testable headless
# and only assemble() allocates nodes.
extends RefCounted

# Every primitive a kit may ask for. Anything not in here falls through to a
# box, which is deliberate — a typo in a plan should draw something visibly
# wrong in the gallery, not crash a map.
const PARTS := ["box", "prism", "lean", "cone", "post", "disc", "rock"]

# Three brightness steps, picked per part off the kit's own seed, so a row of
# houses or a row of headstones is not one flat colour. Coarse on purpose: at
# the 22-83px these are drawn at, continuous jitter is noise and three steps
# still read as "separate objects".
const SHADES := [-0.10, 0.0, 0.12]

# Triangle cost per primitive, for the budget checks. Counted off the meshes
# built below rather than guessed: a kit's whole claim is that it costs ~1-2k
# triangles against the GLBs' ~82k, and a claim worth making is worth counting.
const TRIS := {
	"box": 12, "prism": 8, "lean": 8, "cone": 12,
	"post": 20, "disc": 60, "rock": 60,
}

static var _meshes := {}         # "part:w,h,d" -> Mesh, shared by every instance
static var _materials := {}      # "kit:role:shade" -> StandardMaterial3D


# One Node3D holding one MeshInstance3D per part, resting on y=0, ready to be
# positioned by a diorama layer exactly like an instantiated GLB.
#
# `palette` maps a role to a Color; `key` namespaces this kit's materials in the
# shared cache, so a settlement's "stone" and a lair's "stone" stay different
# colours. Meshes and materials are shared statics, so the Nth diorama allocates
# nothing but nodes.
static func assemble(parts: Array, palette: Dictionary, key: String) -> Node3D:
	var root := Node3D.new()
	root.name = "kit_%s" % key
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_for(String(part["part"]), part["size"])
		mi.material_override = material_for(key, String(part["role"]), palette,
			int(part["shade"]))
		var b := Basis.from_euler(Vector3(0.0, float(part["yaw"]), float(part["tilt"])))
		mi.transform = Transform3D(b, part["pos"])
		root.add_child(mi)
	return root


# Primitive meshes are sized per part rather than scaled from a unit mesh: a
# non-uniform Node3D scale would skew the normals on anything tilted (the orc
# buildings, every headstone in a graveyard), and PrimitiveMesh instances with
# identical parameters are cheap to hold. Keyed on the part name and its rounded
# size so a map full of dioramas shares a few dozen resources, not one each.
static func mesh_for(part: String, size: Vector3) -> Mesh:
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
		"rock":
			# A boulder, a cave mound, a grave mound. Deliberately coarse: at 5
			# segments and 3 rings the facets are big enough to catch the sun
			# separately, which is what makes it read as stone rather than as a
			# ball. Scaled per axis through the radius/height, so a rock can be
			# squashed flat without the normals skewing.
			var r := SphereMesh.new()
			r.radius = size.x * 0.5
			r.height = size.y
			r.radial_segments = 5
			r.rings = 3
			m = r
		_:
			var b := BoxMesh.new()
			b.size = size
			m = b
	_meshes[key] = m
	return m


# Flat, untextured: no albedo map at all, which is the point — there is no atlas
# to mip away. Roughness is high and specular off so the only shading is the
# diorama rig's own sun, and an edge stays an edge at 10px.
static func material_for(key: String, role: String, palette: Dictionary,
		shade: int) -> StandardMaterial3D:
	var full := "%s:%s:%d" % [key, role, shade]
	if _materials.has(full):
		return _materials[full]
	# Magenta rather than a default colour: a role missing from a palette is a
	# bug in the kit, and it should be impossible to miss in the gallery.
	var base: Color = palette.get(role, Color.MAGENTA)
	var step: float = SHADES[clampi(shade, 0, SHADES.size() - 1)]
	var m := StandardMaterial3D.new()
	m.albedo_color = base.lightened(step) if step > 0.0 else base.darkened(-step)
	m.roughness = 0.92
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[full] = m
	return m


# The triangle budget a kit's whole argument rests on. Tests and the gallery
# both want it and neither should re-derive it.
static func triangles(parts: Array) -> int:
	var total := 0
	for part in parts:
		total += int(TRIS.get(String(part["part"]), TRIS["box"]))
	return total


# --- helpers every kit's plan() wants ---------------------------------------

# Is `at` far enough from everything already placed? Circle-vs-circle on the
# ground plane — parts are boxes and rocks, but their yaw is arbitrary, so a
# bounding circle is both the honest test and the cheap one. `taken` is a list
# of [Vector2 centre, float clearance], which the caller appends to itself.
static func clear_of(at: Vector2, clearance: float, taken: Array) -> bool:
	for t in taken:
		if at.distance_to(t[0]) < clearance + float(t[1]):
			return false
	return true


# A shallow apron under a diorama. The first settlement render without one was
# the clearest single problem: flat-shaded parts with nothing beneath them read
# as blocks floating over the terrain, because there is no contact edge
# anywhere. A disc gives every part a line to sit on.
#
# This does cover the footprint ring World._draw_settlement()/_draw_lair() draw
# underneath, which the diorama layers otherwise leave alone — but that ring is
# already covered today: a GLB fitted to its target height is far wider than the
# ring and brings its own baked base plate. So this matches existing behaviour
# rather than introducing a regression.
static func apron(parts: Array, role: String, radius: float, thickness := 0.7) -> void:
	parts.append({
		"part": "disc", "role": role, "shade": 1,
		"pos": Vector3(0, thickness * 0.5, 0),
		"size": Vector3(radius * 2.0, thickness, radius * 2.0),
		"yaw": 0.0, "tilt": 0.0,
	})
