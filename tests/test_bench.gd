# The bench (the design audit, docs/audit-game-design.md §2.4; core/bench.gd):
# a merc left out of the marching order grows restless, is warned about once,
# and after that may leave — never the founder, never below the minimum
# roster, seeded so a reload replays the same morning. And the bench sits at
# the fire under a roof (core/party_opinion.gd's camp_moment with `bench`), but
# not on the open road. Plus the save: the clocks round-trip through the world
# save, and a save from before them loads with none.
#   godot --headless --path . -s tests/test_bench.gd
extends SceneTree

const Bench = preload("res://core/bench.gd")
const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const WorldSave = preload("res://core/world_save.gd")
const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")

const DAY := Bench.DAY

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_clock_starts_and_stops()
	test_warned_once_then_may_leave()
	test_never_the_founder()
	test_never_below_the_minimum()
	test_leaving_is_seeded()
	test_marching_is_the_cure()
	test_fireside_with_the_bench()
	test_save_round_trip()
	print("test_bench: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Five: Vera (the founder, first on the books), Pike and Ilsa, Thrun and Gera.
# The first four march; Gera sits out.
func _party() -> Party:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func test_clock_starts_and_stops() -> void:
	var p := _party()
	check(p.bench_list().size() == 1 and p.bench_list()[0].id == "gera", "Gera is the one benched")
	Bench.sync(p, 100.0)
	check(p.bench_clock.keys() == ["gera"] and float(p.bench_clock["gera"]["since"]) == 100.0,
		"her clock starts the first time anyone looks")
	Bench.sync(p, 5000.0)
	check(float(p.bench_clock["gera"]["since"]) == 100.0, "...and keeps its start")
	check(Bench.days(p, "gera", 100.0 + 3.5 * DAY) == 3, "whole days on the bench")
	check(Bench.days(p, "vera", 100.0 + 3.5 * DAY) == 0, "a marching merc has been on it no days")
	p.swap("pike", "gera")
	Bench.sync(p, 6000.0)
	check(not p.bench_clock.has("gera") and float(p.bench_clock["pike"]["since"]) == 6000.0,
		"swapped in, her clock is gone; Pike's starts")
	p.get_member("pike").dead = true
	Bench.sync(p, 7000.0)
	check(not p.bench_clock.has("pike"), "the dead are not restless")

func test_warned_once_then_may_leave() -> void:
	var p := _party()
	var e: Dictionary = {}
	var t0 := 0.0
	Bench.sync(p, t0)
	check(Bench.tick(p, t0 + (Bench.RESTLESS_DAYS - 1) * DAY).is_empty(), "nothing before the restless days")
	e = Bench.tick(p, t0 + Bench.RESTLESS_DAYS * DAY)
	check(e.get("kind", "") == "restless" and e.get("id", "") == "gera", "then the warning: %s" % str(e))
	check("Gera" in String(e.get("text", "")) and "leave the company" in String(e.get("text", "")),
		"...which names her and says what happens next: %s" % e.get("text", ""))
	check(not "'" in String(e.get("text", "")).replace("company's", ""), "...in the house voice, no contractions")
	check(Bench.restless(p, "gera"), "she is restless now")
	check(Bench.tick(p, t0 + (Bench.RESTLESS_DAYS + 1) * DAY).is_empty(), "the warning is said once")
	# Before the leave days are up, she stays whatever the dice would say.
	for d in range(Bench.RESTLESS_DAYS, Bench.RESTLESS_DAYS + Bench.LEAVE_AFTER_DAYS):
		check(Bench.tick(p, t0 + d * DAY + 60.0).is_empty(), "she stays on day %d" % d)
	# Some day after, she goes.
	var gone: Dictionary = {}
	var day := Bench.RESTLESS_DAYS + Bench.LEAVE_AFTER_DAYS
	while gone.is_empty() and day < 200:
		gone = Bench.tick(p, t0 + day * DAY + 60.0)
		day += 1
	check(gone.get("kind", "") == "leaves" and gone.get("id", "") == "gera", "and one morning she is gone: %s" % str(gone))
	check(p.get_member("gera") == null and not p.bench_clock.has("gera"), "off the roster and off the clock")
	check(gone.get("ch") != null and gone["ch"].id == "gera", "the screen is handed her, to file in the barracks")
	check(not "'" in String(gone.get("text", "")), "the leaving line is in the house voice: %s" % gone.get("text", ""))
	var named := false
	for k in p.relations:
		if "gera" in String(k):
			named = true
	check(not named, "nobody's opinion of her is left behind")

func test_never_the_founder() -> void:
	var p := _party()
	check(Bench.founder(p) == "vera", "the founder is the first on the books")
	p.swap("vera", "gera")   # the founder sits out; Gera marches
	Bench.sync(p, 0.0)
	var told := false
	for d in range(0, 120):
		if not Bench.tick(p, d * DAY + 60.0).is_empty():
			told = true
	check(not told and p.get_member("vera") != null, "the founder is never warned and never leaves")

func test_never_below_the_minimum() -> void:
	var p := _party()
	p.get_member("thrun").dead = true   # four living: the minimum
	Bench.sync(p, 0.0)
	var kinds: Array = []
	for d in range(0, 120):
		var e := Bench.tick(p, d * DAY + 60.0)
		if not e.is_empty():
			kinds.append(e["kind"])
	check(kinds == ["restless"], "at the minimum roster she is warned, and stays (%s)" % str(kinds))
	check(p.get_member("gera") != null, "...still on the books")

func test_leaving_is_seeded() -> void:
	# The same merc on the same day gets the same answer, every time it is asked.
	var same := true
	for d in 50:
		var t := d * DAY + 30.0
		if Bench.leaves_today("gera", t) != Bench.leaves_today("gera", t + 600.0):
			same = false
	check(same, "one answer a day, whenever in the day it is asked")
	var yes := 0
	for d in 300:
		if Bench.leaves_today("gera", d * DAY):
			yes += 1
	check(yes > 60 and yes < 150, "about LEAVE_PCT of days say yes (%d of 300)" % yes)
	# Two identical companies, the same days: the same morning.
	var a := _party()
	var b := _party()
	Bench.sync(a, 0.0)
	Bench.sync(b, 0.0)
	var ga := -1
	var gb := -1
	for d in range(0, 200):
		if ga < 0 and Bench.tick(a, d * DAY + 60.0).get("kind", "") == "leaves":
			ga = d
		if gb < 0 and Bench.tick(b, d * DAY + 60.0).get("kind", "") == "leaves":
			gb = d
	check(ga > 0 and ga == gb, "a reload replays the same morning (day %d, %d)" % [ga, gb])

func test_marching_is_the_cure() -> void:
	var p := _party()
	Bench.sync(p, 0.0)
	Bench.tick(p, Bench.RESTLESS_DAYS * DAY)
	check(Bench.restless(p, "gera"), "restless")
	p.swap("thrun", "gera")
	Bench.sync(p, Bench.RESTLESS_DAYS * DAY + 60.0)
	p.swap("gera", "thrun")
	Bench.sync(p, Bench.RESTLESS_DAYS * DAY + 120.0)
	check(not Bench.restless(p, "gera") and Bench.days(p, "gera", Bench.RESTLESS_DAYS * DAY + 120.0) == 0,
		"a day in the line and back: the clock starts over, the restlessness with it")

func test_fireside_with_the_bench() -> void:
	var road := 0
	var roof := 0
	var benched_line := ""
	for s in range(1, 400):
		var p := _party()
		var m := PartyOpinion.camp_moment(p, RNG.new(s))
		if not m.is_empty() and ("gera" in [m["a"], m["b"]]):
			road += 1
		var q := _party()
		var n := PartyOpinion.camp_moment(q, RNG.new(s), true)
		if not n.is_empty() and ("gera" in [n["a"], n["b"]]):
			roof += 1
			check(n["benched"] == ["gera"], "the moment says which of them is benched")
			benched_line = String(n["text"])
	check(road == 0, "on the road the bench is not at the fire")
	check(roof > 0, "under a roof it is, and a benched merc can be the pair (%d of 400): %s" % [roof, benched_line])
	var p := _party()
	p.get_member("gera").dead = true
	check(PartyOpinion.fireside_ids(p, true).size() == 4, "the dead do not sit at the fire")

func test_save_round_trip() -> void:
	var p := _party()
	Bench.sync(p, 1234.0)
	Bench.tick(p, 1234.0 + Bench.RESTLESS_DAYS * DAY)
	var w := World.new()
	var d: Dictionary = WorldSave.to_dict(w, p)
	var back = JSON.parse_string(JSON.stringify(d))
	var got = WorldSave.from_dict(back)
	var q = got["party"] if got is Dictionary else got.party
	check(q != null and q.bench_clock.has("gera"), "the bench's clocks ride the world save")
	if q != null and q.bench_clock.has("gera"):
		check(float(q.bench_clock["gera"]["since"]) == 1234.0 and bool(q.bench_clock["gera"]["warned"]),
			"...start and warning intact")
	# A save from before the bench counted: no key.
	back["party"].erase("bench")
	var old = WorldSave.from_dict(back)
	var r = old["party"] if old is Dictionary else old.party
	check(r != null and r.bench_clock.is_empty(), "an old save loads with no clocks")
	Bench.sync(r, 99999.0)
	check(float(r.bench_clock["gera"]["since"]) == 99999.0 and not Bench.restless(r, "gera"),
		"...and they start at the first look after the load, nobody restless yet")
