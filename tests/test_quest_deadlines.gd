# The design audit §3.4: bounties and rescues carry a deadline, shown on the
# posting and in the log; past it an unfinished one fails and leaves the log,
# so the board can post it again. Errands and deliveries stay open-ended. An
# old save's quests have no deadline and never expire, and a content pack's
# story quest may name its own `deadline_days` (docs/modding.md).
#   godot --headless --path . -s tests/test_quest_deadlines.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Posting = preload("res://core/quest_posting.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldSave = preload("res://core/world_save.gd")
const Story = preload("res://core/mod/story.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	FactionOpinion.reset()
	test_who_gets_one()
	test_the_clock()
	test_old_saves()
	test_story_quests()
	FactionOpinion.reset()
	print("test_quest_deadlines: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The posting test's map: a city with every counter, a band and a lair near it.
func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	w.add_party(World.RoamingParty.new("raiders", Vector2(200, 200), "bandit"))
	w.add_lair(World.Lair.new("warren", Vector2(-300, 300), "goblinoid"))
	return w

func _party() -> Party:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func test_who_gets_one() -> void:
	var w := _world()
	var offers: Array = Visit.quest_offers(w.settlements[0], _party(), w)
	var kinds := {}
	for q in offers:
		kinds[String(q["kind"])] = q
	# (a rescue is posted only for a lair with pens still ahead: test_the_clock takes one by hand)
	check(kinds.has("hunt_party") and kinds.has("deliver_goods"), "fixture: the city posts a bounty and a delivery (%s)" % [kinds.keys()])
	for k in kinds:
		var q: Dictionary = kinds[k]
		if Posting.DEADLINE_DAYS.has(k):
			check(int(q.get("deadline_days", 0)) == int(Posting.DEADLINE_DAYS[k]),
				"a %s posting gives %d days" % [k, int(Posting.DEADLINE_DAYS[k])])
			check(Quest.time_left(q, 0.0) == "%d days to do it" % int(Posting.DEADLINE_DAYS[k]),
				"...and says so before it is taken: %s" % Quest.time_left(q, 0.0))
		else:
			check(not q.has("deadline_days"), "a %s job stays open-ended" % k)
	check(not Posting.DEADLINE_DAYS.has("deliver_goods") and not Posting.DEADLINE_DAYS.has("supply_item")
		and not Posting.DEADLINE_DAYS.has("scout_region"), "errands and deliveries never get one")

func test_the_clock() -> void:
	var p := _party()
	var bounty := {"id": "b1", "kind": "hunt_party", "title": "Hunt down Ribsnap's lot", "state": "offered",
		"progress": 0, "required": 1, "target_party_id": "raiders", "deadline_days": 4}
	var errand := {"id": "e1", "kind": "deliver_goods", "title": "Run a crate", "state": "offered",
		"progress": 0, "required": 1, "target_settlement_id": "greenmarch"}
	var done := {"id": "r1", "kind": "rescue", "title": "Bring back the miller's boy", "state": "offered",
		"progress": 0, "required": 1, "target_lair_id": "warren", "deadline_days": 3}
	check(Quest.accept(p, bounty, 1000.0) and float(bounty["deadline"]) == 1000.0 + 4 * Quest.DAY,
		"taking a bounty starts its clock: due four days on")
	Quest.accept(p, errand, 1000.0)
	check(not errand.has("deadline"), "an errand has none")
	Quest.accept(p, done, 1000.0)
	Quest.record_rescued(p, "warren")
	check(String(done["state"]) == "complete", "fixture: the rescue is done in time")
	check(Quest.time_left(bounty, 1000.0 + 1.5 * Quest.DAY) == "2 days left", "the log reads days left: %s" % Quest.time_left(bounty, 1000.0 + 1.5 * Quest.DAY))
	check(Quest.time_left(bounty, 1000.0 + 3.5 * Quest.DAY) == "less than a day left", "...and the last day as such")
	check(Quest.describe(bounty, 1000.0 + 1.5 * Quest.DAY).contains("(2 days left)"), "the journal line carries it: %s" % Quest.describe(bounty, 1000.0 + 1.5 * Quest.DAY))
	check(not Quest.describe(errand, 5000.0).contains("left"), "...an errand's does not")
	check(Quest.expire(p, 1000.0 + 4 * Quest.DAY).is_empty(), "on the minute it is due, nothing has failed yet")
	var gone: Array = Quest.expire(p, 1000.0 + 4 * Quest.DAY + 1.0)
	check(gone == ["Hunt down Ribsnap's lot"], "past it, the unfinished bounty fails (%s)" % [gone])
	check(Quest.get_quest(p, "b1").is_empty(), "...and leaves the log, so the board can post it again")
	check(not Quest.get_quest(p, "e1").is_empty(), "the errand is still open, days later")
	check(not Quest.get_quest(p, "r1").is_empty() and Quest.can_turn_in(done, p),
		"a job done in time keeps past its day, and can still be turned in")
	# the party's own clock stamp stands in when no minute is passed (a story beat)
	var q := _party()
	q.world_now = 300.0
	var s := {"id": "s1", "kind": "rescue", "title": "x", "state": "offered", "progress": 0, "required": 1,
		"target_lair_id": "warren", "deadline_days": 2}
	Quest.accept(q, s)
	check(float(s["deadline"]) == 300.0 + 2 * Quest.DAY, "no minute passed: the party's world_now starts the clock")

func test_old_saves() -> void:
	var p := _party()
	var old := {"id": "o1", "kind": "hunt_party", "title": "An old bounty", "state": "active",
		"progress": 0, "required": 1, "target_party_id": "raiders"}
	p.quests.append(old)
	var w := _world()
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(w, p))))
	check(Quest.expire(back["party"], 1e9).is_empty() and not Quest.get_quest(back["party"], "o1").is_empty(),
		"a quest from an old save has no deadline and never expires")
	var p2 := _party()
	var b := {"id": "b2", "kind": "hunt_party", "title": "A bounty", "state": "offered", "progress": 0,
		"required": 1, "target_party_id": "raiders", "deadline_days": 4}
	Quest.accept(p2, b, 50.0)
	var back2 = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(w, p2))))
	var q2: Dictionary = Quest.get_quest(back2["party"], "b2")
	check(float(q2.get("deadline", -1.0)) == 50.0 + 4 * Quest.DAY, "a deadline survives a save")

func test_story_quests() -> void:
	var good := {"id": "q", "title": "A job", "kind": "clear_lair", "target_lair_id": "x", "deadline_days": 5}
	var bad := {"id": "q2", "title": "A job", "kind": "clear_lair", "target_lair_id": "x", "deadline_days": 0}
	var worse := {"id": "q3", "title": "A job", "kind": "clear_lair", "target_lair_id": "x", "deadline_days": "soon"}
	var none := {"id": "q4", "title": "A job", "kind": "clear_lair", "target_lair_id": "x"}
	for pair in [[good, true], [none, true], [bad, false], [worse, false]]:
		var st = Story.new()
		st._check_quest(pair[0], "beat", {}, {})
		check(st.errors.is_empty() == pair[1], "a story quest with deadline_days %s is %s (%s)" % [
			str(pair[0].get("deadline_days", "(none)")), "fine" if pair[1] else "an error", st.errors])
