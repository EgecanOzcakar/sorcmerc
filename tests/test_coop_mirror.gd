# Issue #133: the guest's map, between two of the host's deltas.
#
# The host sends where everyone stands twice a second (Coop.map_delta, forwarded
# and never logged). The guest used to write each one straight onto the map,
# which made the road move at the rate the packets arrived: a step, half a
# second of nothing, another step. What crosses the wire is right; what the
# screen does with it between arrivals was the bug.
#
# So this checks the thing the player was complaining about — that the party
# moves on the frames BETWEEN deltas, in one direction, and arrives where the
# host said rather than somewhere past it.
#   godot --headless --path . -s tests/test_coop_mirror.gd
extends SceneTree

const Coop = preload("res://core/coop.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# Only the two fields _spectate() reads off a link.
class StubLink extends RefCounted:
	var role := "guest"
	var code := "TESTRM"
	var map_latest: Dictionary = {}
	var visit_latest: Dictionary = {}
	var world_pending: Dictionary = {}
	var owners_latest: Dictionary = {}
	var arrivals := 1
	func send(_m: Dictionary) -> void: pass
	func take() -> Array: return []
	func pump() -> void: pass
	func open() -> bool: return true
	func other_here() -> bool: return true
	func close() -> void: pass

func _init() -> void:
	var link = StubLink.new()
	Coop.link = link
	var screen = load("res://scenes/world/world.tscn").instantiate()
	screen.spectator = true
	root.add_child(screen)
	for _i in 10:
		await process_frame

	var p = screen.world.player()
	check(p != null, "the mirrored map has a player party on it")
	var start := Vector2(100, 100)
	var next := Vector2(140, 100)

	# The first delta on a fresh screen has nothing to glide from: it snaps.
	screen._aim_mirror(_delta(screen, p, start, 600.0))
	screen._draw_mirror()
	check(p.position.is_equal_approx(start), "the first delta snaps: %s" % str(p.position))

	# Half a second later, a second delta 40 units along. That interval is the
	# span the glide is paced over, so the party should now cross it over the
	# next half second of frames rather than in one.
	screen._mirror_age = 0.5
	screen._aim_mirror(_delta(screen, p, next, 630.0))
	screen._draw_mirror()
	check(p.position.is_equal_approx(start), "the second delta starts where the map already was")

	var seen: Array = []
	for _i in 5:
		screen._mirror_age += 0.1
		screen._draw_mirror()
		seen.append(p.position.x)
	check(seen.size() == 5, "five frames of the half second between deltas")
	var moved_every_frame := true
	var monotonic := true
	for i in seen.size():
		if i > 0 and seen[i] <= seen[i - 1]:
			moved_every_frame = false
		if seen[i] < start.x - 0.01 or seen[i] > next.x + 0.01:
			monotonic = false
	check(moved_every_frame, "it moves on every frame between deltas, not on arrival: %s" % str(seen))
	check(monotonic, "and never past where the host said it was: %s" % str(seen))
	check(is_equal_approx(seen[-1], next.x), "by the next delta's due time it is there: %f" % seen[-1])
	check(is_equal_approx(screen.world.clock.elapsed, 630.0), "the clock arrives with it: %f" % screen.world.clock.elapsed)

	# A delta that never comes leaves the map on the last place the host
	# actually was. Overshooting would draw the party somewhere it has not been.
	for _i in 30:
		screen._mirror_age += 0.1
		screen._draw_mirror()
	check(p.position.is_equal_approx(next), "a missing delta stops the glide, it does not extrapolate: %s" % str(p.position))
	check(is_equal_approx(screen.world.clock.elapsed, 630.0), "nor runs the clock on past it")

	# Same screen, same stream: the ordinary case is a glide, never a snap.
	screen._mirror_age = 0.5
	screen._aim_mirror(_delta(screen, p, Vector2(180, 100), 660.0))
	screen._draw_mirror()
	check(p.position.is_equal_approx(next), "every delta after the first glides")

	Coop.link = null
	screen.queue_free()
	await process_frame
	print("test_coop_mirror: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# What core/coop.gd's map_delta() puts on the wire, with the player party moved
# to `at` — every other party stays where the map already has it.
func _delta(screen, player, at: Vector2, elapsed: float) -> Dictionary:
	var d := {}
	for q in screen.world.parties:
		d[q.id] = [at.x, at.y] if q == player else [q.position.x, q.position.y]
	return {"t": "map", "elapsed": elapsed, "paused": false, "at": d}
