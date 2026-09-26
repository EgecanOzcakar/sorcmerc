# #232 / #234 — the road asks (core/road_events.gd), headless: the built-in
# table validates and keeps every D3 event reachable by "as the orders have
# it"; the validator turns each kind of authoring mistake into an error; the
# pick puts a follow-up first and never picks a chain-only event by chance; the
# choices say what they would take and refuse what cannot be paid; each shape
# of choice resolves (the orders, a check, a spell, a cost, a plain outcome);
# every effect does what it says — including a way on the map that was not
# there, shown at once or only noticed, and a fight; follow-ups chain and are
# saved; a pack's events join the table through the real pack pipeline.
#   godot --headless --path . -s tests/test_road_events.gd
extends SceneTree

const World = preload("res://core/world.gd")
const RoadEvents = preload("res://core/road_events.gd")
const Travel = preload("res://core/travel.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const WorldSave = preload("res://core/world_save.gd")
const Registry = preload("res://core/mod/registry.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Party = preload("res://core/party.gd")
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

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/roadev-%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	_the_table()
	_the_validator()
	_picking()
	_options()
	_choosing()
	_effects()
	_chains()
	_packs()
	print("test_road_events: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _the_table() -> void:
	var base: Array = RoadEvents.base()
	check(RoadEvents.validate(base).is_empty(), "the built-in table validates (%s)" % [RoadEvents.validate(base)])
	for e in base:
		var n: int = (e["choices"] as Array).size()
		check(n >= 2 and n <= 3, "%s offers 2 or 3 choices (%d)" % [e["id"], n])
	# Every D3 event is still on the road, and the standing orders still decide
	# it when the player lets them.
	for d3 in Travel.EVENTS:
		var e := RoadEvents.event(String(d3["id"]))
		check(not e.is_empty(), "D3's %s is on the road" % d3["id"])
		check(e.get("choices", []).any(func(c): return bool(c.get("orders", false))), "...with \"as the orders have it\"")
	check(base.any(func(e): return bool(e.get("chain", false))), "the table has follow-up-only events")

func _the_validator() -> void:
	var good := {"id": "x", "title": "X", "text": "x", "choices": [
		{"id": "a", "label": "A", "then": {"text": "a"}},
		{"id": "b", "label": "B", "check": {"skills": ["athletics"], "dc": 12}, "pass": {"text": "p"}, "fail": {"text": "f"}}]}
	check(RoadEvents.validate([good]).is_empty(), "validate: a sound event passes")
	var cases := {
		"one choice": func(e): e["choices"].pop_back(),
		"an unknown effect": func(e): e["choices"][0]["then"]["teleport"] = true,
		"a follow-up to nothing": func(e): e["choices"][0]["then"]["next"] = {"event": "nowhere"},
		"an item that is not one": func(e): e["choices"][0]["then"]["item"] = "a-sandwich",
		"a check without its fail": func(e): e["choices"][1].erase("fail"),
		"orders on a pack's own event": func(e): e["choices"][0] = {"id": "o", "label": "O", "orders": true},
		"a bad reveal": func(e): e["choices"][0]["then"]["reveal"] = "treasure",
		"a band that is not a country": func(e): e["bands"] = ["narnia"],
		"a needs nobody knows": func(e): e["needs"] = "sunshine",
		"two choices with one id": func(e): e["choices"][1]["id"] = "a",
		"a role that is no job": func(e): e["choices"][1]["check"]["role"] = "cook",
	}
	for why in cases:
		var e: Dictionary = good.duplicate(true)
		cases[why].call(e)
		check(not RoadEvents.validate([e]).is_empty(), "validate: %s is an error" % why)
	var own: Dictionary = good.duplicate(true)
	own["choices"][0]["then"]["item"] = "a-sandwich"
	check(RoadEvents.validate([own], [], {"a-sandwich": true}).is_empty(), "validate: an item the pack adds itself is an item")
	var chained: Dictionary = good.duplicate(true)
	chained["choices"][0]["then"]["next"] = {"event": "the-camp", "after": 30}
	check(RoadEvents.validate([chained], ["the-camp"]).is_empty(), "validate: a pack may chain into a built-in event")

func _picking() -> void:
	var w := _small()
	var p := _party()
	var seen := {}
	for i in 300:
		var e := RoadEvents.pick(p, w, RNG.new(i + 1))
		if not e.is_empty():
			seen[String(e["id"])] = true
	check(seen.size() >= 8, "pick: the road offers many events (%d kinds in 300 picks)" % seen.size())
	check(not seen.has("the-camp") and not seen.has("the-trapper"), "pick: a follow-up-only event never comes by chance")
	check(not seen.has("refugees"), "pick: an event whose need the world does not meet does not fire (no raid)")
	w.road_chain.append({"event": "the-camp", "due": w.clock.elapsed + 60.0})
	check(String(RoadEvents.pick(p, w, RNG.new(1)).get("id", "")) != "the-camp", "pick: a follow-up waits for its time")
	w.clock.elapsed += 61.0
	check(String(RoadEvents.pick(p, w, RNG.new(1)).get("id", "")) == "the-camp", "pick: ...then comes first")
	check(w.road_chain.is_empty(), "pick: ...once")

func _options() -> void:
	var w := _small()
	var p := _party()
	var toll := RoadEvents.event("toll")
	p.gold = 5
	var opts: Array = RoadEvents.options(toll, p, w)
	var pay: Dictionary = opts.filter(func(o): return o["id"] == "pay")[0]
	check(pay["disabled"] and pay["why"] == "not enough gold", "options: a price the purse cannot meet is offered but disabled")
	p.gold = 500
	pay = RoadEvents.options(toll, p, w).filter(func(o): return o["id"] == "pay")[0]
	check(not pay["disabled"] and "40 gold" in String(pay["hint"]), "options: ...and says what it costs (%s)" % pay["hint"])
	var ford: Array = RoadEvents.options(RoadEvents.event("ford"), p, w)
	var rope: Dictionary = ford.filter(func(o): return o["id"] == "rope")[0]
	check("DC 12" in String(rope["hint"]) and "Athletics" in String(rope["hint"]), "options: a check names who and at what (%s)" % rope["hint"])
	check(String(ford[0]["hint"]) == "the standing orders decide", "options: the orders' choice says so")
	check(RoadEvents.choose(toll, "pay", _broke(p), w, RNG.new(1)).is_empty(), "choose: a disabled choice cannot be taken")

func _broke(p):
	p.gold = 0
	return p

func _choosing() -> void:
	var w := _small()
	var p := _party()
	p.gold = 500
	# The orders: D3's own roll on D3's own event.
	var out := RoadEvents.choose(RoadEvents.event("rough-going"), "orders", p, w, RNG.new(3))
	check(out.has("ok") and out.has("nat") and out["choice"] == "orders", "choose: the orders roll D3's check (%s)" % [out.keys()])
	# A cost is paid, and a plain outcome applies.
	var g0: int = p.gold
	out = RoadEvents.choose(RoadEvents.event("toll"), "pay", p, w, RNG.new(3))
	check(p.gold == g0 - 40 and int(out["paid"]) == 40 and bool(out["ok"]), "choose: paying the toll costs 40 and lets the company through")
	# A check rolls with the standing order for its role, named.
	var scout: String = p.party_characters()[0].id
	Travel.set_orders(p, "normal", scout, "")
	out = RoadEvents.choose(RoadEvents.event("tracks"), "follow", p, w, RNG.new(9))
	check(String(out["char_id"]) == scout and bool(out["named"]), "choose: the scout the orders name makes the scout's roll")
	check(out.has("nat") and out.has("dc") and int(out["dc"]) == 14, "choose: ...and the card gets the roll")

func _effects() -> void:
	var w := _small()
	var p := _party()
	p.gold = 100
	var rng = RNG.new(5)
	var out := {}
	var t0: float = w.clock.elapsed
	RoadEvents.apply({"minutes": 90}, p, w, rng, out)
	check(is_equal_approx(w.clock.elapsed, t0 + 90.0) and out["minutes"] == 90.0, "effect: minutes")
	out = {}
	RoadEvents.apply({"gold": [20, 30]}, p, w, rng, out)
	check(int(out["gold"]) >= 20 and int(out["gold"]) <= 30 and p.gold == 100 + int(out["gold"]), "effect: gold found in its range")
	p.gold = 7
	out = {}
	RoadEvents.apply({"gold": -50}, p, w, rng, out)
	check(p.gold == 0 and int(out["gold"]) == -7, "effect: a loss never takes more than the purse")
	for ch in p.party_characters():
		ch.hp_current = 2
	out = {}
	RoadEvents.apply({"hurt": 0.9}, p, w, rng, out)
	check(p.party_characters().all(func(ch): return ch.hp_current >= 1), "effect: hurt never drops anybody")
	out = {}
	RoadEvents.apply({"heal": 0.5}, p, w, rng, out)
	check(int(out["healed"]) > 0, "effect: heal")
	out = {}
	RoadEvents.apply({"item": "salvage"}, p, w, rng, out)
	check(Travel.SALVAGE.has(String(out["item"])) and p.stash_count(String(out["item"])) >= 1, "effect: salvage lands in the pack")
	var home = Travel._nearest_settlement(w)
	var op0: float = FactionOpinion.get_opinion(home.faction)
	out = {}
	RoadEvents.apply({"opinion": 5}, p, w, rng, out)
	check(FactionOpinion.get_opinion(home.faction) > op0 and out["thanks"] == home.sname, "effect: opinion of the nearest town's people")
	var hidden: int = w.lairs.filter(func(l): return not l.discovered).size()
	out = {}
	RoadEvents.apply({"reveal": "lair"}, p, w, rng, out)
	check(w.lairs.filter(func(l): return not l.discovered).size() == hidden - 1 and out.has("lair"), "effect: reveal a lair")
	# A way that was on no map: shown at once...
	var known0: int = w.routes.edges.values().filter(func(e): return e["known"]).size()
	var edges0: int = w.routes.edges.size()
	out = {}
	RoadEvents.apply({"trail": {"known": true}}, p, w, rng, out)
	check(w.routes.edges.values().filter(func(e): return e["known"]).size() > known0, "effect: trail shown — a known way that was not there")
	check(out.get("trail_known", false) and String(out.get("trail", "")) != "", "effect: ...named on the card (%s)" % out.get("trail", ""))
	# ...or only noticed when passing its start.
	var w2 := _small()
	var e0: int = w2.routes.edges.size()
	var k0: int = w2.routes.edges.values().filter(func(e): return e["known"]).size()
	out = {}
	RoadEvents.apply({"trail": {"known": false}}, p, w2, rng, out)
	var added: Array = w2.routes.edges.values().filter(func(e): return e.get("why", "") == "road")
	check(w2.routes.edges.size() > e0 and w2.routes.edges.values().filter(func(e): return e["known"]).size() == k0,
		"effect: trail noticed — a way laid, hidden until passed")
	check(not added.is_empty() and added.all(func(e): return not (e["notice"] as Array).is_empty()), "effect: ...with a place it is noticed from")
	# No roads: the nearest lair instead.
	var free := _small(false)
	out = {}
	RoadEvents.apply({"trail": {"known": true}}, p, free, rng, out)
	check(out.has("lair") and not out.has("trail"), "effect: trail on a free-roaming map reveals a lair")
	# A fight: a hostile band spec for the approach card.
	out = {}
	RoadEvents.apply({"fight": {"faction": "road"}}, p, w, rng, out)
	check(out.has("fight") and bool(out["fight"]["hostile"]) and not (out["fight"]["troops"] as Array).is_empty(), "effect: fight — a hostile band with troops")
	out = {}
	RoadEvents.apply({"fight": {"faction": "bandit"}}, p, w, rng, out)
	check(String(out["fight"]["faction"]) == "bandit", "effect: fight — the named people")
	out = {}
	var xp0: int = p.party_characters()[0].xp
	RoadEvents.apply({"xp": 30}, p, w, rng, out)
	check(p.party_characters()[0].xp > xp0, "effect: xp")

func _chains() -> void:
	var w := _small()
	var p := _party()
	var out := {}
	RoadEvents.apply({"next": {"event": "the-trapper", "after": 120}}, p, w, RNG.new(1), out)
	check(out["chained"] == "the-trapper" and w.road_chain.size() == 1, "chain: a follow-up is put on the road ahead")
	var d: Dictionary = WorldSave.to_dict(w)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"]
	check(back.road_chain.size() == 1 and String(back.road_chain[0]["event"]) == "the-trapper"
		and is_equal_approx(float(back.road_chain[0]["due"]), w.clock.elapsed + 120.0), "chain: saved with the world")
	d.erase("road_chain")
	check(WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"].road_chain.is_empty(), "chain: an old save has none")
	# The whole chain, as a player makes it: follow the tracks, find the camp.
	var w2 := _small()
	var scout: String = p.party_characters()[0].id
	Travel.set_orders(p, "normal", scout, "")
	var followed := false
	for seed in range(1, 60):
		var o := RoadEvents.choose(RoadEvents.event("tracks"), "follow", p, w2, RNG.new(seed))
		if bool(o.get("ok", false)):
			followed = o.get("chained", "") == "the-camp"
			break
	check(followed, "chain: following the tracks puts the camp ahead")
	check(String(RoadEvents.pick(p, w2, RNG.new(1)).get("id", "")) == "the-camp", "chain: ...and the camp is the road's next event")

# Through the real pack pipeline: a pack's road_events file, scanned and applied.
func _packs() -> void:
	var root := "user://test/roadev-mods-%d-%d" % [OS.get_process_id(), randi()]
	var dir := root + "/bridge-pack"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "sorcmerc-pack", "api": 1, "id": "bridge-pack", "title": "Bridges",
		"road_events": "road.json"}))
	f.close()
	f = FileAccess.open(dir + "/road.json", FileAccess.WRITE)
	f.store_string(JSON.stringify([{"id": "old-bridge", "title": "The bridge is out", "text": "Half a bridge.",
		"choices": [{"id": "wade", "label": "Wade", "then": {"text": "Wet.", "minutes": 30}},
			{"id": "wait", "label": "Wait", "then": {"text": "A stranger.", "next": {"event": "the-trapper", "after": 0}}}]}]))
	f.close()
	var bad := root + "/broken-pack"
	DirAccess.make_dir_recursive_absolute(bad)
	f = FileAccess.open(bad + "/pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "sorcmerc-pack", "api": 1, "id": "broken-pack", "title": "Broken",
		"road_events": "road.json"}))
	f.close()
	f = FileAccess.open(bad + "/road.json", FileAccess.WRITE)
	f.store_string(JSON.stringify([{"id": "oops", "title": "Oops", "text": "x", "choices": [{"id": "a", "label": "A", "then": {"teleport": 1}}]}]))
	f.close()
	OS.set_environment("SORCMERC_MODS_DIR", ProjectSettings.globalize_path(root))
	Registry.scan(true)
	Registry.apply_data()
	var good = Registry.find("bridge-pack")
	var broken = Registry.find("broken-pack")
	check(good != null and good.live(), "pack: a sound road_events file loads (%s)" % [good.errors if good != null else "missing"])
	check(broken != null and broken.status == "broken" and not broken.errors.is_empty(), "pack: a broken one is refused, and says why")
	check(not RoadEvents.event("old-bridge").is_empty(), "pack: its event is on the road")
	check(RoadEvents.event("oops").is_empty(), "pack: the broken pack's is not")
	check(not RoadEvents.event("toll").is_empty(), "pack: the built-ins are still there")
	RoadEvents.set_packs([])
	OS.set_environment("SORCMERC_MODS_DIR", "")
