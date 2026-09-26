# #231 phase 2 — bands pinned to a road (core/route_pins.gd), headless: a band
# stood on the nearest road and taken off the map, met when the company walks
# past it (at any clock speed, and only when it walks), put back when the
# meeting leaves it standing and held until the company is clear, gone when it
# is put down; the towns' bounties and the jobs that name them; a raid standing
# at a town's gate instead of walking to it, landing, and turned; a story's
# spawn_party and a pack's parties[] on a route world; the save.
#   godot --headless --path . -s tests/test_route_pins.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const WorldSave = preload("res://core/world_save.gd")
const Raids = preload("res://core/raids.gd")
const Quest = preload("res://core/quest.gd")
const QuestPosting = preload("res://core/quest_posting.gd")
const Visit = preload("res://core/settlement_visit.gd")
const StoryRuntime = preload("res://core/mod/story_runtime.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Grudges = preload("res://core/grudges.gd")
const Party = preload("res://core/party.gd")

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

func _route_world() -> World:
	FactionOpinion.reset()
	Grudges.reset()
	var w := _small()
	RouteTravel.adopt(w)
	return w

func _band(id: String, pos: Vector2, faction := "orc") -> World.RoamingParty:
	var b := World.RoamingParty.new(id, pos, faction)
	b.troops.append({"role": "heavy", "level": 2})
	return b

func _settlement(w: World, id: String):
	for s in w.settlements:
		if s.id == id:
			return s
	return null

func _lair(w: World, id: String):
	for l in w.lairs:
		if l.id == id:
			return l
	return null

# A point `d` along the known road from the company's spot toward `to`, and the
# walk there: the order given, then world-minutes until it is reached.
func _walk_to(w: World, to: String, cap := 400) -> Array:
	var events: Array = []
	var p = w.player()
	RouteTravel.go(w, to)
	for _i in cap:
		if p.at_goal():
			break
		var from: Vector2 = p.position
		w.tick(1.0)
		var evs := RouteTravel.step(w, from)
		events.append_array(evs)
		if evs.any(func(e): return e.has("band")):
			break
	return events

func _pin_and_meet() -> void:
	var w := _route_world()
	var p = w.player()
	# Greenmarch's road, a little short of the town: somewhere the march passes.
	var way: Dictionary = w.routes.path_from(p.position, "settlement:greenmarch")
	var pts: PackedVector2Array = way["points"]
	var mid: Vector2 = pts[pts.size() / 2]
	var b := _band("orc-pin", mid + Vector2(15, 15))
	w.add_party(b)
	check(RoutePins.pin(w, b, "story"), "pin: pinned")
	check(not w.parties.has(b) and w.pinned.has(b), "pin: off the map, on the road")
	check(float(w.routes.locate(b.position, true)["distance"]) < 0.01, "pin: stands on a known road")
	check(RoutePins.is_pinned(b) and RoutePins.why(b) == "story", "pin: says why")
	check(String(b.ai["behavior"]) == "pinned", "pin: nothing steers it")
	check(w.band("orc-pin") == b and w.bands().has(b), "pin: World.band finds it")
	# Standing still next to it meets nothing.
	check(RoutePins.reached(w, b.position + Vector2(5, 0), b.position + Vector2(5, 0)) == null,
		"reached: a company standing still meets nothing")
	# The march passes it: the road sends it, hostile, whatever the dice say.
	var evs := _walk_to(w, "settlement:greenmarch")
	var hits: Array = evs.filter(func(e): return e.has("band"))
	check(hits.size() == 1 and hits[0]["band"] == b, "march: walks up to the pinned band")
	check(not hits.is_empty() and hits[0]["kind"] == "threat" and bool(hits[0]["hostile"]), "march: an orc band is a threat")
	check(w.parties.has(b) and not w.pinned.has(b), "march: on the map for its meeting")
	check(p.position.distance_to(b.position) <= RoutePins.REACH + 1.0, "march: met where it stands")
	# A meeting that leaves it standing (a slip): back on its spot, held.
	WorldAI.truce(b, p, w.clock.elapsed)
	RouteTravel.forget(w, b)
	check(w.pinned.has(b) and not w.parties.has(b), "forget: a band left standing is pinned again")
	check(bool(b.ai["pin"].get("held", false)), "forget: ...held")
	check(not b.ai.has("break_off"), "forget: ...with nowhere to walk off to")
	# Walking on past it does not meet it again.
	var again := _walk_to(w, "settlement:greenmarch")
	check(not again.any(func(e): return e.has("band")), "held: walking on does not reopen the meeting")
	check(p.position.distance_to(Vector2(420, -180)) < 0.5, "held: the march arrives")
	check(not bool(b.ai["pin"].get("held", false)), "held: let go once the company is clear")
	# Back the other way: it is there again.
	var back := _walk_to(w, "settlement:riverhold")
	check(back.any(func(e): return e.get("band") == b), "held: met again on the way back")
	# Put down: whoever put it down erased it; forget leaves it gone.
	w.parties.erase(b)
	RouteTravel.forget(w, b)
	check(w.band("orc-pin") == null, "put down: gone from the map and the road")

# An 8x clock moves the company far in one frame: the walk is measured, not
# its end point.
func _fast_frame() -> void:
	var w := _route_world()
	var b := _band("fast", Vector2(200, 0))
	w.add_party(b)
	RoutePins.pin(w, b, "story")
	var spot: Vector2 = b.position
	check(RoutePins.reached(w, spot + Vector2(-300, 0), spot + Vector2(300, 0)) == b, "fast: a frame that steps over it meets it")
	check(RoutePins.reached(w, spot + Vector2(-300, 200), spot + Vector2(300, 200)) == null, "fast: a frame that passes far off does not")

func _bounties() -> void:
	var w := _route_world()
	var posted: Array = RoutePins.tick(w, 2000.0)
	var towns: Array = []
	for s in w.settlements:
		if not WorldAI.is_monster(s.faction):
			towns.append(s.id)
	check(posted.size() == towns.size(), "bounty: every civilized town on settled ground prices one (%d of %d)" % [posted.size(), towns.size()])
	for b in posted:
		var s = _settlement(w, String(b.ai["pin"]["town"]))
		var d: float = b.position.distance_to(s.position)
		check(d >= RoutePins.BOUNTY_NEAR - 0.01 and d <= RoutePins.BOUNTY_FAR + 0.01, "bounty: %s stands in its town's reach (%.0f)" % [b.id, d])
		check(float(w.routes.locate(b.position, true)["distance"]) < 0.01, "bounty: %s on a known road" % b.id)
		check(WorldAI.is_monster(b.faction) and not b.troops.is_empty(), "bounty: %s is a monster band with troops" % b.id)
		for x in w.settlements:
			check(x.position.distance_to(b.position) >= d - 0.01, "bounty: %s is nearest its own town" % b.id)
		check(w.bounty_due[s.id] < 0.0, "bounty: %s's town waits on it" % b.id)
	check(RoutePins.tick(w, 2100.0).is_empty(), "bounty: one at a time")
	# Deterministic: the same map posts the same bands.
	var w2 := _route_world()
	var posted2: Array = RoutePins.tick(w2, 2000.0)
	check(posted.map(func(b): return [b.id, b.position, b.faction]) == posted2.map(func(b): return [b.id, b.position, b.faction]),
		"bounty: seeded — the same map posts the same bands")
	# The job: the board posts it as a hunt, the map marks the road.
	var rh = _settlement(w, "riverhold")
	var mine = RoutePins.bounty_of(w, "riverhold")
	var pool: Array = Quest._world_quest_pool(w, rh)
	check(pool.any(func(q): return q["kind"] == "hunt_party" and q["id"] == mine.id), "job: the board's pool names the bounty band")
	var party := Party.new()
	var q: Dictionary = {"id": "world:hunt_party:%s:0" % mine.id, "kind": "hunt_party", "state": "active",
		"target_party_id": mine.id, "giver_node_id": "riverhold", "title": "Hunt"}
	party.quests.append(q)
	var marks: Array = Quest.map_marks(w, party)
	check(marks.size() == 1 and (marks[0]["pos"] as Vector2).is_equal_approx(mine.position), "job: the mark points at the road it stands on, fog or not")
	check(QuestPosting._target_position(w, q) == mine.position, "job: the posting reads where it stands")
	# Put down: the town's clock starts again, and the next is a new band.
	w.pinned.erase(mine)
	Quest.record_party_defeated(party, mine.id)
	check(String(party.quests[0]["state"]) == "complete", "job: done when the band is put down")
	RoutePins.tick(w, 3000.0)
	var due: float = float(w.bounty_due["riverhold"])
	check(due >= 3000.0 + RoutePins.BOUNTY_EVERY and due < 3000.0 + RoutePins.BOUNTY_EVERY + RoutePins.BOUNTY_JITTER,
		"bounty: the next is priced two days on (%.0f)" % due)
	var next: Array = RoutePins.tick(w, due)
	check(next.size() == 1 and next[0].id != mine.id and RoutePins.bounty_of(w, "riverhold") == next[0], "bounty: a new band, then")
	# A free-roaming map prices none: its bands walk.
	var free := _small()
	check(RoutePins.tick(free, 2000.0).is_empty() and free.pinned.is_empty(), "bounty: none on a free-roaming map")

func _raid() -> void:
	var w := _route_world()
	var tangle = _lair(w, "the-tangle")
	var gm = _settlement(w, "greenmarch")
	var now: float = Raids.due_at(tangle) + 1.0
	for l in w.lairs:   # only the Tangle's clock runs out for this
		if l != tangle:
			l.raid_at = now
	var lines: Array = Raids.tick(w, now)
	var b = Raids.band_of(w, tangle)
	check(b != null and w.pinned.has(b) and not w.parties.has(b), "raid: the band is pinned, not walking the map")
	check(lines.any(func(t): return "camped outside Greenmarch" in String(t)), "raid: the town says so (%s)" % [lines])
	check(b != null and String(b.ai["phase"]) == "siege" and Raids.turnable(b), "raid: straight to the siege, and turnable")
	check(b != null and b.position.distance_to(gm.position) <= Visit.BATTLE_RADIUS, "raid: at the gate, inside the town's battle radius (%.0f)" % (b.position.distance_to(gm.position) if b != null else -1.0))
	var e: Dictionary = w.routes.edges.get(String(b.ai["pin"]["edge"]), {}) if b != null else {}
	check(not e.is_empty() and "settlement:greenmarch" in [e["a"], e["b"]], "raid: on one of the town's own roads")
	check(Raids.settlement_tag(w, gm, now).begins_with(" — raiders at the gate"), "raid: the label says so")
	check(Raids.tick(w, now + 60.0).is_empty() and Raids.band_of(w, tangle) == b, "raid: it stands, it does not walk")
	# Left alone, it lands and goes home — off the map, at once.
	lines = Raids.tick(w, now + Raids.SIEGE + 1.0)
	check(gm.raided_by == "the-tangle", "raid: lands")
	check(w.band(b.id) == null and tangle.raid_band == "", "raid: the band is gone home")
	check(lines.any(func(t): return "is raided" in String(t)), "raid: the landing is said")
	# Turned: a second map, the band met and put down before it lands.
	var w2 := _route_world()
	var t2 = _lair(w2, "the-tangle")
	for l in w2.lairs:
		if l != t2:
			l.raid_at = now
	Raids.tick(w2, now)
	var b2 = Raids.band_of(w2, t2)
	RoutePins.take(w2, b2)
	check(w2.parties.has(b2) and Raids.band_of(w2, t2) == b2, "turned: on the map for its meeting, still the lair's band")
	w2.parties.erase(b2)   # what _launch_combat does with a band it beat
	Raids.tick(w2, now + 10.0)
	check(t2.raid_band == "" and is_equal_approx(t2.raid_at, now + 10.0), "turned: the lair's clock starts again")
	Raids.tick(w2, now + Raids.SIEGE + 1.0)
	check(_settlement(w2, "greenmarch").raided_by == "", "turned: the raid never lands")

func _story_and_pack() -> void:
	var w := _route_world()
	var lines: Array = StoryRuntime._spawn({"id": "the-red-hand", "near": "riverhold", "offset": [120, 40],
		"faction": "bandit", "name": "The Red Hand", "troops": [{"role": "heavy", "level": 2}]}, w)
	var b = w.band("the-red-hand")
	check(b != null and w.pinned.has(b) and not w.parties.has(b), "story: spawn_party pins on a route world")
	check(b != null and RoutePins.why(b) == "story" and float(w.routes.locate(b.position, true)["distance"]) < 0.01, "story: ...on a known road")
	check(lines.size() == 1 and "Red Hand" in String(lines[0]), "story: and says so")
	StoryRuntime._spawn({"id": "the-red-hand", "near": "riverhold", "faction": "bandit"}, w)
	check(w.bands().filter(func(x): return x.id == "the-red-hand").size() == 1, "story: firing twice does not double it")
	# A free-roaming map: it walks, as it always did.
	var free := _small()
	StoryRuntime._spawn({"id": "the-red-hand", "near": "riverhold", "faction": "bandit"}, free)
	check(free.parties.any(func(x): return x.id == "the-red-hand") and free.pinned.is_empty(), "story: walks on a free-roaming map")
	# A pack's map: its authored bands are pinned, not dropped.
	var pw := _small()
	var authored: Array = pw.parties.filter(func(q): return not q.is_player).map(func(q): return q.id)
	RouteTravel.adopt(pw, true)
	check(pw.parties.size() == 1 and pw.pinned.size() == authored.size(), "pack: every authored band pinned (%d of %d)" % [pw.pinned.size(), authored.size()])
	check(pw.pinned.all(func(q): return RoutePins.why(q) == "pack" and authored.has(q.id)), "pack: ...by its own id")

func _save() -> void:
	var w := _route_world()
	RoutePins.tick(w, 2000.0)
	var b := _band("held-one", Vector2(100, 0))
	w.add_party(b)
	RoutePins.pin(w, b, "story")
	RoutePins.take(w, b)
	RoutePins.put_back(w, b)
	var d: Dictionary = WorldSave.to_dict(w)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"]
	check(back.pinned.size() == w.pinned.size(), "save: the pinned bands come back (%d)" % back.pinned.size())
	var hb = back.band("held-one")
	check(hb != null and back.pinned.has(hb) and not back.parties.has(hb), "save: ...pinned, not on the map")
	check(hb != null and hb.position.is_equal_approx(b.position) and (hb.ai["pin"]["at"] as Vector2).is_equal_approx(b.position), "save: ...where they stood")
	check(hb != null and bool(hb.ai["pin"].get("held", false)), "save: ...held if they were")
	check(back.bounty_due.size() == w.bounty_due.size() and back.bounty_due.keys().all(func(k): return is_equal_approx(float(back.bounty_due[k]), float(w.bounty_due[k]))), "save: the towns' bounty clocks")
	# Saved mid-meeting: the screen's clear_met puts it back on its spot.
	RoutePins.take(back, hb)
	var d2: Dictionary = WorldSave.to_dict(back)
	var again = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d2)))["world"]
	RouteTravel.clear_met(again)
	check(again.pinned.any(func(x): return x.id == "held-one") and not again.parties.any(func(x): return x.id == "held-one"), "save: a meeting the game was closed on puts it back")
	# An old save has neither key.
	d.erase("pinned")
	d.erase("bounty_due")
	var old = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"]
	check(old != null and old.pinned.is_empty() and old.bounty_due.is_empty(), "save: an old save loads with none")

func _init() -> void:
	_pin_and_meet()
	_fast_frame()
	_bounties()
	_raid()
	_story_and_pack()
	_save()
	print("test_route_pins: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
