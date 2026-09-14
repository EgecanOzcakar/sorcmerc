# T-actionbar: spell-tier stacking, glyphs, and frequency-based prioritization
# on the redesigned action bar (scenes/main.gd _build_hero_menu/_set_buttons).
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
	var bh_buttons := labels.filter(func(t): return t.contains("Burning Hands"))
	check(bh_buttons.size() == 1, "Burning Hands collapses to one button, not one per tier (got %s)" % str(bh_buttons))
	check(not labels.any(func(t): return t.contains("★")), "no upcast tier leaks onto the main bar as its own button")
	check(main._buttons.columns == main.BTN_COLUMNS, "buttons lay out in the fixed-width grid")

	# Press it: since Burning Hands has 2 tiers, this should open the tier
	# submenu (Back present, both tiers present) rather than casting directly.
	var kids: Array = main._buttons.get_children()
	var bh_idx: int = labels.find(bh_buttons[0]) if not bh_buttons.is_empty() else -1
	check(bh_idx >= 0, "found the Burning Hands button to press")
	if bh_idx >= 0:
		kids[bh_idx].pressed.emit()
		var sub_labels: Array = await _labels(main)
		check(sub_labels.any(func(t): return t.contains("Burning Hands") and not t.contains("★")),
			"tier 1 (base, unstarred) is offered in the submenu")
		check(sub_labels.any(func(t): return t.contains("★2")), "tier 2 (★2) is offered in the submenu")
		check(sub_labels.any(func(t): return t.contains("Back")), "the submenu has a way back")
		# Back returns to the main menu with Burning Hands collapsed again.
		var sub_kids: Array = main._buttons.get_children()
		var back_idx: int = -1
		for i in sub_labels.size():
			if sub_labels[i].contains("Back"):
				back_idx = i
		sub_kids[back_idx].pressed.emit()
		var after_back: Array = await _labels(main)
		check(after_back.filter(func(t): return t.contains("Burning Hands")).size() == 1,
			"Back returns to the main menu, still one Burning Hands button")

	# Frequency: bump Dodge's key hard, rebuild, confirm it moved to the front.
	main._build_hero_menu(ilsa)
	var before: Array = await _labels(main)
	for i in 20:
		main._bump_freq("dodge")   # BASIC's dodge verb id — see scenes/main.gd _build_hero_menu
	main._build_hero_menu(ilsa)
	var after: Array = await _labels(main)
	var dodge_before: int = -1
	var dodge_after: int = -1
	for i in before.size():
		if before[i].contains("Dodge"): dodge_before = i
	for i in after.size():
		if after[i].contains("Dodge"): dodge_after = i
	check(dodge_before >= 0 and dodge_after >= 0, "Dodge is offered before and after")
	check(dodge_after < dodge_before, "a heavily-used verb (Dodge) moves toward the front, not backward")
	check(after[0].contains("Dodge"), "20 uses is enough to put Dodge in the [1] slot")

	print("test_action_bar: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
