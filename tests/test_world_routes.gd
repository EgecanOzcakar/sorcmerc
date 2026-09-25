# #231 — the route network (core/world_routes.gd). The model only, headless.
#   godot --headless --path . -s tests/test_world_routes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const Landmarks = preload("res://core/landmarks.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# --- every shipped map ---------------------------------------------------------

func _shipped(w, name: String) -> void:
	var net = WorldRoutes.build(w)
	var pid := func(kind, id): return WorldRoutes.poi_id(kind, id)
	# Every place is a node, where the place is, and known exactly when the
	# issue says it is obvious.
	for s in w.settlements:
		var n: Dictionary = net.nodes.get(pid.call("settlement", s.id), {})
		check(not n.is_empty() and n["position"] == s.position and n["known"], "%s: %s is a known node" % [name, s.id])
	for l in w.lairs:
		var n: Dictionary = net.nodes.get(pid.call("lair", l.id), {})
		check(not n.is_empty() and n["position"] == l.position and n["known"], "%s: lair %s is a known node" % [name, l.id])
	for m in w.landmarks:
		var n: Dictionary = net.nodes.get(pid.call("landmark", m.id), {})
		check(not n.is_empty() and n["known"] == m.found, "%s: landmark %s is a node, hidden until found" % [name, m.id])
	# The known roads join every town and every lair; every edge together
	# reaches every landmark too.
	var home: String = pid.call("settlement", w.settlements[0].id)
	var known: Array = net.reachable(home)
	for s in w.settlements:
		check(known.has(pid.call("settlement", s.id)), "%s: %s reachable on known roads" % [name, s.id])
	for l in w.lairs:
		check(known.has(pid.call("lair", l.id)), "%s: %s reachable on known roads" % [name, l.id])
	for m in w.landmarks:
		var id: String = pid.call("landmark", m.id)
		check(not known.has(id), "%s: %s not reachable before it is found" % [name, m.id])
		check(not net.path(home, id, false).is_empty(), "%s: %s hangs off the network" % [name, m.id])
	# Tiers: a road joins towns (or forks cut into roads), a track ends at a
	# lair, a path at a landmark; paths and byways start hidden and say where
	# they are noticed from; nothing else is hidden.
	for eid in net.edges:
		var e: Dictionary = net.edges[eid]
		var ka: String = net.nodes[e["a"]]["kind"]
		var kb: String = net.nodes[e["b"]]["kind"]
		match String(e["kind"]):
			"road":
				check(ka in ["settlement", "fork"] and kb in ["settlement", "fork"], "%s: road %s joins towns" % [name, eid])
				check(e["known"], "%s: road %s is known" % [name, eid])
			"track":
				check(e["known"], "%s: track %s is known" % [name, eid])
			"path", "byway":
				check(not e["known"], "%s: %s %s starts hidden" % [name, e["kind"], eid])
				check(not (e["notice"] as Array).is_empty(), "%s: %s is noticed from somewhere" % [name, eid])
				for n in e["notice"]:
					check(n == e["a"] or n == e["b"], "%s: %s is noticed from one of its own ends" % [name, eid])
		check(e["length"] > 0.0, "%s: %s has length" % [name, eid])
		# Dry the whole way: sampled every 10 units, the step World walks in.
		var pts: PackedVector2Array = e["points"]
		var wet := false
		for i in range(1, pts.size()):
			var seg := pts[i - 1].distance_to(pts[i])
			var d := 0.0
			while d <= seg and not wet:
				wet = w.water_depth(pts[i - 1].lerp(pts[i], d / maxf(seg, 0.001))) < -1.0
				d += 10.0
		check(not wet, "%s: %s stays out of the water" % [name, eid])
	for kind in ["track", "path"]:
		check(net.stats()[kind] > 0, "%s: has %ss" % [name, kind])
	check(net.stats()["road"] >= w.settlements.size() - 1, "%s: at least a tree of roads" % name)
	# Nothing crosses anything without a node where it does.
	var ids: Array = net.edges.keys()
	var crossings := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			crossings += _crossings(net.edges[ids[i]], net.edges[ids[j]])
	check(crossings == 0, "%s: no edge crosses another (%d)" % [name, crossings])
	# The same map is the same network, and a save carries it whole.
	var again = WorldRoutes.build(w)
	check(JSON.stringify(again.to_dict()) == JSON.stringify(net.to_dict()), "%s: build is deterministic" % name)
	var back = WorldRoutes.from_dict(JSON.parse_string(JSON.stringify(net.to_dict())))
	check(JSON.stringify(back.to_dict()) == JSON.stringify(net.to_dict()), "%s: survives a JSON round trip" % name)
	var far: String = pid.call("lair", w.lairs[-1].id)
	check(is_equal_approx(float(back.path(home, far)["length"]), float(net.path(home, far)["length"])), "%s: a reloaded network walks the same" % name)

func _crossings(e: Dictionary, f: Dictionary) -> int:
	var p: PackedVector2Array = e["points"]
	var q: PackedVector2Array = f["points"]
	var n := 0
	for i in range(1, p.size()):
		for j in range(1, q.size()):
			var hit = Geometry2D.segment_intersects_segment(p[i - 1], p[i], q[j - 1], q[j])
			if hit == null:
				continue
			# Meeting at either edge's own end — a shared node, or where a spur
			# joins — is a junction.
			if hit.distance_to(p[0]) < 1.0 or hit.distance_to(p[-1]) < 1.0 \
					or hit.distance_to(q[0]) < 1.0 or hit.distance_to(q[-1]) < 1.0:
				continue
			n += 1
	return n

# --- the shape, on maps small enough to reason about ---------------------------

func _line_of_towns() -> void:
	# Three towns in a row: two roads, and none from end to end past the middle.
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(400, 0), "elf"))
	w.add_settlement(World.Settlement.new("c", Vector2(800, 0), "dwarf"))
	var net = WorldRoutes.build(w)
	check(net.edges.has(WorldRoutes.edge_id("settlement:a", "settlement:b")), "line: a-b road")
	check(net.edges.has(WorldRoutes.edge_id("settlement:b", "settlement:c")), "line: b-c road")
	check(not net.edges.has(WorldRoutes.edge_id("settlement:a", "settlement:c")), "line: no a-c road past b")
	var way: Dictionary = net.path("settlement:a", "settlement:c")
	check(way["nodes"] == ["settlement:a", "settlement:b", "settlement:c"], "line: a to c goes through b")
	check(is_equal_approx(float(way["length"]), 800.0), "line: 800 units")
	check((way["points"] as PackedVector2Array)[0] == Vector2(0, 0) and (way["points"] as PackedVector2Array)[-1] == Vector2(800, 0), "line: points run a to c")
	var back: Dictionary = net.path("settlement:c", "settlement:a")
	check((back["points"] as PackedVector2Array)[0] == Vector2(800, 0), "line: walked backwards, the points are reversed")

func _square() -> void:
	# Four towns on a square: the four sides are roads and neither diagonal is
	# (each has two towns nearer both its ends) — the loop a neighbourhood graph
	# makes once there are enough towns for a loop to be the short way round.
	# Three never make one: a triangle's longest side always has the third town
	# nearer both its ends.
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(500, 0), "elf"))
	w.add_settlement(World.Settlement.new("c", Vector2(500, 500), "dwarf"))
	w.add_settlement(World.Settlement.new("d", Vector2(0, 500), "human"))
	var net = WorldRoutes.build(w)
	check(net.stats()["road"] == 4, "square: four roads (%d)" % net.stats()["road"])
	check(not net.edges.has(WorldRoutes.edge_id("settlement:a", "settlement:c")), "square: no diagonal")
	check(net.neighbours("settlement:a").size() == 2, "square: two ways out of every town")

func _spurs_and_forks() -> void:
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(1000, 0), "elf"))
	w.add_lair(World.Lair.new("den", Vector2(500, 300), "goblinoid"))
	# Beside the road near its middle: a fork is cut there.
	w.add_landmark(World.Landmark.new("landmark-ruins-0", "ruins", Vector2(300, -150)))
	# Right by town a: it hangs from the town, not from a fork beside it.
	w.add_landmark(World.Landmark.new("landmark-stones-1", "stones", Vector2(10, 120)))
	# A hut: its path has to be searched for.
	w.add_landmark(World.Landmark.new("landmark-hut-2", "hut", Vector2(800, -200)))
	var net = WorldRoutes.build(w)
	var den: Dictionary = net.node_for("lair", "den")
	check(den["known"], "spurs: the lair is known")
	var track: Array = net.edges.values().filter(func(e): return e["kind"] == "track")
	check(track.size() == 1, "spurs: one track")
	var fork: String = track[0]["a"] if track[0]["b"] == "lair:den" else track[0]["b"]
	check(net.nodes[fork]["kind"] == "fork" and is_equal_approx(net.nodes[fork]["position"].x, 500.0), "spurs: the track leaves from a fork at x=500 (%s)" % fork)
	check(not net.path("settlement:a", "lair:den").is_empty(), "spurs: the lair is walkable at once")
	var stones := WorldRoutes.edge_id("settlement:a", "landmark:landmark-stones-1")
	check(net.edges.has(stones), "spurs: a landmark by the gate hangs from the town")
	var ruins_edge := ""
	for eid in net.edges:
		if net.edges[eid]["b"] == "landmark:landmark-ruins-0" or net.edges[eid]["a"] == "landmark:landmark-ruins-0":
			ruins_edge = eid
	check(ruins_edge != "" and not net.edges[ruins_edge]["known"], "spurs: the ruins' path is hidden")
	check(net.path("settlement:a", "landmark:landmark-ruins-0").is_empty(), "spurs: no known way to the ruins yet")
	var ruins_fork: String = net.edges[ruins_edge]["notice"][0]
	check(net.nodes[ruins_fork]["kind"] == "fork", "spurs: the ruins' path leaves a fork")
	# Walking the road: nothing seen far from the fork, the path seen at it,
	# and once only.
	check(net.notice(Vector2(150, 0)).is_empty(), "spurs: nothing noticed away from a fork")
	var seen: Array = net.notice(net.nodes[ruins_fork]["position"] + Vector2(10, 0))
	check(seen.has(ruins_edge), "spurs: passing the fork reveals the path")
	check(net.nodes["landmark:landmark-ruins-0"]["known"], "spurs: ...and the ruins")
	check(not net.path("settlement:a", "landmark:landmark-ruins-0").is_empty(), "spurs: the ruins are walkable now")
	check(net.notice(net.nodes[ruins_fork]["position"]).is_empty(), "spurs: noticed once")
	# The hut: walking past is not enough; a search from the fork is.
	var hut_edge := ""
	for eid in net.edges:
		if "landmark:landmark-hut-2" in [net.edges[eid]["a"], net.edges[eid]["b"]]:
			hut_edge = eid
	check(net.edges[hut_edge]["search"], "spurs: the hut's path is a search")
	var hut_from: String = net.edges[hut_edge]["notice"][0]
	var at: Vector2 = net.nodes[hut_from]["position"]
	check(not net.notice(at).has(hut_edge), "spurs: walking past does not find the hut")
	check(net.searchable(at) == [hut_edge], "spurs: ...but a search could")
	check(net.searchable(Vector2(-500, -500)).is_empty(), "spurs: nothing to search for out of reach")
	check(net.reveal(hut_edge), "spurs: the search finds it")
	check(not net.reveal(hut_edge), "spurs: and finding it twice changes nothing")
	check(net.searchable(at).is_empty(), "spurs: nothing left to search for there")
	# From partway down a road, the way on or back, whichever is shorter.
	var mid := Vector2(650, 5)
	var way: Dictionary = net.path_from(mid, "settlement:b")
	check((way["points"] as PackedVector2Array)[0] == mid, "spurs: path_from starts where the company stands")
	check((way["points"] as PackedVector2Array)[-1] == Vector2(1000, 0), "spurs: ...and ends at the town")
	check(absf(float(way["length"]) - 355.0) < 1.0, "spurs: ...on, not back (%.1f)" % float(way["length"]))
	var poly := 0.0
	var pts: PackedVector2Array = way["points"]
	for i in range(1, pts.size()):
		poly += pts[i - 1].distance_to(pts[i])
	check(absf(poly - float(way["length"])) < 0.5, "spurs: the length is the polyline's")
	# nearest_node never answers with a fork, or a place not yet known.
	check(net.nearest_node(Vector2(500, 10)) != fork, "spurs: nearest_node skips forks")

func _leads() -> void:
	# A landmark hung off another landmark's hidden path: a lead to the far
	# one reveals the whole hidden stretch back to the road.
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(1000, 0), "elf"))
	w.add_landmark(World.Landmark.new("landmark-ruins-0", "ruins", Vector2(500, 200)))
	w.add_landmark(World.Landmark.new("landmark-shrine-1", "shrine", Vector2(500, 420)))
	var net = WorldRoutes.build(w)
	check(net.path("settlement:a", "landmark:landmark-shrine-1").is_empty(), "leads: the shrine is not known")
	var shown: Array = net.reveal_node("landmark:landmark-shrine-1")
	check(shown.size() == 2, "leads: both hidden stretches revealed (%d)" % shown.size())
	check(not net.path("settlement:a", "landmark:landmark-shrine-1").is_empty(), "leads: the shrine is walkable")
	check(net.nodes["landmark:landmark-ruins-0"]["known"], "leads: and the ruins on the way are known")

func _attach_later() -> void:
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(1000, 0), "elf"))
	var net = WorldRoutes.build(w)
	var before: Dictionary = net.path("settlement:a", "settlement:b")
	var id: String = net.attach(w, "lair", "child", Vector2(400, 250), true)
	check(id == "lair:child" and net.nodes.has(id), "attach: the new lair is a node")
	check(not net.path("settlement:a", id).is_empty(), "attach: ...on a known track")
	check(is_equal_approx(float(net.path("settlement:a", "settlement:b")["length"]), float(before["length"])),
		"attach: the road between the towns is the same length")
	check(net.attach(w, "lair", "child", Vector2(400, 250), true) == id and net.stats()["track"] == 1, "attach: twice is once")
	var back = WorldRoutes.from_dict(net.to_dict())
	var again: String = back.attach(w, "lair", "second", Vector2(600, -250), true)
	check(not back.nodes[again].is_empty() and back.stats()["forks"] == 2 and back.nodes.has("fork:1"),
		"attach: after a load the next fork gets a fresh number")

func _water() -> void:
	# A lake between two towns: the road goes round it.
	var w := World.new()
	w.add_settlement(World.Settlement.new("a", Vector2(0, 0), "human"))
	w.add_settlement(World.Settlement.new("b", Vector2(800, 0), "elf"))
	w.add_water(Vector2(400, 0), 120.0)
	var net = WorldRoutes.build(w)
	var e: Dictionary = net.edges[WorldRoutes.edge_id("settlement:a", "settlement:b")]
	check((e["points"] as PackedVector2Array).size() > 2, "water: the road bends round the lake")
	check(float(e["length"]) > 800.0, "water: and is longer for it (%.0f)" % float(e["length"]))

func _init() -> void:
	var scene = load("res://scenes/world/world.tscn").instantiate()
	_shipped(scene._small_world(), "small")
	scene.free()
	_shipped(LargeWorld.build(), "large")
	for s in [1, 2, 3, 7, 42]:
		_shipped(ProceduralWorld.build(s), "proc%d" % s)
	_line_of_towns()
	_square()
	_spurs_and_forks()
	_leads()
	_attach_later()
	_water()
	print("test_world_routes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
