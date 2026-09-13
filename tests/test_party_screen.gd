# T9x: the Party screen's "Map figure" picker (core/party.gd's
# overworld_figure) — drives the real scene's OptionButton, not just the
# data field, so a broken wire (wrong metadata, item order) would show up.
#   godot --headless --path . -s tests/test_party_screen.gd
extends SceneTree

const HeroModels = preload("res://scenes/figures3d.gd").HERO_MODELS

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

	check(ob.item_count == HeroModels.size() + 1, "one entry per hero model, plus the default pawn")
	check(String(ob.get_item_metadata(0)) == "", "the first entry is the default (no figure)")
	check(ob.get_selected_id() == ob.get_item_id(0) or ob.selected == 0,
		"a fresh party starts on the default pawn")

	# Pick a real class and confirm the field actually updates.
	var wiz_idx := -1
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == "wizard":
			wiz_idx = i
	check(wiz_idx >= 0, "wizard is one of the offered figures")
	ob.select(wiz_idx)
	ob.item_selected.emit(wiz_idx)
	check(screen.party.overworld_figure == "wizard", "picking one actually sets overworld_figure")

	# Re-opening the screen with that party should show the pick already made.
	var screen2 = load("res://scenes/party/party.tscn").instantiate()
	screen2.party = screen.party
	root.add_child(screen2)
	await process_frame
	var ob2 := find_option_button(screen2)
	check(ob2 != null and String(ob2.get_item_metadata(ob2.selected)) == "wizard",
		"reopening the screen shows the previously chosen figure selected")

	print("test_party_screen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
