# #231 phase 1 — a company on the roads (core/route_travel.gd), headless: a
# world adopted into routes, the march, what the road does frame by frame, the
# search at a fork, a landmark's lead laying a trail, the camp, the save.
#   godot --headless --path . -s tests/test_route_travel.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const WorldSave = preload("res://core/world_save.gd")
const Landmarks = preload("res://core/landmarks.gd")
const Grudges = preload("res://core/grudges.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _small() -> World:
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var w: World = scene._small_world()
	scene.free()
	return w

# Walk the company along its orders, a world-minute at a time, the way the
# screen's frames do; collect what the road does. Stops at the goal.
func _walk(w: World, cap_minutes := 400) -> Array:
	var events: Array = []
	var p = w.player()
	for _i in cap_minutes:
		if p.at_goal():
			break
		var from: Vector2 = p.position
		w.tick(1.0)
		events.append_array(RouteTravel.step(w, from))
	return events

func _adopt() -> void:
	var w := _small()
	check(not RouteTravel.on(w), "adopt: a built map is free-roaming until adopted")
	check(w.parties.size() > 1, "adopt: the builder put bands down")
	RouteTravel.adopt(w)
	check(RouteTravel.on(w), "adopt: now a route world")
	check(w.parties.size() == 1 and w.parties[0].is_player, "adopt: nobody on the map but the company")
	check(w.fallen.is_empty() and w.route_walked == 0.0, "adopt: nothing waiting to come back, the odometer at zero")
	var at: Dictionary = w.routes.locate(w.player().position, true)
	check(float(at["distance"]) < 0.01, "adopt: the company stands on a known road")

func _march() -> void:
	FactionOpinion.reset()
	Grudges.reset()
	var w := _small()
	RouteTravel.adopt(w)
	var p = w.player()
	check(not RouteTravel.go(w, "lair:goblin-warren"), "march: no known road to a hidden lair")
	check(p.at_goal(), "march: ...and the orders are unchanged")
	check(RouteTravel.go(w, "settlement:greenmarch"), "march: a known town")
	var way: Dictionary = w.routes.path_from(p.position, "settlement:greenmarch")
	check(p.goal != p.position and p.route.size() + 1 >= 1, "march: orders given")
	var events := _walk(w)
	check(p.position.distance_to(Vector2(420, -180)) < 0.5, "march: arrives at Greenmarch (%s)" % p.position)
	# The odometer adds each frame's straight displacement, so a frame that turns
	# a corner shaves it. A world-minute's step (40 units) shaves ~2%; a real
	# frame moves a few units and shaves nothing worth counting.
	check(absf(w.route_walked - float(way["length"])) < 0.03 * float(way["length"]), "march: the odometer reads the road's length (%.0f vs %.0f)" % [w.route_walked, float(way["length"])])
	# Every point walked was on the network.
	check(float(w.routes.locate(p.position, true)["distance"]) < 0.5, "march: still on the road at the end")
	var threats := events.filter(func(e): return e["kind"] == "threat")
	for t in threats:
		check(t["spec"]["hostile"] and not t["spec"]["troops"].is_empty(), "march: a threat is a hostile band with troops")
	# place_near / place_name: what a click means.
	check(RouteTravel.place_near(w, Vector2(425, -185), 20.0) == "settlement:greenmarch", "click: near a town is the town")
	check(RouteTravel.place_near(w, Vector2(425, -185), 2.0) == "", "click: out of reach is nothing")
	check(RouteTravel.place_name(w, "settlement:greenmarch") == "Greenmarch", "click: the town's name")

func _the_road_sends() -> void:
	# A long walk back and forth: the road sends threats at about the rate the
	# model says, and meetings near friendly towns — deterministically.
	FactionOpinion.reset()
	Grudges.reset()
	var w := _small()
	RouteTravel.adopt(w)
	var threats := 0
	var meetings := 0
	var expected := 0.0
	var towns := ["settlement:greenmarch", "settlement:riverhold", "settlement:dun-arrow", "settlement:riverhold"]
	var p = w.player()
	for lap in 12:
		RouteTravel.go(w, towns[lap % towns.size()])
		for _i in 400:
			if p.at_goal():
				break
			var from: Vector2 = p.position
			w.tick(1.0)
			expected += RouteEncounters.rate(w, p.position) * from.distance_to(p.position) / 1000.0
			for e in RouteTravel.step(w, from):
				if e["kind"] == "threat": threats += 1
				elif e["kind"] == "meet": meetings += 1
	check(w.route_walked > 5000.0, "road: a long walk (%.0f)" % w.route_walked)
	check(threats > 0 and absf(threats - expected) < 4.0 * sqrt(maxf(expected, 1.0)), "road: %d threats, %.1f expected" % [threats, expected])
	check(meetings > 0, "road: meetings near friendly towns (%d)" % meetings)
	# Determinism: the same walk on a fresh copy meets the same things.
	var w2 := _small()
	RouteTravel.adopt(w2)
	var again := 0
	var p2 = w2.player()
	for lap in 12:
		RouteTravel.go(w2, towns[lap % towns.size()])
		for _i in 400:
			if p2.at_goal():
				break
			var from: Vector2 = p2.position
			w2.tick(1.0)
			for e in RouteTravel.step(w2, from):
				if e["kind"] == "threat": again += 1
	check(again == threats, "road: the same walk, the same road (%d vs %d)" % [again, threats])

func _bands() -> void:
	var w := _small()
	RouteTravel.adopt(w)
	var spec := RouteEncounters.compose(w, w.player().position, {"faction": "goblinoid", "source": "country"}, RNG.new(5), "k")
	var b = RouteTravel.band_for(w, spec)
	check(w.parties.has(b) and b.position == w.player().position, "band: stands on the map where the company is")
	check(WorldAI.is_hostile(b, w.player()), "band: hostile, so the approach card asks")
	RouteTravel.forget(w, b)
	check(not w.parties.has(b), "band: gone when the meeting is")
	var left = RouteTravel.band_for(w, spec)
	RouteTravel.clear_met(w)
	check(not w.parties.has(left) and w.parties.size() == 1, "band: a meeting the game was closed on ends with it")
	var roamer := World.RoamingParty.new("wolves", Vector2.ZERO, "beast")
	w.add_party(roamer)
	RouteTravel.forget(w, roamer)
	check(w.parties.has(roamer), "band: forget() only takes what the road sent")

func _search_and_marks() -> void:
	var w := _small()
	RouteTravel.adopt(w)
	var p = w.player()
	# Stand at the fork a hidden lair's track leaves from.
	var track := ""
	for eid in w.routes.edges:
		var e: Dictionary = w.routes.edges[eid]
		if e["kind"] == "track" and not e["known"] and w.routes.nodes[e["notice"][0]]["known"]:
			track = eid
			break
	check(track != "", "search: a hidden lair track leaves a known fork")
	var fork: String = w.routes.edges[track]["notice"][0]
	p.position = w.routes.nodes[fork]["position"]
	check(RouteTravel.searchable(w).has(track), "search: offered at the fork")
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	var found := {}
	for day in 30:
		found = RouteTravel.search(w, party, RNG.new(100 + day))
		if not found.is_empty() and found["ok"]:
			break
	check(not found.is_empty() and found["ok"], "search: a pass within a month of tries")
	var lair_id: String = w.routes.edges[track]["b"] if String(w.routes.edges[track]["b"]).begins_with("lair:") else w.routes.edges[track]["a"]
	var lair = w.lairs.filter(func(l): return "lair:" + l.id == lair_id)[0]
	check(lair.discovered, "search: the lair is discovered")
	check(found["places"].has(lair.sname), "search: and named")
	check(RouteTravel.go(w, lair_id), "search: and walkable")
	# The other door: a lair marked found elsewhere (a rumour) gets its way revealed.
	var other = w.lairs.filter(func(l): return not l.discovered)[0]
	other.discovered = true
	RouteTravel.step(w, p.position)
	check(w.routes.nodes["lair:" + other.id]["known"], "marks: a rumoured lair's track is revealed on the next frame")
	check(not w.routes.path(w.routes.nearest_node(p.position), "lair:" + other.id).is_empty(), "marks: ...and it can be walked to")

func _lead() -> void:
	var w := _small()
	RouteTravel.adopt(w)
	var ruins = w.landmarks.filter(func(m): return m.kind == "ruins")[0]
	var e := {"text": "A lead."}
	var before: int = w.routes.stats()["trail"]
	check(RouteTravel.lead(w, ruins, e), "lead: a trail is laid")
	check(w.routes.stats()["trail"] > before, "lead: counted as a trail")
	check(String(e["text"]).contains("on no map") and String(e.get("lair", "")) != "", "lead: the card says where (%s)" % e.get("lair", ""))
	check(w.routes.nodes["landmark:" + ruins.id]["known"] and ruins.found, "lead: the landmark it was read at is found")
	# Through Landmarks' own door: the "read" answer's reward goes the same way.
	var w2 := _small()
	RouteTravel.adopt(w2)
	var r2 = w2.landmarks.filter(func(m): return m.kind == "ruins")[0]
	var e2 := {"text": "x"}
	Landmarks._lead_or_trail(w2, r2, e2)
	check(w2.routes.stats()["trail"] > 0, "lead: Landmarks' lead lays a trail on a route world")
	var w3 := _small()
	var e3 := {"text": "x"}
	Landmarks._lead_or_trail(w3, w3.landmarks[0], e3)
	check(w3.routes == null and e3.has("lair") or String(e3["text"]).contains("Nothing"), "lead: a free-roaming world keeps the old lead")

func _camp() -> void:
	FactionOpinion.reset()
	var w := _small()
	RouteTravel.adopt(w)
	var gate := Vector2(0, 0)          # Riverhold
	var wild := Vector2(-520, -250)    # the giant hold's door
	var at_gate := RouteTravel.camp_ambush_pct(w, gate)
	var at_lair := RouteTravel.camp_ambush_pct(w, wild)
	check(at_gate < WorldCamp.AMBUSH_CHANCE_PCT, "camp: safer under a town's walls (%d%%)" % at_gate)
	check(at_lair > WorldCamp.AMBUSH_CHANCE_PCT, "camp: riskier at a lair's door (%d%%)" % at_lair)
	check(at_lair <= roundi(WorldCamp.AMBUSH_CHANCE_PCT * RouteTravel.CAMP_MAX_MULT), "camp: held to three times")
	check(not WorldCamp.ambush_roll(RNG.new(1), 0) and WorldCamp.ambush_roll(RNG.new(1), 100), "camp: ambush_roll takes the chance it is given")

func _save() -> void:
	Grudges.reset()
	var w := _small()
	RouteTravel.adopt(w)
	RouteTravel.go(w, "settlement:greenmarch")
	_walk(w)
	var ruins = w.landmarks.filter(func(m): return m.kind == "ruins")[0]
	RouteTravel.lead(w, ruins, {"text": ""})
	Grudges.add("gnoll", Grudges.BAND)
	var d: Dictionary = JSON.parse_string(JSON.stringify(WorldSave.to_dict(w)))
	Grudges.reset()
	var back = WorldSave.from_dict(d)["world"]
	check(RouteTravel.on(back), "save: a route world loads as one")
	check(JSON.stringify(back.routes.to_dict()) == JSON.stringify(w.routes.to_dict()), "save: the network whole, trails and all")
	check(is_equal_approx(back.route_walked, w.route_walked), "save: the odometer")
	check(is_equal_approx(Grudges.get_grudge("gnoll"), Grudges.BAND), "save: the grudges")
	var free := _small()
	var d2: Dictionary = JSON.parse_string(JSON.stringify(WorldSave.to_dict(free)))
	check(not RouteTravel.on(WorldSave.from_dict(d2)["world"]), "save: a free-roaming world stays one")
	d2.erase("routes")
	d2.erase("grudges")
	d2.erase("route_walked")
	check(WorldSave.from_dict(d2) != null, "save: an old save without the keys loads")
	Grudges.reset()

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	_adopt()
	_march()
	_the_road_sends()
	_bands()
	_search_and_marks()
	_lead()
	_camp()
	_save()
	FactionOpinion.reset()
	Grudges.reset()
	print("test_route_travel: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
