# What the biome layer (#169) looks like: the ground in each of the three
# kinds with the HUD bar naming it, and then the whole large map from
# overhead with its fog lifted, where the woods and the marshes are the discs
# core/world.gd placed. The roaming bands are cleared first — this is a
# picture of the ground, and a dozen band labels over it is not.
#
# Not headless — the capture hangs without a real rendering driver:
#   godot --path . -s tests/shot_biomes.gd
extends SceneTree

const Regions = preload("res://core/regions.gd")

# A spot inside the disc but off any town's doorstep, so the shot is ground
# and not a diorama and no visit card opens over it.
func _clear_spot(world, at: Vector2, radius: float) -> Vector2:
	var best := at
	var far := 0.0
	for a in 12:
		for f in [0.0, 0.45, 0.7]:
			var p: Vector2 = at + Vector2(radius * f, 0).rotated(TAU * a / 12.0)
			var near := 1e9
			for s in world.settlements:
				near = minf(near, p.distance_to(s.position))
			if near > far:
				far = near
				best = p
	return best


# The forest rule tallied over every block on the map, bucketed by the kind of
# ground under it: what share of each biome actually comes up wood.
func _wooded_by_kind(w, world, a: Vector2, ext: float) -> Dictionary:
	var block := 15.0 * 8.0   # CELL * TILE_CLUSTER: the unit the forest rule works in
	var tally := {}
	var span := int(ext / block)
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			var b := Vector2i(floori(a.x / block) + i, floori(a.y / block) + j)
			var centre: Vector2 = (Vector2(b) + Vector2(0.5, 0.5)) * block
			if world.is_water(centre):
				continue
			var kind: String = world.biome_at(centre)
			var t: Array = tally.get(kind, [0, 0])
			t[0] += 1
			if w.block_wooded(b):
				t[1] += 1
			tally[kind] = t
	return tally


func _init() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	w.world_size = "large"
	root.add_child(w)
	for i in 40:
		await process_frame
	var world = w.world
	world.clock.pause()
	for p in world.parties.duplicate():
		if not p.is_player:
			world.parties.erase(p)

	# The mask only paints ground the party has seen, so walk the fog off the
	# whole map first: one waypoint per vision radius, the grid centred where
	# Regions measures the map from.
	var a: Vector2 = Regions.anchor(world)
	var ext: float = Regions.extent(world) + 300.0
	var y := -ext
	while y <= ext:
		var x := -ext
		while x <= ext:
			world.reveal(a + Vector2(x, y))
			x += 240.0
		y += 240.0
	print("revealed %d waypoints over %.0f units" % [world.explored.size(), ext * 2.0])

	# The ground itself, in each kind, with the bar that names it.
	for spot in [{"at": Vector2(-600, -900), "r": 420.0, "name": "woods"},
			{"at": Vector2(250, 900), "r": 300.0, "name": "marsh"},
			{"at": Vector2(-60, -260), "r": 220.0, "name": "downs"}]:
		var at: Vector2 = _clear_spot(world, spot["at"], spot["r"])
		var p = world.player()
		p.position = at
		world.reveal(at)
		w.center_on(at)
		w.set_zoom(1.15)
		await _shoot(w, "res://biome_%s.png" % spot["name"])
		print("  %-6s %s: %s | %d trees in view"
			% [spot["name"], str(at.round()), w._region_lbl.text, w._view.scatter.tree_count()])

	# And the map from overhead: the tree line IS the biome layer, drawn.
	for kind in _wooded_by_kind(w, world, a, ext):
		var t: Array = _wooded_by_kind(w, world, a, ext)[kind]
		print("  %-6s %4d blocks of dry ground, %3.0f%% of them wood" % [kind, t[0], 100.0 * t[1] / maxf(1.0, t[0])])
	w.center_on(a)
	w.set_zoom(0.25)
	w.tilt_by(90.0)
	await _shoot(w, "res://biome_map.png")

	# And the crossing: open downs into the Silverleaf woods, the bar naming
	# the ground as the party walks into it.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_biome_walk"))
	w.tilt_by(-90.0)
	w.set_zoom(1.0)
	var p = world.player()
	p.position = Vector2(-180, -560)
	world.set_goal(p, Vector2(-560, -880))
	world.clock.resume()
	for i in 36:
		for f in 3:
			await process_frame
		world.reveal(p.position)
		w.center_on(p.position)
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://shots_biome_walk/walk_%02d.png" % i)
	print("walked into the woods: %s" % w._region_lbl.text)
	quit()


func _shoot(w, path: String) -> void:
	for i in 14:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path.get_file())
