# Asserts on the pure hex math.
#   flatpak run org.godotengine.Godot --headless --path . -s tests/test_hex.gd
extends SceneTree

const Hex = preload("res://core/hex.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var o := Vector2i.ZERO

	check(Hex.distance(o, o) == 0, "distance to self is 0")
	for d in Hex.DIRS:
		check(Hex.distance(o, d) == 1, "each direction is distance 1")
	check(Hex.distance(Vector2i(0, 0), Vector2i(3, -1)) == 3, "known distance 3")
	check(Hex.distance(Vector2i(2, -1), Vector2i(-1, 3)) == Hex.distance(Vector2i(-1, 3), Vector2i(2, -1)), "distance symmetric")

	check(Hex.neighbors(o).size() == 6, "6 neighbours")

	check(Hex.direction_to(o, Vector2i(5, 0)) == Vector2i(1, 0), "direction_to east")
	check(Hex.direction_to(Vector2i(2, 2), Vector2i(2, -2)) == Vector2i(0, -1), "direction_to north")

	# cone: length 1 is a small wedge, length 2 strictly larger, never the origin
	var c1 := Hex.cone(o, Vector2i(1, 0), 1)
	var c2 := Hex.cone(o, Vector2i(1, 0), 2)
	check(not (o in c1), "cone excludes origin")
	check(c1.size() >= 1 and c1.size() <= 3, "cone len 1 is a wedge (got %d)" % c1.size())
	check(c2.size() > c1.size(), "cone len 2 larger than len 1")
	for h in c2:
		check(Hex.distance(o, h) <= 2, "cone hex within length")

	# reachable: open board, all hexes passable
	var open := func(_p): return true
	var r := Hex.reachable(open, o, 2, [])
	check(r[o] == 0, "start cost 0")
	check(r.size() == 19, "2-step flood on open grid = 19 hexes (got %d)" % r.size())
	# a blocked hex is not steppable but you can still end next to it
	var blk := [Vector2i(1, 0)]
	var r2 := Hex.reachable(open, o, 1, blk)
	check(not r2.has(Vector2i(1, 0)), "blocked hex not reachable")
	check(r2.has(Vector2i(0, 1)), "other neighbours still reachable")
	# walls: passable only for |q|<=1
	var wall := func(p): return absi(p.x) <= 1
	var r3 := Hex.reachable(wall, o, 5, [])
	for h in r3:
		check(absi(h.x) <= 1, "flood respects impassable hexes")

	check(Hex.line(o, Vector2i(3, 0)).size() == 4, "line inclusive endpoints")
	check(Hex.from_pixel(Hex.to_pixel(Vector2i(2, -1), 20.0), 20.0) == Vector2i(2, -1), "pixel round-trips")

	print("test_hex: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
