# #232 — a meeting on the road need not be a fight (core/approach.gd, the four
# ways the owner added on 2026-09-26), headless: demand is only on the card
# against a band the company plainly outclasses, and pays or fights; a
# caravan's packs are a road event the choice card can ask, and buying from
# them spends the price and fills the pack; news puts a way on the map (or a
# lair, on a map without roads); a job is a real delivery taken on the spot,
# once; a band with no world to point at offers what it always did.
#   godot --headless --path . -s tests/test_approach_road.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Approach = preload("res://core/approach.gd")
const RoadEvents = preload("res://core/road_events.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _small(routes := true) -> World:
	var scene = load("res://scenes/world/world.tscn").instantiate()
	var w: World = scene._small_world()
	scene.free()
	if routes:
		RouteTravel.adopt(w)
	return w

func _party() -> Party:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _band(faction: String, levels: Array, source := "") -> World.RoamingParty:
	var b := World.RoamingParty.new("band-%s-%d" % [faction, levels.size()], Vector2(60, 40), faction)
	for lv in levels:
		b.troops.append({"role": "light", "level": int(lv)})
	if source != "":
		b.ai = {"behavior": "met", "source": source}
	return b

func _ids(opts: Array) -> Array:
	return opts.map(func(o): return String(o["id"]))

func _init() -> void:
	FactionOpinion.reset()
	_demand()
	_trade()
	_news()
	_job()
	_no_world()
	print("test_approach_road: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _demand() -> void:
	var p := _party()
	var weak := _band("bandit", [1])
	var strong := _band("bandit", [5, 5, 5, 5, 5])
	check(Approach.can_demand(p, weak) and _ids(Approach.options(p, weak)).has("demand"), "demand: offered against a band the company outclasses")
	var ids := _ids(Approach.options(p, weak))
	check(ids.find("demand") == ids.find("parley") + 1, "demand: ...beside parley, the two tolls together (%s)" % [ids])
	check(not _ids(Approach.options(p, strong)).has("demand"), "demand: never against its betters")
	check(not _ids(Approach.options(p, _band("undead", [1]))).has("demand"), "demand: never against the mindless")
	check(not _ids(Approach.options(p, World.RoamingParty.new("empty", Vector2.ZERO, "bandit"))).has("demand"), "demand: never against a band of nobody")
	var row: Dictionary = Approach.options(p, weak).filter(func(o): return o["id"] == "demand")[0]
	check(str(Approach.tribute(weak)) in String(row["win"]) and row.has("dc") and row.has("cname"), "demand: the row names the tribute and who would roll")
	var paid := {}
	var fought := {}
	for seed_v in range(1, 200):
		var r := Approach.resolve(p, weak, "demand", RNG.new(seed_v))
		if bool(r["ok"]) and paid.is_empty():
			paid = r
		elif not bool(r["ok"]) and fought.is_empty():
			fought = r
		if not paid.is_empty() and not fought.is_empty():
			break
	check(not paid.is_empty() and not bool(paid["fight"]) and int(paid["tribute"]) == Approach.tribute(weak), "demand: made, they pay and there is no fight")
	check(fought.is_empty() or (bool(fought["fight"]) and not bool(fought["forced_ambush"])), "demand: refused, a plain fight — no first round handed over")

func _trade() -> void:
	var w := _small()
	var p := _party()
	var caravan := _band("human", [2, 2], "caravan")
	var patrol := _band("human", [2, 2], "patrol")
	check(_ids(Approach.options(p, caravan, false, w)).has("trade"), "trade: a caravan offers it")
	check(not _ids(Approach.options(p, patrol, false, w)).has("trade"), "trade: a patrol does not")
	var r := Approach.resolve(p, caravan, "trade", RNG.new(1), w)
	check(not bool(r["fight"]) and r.has("wares"), "trade: no fight, and the packs are opened")
	var wares: Dictionary = r["wares"]
	check(RoadEvents.validate([wares]).is_empty(), "trade: the packs are a sound road event (%s)" % [RoadEvents.validate([wares])])
	check((wares["choices"] as Array).size() == Approach.CARAVAN_WARES + 1, "trade: %d things and \"nothing today\"" % Approach.CARAVAN_WARES)
	check(Approach.wares(caravan) == wares, "trade: the same band shows the same packs (seeded)")
	var buy: Dictionary = wares["choices"][0]
	var price: int = int(buy["cost"]["gold"])
	var item: String = String(buy["then"]["item"])
	p.gold = price + 3
	var out := RoadEvents.choose(wares, String(buy["id"]), p, w, RNG.new(1))
	check(p.gold == 3 and p.stash_count(item) >= 1 and int(out["paid"]) == price, "trade: buying spends the price and fills the pack")
	p.gold = 0
	check(RoadEvents.options(wares, p, w)[0]["disabled"], "trade: a purse that is short cannot buy")

func _news() -> void:
	var w := _small()
	var p := _party()
	var patrol := _band("human", [2], "patrol")
	check(_ids(Approach.options(p, patrol, false, w)).has("news"), "news: offered by anybody on the road")
	var known0: int = w.routes.edges.values().filter(func(e): return e["known"]).size()
	var r := Approach.resolve(p, patrol, "news", RNG.new(1), w)
	check(not bool(r["fight"]) and String(r.get("trail", "")) != "", "news: a way on the map to somewhere (%s)" % r.get("text", ""))
	check(w.routes.edges.values().filter(func(e): return e["known"]).size() > known0, "news: ...and the way is known now")
	var free := _small(false)
	r = Approach.resolve(p, patrol, "news", RNG.new(1), free)
	check(r.has("lair"), "news: on a map without roads, a lair instead")

func _job() -> void:
	var w := _small()
	var p := _party()
	var patrol := _band("human", [2], "patrol")
	var row: Array = Approach.options(p, patrol, false, w).filter(func(o): return o["id"] == "job")
	check(not row.is_empty() and "◉" in String(row[0]["win"]), "job: offered, with where and what it pays (%s)" % (row[0]["win"] if not row.is_empty() else ""))
	var r := Approach.resolve(p, patrol, "job", RNG.new(1), w)
	var active: Array = p.quests.filter(func(q): return q["kind"] == "deliver_goods" and q["state"] == "active")
	check(active.size() == 1 and String(r.get("quest", "")) != "", "job: a delivery taken on the spot, in the log")
	check(not _ids(Approach.options(p, patrol, false, w)).has("job"), "job: ...once — the same run is not offered again")

func _no_world() -> void:
	var p := _party()
	check(_ids(Approach.options(p, _band("human", [2], "caravan"), false)) == ["greet", "pass"],
		"no world to point at: a friendly band offers what it always did")
