# The overworld's camera, now that it turns.
#
# The refactor that made the map 3D rests on one claim: World._iso() was never
# an approximation of a camera, it WAS one — an orthographic camera at yaw
# ISO_YAW and pitch asin(ISO_SQUASH) — so making those two angles variable
# turns the map without disturbing anything built on _pix()/_unpix(). Every
# mechanism on the map is built on those two: click-to-move, the ground mask's
# visible-cell box, the off-screen chevrons, the minimap's view rectangle.
#
# The claim is only worth anything if the REAL Camera3D in the view agrees with
# the arithmetic, at any angle — one camera, two ways of asking it questions,
# not two cameras that have to be kept in step by hand (which is exactly what
# the four separate viewports this replaced got wrong, and what #58 was).
#
# Run twice, once per kind of map (#231): on the free plane (SORCMERC_ROUTES=0,
# the opt-out) and on the roads (the default). The camera is the same camera on
# both; what a click on a turned map MEANS is not. On the free plane it marches
# to the ground under the cursor. On the roads a click names a place — the
# town, found lair or found landmark under the cursor — and the company goes
# there by road, or nowhere: a click on open ground gives no order. Both are
# asked at a turned, tilted camera, where a _pix/_unpix that disagreed with the
# real Camera3D would send the company somewhere else.
#   godot --headless --path . -s tests/test_world_camera.gd
extends SceneTree

const RouteTravel = preload("res://core/route_travel.gd")

var _pass := 0
var _fail := 0
var _mode := ""

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", _mode, label)

# Every angle below is one the camera can actually be put at, including both
# ends of the tilt clamp — the shallow end is where the projection's sin(pitch)
# is smallest and _unpix() is nearest to dividing by zero.
const ANGLES := [[35.0, 22.332], [0.0, 45.0], [115.0, 12.0], [250.0, 82.0], [359.0, 60.0]]

func _init() -> void:
	await _run(false)
	await _run(true)
	print("test_world_camera: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run(routes: bool) -> void:
	# "0" is the free plane, where bands walk the map (#231: routes are the default)
	OS.set_environment("SORCMERC_ROUTES", "1" if routes else "0")
	_mode = "[roads] " if routes else "[free plane] "
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.size = Vector2(1180, 760)

	# --- the round trip, at every angle ----------------------------------
	var worst := 0.0
	for a in ANGLES:
		main._yaw = a[0]
		main._pitch = a[1]
		for z in [0.25, 1.0, 2.5]:
			main.set_zoom(z)
			main._pan = Vector2(140.0 * z, -85.0)
			main._layout()
			for w in [Vector2.ZERO, Vector2(500, -900), Vector2(-2400, 1750), Vector2(13, 7)]:
				worst = maxf(worst, main._unpix(main._pix(w)).distance_to(w))
	check(worst < 0.01, "_pix and _unpix invert each other at every angle (worst %.5f units)" % worst)

	# --- ...and the real camera lands on the same pixel -------------------
	# The one that matters. unproject_position() asks the Camera3D where a
	# point in the 3D world falls on screen; _pix() asks world.gd's own
	# arithmetic the same question about the same point on the map's floor.
	# A disagreement here is a label beside the thing it names and a click that
	# marches somewhere else.
	var cam_worst := 0.0
	for a in ANGLES:
		main._yaw = a[0]
		main._pitch = a[1]
		for z in [0.4, 1.0, 2.2]:
			main.set_zoom(z)
			main._pan = Vector2(-60.0, 120.0 * z)
			main._layout()
			main._process(0.016)
			await process_frame
			var cam: Camera3D = main._view.camera()
			for w in [Vector2.ZERO, Vector2(220, -140), Vector2(-310, 260)]:
				var got: Vector2 = cam.unproject_position(Vector3(w.x, 0.0, w.y))
				cam_worst = maxf(cam_worst, got.distance_to(main._pix(w)))
	check(cam_worst < 1.0, "the Camera3D projects a map point where _pix() says (worst %.3f px)" % cam_worst)

	# --- turning and tilting hold the middle of the screen ----------------
	# A map that slides out from under you as you turn it is a map you cannot
	# turn on purpose.
	main.reset_view()
	main._layout()
	var centre: Vector2 = main._unpix(main.size * 0.5)
	main.orbit_by(70.0)
	check(main._unpix(main.size * 0.5).distance_to(centre) < 0.5,
		"turning the camera keeps the ground under the middle of the screen")
	main.tilt_by(25.0)
	check(main._unpix(main.size * 0.5).distance_to(centre) < 0.5, "...and so does tilting it")
	check(is_equal_approx(main.yaw(), fposmod(main.ISO_YAW + 70.0, 360.0)), "the turn is the turn that was asked for")

	# --- the tilt clamps at both ends -------------------------------------
	for i in 40:
		main.tilt_by(main.PITCH_STEP)
	check(main.pitch() == main.PITCH_MAX, "tilting up stops at PITCH_MAX (%.1f)" % main.pitch())
	for i in 80:
		main.tilt_by(-main.PITCH_STEP)
	check(main.pitch() == main.PITCH_MIN, "tilting down stops at PITCH_MIN (%.1f)" % main.pitch())
	check(main.PITCH_MIN > 0.0, "...and never reaches edge-on, where the map is a line and _unpix divides by zero")

	# The turn wraps rather than running off, so Q held down is a turntable and
	# not a number growing forever.
	main._yaw = 350.0
	main.orbit_by(20.0)
	check(is_equal_approx(main.yaw(), 10.0), "the turn wraps at 360 (%.1f)" % main.yaw())

	# --- Home puts it back -----------------------------------------------
	main.set_zoom(2.1)
	main.orbit_by(123.0)
	main.tilt_by(19.0)
	var before: Vector2 = main._unpix(main.size * 0.5)
	main.reset_view()
	check(is_equal_approx(main.yaw(), main.ISO_YAW) and is_equal_approx(main.pitch(), main.ISO_PITCH)
		and is_equal_approx(main._zoom, 1.0), "Home restores the view the map opens on")
	check(main._unpix(main.size * 0.5).distance_to(before) < 0.5,
		"...without also teleporting the player somewhere else on the map")

	# --- the default IS the old flat map's projection ---------------------
	# ISO_SQUASH is still what scenes/world/settlement_kit.gd and the gallery
	# shots size themselves against, so the camera it names has to be the one
	# the map opens on, or every diorama on the map is the wrong size.
	check(is_equal_approx(sin(deg_to_rad(main.ISO_PITCH)), main.ISO_SQUASH),
		"the opening pitch is exactly asin(ISO_SQUASH) — one camera, written two ways")

	# --- click-to-move still means what it says, at any angle -------------
	var p = main.world.player()
	main.reset_view()
	main.orbit_by(-95.0)
	main.tilt_by(14.0)
	main._layout()
	check(RouteTravel.on(main.world) == routes, "the map is the kind this pass is for")
	if routes:
		_route_clicks(main, p)
	else:
		var target: Vector2 = main._unpix(Vector2(410, 300))
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(410, 300)
		main._gui_input(click)
		# World.set_goal() may clamp the order (water, bounds), so this asks that
		# the goal is the clamp OF the point clicked, not some other point.
		check(p.goal.distance_to(target) < 1.0 or main.world.is_water(target),
			"a click on a turned map marches to the ground under the cursor")
	main.queue_free()
	await process_frame

func _left_click(main, at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	main._gui_input(click)

# On the roads: the place under the cursor, found through the turned camera's
# own _pix, is where the march ends; open ground under the cursor is no order.
func _route_clicks(main, p) -> void:
	# A town the company is not standing in, on the screen at this angle.
	var town = null
	for s in main.world.settlements:
		var sp: Vector2 = main._pix(s.position)
		if s.position.distance_to(p.position) > 60.0 and Rect2(Vector2.ZERO, main.size).grow(-40.0).has_point(sp):
			town = s
			break
	check(town != null, "a town is on the turned screen to click")
	if town == null:
		return
	# A spot of open ground on the screen, well clear of every place a click could name.
	var ground := Vector2(-1, -1)
	for y in range(60, int(main.size.y) - 60, 40):
		for x in range(60, int(main.size.x) - 60, 40):
			var at: Vector2 = main._unpix(Vector2(x, y))
			if RouteTravel.place_near(main.world, at, 200.0) == "":
				ground = Vector2(x, y)
				break
		if ground.x >= 0.0:
			break
	check(ground.x >= 0.0, "a stretch of open ground is on the turned screen to click")
	var before: Vector2 = p.position
	if ground.x >= 0.0:
		_left_click(main, ground)
		check(p.at_goal() and p.position == before, "a click on open ground on a turned map gives no order")
		check(String(main._camp_msg.text).begins_with("No road"), "...and says so: %s" % main._camp_msg.text)
	_left_click(main, main._pix(town.position))
	check(not p.at_goal(), "a click on a town on a turned map is an order")
	check(main._destination(p).distance_to(town.position) < 1.0,
		"...and the march ends at the town under the cursor, %s (%s)" % [town.sname, main._destination(p)])
	check(String(main._camp_msg.text).begins_with("On the road to %s" % town.sname), "...said on the HUD: %s" % main._camp_msg.text)
