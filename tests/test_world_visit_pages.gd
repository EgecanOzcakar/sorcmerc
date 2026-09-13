# T9x: the settlement visit split into separate screens — a town square hub
# (Market / Inn / Notice Board / Investigate) instead of one panel with
# everything stacked in it. Drives the real scene and its actual button
# tree (not just the data-level Visit.* calls test_settlement_visit.gd
# already covers) so a missing page or a broken navigation wire shows up.
#   godot --headless --path . -s tests/test_world_visit_pages.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func has_button(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text:
			return true
	return false

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(labels(c))
	return out

func has_label(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l.text:
			return true
	return false

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text and not b.disabled:
			b.pressed.emit()
			return true
	return false

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	var s = main.world.settlements[0]
	main._open_visit(s)
	check(main._visit_page == "hub", "a fresh visit opens on the town square")
	check(has_button(main._visit_panel, "Market"), "the hub offers a way into the market")
	check(has_button(main._visit_panel, "Inn"), "...and the inn")
	check(has_button(main._visit_panel, "Notice Board"), "...and the notice board")
	check(not has_button(main._visit_panel, "Steal from the market"),
		"market-only actions don't leak onto the hub")
	check(not has_button(main._visit_panel, "Rest the night"),
		"inn-only actions don't leak onto the hub")

	check(press(main._visit_panel, "Market"), "the Market button actually works")
	check(main._visit_page == "market", "...and switches the page")
	check(has_button(main._visit_panel, "Steal from the market"), "the market page has its own actions")
	check(has_label(main._visit_panel, WorldCampName()), "...including the camp kit")
	check(not has_button(main._visit_panel, "Rest the night"), "...but not the inn's")
	check(has_button(main._visit_panel, "Town Square"), "every non-hub page can go back")

	check(press(main._visit_panel, "Town Square"), "back actually returns to the hub")
	check(main._visit_page == "hub", "...and the page state follows")

	check(press(main._visit_panel, "Inn"), "the Inn button works")
	check(main._visit_page == "inn", "...and switches the page")
	check(has_button(main._visit_panel, "Rest the night"), "the inn page has its own action")
	check(not has_button(main._visit_panel, "Steal"), "...but not the market's")

	press(main._visit_panel, "Town Square")
	check(press(main._visit_panel, "Notice Board"), "the Notice Board button works")
	check(main._visit_page == "board", "...and switches the page")
	check(has_button(main._visit_panel, "Leave"), "every page keeps a way out")

	check(press(main._visit_panel, "Leave"), "Leave actually closes the visit")
	check(main._visit.is_empty(), "...and the visit is really over")

	print("test_world_visit_pages: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func WorldCampName() -> String:
	return preload("res://core/world_camp.gd").CAMP_KIT_NAME
