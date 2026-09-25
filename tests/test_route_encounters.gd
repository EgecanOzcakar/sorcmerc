# #231 — who the company meets on the road (core/route_encounters.gd). The
# model only, headless.
#   godot --headless --path . -s tests/test_route_encounters.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBands = preload("res://core/world_bands.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const Regions = preload("res://core/regions.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# A map wide enough that the heartland reaches past every radius in play: the
# human town is the anchor at the origin, and a lair far out stretches the
# extent to 2400, so the heartland runs to 1200 and the deeps start past 2088.
func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("home", Vector2(0, 0), "human", "city"))
	w.add_lair(World.Lair.new("far", Vector2(2400, 0), "dragon"))
	return w

func _sum(cands: Array) -> float:
	var t := 0.0
	for c in cands:
		t += float(c["rate"])
	return t

func _rings() -> void:
	FactionOpinion.reset()
	var w := _world()
	# Away from the town and the lair: the country and nothing else.
	var quiet := Vector2(0, 900)
	var f: Dictionary = RouteEncounters.factors(w, quiet)
	check(f["ring"] == "heartland", "rings: (0,900) is heartland")
	check(is_equal_approx(float(f["cover"]), 1.0) and is_equal_approx(float(f["lure"]), 1.0), "rings: no cover, no lure out there")
	check(is_equal_approx(float(f["rate"]), RouteEncounters.BASE), "rings: the rate is BASE")
	var cands := RouteEncounters.candidates(w, quiet)
	check(is_equal_approx(_sum(cands), float(f["rate"])), "rings: candidates share out the whole rate")
	for c in cands:
		check(c["source"] == "country" and Regions.HOMES["heartland"].has(c["faction"]), "rings: %s lives in the heartland" % c["faction"])
	# The mix is WorldBands' own table: bandits and goblins (5 each) over beasts (5)...
	var by := {}
	for c in cands:
		by[c["faction"]] = float(c["rate"])
	check(is_equal_approx(by.get("bandit", 0.0), by.get("goblinoid", -1.0)), "rings: equal KINDS weight, equal share")
	# The ring decides who and how strong, not how often (BASE's comment).
	var deep := Vector2(0, 2300)
	check(RouteEncounters.factors(w, deep)["ring"] == "deeps", "rings: (0,2300) is the deeps")
	check(is_equal_approx(RouteEncounters.rate(w, deep), RouteEncounters.rate(w, quiet)), "rings: as busy as the heartland")
	for c in RouteEncounters.candidates(w, deep):
		check(Regions.HOMES["deeps"].has(c["faction"]), "rings: %s lives in the deeps" % c["faction"])

func _cover() -> void:
	FactionOpinion.reset()
	var w := _world()
	var gate := Vector2(0, 20)
	var far := Vector2(0, 900)
	var neutral := RouteEncounters.rate(w, gate)
	check(neutral < RouteEncounters.rate(w, far), "cover: a town's gate is safer than the open road")
	check(is_equal_approx(RouteEncounters.regard("human"), 0.5), "cover: neutral regard is half")
	FactionOpinion.set_opinion("human", 60.0)
	check(RouteEncounters.rate(w, gate) < neutral, "cover: a people that likes you keeps its roads clearer")
	check(is_equal_approx(RouteEncounters.regard("human"), 1.0), "cover: +50 and over is all of it")
	FactionOpinion.set_opinion("human", FactionOpinion.HOSTILE)
	var f: Dictionary = RouteEncounters.factors(w, gate)
	check(is_equal_approx(float(f["cover"]), 1.0), "cover: none at all from a people hostile to you")
	check(f["hunt"].has("human"), "hunt: and they come looking")
	var hunters: Array = RouteEncounters.candidates(w, gate).filter(func(c): return c["source"] == "hunt")
	check(hunters.size() == 1 and hunters[0]["faction"] == "human", "hunt: the hunt is a candidate of its own")
	check(is_equal_approx(_sum(RouteEncounters.candidates(w, gate)), float(f["rate"])), "hunt: still sums to the rate")
	check(RouteEncounters.factors(w, Vector2(0, 900))["hunt"].is_empty(), "hunt: only near their towns")
	FactionOpinion.reset()

func _lure() -> void:
	FactionOpinion.reset()
	var w := _world()
	var den = w.add_lair(World.Lair.new("den", Vector2(0, 900), "undead"))
	var at := Vector2(0, 880)
	var f: Dictionary = RouteEncounters.factors(w, at)
	check(float(f["lure"]) > 1.9, "lure: a live lair next to the road (%.2f)" % float(f["lure"]))
	var undead: Array = RouteEncounters.candidates(w, at).filter(func(c): return c["faction"] == "undead")
	check(undead.size() == 1 and undead[0]["source"] == "lair", "lure: pulls its own people into a country that is not theirs")
	den.looted = true
	check(is_equal_approx(float(RouteEncounters.factors(w, at)["lure"]), 1.0), "lure: an emptied lair pulls nothing")
	# An orc hold is a lair with a market.
	w.add_settlement(World.Settlement.new("hold", Vector2(900, 0), "orc", "camp"))
	var near_hold: Array = RouteEncounters.candidates(w, Vector2(900, 30)).filter(func(c): return c["faction"] == "orc")
	check(not near_hold.is_empty(), "lure: an orc hold's roads have orcs on them")
	# A raided town has the raiders' people on its roads.
	den.looted = false
	var town = w.add_settlement(World.Settlement.new("vale", Vector2(-900, 0), "elf", "town"))
	var before: float = RouteEncounters.factors(w, Vector2(-900, 20))["lure"]
	town.raided_by = "den"
	check(float(RouteEncounters.factors(w, Vector2(-900, 20))["lure"]) > before, "raid: a raided town's roads are worse")
	check(not RouteEncounters.candidates(w, Vector2(-900, 20)).filter(func(c): return c["faction"] == "undead").is_empty(), "raid: ...with the raiders on them")

func _rolls() -> void:
	FactionOpinion.reset()
	var w := _world()
	var at := Vector2(0, 900)
	var a := RouteEncounters.roll(w, at, "e|3|0")
	var b := RouteEncounters.roll(w, at, "e|3|0")
	check(JSON.stringify(a) == JSON.stringify(b), "roll: the same key is the same road")
	# Over many stretches, the rolls land where the rate says they will.
	var fired := 0
	var n := 4000
	for k in n:
		if not RouteEncounters.roll(w, at, "stretch|%d" % k).is_empty():
			fired += 1
	var expect := RouteEncounters.chance(w, at) * n
	check(absf(fired - expect) < 4.0 * sqrt(expect), "roll: %d fired, %.0f expected" % [fired, expect])
	check(is_equal_approx(RouteEncounters.chance(w, at, 0.0), 0.0), "roll: no road walked, no chance")
	# Keys: the same stretch on the same day, a new one the next step or day.
	var k0 := RouteEncounters.step_key("x~y", 150.0, 100.0)
	check(k0 == RouteEncounters.step_key("x~y", 199.0, 1400.0), "key: same stretch, same day")
	check(k0 != RouteEncounters.step_key("x~y", 250.0, 100.0), "key: the next stretch")
	check(k0 != RouteEncounters.step_key("x~y", 150.0, 100.0 + FactionOpinion.DAY), "key: the next day")

func _compose() -> void:
	FactionOpinion.reset()
	var w := _world()
	var rng = load("res://core/rng.gd").new(7)
	var spec := RouteEncounters.compose(w, Vector2(0, 900), {"faction": "gnoll", "source": "country"}, rng, "k")
	var row: Array = WorldBands.KINDS.filter(func(k): return k["id"] == spec["kind"])
	check(row.size() == 1 and row[0]["faction"] == "gnoll", "compose: a gnoll band is a gnoll KINDS row (%s)" % spec["kind"])
	check(spec["troops"].size() == row[0]["roles"].size(), "compose: the row's troop template")
	for t in spec["troops"]:
		check(int(t["level"]) >= 1 and int(t["level"]) <= 3, "compose: heartland levels (%d)" % int(t["level"]))
	check(spec["hostile"], "compose: monsters are hostile")
	var rare := RouteEncounters.compose(w, Vector2(0, 2300), {"faction": "dragon", "source": "lair"}, rng, "k2")
	check(rare["troops"].size() == RouteEncounters.RARE_ROLES.size(), "compose: a faction with no KINDS row still fields a band")
	for t in rare["troops"]:
		check(int(t["level"]) >= 10, "compose: deeps levels (%d)" % int(t["level"]))
	# A people 40 points past hostile sends two more heavies than its patrol row.
	FactionOpinion.set_opinion("human", -90.0)
	var hunt := RouteEncounters.compose(w, Vector2(0, 20), {"faction": "human", "source": "hunt"}, rng, "k3")
	var patrol: Array = WorldBands.KINDS.filter(func(k): return k["id"] == "human-patrol")[0]["roles"]
	check(hunt["kind"] == "human-patrol", "compose: a hunting people sends its patrol")
	check(hunt["troops"].size() == patrol.size() + 2, "compose: heavier for the grudge (%d)" % hunt["troops"].size())
	check(hunt["hostile"], "compose: and it is hostile")
	FactionOpinion.set_opinion("human", -55.0)
	check(RouteEncounters.compose(w, Vector2(0, 20), {"faction": "human", "source": "hunt"}, rng, "k4")["troops"].size() == patrol.size(),
		"compose: just past hostile is the plain patrol")
	# As a band: what the approach card and the fight already take.
	var b = RouteEncounters.band(spec, Vector2(5, 900))
	check(b.id == spec["id"] and b.faction == "gnoll" and b.position == Vector2(5, 900), "band: id, faction, place")
	check(b.troops.size() == spec["troops"].size() and not b.is_player, "band: its troops, not the player")
	var player := World.RoamingParty.new("player", Vector2.ZERO, "human", true)
	check(WorldAI.is_hostile(b, player), "band: hostile to the company")
	check(not w.parties.has(b), "band: not put on the map")
	FactionOpinion.reset()

func _init() -> void:
	_rings()
	_cover()
	_lure()
	_rolls()
	_compose()
	FactionOpinion.reset()
	print("test_route_encounters: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
