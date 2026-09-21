# The lodge — one house bought where the company is Known, five rooms built
# onto it: the strongroom, the yard, the garden, the shrine, the map room.
#   docs/superpowers/specs/2026-09-21-lodge-design.md §1–§4
#   godot --headless --path . -s tests/test_lodge.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Lodge = preload("res://core/lodge.gd")
const Downtime = preload("res://core/downtime.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const WorldSave = preload("res://core/world_save.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Campaign = preload("res://core/campaign.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_buy()
	test_rooms()
	test_strongroom()
	test_garden()
	test_maproom()
	test_yard()
	test_shrine()
	test_restamp()
	test_save()
	print("test_lodge: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# A human city at the origin, an elf town, an orc camp (nobody buys a house
# among orcs), and three lairs near enough for the map room to know about.
func _world() -> World:
	var w = World.new()
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(300, 0), "elf", "town"))
	w.add_settlement(World.Settlement.new("ashpit", Vector2(600, 0), "orc", "camp"))
	w.add_lair(World.Lair.new("warren-a", Vector2(200, 0), "goblinoid"))
	w.add_lair(World.Lair.new("warren-b", Vector2(0, 200), "goblinoid"))
	w.add_lair(World.Lair.new("warren-c", Vector2(-200, 0), "goblinoid"))
	return w

func _party(gold := 1000) -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.gold = gold
	return p

func _fresh() -> void:
	FactionOpinion.reset()
	Ladder.reset()
	Ach._current = Ach.new()
	Ach.take_toasts()

# A company with a house at Riverhold and `gold` in the purse.
func _housed(gold := 2000) -> Array:
	_fresh()
	var w := _world()
	var party := _party(Lodge.HOUSE_COST + gold)
	Ladder.deed("human", Ladder.RUNG_AT[Ladder.KNOWN])
	Lodge.buy(party, w, w.settlements[0])
	return [w, party]

# --- the house ------------------------------------------------------------

func test_buy() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var town = w.settlements[1]
	var camp = w.settlements[2]
	var party := _party(Lodge.HOUSE_COST)
	check(party.lodge.is_empty() and Lodge.settlement(party, w) == null and Lodge.rooms_built(party) == 0, "a fresh company has no lodge")
	check(not Lodge.can_buy(party, w, city) and Lodge.buy(party, w, city).is_empty(), "a Stranger cannot buy a house")
	Ladder.deed("human", Ladder.RUNG_AT[Ladder.KNOWN])
	check(Lodge.can_buy(party, w, city), "a Known one can")
	check(not Lodge.can_buy(party, w, camp), "not among orcs")
	party.gold = Lodge.HOUSE_COST - 1
	check(not Lodge.can_buy(party, w, city), "not a coin short of it")
	party.gold = Lodge.HOUSE_COST
	var deeds_before: int = Ladder.deeds("human")
	var r: Dictionary = Lodge.buy(party, w, city)
	check(not r.is_empty() and "Riverhold" in String(r["text"]), "the deed is signed")
	check(party.gold == 0 and party.lodge["settlement_id"] == "riverhold" and party.lodge["rooms"].is_empty() and party.lodge["gold"] == 0,
		"the house cost, the empty rooms, the empty strongroom")
	check(Lodge.at(party, city) and not Lodge.at(party, town) and Lodge.settlement(party, w) == city, "the lodge is at Riverhold")
	check(Ladder.deeds("human") == deeds_before + 1, "a deed for the town's people")
	check(Ach.count("lodges") == 1 and Ach.is_unlocked("lodge_bought"), "A Door of Our Own")
	party.gold = 10000
	Ladder.deed("elf", Ladder.RUNG_AT[Ladder.KNOWN])
	check(not Lodge.can_buy(party, w, town) and Lodge.buy(party, w, town).is_empty() and party.gold == 10000, "one lodge only")

# --- the rooms ------------------------------------------------------------

func test_rooms() -> void:
	var hp := _housed(0)
	var w: World = hp[0]
	var party: Party = hp[1]
	check(not Lodge.can_build(_party(10000), "strongroom"), "no lodge, no room")
	check(not Lodge.can_build(party, "strongroom") and Lodge.build(party, w, "strongroom").is_empty(), "an empty purse builds nothing")
	check(not Lodge.can_build(party, "ballroom"), "nor a room the plan does not have")
	var n := 0
	for room in Lodge.ROOMS:
		var cost: int = Lodge.ROOMS[room]["cost"]
		party.gold = cost - 1
		check(not Lodge.can_build(party, room), "%s: a coin short" % room)
		party.gold = cost
		w.clock.elapsed = 100.0 * (n + 1)
		var r: Dictionary = Lodge.build(party, w, room)
		n += 1
		check(not r.is_empty() and party.gold == 0 and Lodge.has(party, room) and Lodge.rooms_built(party) == n, "%s: built, paid" % room)
		check(String(Lodge.ROOMS[room]["title"]) in String(r["text"]).to_lower(), "%s: the line names the room" % room)
		party.gold = cost
		check(not Lodge.can_build(party, room) and Lodge.build(party, w, room).is_empty() and party.gold == cost, "%s: built once" % room)
		party.gold = 0
	check(is_equal_approx(float(party.lodge["garden_at"]), 300.0) and is_equal_approx(float(party.lodge["maproom_at"]), 500.0),
		"the garden and the map room are stamped when they are built")
	check(Ach.count("lodge_rooms") == 5 and Ach.is_unlocked("lodge_full"), "Every Room Built")

# --- the strongroom -------------------------------------------------------

func test_strongroom() -> void:
	var hp := _housed(500)
	var w: World = hp[0]
	var party: Party = hp[1]
	check(not Lodge.deposit(party, 100) and party.gold == 500 and Lodge.stored(party) == 0, "no strongroom, nowhere to put it")
	party.gold += Lodge.ROOMS["strongroom"]["cost"]
	Lodge.build(party, w, "strongroom")
	check(not Lodge.deposit(party, 501) and not Lodge.deposit(party, 0) and not Lodge.deposit(party, -5), "the purse bounds a deposit")
	check(Lodge.deposit(party, 300) and party.gold == 200 and Lodge.stored(party) == 300, "300 ◉ goes into the strongroom")
	check(not Lodge.withdraw(party, 301) and not Lodge.withdraw(party, 0), "the strongroom bounds a withdrawal")
	check(Lodge.withdraw(party, 100) and party.gold == 300 and Lodge.stored(party) == 200, "100 ◉ comes back out")
	check(Lodge.spare_from_loss(party, 1000) == 300 and Lodge.stored(party) == 200, "a loss is the purse's at most; the strongroom is not in it")
	check(Lodge.spare_from_loss(party, 50) == 50, "a small loss is itself")

# --- the garden -----------------------------------------------------------

func _potions(party) -> int:
	var n := 0
	for e in party.stash:
		if e["item_id"] == Lodge.GARDEN_POTION and Party.is_identified(e):
			n += int(e["quantity"])
	return n

func test_garden() -> void:
	var hp := _housed(Lodge.ROOMS["garden"]["cost"])
	var w: World = hp[0]
	var party: Party = hp[1]
	var r: Dictionary = Lodge.collect(party, w)
	check(r["potions"] == 0 and r["leads"].is_empty() and r["text"] == "", "no garden, nothing to collect")
	var period: float = Lodge.GARDEN_DAYS * Downtime.DAY
	Lodge.build(party, w, "garden")
	check(Lodge.collect(party, w)["potions"] == 0 and _potions(party) == 0, "nothing the day it is planted")
	w.clock.elapsed += period - 1.0
	check(Lodge.collect(party, w)["potions"] == 0, "nothing a minute short of the first")
	w.clock.elapsed += 1.0
	r = Lodge.collect(party, w)
	check(r["potions"] == 1 and _potions(party) == 1 and "one potion" in String(r["text"]), "one potion after GARDEN_DAYS")
	check(is_equal_approx(float(party.lodge["garden_at"]), w.clock.elapsed), "...and the garden is re-stamped")
	w.clock.elapsed += period * 1.5
	r = Lodge.collect(party, w)
	check(r["potions"] == 1 and is_equal_approx(float(party.lodge["garden_at"]), w.clock.elapsed - period * 0.5),
		"a period and a half is one potion, and the half is kept growing")
	w.clock.elapsed += period * 0.5
	check(Lodge.collect(party, w)["potions"] == 1, "...so the next comes half a period later")
	w.clock.elapsed += period * 20
	r = Lodge.collect(party, w)
	check(r["potions"] == Lodge.GARDEN_CAP and _potions(party) == 3 + Lodge.GARDEN_CAP and "three potions" in String(r["text"]),
		"a season away is the cap")
	check(is_equal_approx(float(party.lodge["garden_at"]), w.clock.elapsed), "a full garden starts over from now")
	w.clock.elapsed += period - 1.0
	check(Lodge.collect(party, w)["potions"] == 0, "...nothing banked past it")

# --- the map room ---------------------------------------------------------

func test_maproom() -> void:
	var hp := _housed(Lodge.ROOMS["maproom"]["cost"])
	var w: World = hp[0]
	var party: Party = hp[1]
	var period: float = Lodge.MAPROOM_DAYS * Downtime.DAY
	Lodge.build(party, w, "maproom")
	w.clock.elapsed += period - 1.0
	check(Lodge.collect(party, w)["leads"].is_empty(), "nothing a minute short of the first")
	w.clock.elapsed += 1.0
	var r: Dictionary = Lodge.collect(party, w)
	check(r["leads"].size() == 1 and r["leads"][0].has("lair_id") and "map room" in String(r["text"]), "one lead after MAPROOM_DAYS")
	check(w.lairs.filter(func(l): return l.discovered).size() == 1, "...and it marks a lair")
	w.clock.elapsed += period * 10
	r = Lodge.collect(party, w)
	check(r["leads"].size() == Lodge.MAPROOM_CAP and w.lairs.filter(func(l): return l.discovered).size() == 3, "a season away is the cap")
	w.clock.elapsed += period * 10
	r = Lodge.collect(party, w)
	check(r["leads"].is_empty() and is_equal_approx(float(party.lodge["maproom_at"]), w.clock.elapsed),
		"with nothing left to mark, the wall stays as it is and the clock still moves")

# --- the yard -------------------------------------------------------------

func test_yard() -> void:
	var hp := _housed(Lodge.ROOMS["yard"]["cost"] + 1000)
	var w: World = hp[0]
	var party: Party = hp[1]
	var city = w.settlements[0]
	var vera = party.get_member("vera")
	Visit.visit(city, w)
	check(not Lodge.can_retrain(party, w, vera), "no yard, no retraining")
	Lodge.build(party, w, "yard")
	check(not Lodge.can_retrain(party, w, vera), "a hero with no general feat has nothing to swap")
	vera.feats.append("sentinel")
	vera.dirty()
	Downtime.decide_ability(vera, "sentinel")
	var key := "ability-choice:feat:sentinel:0"
	check(vera.choices.has(key), "the +1 was decided (the test's own setup)")
	check(Lodge.can_retrain(party, w, vera), "now the yard will take them")
	check(Lodge.retrain(party, w, vera, "alert", "durable").is_empty(), "an origin feat is not swapped")
	check(Lodge.retrain(party, w, vera, "sentinel", "alert").is_empty(), "nor swapped for")
	check(Lodge.retrain(party, w, vera, "sentinel", "sentinel").is_empty(), "nor for itself")
	var bed: int = Downtime.bed_cost(city, Lodge.RETRAIN_DAYS)
	party.gold = Lodge.RETRAIN_COST + bed - 1
	var r: Dictionary = Lodge.retrain(party, w, vera, "sentinel", "durable")
	check(not r.get("ok", true) and "sentinel" in vera.feats, "a purse short of the fee and the bed swaps nothing")
	party.gold = Lodge.RETRAIN_COST + bed
	var before: float = w.clock.elapsed
	var con_before: int = vera.sheet().abilities["con"]["total"]
	var str_before: int = vera.sheet().abilities["str"]["total"]
	var dex_before: int = vera.sheet().abilities["dex"]["total"]
	r = Lodge.retrain(party, w, vera, "sentinel", "durable")
	check(r.get("ok", false) and not "sentinel" in vera.feats and "durable" in vera.feats, "the swap")
	check(not vera.choices.has(key) and vera.choices.has("ability-choice:feat:durable:0"), "the old +1 is forgotten, the new one decided")
	check(vera.sheet().abilities["con"]["total"] == con_before + 1
		and vera.sheet().abilities["str"]["total"] + vera.sheet().abilities["dex"]["total"] == str_before + dex_before - 1,
		"...and the sheet says so")
	check(not vera.sheet().pending.any(func(p): return ":feat:" in String(p["key"])), "nothing pending off either feat")
	check(party.gold == 0 and is_equal_approx(w.clock.elapsed, before + Lodge.RETRAIN_DAYS * Downtime.DAY), "the fee, the bed, three days")
	check(r["cost"] == Lodge.RETRAIN_COST and r["days"] == Lodge.RETRAIN_DAYS and "Durable" in String(r["text"]) and "Sentinel" in String(r["text"]), "the row reports what it took")
	check(Ach.count("downtime_days") == Lodge.RETRAIN_DAYS, "the days are downtime's")
	party.gold = 1000
	check(not Lodge.can_retrain(party, w, vera) and Lodge.retrain(party, w, vera, "durable", "sentinel").is_empty(), "once per hero per visit")
	Visit.visit(city, w)
	check(Lodge.can_retrain(party, w, vera), "a new visit, a new swap")
	check(Lodge.retrain(party, w, vera, "durable", "sentinel").get("ok", false) and "sentinel" in vera.feats and not "durable" in vera.feats, "...back again")

# --- the shrine -----------------------------------------------------------

func test_shrine() -> void:
	var hp := _housed(Lodge.ROOMS["shrine"]["cost"])
	var w: World = hp[0]
	var party: Party = hp[1]
	var city = w.settlements[0]
	Visit.visit(city, w)
	check(Lodge.bless(party, w).is_empty() and not party.blessed, "no shrine, no blessing")
	Lodge.build(party, w, "shrine")
	var r: Dictionary = Lodge.bless(party, w)
	check(not r.is_empty() and party.blessed, "the shrine's blessing")
	party.blessed = false
	check(Lodge.bless(party, w).is_empty() and not party.blessed, "once per visit")
	w.clock.elapsed += 10.0
	Visit.visit(city, w)
	check(not Lodge.bless(party, w).is_empty() and party.blessed, "a new visit, a new blessing")

# --- once a visit, across a re-read ----------------------------------------

func test_restamp() -> void:
	var hp := _housed(Lodge.ROOMS["shrine"]["cost"] + Lodge.ROOMS["yard"]["cost"] + 1000)
	var w: World = hp[0]
	var party: Party = hp[1]
	var city = w.settlements[0]
	var vera = party.get_member("vera")
	Visit.visit(city, w)
	Lodge.build(party, w, "shrine")
	Lodge.build(party, w, "yard")
	vera.feats.append("sentinel")
	vera.dirty()
	Lodge.retrain(party, w, vera, "sentinel", "durable")
	Lodge.bless(party, w)
	var old: float = city.last_visited
	w.clock.elapsed += 10.0
	Visit.visit(city, w)
	Lodge.restamp(party, city, old, city.last_visited)
	check(not Lodge.can_retrain(party, w, vera) and Lodge.bless(party, w).is_empty(), "the visit's stamps move with the re-read")

# --- the save -------------------------------------------------------------

func test_save() -> void:
	var hp := _housed(5000)
	var w: World = hp[0]
	var party: Party = hp[1]
	var city = w.settlements[0]
	Visit.visit(city, w)
	for room in ["strongroom", "garden", "shrine"]:
		Lodge.build(party, w, room)
	Lodge.deposit(party, 250)
	Lodge.bless(party, w)
	party.lodge["retrained"] = {"vera": city.last_visited}
	var d: Dictionary = JSON.parse_string(JSON.stringify(Lodge.to_dict(party)))
	var back := _party(0)
	Lodge.from_dict(back, d)
	check(back.lodge["settlement_id"] == "riverhold" and back.lodge["rooms"] == ["strongroom", "garden", "shrine"], "the house and its rooms")
	check(back.lodge["gold"] is int and Lodge.stored(back) == 250, "the strongroom, as an int")
	check(back.lodge["garden_at"] is float and is_equal_approx(float(back.lodge["garden_at"]), float(party.lodge["garden_at"]))
		and float(back.lodge["maproom_at"]) < 0.0, "the garden's stamp, and the map room's unbuilt one")
	check(Lodge.bless(back, w).is_empty() and not Lodge.can_retrain(back, w, back.get_member("vera")), "the once-a-visit stamps survive the file")
	Lodge.from_dict(back, null)
	check(back.lodge.is_empty(), "nothing loads as nothing")
	Lodge.from_dict(back, {"rooms": ["yard"]})
	check(back.lodge.is_empty(), "a lodge with no town is no lodge")
	# the world save and the campaign save carry it beside downtime
	var rd: Dictionary = WorldSave.to_dict(w, party)
	check(rd["party"].get("lodge", {}).get("settlement_id", "") == "riverhold", "the lodge rides the world save's party dict")
	check(Lodge.stored(WorldSave.from_dict(rd)["party"]) == 250, "...and reads back")
	var cr = Campaign.new(party)
	var cd: Dictionary = CampaignSave.to_dict(cr)
	check(cd["party"].get("lodge", {}).get("settlement_id", "") == "riverhold", "the lodge rides the campaign save's party dict")
	check(Lodge.stored(CampaignSave.from_dict(cd).party) == 250, "...and reads back")
