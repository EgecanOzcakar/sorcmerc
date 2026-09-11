# O2/O4 — scene-driver smoke test for the open-world map screen: it renders, the
# clock runs, a right-click moves the player party, pause stops it, the camera
# pans/zooms without crashing, and closing on a hostile party hands off to a real
# scenes/main.tscn fight that freezes the map until it is won.
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
	await _encounter_handoff(p)
	await _offscreen_battle(p)
	await _settlement_visit(p)
	_done()

# --- O6: walking into a settlement opens the market, Leave closes it --------
func _settlement_visit(p) -> void:
	var s = screen.world.settlements[0]
	p.position = s.position + Vector2(screen.VISIT_RADIUS + 12.0, 0)
	screen.world.set_goal(p, s.position)
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("the market opened while the party was still outside the walls")
		return
	await step(5)
	if screen._visit.is_empty():
		fail("walking into the settlement did not open the market")
		return
	if not screen.world.clock.is_paused():
		fail("the visit did not pause the world clock")
	if screen._visit_panel == null or screen._visit["stock"].is_empty():
		fail("the market panel came up with nothing on it")
		return

	# Buy the first thing on the shelf through the panel's own path.
	screen.party.gold = 100000
	var id: String = String(screen._visit["stock"][0]["item_id"])
	var price: int = screen._visit["stock"][0]["price"]
	var gold0: int = screen.party.gold
	screen._buy(id)
	if screen.party.gold != gold0 - price or screen.party.stash_count(id) != 1:
		fail("buying from the market panel did not move gold/stash")
	if screen._visit["stock"].any(func(e): return e["item_id"] == id):
		fail("the bought item is still on the shelf")

	# Steal: narrated, and it queues the O7 opinion delta on the settlement.
	var opinion0: float = s.pending_opinion_delta
	screen._steal()
	if s.pending_opinion_delta >= opinion0:
		fail("stealing did not queue an opinion delta for O7")
	if screen._visit_log == null or screen._visit_log.text == "":
		fail("the theft was not narrated in the panel")

	screen._close_visit()
	if not screen._visit.is_empty() or screen._visit_panel != null:
		fail("Leave did not close the market")
	if screen.world.clock.is_paused():
		fail("Leave did not resume the world clock")
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("the market reopened on the spot after Leave")
	# ...and it opens again once the party has left the walls and come back.
	var away: Vector2 = s.position + Vector2(screen.VISIT_RADIUS + 60.0, 0)
	screen.world.set_goal(p, away)
	await step(30)
	if not screen._visit.is_empty():
		fail("the market stayed open while the party walked out")
		return
	screen.world.set_goal(p, s.position)
	await step(30)
	if screen._visit.is_empty():
		fail("coming back to the settlement did not open the market again")
	else:
		screen._close_visit()

# --- O5: two NPC parties meeting resolve off-screen, no scene, no pause -----
func _offscreen_battle(p) -> void:
	var World = load("res://core/world.gd")
	var away: Vector2 = p.position + Vector2(4000, 4000)     # nowhere near the player
	var a = screen.world.add_party(World.RoamingParty.new("raid-band", away, "bandit"))
	var b = screen.world.add_party(World.RoamingParty.new("garrison", away + Vector2(40, 0), "soldier"))
	a.goal = b.position
	b.goal = b.position
	var n: int = screen.world.parties.size()
	await step(6)     # 0.6s x 40 u/s closes the 40-unit gap into the radius
	if screen.world.parties.size() != n - 1:
		fail("the NPC meeting did not resolve to exactly one dead party (%d -> %d)"
			% [n, screen.world.parties.size()])
	if screen.world.parties.has(a) == screen.world.parties.has(b):
		fail("exactly one of the two bands should be left standing")
	if screen._combat != null:
		fail("an NPC-vs-NPC battle launched a combat scene")
	if screen.world.clock.is_paused():
		fail("an NPC-vs-NPC battle paused the world clock")
	if screen.world.player() == null:
		fail("the player was caught up in an off-screen battle")

# --- O4: proximity triggers a real fight, winning clears the party ------
func _encounter_handoff(p) -> void:
	var foe = null
	for q in screen.world.parties:
		if not q.is_player and q.faction != "soldier":
			foe = q
			break
	if foe == null:
		fail("no hostile party in the demo world to be ambushed by")
		return

	# Walk them together: just outside the radius, then inside it. Out in open
	# country — standing on a settlement would open O6's market instead.
	var open_country := Vector2(3000, -3000)
	p.position = open_country
	screen.world.set_goal(p, open_country)
	foe.position = open_country + Vector2(screen.ENCOUNTER_RADIUS + 10.0, 0)
	foe.goal = open_country
	screen._check_encounter()
	if screen._combat != null:
		fail("combat launched while the parties were still apart")
		return
	await step(4)     # 0.4s x 40 u/s closes the last 10 units and then some
	if screen._combat == null:
		fail("closing inside ENCOUNTER_RADIUS did not launch a fight")
		return

	# A real scenes/main.tscn with a real roster and a live Encounter behind it.
	if screen._combat.spec.get("monsters", []).is_empty():
		fail("the fight got an empty spec: %s" % [screen._combat.spec])
	if screen._combat.cb == null or screen._combat.cb.combatants.is_empty():
		fail("no live combat (Encounter-built Combat) inside the combat scene")
	else:
		var foes: Array = screen._combat.cb.combatants.filter(func(c): return c.team == "foe")
		if foes.is_empty():
			fail("the live combat has no foes from the encountered party")
	if not screen.world.clock.is_paused():
		fail("the world clock kept running during the fight")
	var frozen: Vector2 = foe.position
	await step(5)
	if not foe.position.is_equal_approx(frozen):
		fail("parties kept moving on the map during the fight")

	# Win it the way scenes/main.gd's _finish() does — fill `result`.
	screen._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5}
	await step(4)
	if screen._combat != null:
		fail("the combat scene was never torn down after the fight")
	if screen.world.parties.has(foe):
		fail("the defeated party is still on the map")
	if screen.world.clock.is_paused():
		fail("the world clock did not resume after the fight")

	# A faction with no board of its own still gets a roster and a board.
	var World = load("res://core/world.gd")
	var spec: Dictionary = screen.encounter_spec(
		World.RoamingParty.new("cult", Vector2.ZERO, "cultist"))
	if spec.get("monsters", []).is_empty() or spec.get("theme", "") != screen.DEFAULT_THEME:
		fail("themeless faction got no usable spec: %s" % [spec])

	# ...and the map still runs: the player marches again.
	var back: Vector2 = p.position
	screen.world.set_goal(p, back + Vector2(200, 0))
	await step(5)
	if p.position.is_equal_approx(back):
		fail("the map is not playable again after combat")

func _done() -> void:
	print("drive_world: %s" % ["OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)
