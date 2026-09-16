# Issue #24: "berserker rage needs twice keyboard press for activation".
#
# Rage burns a limited pool, so it wears the two-press confirm guard every
# costly verb wears (scenes/main.gd _costly/_confirm_opt). The guard was fine;
# where it landed was not. Arming it rebuilt the MAIN BAR, and Rage lives one
# level down, in the [3] Bonus submenu — so the first press armed it and threw
# the player back to a bar with no confirm anywhere on it, where the second
# press of the same key swung the greataxe instead. Rage actually took four
# presses (3, 1, 3, 1), and the third and fourth were the only ones that looked
# like they did anything.
#
#   godot --headless --path . -s tests/test_confirm_in_submenu.gd
extends SceneTree

const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The name leads the tooltip since T-skillicons; b.text is only populated in a
# build with no icons. Same reader tests/test_action_bar.gd uses.
func _labels(main) -> Array:
	await process_frame
	var out: Array = []
	for b in main._buttons.get_children():
		var tip := String(b.tooltip_text)
		out.append(tip.get_slice("\n", 0) if tip != "" else String(b.text))
	return out

func _init() -> void:
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = party
	root.add_child(main)
	for i in 10:
		await process_frame

	var thrun = null
	for c in main.cb.combatants:
		if c.cname == "Thrun Stonefist":
			thrun = c
	check(thrun != null, "the demo roster's barbarian is on the board")
	if thrun == null:
		print("test_confirm_in_submenu: %d passed, %d failed" % [_pass, _fail])
		quit(1); return

	main._build_hero_menu(thrun)
	var bar: Array = await _labels(main)
	check(bar.size() == 11 and bar[2].contains("Bonus"), "[3] is the Bonus slot (%s)" % str(bar))

	# [3] — the submenu, because a barbarian has two bonus-cost things (Rage and
	# Reckless Attack), not one.
	main._press_hotkey(2)
	var sub: Array = await _labels(main)
	check(main._submenu == "bonus", "pressing 3 opens the bonus list")
	check(sub[0].contains("Rage"), "Rage is the first thing in it (%s)" % str(sub))

	# [1] — arms the confirm, and must leave the player looking at the list they
	# armed it from, with the confirm under the key they just pressed.
	main._press_hotkey(0)
	var armed: Array = await _labels(main)
	check(main._armed == "barbarian-rage", "the first press arms Rage")
	check(main._submenu == "bonus", "...and stays in the bonus list")
	check(armed[0].to_lower().contains("confirm"), "...with the confirm on the key just pressed (%s)" % str(armed))
	check(not main._buttons.get_child(0).disabled, "...and it is pressable")

	# [1] again — Rage comes out. Two presses of the same key, which is what the
	# guard has always claimed to cost.
	check(thrun.pool_left("rage") == 2, "both rages are unspent going in")
	main._press_hotkey(0)
	await process_frame
	check(thrun.pool_left("rage") == 1, "the second press of the same key rages")
	check(main._armed == "", "...and disarms")

	# The greataxe stayed in its scabbard: nothing about this spent the action.
	check(thrun.econ["action"] > 0, "arming and confirming never swung a weapon")

	# The same guard on the main bar is unchanged — End turn with an unspent
	# action arms and confirms in place.
	main._build_hero_menu(thrun)
	await process_frame
	var n: int = main._buttons.get_child_count()
	main._press_hotkey(-1)
	var ended: Array = await _labels(main)
	check(main._armed == "end", "End turn arms on the main bar")
	check(main._submenu == "", "...without opening anything")
	check(ended.size() == n and ended[n - 1].to_lower().contains("confirm"),
		"...and the bar keeps its shape, with the confirm in End turn's own slot (%s)" % str(ended))

	print("test_confirm_in_submenu: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
