# MEASUREMENT (2026-09-25) — the design audit's two estimates (§4.4), and the
# XP pace of the road (§7.3), played rather than computed. Not a test, and not
# part of tools/run_tests.sh.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/sweep_road_day.gd
#   LEVELS=3 RUNS=4 DAYS=6 REST=need ROTATE=1 godot ... -s tests/sweep_road_day.gd
#
# The audit estimated that the gold cost of a rest shrinks to nothing and that
# the 24-hour long-rest gate barely binds outside sites ("two road fights fill a
# day"), and that a drained company could swap in a fresh benched one as a
# second slot pool. Both were arithmetic. This plays the road instead: one
# company, carried from fight to fight on ONE set of resources, for DAYS days
# of world clock, RUNS times at each level.
#
# What a day is made of, each on the game's own clock and rules:
#   walking   WALK world-minutes between contacts, default 37: tests/
#             sweep_route_travel.gd measured 0.67 hostile contacts per 1000
#             units walked on today's free-roaming map, at World.SPEED 40 a
#             minute. Every contact is fought (engage; no parley or slipping by).
#   a fight   Scaler.roster_for(party, WorldThreat.BASELINE, ..., the power
#             scale WorldThreat.assess reads off the company as it stands) —
#             world.gd's encounter_spec with the country's scale at 1.0 (in
#             band), autoplayed, Encounter.resolve_outcome writing HP, slots
#             and pools back, and the clock billed world.gd's MINUTES_PER_ROUND
#             an hour a round.
#   a short   after a fight that leaves the company under half its HP, when
#   rest      SettlementVisit.can_short_rest allows (two per long rest).
#   a long    REST=gate: the moment the 24-hour gate opens (a company that
#   rest      sleeps whenever it may). REST=need: only when the gate is open
#             AND the company is spent (under half HP, or no slot left on any
#             caster). Eight hours, through SettlementVisit.rest (the world
#             walks through the night).
#   a defeat  counted, and the company is stood back up by a long rest on the
#             spot (the cost of losing is not this sweep's question).
#   ROTATE=1  a second preset trio sits on the bench, and before a fight the
#             two swap whenever the one marching is spent and the bench is not
#             — the audit's "second slot pool". The bench sleeps when the
#             company sleeps (core/settlement_visit.gd's rest walks the whole
#             roster) and earns nothing while benched.
#   ROTATE=eager  the same bench, swapped in before ANY fight it walks into in
#             better shape (HP plus slots) than the trio marching: the most a
#             player could get out of the bench as a second pool.
#
# Income per fight is the result's coin plus its loot sold at
# Campaign.SELL_RATE. The rest's price is quoted four ways (a town inn 20 ◉,
# a city inn 40, the same town at Known 10, a camp kit 150), each as a share of
# the income the days between rests brought in.
#
# Its tables are in core/settlement_visit.gd (the gate, and the rest's price)
# and core/party.gd (the bench), and the build log, "The measured pass".
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Campaign = preload("res://core/campaign.gd")
const Encounter = preload("res://core/encounter.gd")
const Leveling = preload("res://core/leveling.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const Visit = preload("res://core/settlement_visit.gd")
const World = preload("res://core/world.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const WorldThreat = preload("res://core/world_threat.gd")

const MINUTES_PER_ROUND := 60.0   # scenes/world/world.gd's
const REST_PRICES := [["town inn", 20], ["city inn", 40], ["town, Known", 10], ["camp kit", WorldCamp.CAMP_KIT_PRICE]]

var _walk := 37.0
var _policy := "gate"
var _rotate := false
var _eager := false

func _init() -> void:
	var runs := _env_i("RUNS", 10)
	var days := _env_i("DAYS", 10)
	_walk = float(_env_i("WALK", 37))
	_policy = OS.get_environment("REST") if OS.get_environment("REST") != "" else "gate"
	_rotate = OS.get_environment("ROTATE") in ["1", "eager"]
	_eager = OS.get_environment("ROTATE") == "eager"
	var levels: Array = [3, 6, 10]
	if OS.get_environment("LEVELS") != "":
		levels = Array(OS.get_environment("LEVELS").split(",")).map(func(x): return int(x))
	print("the road: %d runs x %d days a level, %.0f min walked between contacts, rest=%s, rotate=%s" % [
		runs, days, _walk, _policy, ("eager" if _eager else str(_rotate))])
	print("wounds curve HURT_AT %.2f floor %.2f; one fight = an hour a round on the clock" % [
		WorldThreat.HURT_AT, WorldThreat.SCALE_FLOOR])
	for L in levels:
		var t := {"fights": 0, "won": 0, "lost": 0, "long": 0, "short": 0, "rounds": 0, "coin": 0.0, "sold": 0.0,
			"xp": 0.0, "slots_at_rest": 0.0, "hp_at_rest": 0.0, "slots_in": 0.0, "hp_in": 0.0,
			"swaps": 0, "minutes": 0.0}
		for r in runs:
			_run(L, days, r + 1, t)
		_report(L, t, runs * days)
	quit(0)

func _env_i(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.get_environment(k) != "" else d

func _report(L: int, t: Dictionary, days: int) -> void:
	var f: float = maxf(1.0, float(t["fights"]))
	var rests: float = maxf(1.0, float(t["long"]))
	var income: float = float(t["coin"]) + float(t["sold"])
	var per_hero_xp: float = float(t["xp"]) / f
	var step: int = Leveling.xp_for_level(L + 1) - Leveling.xp_for_level(L)
	print("")
	print("level %d: %d fights in %d days, %.1f%% won, %.1f rounds a fight" % [
		L, int(t["fights"]), days, 100.0 * float(t["won"]) / f, float(t["rounds"]) / f])
	print("  %.2f fights a day, %.2f long rests a day, %.2f fights a long rest, %.2f short rests a long rest" % [
		f / days, float(t["long"]) / days, f / rests, float(t["short"]) / rests])
	print("  walking into a fight: %.0f%% HP, %.0f%% of slots; lying down to a long rest: %.0f%% HP, %.0f%% of slots" % [
		100.0 * float(t["hp_in"]) / f, 100.0 * float(t["slots_in"]) / f,
		100.0 * float(t["hp_at_rest"]) / rests, 100.0 * float(t["slots_at_rest"]) / rests])
	print("  income %.0f coin + %.0f sold = %.1f a fight, %.0f a long rest" % [
		t["coin"], t["sold"], income / f, income / rests])
	var line := "  a long rest costs:"
	for p in REST_PRICES:
		line += "  %s %d (%.0f%%)" % [p[0], p[1], 100.0 * float(p[1]) / maxf(1.0, income / rests)]
	print(line)
	print("  XP a hero a fight %.0f: %.1f fights to level %d (step %d)%s" % [per_hero_xp, step / maxf(1.0, per_hero_xp),
		L + 1, step, ("; %d swaps" % int(t["swaps"])) if _rotate else ""])

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party(L: int) -> Party:
	var p := Party.new()
	for ch in Presets.party_at(L):
		p.add_member(ch)
	if _rotate:
		for ch in Presets.party_at(L):
			ch.id = ch.id + "-b"
			ch.cname = ch.cname + " B"
			p.add_member(ch)
			p.bench(ch.id)   # the fourth seat fills itself; the second trio is the bench
	return p

# Pooled HP fraction and slots-left fraction over whoever is marching.
func _condition(p: Party, ids: Array) -> Array:
	var hp := 0.0
	var mx := 0.0
	var left := 0
	var full := 0
	for id in ids:
		var ch = p.get_member(id)
		var s: Dictionary = p.summary(id)
		hp += float(s["hp"])
		mx += float(s["max_hp"])
		for n in Adapter.slots_left(ch):
			left += int(n)
		for n in Adapter._full_slots(ch.sheet()):
			full += int(n)
	return [hp / maxf(1.0, mx), float(left) / maxf(1.0, float(full))]

func _spent(c: Array) -> bool:
	return c[0] < 0.5 or c[1] <= 0.0

func _run(L: int, days: int, run: int, t: Dictionary) -> void:
	var w := _world()
	var p := _party(L)
	p.last_long_rest_at = 0.0   # the company set out at dawn off a night's sleep
	var end: float = days * 1440.0
	var n := 0
	while w.clock.elapsed < end:
		n += 1
		w.clock.elapsed += _walk
		if _rotate:
			var here := _condition(p, p.active)
			var bench: Array = p.bench_list().map(func(ch): return ch.id)
			var there := _condition(p, bench) if bench.size() == p.active.size() else [0.0, 0.0]
			var better: bool = there[0] + there[1] > here[0] + here[1] + 0.1 if _eager \
				else (_spent(here) and not _spent(there))
			if bench.size() == p.active.size() and better:
				var out: Array = p.active.duplicate()
				for i in out.size():
					p.swap(out[i], bench[i])
				t["swaps"] += 1
		var cond := _condition(p, p.active)
		t["hp_in"] += cond[0]
		t["slots_in"] += cond[1]
		var r := _fight(p, L * 100000 + run * 1000 + n)
		t["fights"] += 1
		t["rounds"] += int(r["rounds"])
		w.clock.elapsed += int(r["rounds"]) * MINUTES_PER_ROUND
		if r["outcome"] == "Victory":
			t["won"] += 1
			t["coin"] += float(r["gold"])
			for id in r["loot"]:
				t["sold"] += Campaign.item_price(String(id)) * Campaign.SELL_RATE
			t["xp"] += float(r["xp"]) / p.active.size()
		else:
			t["lost"] += 1
			_long_rest(p, w, t, true)
			continue
		var after := _condition(p, p.active)
		if after[0] < 0.5 and Visit.can_short_rest(p, w):
			Visit.rest(p, w, "short-rest")
			t["short"] += 1
		if Visit.can_long_rest(p, w) and (_policy == "gate" or _spent(_condition(p, p.active))):
			_long_rest(p, w, t, false)

func _long_rest(p: Party, w: World, t: Dictionary, forced: bool) -> void:
	if not forced:
		var c := _condition(p, p.active)
		t["hp_at_rest"] += c[0]
		t["slots_at_rest"] += c[1]
	else:
		t["hp_at_rest"] += 0.0
		t["slots_at_rest"] += 0.0
	for ch in p.roster:
		ch.dead = false   # the cost of a defeat is not this sweep's question
	Visit.rest(p, w, "long-rest")
	t["long"] += 1

func _fight(p: Party, seed: int) -> Dictionary:
	var chars: Array = p.party_characters()
	var threat := WorldThreat.assess(p)
	var spec: Dictionary = Scaler.roster_for(chars, String(threat["difficulty"]), {}, "", seed,
		float(threat["power_scale"]))
	spec["seed"] = seed
	var team: Array = []
	for i in chars.size():
		team.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var cb = Encounter.build(spec, team)
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1
	return Encounter.resolve_outcome(cb, chars)
