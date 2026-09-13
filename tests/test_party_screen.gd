# T9x: the Party screen's "Map figure" picker (core/party.gd's
# overworld_figure) — drives the real scene's OptionButton, not just the
# data field, so a broken wire (wrong metadata, item order) would show up.
# Options are the ACTIVE party's own members, one row per person — so picking
# Vera sets overworld_figure to "vera", two members of the same class are two
# rows that each stick, and nobody outside the active four is offered at all.
#   godot --headless --path . -s tests/test_party_screen.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# The row carrying this member id, or -1.
func index_of(ob: OptionButton, member_id: String) -> int:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == member_id:
			return i
	return -1

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

	# Pick a real, active member and confirm the field updates — with their
	# id, the character, not "fighter", the class.
	var vera_idx := index_of(ob, "vera")
	check(vera_idx >= 0, "Vera is one of the offered figures, by her own id")
	ob.select(vera_idx)
	ob.item_selected.emit(vera_idx)
	check(screen.party.overworld_figure == "vera", "picking one actually sets overworld_figure")

	# Re-opening the screen with that party should show the pick already made.
	var screen2 = load("res://scenes/party/party.tscn").instantiate()
	screen2.party = screen.party
	root.add_child(screen2)
	await process_frame
	var ob2 := find_option_button(screen2)
	check(ob2 != null and String(ob2.get_item_metadata(ob2.selected)) == "vera",
		"reopening the screen shows the previously chosen figure selected")

	# Two members of the same class are two rows, and each one sticks: swap
	# the benched Gera (barbarian) in for Ilsa and the active four hold two
	# barbarians, Gera and Thrun.
	check(screen.party.swap("ilsa", "gera"), "swap Gera in for Ilsa")
	screen._refresh()
	await process_frame          # the previous picker is only queue_free()d
	ob = find_option_button(screen)
	var gera_idx := index_of(ob, "gera")
	var thrun_idx := index_of(ob, "thrun")
	check(gera_idx >= 0 and thrun_idx >= 0 and gera_idx != thrun_idx,
		"two barbarians are two separate, individually selectable rows")
	for who in ["gera", "thrun"]:
		ob.select(index_of(ob, who))
		ob.item_selected.emit(index_of(ob, who))
		check(screen.party.overworld_figure == who, "picking %s sets exactly %s" % [who, who])
		screen._refresh()
		await process_frame
		ob = find_option_button(screen)
		check(String(ob.get_item_metadata(ob.selected)) == who, "and %s is still the one shown selected" % who)

	# Back-compat: a save written before the switch holds a class id. The
	# picker resolves it the old way — the first active member of that class,
	# Gera here — and core/party.gd migrates the field to her id.
	screen.party.overworld_figure = "barbarian"
	screen._refresh()
	await process_frame
	ob = find_option_button(screen)
	check(String(ob.get_item_metadata(ob.selected)) == "gera",
		"an old save's class id opens on the member it resolves to")
	check(screen.party.overworld_figure == "gera", "...and the field is migrated to that member's id")

	print("test_party_screen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
