# #231 phase 1 — the world screen as a route world, driven like a player would:
# SORCMERC_ROUTES=1, the small map, a click on a town, the walk there, what the
# road sends met on the approach card and gone after it, the town that is only
# passed through not opening, the one at the end opening, the search at a fork,
# and a map built without the flag still roaming free.
#   godot --headless --path . -s tests/drive_routes.gd
extends SceneTree

const RouteTravel = preload("res://core/route_travel.gd")
const Grudges = preload("res://core/grudges.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var screen
var _pass := 0
var _fail := 0
var _met := 0          # approach cards the road opened
var _met_ids: Array = []

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	Grudges.reset()
	OS.set_environment(RouteTravel.FLAG, "1")
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

# Frames with a fixed delta, waving away what a player would wave away. A card
# the road opened is answered "no fight" — the robot is here for the road, and
# tests/drive_world.gd already drives a fight end to end.
func step(n: int, dt := 0.1) -> void:
	for i in n:
		screen._process(dt)
		await process_frame
		if screen._event_card != null:
			screen._event_card.acknowledged.emit()
		if screen._approach_card != null and screen._approach_foe != null:
			var foe = screen._approach_foe
			_met += 1
			_met_ids.append(foe.id)
			check(String(foe.ai.get("behavior", "")) == "met", "the card is for a band the road sent (%s)" % foe.id)
			check(screen.world.parties.has(foe), "...standing on the map while it is met")
			screen._close_approach()
			screen._on_approach_reported(foe, {"fight": false})
			check(not screen.world.parties.has(foe), "...and gone once the meeting is over")
		if screen._spoils_panel != null:
			screen._close_spoils()
		while screen._moment != null:
			screen._moment._skip_or_advance()

func _unhalt() -> void:
	screen._halted_on_arrival = false
	screen.world.clock.resume()

func _run() -> void:
	await process_frame
	screen.size = Vector2(1280, 800)
	await step(2)
	var w = screen.world
	var p = w.player()
	check(RouteTravel.on(w), "the flag made a route world")
	check(w.parties.size() == 1 and w.parties[0] == p, "nobody on the map but the company")
	check(float(w.routes.locate(p.position, true)["distance"]) < 0.5, "the company starts on a road")
	var says := false
	for c in screen.find_children("*", "Label", true, false):
		says = says or String(c.text).begins_with("Click marches to a known place")
	check(says, "the HUD says how travel works now")

	# A click on open ground does nothing.
	var before: Vector2 = p.position
	screen._route_click(screen._pix(Vector2(-700, 700)))
	check(p.at_goal() and p.position == before, "a click on open ground gives no order")
	check(String(screen._camp_msg.text).begins_with("No road"), "...and says so")

	# To Riverhold first, where the roads meet; then to Greenmarch.
	screen._route_click(screen._pix(Vector2(0, 0)))
	await _arrive(p, 400)
	check(screen._visit.get("settlement") != null and screen._visit["settlement"].id == "riverhold", "a click on Riverhold walks there and opens it")
	screen._close_visit()
	_unhalt()
	await step(3)
	screen._route_click(screen._pix(Vector2(420, -180)))   # Greenmarch
	check(not p.at_goal(), "a click on a known town is an order")
	check(String(screen._camp_msg.text).begins_with("On the road to Greenmarch"), "...said on the HUD")
	var off_road := false
	for i in 600:
		await step(1)
		if not screen._visit.is_empty():
			break
		off_road = off_road or float(w.routes.locate(p.position, true)["distance"]) > 0.5
	check(not off_road, "the march never leaves the road")
	var opened = screen._visit.get("settlement")
	check(opened != null and opened.id == "greenmarch", "the town at the end opens (%s)" % (opened.id if opened != null else "none"))
	screen._close_visit()
	_unhalt()

	# Dun-Arrow to Greenmarch runs through Riverhold on the small map's roads:
	# passed through, not opened.
	screen._route_click(screen._pix(Vector2(-360, 260)))
	await _arrive(p, 900)
	screen._close_visit()
	_unhalt()
	var way: Dictionary = w.routes.path_from(p.position, "settlement:greenmarch")
	check(way["nodes"].has("settlement:riverhold"), "the way to Greenmarch runs through Riverhold")
	screen._route_click(screen._pix(Vector2(420, -180)))
	var opened_on_way := []
	for i in 1200:
		await step(1, 0.25)
		if not screen._visit.is_empty():
			opened_on_way.append(screen._visit["settlement"].id)
			break
		if p.at_goal():
			break
	check(opened_on_way == ["greenmarch"], "Riverhold is passed through; Greenmarch opens (%s)" % [opened_on_way])
	if not screen._visit.is_empty():
		screen._close_visit()
	_unhalt()

	# Walk the roads for a while: back and forth between the towns, so the road
	# sends something. The same walk meets the same things (seeded per stretch
	# and day), so this is deterministic.
	var towns := [Vector2(0, 0), Vector2(-360, 260), Vector2(0, 0), Vector2(420, -180)]
	for lap in 16:
		screen._route_click(screen._pix(towns[lap % towns.size()]))
		await _arrive(p, 900)
		if not screen._visit.is_empty():
			screen._close_visit()
		_unhalt()
	check(w.route_walked > 3000.0, "a long walk on the roads (%.0f)" % w.route_walked)
	check(_met > 0, "the road sent somebody (%d meetings)" % _met)
	var bands: Array = w.parties.filter(func(q): return not q.is_player)
	check(bands.is_empty(), "and nobody is left standing on the map (%d)" % bands.size())

	# The search at a fork: stand where a hidden lair's track leaves the road.
	var fork := ""
	for eid in w.routes.edges:
		var e: Dictionary = w.routes.edges[eid]
		if e["kind"] == "track" and not e["known"] and w.routes.nodes[e["notice"][0]]["known"]:
			fork = e["notice"][0]
			break
	check(fork != "", "a hidden lair track leaves a known fork")
	p.position = w.routes.nodes[fork]["position"]
	w.set_goal(p, p.position)
	screen._check_lairs()
	check(screen._lair_btn.visible and screen._lair_btn.text.begins_with("Search the ground"), "the lair button offers the search at the fork")
	screen._lair_action()
	check(is_instance_valid(screen._map_die) or String(screen._lair_msg.text).contains("Survival"), "the search rolls its die over the map")
	screen._land_map_roll()   # what a click on the die does: land it now
	check(String(screen._lair_msg.text).contains("Survival"), "the search is rolled and said (%s)" % screen._lair_msg.text)
	screen.queue_redraw()
	await process_frame   # the roads draw without error
	screen.queue_free()
	await process_frame

	# Without the flag, a new map is the free plane it always was.
	OS.set_environment(RouteTravel.FLAG, "")
	var free = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(free)
	await process_frame
	check(not RouteTravel.on(free.world), "no flag, no roads")
	check(free.world.parties.size() > 1, "...and the bands are on the map")
	free.queue_free()
	await process_frame
	Grudges.reset()
	FactionOpinion.reset()
	print("drive_routes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Step until the company is where it was sent, a town has opened, or `cap`
# frames pass.
func _arrive(p, cap: int) -> void:
	for i in cap:
		await step(1, 0.25)
		if p.at_goal() or not screen._visit.is_empty():
			return
