# #232 / #234 — the road asks (core/road_events.gd), headless: the built-in
# table validates and keeps every D3 event reachable by "as the orders have
# it"; the validator turns each kind of authoring mistake into an error; the
# pick puts a follow-up first and never picks a chain-only event by chance; the
# choices say what they would take and refuse what cannot be paid; each shape
# of choice resolves (the orders, a check, a spell, a cost, a plain outcome);
# every effect does what it says — including a way on the map that was not
# there, shown at once or only noticed, and a fight; follow-ups chain and are
# saved; a pack's events join the table through the real pack pipeline.
# The research batch (docs/research-road-events.md): the road remembers —
# cooldowns, one-time events, never the same twice running, sometimes nothing,
# all saved; the pace climbs between questions to about D3's six hours on
# average; a check can end in a triumph or a disaster; the right item makes a
# choice certain; a text can be one of several.
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
	_repetition()
	_pacing()
	_degrees()
	_uses()
	_variants()
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
		"a triumph without a check": func(e): e["choices"][0]["triumph"] = {"text": "t"},
		"a disaster that is no outcome": func(e): e["choices"][1]["disaster"] = "boom",
		"uses of no item": func(e): e["choices"][0] = {"id": "u", "label": "U", "uses": {"item": "a-sandwich"}, "pass": {"text": "p"}},
		"uses without its pass": func(e): e["choices"][0] = {"id": "u", "label": "U", "uses": {"item": "rope-of-climbing"}},
		"an empty text variant": func(e): e["text"] = ["one", ""],
		"an outcome text that is a number": func(e): e["choices"][0]["then"]["text"] = 7,
		"a cooldown that is not a number": func(e): e["cooldown"] = "a while",
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
		w.road_seen.clear()   # the table's variety, not the road's memory (_repetition)
		w.road_last = ""
		var e := RoadEvents.pick(p, w, RNG.new(i + 1))
		if not e.is_empty():
			seen[String(e["id"])] = true
	check(seen.size() >= 8, "pick: the road offers many events (%d kinds in 300 picks)" % seen.size())
	check(not seen.has("the-camp") and not seen.has("the-trapper"), "pick: a follow-up-only event never comes by chance")
	check(not seen.has("refugees"), "pick: an event whose need the world does not meet does not fire (no raid)")
	w.road_seen.clear()
	w.road_last = ""
	w.road_chain.append({"event": "the-camp", "due": w.clock.elapsed + 60.0})
	var early := ""
	for i in 20:
		early = String(RoadEvents.pick(p, w, RNG.new(i + 1)).get("id", ""))
		if early != "":
			break
	check(early != "" and early != "the-camp", "pick: a follow-up waits for its time (%s)" % early)
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

# The road remembers (proposal 1): never twice running, a cooldown, a one-time
# event never again, a quiet stretch now and then — and all of it saved.
func _repetition() -> void:
	var w := _small()
	var p := _party()
	var e := {}
	for i in 20:
		e = RoadEvents.pick(p, w, RNG.new(i + 1))
		if not e.is_empty():
			break
	var id := String(e.get("id", ""))
	check(id != "" and w.road_last == id and w.road_seen.has(id), "repeat: the road remembers what it asked (%s)" % id)
	var base := RoadEvents.event(id)
	check(not RoadEvents.rested(base, w), "repeat: ...and does not ask it again straight away")
	w.road_last = "someone-else"
	w.clock.elapsed += float(base.get("cooldown", RoadEvents.COOLDOWN)) - 1.0
	check(not RoadEvents.rested(base, w), "repeat: ...nor before its cooldown is out")
	w.clock.elapsed += 2.0
	check(RoadEvents.rested(base, w), "repeat: ...and may once it is")
	var again := false
	for i in 200:
		if String(RoadEvents.pick(p, w, RNG.new(1000 + i)).get("id", "")) == id:
			again = true
			break
		w.clock.elapsed += RoadEvents.COOLDOWN * 3.0
	check(again, "repeat: an event comes round again, in time")
	# Per-event cooldowns, as the table writes them.
	check(float(RoadEvents.event("good-ground")["cooldown"]) < RoadEvents.COOLDOWN
		and float(RoadEvents.event("toll")["cooldown"]) > RoadEvents.COOLDOWN, "repeat: an event may set its own cooldown")
	# Once: the bell in the river is met once a campaign.
	var bell := RoadEvents.event("the-bell")
	check(bool(bell.get("once", false)), "once: the bell is a one-time event")
	w.road_seen["the-bell"] = w.clock.elapsed
	w.road_last = ""
	w.clock.elapsed += 1440.0 * 365.0
	check(not RoadEvents.rested(bell, w), "once: ...never asked again, a year on")
	# Nothing, sometimes; a road that runs through every event never repeats one
	# inside its cooldown.
	var w2 := _small()
	var quiet := 0
	var last_at := {}
	var too_soon := 0
	var prev := ""
	var twice := 0
	for i in 400:
		w2.clock.elapsed += 360.0
		var got := RoadEvents.pick(p, w2, RNG.new(5000 + i))
		if got.is_empty():
			quiet += 1
			continue
		var gid := String(got["id"])
		if last_at.has(gid) and w2.clock.elapsed - float(last_at[gid]) < float(RoadEvents.event(gid).get("cooldown", RoadEvents.COOLDOWN)):
			too_soon += 1
		if gid == prev:
			twice += 1
		last_at[gid] = w2.clock.elapsed
		prev = gid
	check(quiet > 0 and quiet < 400, "nothing: now and then the road has nothing to say (%d of 400)" % quiet)
	check(too_soon == 0, "repeat: no event inside its own cooldown over 400 stretches (%d)" % too_soon)
	check(twice == 0, "repeat: never the same event twice running (%d)" % twice)
	# A follow-up is promised: it comes even when it was just asked.
	w2.road_last = "the-camp"
	w2.road_seen["the-camp"] = w2.clock.elapsed
	w2.road_chain.append({"event": "the-camp", "due": w2.clock.elapsed})
	check(String(RoadEvents.pick(p, w2, RNG.new(1)).get("id", "")) == "the-camp", "repeat: a follow-up is exempt")
	# Saved with the world; an old save remembers nothing.
	var d: Dictionary = WorldSave.to_dict(w2, p)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"]
	check(back.road_last == w2.road_last and back.road_seen.size() == w2.road_seen.size()
		and is_equal_approx(float(back.road_seen["the-camp"]), w2.clock.elapsed), "repeat: the road's memory is saved")
	d.erase("road_seen")
	d.erase("road_last")
	var old = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)))["world"]
	check(old.road_seen.is_empty() and old.road_last == "", "repeat: an old save remembers nothing")

# The pace (proposal 10): nothing just after a question, certain by PACE_MAX,
# about D3's six hours on average; a due follow-up asks at once.
func _pacing() -> void:
	check(RoadEvents.pace_chance(0.0) == 0.0 and RoadEvents.pace_chance(RoadEvents.PACE_MIN) == 0.0,
		"pace: nothing just after a question")
	check(RoadEvents.pace_chance(RoadEvents.PACE_MAX) == 1.0, "pace: certain by PACE_MAX")
	var w := _small()
	var rng := RNG.new(77)
	var total := 0.0
	var gaps: Array = []
	for n in 2000:
		var since := 0.0
		while true:
			since += RoadEvents.PACE_STEP
			if RoadEvents.asks_now(w, since, rng):
				break
		gaps.append(since)
		total += since
	var mean := total / gaps.size()
	check(mean > 320.0 and mean < 380.0, "pace: the gap averages about D3's six hours (%.0f minutes)" % mean)
	check(gaps.min() >= RoadEvents.PACE_MIN and gaps.max() <= RoadEvents.PACE_MAX and gaps.min() != gaps.max(),
		"pace: ...between %d and %d, never on a metronome" % [gaps.min(), gaps.max()])
	w.road_chain.append({"event": "the-camp", "due": w.clock.elapsed})
	check(RoadEvents.chain_due(w) and RoadEvents.asks_now(w, 0.0, rng), "pace: a follow-up that is due asks at once")

# Degrees of success (proposal 7).
func _degrees() -> void:
	var ch: Dictionary = RoadEvents.event("rough-going")["choices"].filter(func(c): return c["id"] == "push")[0]
	check(ch.has("triumph") and ch.has("disaster"), "degrees: pushing through the mud has four endings")
	check(RoadEvents.degree_of(ch, 12, 22, 14) == "triumph", "degrees: beating the DC by 8 is a triumph")
	check(RoadEvents.degree_of(ch, 20, 25, 30) == "triumph", "degrees: ...and so is a natural 20, short or not")
	check(RoadEvents.degree_of(ch, 10, 15, 14) == "", "degrees: a plain pass is a pass")
	check(RoadEvents.degree_of(ch, 3, 6, 14) == "disaster", "degrees: missing by 8 is a disaster")
	check(RoadEvents.degree_of(ch, 1, 30, 14) == "disaster", "degrees: ...and so is a natural 1")
	var plain: Dictionary = RoadEvents.event("tracks")["choices"].filter(func(c): return c["id"] == "follow")[0]
	check(RoadEvents.degree_of(plain, 20, 40, 14) == "" and RoadEvents.degree_of(plain, 1, 1, 14) == "",
		"degrees: a choice that wrote neither end is pass and fail")
	var w := _small()
	var p := _party()
	var seen := {}
	for seed in range(1, 400):
		var out := RoadEvents.choose(RoadEvents.event("rough-going"), "push", p, w, RNG.new(seed))
		var deg := String(out.get("degree", ""))
		if deg == "triumph":
			check(bool(out["ok"]) and out["kind"] == "good" and float(out["minutes"]) == -120.0, "degrees: a triumph plays its own outcome")
		elif deg == "disaster":
			check(not bool(out["ok"]) and out["kind"] == "bad" and float(out["minutes"]) == 300.0, "degrees: a disaster plays its own outcome")
		seen[deg] = true
		if seen.size() == 3:
			break
	check(seen.size() == 3, "degrees: one roll, pass or fail, triumph and disaster all come up (%s)" % [seen.keys()])

# The right thing makes it certain (proposal 8).
func _uses() -> void:
	var w := _small()
	var p := _party()
	var ford := RoadEvents.event("ford")
	var opt: Dictionary = RoadEvents.options(ford, p, w).filter(func(o): return o["id"] == "rope")[0]
	check(not opt["disabled"] and "vs DC" in String(opt["hint"]), "uses: without the rope, roping across is a roll (%s)" % opt["hint"])
	var out := RoadEvents.choose(ford, "rope", p, w, RNG.new(4))
	check(out.has("nat"), "uses: ...and it is rolled")
	p.stash_add("rope-of-climbing")
	opt = RoadEvents.options(ford, p, w).filter(func(o): return o["id"] == "rope")[0]
	check("certain" in String(opt["hint"]) and not "used up" in String(opt["hint"]), "uses: with it, the card says it is certain (%s)" % opt["hint"])
	var sure := true
	for seed in range(1, 30):
		out = RoadEvents.choose(ford, "rope", p, w, RNG.new(seed))
		sure = sure and bool(out["ok"]) and not out.has("nat") and String(out["used_item"]) == "rope-of-climbing"
	check(sure, "uses: ...and it is, every time, without a roll")
	check(p.stash_count("rope-of-climbing") == 1 and bool(out["used_kept"]), "uses: a rope of climbing is kept")
	check(String(out["text"]) != "" and not "%s" in String(out["text"]), "uses: ...and whoever used it is named")
	# An item that is used up, on a choice that needs it.
	var e := {"id": "x-drink", "title": "X", "text": "x", "choices": [
		{"id": "drink", "label": "Drink it", "uses": {"item": "potions-of-healing"}, "pass": {"text": "%s drinks.", "xp": 1}},
		{"id": "no", "label": "No", "then": {"text": "no"}}]}
	check(RoadEvents.validate([e]).is_empty(), "uses: a choice that needs an item validates (%s)" % [RoadEvents.validate([e])])
	opt = RoadEvents.options(e, p, w)[0]
	check(opt["disabled"] and "no " in String(opt["why"]), "uses: without the item it is offered but disabled (%s)" % opt["why"])
	check(RoadEvents.choose(e, "drink", p, w, RNG.new(1)).is_empty(), "uses: ...and cannot be taken")
	p.stash_add("potions-of-healing")
	opt = RoadEvents.options(e, p, w)[0]
	check(not opt["disabled"] and "used up" in String(opt["hint"]), "uses: with it, the card says it is used up (%s)" % opt["hint"])
	out = RoadEvents.choose(e, "drink", p, w, RNG.new(1))
	check(bool(out["ok"]) and p.stash_count("potions-of-healing") == 0 and not bool(out["used_kept"]), "uses: ...and it is")

# Text that varies (proposal 11).
func _variants() -> void:
	var w := _small()
	var p := _party()
	var raw = RoadEvents.event("good-ground")["text"]
	check(raw is Array and raw.size() >= 2, "variants: an event may carry several texts")
	var seen := {}
	for i in 60:
		w.road_seen.clear()
		w.road_last = ""
		w.clock.elapsed += 1.0
		var e: Dictionary = RoadEvents._asked(RoadEvents.event("good-ground"), w, RNG.new(i + 1))
		check(e["text"] is String and raw.has(e["text"]), "variants: the card gets one of them, as a string")
		seen[e["text"]] = true
	check(seen.size() == raw.size(), "variants: ...and every one of them comes up (%d of %d)" % [seen.size(), raw.size()])
	check(RoadEvents.event("good-ground")["text"] is Array, "variants: the table itself is left as written")
	var ev := {"id": "x-v", "title": "X", "text": "x", "choices": [
		{"id": "a", "label": "A", "then": {"text": ["%s one.", "%s two."]}},
		{"id": "b", "label": "B", "then": {"text": "b"}}]}
	var outs := {}
	for i in 30:
		outs[String(RoadEvents.choose(ev, "a", p, w, RNG.new(i + 1))["text"])] = true
	check(outs.size() == 2 and not outs.keys().any(func(t): return "%s" in t), "variants: an outcome's text varies too, and names who did it")
