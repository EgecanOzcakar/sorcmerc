# T5 campaign model — stage progression, node resolution, banking, rest, shop.
#   godot --headless --path . -s tests/test_campaign.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")
const Presets = preload("res://core/presets.gd")

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
	test_treasure()
	test_combat()
	test_defeat()
	test_rest()
	test_merchant()
	test_quest_flow()
	test_full_run()
	print("test_campaign: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- the route ------------------------------------------------------------

func test_route() -> void:
	var c := _campaign()
	check(Campaign.STAGES.size() >= 4, "the route has 4+ stages")
	var kinds := {}
	for stage in Campaign.STAGES:
		check(stage.size() >= 1 and stage.size() <= 3, "a stage offers 1-3 nodes")
		for n in stage:
			check(n["kind"] in ["combat", "treasure", "merchant", "rest"], "%s has a known kind" % n["id"])
			kinds[n["kind"]] = true
			if n["kind"] == "combat":
				check(n.get("difficulty", "") in ["easy", "normal", "hard"], "%s has a difficulty" % n["id"])
	check(kinds.size() == 4, "all four node kinds appear on the route")
	var last: Array = Campaign.STAGES[Campaign.STAGES.size() - 1]
	check(last.size() == 1 and last[0]["kind"] == "combat" and last[0].get("boss", false),
		"the route ends on a boss fight")

	check(c.stage == 0 and c.state == "picking", "a fresh campaign starts at stage 0")
	check(c.options().size() == Campaign.STAGES[0].size(), "options() is the current stage")
	check(c.enter(9).is_empty(), "an out-of-range choice is refused")
	check(c.enter(0)["id"] == Campaign.STAGES[0][0]["id"], "enter picks the node")
	check(c.enter(1).is_empty(), "cannot enter a second node on the same stage")
	c.state = "visiting"
	c.leave()
	check(c.stage == 1 and c.state == "picking", "leave advances the stage")

func test_treasure() -> void:
	var c := _campaign()
	c.stage = 2
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
	c.leave()
	check(c.stage == 1, "the route advances past the fight")

	# The boss node carries its own purse on top of the fight's.
	var c2 := _campaign()
	c2.stage = Campaign.STAGES.size() - 1
	c2.enter(0)
	c2.finish_combat({"outcome": "Victory", "xp": 10, "gold": 10, "loot": [], "deaths": [], "kills": []})
	check(c2.party.gold == 10 + int(Campaign.STAGES[c2.stage][0]["gold"]), "node gold is added to fight gold")
	c2.leave()
	check(c2.state == "won", "clearing the last stage wins the run")

func test_defeat() -> void:
	var c := _campaign()
	c.enter(_find(c, "combat"))
	c.finish_combat({"outcome": "Defeat", "xp": 0, "gold": 0, "loot": [], "deaths": ["vera"], "kills": []})
	check(c.state == "lost", "a defeat ends the run")
	c.leave()
	check(c.state == "lost" and c.stage == 0, "a lost run does not advance")

	# Death is a within-run cost: a concluded run (won or lost) revives everyone free.
	var c2 := _campaign()
	c2.enter(_find(c2, "combat"))
	c2.finish_combat({"outcome": "Victory", "xp": 0, "gold": 0, "loot": [], "deaths": ["vera"],
		"kills": []})
	check(c2.party.get_member("vera").dead, "vera died mid-run")
	c2.stage = Campaign.STAGES.size() - 1
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
	c.stage = 1
	c.enter(_find(c, "rest"))
	var ch = c.party.party_characters()[0]
	ch.hp_current = 1
	var used: Array[int] = [1]
	ch.slots_used = used
	c.rest("long-rest")
	check(ch.hp_current == -1, "a long rest restores HP (the sheet's full-HP sentinel)")
	check(ch.slots_used.is_empty(), "a long rest restores spell slots")
	ch.hp_current = 3
	c.rest("short-rest")
	check(ch.hp_current == 3, "a short rest does not heal to full")

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
	var uncommon := Campaign.item_price("adamantine-armor")
	var rare := Campaign.item_price("scroll-of-resurrection")
	var very_rare := Campaign.item_price("ammunition-of-slaying")
	var legendary := Campaign.item_price("apparatus-of-the-crab")
	check(uncommon >= 100 and uncommon <= 300, "uncommon lands in 100-300 gp (got %d)" % uncommon)
	check(rare >= 1000 and rare <= 5000, "rare lands in 1000-5000 gp (got %d)" % rare)
	check(very_rare >= 10000 and very_rare <= 30000, "very-rare lands in 10k-30k (got %d)" % very_rare)
	check(legendary >= 50000, "legendary is 50k+ (got %d)" % legendary)
	check(uncommon < rare and rare < very_rare and very_rare < legendary, "the tiers are ordered")
	check(Campaign.item_price("no-such-item") == 0, "an unknown item has no price")

	# The scroll is stocked at some merchants and buyable there.
	var scrolls := 0
	for s in Campaign.STAGES:
		for n in s:
			if n["kind"] != "merchant":
				continue
			var m := Campaign.new(c.party)
			m.node = n
			if Campaign.SCROLL in m.stock_ids():
				scrolls += 1
				m.party.add_gold(rare)
				check(m.buy(Campaign.SCROLL), "the scroll can be bought where it is stocked")
				check(m.party.stash_count(Campaign.SCROLL) == 1, "and lands in the stash")
	check(scrolls > 0, "at least one merchant on the route stocks the scroll")

func test_quest_flow() -> void:
	var c := _campaign()
	c.enter(_find(c, "combat"))
	check(c.offer().is_empty(), "combat nodes offer no quests")
	var c2 := _campaign()
	c2.enter(_find(c2, "merchant"))
	var q := c2.offer()
	check(not q.is_empty(), "the merchant offers a quest")
	check(c2.accept(q), "accept at the merchant")
	check(c2.party.quests.size() == 1, "the quest is in the party log")
	check(not c2.turn_in(q), "cannot turn in an unfinished quest")
	q["progress"] = int(q["required"])
	q["state"] = "complete"
	var gold: int = c2.party.gold
	check(c2.turn_in(q), "turn in at the merchant")
	check(c2.party.gold > gold, "the reward is paid")

# The whole loop, model-only: walk every stage taking the first node, faking each fight.
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
	check(stages == Campaign.STAGES.size(), "every stage was walked once")
	check(c.xp > 0 and c.party.gold > 0, "the run banked xp and gold")
	check(c.log.size() >= stages, "the run journal recorded each node")

# --- helpers --------------------------------------------------------------

func _find(c: Campaign, kind: String) -> int:
	var opts := c.options()
	for i in opts.size():
		if opts[i]["kind"] == kind:
			return i
	check(false, "stage %d has no %s node" % [c.stage, kind])
	return 0

func _count(spec: Dictionary, id: String) -> int:
	for e in spec["monsters"]:
		if e["id"] == id:
			return int(e["count"])
	return 0
