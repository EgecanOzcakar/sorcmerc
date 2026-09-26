# Landmarks on the world screen, on the roads — tests/test_world_landmarks.gd's
# counterpart for the default map (#231). That file keeps the free plane
# (SORCMERC_ROUTES=0), where a landmark is found by walking up to it and a
# hidden one offers its own search to a company standing beside it. On the
# roads the company cannot stand anywhere a road does not go, so a landmark is
# found by its PATH: a way noticed leaving the road as the march passes the fork
# it leaves from (world_routes.gd's notice), or a hidden way the Survival search
# at a fork turns up (RouteTravel.search). Once found it is a place: drawn on
# the map, clicked, marched to by road, and there the same button, the same
# approach card and the same event card as on the free plane — and a spent
# place is quiet.
#
# Nothing here is arranged: the landmarks, their paths and the forks are the
# small map's own, found by the real march through the real click
# (tests/road_screen.gd). The one thing waved away is the road's own traffic —
# a meeting on the way is answered "no fight", the way tests/drive_routes.gd
# answers it — since this is about the places, not who walks the road.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_landmarks_routes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Landmarks = preload("res://core/landmarks.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _marked(main, name: String) -> bool:
	return main.ground_marks().any(func(r): return r.get("label", "") == name)

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "1")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	check(RouteTravel.on(w), "the default map is a route world")
	check(w.landmarks.size() >= 6, "the small map has landmarks (%d)" % w.landmarks.size())
	check(w.landmarks.all(func(m): return not m.found), "none is found before the company has walked a road")
	check(w.landmarks.all(func(m): return not _marked(main, m.sname)), "...and none is drawn")

	# --- found by its path: a way noticed leaving the road as the march passes ---
	# A landmark's path that is noticed (not searched for) from a fork the
	# company knows, and a town whose road passes that fork.
	var mark = null
	var via := ""
	var dest = null
	for eid in w.routes.edges:
		var e: Dictionary = w.routes.edges[eid]
		if e["known"] or e["search"] or e["kind"] != "path":
			continue
		var f: String = e["notice"][0]
		var far: String = e["b"] if e["a"] == f else e["a"]
		if not w.routes.nodes[f]["known"] or w.routes.nodes[far]["kind"] != "landmark":
			continue
		for s in w.settlements:
			var way: Dictionary = w.routes.path_from(p.position, RoadScreen.node(s))
			if not way.is_empty() and (way["nodes"] as Array).has(f) and s.position.distance_to(p.position) > 100.0:
				dest = s
				break
		if dest != null:
			mark = w.landmark(String(w.routes.nodes[far]["ref"]))
			via = f
			break
	check(mark != null, "a landmark's path is noticed from a fork on a known road")
	if mark == null:
		_done()
		return
	var noticed := false
	var got: String = await RoadScreen.march(self, main, dest.position)
	for i in 20:
		noticed = noticed or ("A way leaves the road here" in String(main._lair_msg.text) and mark.sname in String(main._lair_msg.text))
		if got != "card" or main._approach_foe == null:
			break
		RoadScreen.wave_off(main)
		got = await RoadScreen.walk(self, main)
	check(got == "visit" and main._visit.get("settlement") == dest, "the march to %s ends at its gate (%s)" % [dest.sname, got])
	check(mark.found, "marching past %s, %s's path is seen and it is found" % [via, mark.sname])
	check(w.routes.nodes[WorldRoutes.poi_id("landmark", mark.id)]["known"], "...its way is a known road now")
	check(noticed or "A way leaves the road here" in String(main._lair_msg.text), "...and the HUD said a way leaves the road: %s" % main._lair_msg.text)
	check(_marked(main, mark.sname), "a found landmark is a marker")
	var unfound: Array = w.landmarks.filter(func(m): return not m.found)
	check(not unfound.is_empty() and unfound.all(func(m): return not _marked(main, m.sname)), "an unfound one is not")
	main._close_visit()
	await process_frame

	# --- a place: clicked, marched to by road, a button to visit ---
	got = await RoadScreen.go(self, main, mark.position)
	check(got == "arrived" and p.position.distance_to(mark.position) <= 8.0, "a click on %s marches there by road (%s)" % [mark.sname, got])
	for i in 3:
		await process_frame
	check(main._place_btn.visible and "Visit" in main._place_btn.text and mark.sname in main._place_btn.text,
		"the button offers a visit: %s" % main._place_btn.text)

	# leave spends nothing
	main._place_btn.pressed.emit()
	await process_frame
	check(main._approach_card != null and w.clock.is_paused(), "the card opens and the clock stops")
	main._on_place_chosen(Landmarks.LEAVE)
	for i in 3:
		await process_frame
	check(not mark.spent and main._approach_card == null and not w.clock.is_paused(), "leave closes the card, spends nothing")

	# answered: the event card, the place spent
	main._place_btn.pressed.emit()
	await process_frame
	var opts: Array = Landmarks.options(mark, main.party, w)
	check(main._approach_card != null and opts.size() > 1, "asked again, it has something to try (%d rows)" % opts.size())
	main._on_place_chosen(String(opts[0]["id"]))
	for i in 3:
		await process_frame
	check(main._event_card != null, "the outcome is on the event card")
	check(mark.spent, "answered, the place is spent")
	main._event_card.acknowledged.emit()
	for i in 3:
		await process_frame
	check(not w.clock.is_paused(), "acknowledged, the clock runs")
	check(not main._place_btn.visible or not (mark.sname in main._place_btn.text), "a spent place offers no visit")

	# --- a hidden way is the search at its fork, not the place button's ---
	# March along a road that passes a fork a hidden way leaves; where the
	# search is offered, the place button offers nothing — a hidden landmark
	# is never searched for beside itself on the roads.
	var fork := ""
	var to = null
	for eid in w.routes.edges:
		var e: Dictionary = w.routes.edges[eid]
		if e["known"] or not e["search"] or not w.routes.nodes[e["notice"][0]]["known"]:
			continue
		for s in w.settlements:
			var way: Dictionary = w.routes.path_from(p.position, RoadScreen.node(s))
			if not way.is_empty() and (way["nodes"] as Array).has(e["notice"][0]) and not WorldAI.is_monster(s.faction):
				to = s
				break
		if to != null:
			fork = e["notice"][0]
			break
	check(to != null, "a known road passes a fork a hidden way leaves")
	if to == null:
		_done()
		return
	RoadScreen.click(main, to.position)
	if w.clock.is_paused() and not main._halted_on_arrival:
		main._toggle_pause()
	var offered := false
	for i in 1500:
		await RoadScreen.frame(self, main)
		if main._approach_card != null and main._approach_foe != null:
			RoadScreen.wave_off(main)
		elif main._event_card != null:
			main._event_card.acknowledged.emit()
		elif not main._visit.is_empty() or p.at_goal():
			break
		elif main._route_search and main._lair_btn.visible:
			offered = true
			break
	check(offered, "passing %s, the lair button offers the search" % fork)
	if offered:
		main._toggle_pause()
		check(main._lair_btn.text.begins_with("Search the ground"), "...the Survival check: %s" % main._lair_btn.text)
		check(not (main._place_btn.visible and "Search" in main._place_btn.text), "...and the place button offers no search of its own")
		main._lair_msg.text = ""
		main._lair_btn.pressed.emit()
		if is_instance_valid(main._map_die):
			main._land_map_roll()   # what a click on the die does
		await process_frame
		check("Survival" in String(main._lair_msg.text), "the search is rolled and said: %s" % main._lair_msg.text)
	_done()

func _done() -> void:
	print("test_world_landmarks_routes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

