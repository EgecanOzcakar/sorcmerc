# T-actionbar: the fixed nine-slot bar, spell-tier stacking, and submenus
# (scenes/main.gd _build_hero_menu/_slotted/_set_buttons).
# Ilsa Vane, the demo party's cleric (core/presets.gd), has Burning Hands
# castable at level 1 and 2 (Light Domain always-prepared + her own 2nd-level
# slots) — a real 2-tier spell to stack, not a synthetic fixture.
#   godot --headless --path . -s tests/test_action_bar.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# What a button says it is. Since T-skillicons the face carries the skill's
# badge and two corner chips, and the NAME leads the tooltip instead
# (scenes/main.gd _build_hero_menu builds "name\nprose\nnumbers"), so that
# first line is what identifies a button now. `b.text` is only populated in a
# build with no icons, and is read here as the fallback for exactly that case.
#
# _set_buttons() queue_free()s the old row instead of removing it outright, so
# get_children() still returns stale buttons until a frame turns over — every
# read below waits one frame first.
func _labels(main) -> Array:
	await process_frame
	var out: Array = []
	for b in main._buttons.get_children():
		var tip := String(b.tooltip_text)
		out.append(tip.get_slice("\n", 0) if tip != "" else String(b.text))
	return out

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	var ilsa = null
	for c in main.cb.combatants:
		if c.cname == "Ilsa Vane":
			ilsa = c
	check(ilsa != null, "Ilsa Vane is in the demo party")
	if ilsa == null:
		print("test_action_bar: %d passed, %d failed" % [_pass, _fail])
		quit(1); return

	main._build_hero_menu(ilsa)
	var labels: Array = await _labels(main)
	# The fixed layout: nine slots, Swap, End turn — for every character.
	check(labels.size() == 11, "eleven buttons: nine slots, Swap, End turn (got %d)" % labels.size())
	check(labels[0].contains("Attack") and labels[1].contains("Spells") and labels[2].contains("Bonus")
		and labels[3].contains("Features") and labels[4].contains("Dash") and labels[5].contains("Disengage")
		and labels[6].contains("Dodge") and labels[7].contains("Hide") and labels[8].contains("Help"),
		"slots 1-9 are Attack, Spells, Bonus, Features, Dash, Disengage, Dodge, Hide, Help & Shove (%s)" % str(labels))
	check(labels[10].contains("End turn"), "the last button is End turn")
	var keys: Array = main._buttons.get_children().map(func(b): return String(b.get_meta("hotkey", "")))
	check(keys.slice(0, 9) == ["1", "2", "3", "4", "5", "6", "7", "8", "9"] and keys[9] == "Tab" and keys[10] == "Spc",
		"the key chips read 1-9, Tab, Spc (%s)" % str(keys))
	check(not labels.any(func(t): return t.contains("Burning Hands")), "no spell sits on the main bar — they live under [2]")
	check(main._buttons.columns == main.BTN_COLUMNS, "buttons lay out in the fixed-width grid")
	# Vera's bar is the same shape, with the slots she lacks greyed rather than gone.
	var vera = null
	for c in main.cb.combatants:
		if c.cname == "Vera Kord":
			vera = c
	main._build_hero_menu(vera)
	var vlabels: Array = await _labels(main)
	check(vlabels.size() == 11 and vlabels[1].contains("Spells") and vlabels[4].contains("Dash"),
		"the fighter's bar has the same eleven slots in the same places")
	var vkids: Array = main._buttons.get_children()
	check(vkids[1].disabled, "a fighter's Spells slot is there, greyed")
	check(not vkids[4].disabled, "...and her Dash is live")   # Attack may be greyed: nobody in reach yet
	# [3] Bonus: Vera's Second Wind is a bonus action, so it sits there (and not under Features)
	main._press_hotkey(2)
	var vbonus: Array = await _labels(main)
	check(vbonus.any(func(l): return l.contains("Second Wind")), "Second Wind is under [3] Bonus (%s)" % str(vbonus))
	main.board_cancel()
	await process_frame
	main._press_hotkey(3)
	var vfeat: Array = await _labels(main)
	check(not vfeat.any(func(l): return l.contains("Second Wind")), "...and not under [4] Features (%s)" % str(vfeat))
	main.board_cancel()
	await process_frame

	# [2] opens the level groups, always; Level 1 holds Burning Hands once (its tiers collapse), Esc back.
	main._build_hero_menu(ilsa)
	await process_frame
	main._press_hotkey(1)
	var lvl_labels: Array = await _labels(main)
	check(lvl_labels[0].contains("Cantrips") and lvl_labels[1].contains("Level 1"), "three spells still get level groups (%s)" % str(lvl_labels))
	main._press_hotkey(1)
	var sub_labels: Array = await _labels(main)
	var bh_buttons := sub_labels.filter(func(t): return t.contains("Burning Hands"))
	check(bh_buttons.size() == 1, "Burning Hands collapses to one button, not one per tier (got %s)" % str(bh_buttons))
	check(not sub_labels.any(func(t): return t.contains("★")), "no upcast tier leaks into the spell list as its own button")
	check(sub_labels[-1].contains("Back") and String(main._buttons.get_children()[-1].get_meta("hotkey", "")) == "Esc",
		"the spell list ends in Back, on Esc")
	check(not sub_labels.any(func(l): return l.contains("Sacred Flame")), "Level 1 does not list the cantrip")
	var lv: Array = main._buttons.get_children().map(func(b): return int(b.tooltip_text.length()))   # touch the buttons
	check(lv.size() > 0, "spell buttons exist")

	# Press it: since Burning Hands has 2 tiers, this should open the tier
	# submenu (Back present, both tiers present) rather than casting directly.
	var kids: Array = main._buttons.get_children()
	var bh_idx: int = sub_labels.find(bh_buttons[0]) if not bh_buttons.is_empty() else -1
	check(bh_idx >= 0, "found the Burning Hands button to press")
	if bh_idx >= 0:
		kids[bh_idx].pressed.emit()
		var tier_labels: Array = await _labels(main)
		check(tier_labels.any(func(t): return t.contains("Burning Hands") and not t.contains("★")),
			"tier 1 (base, unstarred) is offered in the tier picker")
		check(tier_labels.any(func(t): return t.contains("★2")), "tier 2 (★2) is offered in the tier picker")
		check(tier_labels.any(func(t): return t.contains("Back")), "the tier picker has a way back")
		# Esc returns to the main bar, spells folded under [2] again.
		main.board_cancel()
		var after_back: Array = await _labels(main)
		check(after_back.size() == 11 and after_back[1].contains("Spells"), "Esc returns to the main bar")

	# A verb that has gone unavailable holds its slot, greyed, instead of
	# collapsing the row and shifting every badge after it.
	main._build_hero_menu(ilsa)
	var full: Array = await _labels(main)
	var lit: int = main._buttons.get_children().filter(func(b): return not b.disabled).size()
	ilsa.econ["action"] = 0
	main._build_hero_menu(ilsa)
	var spent: Array = await _labels(main)
	check(spent.size() == full.size(), "spending the action does not shorten the bar (%d vs %d)"
		% [spent.size(), full.size()])
	for i in mini(spent.size(), full.size()) - 1:      # the last slot is End turn, which relabels
		check(spent[i] == full[i], "slot %d still holds the same skill" % (i + 1))
	var still_lit: int = main._buttons.get_children().filter(func(b): return not b.disabled).size()
	check(still_lit < lit, "and the ones that need the action are greyed out (%d lit, was %d)"
		% [still_lit, lit])

	# A caster with every spell in the book: [2] groups by level, each group
	# numbered from 1, and a group past nine entries pages on [9] More.
	var ch = load("res://core/presets.gd").ilsa()
	var Adapter = load("res://core/adapter.gd")
	var Catalog = load("res://core/rules/catalog.gd")
	var Effects = load("res://core/rules/effects.gd")
	for i in 5:
		ch.add_level("cleric", -1)
	var ids: Array = []
	for sid in Catalog.index("spells.json").keys():
		if not Effects.spell(sid).is_empty():
			ids.append(sid)
	ch.prepared.assign(ids)
	var archmage = Adapter.to_combatant(ch, "party", ilsa.pos)
	archmage.id = "archmage"
	archmage.team = "party"
	main.cb.combatants.append(archmage)
	main.cb.begin_turn_for(archmage)
	main._build_hero_menu(archmage)
	await process_frame
	main._press_hotkey(1)
	var groups: Array = await _labels(main)
	check(groups[0].contains("Cantrips") and groups[1].contains("Level 1") and groups.size() <= 10,
		"20+ spells: [2] opens level groups, Cantrips first (%s)" % str(groups))
	check(groups[-1].contains("Back"), "the group list ends in Back")
	main._press_hotkey(0)   # Cantrips
	var cantrips: Array = await _labels(main)
	var cn: int = cantrips.filter(func(l): return not l.contains("Back") and not l.contains("More")).size()
	check(cn >= 5 and cn <= 9, "the cantrip page holds at most nine spells (%d)" % cn)
	if cantrips.any(func(l): return l.contains("More")):
		var more_idx: int = -1
		for i in cantrips.size():
			if cantrips[i].contains("More"):
				more_idx = i
		check(more_idx == 8, "More sits on [9]")
		main._press_hotkey(more_idx)
		var page2: Array = await _labels(main)
		check(page2 != cantrips and page2.any(func(l): return l.contains("Back")), "More turns the page")
	main.board_cancel()
	var home: Array = await _labels(main)
	check(home.size() == 11 and home[1].contains("Spells"), "Esc from a group returns to the main bar")

	print("test_action_bar: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
