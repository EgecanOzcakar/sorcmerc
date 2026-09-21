# O6: the settlement market is a seeded function of (settlement, time since the
# last visit, a battle nearby), and stealing is one seeded d20 check with an O7
# opinion hook on it.
#   godot --headless --path . -s tests/test_settlement_visit.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Party = preload("res://core/party.gd")
const Campaign = preload("res://core/campaign.gd")
const RNG = preload("res://core/rng.gd")
const Quest = preload("res://core/quest.gd")
const Downtime = preload("res://core/downtime.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# #87: the button says what it would roll before it is pressed.
func test_check_preview() -> void:
	var party := _party()
	var line := Visit.check_preview(party, Visit.STEAL_SKILL, Visit.STEAL_DC)
	check("vs DC %d" % Visit.STEAL_DC in line and "Sleight" in line and "%" in line, "a steal preview names the skill, the DC and the odds (%s)" % line)
	var c = Campaign.new(party)
	var who: String = c.best_at(Visit.STEAL_SKILL)
	check(party.get_member(who).cname in line, "...and who rolls it")
	var bonus: int = c.skill_bonus(who, Visit.STEAL_SKILL)
	var need := clampi(Visit.STEAL_DC - bonus, 2, 20)
	check(("needs %d+" % need) in line and ("%d%%" % int(round((21 - need) / 20.0 * 100.0))) in line, "the odds are the d20's (%s)" % line)
	var adv := Visit.check_preview(party, Visit.HAGGLE_SKILL, Visit.HAGGLE_DC, true)
	check("advantage" in adv, "advantage is said when it applies")
	check("Nobody" in Visit.check_preview(Party.new(), Visit.STEAL_SKILL, Visit.STEAL_DC), "an empty party cannot try")

# #108/#109: the bench rests too, and the healer raises the dead.
func test_bench_rests_and_healer_raises() -> void:
	var w := World.new()
	w.add_settlement(World.Settlement.new("home", Vector2.ZERO, "human", "city"))
	var party := _party()
	var benched = party.roster[0]
	for ch in party.roster:
		ch.hp_current = 1
	party.bench(benched.id)
	Visit.rest(party, w, "long-rest")
	check(benched.hp_current == -1, "a long rest heals the benched member too (#108)")
	benched.dead = true
	benched.hp_current = 0
	party.gold = Party.REVIVE_COST - 1
	var r: Dictionary = Visit.raise_dead(party, benched.id)
	check(not r["ok"] and benched.dead, "a purse short of the fee raises nobody")
	party.gold = Party.REVIVE_COST
	r = Visit.raise_dead(party, benched.id)
	check(r["ok"] and not benched.dead and benched.hp_current == 1 and party.gold == 0,
		"the healer raises the dead for REVIVE_COST, no caster asked (#109)")
	check(not Visit.raise_dead(party, benched.id)["ok"], "...and only the dead")
	check(party.summary(benched.id).get("dead", true) == false, "the summary carries the flag the party card reads")

func _init() -> void:
	test_check_preview()
	test_bench_rests_and_healer_raises()
	test_market_is_deterministic()
	test_gap_changes_the_market()
	test_visit_stamps_and_second_visit_is_thinner()
	test_battle_flag_changes_it()
	test_battle_marking_is_local()
	test_trade()
	test_full_shelf_is_a_fraction_of_the_catalog()
	test_steal_deterministic_and_hooks()
	test_opinion_moves_prices_and_can_refuse_trade()
	test_rest_and_quests()
	test_quest_board_and_chains()
	test_persuade_and_investigate()
	test_counters_and_the_two_services_that_sell_nothing()

	# raids: a raided town's shelf is the battle shelf for as long as the raid stands
	var wv := World.new()
	var sv := wv.add_settlement(World.Settlement.new("raided", Vector2.ZERO, "human", "town"))
	wv.clock.elapsed = 10000.0
	sv.battle_at = -1.0
	sv.raided_by = "warren"
	var mv: Dictionary = Visit.visit(sv, wv)
	check(bool(mv["battle"]), "a raided town reads as a battle market with no battle_at at all")
	sv.raided_by = ""
	sv.last_visited = -1.0
	check(not bool(Visit.visit(sv, wv)["battle"]), "...and not once lifted")

	# the ladder: the bed by rung, and the back room at Trusted
	var Ladder = load("res://core/ladder.gd")
	var Loot = load("res://core/loot.gd")
	Ladder.reset()
	var wb := World.new()
	var city = wb.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	var camp = wb.add_settlement(World.Settlement.new("dun", Vector2(500, 0), "human", "camp"))
	wb.clock.elapsed = 20000.0
	check(Visit.inn_cost(city) == 40, "a stranger pays the city's 40")
	Ladder.deed("human", 4)
	check(Visit.inn_cost(city) == 20 and Visit.inn_cost(camp) == 5, "Known: half (ceil)")
	var m0: Dictionary = Visit.visit(city, wb)
	check(Visit.stock_by_service(city, m0).get("backroom", []).is_empty(), "Known: no back room")
	Ladder.deed("human", 8)
	city.last_visited = -1.0
	var m1: Dictionary = Visit.visit(city, wb)
	var br: Array = Visit.stock_by_service(city, m1).get("backroom", [])
	check(br.size() == Visit.BACK_ROOM_N, "Trusted: three in the back room (%d)" % br.size())
	for e in br:
		check(String(Campaign.item_data(String(e["item_id"])).get("rarity", "")) == "uncommon", "...uncommon (%s)" % e["item_id"])
		check(int(e["price"]) == maxi(1, int(round(Campaign.item_price(String(e["item_id"])) * float(m1["markup"])))), "...at list times the market's markup")
		check(String(e.get("service", "")) == "backroom", "...tagged for the tab")
	var ids0: Array = br.map(func(e): return e["item_id"])
	city.last_visited = -1.0
	var ids1: Array = Visit.stock_by_service(city, Visit.visit(city, wb)).get("backroom", []).map(func(e): return e["item_id"])
	check(ids0 == ids1, "the same shelf on the same day (seeded off the settlement and the steps)")
	camp.last_visited = -1.0
	check(Visit.stock_by_service(camp, Visit.visit(camp, wb)).get("backroom", []).is_empty(), "a camp has no back room: nobody there deals in these")
	Ladder.deed("human", 13)
	city.last_visited = -1.0
	var m2: Dictionary = Visit.visit(city, wb)
	var br2: Array = Visit.stock_by_service(city, m2).get("backroom", [])
	var rares := 0
	for e in br2:
		if String(Campaign.item_data(String(e["item_id"])).get("rarity", "")) == "rare":
			rares += 1
	check(br2.size() == Visit.BACK_ROOM_N + Visit.BACK_ROOM_RARE and rares == Visit.BACK_ROOM_RARE, "Sworn: two rare beside the three")
	check(Visit.inn_cost(city) == 0, "Sworn: on the house")
	# every restock step is a different seeded shelf: none draws a potion or
	# scroll the counters already sell, and no counter claims a tagged row
	# (greyhaven's unfiltered shelves collide at six of the seven steps)
	var grey = wb.add_settlement(World.Settlement.new("greyhaven", Vector2(0, 500), "human", "city"))
	for c2 in [city, grey]:
		var own2: Array = Visit.catalog(c2)
		for k in Visit.MAX_STEPS + 1:
			c2.last_visited = wb.clock.elapsed - k * Visit.RESTOCK
			var mk: Dictionary = Visit.visit(c2, wb)
			var tagged: Array = mk["stock"].filter(func(e): return String(e.get("service", "")) == "backroom")
			check(not tagged.any(func(e): return own2.has(e["item_id"])), "the back room draws nothing the counters already sell (%s, step %d)" % [c2.id, k])
			var groups: Dictionary = Visit.stock_by_service(c2, mk)
			for g in groups:
				if g != "backroom":
					check(not groups[g].any(func(e): return String(e.get("service", "")) == "backroom"), "a back-room item is not also on the %s's shelf (%s, step %d)" % [g, c2.id, k])
	# a town that refuses to trade has no back room either
	FactionOpinion.set_opinion("human", -80.0)
	city.last_visited = -1.0
	var mr: Dictionary = Visit.visit(city, wb)
	check(bool(mr["refused"]) and not Visit.stock_by_service(city, mr).has("backroom"), "refused: no back room")
	FactionOpinion.reset()
	# buying one lands it in the stash, identified
	var pb := _party()
	pb.gold = 100000
	var pick := String(br2[0]["item_id"])
	check(Visit.buy(m2, pb, pick), "bought")
	check(pb.stash_count(pick, true) == 1, "...identified in the stash")
	check(Visit.stock_by_service(city, m2).get("backroom", []).size() == br2.size() - 1, "...and off the shelf")
	Ladder.reset()

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
	# A bare shelf is dear to buy from; it does not pay a premium for what the
	# party crafted at half list (core/downtime.gd's bench).
	var bare := Visit.market(w.settlements[0], 0.0, false)
	var potion: String = Campaign.potion_ids()[0]
	check(bare["markup"] > 1.0 and Visit.sell_price(bare, potion) <= Downtime.craft_cost(potion),
		"a bare shelf pays no more for a potion than the bench charged for it")
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
	check(String(hit["text"]).contains("opinion %d" % int(Visit.OPINION_STEAL_SUCCESS)),
		"...and says so on the spot")
	# The stall is watched now: a second try today does not even roll.
	var again := Visit.steal(s, party, w, m, _rng_rolling(20))
	check(again.get("watched", false) and int(again["gold"]) == 0, "no second theft while the stall is watched")
	check(Visit.steal_wait(s, w) > 0.0, "...and the wait is visible")
	w.clock.elapsed += Visit.STEAL_COOLDOWN_MINUTES
	check(Visit.steal_wait(s, w) == 0.0, "a day later the watch is off")
	var miss := Visit.steal(s, party, w, m, _rng_rolling(1))
	check(not miss["ok"] and int(miss["gold"]) == 0, "a nat 1 gets caught with nothing")
	check(s.pending_opinion_delta
			== Visit.OPINION_STEAL_SUCCESS + Visit.OPINION_STEAL_CAUGHT,
		"getting caught queued the bigger O7 opinion hit, on top of the first")
	# Unseeded: same settlement, same hour, same outcome.
	s.stolen_at = -1.0
	var a := Visit.steal(s, _party(), w, m)
	s.stolen_at = -1.0
	var b := Visit.steal(s, _party(), w, m)
	check(a["nat"] == b["nat"] and a["ok"] == b["ok"], "the same attempt rolls the same")
	check(String(a["text"]) != "", "the attempt is narrated")

# O9 item 2/4: the inn spends world-time to heal, and a settlement is a quest giver.
func test_rest_and_quests() -> void:
	FactionOpinion.reset()
	var w := _world()
	var s = w.settlements[0]
	var party := _party()
	var ch = party.party_characters()[0]
	ch.hp_current = 1
	w.clock.tick(10.0)
	var t0: float = w.clock.elapsed
	Visit.rest(party, w)
	check(is_equal_approx(w.clock.elapsed, t0 + Visit.LONG_REST_MINUTES), "a rest spends world-time")
	check(ch.hp_current != 1, "a long rest heals the party")

	# T9x: a room at the inn isn't free, and scales with settlement kind —
	# checked at the data level here; world.gd's _rest() is what actually
	# charges it (see test_world_camp_integration.gd).
	check(Visit.inn_cost(World.Settlement.new("x", Vector2.ZERO, "human", "city")) >
		Visit.inn_cost(World.Settlement.new("x", Vector2.ZERO, "human", "town")),
		"a city room costs more than a town room")
	check(Visit.inn_cost(World.Settlement.new("x", Vector2.ZERO, "human", "town")) >
		Visit.inn_cost(World.Settlement.new("x", Vector2.ZERO, "human", "camp")),
		"a town room costs more than a camp")

	check(Visit.giver_node_id(s) == Visit.giver_node_id(s), "a settlement's giver is stable")
	check(Visit.giver_node_id(w.settlements[1]) != "" , "every settlement has one")
	var offer := Visit.quest_offer(s, party)
	check(not offer.is_empty(), "a neutral settlement has work")
	check(Quest.accept(party, offer), "the offer can be accepted")
	check(Visit.quest_offer(s, party) != offer, "the same job is not offered twice")
	check(Visit.turn_ins(party).is_empty(), "an unfinished job cannot be turned in")
	offer["progress"] = int(offer["required"])
	offer["state"] = "complete"
	check(Visit.turn_ins(party).size() == 1, "a finished job is ready to hand in")
	var gold0: int = party.gold
	check(Quest.turn_in(party, offer, s.faction) and party.gold > gold0, "handing it in pays")
	check(FactionOpinion.get_opinion(s.faction) == FactionOpinion.QUEST_DONE,
		"...and the faction hears about it")
	FactionOpinion.set_opinion(s.faction, FactionOpinion.QUEST_MIN - 1.0)
	check(Visit.quest_offer(s, party).is_empty(), "a faction that dislikes you has no work")
	FactionOpinion.reset()

# T9x: the quest board (multiple concurrent offers) and chains (escalating,
# faction-specific — reward and title ramp up the more jobs against that
# faction the party has turned in).
func test_quest_board_and_chains() -> void:
	var w := _world()
	var home = w.settlements[0]
	w.add_settlement(World.Settlement.new("ashfell", Vector2(400, 0), "orc", "city"))
	var band := w.add_party(World.RoamingParty.new("raiders", Vector2(1, 1), "bandit"))
	w.add_lair(World.Lair.new("warren", Vector2(2, 2), "goblinoid"))
	var party := _party()

	var board: Array = Visit.quest_offers(home, party, w)
	check(board.size() >= 2, "a settlement with several eligible targets offers several jobs at once (got %d)" % board.size())
	var hunt: Dictionary = {}
	for q in board:
		if q["kind"] == "hunt_party":
			hunt = q
	check(not hunt.is_empty(), "the raiders band shows up as a hunt-party job on the board")
	check(int(hunt.get("chain_tier", -1)) == 0, "a first job against this faction is tier 0")

	check(Quest.accept(party, hunt), "the board's own offer can be accepted")
	hunt["progress"] = 1
	hunt["state"] = "complete"
	check(Quest.turn_in(party, hunt, "bandit"), "turning in a chain job pays out")
	check(Quest.faction_chain_tier(party, "bandit") == 1, "one turned-in job against bandit is chain tier 1")

	# The next job against the same faction (another bandit band) reads as the
	# escalated tier — different title, bigger base reward.
	var band2 := w.add_party(World.RoamingParty.new("raiders-2", Vector2(3, 3), "bandit"))
	var board2: Array = Visit.quest_offers(home, party, w)
	var hunt2: Dictionary = {}
	for q in board2:
		if q["kind"] == "hunt_party":
			hunt2 = q
	check(not hunt2.is_empty(), "a fresh band still offers a hunt-party job")
	check(int(hunt2["chain_tier"]) == 1, "the next job against the same faction is tier 1")
	check(hunt2["title"] != hunt["title"], "an escalated job reads differently, not a copy of tier 0")

# The smallest seed whose first d20 is `want` — the test wants a pinned roll, not
# a particular stream.
func _rng_rolling(want: int):
	for s in range(1, 4000):
		var r = RNG.new(s)
		if r.roll_die(20) == want:
			return RNG.new(s)
	check(false, "no seed rolls a %d" % want)
	return RNG.new(1)

# O7: what the faction thinks of you rides on top of the scarcity markup, and
# past REFUSE_TRADE the stall is closed to you.
func test_opinion_moves_prices_and_can_refuse_trade() -> void:
	FactionOpinion.reset()
	var w := _world()
	var s = w.settlements[0]
	var neutral := Visit.market(s, 120.0, false)
	var hated := Visit.market(s, 120.0, false, -40.0)
	var loved := Visit.market(s, 120.0, false, 40.0)
	check(hated["markup"] > neutral["markup"], "a faction that dislikes you charges more")
	check(loved["markup"] < neutral["markup"], "...and one that likes you charges less")
	var id: String = neutral["stock"][0]["item_id"]
	check(Visit.price_of(hated, id) > Visit.price_of(neutral, id), "the shelf price follows")
	var full := Visit.RESTOCK * Visit.MAX_STEPS
	check(Visit.sell_price(Visit.market(s, full, false, 40.0), id) < Visit.sell_price(Visit.market(s, full, false), id),
		"so does the sell price, off a full shelf")
	check(Visit.sell_price(hated, id) == Visit.sell_price(neutral, id) and Visit.sell_price(neutral, id) == Visit.sell_price(Visit.market(s, full, false), id),
		"...but a dear shelf pays list, never a premium")

	var refused := Visit.market(s, 120.0, false, FactionOpinion.REFUSE_TRADE - 1.0)
	check(refused["refused"] and refused["stock"].is_empty(), "below the floor they will not deal")
	var party := _party()
	party.gold = 100000
	check(not Visit.buy(refused, party, id), "and nothing can be bought off a refused market")

	# visit() reads the live score, so the same town is dearer after you rob it.
	Visit.visit(s, w)
	s.pending_opinion_delta = -40.0
	FactionOpinion.drain(w)
	w.clock.tick(Visit.RESTOCK * 3.0)
	var after := Visit.visit(s, w)
	check(after["opinion"] == -40.0, "visit() reads the live faction score")
	check(after["markup"] > Visit.market(s, after["gap"], false)["markup"],
		"robbing them shows up on the next visit's prices")
	FactionOpinion.reset()

# T9x: talking a refused market into trading anyway, and picking over a
# recent battlefield — both one-roll, both-outcomes-reachable checks, same
# shape as steal().
func test_persuade_and_investigate() -> void:
	var w := _world()
	var s = w.settlements[0]
	var party := _party()

	var open_market := Visit.market(s, 120.0, false)
	check(Visit.persuade(s, open_market, party).is_empty(), "nothing to persuade when the market isn't refusing")

	var refused := Visit.market(s, 120.0, false, FactionOpinion.REFUSE_TRADE - 1.0)
	var saw_ok := false
	var saw_fail := false
	for seed_v in range(40):
		var roll: Dictionary = Visit.persuade(s, refused, party, RNG.new(seed_v + 1))
		check(not roll.is_empty(), "persuade() rolls for a party that has members")
		check(String(roll["text"]) != "", "the attempt is narrated")
		if roll["ok"]:
			saw_ok = true
		else:
			saw_fail = true
	check(saw_ok and saw_fail, "both outcomes reachable across seeds (got ok=%s fail=%s)" % [saw_ok, saw_fail])

	var opened := Visit.persuade_into_trading(s, refused)
	check(not opened["refused"] and not opened["stock"].is_empty(), "a persuaded market actually opens back up")
	check(opened["opinion"] == refused["opinion"], "the faction's real opinion is untouched by talking your way in")

	# A much worse opinion is a harder sell.
	var very_refused := Visit.market(s, 120.0, false, FactionOpinion.REFUSE_TRADE - 50.0)
	var r1 := Visit.persuade(s, refused, party, RNG.new(1))
	var r2 := Visit.persuade(s, very_refused, party, RNG.new(1))
	check(r2["dc"] > r1["dc"], "a settlement that loathes you is a harder sell than one that merely refuses")

	# --- haggle: the mirror of persuade, for a market that's already open ---
	check(Visit.haggle(refused, party).is_empty(), "nothing to haggle over on a market that's refusing")
	var saw_hok := false
	var saw_hfail := false
	for seed_v in range(40):
		var roll: Dictionary = Visit.haggle(open_market, party, RNG.new(seed_v + 1))
		check(not roll.is_empty(), "haggle() rolls for a party that has members")
		check(String(roll["text"]) != "", "the attempt is narrated")
		if roll["ok"]:
			saw_hok = true
			check(roll["mult"] < 1.0, "a win discounts this visit's prices")
		else:
			saw_hfail = true
			check(roll["mult"] > 1.0, "a loss makes this visit's prices worse")
	check(saw_hok and saw_hfail, "both outcomes reachable across seeds (got ok=%s fail=%s)" % [saw_hok, saw_hfail])

	var priced := Visit.market(s, 120.0, false)
	var id2: String = priced["stock"][0]["item_id"]
	var before_price: int = Visit.price_of(priced, id2)
	var before_markup: float = priced["markup"]
	Visit.apply_haggle(priced, 0.85)
	check(Visit.price_of(priced, id2) == maxi(1, int(round(before_price * 0.85))),
		"apply_haggle rescales every shelf price")
	check(is_equal_approx(priced["markup"], before_markup * 0.85), "...and the markup itself, so sell prices follow too")

	# --- investigate_battle ---
	var no_battle := Visit.market(s, 120.0, false)
	check(Visit.investigate_battle(s, no_battle, party).is_empty(), "nothing to investigate without a recent battle")

	var battle := Visit.market(s, 120.0, true)
	var saw_bok := false
	var saw_bfail := false
	for seed_v in range(40):
		var gold0: int = party.gold
		var roll: Dictionary = Visit.investigate_battle(s, battle, party, RNG.new(seed_v + 1))
		check(not roll.is_empty(), "investigate_battle() rolls for a party that has members")
		if roll["ok"]:
			saw_bok = true
			check(party.gold == gold0 + roll["gold"], "a success actually pays the gold it reports")
		else:
			saw_bfail = true
			check(party.gold == gold0, "a failure pays nothing")
	check(saw_bok and saw_bfail, "both outcomes reachable across seeds (got ok=%s fail=%s)" % [saw_bok, saw_bfail])

# --- T9y: the counters behind the market -----------------------------------
# T25 sized a settlement's services long ago and the visit panel listed their
# names, but the shelf was one flat list and the two services that stock no
# goods at all — Healer, Librarian — had no way to be used. These are the
# data-level halves of both (scenes/world/world.gd draws them).
func test_counters_and_the_two_services_that_sell_nothing() -> void:
	var w := _world()
	var city = w.settlements[0]
	var town = w.settlements[1]
	var party := _party()
	var m: Dictionary = Visit.visit(city, w)

	# Every row on the shelf lands under exactly one counter, and nothing is
	# invented or dropped on the way.
	var groups: Dictionary = Visit.stock_by_service(city, m)
	var regrouped: Array = []
	for service in groups:
		for e in groups[service]:
			check(not e["item_id"] in regrouped, "%s is on one counter, not two" % e["item_id"])
			regrouped.append(e["item_id"])
	check(regrouped.size() == m["stock"].size(), "every row on the shelf belongs to some counter")
	check(groups.has("generalist"), "the generalist counter always exists, even if empty")
	for service in groups:
		check(service in Visit.services(city), "%s is a counter this settlement staffs" % service)

	# A camp staffs nobody but the generalist, so its whole shelf falls there.
	check(Visit.has_service(city, "healer"), "a city has a healer")
	check(not Visit.has_service(town, "healer"), "a town does not")

	# --- the healer ---
	check(Visit.heal(party)["ok"] == false, "a party in the pink has nothing to pay a healer for")
	var hurt = party.roster[0]
	hurt.hp_current = 1
	party.gold = Visit.HEAL_COST - 1
	var broke: Dictionary = Visit.heal(party)
	check(not broke["ok"] and party.gold == Visit.HEAL_COST - 1, "no gold, no healing, no charge")
	check(hurt.hp_current == 1, "...and nobody was quietly healed for free")
	party.gold = Visit.HEAL_COST
	var healed: Dictionary = Visit.heal(party)
	check(healed["ok"] and healed["healed"] == 1, "the healer patches up whoever is actually hurt")
	check(party.gold == 0, "...for exactly the posted fee")
	check(hurt.hp_current < 0, "...back to the sheet's own maximum")

	# The healer is the way past a long-rest cooldown, so it must not care
	# about one: that is the whole reason to pay instead of sleeping.
	party.last_long_rest_at = w.clock.elapsed
	check(not Visit.can_long_rest(party, w), "the party just rested")
	party.roster[0].hp_current = 2
	party.gold = Visit.HEAL_COST
	check(Visit.heal(party)["ok"], "the healer works regardless of the rest cooldown")

	# --- the long-rest countdown the inn page shows ---
	check(Visit.long_rest_in(party, w) > 0.0, "a fresh rest leaves time on the clock")
	w.clock.elapsed += Visit.LONG_REST_COOLDOWN
	check(Visit.long_rest_in(party, w) == 0.0, "a full day later there is none left")
	check(Visit.can_long_rest(party, w), "...which is exactly when resting is allowed again")

	# --- the librarian ---
	party.gold = Visit.IDENTIFY_COST * 2
	party.stash_add("spell-scroll", 1, false)
	check(party.unidentified().size() == 1, "the pack holds one mystery")
	check(not Visit.identify(party, "longsword")["ok"], "nothing unidentified like that in the pack")
	check(party.gold == Visit.IDENTIFY_COST * 2, "...and no fee for the question")
	var read: Dictionary = Visit.identify(party, "spell-scroll")
	check(read["ok"], "the librarian reads the mystery")
	check(party.gold == Visit.IDENTIFY_COST, "...for the flat fee")
	check(party.unidentified().is_empty(), "...leaving nothing unidentified")
	check(party.stash_count("spell-scroll", true) == 1, "...and the item itself is still there, known")

func test_full_shelf_is_a_fraction_of_the_catalog() -> void:
	var s = _world().settlements[0]
	var full := Visit.market(s, Visit.RESTOCK * Visit.MAX_STEPS, false)
	check(full["stock"].size() == int(ceil(Visit.catalog(s).size() * Visit.FULL_SHELF)),
		"a rested market shows FULL_SHELF of its catalog, not all of it")
