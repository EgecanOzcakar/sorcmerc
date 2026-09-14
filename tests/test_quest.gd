# T9 quests — accept / progress / turn-in for both kinds, and the spawn bias
# actually changing Scaler.roster_for's output.
#   godot --headless --path . -s tests/test_quest.gd
extends SceneTree

const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _init() -> void:
	test_catalog()
	test_offer_accept()
	test_opinion_gates_offers()
	test_turn_in_raises_the_faction()
	test_kill_count()
	test_collect_item()
	test_bias()
	print("test_quest: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_catalog() -> void:
	check(Quest.CURATED.size() >= 3, "3+ curated quests")
	for q in Quest.CURATED:
		check(q["kind"] in ["kill_count", "collect_item"], "%s has a known kind" % q["id"])
		check(int(q["required"]) > 0, "%s requires something" % q["id"])
		check(int(q["reward"].get("gold", 0)) > 0, "%s pays" % q["id"])
		if q["kind"] == "collect_item":
			check(q.has("target_item_id") and q.has("drop_chance"), "%s drops an item" % q["id"])
	check(Quest.fresh("goblin-ears")["state"] == "offered", "a fresh quest is offered")
	check(Quest.fresh("goblin-ears")["progress"] == 0, "a fresh quest is at 0")
	check(Quest.fresh("nope").is_empty(), "unknown quest id is empty")

func test_offer_accept() -> void:
	var p := _party()
	var q := Quest.offer_for(p, "wayside-camp")
	check(q["giver_node_id"] == "wayside-camp", "the giver offers its own quest")
	check(Quest.offer_for(p, "nowhere").is_empty(), "a node with no quests offers nothing")
	check(Quest.accept(p, q), "accept")
	check(p.quests.size() == 1 and p.quests[0]["state"] == "active", "the log holds one active quest")
	check(not Quest.accept(p, Quest.fresh(q["id"])), "the same quest cannot be taken twice")
	var q2 := Quest.offer_for(p, "wayside-camp")
	check(q2["id"] != q["id"], "the giver moves on to its next quest")
	check(Quest.active(p).size() == 1, "active() lists only what is in the log")

func test_kill_count() -> void:
	var p := _party()
	var q := Quest.fresh("road-clearing")   # 3 x vess
	Quest.accept(p, q)
	var rng = RNG.new(7)
	Quest.record_kills(p, ["snik", "snik"], rng)
	check(q["progress"] == 0, "unrelated kills do not count")
	Quest.record_kills(p, ["vess", "snik"], rng)
	check(q["progress"] == 1, "one matching kill counts once")
	check(not Quest.can_turn_in(q), "not turn-innable while short")
	var lines := Quest.record_kills(p, ["vess", "vess", "vess"], rng)
	check(q["progress"] == 3, "progress caps at required")
	check(q["state"] == "complete", "fulfilled quest goes complete")
	check(lines.size() >= 1, "progress is logged")
	check(Quest.can_turn_in(q), "turn-innable now")

	var gold := p.gold
	check(Quest.turn_in(p, q), "turn in")
	check(p.gold == gold + 75, "the gold reward is paid")
	check(p.stash_count("shortsword") == 1, "the item reward lands in the stash")
	check(q["state"] == "turned_in", "state is turned_in")
	check(not Quest.turn_in(p, q), "cannot turn in twice")
	check(Quest.active(p).is_empty(), "a turned-in quest leaves the active list")

func test_collect_item() -> void:
	# 5 ears at a 50% drop: progress is items, not kills. Probabilistic, so the
	# assertion is over 200 seeds, not one.
	var totals := 0
	var completed := 0
	for s in range(1, 201):
		var p := _party()
		var q := Quest.fresh("goblin-ears")
		Quest.accept(p, q)
		Quest.record_kills(p, ["snik", "snik", "snik", "snik"], RNG.new(s))
		check(q["progress"] <= 4, "seed %d: never more items than kills" % s)
		check(p.stash_count("goblin-ear") == q["progress"], "seed %d: stash tracks progress" % s)
		totals += q["progress"]
		if q["progress"] >= 4:
			completed += 1
	var rate := float(totals) / (200.0 * 4.0)
	check(rate > 0.4 and rate < 0.6, "the 50%% drop lands near 50%% over 200 seeds (got %.2f)" % rate)
	check(completed > 0 and completed < 200, "some runs drop 4/4, most do not (%d/200)" % completed)

	# Turning a collect quest in consumes the items.
	var p2 := _party()
	var q2 := Quest.fresh("goblin-ears")
	Quest.accept(p2, q2)
	for i in 40:
		Quest.record_kills(p2, ["snik"], RNG.new(i + 1))
	check(q2["progress"] == 5, "40 goblins is enough for 5 ears")
	check(Quest.turn_in(p2, q2), "collect quest turns in")
	check(p2.stash_count("goblin-ear") == 0, "the ears are handed over")

func test_bias() -> void:
	var p := _party()
	check(Quest.bias(p).is_empty(), "no quests, no bias")
	var q := Quest.fresh("kritch-bounty")   # 4 x kritch
	Quest.accept(p, q)
	check(Quest.bias(p) == {"kritch": Quest.BIAS_WEIGHT}, "an active quest biases its target")

	# THE PROOF: the same party at the same difficulty fields more kritch with the
	# quest than without it.
	var chars := p.party_characters()
	var plain := _count(Scaler.roster_for(chars, "normal"), "kritch")
	var biased := _count(Scaler.roster_for(chars, "normal", Quest.bias(p)), "kritch")
	check(biased > plain, "quest bias adds kritch to the roster (%d -> %d)" % [plain, biased])

	q["progress"] = int(q["required"])
	q["state"] = "complete"
	check(Quest.bias(p).is_empty(), "a fulfilled quest stops biasing")
	# T91/M4: a quest whose target is a place or a band, not a monster. There is
	# nothing to bias a roster toward, and asking it for a monster id threw.
	Quest.accept(p, {"id": "lair-job", "kind": "clear_lair", "target_lair_id": "warren",
		"title": "Clear the warren", "required": 1, "progress": 0, "state": "offered",
		"reward": {"gold": 10}})
	check(Quest.bias(p).is_empty(), "a world-target quest biases nothing, and does not throw")

func _count(spec: Dictionary, id: String) -> int:
	for e in spec["monsters"]:
		if e["id"] == id:
			return int(e["count"])
	return 0

# O7: the giver's faction opinion gates what (if anything) is on offer, and a
# turn-in credited to a faction raises it.
func test_opinion_gates_offers() -> void:
	FactionOpinion.reset()
	var p := _party()
	check(Quest.offer_for(p, "wayside-camp").is_empty() == false, "neutral offers as before")
	check(Quest.offer_for(p, "wayside-camp", FactionOpinion.QUEST_MIN - 1.0).is_empty(),
		"a faction that dislikes you has no work for you")
	check(not Quest.offer_for(p, "wayside-camp", FactionOpinion.QUEST_MIN + 1.0).is_empty(),
		"just above the floor they still hire you")
	# Take both of this giver's quests: at neutral it is out of work, while a
	# faction that likes you passes you somebody else's.
	Quest.accept(p, Quest.offer_for(p, "wayside-camp"))
	Quest.accept(p, Quest.offer_for(p, "wayside-camp"))
	check(Quest.offer_for(p, "wayside-camp").is_empty(), "a tapped-out giver offers nothing")
	var extra := Quest.offer_for(p, "wayside-camp", FactionOpinion.QUEST_GENEROUS)
	check(not extra.is_empty() and extra["giver_node_id"] != "wayside-camp",
		"a faction that likes you hands over a neighbour's job")

func test_turn_in_raises_the_faction() -> void:
	FactionOpinion.reset()
	var p := _party()
	var q := Quest.fresh("road-clearing")
	Quest.accept(p, q)
	Quest.record_kills(p, ["vess", "vess", "vess"], RNG.new(1))
	check(Quest.turn_in(p, q, "soldier"), "turn in at a faction's town")
	check(FactionOpinion.get_opinion("soldier") == FactionOpinion.QUEST_DONE,
		"finishing their job raises their opinion")
	var q2 := Quest.fresh("kritch-bounty")
	Quest.accept(p, q2)
	Quest.record_kills(p, ["kritch", "kritch", "kritch", "kritch"], RNG.new(1))
	check(Quest.turn_in(p, q2), "the factionless (linear campaign) turn-in still works")
	check(FactionOpinion.get_opinion("soldier") == FactionOpinion.QUEST_DONE,
		"...and moves nobody's opinion")
	FactionOpinion.reset()
