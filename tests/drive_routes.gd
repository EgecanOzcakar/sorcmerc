# #231 phase 1 — the world screen as a route world, driven like a player would:
# SORCMERC_ROUTES=1, the small map, a click on a town, the walk there, what the
# road sends met on the approach card and gone after it, the town that is only
# passed through not opening, the one at the end opening, the search at a fork,
# and a map built without the flag still roaming free.
# Phase 2 (core/route_pins.gd): the towns price bands on their roads, and the
# march walks up to one — its card opens, and the slip leaves it standing on
# its road, not on the map; a raid stands pinned at Greenmarch's gate, said on
# the HUD, met on the way in, and lands when it is left.
#   godot --headless --path . -s tests/drive_routes.gd
extends SceneTree

const RouteTravel = preload("res://core/route_travel.gd")
const Grudges = preload("res://core/grudges.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const RoutePins = preload("res://core/route_pins.gd")
const Raids = preload("res://core/raids.gd")

var screen
var _pass := 0
var _fail := 0
var _met := 0          # approach cards the road opened
var _met_ids: Array = []
var _pinned_met: Array = []   # ids of pinned bands whose card opened

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
			var pinned: bool = RoutePins.is_pinned(foe)
			if pinned:
				_pinned_met.append(foe.id)
			check(pinned or String(foe.ai.get("behavior", "")) == "met", "the card is for a band the road sent or one pinned on it (%s)" % foe.id)
			check(screen.world.parties.has(foe), "...standing on the map while it is met")
			screen._close_approach()
			screen._on_approach_reported(foe, {"fight": false})
			check(not screen.world.parties.has(foe), "...and off the map once the meeting is over")
			if pinned:
				check(screen.world.pinned.has(foe), "...a pinned one back on its road")
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
	await _pins(w, p)

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

	# Opted out (SORCMERC_ROUTES=0), a new map is the free plane it always was.
	OS.set_environment(RouteTravel.FLAG, "0")
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

# Phase 2, on the same screen and map. The laps take the morning; past the
# first day every town has priced a band (the screen's own RouteTravel.tick).
func _pins(w, p) -> void:
	w.clock.elapsed = maxf(w.clock.elapsed, 1500.0)
	await step(1)
	var bounty = RoutePins.bounty_of(w, "riverhold")
	check(bounty != null and w.pinned.has(bounty), "Riverhold has priced a band on its roads")
	check(w.parties.all(func(q): return q.is_player), "...and it is not on the map")
	if bounty == null:
		return
	# March somewhere whose way passes where it stands; its card opens.
	var seen_before: int = _pinned_met.count(bounty.id)
	var dest := ""
	for s in w.settlements:
		var way: Dictionary = w.routes.path_from(p.position, "settlement:%s" % s.id)
		if not way.is_empty() and _passes(way["points"], bounty.position):
			dest = s.id
			break
	if dest == "":   # standing past it already: from Riverhold, then
		p.position = w.settlements[0].position
		w.set_goal(p, p.position)
		for s in w.settlements:
			var way: Dictionary = w.routes.path_from(p.position, "settlement:%s" % s.id)
			if not way.is_empty() and _passes(way["points"], bounty.position):
				dest = s.id
				break
	check(dest != "", "a known road passes the bounty band")
	var target = null
	for s in w.settlements:
		if s.id == dest:
			target = s
	screen._route_click(screen._pix(target.position))
	await _arrive(p, 900)
	if not screen._visit.is_empty():
		screen._close_visit()
	_unhalt()
	check(_pinned_met.count(bounty.id) == seen_before + 1, "the march walks up to it, once (%s)" % [_pinned_met])
	check(w.pinned.has(bounty) and not w.parties.has(bounty), "the slip leaves it on its road")

	# A raid: the Tangle's clock runs out, and its band stands at Greenmarch's gate.
	var tangle = null
	for l in w.lairs:
		if l.id == "the-tangle":
			tangle = l
		elif l.raid_band == "":
			l.raid_at = w.clock.elapsed   # nobody else's clock runs out now
	var gm = null
	for s in w.settlements:
		if s.id == "greenmarch":
			gm = s
	tangle.raids = 0
	tangle.raid_at = w.clock.elapsed - Raids.RAID_AFTER - Raids.RAID_JITTER
	gm.raided_by = ""
	await step(1)
	var raiders = Raids.band_of(w, tangle)
	check(raiders != null and w.pinned.has(raiders), "the raid is a band pinned at the gate, not on the map")
	check(String(screen._lair_msg.text).contains("camped outside Greenmarch"), "...said on the HUD (%s)" % screen._lair_msg.text)
	if raiders == null:
		return
	# Walking in to Greenmarch meets it at the gate.
	p.position = Vector2(0, 0)
	w.set_goal(p, p.position)
	screen._route_click(screen._pix(gm.position))
	await _arrive(p, 900)
	if not screen._visit.is_empty():
		screen._close_visit()
	_unhalt()
	check(_pinned_met.has(raiders.id), "the march in meets the raiders at the gate")
	# Left alone, it lands.
	w.clock.elapsed = float(raiders.ai["until"]) + 1.0
	await step(1)
	check(gm.raided_by == "the-tangle", "left alone, the raid lands")
	check(w.band(raiders.id) == null, "...and the band goes home off the map")

func _passes(pts: PackedVector2Array, at: Vector2) -> bool:
	for i in range(1, pts.size()):
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, pts[i - 1], pts[i])) <= RoutePins.REACH * 0.5:
			return true
	return false

# Step until the company is where it was sent, a town has opened, or `cap`
# frames pass.
func _arrive(p, cap: int) -> void:
	for i in cap:
		await step(1, 0.25)
		if p.at_goal() or not screen._visit.is_empty():
			return
