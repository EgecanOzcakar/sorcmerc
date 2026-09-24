# Contracts (core/contracts.gd): the gates that decide who hires the company,
# what their regard pays, and who a job counts for when it is handed in.
#   godot --headless --path . -s tests/test_contracts.gd
extends SceneTree

const Contracts = preload("res://core/contracts.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Party = preload("res://core/party.gd")
const Posting = preload("res://core/quest_posting.gd")
const Quest = preload("res://core/quest.gd")
const Visit = preload("res://core/settlement_visit.gd")
const World = preload("res://core/world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_gates()
	test_pay()
	test_board_stamps_the_issuer()
	test_credit_goes_to_the_issuer()
	test_old_job_credits_the_hand_in()
	test_against_a_people()
	_reset()
	print("test_contracts: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _reset() -> void:
	FactionOpinion.reset()
	Ladder.reset()

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_settlement(World.Settlement.new("ashfell", Vector2(160, 470), "orc", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_party(World.RoamingParty.new("raiders", Vector2(200, 200), "bandit"))
	w.add_lair(World.Lair.new("warren", Vector2(-300, 300), "goblinoid"))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func test_gates() -> void:
	_reset()
	check(Contracts.open("clear_lair", "human"), "a stranger may clear a lair")
	check(Contracts.open("hunt_party", "human"), "...and hunt a band, at neutral")
	check(not Contracts.open("raid_settlement", "human"), "...but war work waits until they know you")
	check(Contracts.why_closed("raid_settlement", "human").contains("Known"), "and the board says so: %s" % Contracts.why_closed("raid_settlement", "human"))
	check(Contracts.why_closed("clear_lair", "human") == "", "an open kind has no note")
	Ladder.deed("human", Ladder.RUNG_AT[Ladder.KNOWN])
	check(Contracts.open("raid_settlement", "human"), "Known: war work opens")
	FactionOpinion.set_opinion("human", -10.0)
	check(not Contracts.open("hunt_party", "human") and not Contracts.open("raid_settlement", "human"),
		"cross with you: no killing work, whatever you have done for them")
	check(Contracts.why_closed("hunt_party", "human").contains("think better"), "and the note says it is their mood")
	check(Contracts.open("deliver_goods", "human"), "carting still goes to anyone above the board's floor")
	FactionOpinion.set_opinion("human", FactionOpinion.QUEST_MIN)
	check(not Contracts.open("deliver_goods", "human"), "at the floor, nothing at all")

func test_pay() -> void:
	_reset()
	check(is_equal_approx(Contracts.pay_mult("human"), 1.0), "neutral: x1.00")
	FactionOpinion.set_opinion("human", 100.0)
	check(is_equal_approx(Contracts.pay_mult("human"), 1.0 + Contracts.STANDING_PAY), "loved: x%.2f" % (1.0 + Contracts.STANDING_PAY))
	FactionOpinion.set_opinion("human", -60.0)
	check(is_equal_approx(Contracts.pay_mult("human"), 1.0 + Contracts.STANDING_PAY * FactionOpinion.QUEST_MIN / 100.0),
		"below the board's floor it pays no less than at the floor (%.3f)" % Contracts.pay_mult("human"))
	# and it stacks with renown on the real board
	_reset()
	var w := _world()
	var p := _party()
	var s = w.settlements[0]
	var plain: Array = Visit.quest_offers(s, p, w)
	FactionOpinion.set_opinion("human", 40.0)
	var liked: Array = Visit.quest_offers(s, p, w)
	check(plain.size() == liked.size() and plain.size() > 0, "same board, liked or not")
	var never_less := true
	var some_more := false
	for i in plain.size():
		var a := int(plain[i]["reward"]["gold"])
		var b := int(liked[i]["reward"]["gold"])
		never_less = never_less and b >= a
		some_more = some_more or b > a
	check(never_less and some_more, "at +40 every job pays at least as much, and some pay more")

func test_board_stamps_the_issuer() -> void:
	_reset()
	var w := _world()
	var p := _party()
	for s in [w.settlements[0], w.settlements[1]]:
		for q in Visit.quest_offers(s, p, w):
			check(String(q.get("issuer", "")) == s.faction, "%s at %s is %s work" % [q["id"], s.id, s.faction])
	var closed: Array = Posting.closed(w.settlements[0], Visit.services(w.settlements[0]))
	check(closed.any(func(c): return c["kind"] == "raid_settlement"), "the city lists its war work as closed to a stranger")
	check(not closed.any(func(c): return c["kind"] == "clear_lair"), "...and nothing that is open")
	check(Posting.closed(w.settlements[1], Visit.services(w.settlements[1])).all(func(c): return c["kind"] != "raid_settlement"),
		"a town that never posts raids does not list them as closed")

func _done(q: Dictionary) -> Dictionary:
	q["state"] = "complete"
	q["progress"] = int(q.get("required", 1))
	return q

func test_credit_goes_to_the_issuer() -> void:
	_reset()
	var p := _party()
	var q := _done({"id": "c1", "kind": "clear_lair", "target_lair_id": "warren", "required": 1,
		"issuer": "dwarf", "against": "goblinoid", "chain_faction": "goblinoid", "reward": {"gold": 100}})
	p.quests.append(q)
	check(Quest.turn_in(p, q, "elf"), "handed in at an elven inn")
	check(is_equal_approx(FactionOpinion.get_opinion("dwarf"), FactionOpinion.QUEST_DONE), "the dwarves who posted it are pleased")
	check(Ladder.deeds("dwarf") == 1, "...and count it a deed")
	check(is_equal_approx(FactionOpinion.get_opinion("elf"), 0.0) and Ladder.deeds("elf") == 0, "the elves only held the purse")
	check(is_equal_approx(FactionOpinion.get_opinion("goblinoid"), 0.0), "a monster faction keeps no opinion to lose")

func test_old_job_credits_the_hand_in() -> void:
	_reset()
	var p := _party()
	var q := _done({"id": "c2", "kind": "clear_lair", "target_lair_id": "warren", "required": 1,
		"reward": {"gold": 50}})
	p.quests.append(q)
	check(Quest.turn_in(p, q, "elf"), "a job from before contracts is handed in")
	check(is_equal_approx(FactionOpinion.get_opinion("elf"), FactionOpinion.QUEST_DONE) and Ladder.deeds("elf") == 1,
		"...and credits the hand-in town, exactly as before")

func test_against_a_people() -> void:
	_reset()
	var p := _party()
	var q := _done({"id": "c3", "kind": "hunt_party", "target_party_id": "caravan", "required": 1,
		"issuer": "human", "against": "elf", "reward": {"gold": 80}})
	p.quests.append(q)
	Quest.turn_in(p, q, "human")
	check(FactionOpinion.get_opinion("elf") < 0.0, "a job against the elves costs you with the elves (%.1f)" % FactionOpinion.get_opinion("elf"))
	check(FactionOpinion.get_opinion("human") > 0.0, "...and pleases the humans who paid for it")
