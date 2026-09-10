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
	test_combat_wiring()
	test_campaign_wiring()
	test_leveling_wiring()
	test_party_wiring()
	await test_viewer()
	_wipe()
	print("test_achievements: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()

func test_defs() -> void:
	check(Ach.DEFS.size() >= 10, "a real list of achievements")
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
