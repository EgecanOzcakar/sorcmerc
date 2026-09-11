# O2 — scene-driver smoke test for the open-world map screen: it renders, the
# clock runs, a right-click moves the player party, pause stops it, and the
# camera pans/zooms without crashing.
#   godot --headless --path . -s tests/drive_world.gd
extends SceneTree

var screen
var _fail := 0

func _init() -> void:
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

func click(button: int, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	screen._gui_input(e)

# The scene's own _process runs too, but headless deltas are tiny — drive time
# explicitly so the assertions below are about movement, not frame pacing.
func step(n: int, dt := 0.1) -> void:
	for i in n:
		screen._process(dt)
		await process_frame

func _run() -> void:
	await process_frame
	screen.size = Vector2(1280, 800)
	await step(2)

	var p = screen.world.player()
	if p == null:
		fail("the scene has no player party")
		return _done()
	if screen.world.settlements.size() < 2 or screen.world.parties.size() < 3:
		fail("the scene has nothing to render: %d settlements, %d parties"
			% [screen.world.settlements.size(), screen.world.parties.size()])

	# --- right-click sets a goal and the party actually walks there ---------
	var start: Vector2 = p.position
	click(MOUSE_BUTTON_RIGHT, Vector2(1000, 600))
	if p.goal.is_equal_approx(start):
		fail("right-click did not set a goal away from the party")
	await step(5)
	if p.position.is_equal_approx(start):
		fail("the player party never moved toward the clicked point")
	if p.position.distance_to(p.goal) >= start.distance_to(p.goal):
		fail("the player party moved, but not toward its goal")

	# --- pause freezes it, resume unfreezes --------------------------------
	screen._toggle_pause()
	if not screen.world.clock.is_paused():
		fail("the pause button did not pause the clock")
	var held: Vector2 = p.position
	await step(5)
	if not p.position.is_equal_approx(held):
		fail("the party kept moving while paused")
	screen._toggle_pause()
	await step(5)
	if p.position.is_equal_approx(held):
		fail("resuming did not start the party moving again")

	# --- camera: drag-pan and scroll-zoom ----------------------------------
	var pan0: Vector2 = screen._pan
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.position = Vector2(600, 400)
	m.relative = Vector2(-40, 25)
	screen._gui_input(m)
	if screen._pan.is_equal_approx(pan0):
		fail("drag did not pan the camera")

	# Zoom keeps the world point under the cursor put, and clamps at both ends.
	var at := Vector2(700, 350)
	var under: Vector2 = screen._unpix(at)
	click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._unpix(at).distance_to(under) > 1.0:
		fail("zoom did not keep the point under the cursor fixed")
	for i in 40:
		click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._zoom > screen.ZOOM_MAX:
		fail("zoom exceeded ZOOM_MAX")
	for i in 80:
		click(MOUSE_BUTTON_WHEEL_DOWN, at)
	if screen._zoom < screen.ZOOM_MIN:
		fail("zoom fell below ZOOM_MIN")
	await step(2)     # a frame at min zoom, to exercise the far-out ground path
	_done()

func _done() -> void:
	print("drive_world: %s" % ["OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)
