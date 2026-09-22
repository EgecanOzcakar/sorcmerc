# The woods, as trees you can walk a camera around.
#
# Forest used to be a texture: the ground mask's red channel picked
# `forest_tex` instead of `grass_tex` for that cell, and a wood was a patch of
# darker ground. That is all a flat map can do. Once the camera tilts and turns,
# it is also the thing that most obviously gives away that nothing on the map
# has a third dimension — a town is a model, a marching band is a model, and the
# entire countryside between them is wallpaper.
#
# So the forest cells grow real trees. They are what a rotating camera actually
# reads: they stand up off the ground, they occlude each other, and they slide
# past each other as the view turns, which is the parallax that says the map has
# depth. The ground texture stays underneath them, so the woods still read as
# woods wherever the trees are thinned out.
#
# THE RULE IS NOT COPIED. Which cells are forest is decided by exactly the
# rule World._build_mask() writes into the mask's red channel: world.gd's own
# `block_wooded()`, called off the same TILE_CLUSTER block, rather than
# restated here. A second copy of that rule is a wood that grows where the
# ground is grass — and since O-biome the rule is a hash against a threshold
# that varies with the biome disc under the block (core/world.gd), so there is
# more of it to keep in step than one constant.
#
# WHAT IT COSTS, AND THE TWO THINGS THAT KEEP IT DOWN. The trees are two
# MultiMeshes, so the whole map is two draw calls. And the instance arrays are
# rebuilt only when the ground under them changes — keyed on world.gd's own
# memo for the explored-cells-on-screen set, so panning a few cells, or standing
# still, rebuilds nothing. The fog fade, which DOES change every frame as the
# party walks, is two shader uniforms instead (assets/world/ground/foliage.gdshader).
#
# Measured on the worst case there is — the large map at ZOOM_MIN on a 1920x1080
# window after a long walk, 40,885 explored cells on screen and 2,108 trees on
# them: 29ms on a replant, and 0.28ms on a frame that changes nothing (that one
# is the map's whole per-frame upkeep, mask and camera and layers included, not
# this file's share of it — there is nothing left to share). The replant
# happens when world.explored grows, which is the same moment the ground mask
# rebuilds, and that costs 147ms on its own (issue #31's remaining half, walking
# the same cells; untouched by this file and the reason the budget here was
# worth keeping small). Both numbers are why the loop in _plant() is ordered the
# way it is rather than the way it reads best.
extends Node3D

const FoliageShader := preload("res://assets/world/ground/foliage.gdshader")

# A cell is CELL (15) world units across and a party figure is 15 tall, so these
# are stands of trees rather than single trunks — at the scale the map is read
# at, one trunk per 7 metres of ground would be invisible and one per cell is a
# wood.
const TREES_PER_CELL := 2
const TREE_HEIGHT := Vector2(17.0, 26.0)     # min/max, world units
# The ceiling on how many go up at once. Zoomed all the way out the screen
# covers tens of thousands of cells, and past a certain point another thousand
# trees is another thousand triangles nobody can see: beyond this the stand
# thins out and what is left grows, so the woods keep their coverage.
const MAX_TREES := 4000

var _conifer: MultiMeshInstance3D
var _broadleaf: MultiMeshInstance3D
var _mat: ShaderMaterial
var _key: Array = []            # what the current instance arrays were built for


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = FoliageShader
	_conifer = _bank(_tree_mesh(false))
	_broadleaf = _bank(_tree_mesh(true))


func _bank(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = _mat
	add_child(mmi)
	return mmi


# --- the trees themselves -------------------------------------------------
# Built from primitives rather than loaded, the same way scenes/world/
# kit_parts.gd builds a settlement: about 60 triangles each, two-tone in vertex
# colour, and no texture to fetch. At the size a tree is drawn on this map that
# is the whole of what the eye gets, and it means the woods cost nothing to ship.
const TRUNK := Color(0.30, 0.22, 0.15)
const CONIFER_LEAF := Color(0.13, 0.30, 0.17)
const BROAD_LEAF := Color(0.22, 0.38, 0.18)

# One unit tall, standing on y = 0, so the instance transform's Y scale is the
# tree's height in world units.
static func _tree_mesh(broadleaf: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if broadleaf:
		_part(st, _cyl(0.055, 0.075, 0.5, 5), Vector3(0.0, 0.25, 0.0), TRUNK)
		var crown := SphereMesh.new()
		crown.radius = 0.30
		crown.height = 0.62
		crown.radial_segments = 7
		crown.rings = 4
		_part(st, crown, Vector3(0.0, 0.70, 0.0), BROAD_LEAF)
	else:
		_part(st, _cyl(0.045, 0.065, 0.32, 5), Vector3(0.0, 0.16, 0.0), TRUNK)
		# Three stacked skirts: a conifer's silhouette is the one shape that
		# survives being 20 pixels tall, which is most of what these are for.
		_part(st, _cyl(0.0, 0.26, 0.42, 6), Vector3(0.0, 0.42, 0.0), CONIFER_LEAF)
		_part(st, _cyl(0.0, 0.19, 0.34, 6), Vector3(0.0, 0.64, 0.0), CONIFER_LEAF)
		_part(st, _cyl(0.0, 0.11, 0.26, 6), Vector3(0.0, 0.85, 0.0), CONIFER_LEAF)
	st.generate_normals()
	return st.commit()


static func _cyl(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 0
	return c


# Appends a primitive's triangles at `at`, painted `col`. get_mesh_arrays() and
# not append_from(), because append_from copies the source's vertex data as it
# stands and there is no colour in it — the two-tone is the entire look.
static func _part(st: SurfaceTool, m: PrimitiveMesh, at: Vector3, col: Color) -> void:
	var arrays := m.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(col)
		st.add_vertex(verts[i] + at)


# --- placement ------------------------------------------------------------
# `world_map` is scenes/world/world.gd. Called every frame; almost every call
# does nothing but refresh the fog uniforms, which is the point.
func rebuild(world_map: Control) -> void:
	var w = world_map.get("world")
	if w == null:
		return
	var p = w.player()
	_mat.set_shader_parameter("player", p.position if p != null else Vector2(1e9, 1e9))
	_mat.set_shader_parameter("sight", w.sight_radius())
	_mat.set_shader_parameter("fog_remembered", Vector4(world_map.FOG_REMEMBERED.r,
		world_map.FOG_REMEMBERED.g, world_map.FOG_REMEMBERED.b, world_map.FOG_REMEMBERED.a))
	# The explored-and-on-screen cells, already computed for the ground mask and
	# memoised on exactly what it depends on. Riding that memo rather than
	# keeping a second one is what makes "rebuild only when the ground changed"
	# true without this file having to know what "changed" means.
	var cells: Dictionary = world_map._ground_set
	# How many of the forest cells get planted. Quantised to powers of two so
	# that panning across a boundary does not make the whole wood flicker
	# between two densities frame after frame.
	var want := maxi(1, int(cells.size() * world_map.FOREST_FRACTION_EST * TREES_PER_CELL))
	var keep := 1.0
	while keep > 0.03 and want * keep > MAX_TREES:
		keep *= 0.5
	var key := [world_map._ground_key, keep]
	if key == _key:
		return
	_key = key
	_plant(world_map, cells, keep)


func _plant(world_map: Control, cells: Dictionary, keep: float) -> void:
	# Thinning the stand makes what is left stand for more ground, so it grows
	# to match: coverage, not count, is what reads as a forest from far away.
	var grow: float = minf(1.0 / sqrt(maxf(keep, 0.03)), 3.2)
	var CELL: float = world_map.CELL
	var cluster_n: int = world_map.TILE_CLUSTER
	var dry: float = world_map.SHORE * 0.4
	var world = world_map.world
	var conifers: Array[Transform3D] = []
	var broadleaves: Array[Transform3D] = []
	var con_cols: PackedColorArray = PackedColorArray()
	var broad_cols: PackedColorArray = PackedColorArray()
	# Cheapest-and-most-rejecting test first, all the way down. Zoomed out this
	# walks tens of thousands of cells, and the order below is the difference
	# between a replant nobody notices and one that drops a frame:
	#   thin      one hash, rejects ~7 in 8 when it is doing anything at all
	#   forest    a hash plus a scan of the biome discs, but memoised per
	#             TILE_CLUSTER block, so ~1 in 64
	#   water     a scan of every lake, so it runs last and on almost nothing
	var forest := {}
	# The thinning roll is written out rather than called: it runs on every
	# explored cell on screen — tens of thousands of them zoomed out — and at
	# that count one GDScript call per cell is a measurable part of the replant.
	# It is scatter's own roll, not the map's, which is why it is free to be the
	# cheapest stable hash there is rather than World._rand()'s (that one builds
	# a Vector3i first, and is kept below for the rule that IS shared).
	var thin := int(keep * 1024.0)
	for cell in cells:
		if keep < 1.0 and absi(hash(cell)) % 1024 > thin:
			continue
		var block := Vector2i(int(floor(float(cell.x) / cluster_n)), int(floor(float(cell.y) / cluster_n)))
		var wood: bool = forest.get(block, false)
		if not forest.has(block):
			# The mask's own forest rule, read from world.gd — see the header.
			# O-biome: it is a threshold per biome now, so the whole rule lives
			# in block_wooded() rather than being a hash against a constant this
			# file could have read for itself. Still one call per block, not per
			# cell, which is what the memo above is for.
			wood = world_map.block_wooded(block)
			forest[block] = wood
		if not wood:
			continue
		# Nothing grows in the lake. water_depth() is a signed distance — it is
		# positive outside the bank — and the mask paints the bank as a ramp
		# half a SHORE either side rather than a hard edge, so a tree stops
		# where the ground the mask paints stops being dry.
		var centre := Vector2(cell.x + 0.5, cell.y + 0.5) * CELL
		if world.water_depth(centre) < dry:
			continue
		for k in TREES_PER_CELL:
			var jx: float = world_map._rand(cell, 20 + k) - 0.5
			var jz: float = world_map._rand(cell, 40 + k) - 0.5
			var at := centre + Vector2(jx, jz) * CELL * 0.85
			var r: float = world_map._rand(cell, 60 + k)
			var h: float = lerpf(TREE_HEIGHT.x, TREE_HEIGHT.y, r) * grow
			var xf := Transform3D(
				Basis.from_euler(Vector3(0.0, r * TAU, 0.0)).scaled(
					Vector3(h * lerpf(0.85, 1.15, jx + 0.5), h, h * lerpf(0.85, 1.15, jz + 0.5))),
				Vector3(at.x, 0.0, at.y))
			# A little brightness spread so a hillside of the same mesh does not
			# read as one repeated object.
			var shade := Color.WHITE * lerpf(0.78, 1.16, world_map._rand(cell, 80 + k))
			shade.a = 1.0
			if r > 0.62:
				broadleaves.append(xf)
				broad_cols.append(shade)
			else:
				conifers.append(xf)
				con_cols.append(shade)
	_fill(_conifer, conifers, con_cols)
	_fill(_broadleaf, broadleaves, broad_cols)


func _fill(bank: MultiMeshInstance3D, xforms: Array[Transform3D], cols: PackedColorArray) -> void:
	var mm := bank.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])


func tree_count() -> int:
	return _conifer.multimesh.instance_count + _broadleaf.multimesh.instance_count
