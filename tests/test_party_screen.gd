# T9x: the Party screen's "Map figure" picker (core/party.gd's
# overworld_figure) — drives the real scene's OptionButton, not just the
# data field, so a broken wire (wrong metadata, item order) would show up.
# Options are the ACTIVE party's own members, by name — not any of the 12
# possible classes — so picking Vera (a fighter) sets overworld_figure to
# "fighter"; nobody outside the active four is offered at all.
#   godot --headless --path . -s tests/test_party_screen.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func find_option_button(node: Node) -> OptionButton:
	for c in node.get_children():
		if c is OptionButton:
			return c
		var hit := find_option_button(c)
		if hit != null:
			return hit
	return null

func _init() -> void:
	var screen = load("res://scenes/party/party.tscn").instantiate()
	root.add_child(screen)
	await process_frame

	var ob := find_option_button(screen)
	check(ob != null, "the map-figure picker exists")
	if ob == null:
		quit(1); return

	# The demo roster's active four: Vera (fighter), Pike (rogue), Ilsa
	# (cleric), Thrun (barbarian) — Gera (the 5th, a barbarian) is benched
	# and should NOT be offered.
	check(ob.item_count == screen.party.active.size() + 1,
		"one entry per ACTIVE member, plus the default pawn (got %d)" % ob.item_count)
	check(String(ob.get_item_metadata(0)) == "", "the first entry is the default (no figure)")
	check(ob.selected == 0, "a fresh party starts on the default pawn")
	var names := ""
	for i in ob.item_count:
		names += ob.get_item_text(i) + "|"
	check("Vera Kord" in names, "an active member is offered by name")
	check(not "Gera" in names, "a benched member is not offered")

	# Pick a real, active member's class and confirm the field updates.
	var fighter_idx := -1
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == "fighter":
			fighter_idx = i
	check(fighter_idx >= 0, "Vera (fighter) is one of the offered figures")
	ob.select(fighter_idx)
	ob.item_selected.emit(fighter_idx)
	check(screen.party.overworld_figure == "fighter", "picking one actually sets overworld_figure")

	# Re-opening the screen with that party should show the pick already made.
	var screen2 = load("res://scenes/party/party.tscn").instantiate()
	screen2.party = screen.party
	root.add_child(screen2)
	await process_frame
	var ob2 := find_option_button(screen2)
	check(ob2 != null and String(ob2.get_item_metadata(ob2.selected)) == "fighter",
		"reopening the screen shows the previously chosen figure selected")

	print("test_party_screen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
