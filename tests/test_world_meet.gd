# Meeting a band on purpose: a band that is not hostile is never met by
# standing next to it, only by clicking its figure (world.gd's _seek), which
# marches the party at it and opens the approach card on contact — or at once,
# if it is already in reach. A hostile band still closes and forces the card.
# A band that outruns the party is run down on a roll or gets away
# (core/world_chase.gd).
#   godot --headless --path . -s tests/test_world_meet.gd
extends SceneTree
const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldChase = preload("res://core/world_chase.gd")
var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The map by hand, the way tests/drive_world.gd steps it: a fixed tick, and a
# road event (none should come in this few) waved away if one does.
func step(main, n: int, until := Callable(), dt := 0.1) -> void:
	for i in n:
		main._process(dt)
		await process_frame
		if main._event_card != null:
			main._event_card.acknowledged.emit()
		if until.is_valid() and until.call():
			return

func ways(main) -> Array:
	var out: Array = []
	for b in main._approach_card.get_children():
		if b is Button:
			out.append(String(b.name).get_slice("_", 2))
	return out

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "0")   # the free plane, where bands walk the map (#231: routes are the default)
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")   # a chase roll's die lands at once
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	# Open country, midday, nobody else on the road: only the bands placed here
	# can be met, and no gate or night watch gets in between.
	for q in w.parties.duplicate():
		if q != p:
			w.parties.erase(q)
	var here := Vector2(3000, -3000)
	p.position = here
	w.set_goal(p, here)
	main._was_travelling = false
	var clock = w.clock
	while clock.is_night():
		clock.elapsed += 60.0
	clock.resume()

	# --- a friendly patrol in reach does nothing by itself ------------------
	var patrol = w.add_party(World.RoamingParty.new("patrol-test", here + Vector2(10, 0), "human"))
	check(not WorldAI.is_hostile(patrol, p), "setup: the patrol is not hostile")
	patrol.speed = 0.0   # it goes only where this test puts it; a chase at equal speed is its own question
	await step(main, 10)
	check(main._approach_card == null, "standing next to a friendly patrol opens no card")
	check(not clock.is_paused(), "...and does not stop the clock")

	# --- clicking it when it is already in reach meets it at once ------------
	main._seek(patrol)
	check(main._approach_card != null, "a click on a patrol in reach opens the card at once")
	check(main._approach_card != null and ways(main).has("greet") and ways(main).has("pass"),
		"...the friendly card, greet or move on")
	check(clock.is_paused(), "...and the clock stops for it")
	main._on_approach_chosen("pass")
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._approach_card == null, "moving on closes the card")
	check(clock.is_paused() and main._halted_on_arrival,
		"...and hands back a halted map, not one that runs on with nobody giving orders")

	# --- clicking it from across the field marches there and meets it -------
	patrol.position = here + Vector2(160, 0)
	patrol.goal = patrol.position
	main._seek(patrol)
	check(main._approach_card == null, "a patrol out of reach: no card yet")
	check(main._meet_id == patrol.id, "...the party is on its way to meet it")
	check(p.goal.distance_to(patrol.position) < 1.0, "...marching straight at it")
	check("Marching to meet" in String(main._camp_msg.text), "...and the HUD says so")
	await step(main, 200, func(): return main._approach_card != null)
	check(main._approach_card != null, "walking up to the clicked patrol opens its card")
	check(main._meet_id == "", "...and the errand is done")
	check(not ("Marching to meet" in String(main._camp_msg.text)), "...and the HUD line with it")
	check(p.position.distance_to(patrol.position) <= main.ENCOUNTER_RADIUS * 2.0, "...next to it")
	main._on_approach_chosen("greet")
	main._event_card.acknowledged.emit()
	await process_frame

	# --- it follows the patrol if the patrol moves -------------------------
	patrol.position = p.position + Vector2(200, 0)
	patrol.goal = patrol.position
	main._seek(patrol)
	patrol.position = p.position + Vector2(0, 200)
	patrol.goal = patrol.position
	await step(main, 2)
	check(p.goal.distance_to(patrol.position) < 1.0 or main._approach_card != null,
		"a patrol that moved is followed, not the ground it stood on")
	await step(main, 200, func(): return main._approach_card != null)
	check(main._approach_card != null, "...and met where it went")
	if main._approach_card != null:
		main._close_approach()
		clock.resume()

	# --- sending the party anywhere else calls it off -----------------------
	patrol.position = p.position + Vector2(200, 0)
	patrol.goal = patrol.position
	main._halted_on_arrival = false
	main._seek(patrol)
	w.set_goal(p, p.position + Vector2(-200, 0))   # an order from somewhere other than the patrol
	await step(main, 5)
	check(main._meet_id == "", "a new order drops the errand")
	patrol.position = p.position + Vector2(10, 0)
	patrol.goal = patrol.position
	await step(main, 5)
	check(main._approach_card == null, "...and bumping into the patrol afterwards still opens nothing")

	# --- the figure is what is clicked -------------------------------------
	main._layout()
	check(main._band_at(main._pix(patrol.position)) == patrol, "a click on the patrol's figure finds the patrol")
	check(main._band_at(main._pix(patrol.position + Vector2(400, 400))) == null, "a click on open ground finds no band")

	# --- a band that outruns the party: run down on a roll, or away --------
	check(WorldChase.outpaced(40.0, 40.0) and WorldChase.outpaced(52.0, 40.0), "as fast or faster: legs alone won't do it")
	check(not WorldChase.outpaced(52.0, 56.0), "a forced march outpaces a beast pack, and then there is no roll")
	check(WorldChase.dc(40.0, 40.0) == WorldChase.BASE_DC, "an even chase is the base DC")
	check(WorldChase.dc(52.0, 40.0) == WorldChase.BASE_DC + 3, "a band 30% faster is +3")
	check(WorldChase.dc(60.0, 40.0) > WorldChase.dc(52.0, 40.0), "...and a dragon harder still")
	w.parties.erase(patrol)
	var caught := 0
	var escaped := 0
	for n in 12:
		while clock.is_night():   # by day: the whole chase fits inside the day's sight
			clock.elapsed += 60.0
		main._halted_on_arrival = false
		w.set_goal(p, p.position)
		clock.resume()
		var beasts = w.add_party(World.RoamingParty.new("beasts-%d" % n, p.position + Vector2(60, 0), "beast"))
		beasts.ai = {}                                     # no behaviour: it keeps walking where it is sent
		beasts.goal = beasts.position + Vector2(0, -8000)  # away, and faster than the party
		check(beasts.speed > p.speed, "setup: the beasts outrun the party")
		main._seek(beasts)
		await step(main, 400, func(): return main._approach_card != null or main._meet_id == "", 0.5)
		if main._approach_card != null:
			check("runs" in String(main._camp_msg.text) and "DC" in String(main._camp_msg.text),
				"a caught band was run down on a roll, and the HUD says so: %s" % main._camp_msg.text)
			check(ways(main).has("engage"), "...and the hostile card opens where it was caught")
			caught += 1
			main._close_approach()
		elif "get away" in String(main._camp_msg.text):
			escaped += 1
		else:
			check(false, "a chase ended neither caught nor escaped: %s" % main._camp_msg.text)
		w.parties.erase(beasts)
	check(caught > 0, "some fleeing bands are run down (%d of 12)" % caught)
	check(escaped > 0, "...and some get away after %d misses (%d of 12)" % [WorldChase.MAX_TRIES, escaped])
	clock.resume()
	main._halted_on_arrival = false

	# --- a band lost in the fog ends the chase, and says so ---------------
	var ghost = w.add_party(World.RoamingParty.new("ghost-test", p.position + Vector2(100, 0), "beast"))
	ghost.ai = {}
	main._seek(ghost)
	ghost.position = Vector2(90000, 90000)
	await step(main, 2)
	check(main._meet_id == "" and "Lost sight" in String(main._camp_msg.text), "a band gone into the fog is lost")
	w.parties.erase(ghost)

	# --- a hostile band still closes and forces the card -------------------
	var gobs = w.add_party(World.RoamingParty.new("gobs-test", p.position + Vector2(10, 0), "goblinoid"))
	check(WorldAI.is_hostile(gobs, p), "setup: goblinoids are hostile")
	clock.resume()
	await step(main, 3, func(): return main._approach_card != null)
	check(main._approach_card != null, "a hostile band in reach still opens the card by itself")
	check(main._approach_card != null and ways(main).has("engage"), "...the hostile one")
	main._close_approach()
	w.parties.erase(gobs)

	# --- #229: a band locked in a clash is met by nobody until it is over ---
	var watch = w.add_party(World.RoamingParty.new("watch-clash", p.position + Vector2(10, 0), "human"))
	watch.ai = {}
	watch.goal = watch.position
	var wolves = w.add_party(World.RoamingParty.new("wolves-clash", p.position + Vector2(12, 0), "beast"))
	wolves.ai = {}
	wolves.goal = wolves.position
	main._layout()
	check(main._band_at(main._pix(watch.position)) == watch, "setup: before the clash, its figure is clickable")
	w.clashes.append({"a": watch.id, "b": wolves.id, "winner": watch.id, "outcome": "Defeat",
		"rounds": 3, "at": (watch.position + wolves.position) * 0.5,
		"from": clock.elapsed, "until": clock.elapsed + 99999.0})
	check(main._band_at(main._pix(watch.position)) == null,
		"#229: a band in a clash is not a figure to click — a click there is ground")
	await step(main, 5)
	check(main._approach_card == null, "#229: a hostile band in a clash, in reach, opens no card")
	main._meet(wolves, true)
	check(main._approach_card == null and "locked in a fight" in String(main._camp_msg.text),
		"#229: a march that reaches one stops with a line: %s" % main._camp_msg.text)
	w.clashes.clear()
	w.parties.erase(wolves)
	w.parties.erase(watch)

	main.queue_free()
	print("test_world_meet: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
