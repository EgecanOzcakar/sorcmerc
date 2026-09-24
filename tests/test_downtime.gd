# Downtime — the rows in town that take days: a feat trained, a night on the
# town, a game, the bench, and the pit's bracket.
#   docs/superpowers/specs/2026-09-21-downtime-design.md §2–§6
#   godot --headless --path . -s tests/test_downtime.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")
const Downtime = preload("res://core/downtime.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Rumors = preload("res://core/rumors.gd")
const Ach = preload("res://core/achievements.gd")
const Leveling = preload("res://core/leveling.gd")
const Campaign = preload("res://core/campaign.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const WorldSave = preload("res://core/world_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_spend_days()
	test_train()
	test_carouse()
	test_gamble()
	test_craft()
	test_pit()
	test_complications()
	test_save()
	print("test_downtime: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# A city at the origin (the pit, every counter), a town, a camp, and a lair
# near enough for the common room to know about it.
func _world() -> World:
	var w = World.new()
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(300, 0), "elf", "town"))
	w.add_settlement(World.Settlement.new("burners", Vector2(600, 0), "human", "camp"))
	w.add_lair(World.Lair.new("near-warren", Vector2(200, 0), "goblinoid"))
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

# An rng whose first d20 is `nat` (and, when asked, whose next die of `sides`
# is `second`) — the seed is searched, not guessed, so a branch can be driven.
func _rng(nat: int, sides := 0, second := 0) -> RNG:
	for seed_v in range(1, 20000):
		var r = RNG.new(seed_v)
		if r.roll_die(20) != nat:
			continue
		if sides > 0 and r.roll_die(sides) != second:
			continue
		return RNG.new(seed_v)
	return null

func _level(party, n: int) -> void:
	for ch in party.roster:
		Leveling.grant_levels(ch, n)

# --- days ---------------------------------------------------------------

func test_spend_days() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(1000)
	for ch in party.roster:
		ch.hp_current = 1
	var before: float = w.clock.elapsed
	check(Downtime.bed_cost(city, 5) == Visit.INN_COST["city"] * 5, "the bed is the inn's rate a night")
	var paid: int = Downtime.spend_days(party, w, city, 5)
	check(paid == Visit.INN_COST["city"] * 5 and party.gold == 1000 - paid, "five nights at a Stranger's rate")
	check(is_equal_approx(w.clock.elapsed, before + 5 * Downtime.DAY), "the clock moves exactly five days (the rest's hours inside them)")
	check(party.roster[0].hp_current == -1 and party.roster[4].hp_current == -1, "everyone rested, the bench too")
	check(Ach.count("downtime_days") == 5, "the days are tallied")
	check("5 days, 5 nights" in Downtime.bed_line(city, 5), "the bed line says the nights and the price")
	Ladder.deed(city.faction, Ladder.RUNG_AT[Ladder.KNOWN])
	check(Downtime.spend_days(party, w, city, 2) == int(ceil(Visit.INN_COST["city"] * Visit.INN_KNOWN)) * 2, "a Known company pays half")
	Ladder.deed(city.faction, Ladder.RUNG_AT[Ladder.SWORN])
	check(Downtime.spend_days(party, w, city, 1) == 0, "a Sworn one nothing")
	var poor := _party(10)
	before = w.clock.elapsed
	Ladder.reset()
	check(Downtime.spend_days(poor, w, city, 1) == -1 and poor.gold == 10 and w.clock.elapsed == before,
		"a purse short of the bed spends nothing, and no day passes")

# --- training -------------------------------------------------------------

func test_train() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(0)
	var vera = party.get_member("vera")
	check(not Downtime.can_train(party, vera), "a level-3 hero has nothing to learn yet")
	_level(party, 4)
	check(Downtime.can_train(party, vera), "at level 4 the trainer will take them")
	check(Downtime.train_cost(vera) == Downtime.TRAIN_COST_BASE + Downtime.TRAIN_COST_PER_LEVEL * 4, "150 + 50 a level")
	var pool: Array = Downtime.trainable(vera)
	check(not pool.is_empty(), "there are feats to learn")
	var all_general := true
	for fid in pool:
		if String(Catalog.feat_src(fid).get("category", "")) != Downtime.TRAIN_CATEGORY:
			all_general = false
	check(all_general, "...every one of them general")
	check(not "savage-attacker" in pool and not "alert" in pool, "an origin feat is not on the trainer's list")
	vera.feats.append("durable")
	vera.dirty()
	check(not "durable" in Downtime.trainable(vera), "a feat the sheet already has is not offered again")
	for fid in ["resilient", "elemental-adept", "keen-mind", "observant", "skill-expert"]:
		check(not fid in pool, "%s asks for a choice the trainer cannot make: not offered" % fid)
	check("sentinel" in pool and "durable" in pool, "a feat whose only choice is its +1 is")
	var chosen: Dictionary = {}
	for k in party.get_member("pike").sheet().pending.map(func(p): return String(p["key"])):
		if k.begins_with("feat-choice:"):
			chosen[k] = true
	var pike = party.get_member("pike")
	var fc_key: String = chosen.keys()[0] if not chosen.is_empty() else ""
	check(fc_key != "", "a level-4 hero has a feat-choice to decide (%s)" % fc_key)
	pike.decide(fc_key, {"type": "feat-choice", "featId": "sentinel"})
	check(not "sentinel" in Downtime.trainable(pike), "a feat taken through a feat-choice is not offered again")
	var feat := "sentinel"
	var fee: int = Downtime.train_cost(vera)
	var bed: int = Downtime.bed_cost(city, Downtime.TRAIN_DAYS)
	party.gold = fee + bed - 1
	var r: Dictionary = Downtime.train(party, w, city, vera, feat)
	check(not r.get("ok", true) and not feat in vera.feats, "a purse short of the fee and the bed trains nobody")
	party.gold = fee + bed
	var before: float = w.clock.elapsed
	var str_before: int = vera.sheet().abilities["str"]["total"]
	var dex_before: int = vera.sheet().abilities["dex"]["total"]
	r = Downtime.train(party, w, city, vera, feat)
	check(r.get("ok", false) and feat in vera.feats and Bundles.collect(vera)["expanded_feats"].has(feat),
		"the feat is on the build, and the sheet expands it")
	check(not vera.sheet().pending.any(func(p): return ":feat:sentinel:" in String(p["key"])), "the trainer finishes what it starts: nothing pending off the feat")
	var rose: Array = [vera.sheet().abilities["str"]["total"] - str_before, vera.sheet().abilities["dex"]["total"] - dex_before]
	check(rose == [1, 0] if str_before >= dex_before else rose == [0, 1], "...the +1 lands on the higher of the two it allows (%s)" % [rose])
	check(r["feat_name"] == Catalog.feat_src(feat)["name"] and r["days"] == Downtime.TRAIN_DAYS and r["cost"] == fee, "the row reports what it took")
	check("Five days with a master-at-arms, and Vera Kord comes out of it with %s." % r["feat_name"] in r["text"], "the copy")
	check(party.gold == 0 and is_equal_approx(w.clock.elapsed, before + Downtime.TRAIN_DAYS * Downtime.DAY), "five days and the fee, and the bed")
	check(not Downtime.can_train(party, vera) and Downtime.train(party, w, city, vera, Downtime.trainable(vera)[0]).is_empty(), "once per hero, ever")
	check(Downtime.train(party, w, city, party.get_member("pike"), "alert").is_empty(), "an origin feat is refused")
	check(Downtime.train(party, w, city, party.get_member("pike"), "no-such-feat").is_empty(), "so is nonsense")
	check(Ach.count("trained") == 1 and Ach.is_unlocked("trained_first"), "Schooled")

# --- carousing ------------------------------------------------------------

func test_carouse() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(1000)
	Visit.visit(city, w)
	var cost: int = Downtime.CAROUSE_COST["city"]
	var bed: int = Downtime.bed_cost(city, 1)
	var who: Dictionary = Downtime.best_of(party, Downtime.CAROUSE_SKILLS)
	check(who["skill"] in Downtime.CAROUSE_SKILLS and party.get_member(who["char_id"]) != null, "the party's best at Persuasion or Performance rolls")

	# pass: a contact, and the lead the common room has
	var before: float = w.clock.elapsed
	var r: Dictionary = Downtime.carouse(party, w, city, _rng(15))
	check(r["ok"] and r["nat"] == 15 and r["dc"] == Downtime.CAROUSE_DC and r["contact"], "a 15 makes a friend")
	check(FactionOpinion.get_opinion(city.faction) == Downtime.CAROUSE_CONTACT, "...and the faction warms by 5")
	check(not r["lead"].is_empty() and w.lairs[0].discovered and r["coin"] == 0, "the contact tells them where the warren is, free")
	check(party.gold == 1000 - cost - bed and is_equal_approx(w.clock.elapsed, before + Downtime.DAY), "the night and the bed, one day")
	check(r["complication"] == "" and Ach.count("contacts") == 1 and Ach.is_unlocked("carouse_contact"), "no story; Friends in Low Places")

	# pass with nothing left to tell: the contact stands a round
	var gold: int = party.gold
	r = Downtime.carouse(party, w, city, _rng(15))
	check(r["ok"] and r["lead"].is_empty() and r["coin"] == Downtime.CAROUSE_COIN, "no lead left: coin instead")
	check(party.gold == gold - cost - bed + Downtime.CAROUSE_COIN, "...paid into the purse")

	# nat 20: both
	w.lairs[0].discovered = false
	r = Downtime.carouse(party, w, city, _rng(20))
	check(r["ok"] and r["contact"] and not r["lead"].is_empty() and r["coin"] == Downtime.CAROUSE_COIN, "a 20 is the contact, the lead and the round")

	# fail: a complication, one of the four
	gold = party.gold
	r = Downtime.carouse(party, w, city, _rng(2))
	check(not r["ok"] and r["complication"] in Downtime.COMPLICATIONS, "a 2 is a story (%s)" % r["complication"])
	check(not r["contact"] and r["lead"].is_empty() and r["coin"] == 0, "...and no friend")
	check(party.gold == gold - cost - bed, "the night is still paid for (the card carries the consequence)")
	for i in Downtime.COMPLICATIONS.size():
		r = Downtime.carouse(party, w, city, _rng(2, Downtime.COMPLICATIONS.size(), i + 1))
		check(r["complication"] == Downtime.COMPLICATIONS[i], "the second die picks the kind (%s)" % Downtime.COMPLICATIONS[i])

	# nat 1: the complication and the tab
	gold = party.gold
	r = Downtime.carouse(party, w, city, _rng(1))
	check(not r["ok"] and r["complication"] in Downtime.COMPLICATIONS and r["complication"] != "tab", "a 1 is a story that is not the tab...")
	check(r["tab"] == Downtime.TAB_MULT * cost and party.gold == gold - cost - bed - Downtime.TAB_MULT * cost, "...because the tab comes too, twice the night's cost")
	check("bill nobody remembers" in r["text"], "and the morning says so")

	# two nights of one stay are two rolls: the day spent moves the clock, and the seed with it
	var pair := _stay_pair(w, city, party)
	check(pair[0] >= 0, "a stamp whose first two nights roll different nats (%s)" % [pair])
	if pair[0] >= 0:
		city.last_visited = float(pair[0])
		w.clock.elapsed = float(pair[1])
		party.gold = 1000
		var first: Dictionary = Downtime.carouse(party, w, city)
		var second: Dictionary = Downtime.carouse(party, w, city)
		check(first["nat"] != second["nat"], "...and they do (%d, %d)" % [first["nat"], second["nat"]])

	# the purse
	var poor := _party(cost + bed - 1)
	check(not Downtime.carouse(poor, w, city, _rng(15)).get("ok", true) and poor.gold == cost + bed - 1, "a purse short of the night and the bed stays in")
	check(Downtime.carouse(_party(100), w, w.settlements[2], _rng(15))["cost"] == Downtime.CAROUSE_COST["camp"], "a camp's night is cheaper")

# --- gambling -------------------------------------------------------------

func test_gamble() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(1000)
	Visit.visit(city, w)
	var who: Dictionary = Downtime.best_of(party, Downtime.GAMBLE_SKILLS)
	var b: int = who["bonus"]
	check(who["skill"] in Downtime.GAMBLE_SKILLS, "the party's best at Insight, Deception or Sleight of Hand sits in")
	check(Downtime.can_gamble(party, city), "a fresh visit has a game on")

	# nat 20: treble
	var before: float = w.clock.elapsed
	var r: Dictionary = Downtime.gamble(party, city, 100, _rng(20))
	check(r["ok"] and r["mult"] == 3.0 and r["won"] == 300 and party.gold == 1200, "a 20 trebles the stake")
	check(w.clock.elapsed == before, "an evening, not a day")
	check(Ach.count("trebles") == 1 and Ach.is_unlocked("gamble_treble"), "The House Loses")
	check(not Downtime.can_gamble(party, city) and Downtime.gamble(party, city, 100, _rng(20)).is_empty(), "once a visit")
	w.clock.elapsed += Visit.RESTOCK
	Visit.visit(city, w)
	check(Downtime.can_gamble(party, city), "a new visit, a new game")

	# >= DC + 5: double
	var nat: int = clampi(Downtime.GAMBLE_DC + 5 - b, 2, 19)
	party.gold = 1000
	r = Downtime.gamble(party, city, 50, _rng(nat))
	check(r["ok"] and r["mult"] == 2.0 and r["won"] == 100 and party.gold == 1050, "five over the DC doubles it")
	_revisit(city, w)

	# >= DC: half again
	nat = clampi(Downtime.GAMBLE_DC - b, 2, 19)
	party.gold = 1000
	r = Downtime.gamble(party, city, 50, _rng(nat))
	check(r["ok"] and r["mult"] == 1.5 and r["won"] == 75 and party.gold == 1025, "the DC is half again")
	_revisit(city, w)

	# < DC: gone
	party.gold = 1000
	r = Downtime.gamble(party, city, 200, _rng(2))
	check(not r["ok"] and r["mult"] == 0.0 and r["won"] == 0 and party.gold == 800 and r["complication"] == "", "under it the stake is gone")
	_revisit(city, w)

	# nat 1: gone, and they think you cheated
	party.gold = 1000
	r = Downtime.gamble(party, city, 25, _rng(1))
	check(not r["ok"] and r["won"] == 0 and party.gold == 975 and r["complication"] == "insult", "a 1 is the stake and an insult")
	_revisit(city, w)

	check(Downtime.gamble(_party(20), city, 25, _rng(20)).is_empty(), "no staking what the purse has not got")
	check(Downtime.gamble(party, city, 0, _rng(20)).is_empty(), "nor nothing")
	check(Downtime.GAMBLE_STAKES == [25, 50, 100, 200], "the stakes")

# A (stamp, clock) whose first night and the next (one DAY on) draw different
# nats off Downtime.carouse's own seed — searched, not guessed.
func _stay_pair(w, s, party) -> Array:
	for t in range(1, 5000):
		var nats: Array = []
		for night in 2:
			var r = RNG.new(maxi(1, absi(hash("carouse|%s|%d|%d" % [s.id, t, t + (night + 1) * int(Downtime.DAY)]))))
			nats.append(int(Dice.d20(r)["nat"]))
		if nats[0] != nats[1]:
			return [t, t]
	return [-1, -1]

func _revisit(s, w) -> void:
	w.clock.elapsed += Visit.RESTOCK
	Visit.visit(s, w)

# --- crafting -------------------------------------------------------------

func test_craft() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var town = w.settlements[1]
	var party := _party(1000)
	var m: Dictionary = Visit.visit(city, w)
	var potions: Array = Campaign.potion_ids()
	var expected: Array = []
	for e in m["stock"]:
		if String(e["item_id"]) in potions:
			expected.append(String(e["item_id"]))
	check(Downtime.brewable(city, m) == expected, "the alchemist brews what is on the shelf today")
	check(Downtime.scribable(city, m, party) == ["scroll-of-resurrection", "scroll-of-identification"],
		"the librarian scribes their own two scrolls to order, for a party with a caster — not the generic priced by rarity")
	var tm: Dictionary = Visit.visit(town, w)
	check(Downtime.scribable(town, tm, party).is_empty(), "no librarian in a town")
	check(Downtime.brewable(w.settlements[2], {"stock": m["stock"]}).is_empty(), "no alchemist at a camp")
	var lay := _party(1000)
	lay.swap("ilsa", "gera")   # the cleric to the bench: nobody casts
	check(Downtime.scribable(city, m, lay).is_empty(), "no caster, nothing scribed")

	# brew: half list price, a day, into the stash identified, once per item per visit
	var pid: String = potions[0]
	var shelf := {"stock": [{"item_id": pid, "name": Campaign.item_name(pid), "price": 9999}]}
	var half: int = maxi(1, int(round(Campaign.item_price(pid) * Downtime.CRAFT_RATE)))
	var bed: int = Downtime.bed_cost(city, 1)
	var before: float = w.clock.elapsed
	var r: Dictionary = Downtime.craft(party, w, city, pid, shelf)
	check(r["ok"] and r["cost"] == half and party.gold == 1000 - half - bed, "half the list price, not the shelf's")
	check(party.stash_count(pid, true) == 1 and is_equal_approx(w.clock.elapsed, before + Downtime.DAY), "a day at the bench, one in the pack")
	check(Downtime.craft(party, w, city, pid, shelf).is_empty(), "once per item per visit")
	_revisit(city, w)
	check(Downtime.craft(party, w, city, pid, shelf)["ok"], "...and again next visit")
	check(Downtime.craft(party, w, city, "longsword", shelf).is_empty(), "the bench brews and scribes, nothing else")

	# what the bench made sells for no more than it cost, whatever the shelf
	var bare: Dictionary = Visit.market(city, 0.0, true, -40.0)   # picked over, a fight nearby, disliked: the dearest shelf
	check(bare["markup"] > 1.0 and Visit.sell_price(bare, pid) <= half, "crafted at half, sold at a bare shelf: never above the bench's price (%d vs %d)" % [Visit.sell_price(bare, pid), half])
	for gap in [0.0, Visit.RESTOCK * Visit.MAX_STEPS]:
		for op in [-40.0, 0.0, 40.0]:
			check(Visit.sell_price(Visit.market(city, gap, false, op), pid) <= Downtime.craft_cost(pid), "gap %d opinion %d: sell <= craft" % [gap, op])

	# scribe
	var sid: String = Downtime.scribable(city, m, party)[0]
	party.gold = 5000   # a scroll is a rare item's price; half of it is still most of a purse
	r = Downtime.craft(party, w, city, sid, m)
	check(r["ok"] and party.stash_count(sid, true) == 1 and r["cost"] == maxi(1, int(round(Campaign.item_price(sid) * Downtime.CRAFT_RATE))), "a scroll at half price")
	check(Downtime.craft(lay, w, city, sid, m).is_empty(), "a party with no caster scribes nothing")
	var poor := _party(half + bed - 1)
	check(not Downtime.craft(poor, w, city, pid, shelf).get("ok", true) and poor.gold == half + bed - 1, "the purse has to cover the bench and the bed")

# --- the pit --------------------------------------------------------------

func test_pit() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(100)
	var br: Dictionary = Downtime.pit_bracket(city, w)
	check(br["week"] == 0 and br["names"].size() == 3 and Downtime.PIT_MULT.size() == 3, "a bracket: three champions, each pumped harder")
	check(br["names"][0] != br["names"][1] and br["names"][1] != br["names"][2] and br["names"][0] != br["names"][2], "three different names")
	check(Downtime.pit_bracket(city, w) == br, "seeded: the same week, the same three")
	w.clock.elapsed += 6 * Downtime.DAY
	check(Downtime.pit_bracket(city, w) == br, "...all week")
	w.clock.elapsed += Downtime.DAY
	var next: Dictionary = Downtime.pit_bracket(city, w)
	check(next["week"] == 1, "a new week, a new bracket")
	w.clock.elapsed = 0.0

	var st: Dictionary = Downtime.pit_state(party, city, w)
	check(st["open"] and st["beaten"] == 0 and st["week"] == 0, "the bracket stands, nobody beaten")

	# the spec: the strongest humanoid of the roster, alone, pumped, named
	var base := {"monsters": [{"id": "wolf", "count": 3, "mult": 1.0}, {"id": "bandit", "count": 2, "mult": 1.0},
		{"id": "bandit-captain", "count": 1, "mult": 1.0}], "seed": 7, "theme": "forest-clearing"}
	var spec: Dictionary = Downtime.pit_spec(party, city, w, 1, base)
	check(spec["monsters"].size() == 1 and spec["monsters"][0]["id"] == "bandit-captain" and spec["monsters"][0]["count"] == 1,
		"one foe: the strongest humanoid on the roster")
	check(spec["monsters"][0]["mult"] == Downtime.PIT_MULT[1] and spec["theme"] == "city-square" and spec["seed"] == 7, "pumped for the bout, in the square")
	check(spec["named"] == {"bandit-captain": br["names"][1]}, "...and named for the bracket")
	check(base["monsters"].size() == 3, "the base spec is not touched")
	var beasts := {"monsters": [{"id": "wolf", "count": 3, "mult": 1.0}, {"id": "brown-bear", "count": 1, "mult": 1.0}], "theme": "forest-clearing"}
	check(Downtime.pit_spec(party, city, w, 0, beasts)["monsters"][0]["id"] == "brown-bear", "no humanoid: the strongest of whatever came")

	# the purse, the deed, the bracket
	var r: Dictionary = Downtime.pit_result(party, city, w, 0, true, 0)
	check(r["purse"] == Downtime.PIT_PURSE[0] and party.gold == 100 + Downtime.PIT_PURSE[0] and Ladder.deeds(city.faction) == 1, "a win: the purse and a deed")
	st = Downtime.pit_state(party, city, w)
	check(st["open"] and st["beaten"] == 1, "one down, the bracket stands")
	Downtime.pit_result(party, city, w, 1, true, 0)
	r = Downtime.pit_result(party, city, w, 2, true, 0)
	check(party.gold == 100 + Downtime.PIT_PURSE[0] + Downtime.PIT_PURSE[1] + Downtime.PIT_PURSE[2], "three purses")
	st = Downtime.pit_state(party, city, w)
	check(not st["open"] and st["beaten"] == 3, "the bracket is done for the week")
	check(Ach.count("pit_brackets") == 1 and Ach.is_unlocked("pit_champion"), "Champion of the Pit")
	check("hampion" in r["text"], "...and the line says so")
	w.clock.elapsed += Downtime.PIT_WEEK
	check(Downtime.pit_state(party, city, w)["open"], "next week it stands again")

	# a bout begun on the week's last evening is that week's, whatever the clock says after
	party.gold = 50
	w.clock.elapsed = Downtime.PIT_WEEK * 2 - 1.0
	var wk: int = Downtime.pit_state(party, city, w)["week"]
	w.clock.elapsed += 3 * 60.0   # three rounds: the fight ran past midnight
	r = Downtime.pit_result(party, city, w, 0, true, wk)
	check(party.downtime["pit"]["riverhold"]["week"] == wk and wk == 1 and Downtime.pit_state(party, city, w)["beaten"] == 0,
		"the win is banked to the week the bout was fought in; the new week's bracket stands fresh")
	check(wk < Downtime.pit_state(party, city, w)["week"], "...though the clock is into the next")
	w.clock.elapsed = Downtime.PIT_WEEK * 2

	# a loss: carried out, the house keeps its stake, the bracket closes
	party.gold = 50
	r = Downtime.pit_result(party, city, w, 0, false, Downtime.pit_state(party, city, w)["week"])
	check(r["purse"] == -50 and party.gold == 0, "a loss costs the bout's purse, to zero: the 50 the party had")
	check("all the company had: 50 ◉ of a %d ◉ stake" % Downtime.PIT_PURSE[0] in r["text"] and not "-" in r["text"].get_slice("keeps", 1),
		"...and the line says what moved, never a signed stake (%s)" % r["text"])
	st = Downtime.pit_state(party, city, w)
	check(not st["open"] and st["beaten"] == -1, "...and closes the bracket")
	w.clock.elapsed += Downtime.PIT_WEEK
	check(Downtime.pit_state(party, city, w)["open"] and Downtime.pit_state(party, city, w)["beaten"] == 0, "a new week reopens it")

# --- complications --------------------------------------------------------

func test_complications() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var c: Dictionary = Downtime.complication("tab", city, 30)
	check(c["id"] == "downtime-tab" and c["kind"] == "bad" and c["gold"] == -60, "the tab: twice the night, on a card")
	check(c["text"].begins_with("The morning brings a bill nobody remembers running up."), "its line")
	c = Downtime.complication("brawl", city, 30)
	check(c["id"] == "downtime-brawl" and c["fight"] and c["text"].begins_with("Somebody's cousin takes exception to the company."), "the brawl: a fight")
	c = Downtime.complication("insult", city, 30)
	check(c["id"] == "downtime-insult" and c["opinion"] == -Downtime.INSULT
		and c["text"].begins_with("Something was said that should not have been, and it was heard."), "the insult: opinion")
	c = Downtime.complication("bad_lead", city, 30)
	check(c["id"] == "downtime-bad-lead" and c["lead"]["dud"] and c["lead"]["ok"] and c["lead"]["price"] == 0
		and c["text"].begins_with("A man at the bar knew exactly where the treasure was."), "the bad lead: a rumour that names nothing")
	check(not c.has("gold") and not c.has("opinion") and not c.has("fight"), "one consequence a card")
	for k in Downtime.COMPLICATIONS:
		check(not String(Downtime.complication(k, city, 30)["title"]).is_empty(), "%s has a title" % k)
	check(Downtime.complication("no-such", city, 30).is_empty(), "an unknown kind is no card")

# --- the save -------------------------------------------------------------

func test_save() -> void:
	_fresh()
	var w := _world()
	var city = w.settlements[0]
	var party := _party(5000)
	Visit.visit(city, w)
	_level(party, 4)
	Downtime.train(party, w, city, party.get_member("vera"), Downtime.trainable(party.get_member("vera"))[0])
	Downtime.gamble(party, city, 25, _rng(10))
	var sid: String = Downtime.scribable(city, {}, party)[0]
	Downtime.craft(party, w, city, sid, {})
	Downtime.pit_result(party, city, w, 0, true, 0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(Downtime.to_dict(party)))
	var back := _party(0)
	Downtime.from_dict(back, d)
	check(back.downtime["trained"] == ["vera"], "who trained")
	check(not Downtime.can_gamble(back, city) and not Downtime.can_craft(back, city, sid),
		"the once-a-visit stamps survive the file")
	check(Downtime.pit_state(back, city, w)["beaten"] == 1 and Downtime.pit_state(back, city, w)["open"], "the bracket's progress too")
	check(back.downtime["pit"]["riverhold"]["week"] is int and back.downtime["pit"]["riverhold"]["beaten"] is int, "ints come back ints")
	Downtime.from_dict(back, null)
	check(back.downtime.is_empty(), "nothing loads as nothing")
	# the world save carries it beside the callings
	var rd: Dictionary = WorldSave.to_dict(w, party)
	check(rd["party"].get("downtime", {}).get("trained", []) == ["vera"], "downtime rides the save's party dict")
	check(WorldSave.from_dict(rd)["party"].downtime.get("trained", []) == ["vera"], "...and reads back")
	# the dud lead
	var dud: Dictionary = Rumors.dud(city)
	check(dud["ok"] and dud["dud"] and dud["price"] == 0 and not dud.has("lair_id") and not dud.has("landmark_id"), "a dud names nothing")
