# T5 campaign model — stage progression, node resolution, banking, rest, shop.
#   godot --headless --path . -s tests/test_campaign.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")
const Presets = preload("res://core/presets.gd")
const Encounter = preload("res://core/encounter.gd")
const Dice = preload("res://core/dice.gd")
const CampaignSave = preload("res://core/campaign_save.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _campaign() -> Campaign:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return Campaign.new(p, 99)

func _init() -> void:
	test_route()
	test_generated_routes()
	test_boss_pool()
	test_treasure()
	test_combat()
	test_defeat()
	test_rest()
	test_rest_is_limited_per_run()
	test_merchant()
	test_settlements()
	test_quest_flow()
	test_identification()
	test_opportunity()
	test_full_run()
	print("test_campaign: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- the route ------------------------------------------------------------

func test_route() -> void:
	var c := _campaign()
	check(c.route.size() == Campaign.STAGE_COUNT, "the route has %d stages" % Campaign.STAGE_COUNT)
	var kinds := {}
	for n in Campaign.POOL:
		check(n["kind"] in ["combat", "treasure", "merchant", "rest"], "%s has a known kind" % n["id"])
		kinds[n["kind"]] = true
		check(not n["stage_position"].is_empty(), "%s is eligible somewhere" % n["id"])
		for pos in n["stage_position"]:
			check(pos in Campaign.STAGE_POSITIONS, "%s names a real stage position" % n["id"])
		if n["kind"] == "combat":
			check(n.get("difficulty", "") in ["easy", "normal", "hard"], "%s has a difficulty" % n["id"])
	check(kinds.size() == 4, "all four node kinds are in the pool")

	check(c.stage == 0 and c.state == "picking", "a fresh campaign starts at stage 0")
	check(c.options().size() == c.route[0].size(), "options() is the current stage")
	check(c.enter(9).is_empty(), "an out-of-range choice is refused")
	check(c.enter(0)["id"] == c.route[0][0]["id"], "enter picks the node")
	check(c.enter(1).is_empty(), "cannot enter a second node on the same stage")
	c.state = "visiting"
	c.leave()
	check(c.stage == 1 and c.state == "picking", "leave advances the stage")

# --- T12: the route is generated per seed ---------------------------------

func test_generated_routes() -> void:
	var seeds := [1, 7, 42, 99, 1234, 55555, 8, 313, 2024, 77]
	var seen_ids := {}
	var signatures := {}
	for s in seeds:
		var c := _route(s)
		signatures[_signature(c)] = true
		check(_route(s) != null and _signature(_route(s)) == _signature(c),
			"seed %d reproduces the same route" % s)
		var ids := {}
		var total := 0
		for i in c.route.size():
			var stage: Array = c.route[i]
			for n in stage:
				ids[n["id"]] = true
				seen_ids[n["id"]] = true
				total += 1
				if n["kind"] == "combat":
					check(n["theme"] in Encounter.THEMES,
						"seed %d: %s names a real board" % [s, n["id"]])
			if i == c.route.size() - 1:
				check(stage.size() == 1 and stage[0]["kind"] == "combat" and stage[0].get("boss", false),
					"seed %d ends on exactly one boss fight" % s)
			else:
				check(stage.size() >= 2 and stage.size() <= 3, "seed %d stage %d offers 2-3 nodes" % [s, i])
				for n in stage:
					check(Campaign.STAGE_POSITIONS[i] in n["stage_position"],
						"seed %d: %s is eligible for stage %d" % [s, n["id"], i])
		check(ids.size() == total, "seed %d shows no node template twice on one route" % s)
		var kinds := {}
		check(c.route[0].all(func(n): return n["kind"] == "combat"),
			"seed %d's opening stage is combat-only, no road-not-taken options" % s)
		for i in c.route.size() - 1:
			var fights: Array = c.route[i].filter(func(n): return n["kind"] == "combat")
			if i == 0:
				continue   # the opening stage is deliberately all-combat, checked above
			check(fights.size() >= 1 and fights.size() < c.route[i].size(),
				"seed %d stage %d offers both a fight and a road round it" % [s, i])
			for n in c.route[i]:
				kinds[n["kind"]] = true
		check(kinds.size() == 4, "seed %d walks all four node kinds before the boss" % s)
		var givers := 0
		for i in c.route.size() - 1:
			for n in c.route[i]:
				if Campaign.has_service(n, "innkeeper"):
					givers += 1
		check(givers > 0, "seed %d offers a settlement with an Innkeeper before the boss" % s)
	check(signatures.size() >= seeds.size() - 1, "different seeds produce different routes")
	check(seen_ids.size() >= 20, "the pool is deep enough for real variety (saw %d templates)"
		% seen_ids.size())

# --- T18: the boss is seed-picked out of a pool ---------------------------

func test_boss_pool() -> void:
	check(Campaign.BOSS in Campaign.BOSS_POOL, "the classic Sunken Shrine boss is still in the pool")
	var archetypes := {}
	for b in Campaign.BOSS_POOL:
		archetypes[b.get("archetype", "")] = true
		check(b.get("boss", false) and b["kind"] == "combat" and b["stage_position"] == ["boss"],
			"%s is a boss combat node" % b["id"])
		check(b["theme"] in Encounter.THEMES, "%s names a real board" % b["id"])
		check(int(b.get("gold", 0)) > 0 and b.get("difficulty", "") == "hard",
			"%s pays a boss purse and fights at boss difficulty" % b["id"])
		if b.get("archetype", "") == "elite":
			check(b.has("lead") and not b.get("lead_features", []).is_empty(),
				"%s is an ordinary monster with an extra attack bolted on" % b["id"])
		# every entry resolves to a buildable spec, with the lead actually on the board
		var c := _route(4)
		c.node = b
		var spec := c.combat_spec()
		check(not spec["monsters"].is_empty(), "%s produces a roster" % b["id"])
		var party: Array = []
		for i in c.party.party_characters().size():
			party.append(load("res://core/adapter.gd").to_combatant(
				c.party.party_characters()[i], "party", Encounter.PARTY_STARTS[i]))
		var cb = Encounter.build(spec, party)
		check(cb.team_of("foe").size() >= 2, "%s builds a real board" % b["id"])
		if b.has("lead"):
			var leads: Array = cb.team_of("foe").filter(func(f): return f.src_id == b["lead"])
			check(leads.size() == int(b.get("lead_count", 1)), "%s spawns its lead" % b["id"])
		var ids := {}
		for f in cb.team_of("foe"):
			check(not ids.has(f.id), "%s spawns no two foes with one id (%s)" % [b["id"], f.id])
			ids[f.id] = true
	check(archetypes.has("classic") and archetypes.has("bestiary") and archetypes.has("elite"),
		"the pool mixes both new archetypes with the classic boss")

	# seed-picked, reproducibly, and not always the same one
	var picked := {}
	for s in range(1, 41):
		var boss: Dictionary = _route(s).route[-1][0]
		check(_route(s).route[-1][0]["id"] == boss["id"], "seed %d picks the same boss twice" % s)
		check(boss in Campaign.BOSS_POOL, "seed %d's boss comes out of the pool" % s)
		picked[boss["id"]] = int(picked.get(boss["id"], 0)) + 1
	check(picked.size() == Campaign.BOSS_POOL.size(),
		"40 seeds reach every boss in the pool (saw %d of %d)" % [picked.size(), Campaign.BOSS_POOL.size()])

func _route(seed_value: int) -> Campaign:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return Campaign.new(p, seed_value)

func _signature(c: Campaign) -> String:
	var out: Array = []
	for stage in c.route:
		out.append(",".join(stage.map(func(n): return String(n["id"]))))
	return "|".join(out)

func test_treasure() -> void:
	var c := _campaign()
	var i := _find(c, "treasure")
	var n: Dictionary = c.options()[i]
	c.enter(i)
	check(c.state == "visiting", "a treasure node is visited, not fought")
	check(c.party.gold == int(n["gold"]), "treasure gold is banked immediately")
	check(c.party.stash_count(String(n["item_id"])) == 1, "the treasure item lands in the stash")

# --- combat ---------------------------------------------------------------

func test_combat() -> void:
	var c := _campaign()
	c.enter(_find(c, "combat"))
	check(c.state == "combat", "a combat node waits for the fight")
	var spec := c.combat_spec()
	check(not spec["monsters"].is_empty(), "combat_spec produces a roster")

	# The bias hook: an active quest changes what the next fight spawns.
	Quest.accept(c.party, Quest.fresh("kritch-bounty"))
	var biased := c.combat_spec()
	check(_count(biased, "kritch") > _count(spec, "kritch"), "an active quest biases combat_spec")

	var gold: int = c.party.gold
	c.finish_combat({"outcome": "Victory", "xp": 300, "gold": 40, "loot": ["dagger"],
		"deaths": ["pike"], "kills": ["kritch", "kritch", "snik"]})
	check(c.xp == 300, "xp is banked on the campaign")
	for ch in c.party.roster:
		check(ch.xp == 100, "%s got an even share of the 300 XP" % ch.id)
	check(c.party.gold == gold + 40, "gold is banked on the party")
	check(c.party.stash_count("dagger") == 1, "loot lands in the stash")
	check(not c.party.is_active("pike"), "the dead are benched")
	check(c.party.get_member("pike").dead, "the dead are flagged dead")
	check(not c.party.activate("pike"), "and cannot walk back into the party")
	check(Quest.get_quest(c.party, "kritch-bounty")["progress"] == 2, "kills feed quest progress")
	check(c.state == "visiting", "after the fight the node shows its after-action panel")
	var was: int = c.stage
	c.leave()
	check(c.stage == was + 1, "the route advances past the fight")

	# The boss node carries its own purse on top of the fight's.
	var c2 := _campaign()
	c2.stage = c2.route.size() - 1
	var boss := c2.enter(0)
	c2.finish_combat({"outcome": "Victory", "xp": 10, "gold": 10, "loot": [], "deaths": [], "kills": []})
	check(c2.party.gold == 10 + int(boss["gold"]), "node gold is added to fight gold")
	var expect_mult: float = clampf(Campaign.BOSS_REF_WIN_RATE / float(boss["win_rate"]),
		1.0, Campaign.BOSS_XP_MULT_CAP)
	check(c2.xp == roundi(10 * expect_mult),
		"a harder-than-average boss (win_rate %.2f) pays out %.2fx XP" % [boss["win_rate"], expect_mult])
	check(expect_mult >= 1.0 and expect_mult <= Campaign.BOSS_XP_MULT_CAP,
		"boss XP multiplier never drops below 1x or exceeds the cap")
	c2.leave()

	# A plain (non-boss) node never applies the boss multiplier.
	var c3 := _campaign()
	c3.enter(_find(c3, "combat"))
	c3.finish_combat({"outcome": "Victory", "xp": 50, "gold": 0, "loot": [], "deaths": [], "kills": []})
	check(c3.xp == 50, "a non-boss fight pays plain XP")
	check(c2.state == "won", "clearing the last stage wins the run")

func test_defeat() -> void:
	var c := _campaign()
	c.enter(_find(c, "combat"))
	var was: int = c.stage
	c.finish_combat({"outcome": "Defeat", "xp": 0, "gold": 0, "loot": [], "deaths": ["vera"], "kills": []})
	check(c.state == "lost", "a defeat ends the run")
	c.leave()
	check(c.state == "lost" and c.stage == was, "a lost run does not advance")

	# Death is a within-run cost: a concluded run (won or lost) revives everyone free.
	var c2 := _campaign()
	c2.enter(_find(c2, "combat"))
	c2.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": ["vera"],
		"kills": []})
	check(c2.party.get_member("vera").dead, "vera died mid-run")
	c2.stage = c2.route.size() - 1
	c2.state = "visiting"
	c2.leave()
	check(c2.state == "won" and not c2.party.get_member("vera").dead,
		"winning the run revives the fallen for free")
	var c3 := _campaign()
	c3.enter(_find(c3, "combat"))
	c3.party.get_member("pike").dead = true
	c3.finish_combat({"outcome": "Defeat", "xp": 0, "gold": 0, "loot": [], "deaths": [], "kills": []})
	check(not c3.party.get_member("pike").dead, "losing the run revives the fallen too")

	# The resurrection path through the campaign.
	var c4 := _campaign()
	var ilsa = c4.party.get_member("ilsa")
	ilsa.prepared.append(Party.REVIVE_SPELL)
	for _i in 2:
		ilsa.add_level("cleric")
	c4.enter(_find(c4, "combat"))
	c4.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": ["vera"],
		"kills": []})
	check(not c4.resurrect("vera", "spell"), "no gold, no resurrection")
	c4.party.add_gold(400)
	check(c4.resurrect("vera", "spell", "ilsa"), "the campaign can raise the fallen")
	check(not c4.party.get_member("vera").dead and c4.party.gold == 100, "raised, and 300 gp poorer")

# --- rest / merchant ------------------------------------------------------

func test_rest() -> void:
	var c := _campaign()
	c.enter(_find(c, "rest"))
	var ch = c.party.party_characters()[0]
	ch.hp_current = 1
	var used: Array[int] = [1]
	ch.slots_used = used
	c.rest("long-rest")
	check(ch.hp_current == -1, "a long rest restores HP (the sheet's full-HP sentinel)")
	check(ch.slots_used.is_empty(), "a long rest restores spell slots")
	var max_hp: int = ch.sheet().max_hp
	ch.hp_current = 3
	c.rest("short-rest")
	check(ch.hp_current == 3 + ceili((max_hp - 3) / 2.0),
		"a short rest heals half the missing HP, not all of it (no Hit Dice pool to spend instead)")

# Rest is a limited resource: 2 short + 1 long per run, not a free reset.
func test_rest_is_limited_per_run() -> void:
	var c := _campaign()
	c.enter(_find(c, "rest"))
	check(c.long_rests_left() == 1 and c.short_rests_left() == 2, "a fresh run starts with the full budget")
	check(c.rest("long-rest"), "the one long rest succeeds")
	check(c.long_rests_left() == 0, "...and it's spent")
	check(not c.rest("long-rest"), "a second long rest this run is refused")
	check(c.rest("short-rest") and c.rest("short-rest"), "both short rests succeed")
	check(c.short_rests_left() == 0, "...and both are spent")
	check(not c.rest("short-rest"), "a third short rest this run is refused")

	# and it survives an autosave/resume round trip
	var d = CampaignSave.from_dict(CampaignSave.to_dict(c))
	check(d.long_rests_used == 1 and d.short_rests_used == 2,
		"rest counters persist across a save/load")

func test_merchant() -> void:
	var c := _campaign()
	c.enter(_find(c, "merchant"))
	var stock := c.stock()
	check(stock.size() == c.stock_ids().size(), "the shop lists its stock")
	for e in stock:
		check(e["price"] > 0 and e["name"] != e["item_id"], "%s has a real name and price" % e["item_id"])

	check(not c.buy("longsword"), "cannot buy while broke")
	c.party.add_gold(500)
	var gold: int = c.party.gold
	check(c.buy("longsword"), "buy")
	check(c.party.gold == gold - Campaign.item_price("longsword"), "buying costs the list price")
	check(c.party.stash_count("longsword") == 1, "the purchase lands in the stash")
	check(not c.buy("crown-of-the-gods"), "cannot buy what is not stocked")
	check(c.sell("longsword"), "sell")
	check(c.party.stash_count("longsword") == 0, "the sold item leaves the stash")
	check(c.party.gold == gold - Campaign.item_price("longsword") + maxi(1,
		int(Campaign.item_price("longsword") * Campaign.SELL_RATE)), "selling pays half")
	check(not c.sell("longsword"), "cannot sell what you do not have")

	# T10 pricing: mundane gear at its SRD cost, magic items by rarity tier.
	check(Campaign.item_price("longsword") == 15, "a longsword costs its SRD 15 gp")
	check(Campaign.item_price("dagger") < Campaign.item_price("longsword"),
		"mundane prices stay power-correlated")
	check(Campaign.item_price("plate") > Campaign.item_price("leather"), "plate beats leather")
	var common := Campaign.item_price("potion-of-climbing")
	var uncommon := Campaign.item_price("adamantine-armor")
	var rare := Campaign.item_price("scroll-of-resurrection")
	var very_rare := Campaign.item_price("ammunition-of-slaying")
	var legendary := Campaign.item_price("apparatus-of-the-crab")
	check(common >= 20 and common <= 30, "common lands in the 20-30 gp band (got %d)" % common)
	check(uncommon >= 300 and uncommon <= 600, "uncommon lands in 300-600 gp (got %d)" % uncommon)
	check(rare >= 1500 and rare <= 3000, "rare lands in 1500-3000 gp (got %d)" % rare)
	check(very_rare >= 5000 and very_rare <= 10000, "very-rare lands in 5k-10k (got %d)" % very_rare)
	check(legendary >= 12000 and legendary <= 25000, "legendary lands in 12k-25k (got %d)" % legendary)
	check(common < uncommon and uncommon < rare and rare < very_rare and very_rare < legendary,
		"the tiers are ordered")
	check(Campaign.item_price("no-such-item") == 0, "an unknown item has no price")

	# The scroll is stocked at some merchants and buyable there.
	var scrolls := 0
	for n in Campaign.POOL:
		if n["kind"] != "merchant":
			continue
		var m := _campaign()   # a fresh party per merchant: stashes must not pile up
		m.node = n
		if Campaign.SCROLL in m.stock_ids():
			scrolls += 1
			m.party.add_gold(rare)
			check(m.buy(Campaign.SCROLL), "the scroll can be bought where it is stocked")
			check(m.party.stash_count(Campaign.SCROLL) == 1, "and lands in the stash")
	check(scrolls > 0, "at least one merchant in the pool stocks the scroll")

# --- T25: sized settlements ------------------------------------------------

func test_settlements() -> void:
	var innkeepers := 0
	for n in Campaign.POOL:
		if n["kind"] != "merchant":
			continue
		var size := String(n.get("size", ""))
		check(Campaign.SIZE_SPECIALISTS.has(size), "%s names a real size" % n["id"])
		var want: Array = Campaign.SIZE_SPECIALISTS.get(size, [0, 0])
		var specialists: Array = n.get("services", [])
		check(specialists.size() >= int(want[0]) and specialists.size() <= int(want[1]),
			"%s: a %s carries %d-%d specialists (has %d)" % [n["id"], size, want[0], want[1],
				specialists.size()])
		var services := Campaign.node_services(n)
		check(services[0] == "generalist", "%s puts the Generalist first" % n["id"])
		check(services.size() == specialists.size() + 1, "%s: Generalist plus its specialists" % n["id"])
		for s in services:
			check(s in Campaign.SERVICE_ORDER, "%s: %s is a real service" % [n["id"], s])
			check(String(n.get("npcs", {}).get(s, "")) != "", "%s: %s has a flavour line" % [n["id"], s])
		if Campaign.has_service(n, "innkeeper"):
			innkeepers += 1
	check(innkeepers > 0, "somebody on the road keeps an inn")

	# Every quest's giver is a settlement with an Innkeeper (replaces GIVER_IDS).
	for q in Quest.CURATED:
		var giver: Array = Campaign.POOL.filter(func(n): return n["id"] == q["giver_node_id"])
		check(giver.size() == 1 and Campaign.has_service(giver[0], "innkeeper"),
			"%s is given by an Innkeeper" % q["id"])

	# Catalogs: Generalist is unchanged, specialists widen it.
	var c := _campaign()
	c.node = _pool("hollow-market")
	for id in Campaign.STOCK:
		check(id in c.service_stock_ids("generalist"), "the Generalist still stocks %s" % id)
	check(c.service_stock_ids("weaponsmith").size() > Campaign.STOCK.size(),
		"the Weaponsmith sells the whole weapon catalog")
	check("greatsword" in c.service_stock_ids("weaponsmith"), "including one the Generalist lacks")
	check("plate" in c.service_stock_ids("armorsmith"), "the Armorsmith sells the whole armour catalog")
	check(c.service_stock_ids("healer").is_empty(), "the Healer sells no goods")
	check("plate" in c.shop_ids() and "greatsword" in c.shop_ids(), "the settlement sells both")
	c.party.add_gold(Campaign.item_price("plate"))
	check(c.buy("plate"), "a specialist's stock is buyable")

	var alch := _campaign()
	alch.node = _pool("shuttered-shop")
	var potions := alch.service_stock_ids("alchemist")
	check("potions-of-healing" in potions and "potion-of-speed" in potions and not "potion-of-flying" in potions,
		"the Alchemist sells potions — the ones that do something")
	check(not "plate" in alch.shop_ids(), "a village without an Armorsmith sells no plate")

	# Healer, Librarian, Innkeeper: the three that are not just a catalog.
	var t := _campaign()
	t.node = _pool("caravanserai")
	var ch = t.party.party_characters()[0]
	ch.hp_current = 1
	check(not t.heal_party(), "the healer wants paying")
	t.party.add_gold(Campaign.HEALER_GP + Campaign.IDENTIFY_FEE_GP)
	check(t.heal_party() and ch.hp_current == -1, "the healer puts the party back to full")
	t.party.stash_add(MYSTERY, 1, false)
	check(t.identify_for_fee(MYSTERY), "the librarian identifies for a flat fee, no roll")
	check(t.party.stash_count(MYSTERY, true) == 1, "and the item is known")
	check(not t.identify_for_fee(MYSTERY), "nothing left to read")
	check(t.offer().is_empty(), "no Innkeeper here, no work")
	var camp := _campaign()
	camp.node = _pool("pack-mule")
	check(camp.offer().is_empty(), "a Generalist-only camp offers no quests")
	check(not camp.heal_party() and not camp.identify_for_fee(MYSTERY),
		"and has neither healer nor librarian")

func _pool(id: String) -> Dictionary:
	for n in Campaign.POOL:
		if n["id"] == id:
			return n
	check(false, "no pool node %s" % id)
	return {}

func test_quest_flow() -> void:
	var c := _campaign()
	c.enter(_find(c, "combat"))
	check(c.offer().is_empty(), "combat nodes offer no quests")
	var c2 := _campaign()
	c2.enter(_find_giver(c2))
	var q := c2.offer()
	check(not q.is_empty(), "the quest-giving merchant offers a quest")
	check(c2.accept(q), "accept at the merchant")
	check(c2.party.quests.size() == 1, "the quest is in the party log")
	check(not c2.turn_in(q), "cannot turn in an unfinished quest")
	q["progress"] = int(q["required"])
	q["state"] = "complete"
	if q["kind"] in ["collect_item", "supply_item"]:   # a goods job is paid for goods in hand
		check(not c2.turn_in(q), "a goods job with nothing in the pack is not paid")
		c2.party.stash_add(String(q["target_item_id"]), int(q["required"]))
	var gold: int = c2.party.gold
	check(c2.turn_in(q), "turn in at the merchant")
	check(c2.party.gold > gold, "the reward is paid")

# The whole loop, model-only: walk every stage taking the first node, faking each fight.
# T13 — identification. Loot is a mystery until examined (DC 15 Arcana, at a rest
# node only) or a Scroll of Identification is burned on it (any time, no roll).
const MYSTERY := "cloak-of-elvenkind"

func test_identification() -> void:
	# treasure: a magic item arrives unidentified, mundane steel arrives as itself
	var c := _campaign()
	c.node = {"kind": "treasure", "id": "hoard", "gold": 0, "item_id": MYSTERY}
	c._take_treasure()
	check(c.party.stash_count(MYSTERY) == 1, "the magic item lands in the stash")
	check(c.party.stash_count(MYSTERY, true) == 0, "and lands unidentified")
	check(c.party.unidentified().size() >= 1, "it shows up as a mystery")
	check(Campaign.mystery_name(MYSTERY) == "Unidentified item (uncommon)",
		"a mystery shows its rarity and nothing else (got %s)" % Campaign.mystery_name(MYSTERY))
	c.node["item_id"] = "handaxe"
	c._take_treasure()
	check(c.party.stash_count("handaxe", true) == 1, "mundane loot needs no identifying")
	check(Campaign.is_magic(MYSTERY) and not Campaign.is_magic("handaxe"), "is_magic splits the two")

	# a found identification scroll is never itself a mystery -- it'd otherwise
	# take an identify roll (or a second copy of itself) just to use it at all
	c.node["item_id"] = Campaign.IDENTIFY_SCROLL
	c._take_treasure()
	check(c.party.stash_count(Campaign.IDENTIFY_SCROLL, true) == 1,
		"a found identify scroll lands already identified")
	check(Campaign.is_magic(Campaign.IDENTIFY_SCROLL), "...even though it's still a real magic item")

	# the check is a rest-node action only
	var d := _campaign()
	d.party.stash_add(MYSTERY, 1, false)
	d.node = {"kind": "merchant", "id": "shop"}
	check(not d.identify_check(MYSTERY, d.arcana_examiner()), "no examining at a merchant")
	d.node = {"kind": "rest", "id": "camp"}
	check(not d.identify_check("handaxe", d.arcana_examiner()), "nothing to identify on mundane gear")
	check(not d.identify_check(MYSTERY, "nobody"), "a stranger cannot examine it")

	# both outcomes are reachable across seeds, and a failure is final for this camp
	var hits := 0
	var misses := 0
	for seed_value in range(1, 41):
		var e := _campaign()
		e.rng = load("res://core/rng.gd").new(seed_value)
		e.party.stash_add(MYSTERY, 1, false)
		e.node = {"kind": "rest", "id": "camp"}
		var who := e.arcana_examiner()
		check(who != "", "somebody in the party can examine it")
		if e.identify_check(MYSTERY, who):
			hits += 1
			check(e.party.stash_count(MYSTERY, true) == 1, "a success identifies the item")
			check(not e.identify_check(MYSTERY, who), "nothing left to identify")
		else:
			misses += 1
			check(e.party.stash_count(MYSTERY, true) == 0, "a failure leaves it a mystery")
			check(MYSTERY in e.identify_failed, "the failure is recorded for this camp")
			check(not e.identify_check(MYSTERY, who), "no retry at the same camp")
			e.enter(0)
			check(e.identify_failed.is_empty(), "a new node is a fresh chance")
	print("  arcana (uncommon, 90%% target) over 40 seeds: %d identified, %d failed" % [hits, misses])
	check(hits > 0 and misses > 0, "both outcomes are reachable (%d/%d)" % [hits, misses])

	# DC is fixed per rarity (not per examiner) and rises with rarity
	check(Campaign.identify_dc("adamantine-armor") == 5, "uncommon DC (got %d)" % Campaign.identify_dc("adamantine-armor"))
	check(Campaign.identify_dc("amulet-of-health") == 7, "rare DC (got %d)" % Campaign.identify_dc("amulet-of-health"))
	check(Campaign.identify_dc("ammunition-of-slaying") == 11,
		"very-rare DC (got %d)" % Campaign.identify_dc("ammunition-of-slaying"))
	check(Campaign.identify_dc("apparatus-of-the-crab") == 16,
		"legendary DC (got %d)" % Campaign.identify_dc("apparatus-of-the-crab"))
	var dcs := [Campaign.identify_dc("adamantine-armor"), Campaign.identify_dc("amulet-of-health"),
		Campaign.identify_dc("ammunition-of-slaying"), Campaign.identify_dc("apparatus-of-the-crab")]
	check(dcs[0] < dcs[1] and dcs[1] < dcs[2] and dcs[2] < dcs[3], "DC strictly rises with rarity")

	# ratios at the +2 reference examiner should land near each rarity's stated target
	for pair in [["amulet-of-health", "rare", 0.80], ["ammunition-of-slaying", "very-rare", 0.60]]:
		var item: String = pair[0]
		var target: float = pair[2]
		var ok := 0
		var n := 200
		for s in range(1, n + 1):
			var r = load("res://core/rng.gd").new(s)
			if int(Dice.d20(r)["nat"]) + Campaign.REFERENCE_ARCANA_BONUS >= Campaign.identify_dc(item):
				ok += 1
			r = null
		var rate := float(ok) / n
		print("  %s (%s) at +%d ref: %.0f%% over %d rolls (target %.0f%%)" %
			[item, pair[1], Campaign.REFERENCE_ARCANA_BONUS, rate * 100.0, n, target * 100.0])
		check(absf(rate - target) < 0.12, "%s ratio close to its %.0f%% target (got %.0f%%)" %
			[pair[1], target * 100.0, rate * 100.0])

	# the scroll: no roll, no rest, always works, always consumed
	var f := _campaign()
	f.party.stash_add(MYSTERY, 1, false)
	f.node = {}
	check(not f.identify_with_scroll(MYSTERY), "no scroll, no shortcut")
	f.party.stash_add(Campaign.IDENTIFY_SCROLL)
	check(f.identify_with_scroll(MYSTERY), "the scroll works anywhere, with no roll")
	check(f.party.stash_count(MYSTERY, true) == 1, "the item is identified")
	check(f.party.stash_count(Campaign.IDENTIFY_SCROLL) == 0, "the scroll is consumed")

	# stocked at every merchant, priced by the shared formula, and a treasure drop
	var price := Campaign.item_price(Campaign.IDENTIFY_SCROLL)
	check(price == 400, "the scroll prices as an uncommon item (got %d)" % price)
	check(price < Campaign.item_price(Campaign.SCROLL), "cheaper than the resurrection scroll")
	var g := _campaign()
	g.enter(_find(g, "merchant"))
	check(Campaign.IDENTIFY_SCROLL in g.stock_ids(), "the merchant stocks it")
	g.party.add_gold(price)
	check(g.buy(Campaign.IDENTIFY_SCROLL), "and sells it")
	check(g.party.stash_count(Campaign.IDENTIFY_SCROLL, true) == 1, "a purchase is pre-identified")
	var drops := 0
	for seed_value in range(1, 21):
		var h := _campaign()
		h.rng = load("res://core/rng.gd").new(seed_value)
		h.node = {"kind": "treasure", "id": "hoard", "gold": 0}
		h._take_treasure()
		drops += h.party.stash_count(Campaign.IDENTIFY_SCROLL)
	check(drops > 0 and drops < 20, "the scroll drops from hoards sometimes, not always (%d/20)" % drops)

# T30 — one skill check per node: Perception in a treasure room (bonus purse),
# Survival after a victory (the next stage's fights, named in advance).
func test_opportunity() -> void:
	var c := _campaign()
	check(c.opportunity().is_empty(), "no check on offer while picking")
	c.enter(_find(c, "treasure"))
	var opp := c.opportunity()
	check(opp.get("skill", "") == "perception" and opp.get("char_id", "") != "",
		"a treasure room offers a Perception check to somebody")
	check(c.opportunity_check(), "the check resolves")
	check(c.opportunity_taken and c.opportunity().is_empty(), "and there is no second attempt here")

	# both outcomes are reachable, and a success pays
	var hits := 0
	var misses := 0
	for s in range(1, 41):
		var e := _campaign()
		e.enter(_find(e, "treasure"))
		e.rng = load("res://core/rng.gd").new(s)
		var gold: int = e.party.gold
		if e.opportunity_check():
			hits += 1
			check(e.party.gold > gold, "a found purse is banked")
		else:
			misses += 1
			check(e.party.gold == gold, "a failed search pays nothing")
	check(hits > 0 and misses > 0, "both outcomes are reachable (%d/%d)" % [hits, misses])

	# after a victory: Survival names what is on the next stage
	var d := _campaign()
	d.enter(_find(d, "combat"))
	check(d.opportunity().is_empty(), "no check mid-fight")
	d.finish_combat({"outcome": "Victory", "xp": 10, "gold": 0, "loot": [], "deaths": [], "kills": []})
	check(d.opportunity().get("skill", "") == "survival", "a won fight offers a Survival check")
	var found := false
	for s in range(1, 41):
		var e := _campaign()
		e.enter(_find(e, "combat"))
		e.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": [], "kills": []})
		e.rng = load("res://core/rng.gd").new(s)
		if e.opportunity_check():
			found = true
			check(e.scouted.size() > 0, "a success names the next stage's fights")
			for n in e.scouted:
				check(n in e.route[e.stage + 1] and n["kind"] == "combat",
					"and they are really the next stage's fights")
			var ahead: Array = e.scouted.duplicate()
			e.leave()
			# T41: walk into one of the fights that was named, mid-combat-save it,
			# and the guaranteed ambush has to come back with it.
			var into := 0
			for j in e.options().size():
				if e.options()[j] in ahead:
					into = j
			e.enter(into)
			check(e.scouted.is_empty(), "the forewarning is spent once the party walks on")
			check(e.node_scouted, "but entering a scouted fight remembers it was scouted")
			check(CampaignSave.from_dict(CampaignSave.to_dict(e)).node_scouted,
				"and that guarantee survives a mid-combat save/load")
			break
	check(found, "a Survival success is reachable")

	# the boss stage has no road after it to scout
	var f := _campaign()
	f.stage = f.route.size() - 1
	f.enter(0)
	f.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": [], "kills": []})
	check(f.opportunity().is_empty(), "nothing to scout past the boss")

	# a rest or merchant node offers none
	var g := _campaign()
	g.enter(_find(g, "rest"))
	check(g.opportunity().is_empty(), "no check at a camp")

	# opportunity state survives an autosave/resume round trip mid-node
	var h := _campaign()
	h.enter(_find(h, "combat"))
	h.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": [], "kills": []})
	h.opportunity_check()
	var reloaded = CampaignSave.from_dict(CampaignSave.to_dict(h))
	check(reloaded.opportunity_taken == h.opportunity_taken,
		"a reload of the same node doesn't hand back a spent check")
	check(reloaded.scouted == h.scouted, "and a Survival success's forewarning survives too")

func test_full_run() -> void:
	var c := _campaign()
	var stages := 0
	while c.state == "picking":
		var n := c.enter(0)
		check(not n.is_empty(), "stage %d offers an enterable node" % c.stage)
		if c.state == "combat":
			c.finish_combat({"outcome": "Victory", "xp": 100, "gold": 25, "loot": [],
				"deaths": [], "kills": ["snik"]})
		c.leave()
		stages += 1
	check(c.state == "won", "the run can be completed")
	check(stages == Campaign.STAGE_COUNT, "every stage was walked once")
	check(c.xp > 0 and c.party.gold > 0, "the run banked xp and gold")
	check(c.log.size() >= stages, "the run journal recorded each node")

# --- helpers --------------------------------------------------------------

# T12: the route is generated, so a kind is no longer at a known stage — walk
# forward (moving `c.stage`) to the first stage that offers one.
func _find(c: Campaign, kind: String) -> int:
	while c.stage < c.route.size():
		var opts := c.options()
		for i in opts.size():
			if opts[i]["kind"] == kind:
				return i
		c.stage += 1
	check(false, "the route has no %s node" % kind)
	c.stage = 0
	return 0

# The route always plants one merchant that hands out quests; find it.
func _find_giver(c: Campaign) -> int:
	while c.stage < c.route.size():
		var opts := c.options()
		for i in opts.size():
			if Campaign.has_service(opts[i], "innkeeper"):
				return i
		c.stage += 1
	check(false, "the route has no quest-giving merchant")
	c.stage = 0
	return 0

func _count(spec: Dictionary, id: String) -> int:
	for e in spec["monsters"]:
		if e["id"] == id:
			return int(e["count"])
	return 0
