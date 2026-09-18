# Achievements model round-trip + the viewer standing up on its own.
#   godot --headless --path . -s tests/test_achievements.gd
extends SceneTree

const Ach = preload("res://core/achievements.gd")
const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Encounter = preload("res://core/encounter.gd")
const Combat = preload("res://core/combat.gd")
const Leveling = preload("res://core/leveling.gd")
const RNG = preload("res://core/rng.gd")
const Encounter2 = preload("res://core/encounter.gd")
const Travel = preload("res://core/travel.gd")
const Site = preload("res://core/site.gd")
const Visit = preload("res://core/settlement_visit.gd")
const Quest = preload("res://core/quest.gd")
const Regions = preload("res://core/regions.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Progression = preload("res://core/progression.gd")
const CharacterSave = preload("res://core/character_save.gd")

const VERY_RARE := "amulet-of-the-planes"
const MYSTERY := "cloak-of-elvenkind"

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	_wipe()
	test_defs()
	test_unlock()
	test_round_trip()
	test_all()
	_wipe()
	test_counters()
	test_tally_round_trip()
	test_toast_queue()
	test_groups()
	test_completionist()
	test_goals_match_their_sources()
	test_goals_are_reachable()
	_wipe()
	test_combat_wiring()
	test_campaign_wiring()
	test_leveling_wiring()
	test_party_wiring()
	test_roll_scoring()
	test_kill_scoring()
	test_untracked_fights_score_nothing()
	test_fight_scoring()
	test_identify_tally()
	test_gold_wiring()
	test_multiclass_wiring()
	test_veteran_wiring()
	test_granted_survives_a_save()
	test_relationship_wiring()
	test_world_wiring()
	await test_viewer()
	_wipe()
	print("test_achievements: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()
	Ach.take_toasts()

func test_defs() -> void:
	check(Ach.DEFS.size() >= 100, "a real list of achievements")
	var ids := {}
	var ok := true
	for d in Ach.DEFS:
		if ids.has(d["id"]) or String(d["id"]).is_empty():
			ok = false
		ids[d["id"]] = true
		check(not String(d["title"]).is_empty(), "%s has a title" % d["id"])
		check(not String(d["desc"]).is_empty(), "%s has a description" % d["id"])
	check(ok, "every id is unique and non-empty")

func test_unlock() -> void:
	check(not Ach.is_unlocked("first_victory"), "starts locked")
	check(Ach.unlocked_at("first_victory") == "", "locked has no timestamp")
	check(Ach.unlock("first_victory"), "first unlock is new")
	var at := Ach.unlocked_at("first_victory")
	check(at != "", "unlocking stamps a time")
	check(not Ach.unlock("first_victory"), "second unlock reports not-new")
	check(Ach.unlocked_at("first_victory") == at, "timestamp does not move")
	check(not Ach.unlock("no_such_achievement"), "unknown id is a no-op")

func test_round_trip() -> void:
	Ach.unlock("level_5")
	var at := Ach.unlocked_at("level_5")
	var back = Ach.load_state()
	check(back.unlocked.has("first_victory"), "unlock survives a reload")
	check(back.unlocked.get("level_5") == at, "timestamp survives a reload")
	check(not back.unlocked.has("level_20"), "untouched ones stay locked")

	# Garbage in the file falls back to an empty, unlocked-nothing state.
	var f := FileAccess.open(Ach.PATH, FileAccess.WRITE)
	f.store_string('{"format":"nope","unlocked":{"level_20":"whenever"}}')
	f.close()
	check(Ach.load_state().unlocked.is_empty(), "unknown format falls back to defaults")
	# Unknown ids in a good file are dropped rather than shown.
	f = FileAccess.open(Ach.PATH, FileAccess.WRITE)
	f.store_string('{"format":"%s","unlocked":{"gone_from_the_list":"x","level_5":"%s"}}' % [Ach.FORMAT, at])
	f.close()
	var pruned = Ach.load_state()
	check(pruned.unlocked.size() == 1 and pruned.unlocked.has("level_5"), "retired ids are dropped on load")
	Ach._current = pruned

func test_all() -> void:
	var rows = Ach.all()
	check(rows.size() == Ach.DEFS.size(), "all() lists every achievement")
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = r
	check(by_id["level_5"]["unlocked"] and by_id["level_5"]["at"] != "", "all() shows unlocked state")
	check(not by_id["level_20"]["unlocked"] and by_id["level_20"]["at"] == "", "all() shows locked state")
	check(rows[0]["id"] == Ach.DEFS[0]["id"], "all() keeps display order")

# --- the wiring (the unlock call sites in real gameplay) ------------------

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _campaign() -> Campaign:
	return Campaign.new(_party(), 99)

func _victory(extra := {}) -> Dictionary:
	var r := {"outcome": "Victory", "xp": 10, "gold": 0, "loot": [], "deaths": [],
		"kills": [], "downed": []}
	r.merge(extra, true)
	return r

# A hero dropped to 0 and brought back: combat.gd's death-save wiring.
func test_combat_wiring() -> void:
	var cb = Combat.new(RNG.new(7), Encounter.party() + Encounter.monsters(), Encounter.board())
	var hero = cb.team_of("party")[0]
	cb._apply_damage(hero, hero.hp + 1)
	check(hero.is_down(), "the hero is down, not dead")
	check(cb.downed.has(hero.id), "combat records who hit 0 HP")
	check(not Ach.is_unlocked("death_save"), "still unconscious: nothing earned yet")
	cb.heal(hero, 5)
	check(Ach.is_unlocked("death_save"), "surviving being downed unlocks death_save")
	check(hero.id in Encounter.resolve_outcome(cb, [])["downed"],
		"resolve_outcome carries downed back to the campaign")

	# Stabilising on death saves counts too, without any healing.
	_wipe()
	var cb2 = Combat.new(RNG.new(7), Encounter.party() + Encounter.monsters(), Encounter.board())
	var h2 = cb2.team_of("party")[0]
	cb2._apply_damage(h2, h2.hp + 1)
	check(not Ach.is_unlocked("death_save"), "going down alone earns nothing")
	for _i in 10:                     # one success away each time: no death, no infinite loop
		if h2.statuses.has("stable") or h2.hp > 0:
			break
		h2.death_s = 2
		h2.death_f = 0
		cb2._death_save(h2)
	check(h2.statuses.has("stable") or h2.hp > 0, "the hero stabilised (or snapped awake on a nat 20)")
	check(Ach.is_unlocked("death_save"), "surviving the death saves unlocks it without any healing")

func test_campaign_wiring() -> void:
	_wipe()
	# A hard fight somebody was downed in is a win, but not a flawless one.
	var c := _campaign()
	c.node = {"kind": "combat", "id": "x", "difficulty": "hard"}
	c.state = "combat"
	c.finish_combat(_victory({"downed": ["vera"]}))
	check(Ach.is_unlocked("first_victory"), "winning a fight unlocks first_victory")
	check(not Ach.is_unlocked("hard_flawless"), "a hero went down: not flawless")

	# Clean, on hard, with a very rare drop in the loot.
	var c2 := _campaign()
	c2.node = {"kind": "combat", "id": "y", "difficulty": "hard"}
	c2.state = "combat"
	c2.finish_combat(_victory({"loot": [VERY_RARE]}))
	check(Ach.is_unlocked("hard_flawless"), "a clean hard win unlocks hard_flawless")
	check(Ach.is_unlocked("loot_very_rare"), "a very rare drop unlocks loot_very_rare")

	# An easy fight, however clean, is not the flawless one.
	_wipe()
	var c3 := _campaign()
	c3.node = {"kind": "combat", "id": "z", "difficulty": "easy"}
	c3.state = "combat"
	c3.finish_combat(_victory())
	check(not Ach.is_unlocked("hard_flawless"), "easy difficulty never earns hard_flawless")

	# Treasure: a magic item out of a hoard is loot too.
	_wipe()
	var c4 := _campaign()
	c4.node = {"kind": "treasure", "id": "hoard", "gold": 0, "item_id": VERY_RARE}
	c4._take_treasure()
	check(Ach.is_unlocked("loot_very_rare"), "a very rare item in a hoard unlocks loot_very_rare")

	# Identification, both routes.
	_wipe()
	var c5 := _campaign()
	c5.node = {"kind": "merchant", "id": "hollow-market"}
	c5.state = "visiting"
	c5.party.stash_add(MYSTERY, 1, false)
	c5.party.stash_add(Campaign.IDENTIFY_SCROLL)
	check(c5.identify_with_scroll(MYSTERY), "the scroll identifies it")
	check(Ach.is_unlocked("identify_item"), "identifying with a scroll unlocks identify_item")

	# Spending: BIG_SPENDER_GP gp across one run's merchants.
	check(not Ach.is_unlocked("big_spender"), "no purchases yet")
	c5.party.add_gold(5000)
	while c5.spent < Campaign.BIG_SPENDER_GP:
		check(c5.buy("longsword"), "the merchant sells")
	check(Ach.is_unlocked("big_spender"), "%d gp of shopping unlocks big_spender" % Campaign.BIG_SPENDER_GP)

	# Finishing the road, and walking away from it.
	_wipe()
	var c6 := _campaign()
	c6.stage = c6.route.size() - 1
	c6.state = "visiting"
	c6.leave()
	check(c6.state == "won" and Ach.is_unlocked("campaign_clear"), "winning a run unlocks campaign_clear")
	check(not Ach.is_unlocked("retire_run"), "a win is not a retirement")
	var c7 := _campaign()
	check(c7.retire() and Ach.is_unlocked("retire_run"), "retiring unlocks retire_run")

func test_leveling_wiring() -> void:
	_wipe()
	var ch = Presets.party()[2]      # Ilsa, the cleric
	check(not Ach.is_unlocked("level_5"), "nobody is level 5 yet")
	while ch.level() < 5:
		Leveling.add_level(ch)
	check(Ach.is_unlocked("level_5"), "reaching level 5 unlocks level_5")
	check(not Ach.is_unlocked("level_20"), "level 5 is not level 20")
	check(not Ach.is_unlocked("spell_5th"), "no 5th-level spell at level 5")
	while ch.level() < Leveling.MAX_LEVEL:
		Leveling.add_level(ch)
	check(Ach.is_unlocked("level_20"), "reaching the cap unlocks level_20")
	check(Ach.is_unlocked("spell_5th"),
		"a prepared caster's 5th-level domain spells unlock spell_5th")

	# A preview is not a level-up: it must not unlock anything.
	_wipe()
	var probe = Presets.party()[0]
	while probe.level() < 4:
		probe.add_level(probe.class_id(), Leveling.AVERAGE)   # straight to the character, no milestones
	Leveling.preview(probe)
	check(not Ach.is_unlocked("level_5"), "previewing level 5 does not unlock it")

func test_party_wiring() -> void:
	_wipe()
	var p := _party()
	p.get_member("vera").dead = true
	p.add_gold(Party.REVIVE_COST)
	p.stash_add(Party.REVIVE_SCROLL)
	check(not Ach.is_unlocked("resurrect_ally"), "nobody raised yet")
	check(Party.resurrect(p, "vera", "scroll"), "the scroll works")
	check(Ach.is_unlocked("resurrect_ally"), "raising the dead unlocks resurrect_ally")

func test_viewer() -> void:
	var v = load("res://scenes/achievements/achievements.tscn").instantiate()
	root.add_child(v)
	await process_frame
	check(v.get_child_count() > 0, "viewer builds its UI standalone")
	v.queue_free()


# --- the tallies (T19b: counters, high-water marks and sets) ---------------

func test_counters() -> void:
	_wipe()
	check(Ach.count("kills") == 0, "an untouched counter reads zero")
	check(Ach.bump("kills", 4) == 4, "bump adds and returns the total")
	check(Ach.bump("kills") == 5, "bump defaults to one")
	check(Ach.bump("kills", 0) == 5, "a zero bump changes nothing")
	check(not Ach.is_unlocked("kills_100"), "five kills is not a hundred")
	Ach.bump("kills", 95)
	check(Ach.is_unlocked("kills_100"), "crossing the goal unlocks it")
	check(not Ach.is_unlocked("kills_500"), "...and only the goals actually crossed")

	# A high-water mark only ever moves up.
	check(Ach.record("biggest_hit", 30) == 30, "record takes the new best")
	check(Ach.record("biggest_hit", 12) == 30, "a worse one does not lower it")
	check(Ach.is_unlocked("big_hit_25"), "25 damage is 25 damage")
	check(not Ach.is_unlocked("big_hit_60"), "...and 30 is not 60")

	# A set counts distinct members, not calls.
	check(Ach.collect("bestiary", "goblin") == 1, "collect returns the new size")
	check(Ach.collect("bestiary", "goblin") == 1, "the same member twice is one member")
	check(Ach.collect("bestiary", "kobold") == 2, "a new member counts")
	check(Ach.collect("bestiary", "") == 2, "an empty member is a no-op")
	check(Ach.count("bestiary") == 2, "count reads a set's size")
	check(Ach.members("bestiary").has("kobold"), "members lists what is in it")
	# A jump straight past several goals earns each of them, not just the last.
	for i in 26:
		Ach.collect("bestiary", "beast-%d" % i)
	check(Ach.is_unlocked("bestiary_25"), "a set threshold unlocks like any other")

func test_tally_round_trip() -> void:
	_wipe()
	Ach.bump("kills", 7)
	Ach.record("peak_gold", 1234)
	Ach.collect("schools", "evocation")
	Ach.save_state()
	var back = Ach.load_state()
	check(int(back.counters.get("kills", 0)) == 7, "a counter survives a reload")
	check(int(back.counters.get("peak_gold", 0)) == 1234, "a high-water mark survives a reload")
	check(back.sets.get("schools", []) == ["evocation"], "a set survives a reload")

	# A v1 file — unlocks only, no tallies — still loads, with the tallies at zero.
	var f := FileAccess.open(Ach.PATH, FileAccess.WRITE)
	f.store_string('{"format":"%s","version":1,"unlocked":{"level_5":"2026-01-01T00:00:00"}}' % Ach.FORMAT)
	f.close()
	var old = Ach.load_state()
	check(old.unlocked.has("level_5"), "a version-1 file still reads its unlocks")
	check(old.counters.is_empty() and old.sets.is_empty(), "...and starts the tallies at nothing")
	Ach._current = old

func test_toast_queue() -> void:
	_wipe()
	check(Ach.take_toasts().is_empty(), "nothing earned, nothing to show")
	Ach.unlock("first_victory")
	Ach.unlock("first_victory")
	var got := Ach.take_toasts()
	check(got.size() == 1, "one toast per achievement, however often it is unlocked")
	check(String(got[0]["id"]) == "first_victory", "the toast carries the whole definition")
	check(Ach.take_toasts().is_empty(), "taking drains the queue")

	# Nobody draining it must not grow it without bound.
	_wipe()
	for def in Ach.DEFS:
		Ach.unlock(String(def["id"]))
	check(Ach.pending_toasts() <= Ach.TOAST_QUEUE_MAX, "the queue is capped")

func test_groups() -> void:
	var known := {}
	for g in Ach.GROUPS:
		known[String(g["id"])] = 0
	var ok := true
	for def in Ach.DEFS:
		var g := String(def.get("group", ""))
		if not known.has(g):
			ok = false
			printerr("  unknown group %s on %s" % [g, def["id"]])
			continue
		known[g] += 1
		if def.has("counter"):
			check(int(def.get("goal", 0)) > 0, "%s has a counter, so it needs a goal" % def["id"])
		if def.has("goal"):
			check(String(def.get("counter", "")) != "", "%s has a goal, so it needs a counter" % def["id"])
	check(ok, "every achievement is in a group the viewer knows about")
	for g in known:
		check(known[g] > 0, "group %s has something in it" % g)
	check(Ach.group_label("blood") != "blood", "a group has a label")

func test_completionist() -> void:
	_wipe()
	for def in Ach.DEFS:
		if def["id"] != "completionist":
			check(not Ach.is_unlocked("completionist"), "not yet — %s is still locked" % def["id"])
			Ach.unlock(String(def["id"]))
	check(Ach.is_unlocked("completionist"), "the last one earns the last one")

# Two goals are a number copied by hand out of another file, because
# core/achievements.gd cannot preload either one (travel -> campaign ->
# achievements, and regions -> encounter -> combat -> achievements, both
# already). These are the guard against the copies drifting.
func test_goals_match_their_sources() -> void:
	check(int(Ach.find("every_road_event")["goal"]) == Travel.EVENTS.size(),
		"every_road_event's goal is the size of the road-event table")
	check(int(Ach.find("regions_4")["goal"]) == Regions.BANDS.size(),
		"regions_4's goal is how many bands the map actually has")
	# "Every class" has to mean every class. Adding a thirteenth without moving
	# this goal would quietly leave the achievement earnable one short of what
	# it says, which is the one way a threshold can be wrong and still pass.
	check(int(Ach.find("classes_all_5")["goal"]) == Progression.all_classes().size(),
		"classes_all_5's goal is how many classes there are to be a veteran of")

# Every threshold has to be reachable with the content that ships. The ones
# below are bounded by a fixed table rather than by how long somebody plays.
func test_goals_are_reachable() -> void:
	check(int(Ach.find("bestiary_150")["goal"]) <= Catalog.all("monsters.json").size()
			+ Catalog.all("bestiary.json").size(),
		"there are at least as many monsters as the bestiary goal asks for")
	check(int(Ach.find("schools_8")["goal"]) == 8, "there are eight schools of magic")

# --- more wiring ----------------------------------------------------------

func _fight():
	return Combat.new(RNG.new(7), Encounter.party() + Encounter.monsters(), Encounter.board())

func test_roll_scoring() -> void:
	_wipe()
	var cb = _fight()
	var hero = cb.team_of("party")[0]
	var foe = cb.team_of("foe")[0]
	cb._score_roll(hero, 20, true)
	check(Ach.count("crits") == 1, "a crit is counted")
	check(Ach.is_unlocked("crit_first"), "the first crit is earned")
	check(not Ach.is_unlocked("both_ends"), "one end of the die is not both")
	cb._score_roll(hero, 1, false)
	check(Ach.count("fumbles") == 1, "a natural 1 is counted")
	check(Ach.is_unlocked("both_ends"), "both ends of the die in one fight")
	# The foe's dice are the foe's business.
	cb._score_roll(foe, 20, true)
	check(Ach.count("crits") == 1, "an enemy crit is not the party's crit")

func test_kill_scoring() -> void:
	_wipe()
	var cb = _fight()
	var foes: Array = cb.team_of("foe")
	cb._kill(foes[0])
	check(Ach.count("kills") == 1, "a dead enemy is a kill")
	check(Ach.count("bestiary") == 1, "...and a line in the bestiary")
	cb._kill(foes[0])
	check(Ach.count("kills") == 1, "the same corpse is not killed twice")
	check(not Ach.is_unlocked("triple_kill"), "one kill is not three")
	cb._kill(foes[1])
	cb._kill(foes[2])
	check(Ach.is_unlocked("triple_kill"), "three in one turn is the achievement")
	cb.begin_turn()
	check(cb._kills_this_turn == 0, "a new turn starts the body count over")

	# A hero going down is not a kill for anybody's tally.
	_wipe()
	var cb2 = _fight()
	cb2._kill(cb2.team_of("party")[0])
	check(Ach.count("kills") == 0, "losing somebody is not killing somebody")

func test_untracked_fights_score_nothing() -> void:
	_wipe()
	var cb = _fight()
	cb.tracked = false      # what core/world_battle.gd sets on an NPC-vs-NPC scrap
	cb._kill(cb.team_of("foe")[0])
	cb._score_roll(cb.team_of("party")[0], 20, true)
	cb.heal(cb.team_of("party")[0], 80)
	check(Ach.count("kills") == 0, "an off-screen battle kills nothing of ours")
	check(Ach.count("crits") == 0, "...rolls no dice of ours")
	check(not Ach.is_unlocked("big_heal"), "...and heals nobody of ours")

func test_fight_scoring() -> void:
	_wipe()
	var cb = _fight()
	Encounter2._score_fight(cb, true)
	check(Ach.count("wins") == 1, "a win is counted")
	check(Ach.is_unlocked("one_round"), "a fight over in round 1")
	check(Ach.is_unlocked("untouched"), "nobody was hurt: not a scratch")
	check(not Ach.is_unlocked("long_fight"), "round 1 is not fifteen rounds")
	check(not Ach.is_unlocked("first_wipe"), "a win is not a loss")

	_wipe()
	var cb2 = _fight()
	cb2.round_num = 16
	cb2._apply_damage(cb2.team_of("party")[0], 1)
	Encounter2._score_fight(cb2, true)
	check(Ach.is_unlocked("long_fight"), "fifteen rounds and more")
	check(not Ach.is_unlocked("untouched"), "one hit point is a scratch")

	_wipe()
	var cb3 = _fight()
	Encounter2._score_fight(cb3, false)
	check(Ach.is_unlocked("first_wipe"), "losing earns the one for losing")
	check(Ach.count("wins") == 0, "...and nothing else")

	# Everybody on the floor, and the room still taken.
	_wipe()
	var cb4 = _fight()
	for c in cb4.team_of("party"):
		cb4.downed[c.id] = true
	Encounter2._score_fight(cb4, true)
	check(Ach.is_unlocked("all_down_win"), "every knee on the ground and still a win")

func test_identify_tally() -> void:
	_wipe()
	var c := _campaign()
	c.node = {"kind": "merchant", "id": "hollow-market"}
	c.state = "visiting"
	c.party.stash_add(MYSTERY, 1, false)
	c.party.stash_add(Campaign.IDENTIFY_SCROLL)
	check(c.identify_with_scroll(MYSTERY), "the scroll identifies it")
	check(Ach.count("identified") == 1, "identifying counts towards the tally")
	check(not Ach.is_unlocked("identify_artifact"), "a cloak is not an artifact")

	# The rarity notes: a legendary is collected, a very rare is not.
	_wipe()
	Campaign._note_rarity(VERY_RARE)
	check(Ach.is_unlocked("loot_very_rare"), "a very rare drop still earns its own")
	check(Ach.count("legendaries") == 0, "...but only legendaries fill the case")

func test_gold_wiring() -> void:
	_wipe()
	var p := _party()
	p.add_gold(1200)
	check(Ach.count("gold_earned") == 1200, "earnings are counted")
	check(Ach.count("peak_gold") >= 1200, "the fattest the purse has been")
	check(Ach.is_unlocked("gold_1000"), "a thousand gold at once")
	check(not Ach.is_unlocked("broke"), "not broke yet")
	check(p.spend_gold(1200), "and it is spent")
	check(Ach.count("gold_spent") == 1200, "spending is counted")
	check(Ach.is_unlocked("broke"), "the last gold piece earns its own")
	p.add_gold(10)
	check(Ach.count("peak_gold") >= 1200, "a spent purse does not lower the high-water mark")

func test_multiclass_wiring() -> void:
	_wipe()
	var ch = Presets.party()[0]
	Leveling.add_level(ch)
	check(Ach.count("levels") >= 1, "a level is counted")
	check(Ach.count("classes") >= 1, "...and the class it was taken in")
	check(Ach.count("species") >= 1, "...and the species who took it")
	check(not Ach.is_unlocked("multiclass"), "one class is one class")
	Leveling.add_level(ch, "rogue")
	check(Ach.is_unlocked("multiclass"), "levels in two classes")
	check(not Ach.is_unlocked("multiclass_3"), "two is not three")
	Leveling.add_level(ch, "cleric")
	check(Ach.is_unlocked("multiclass_3"), "levels in three classes")

# The two things "a veteran of every class" turns on: five levels IN one class
# (not a level-5 character), and all five EARNED rather than handed over.
func test_veteran_wiring() -> void:
	_wipe()
	var ch = Presets.party()[0]
	var cid: String = ch.class_id()
	check(ch.level() >= 3, "the preset opens with levels already on the sheet")
	Leveling.milestones(ch)
	check(Ach.count("classes_5") == 0, "the levels a preset hero opens with are not earned")
	for i in Leveling.VETERAN_LEVEL - 1:
		Leveling.add_level(ch, cid)
	check(Ach.count("classes_5") == 0, "four earned levels in a class is not a veteran of it")
	Leveling.add_level(ch, cid)
	check(Ach.members("classes_5") == [cid], "the fifth earned level in a class is")
	check(not Ach.is_unlocked("classes_all_5"), "one class is not every class")

	# The leak this closes: a recruit minted at the party's level arrives with
	# five levels already on the sheet, and one played level must not cash them.
	_wipe()
	var recruit = Presets.party()[1]
	recruit.levels.clear()
	Leveling.grant_levels(recruit, Leveling.VETERAN_LEVEL, "wizard")
	check(recruit.level() == Leveling.VETERAN_LEVEL, "the creator hands over a level-5 build")
	check(Ach.count("classes_5") == 0, "handing the levels over ticks nothing by itself")
	Leveling.add_level(recruit, "wizard")
	check(Ach.count("classes_5") == 0,
		"...and one played level on top of five granted ones does not buy the class")
	for i in Leveling.VETERAN_LEVEL - 1:
		Leveling.add_level(recruit, "wizard")
	check(Ach.members("classes_5") == ["wizard"], "five played levels do")

	# A level-5 character who is a veteran of nothing.
	_wipe()
	var dip = Presets.party()[2]
	var first: String = dip.class_id()
	for i in 4:
		Leveling.add_level(dip, first)
	for i in 4:
		Leveling.add_level(dip, "rogue")
	check(first != "rogue" and Ach.count("classes_5") == 0,
		"four earned in each of two classes is a veteran of neither")

	# ...and the whole list earns it.
	_wipe()
	for one in Progression.all_classes():
		Ach.collect("classes_5", String(one["id"]))
	check(Ach.is_unlocked("classes_all_5"), "a veteran of every class earns The Whole Guild")

# A granted level has to still be granted after a trip through the barracks,
# or the flag is worth nothing the moment a character is saved and loaded.
func test_granted_survives_a_save() -> void:
	_wipe()
	var ch = Presets.party()[0]
	ch.id = "granted-probe"
	Leveling.add_level(ch, ch.class_id())        # one earned level on top
	CharacterSave.save(ch)
	var back = CharacterSave.load_slug("granted-probe")
	CharacterSave.delete("granted-probe")
	check(back != null, "the probe saved and loaded back")
	if back == null:
		return
	var granted := 0
	var earned := 0
	for l in back.levels:
		if bool(l.get("granted", false)):
			granted += 1
		else:
			earned += 1
	check(granted == ch.level() - 1, "every handed-over level came back marked")
	check(earned == 1, "...and the played one came back unmarked")

func test_relationship_wiring() -> void:
	_wipe()
	var p := _party()
	PartyOpinion.adjust(p, "vera", "pike", PartyOpinion.BONDED + 100.0)
	check(Ach.is_unlocked("bonded"), "a pair that got close")
	check(not Ach.is_unlocked("rivals"), "...is not a pair that fell out")
	PartyOpinion.adjust(p, "vera", "ilsa", PartyOpinion.RIVALS - 100.0)
	check(Ach.is_unlocked("rivals"), "a pair that loathe each other")
	PartyOpinion.friendly_fire(p, "vera", "pike")
	check(Ach.is_unlocked("friendly_fire"), "catching your own in your own spell")

func test_world_wiring() -> void:
	_wipe()
	var p := _party()
	Quest.record_settlement_visited(p, "dun-arrow")
	Quest.record_settlement_visited(p, "dun-arrow")
	check(Ach.count("settlements") == 1, "the same town twice is one town")
	Quest.record_region_reached(p, "marches")
	check(Ach.count("regions") == 1, "a region crossed into is counted")

	FactionOpinion.reset()
	FactionOpinion.set_opinion("dwarf", 95.0)
	check(Ach.is_unlocked("faction_loved"), "a faction that thinks the world of you")
	check(not Ach.is_unlocked("faction_hated"), "...is not one that wants you dead")
	FactionOpinion.set_opinion("orc", -95.0)
	check(Ach.is_unlocked("faction_hated"), "a faction that wants you dead")
	FactionOpinion.reset()

	# The road's own table.
	Travel._note_event("storm")
	check(Ach.count("road_events") == 1, "a road event is counted")
	check(Ach.count("road_event_kinds") == 1, "...and which one it was")
	Travel._note_event("storm")
	check(Ach.count("road_events") == 2 and Ach.count("road_event_kinds") == 1,
		"the same weather twice is two events and one kind")
