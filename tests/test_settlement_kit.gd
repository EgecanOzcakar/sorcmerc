# scenes/world/settlement_kit.gd — the modular settlement diorama.
#   godot --headless --path . -s tests/test_settlement_kit.gd
#
# Everything here asserts on plan(), the pure-data half, which is why this runs
# headless with no viewport: the whole point of splitting the file that way is
# that the layout is checkable without a renderer. build() gets one smoke test
# at the bottom (it needs meshes, but not a window).
extends SceneTree

const Kit = preload("res://scenes/world/settlement_kit.gd")
const Settlements3D = preload("res://scenes/world/settlements3d.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)


func _init() -> void:
	var factions: Array = Kit.PROFILES.keys()
	var kinds: Array = Kit.PLANS.keys()

	# --- coverage: the kit answers for exactly what the GLB tier answered for --
	for faction in factions:
		for kind in kinds:
			check(Kit.has(faction, kind), "%s/%s is covered" % [faction, kind])
			check(Settlements3D.MODELS.has(faction)
				and Settlements3D.MODELS[faction].has(kind),
				"%s/%s has a GLB too, so switching source can't lose a settlement"
					% [faction, kind])
	check(not Kit.has("gnoll", "town"), "an uncovered faction says so")
	check(not Kit.has("human", "metropolis"), "an uncovered kind says so")
	check(Kit.plan("gnoll", "town", "x").is_empty(), "and plans nothing for it")

	# --- determinism: same id, same village, forever -------------------------
	# This is what lets a seeded layout replace a fixed model at all. If it
	# drifted, a settlement would be a different shape every time the world
	# reloaded, which is worse than twelve identical blobs.
	for faction in factions:
		for kind in kinds:
			var a: Array = Kit.plan(faction, kind, "ashfell")
			var b: Array = Kit.plan(faction, kind, "ashfell")
			check(_same(a, b), "%s/%s is identical across two calls" % [faction, kind])
	check(not _same(Kit.plan("human", "town", "ashfell"),
		Kit.plan("human", "town", "deepmoor")),
		"two human towns are DIFFERENT towns (the thing 12 fixed GLBs never were)")
	check(not _same(Kit.plan("human", "town", "ashfell"),
		Kit.plan("orc", "town", "ashfell")),
		"the same id under another faction is another town")

	# --- the footprint and height contract -----------------------------------
	# Settlements3D positions a diorama at the settlement's map pixel and never
	# scales it, so these bounds ARE the on-screen size. A part escaping the
	# footprint is a building standing in the fog next to the town.
	for faction in factions:
		for kind in kinds:
			var p: Dictionary = Kit.PLANS[kind]
			var parts: Array = Kit.plan(faction, kind, "seed-%s" % faction)
			check(not parts.is_empty(), "%s/%s plans something" % [faction, kind])
			var top := 0.0
			var reach := 0.0
			var lowest := 1e9
			for part in parts:
				var pos: Vector3 = part["pos"]
				var size: Vector3 = part["size"]
				top = maxf(top, pos.y + size.y * 0.5)
				lowest = minf(lowest, pos.y - size.y * 0.5)
				reach = maxf(reach, Vector2(pos.x, pos.z).length() + maxf(size.x, size.z) * 0.5)
			var want: float = p["height"]
			check(absf(top - want) < want * 0.25,
				"%s/%s tops out near TARGET_HEIGHT %.1f (got %.1f)" % [faction, kind, want, top])
			check(lowest > -0.01,
				"%s/%s has nothing sunk below the ground plane (got %.2f)" % [faction, kind, lowest])
			check(reach < float(p["radius"]) * 1.35,
				"%s/%s stays inside its footprint (reach %.1f, radius %.1f)"
					% [faction, kind, reach, p["radius"]])
			# Same heights as the tier it replaces, so swapping `source` changes
			# how a settlement looks and not how big it is.
			check(is_equal_approx(want, float(Settlements3D.TARGET_HEIGHT[kind])),
				"%s PLANS height matches Settlements3D.TARGET_HEIGHT" % kind)

	# --- buildings don't stand inside each other -----------------------------
	# Rejection sampling is bounded (PLACE_TRIES), so this can't be "never
	# overlaps" — it's "the bound is generous enough that it practically never
	# does". Measured over 200 ids so a regression in the placement loop shows up
	# as a rate and not as one flaky id. At the time of writing the rate is 6
	# pairs in 27.5k (0.02%) with no city worse than a single pair; the bounds
	# below are loose around that, to catch a placement loop that has actually
	# broken rather than one that rolled badly.
	var worst := 0
	var overlaps := 0
	var pairs := 0
	for i in 200:
		var bodies: Array = []
		for part in Kit.plan("human", "city", "city-%d" % i):
			# Dwellings only. This used to filter on role == "wall" and got the
			# right answer by accident; the kitbash set broke the accident (a
			# stall's counter and a totem's skull are wall-coloured too), so the
			# plan now tags the thing people live in.
			if String(part.get("tag", "")) == "dwelling":
				bodies.append(part)
		var hits := 0
		for a in bodies.size():
			for b in range(a + 1, bodies.size()):
				var pa: Vector3 = bodies[a]["pos"]
				var pb: Vector3 = bodies[b]["pos"]
				var ra: float = maxf(bodies[a]["size"].x, bodies[a]["size"].z) * 0.5
				var rb: float = maxf(bodies[b]["size"].x, bodies[b]["size"].z) * 0.5
				pairs += 1
				if Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)) < (ra + rb) * 0.6:
					hits += 1
		overlaps += hits
		worst = maxi(worst, hits)
	check(worst <= 2, "no city has more than 2 badly-overlapping houses (worst %d)" % worst)
	check(float(overlaps) / float(pairs) < 0.005,
		"overlapping pairs stay under 0.5%% of all pairs (got %d/%d)" % [overlaps, pairs])

	# --- the budget this whole file exists for -------------------------------
	# The GLBs are 81.5k-82.9k triangles each, measured off the .glb accessors.
	for faction in factions:
		var tris: int = Kit.triangles(faction, "city", "capital")
		check(tris < 3000, "%s city is under 3k triangles (got %d, GLB is ~82k)" % [faction, tris])
		check(tris > 300, "%s city is not suspiciously empty (got %d)" % [faction, tris])
	check(Kit.triangles("human", "camp", "x") < Kit.triangles("human", "city", "x"),
		"a camp costs less than a city")

	# --- gates: a wall you can see through somewhere -------------------------
	# Counted on the RING, not over the whole plan: the kitbash set puts posts
	# inside the town as well now (a well's winch, a stall's uprights, a totem),
	# and those are not the palisade. Anything standing out at 0.9R or further
	# is, since the houses stop at 0.88R and the wall goes up at 1.02R.
	for faction in factions:
		var ring: float = float(Kit.PLANS["town"]["radius"]) * 0.9
		var posts := 0
		for part in Kit.plan(faction, "town", "gated"):
			var pos: Vector3 = part["pos"]
			if String(part["part"]) == "post" and Vector2(pos.x, pos.z).length() >= ring:
				posts += 1
		check(posts == 20, "%s town's palisade has a 2-post gate gap (got %d of 22)"
			% [faction, posts])
		# ...and the gate is a gate: two squared gateposts and a lintel standing
		# in the gap the ring left, which is what _gatehouse() puts there.
		var gate_parts := 0
		for part in Kit.plan(faction, "town", "gated"):
			var pos2: Vector3 = part["pos"]
			if String(part["part"]) == "box" and String(part["role"]) == "post" \
					and Vector2(pos2.x, pos2.z).length() >= ring:
				gate_parts += 1
		check(gate_parts == 3, "%s town's gate is two posts and a lintel (got %d)"
			% [faction, gate_parts])

	# --- build(): the nodes actually come out --------------------------------
	var node: Node3D = Kit.build("dwarf", "city", "khazduin")
	check(node != null and node.get_child_count() > 0, "build() returns a populated Node3D")
	check(node.get_child_count() == Kit.plan("dwarf", "city", "khazduin").size(),
		"one MeshInstance3D per planned part")
	var meshed := true
	var lowest_y := 1e9
	for child in node.get_children():
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null \
				or (child as MeshInstance3D).material_override == null:
			meshed = false
		lowest_y = minf(lowest_y, (child as MeshInstance3D).get_aabb().position.y
			+ (child as MeshInstance3D).position.y)
	check(meshed, "every part has a mesh and a material")
	check(lowest_y > -0.5, "the assembled diorama rests on y=0 (lowest %.2f)" % lowest_y)
	# Shared resources: the 40th settlement must not allocate a 40th box mesh.
	var other: Node3D = Kit.build("dwarf", "city", "khazduin")
	check(other.get_child(0).mesh == node.get_child(0).mesh,
		"two builds of the same settlement share mesh resources")
	node.free()
	other.free()

	# The rebuilt low-poly models are what the map draws (see settlements3d.gd's
	# header for why); the kit is the source with per-id variety and the one
	# that covers anything those twelve files do not, so it stays tested either
	# way. If this flips, it should flip deliberately.
	check(Settlements3D.source == "glb", "the rebuilt models are the default source")
	check(Settlements3D.MODELS.size() == Kit.PROFILES.size(),
		"...and the kit still answers for every faction they do")

	# --- the lodge (core/lodge.gd): a house, and a part group per room -------
	# Built in a fixed order whatever order the rooms were bought in, so the
	# same lodge is the same lodge across saves; each room's parts carry its
	# tag, so the map can be read back against the party's rooms.
	var rooms: Array = ["strongroom", "yard", "garden", "shrine", "maproom"]
	var shapes := {"strongroom": "box", "yard": "post", "garden": "disc", "shrine": "rock", "maproom": "cone"}
	for faction in factions:
		var prev: int = Kit.lodge_plan(faction, [], "riverhold").size()
		check(prev > 0, "%s lodge: a house with no rooms is still a house" % faction)
		var built: Array = []
		for room in rooms:
			built.append(room)
			var parts: Array = Kit.lodge_plan(faction, built, "riverhold")
			check(parts.size() > prev, "%s lodge grows with %s (%d -> %d)" % [faction, room, prev, parts.size()])
			prev = parts.size()
			check(parts.any(func(x): return String(x.get("tag", "")) == room and String(x["part"]) == shapes[room]),
				"%s lodge: %s is a %s" % [faction, room, shapes[room]])
		var lowest := 1e9
		var reach := 0.0
		for part in Kit.lodge_plan(faction, rooms, "riverhold"):
			var pos: Vector3 = part["pos"]
			var size: Vector3 = part["size"]
			lowest = minf(lowest, pos.y - size.y * 0.5)
			reach = maxf(reach, Vector2(pos.x, pos.z).length() + maxf(size.x, size.z) * 0.5)
		check(lowest > -0.01, "%s lodge has nothing sunk below the ground (got %.2f)" % [faction, lowest])
		check(reach < float(Kit.PLANS["town"]["radius"]), "%s lodge is smaller than a town (reach %.1f)" % [faction, reach])
		check(_same(Kit.lodge_plan(faction, rooms, "riverhold"), Kit.lodge_plan(faction, rooms, "riverhold")),
			"%s lodge is the same lodge twice" % faction)
	check(Kit.lodge_plan("human", rooms, "riverhold").filter(func(x): return String(x.get("tag", "")) == "yard" and String(x["part"]) == "post").size() == 5,
		"the yard is four posts and the training post")
	check(Kit.lodge_plan("human", rooms, "riverhold").filter(func(x): return String(x.get("tag", "")) == "garden").size() == 3,
		"the garden is three beds")
	check(_same(Kit.lodge_plan("human", rooms, "riverhold"),
		Kit.lodge_plan("human", ["maproom", "shrine", "garden", "yard", "strongroom"], "riverhold")),
		"the rooms stand where they stand whatever order they were bought in")
	check(not _same(Kit.lodge_plan("human", [], "riverhold"), Kit.lodge_plan("human", [], "ashfell")), "two lodges are two houses")
	check(Kit.lodge_plan("gnoll", rooms, "x").is_empty(), "no lodge among a people the kit does not dress")
	var lodge: Node3D = Kit.build_lodge("human", rooms, "riverhold")
	check(lodge != null and lodge.get_child_count() == Kit.lodge_plan("human", rooms, "riverhold").size(),
		"build_lodge(): one MeshInstance3D per planned part")
	lodge.free()

	print("test_settlement_kit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		for key in ["part", "role", "shade", "yaw", "tilt"]:
			if a[i][key] != b[i][key]:
				return false
		if not (a[i]["pos"] as Vector3).is_equal_approx(b[i]["pos"]):
			return false
		if not (a[i]["size"] as Vector3).is_equal_approx(b[i]["size"]):
			return false
	return true
