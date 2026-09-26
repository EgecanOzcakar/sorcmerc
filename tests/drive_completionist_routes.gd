# tests/drive_completionist_routes.gd — the completionist's tour, on the roads.
#
# Routes are the default map (#231 phase 2b), and the completionist
# (tests/drive_completionist.gd) is the robot that asks every door on the world
# screen whether it still opens. It was written for the free plane, where the
# company walks to any point it likes and bands walk up to it; that file now
# pins itself to SORCMERC_ROUTES=0 and keeps touring the opt-out. This one is
# the same tour — the same checklist, the same chapters, the same contracts —
# of the map a player actually gets, by extending it and overriding only the
# steps a route world does differently. The checklist is not copied, so the two
# can never drift apart.
#
# What differs on the roads, and how each is toured here:
#
#   * **Every order is a click on a place.** The company never leaves the road
#     (the owner's call), so the march is always to a town, a found lair or a
#     found landmark, through the real click (_order -> _route_click). A click
#     after a pause lets the clock run again with the HUD's own button, which
#     is what a player does.
#   * **Out of a gate** is a walk to the nearest other place that is not a
#     monster's gate (_step_out_of), and back.
#   * **The open road** — somewhere to short-rest, camp and be met — is the
#     middle of a march to the farthest town: the company walks until no town
#     is near and the HUD's Pause stops it there (_into_the_open). A camp may
#     be made anywhere on a road (the owner's call).
#   * **lair:search** is the Survival check at a fork, where a hidden lair's
#     track or a hut's path leaves the road: the tour marches along a road that
#     passes one, and presses the lair button when it offers the search
#     (world.gd's _route_search). Same deed, same contract: the button rolls,
#     and says what it rolled.
#   * **The four meetings** are with a band pinned on the road ahead
#     (core/route_pins.gd) — arranged, per the parent's header, because the
#     road sends bands by its own dice — met as the march walks past it, on the
#     same approach card, and taken off the road after.
#
#   godot --headless --path . -s tests/drive_completionist_routes.gd
extends "res://tests/drive_completionist.gd"

const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")

const OPEN_ROAD := 200.0    # how far from every town the open road starts

var _tour_dest := ""        # the place a meeting's march is making for

func _routes() -> bool:
	return true

# The click, on a place, through the real input handler; and the HUD's own
# Resume when the clock was left stopped (a pause, not a halt: a new order
# releases a halt by itself, world.gd's _check_arrival).
func _order(at: Vector2) -> void:
	if screen._combat != null or not screen._visit.is_empty() or screen._overlay_up():
		return
	if not RouteTravel.on(screen.world):
		fail("the tour of the roads is on a free-roaming map")
		return
	screen.center_on(at)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = screen._pix(at)
	screen._gui_input(e)
	if screen.world.clock.is_paused() and not screen._halted_on_arrival \
			and not is_instance_valid(screen._approach_card) and not is_instance_valid(screen._event_card):
		screen._toggle_pause()

# The known places a click can name: node id -> position, forks left out.
func _places() -> Dictionary:
	var out := {}
	for id in screen.world.routes.nodes:
		var n: Dictionary = screen.world.routes.nodes[id]
		if n["known"] and n["kind"] != "fork":
			out[id] = n["position"]
	return out

func _monster_gate(id: String) -> bool:
	var n: Dictionary = screen.world.routes.nodes[id]
	if n["kind"] != "settlement":
		return false
	var s = _settlement(String(n["ref"]))
	return s != null and WorldAI.is_monster(s.faction)

func _step_out_of(s, label: String) -> bool:
	var best := ""
	var best_d := INF
	var here := WorldRoutesId.settlement(s.id)
	var places := _places()
	for id in places:
		if id == here or _monster_gate(id):
			continue
		var d: float = (places[id] as Vector2).distance_to(s.position)
		if d < best_d:
			best = id
			best_d = d
	if best == "":
		fail("no other place on the roads to step out of %s to" % label)
		return false
	return await _walk_to(places[best], "clear of %s (to %s)" % [label, best])

# The farthest town that is not a monster's gate: a march long enough to have
# an open stretch of road in the middle of it.
func _far_town() -> String:
	var p = screen.world.player()
	var best := ""
	var far := -1.0
	var places := _places()
	for id in places:
		if not String(id).begins_with("settlement:") or _monster_gate(id):
			continue
		var d: float = (places[id] as Vector2).distance_to(p.position)
		if d > far:
			far = d
			best = id
	return best

func _clear_of_towns(pos: Vector2) -> bool:
	for s in screen.world.settlements:
		if s.position.distance_to(pos) < OPEN_ROAD:
			return false
	return true

# March toward the far town and stop on the open road with the HUD's Pause.
func _into_the_open(_at: Vector2) -> bool:
	screen._set_speed(8.0)
	var dest := _far_town()
	if dest == "":
		fail("no town to march toward for the open road")
		return false
	var at: Vector2 = screen.world.routes.nodes[dest]["position"]
	for i in WALK_LIMIT:
		var p = screen.world.player()
		if not screen._visit.is_empty():
			screen._close_visit()
		elif screen._combat != null:
			await _see_the_fight_out()
		elif is_instance_valid(screen._approach_card):
			_meet_them()
		elif _clear_of_towns(p.position) and not p.at_goal():
			if not screen.world.clock.is_paused():
				screen._toggle_pause()
			return true
		elif p.at_goal() or screen.world.clock.is_paused():
			_order(at)
		await _step()
	fail("could not reach the open road on the way to %s in %d frames" % [dest, WALK_LIMIT])
	return false

# The Survival check at a fork: march along a road that passes a fork a hidden
# way leaves, and press the lair button when it offers the search.
func _search_for_lair() -> void:
	var routes = screen.world.routes
	var p = screen.world.player()
	var dest := ""
	var fork := ""
	for eid in routes.edges:
		var e: Dictionary = routes.edges[eid]
		if e["known"] or not e["search"]:
			continue
		var f: String = e["notice"][0]
		if not routes.nodes[f]["known"]:
			continue
		for id in _places():
			if _monster_gate(id):
				continue
			var way: Dictionary = routes.path_from(p.position, id)
			if not way.is_empty() and (way["nodes"] as Array).has(f):
				dest = id
				fork = f
				break
		if dest != "":
			break
	if dest == "":
		fail("lair:search — no known road passes a fork a hidden way leaves")
		return
	screen._set_speed(8.0)
	var at: Vector2 = routes.nodes[dest]["position"]
	for i in WALK_LIMIT:
		p = screen.world.player()
		if not screen._visit.is_empty():
			screen._close_visit()
		elif screen._combat != null:
			await _see_the_fight_out()
		elif is_instance_valid(screen._approach_card):
			_meet_them()
		elif screen._route_search and screen._lair_btn != null and screen._lair_btn.visible:
			if not screen.world.clock.is_paused():
				screen._toggle_pause()
			screen._lair_msg.text = ""
			screen._lair_btn.pressed.emit()
			if is_instance_valid(screen._map_die):
				screen._land_map_roll()   # what a click on the die does
			await _step(2)
			check("lair:search", "Survival" in screen._lair_msg.text,
				"searching at %s said '%s'" % [fork, screen._lair_msg.text])
			return
		elif p.at_goal() or screen.world.clock.is_paused():
			if p.position.distance_to(at) <= 8.0:
				fail("lair:search — marched past %s to %s and the button never offered the search" % [fork, dest])
				return
			_order(at)
		await _step()
	fail("lair:search — could not reach the fork %s in %d frames" % [fork, WALK_LIMIT])

# A band pinned on the road ahead, on the way to the far town.
func _band_in_the_way(way: String):
	var p = screen.world.player()
	_tour_dest = _far_town()
	var pts: PackedVector2Array = screen.world.routes.path_from(p.position, _tour_dest)["points"]
	var spot: Vector2 = pts[-1]
	var walked := 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if walked + seg >= 120.0:
			spot = pts[i - 1].lerp(pts[i], (120.0 - walked) / seg)
			break
		walked += seg
	var band = World.RoamingParty.new("tourband-%s" % way, spot, "goblinoid")
	var roster: Array[Dictionary] = [{"role": "light", "level": 1}, {"role": "heavy", "level": 1}]
	band.troops = roster
	RoutePins.pin(screen.world, band, "story")
	return band

func _close_in(p, _band) -> void:
	if p.at_goal() or screen.world.clock.is_paused():
		_order(screen.world.routes.nodes[_tour_dest]["position"])

func _band_gone(band) -> void:
	RoutePins.drop(screen.world, band)

# The poi id of a settlement, without a preload of core/world_routes.gd just
# for its one static helper.
class WorldRoutesId:
	static func settlement(id: String) -> String:
		return "settlement:%s" % id
