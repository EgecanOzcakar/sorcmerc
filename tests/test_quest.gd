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
	test_the_kinds_that_count_no_bodies()
	test_rescue_and_failed_delivery()
	test_the_ladder()
	test_map_marks()
	print("test_quest: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# D7: three kinds whose progress has nothing to do with a fight. What is checked
# here is that they coexist with the ones that do — a log holding a supply order
# used to be a log where every kill asked it for a monster id it has never had.
# (Placement — who posts them and where — is tests/test_quest_posting.gd.)
func test_the_kinds_that_count_no_bodies() -> void:
	var p := _party()
	Quest.accept(p, {"id": "smith-order", "kind": "supply_item", "target_item_id": "handaxe",
		"title": "Smith's order: 2 Handaxes", "required": 2, "progress": 0,
		"state": "offered", "reward": {"gold": 40}})
	Quest.accept(p, {"id": "crate", "kind": "deliver_goods", "target_settlement_id": "oakford",
		"title": "Run a crate to Oakford", "required": 1, "progress": 0,
		"state": "offered", "reward": {"gold": 60}})
	Quest.accept(p, {"id": "look-out", "kind": "scout_region", "target_region_id": "marches",
		"title": "Ride out into the Marches", "required": 1, "progress": 0,
		"state": "offered", "reward": {"gold": 90}})
	var kills := Quest.record_kills(p, ["snik", "vess", "grull"], RNG.new(3))
	check(kills.is_empty(), "a fight moves none of them, and does not throw asking")
	check(Quest.bias(p).is_empty(), "...and none of them biases a roster")

	Quest.record_settlement_visited(p, "greenmarch")
	check(Quest.get_quest(p, "crate")["state"] == "active", "the wrong town is not the delivery")
	Quest.record_settlement_visited(p, "oakford")
	check(Quest.get_quest(p, "crate")["state"] == "complete", "the right one is")

	Quest.record_region_reached(p, "heartland")
	check(Quest.get_quest(p, "look-out")["state"] == "active", "home is not the frontier")
	Quest.record_region_reached(p, "marches")
	check(Quest.get_quest(p, "look-out")["state"] == "complete", "the band they were sent to is")

	var order := Quest.get_quest(p, "smith-order")
	p.stash_add("handaxe", 2)
	Quest.record_stash(p)
	check(order["state"] == "complete", "goods in the pack complete a supply order")
	var gold := p.gold
	check(Quest.turn_in(p, order), "it turns in")
	check(p.gold == gold + 40 and p.stash_count("handaxe") == 0,
		"...paying for the goods and taking them")

func test_catalog() -> void:
	check(Quest.CURATED.size() >= 3, "3+ curated quests")
	for kind in Quest.KINDS:
		check(Quest.TARGET_FIELD.has(kind), "%s names the field it targets through" % kind)
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

	# Ears sold at a stall (or lost to a wiped delve) are not in hand: the job
	# is not paid for them. turn_in() used to pay in full and then fail to
	# take them, which is gold for nothing.
	var p3 := _party()
	var q3 := Quest.fresh("goblin-ears")
	Quest.accept(p3, q3)
	for i in 40:
		Quest.record_kills(p3, ["snik"], RNG.new(i + 1))
	check(q3["state"] == "complete", "five ears, the job is done")
	p3.stash_remove("goblin-ear", 2)
	var gold3: int = p3.gold
	check(not Quest.can_turn_in(q3, p3), "three ears in the pack: no turn-in offered")
	check(not Quest.turn_in(p3, q3) and p3.gold == gold3, "...and none paid for")
	Quest.record_stash(p3)
	check(int(q3["progress"]) == 3 and q3["state"] == "active", "the pack pulls the tally back to 3/5, active")
	p3.stash_add("goblin-ear", 5)
	Quest.record_stash(p3)
	check(int(q3["progress"]) == 3, "but a collected tally is what bodies dropped: buying ears does not fill it")

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

func test_rescue_and_failed_delivery() -> void:
	check(Quest.KINDS.has("rescue") and Quest.TARGET_FIELD["rescue"] == "target_lair_id", "rescue is a kind that names a lair")
	var p := _party()
	Quest.accept(p, {"id": "rescue:t:warren", "kind": "rescue", "state": "offered", "target_lair_id": "warren",
		"required": 1, "progress": 0, "title": "Bring back the miller's boy from the warren", "reward": {"gold": 90}})
	Quest.record_rescued(p, "other-lair")
	check(Quest.get_quest(p, "rescue:t:warren")["state"] == "active", "a rescue elsewhere is not this one")
	Quest.record_rescued(p, "warren")
	check(Quest.get_quest(p, "rescue:t:warren")["state"] == "complete", "the captive out of that lair completes the job")

	Quest.accept(p, {"id": "deliver:a:b", "kind": "deliver_goods", "state": "offered", "target_settlement_id": "b",
		"required": 1, "progress": 0, "title": "Run a crate of goods to B", "reward": {"gold": 40}})
	Quest.accept(p, {"id": "look-out-2", "kind": "scout_region", "state": "offered", "target_region_id": "deeps",
		"required": 1, "progress": 0, "title": "Scout", "reward": {"gold": 60}})
	var lost: Array = Quest.fail_deliveries(p)
	check(lost == ["Run a crate of goods to B"], "the delivery is the one that fails: %s" % str(lost))
	check(Quest.get_quest(p, "deliver:a:b").is_empty(), "...and it is gone from the log, so the board can post it again")
	check(Quest.get_quest(p, "look-out-2")["state"] == "active", "the scouting job is untouched")
	check(Quest.fail_deliveries(p) == [], "nothing to fail twice")

# the ladder: Known passes a neighbour's job at neutral opinion; turn-in is a deed
func test_the_ladder() -> void:
	var Ladder = load("res://core/ladder.gd")
	Ladder.reset()
	var pk := _party()
	var own: Dictionary = Quest.offer_for(pk, "wayside-camp", 0.0)
	check(not own.is_empty(), "the giver's own job first")
	Quest.accept(pk, own)
	# wayside-camp has two curated jobs of its own — take both before it goes quiet
	var next := Quest.offer_for(pk, "wayside-camp", 0.0)
	while not next.is_empty():
		Quest.accept(pk, next)
		next = Quest.offer_for(pk, "wayside-camp", 0.0)
	check(Quest.offer_for(pk, "wayside-camp", 0.0).is_empty(), "own jobs taken, neutral, stranger: nothing more")
	var neighbour := Quest.offer_for(pk, "wayside-camp", 0.0, Ladder.KNOWN)
	check(neighbour.get("id", "") == "kritch-bounty", "...but Known gets a neighbour's")
	var before: int = Ladder.deeds("human")
	own["progress"] = own["required"]
	if own["kind"] in ["collect_item", "supply_item"]:
		pk.stash_add(String(own["target_item_id"]), int(own["required"]))   # paid for goods in hand only
	Quest.turn_in(pk, own, "human")
	check(Ladder.deeds("human") == before + 1, "a job turned in is a deed for the taker's people")
	Quest.turn_in(pk, own, "human")
	check(Ladder.deeds("human") == before + 1, "...once")

# #153: an open job points at what it names on the map, under the map's own
# fog rules; a done one points back at the town that pays; a job that names
# nothing standing on the map has no mark.
func test_map_marks() -> void:
	var World = load("res://core/world.gd")
	var w = World.new()
	w.add_settlement(World.Settlement.new("home", Vector2(0, 0), "human", "town"))
	w.add_settlement(World.Settlement.new("far", Vector2(900, 0), "orc", "town"))
	var lair = w.add_lair(World.Lair.new("warren", Vector2(300, 300), "goblinoid"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var band = w.add_party(World.RoamingParty.new("goblins-s", Vector2(2000, 2000), "goblinoid"))
	var p := Party.new()
	var job := func(id: String, kind: String, field: String, target: String) -> Dictionary:
		return {"id": id, "kind": kind, field: target, "giver_node_id": "home", "state": "offered",
			"required": 1, "progress": 0, "title": id, "reward": {"gold": 10}}
	Quest.accept(p, job.call("raid", "raid_settlement", "target_settlement_id", "far"))
	Quest.accept(p, job.call("clear", "clear_lair", "target_lair_id", "warren"))
	Quest.accept(p, job.call("hunt", "hunt_party", "target_party_id", "goblins-s"))
	Quest.accept(p, job.call("ears", "collect_item", "target_monster_id", "snik"))
	var kinds := func() -> Array: return Quest.map_marks(w, p).map(func(m): return m["kind"])
	check(kinds.call() == ["raid_settlement"], "a town is always pointed at; a hidden lair and an unseen band are not: %s" % str(kinds.call()))
	lair.discovered = true
	w.reveal(band.position)
	var marks: Array = Quest.map_marks(w, p)
	check(marks.size() == 3 and not marks.any(func(m): return m["done"]), "found and seen, the lair and the band are pointed at")
	check(marks.any(func(m): return m["kind"] == "clear_lair" and m["pos"] == Vector2(300, 300)), "...the lair where it is")
	check(marks.any(func(m): return m["kind"] == "hunt_party" and m["pos"] == band.position), "...the band where it was seen")
	Quest.record_lair_cleared(p, "warren")
	marks = Quest.map_marks(w, p)
	var done: Array = marks.filter(func(m): return m["done"])
	check(done.size() == 1 and done[0]["kind"] == "clear_lair" and done[0]["pos"] == Vector2.ZERO,
		"done, the job points at the town that pays")
