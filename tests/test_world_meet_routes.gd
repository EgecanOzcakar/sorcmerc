# Meeting a band, on the roads — tests/test_world_meet.gd's counterpart for the
# default map (#231). That file keeps the free plane (SORCMERC_ROUTES=0): a
# band that is not hostile is met only by clicking its figure (_seek), which
# marches at it, follows it, and runs it down on a roll if it outpaces the
# company; a hostile one closes by itself; a band locked in a clash is met by
# nobody. None of that has a road counterpart — on the roads nothing walks the
# map, so there is no figure to click, nobody to follow or run down, and no
# band-on-band fight — and it stays the free plane's.
#
# What a route world has instead is the road's meeting: the march walks up to a
# band standing on the road it takes, and the card opens then, for a friendly
# band as for a hostile one (RouteTravel.step: a pinned band reached is met
# whatever it thinks of the company). This drives that through the real click
# (tests/road_screen.gd):
#   * a patrol on the road ahead: the friendly card (greet or move on), the
#     clock stopped for it;
#   * moving on: the card closes, the march walks on (not halted — the company
#     was going somewhere), and the patrol is back on its spot on the road, off
#     the map, held there so walking on past it does not meet it again;
#   * greeting one: the same, after the greeting's card;
#   * a hostile band on the road ahead: the hostile card;
#   * a click on open ground is no order and no errand, and the map has no
#     figure under the cursor to meet.
# The bands are pinned on the road ahead (core/route_pins.gd's own place(), the
# way a bounty or a story's band stands there) because the road sends its own
# by its own dice (tests/test_route_travel.gd's subject). The road's own traffic
# met on the way is waved off, the way tests/drive_routes.gd answers it.
#   godot --headless --path . -s tests/test_world_meet_routes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func ways(main) -> Array:
	var out: Array = []
	if main._approach_card == null:
		return out
	for b in main._approach_card.get_children():
		if b is Button:
			out.append(String(b.name).get_slice("_", 2))
	return out

# The farthest friendly town from where the company stands: a long road.
func _far_town(main):
	var p = main.world.player()
	var best = null
	for s in main.world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		if best == null or s.position.distance_to(p.position) > best.position.distance_to(p.position):
			best = s
	return best

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "1")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	var clock = w.clock
	check(RouteTravel.on(w), "the default map is a route world")
	check(w.parties.all(func(q): return q.is_player), "nobody on the map but the company")
	while clock.is_night():   # by day: no night watch gets in between
		clock.elapsed += 60.0
	clock.resume()

	# --- a patrol on the road ahead is met as the march reaches it -----------
	var dest = _far_town(main)
	var patrol = RoadScreen.band("patrol-test", "human")
	check(not WorldAI.is_hostile(patrol, p), "setup: the patrol is not hostile")
	check(RoadScreen.pin_ahead(main, RoadScreen.node(dest), 80.0, patrol), "setup: it stands on the road to %s" % dest.sname)
	var got: String = await RoadScreen.go(self, main, dest.position, patrol)
	check(got == "card" and main._approach_foe == patrol, "walking the road up to a patrol opens its card (%s)" % got)
	check(ways(main).has("greet") and ways(main).has("pass") and not ways(main).has("engage"),
		"...the friendly card, greet or move on (%s)" % [ways(main)])
	check(clock.is_paused(), "...and the clock stops for it")
	check(w.parties.has(patrol) and not w.pinned.has(patrol), "...the patrol on the map for its meeting")

	# --- moving on: the march walks on, the patrol stays on its road -------
	main._on_approach_chosen("pass")
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._approach_card == null, "moving on closes the card")
	check(not clock.is_paused() and not main._halted_on_arrival and not p.at_goal(),
		"...and the march walks on: the company was going somewhere")
	check(w.pinned.has(patrol) and not w.parties.has(patrol), "...the patrol back on its spot on the road, off the map")
	var reopened := false
	for i in 40:
		await RoadScreen.frame(self, main)
		if main._approach_foe == patrol:
			reopened = true
			break
		if main._approach_card != null:
			RoadScreen.wave_off(main)
		if not main._visit.is_empty() or p.at_goal():
			break
	check(not reopened, "...and walking on past it does not meet it again")

	# --- greeting one: the greeting's card, and it too stays on its road -----
	if not main._visit.is_empty():
		main._close_visit()
	dest = _far_town(main)
	var elves = RoadScreen.band("greet-test", "elf")
	check(RoadScreen.pin_ahead(main, RoadScreen.node(dest), 80.0, elves), "setup: another patrol on the road to %s" % dest.sname)
	got = await RoadScreen.go(self, main, dest.position, elves)
	check(got == "card" and main._approach_foe == elves and ways(main).has("greet"), "walked up to, it offers a greeting (%s)" % got)
	if main._approach_foe == elves:
		main._on_approach_chosen("greet")
		check(main._event_card != null, "the greeting is answered on a card")
		main._event_card.acknowledged.emit()
		await process_frame
		check(main._approach_card == null and main._combat == null, "greeted, no fight")
		check(w.pinned.has(elves) and not w.parties.has(elves), "...and it is back on its road")
	RoutePins.drop(w, elves)
	RoutePins.drop(w, patrol)

	# --- a hostile band on the road ahead: the hostile card ----------------
	if not main._visit.is_empty():
		main._close_visit()
	await RoadScreen.frame(self, main)
	dest = _far_town(main)
	var gobs = RoadScreen.band("gobs-test", "goblinoid")
	check(WorldAI.is_hostile(gobs, p), "setup: goblinoids are hostile")
	check(RoadScreen.pin_ahead(main, RoadScreen.node(dest), 80.0, gobs), "setup: they stand on the road to %s" % dest.sname)
	got = await RoadScreen.go(self, main, dest.position, gobs)
	check(got == "card" and main._approach_foe == gobs, "walking up to a hostile band opens its card (%s)" % got)
	check(ways(main).has("engage"), "...the hostile one (%s)" % [ways(main)])
	RoadScreen.wave_off(main)
	check(w.pinned.has(gobs) and not w.parties.has(gobs), "slipped, it is left standing on its road")
	RoutePins.drop(w, gobs)

	# --- nothing on the map to click; open ground is no order --------------
	main._layout()
	var here: Vector2 = p.position
	var ground := here + Vector2(0, 0)
	for r in [300.0, 450.0, 600.0]:
		for a in 12:
			var at: Vector2 = here + Vector2.RIGHT.rotated(TAU * a / 12.0) * r
			if RouteTravel.place_near(w, at, 150.0) == "":
				ground = at
				break
		if ground != here:
			break
	check(ground != here, "setup: a stretch of open ground near the company")
	check(main._band_at(main._pix(ground)) == null and main._band_at(main._pix(here)) == null,
		"no band stands on the map to be clicked")
	var goal_before: Vector2 = main._destination(p)
	RoadScreen.click(main, ground)
	check(main._meet_id == "" and main._destination(p) == goal_before, "a click on open ground is no order and no errand")
	check(String(main._camp_msg.text).begins_with("No road"), "...and says so: %s" % main._camp_msg.text)

	main.queue_free()
	print("test_world_meet_routes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
