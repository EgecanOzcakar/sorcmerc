# T10 autosave — one rolling slot, written by every state-mutating Campaign method.
#   godot --headless --path . -s tests/test_campaign_save.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
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
	# O17: this process's own autosave slots, so a concurrent godot run cannot
	# clobber them. randi() as well as the pid: under a sandboxed (flatpak)
	# godot every process sees pid 3, so the pid alone is not unique.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
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
	c.party.stash_add("potions-of-healing", 2)
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
		and back.party.stash_count("potions-of-healing") == 2, "the stash survives")
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
	var f := FileAccess.open(CampaignSave.path(), FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	check(CampaignSave.load_latest() == null, "a corrupt autosave loads as null")
	f = FileAccess.open(CampaignSave.path(), FileAccess.WRITE)
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

	# Task 1: relations ride the campaign save the same way the roster does.
	var cr := _campaign()
	PartyOpinion.set_score(cr.party, "vera", "pike", 33.0)
	var rd: Dictionary = CampaignSave.to_dict(cr)
	check(float(rd["party"].get("relations", {}).get(PartyOpinion.key("vera", "pike"), {}).get("score", 0.0)) == 33.0,
		"a relation rides the campaign save's party dict")
	var cr_back = CampaignSave.from_dict(rd)
	check(PartyOpinion.score(cr_back.party, "vera", "pike") == 33.0, "...and reads back through the model")
	rd["party"].erase("relations")
	var cr_old = CampaignSave.from_dict(rd)
	check(cr_old.party.relations.is_empty(), "an old campaign save with no relations loads with none")

	# Task 4: callings ride beside them.
	cr.party.callings["vera"] = {"id": "acolyte", "target_kind": "landmark", "target_id": "shrine-1", "state": "told", "told_at": 42.0}
	rd = CampaignSave.to_dict(cr)
	check(rd["party"].get("callings", {}).get("vera", {}).get("state", "") == "told", "a calling rides the campaign save's party dict")
	check(CampaignSave.from_dict(rd).party.callings.get("vera", {}).get("target_id", "") == "shrine-1", "...and reads back")
	check(cr_old.party.callings.is_empty(), "an old campaign save with no callings loads with none")

	# Downtime rides there too.
	cr.party.downtime = {"trained": ["vera"], "pit": {"riverhold": {"week": 3, "beaten": 1}}}
	rd = CampaignSave.to_dict(cr)
	check(rd["party"].get("downtime", {}).get("trained", []) == ["vera"], "downtime rides the campaign save's party dict")
	check(CampaignSave.from_dict(rd).party.downtime.get("trained", []) == ["vera"], "...and reads back")
	check(cr_old.party.downtime.is_empty(), "an old campaign save with no downtime loads with none")

	# The lodge rides there too.
	cr.party.lodge = {"settlement_id": "riverhold", "rooms": ["strongroom"], "gold": 250, "garden_at": -1.0, "maproom_at": -1.0, "retrained": {}, "blessed_at": -1.0}
	rd = CampaignSave.to_dict(cr)
	check(rd["party"].get("lodge", {}).get("gold", 0) == 250, "the lodge rides the campaign save's party dict")
	check(CampaignSave.from_dict(rd).party.lodge.get("rooms", []) == ["strongroom"], "...and reads back")
	check(cr_old.party.lodge.is_empty(), "an old campaign save with no lodge loads with none")

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
			if kind != "merchant" or Campaign.has_service(opts[i], "innkeeper"):
				return i
		c.stage += 1
	check(false, "the route has no %s node" % kind)
	c.stage = 0
	return 0
