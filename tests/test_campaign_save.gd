# T10 autosave — one rolling slot, written by every state-mutating Campaign method.
#   godot --headless --path . -s tests/test_campaign_save.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _campaign() -> Campaign:
	var p := Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.add_gold(120)
	return Campaign.new(p, 99)

func _init() -> void:
	CampaignSave.clear()
	check(CampaignSave.load_latest() == null, "no autosave, no campaign")

	# Walking a merchant node writes the slot at every step.
	var c := _campaign()
	c.enter(_find(c, "merchant"))
	check(CampaignSave.has_save(), "entering a node autosaves")
	c.party.get_member("vera").xp = 450
	c.party.get_member("pike").dead = true
	c.party.bench("pike")
	c.buy("longsword")
	c.party.stash_add("potion-of-healing", 2)
	c.accept(c.offer())          # the last mutating call is what the slot holds

	var back = CampaignSave.load_latest()
	check(back != null, "the autosave loads back")
	if back == null:
		_done()
	check(back.stage == c.stage and back.state == c.state, "stage and state survive")
	check(back.node.get("id", "") == c.node["id"], "the node you were standing on survives")
	check(back.xp == c.xp, "the run's XP total survives")
	check(back.rng.seed_value == c.rng.seed_value, "the run seed survives")
	check(back.log == c.log, "the journal survives")
	check(back.party.gold == c.party.gold, "gold survives")
	check(back.party.roster.size() == c.party.roster.size(), "the whole roster survives")
	check(back.party.active == c.party.active, "the active party and its order survive")
	check(back.party.stash_count("longsword") == 1
		and back.party.stash_count("potion-of-healing") == 2, "the stash survives")
	check(back.party.quests.size() == 1
		and back.party.quests[0]["id"] == c.party.quests[0]["id"], "the quest log survives")
	check(int(back.party.quests[0]["required"]) == int(c.party.quests[0]["required"]),
		"quest counters come back as ints, not floats")
	check(int(back.party.get_member("vera").xp) == 450, "per-character XP survives")
	check(back.party.get_member("pike").dead, "death survives")
	check(back.party.get_member("vera").sheet().ac == c.party.get_member("vera").sheet().ac,
		"a reloaded character still resolves to the same sheet")

	# It really is one rolling slot.
	c.leave()
	var second = CampaignSave.load_latest()
	check(second.stage == c.stage and second.stage != back.stage, "the slot is overwritten")

	# A corrupt or missing file is "no autosave", never a crash.
	var f := FileAccess.open(CampaignSave.PATH, FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	check(CampaignSave.load_latest() == null, "a corrupt autosave loads as null")
	f = FileAccess.open(CampaignSave.PATH, FileAccess.WRITE)
	f.store_string('{"format": "something-else"}')
	f.close()
	check(CampaignSave.load_latest() == null, "a foreign file loads as null")
	CampaignSave.clear()
	check(not CampaignSave.has_save() and CampaignSave.load_latest() == null, "clear() empties the slot")

	# A resumed run keeps playing.
	var c2 := _campaign()
	c2.enter(_find(c2, "combat"))
	var resumed = CampaignSave.load_latest()
	check(resumed.state == "combat", "a run saved mid-fight resumes in combat")
	resumed.finish_combat({"outcome": "Victory", "xp": 200, "gold": 30, "loot": [],
		"deaths": [], "kills": []})
	resumed.leave()
	check(resumed.stage == c2.stage + 1 and resumed.state == "picking", "and carries on down the road")

	# The screen's own Continue-vs-New-Game choice is driven by tests/drive_campaign.gd
	# ("Begin a new run") — instantiating campaign.tscn from a -s script hangs headless.
	CampaignSave.clear()
	_done()

func _done() -> void:
	print("test_campaign_save: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# T12: the route is generated per seed — walk forward to the first stage that
# offers this kind. "merchant" seeks a quest-giving one, the test accepts a quest.
func _find(c: Campaign, kind: String) -> int:
	while c.stage < c.route.size():
		var opts := c.options()
		for i in opts.size():
			if opts[i]["kind"] != kind:
				continue
			if kind != "merchant" or opts[i]["id"] in Campaign.GIVER_IDS:
				return i
		c.stage += 1
	check(false, "the route has no %s node" % kind)
	c.stage = 0
	return 0
