# O6: the settlement market is a seeded function of (settlement, time since the
# last visit, a battle nearby), and stealing is one seeded d20 check with an O7
# opinion hook on it.
#   godot --headless --path . -s tests/test_settlement_visit.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_market_is_deterministic()
	test_gap_changes_the_market()
	test_visit_stamps_and_second_visit_is_thinner()
	test_battle_flag_changes_it()
	test_battle_marking_is_local()
	test_trade()
	test_steal_deterministic_and_hooks()
	print("test_settlement_visit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "soldier", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(900, 0), "soldier", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "soldier", true))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

static func _ids(m: Dictionary) -> Array:
	return m["stock"].map(func(e): return e["item_id"])

func test_market_is_deterministic() -> void:
	var s = _world().settlements[0]
	var a := Visit.market(s, 120.0, false)
	var b := Visit.market(s, 120.0, false)
	check(_ids(a) == _ids(b), "same settlement+gap gives the same shelf")
	check(a["markup"] == b["markup"], "same settlement+gap gives the same prices")
	check(not a["stock"].is_empty(), "a market has stock at all")
	var other := Visit.market(_world().settlements[1], 120.0, false)
	check(_ids(other) != _ids(a), "a different settlement stocks differently")

func test_gap_changes_the_market() -> void:
	var s = _world().settlements[0]
	var fresh := Visit.market(s, 0.0, false)                        # just left
	var later := Visit.market(s, Visit.RESTOCK * Visit.MAX_STEPS, false)
	check(fresh["stock"].size() < later["stock"].size(),
		"a picked-over market has less on the shelf than a restocked one")
	check(fresh["markup"] > later["markup"], "a thin shelf is a dear one")
	check(later["steps"] == Visit.MAX_STEPS and is_equal_approx(later["markup"], 1.0),
		"a fully restocked market sells at list price")

func test_visit_stamps_and_second_visit_is_thinner() -> void:
	var w := _world()
	var s = w.settlements[0]
	w.clock.tick(600.0)
	var first := Visit.visit(s, w)
	check(s.last_visited == w.clock.elapsed, "the visit stamped last_visited")
	check(first["gap"] < 0.0 and first["steps"] == Visit.MAX_STEPS,
		"a never-visited settlement reads as fully stocked")
	w.clock.tick(10.0)
	var soon := Visit.visit(s, w)               # ten minutes later
	check(soon["steps"] == 0 and soon["stock"].size() < first["stock"].size(),
		"coming straight back finds the shelf as it was left")
	w.clock.tick(Visit.RESTOCK * Visit.MAX_STEPS)
	var late := Visit.visit(s, w)
	check(late["stock"].size() > soon["stock"].size() and late["markup"] < soon["markup"],
		"coming back a day later finds it restocked and cheaper")

func test_battle_flag_changes_it() -> void:
	var s = _world().settlements[0]
	var peace := Visit.market(s, 300.0, false)
	var war := Visit.market(s, 300.0, true)
	check(war["markup"] > peace["markup"], "a fight nearby marks the market up")
	check(war["stock"].size() < peace["stock"].size(), "a fight nearby empties the shelf")
	check(_ids(war) == _ids(Visit.market(s, 300.0, true)), "the post-battle market is seeded too")

func test_battle_marking_is_local() -> void:
	var w := _world()
	w.clock.tick(100.0)
	Visit.mark_battle(w, Vector2(30, 30), w.clock.elapsed)      # right outside riverhold
	check(Visit.battle_recent(w.settlements[0], w.clock.elapsed), "the near settlement felt it")
	check(not Visit.battle_recent(w.settlements[1], w.clock.elapsed), "the far one did not")
	var m := Visit.visit(w.settlements[0], w)
	check(m["battle"], "a visit right after reads the battle flag")
	w.clock.tick(Visit.BATTLE_WINDOW + 1.0)
	check(not Visit.battle_recent(w.settlements[0], w.clock.elapsed), "the flag ages out")

func test_trade() -> void:
	var w := _world()
	var party := _party()
	party.gold = 100000
	var m := Visit.visit(w.settlements[0], w)
	var id: String = m["stock"][0]["item_id"]
	var price := Visit.price_of(m, id)
	var before: int = party.gold
	check(Visit.buy(m, party, id), "buying a stocked item works")
	check(party.gold == before - price and party.stash_count(id) == 1, "gold and stash moved")
	check(not Visit.buy(m, party, id), "the bought item left the shelf")
	check(Visit.sell(m, party, id) and party.gold == before - price + Visit.sell_price(m, id),
		"selling it back pays the market sell price")
	check(not Visit.buy(m, party, "not-a-thing"), "unstocked ids cannot be bought")

func test_steal_deterministic_and_hooks() -> void:
	var w := _world()
	var s = w.settlements[0]
	var m := Visit.visit(s, w)
	var party := _party()
	var gold0: int = party.gold
	# Pinned rolls: RNG seeds chosen so the first d20 is a 20 / a 1.
	var hit := Visit.steal(s, party, w, m, _rng_rolling(20))
	check(hit["ok"] and hit["gold"] >= Visit.STEAL_GOLD_MIN, "a nat 20 lifts something")
	check(party.gold == gold0 + int(hit["gold"]), "the gold landed in the purse")
	check(s.pending_opinion_delta == Visit.OPINION_STEAL_SUCCESS,
		"a clean theft queued the O7 opinion hit")
	var miss := Visit.steal(s, party, w, m, _rng_rolling(1))
	check(not miss["ok"] and int(miss["gold"]) == 0, "a nat 1 gets caught with nothing")
	check(s.pending_opinion_delta
			== Visit.OPINION_STEAL_SUCCESS + Visit.OPINION_STEAL_CAUGHT,
		"getting caught queued the bigger O7 opinion hit, on top of the first")
	# Unseeded: same settlement, same hour, same outcome.
	var a := Visit.steal(s, _party(), w, m)
	var b := Visit.steal(s, _party(), w, m)
	check(a["nat"] == b["nat"] and a["ok"] == b["ok"], "the same attempt rolls the same")
	check(String(a["text"]) != "", "the attempt is narrated")

# The smallest seed whose first d20 is `want` — the test wants a pinned roll, not
# a particular stream.
func _rng_rolling(want: int):
	for s in range(1, 4000):
		var r = RNG.new(s)
		if r.roll_die(20) == want:
			return RNG.new(s)
	check(false, "no seed rolls a %d" % want)
	return RNG.new(1)
