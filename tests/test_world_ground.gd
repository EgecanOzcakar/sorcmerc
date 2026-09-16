# Issue #31: "fps drop in overworld map".
#
# The ground loop walked every cell of the VIEWPORT every frame and asked
# world.is_explored() about each one — 3.7us a cell measured, since that folds
# in a scan of every settlement — then, for the ones that came back yes,
# recomputed the tile from world.water_depth(), another linear scan, at 4.8us a
# cell. At 3840x2118 and zoom 2.5 that is 9,207 cells, i.e. 35-80ms of pure
# GDScript before a single tile is drawn.
#
# It walks the explored ground now instead: out from each remembered waypoint
# and each settlement beacon, clipped to the viewport. This test is mostly
# about the claim that makes that legal — the set it arrives at is exactly the
# set is_explored() would have said yes to.
#
#   godot --headless --path . -s tests/test_world_ground.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	main.world_size = "large"
	root.add_child(main)
	for i in 10:
		await process_frame
	main.size = Vector2(1280, 800)
	main._process(0.016)
	await process_frame

	var p = main.world.player()
	check(p != null, "there is a player party")

	# A real walk: a trail with bends in it, not one blob.
	for i in 120:
		main.world.reveal(p.position + Vector2(i * 18.0, sin(i * 0.2) * 260.0))
	check(main.world.explored.size() > 4, "the trail has waypoints on it (%d)" % main.world.explored.size())

	var CELL: float = main.CELL
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for corner in [Vector2.ZERO, Vector2(main.size.x, 0), Vector2(0, main.size.y), main.size]:
		var w: Vector2 = main._unpix(corner)
		mn = mn.min(w); mx = mx.max(w)
	var i0 := int(floor(mn.x / CELL)); var i1 := int(ceil(mx.x / CELL))
	var j0 := int(floor(mn.y / CELL)); var j1 := int(ceil(mx.y / CELL))

	# --- the claim: same set, reached from the other end -----------------
	var fast: Dictionary = main._visible_ground(i0, i1, j0, j1)
	var slow := {}
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			if main.world.is_explored(Vector2(i + 0.5, j + 0.5) * CELL):
				slow[Vector2i(i, j)] = true
	check(fast.size() == slow.size(),
		"the walk finds as many cells as the per-cell scan (%d vs %d)" % [fast.size(), slow.size()])
	var missing := 0
	var extra := 0
	for c in slow:
		if not fast.has(c): missing += 1
	for c in fast:
		if not slow.has(c): extra += 1
	check(missing == 0, "...and misses none of them (%d missing)" % missing)
	check(extra == 0, "...and invents none (%d extra)" % extra)
	check(fast.size() > 0 and fast.size() < (i1 - i0 + 1) * (j1 - j0 + 1),
		"a partly-walked map is partly lit (%d of %d cells)" % [fast.size(), (i1 - i0 + 1) * (j1 - j0 + 1)])

	# A settlement lights its own beacon with nothing walked at all.
	main.world.explored.clear()
	main._ground_key = []            # the memo is keyed on the trail's length; clear() keeps it
	var beacon: Dictionary = main._visible_ground(i0, i1, j0, j1)
	var beacon_slow := {}
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			if main.world.is_explored(Vector2(i + 0.5, j + 0.5) * CELL):
				beacon_slow[Vector2i(i, j)] = true
	check(beacon.size() == beacon_slow.size(),
		"settlement beacons agree too (%d vs %d)" % [beacon.size(), beacon_slow.size()])

	# --- the tile a cell draws is stable, and cached ----------------------
	var probe := Vector2i(3, 7)
	var first: Vector2i = main._ground_tile(probe)
	check(main._tile_cache.has(probe), "the tile pick is remembered")
	check(main._ground_tile(probe) == first, "...and comes back the same")
	check(first.x in [0, 1, 2], "...naming one of the three sheets (%d)" % first.x)
	# It has to be the same answer the old per-frame arithmetic gave.
	var center := Vector2(probe.x + 0.5, probe.y + 0.5) * CELL
	var cl: Vector2i = main._cluster(probe, main.TILE_CLUSTER)
	var wet: float = 0.5 - main.world.water_depth(center) / (main.SHORE * 2.0)
	var want_kind := 0
	var want_pool: Array = main.GRASS
	if main._rand(probe, 9) < wet:
		want_kind = 2; want_pool = main.WATER
	elif main._rand(cl, 5) > main.WOODED:
		want_kind = 1; want_pool = main.FOREST
	check(first.x == want_kind, "the cached sheet is the one the arithmetic picks")
	check(first.y == want_pool[int(main._rand(cl, 1) * want_pool.size()) % want_pool.size()],
		"...and so is the tile in it")
	check(main._tile_sheet(0) == main._terrain_tex and main._tile_sheet(1) == main._forest_tex
		and main._tile_sheet(2) == main._water_tex, "the sheet ids map to the right textures")

	# --- the memo answers the same thing twice ---------------------------
	main.world.explored.append(p.position + Vector2(4000, 4000))   # far off screen
	var again: Dictionary = main._visible_ground(i0, i1, j0, j1)
	check(again.size() == beacon.size(), "a waypoint nowhere near the screen changes nothing")
	var moved: Dictionary = main._visible_ground(i0 + 400, i1 + 400, j0, j1)
	check(moved.size() != beacon.size() or beacon.is_empty(),
		"...but panning somewhere else does not hand back the old answer")

	# --- the ground shader's mask: R forest, G water, B explored, per cell ----
	main.world.add_water(Vector2(3000, 3000), 120.0)
	var lake_cell := Vector2i(int(3000.0 / main.CELL), int(3000.0 / main.CELL))
	var a0 := lake_cell.x - 20; var a1 := lake_cell.x + 20
	var b0 := lake_cell.y - 20; var b1 := lake_cell.y + 20
	main.world.explored.append(Vector2(3000, 3000))
	var cells: Dictionary = main._visible_ground(a0, a1, b0, b1)
	var tex: ImageTexture = main._build_mask(a0, a1, b0, b1, 1, cells)
	var img := tex.get_image()
	check(img.get_width() == 41 and img.get_height() == 41, "one texel per cell (%dx%d)" % [img.get_width(), img.get_height()])
	var mid := img.get_pixel(20, 20)
	check(mid.g > 0.99 and mid.r == 0.0 and mid.b > 0.99, "the lake's middle is water, not forest, and explored (%s)" % str(mid))
	var far := img.get_pixel(0, 0)
	check(far.g == 0.0, "the corner, 20 cells out, is dry")
	check(main._build_mask(a0, a1, b0, b1, 2, cells).get_image().get_width() == 21, "step 2 halves the mask")
	# a pan inside the padded box rebuilds nothing; leaving it does
	main._pan = Vector2.ZERO
	main.queue_redraw()
	await process_frame
	var key0: Array = main._mask_key.duplicate()
	main._pan += Vector2(15, 5)
	main.queue_redraw()
	await process_frame
	check(main._mask_key == key0, "a small pan keeps the mask (%s)" % str(key0))
	main._pan += Vector2(4000, 1500)
	main.queue_redraw()
	await process_frame
	check(main._mask_key != key0, "a long pan rebuilds it")

	print("test_world_ground: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
