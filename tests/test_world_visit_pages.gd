# T9x: the settlement visit split into separate screens — a town square hub
# (Market / Inn / Notice Board / Investigate) instead of one panel with
# everything stacked in it. Drives the real scene and its actual button
# tree (not just the data-level Visit.* calls test_settlement_visit.gd
# already covers) so a missing page or a broken navigation wire shows up.
#   godot --headless --path . -s tests/test_world_visit_pages.gd
extends SceneTree

const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

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

	# --- regression: a rest (fresh shelf roll) must not reset the other
	# one-per-visit flags (steal/persuade/investigate) — they used to
	# silently reset because Visit.visit()'s fresh dict only ever had
	# "stolen" carried forward by hand, not persuaded/investigated too.
	var s2 = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s2)
	for i in 10:
		await process_frame
	var home = s2.world.settlements[0]
	FactionOpinion.set_opinion(home.faction, FactionOpinion.REFUSE_TRADE - 1.0)
	Visit.mark_battle(s2.world, home.position, s2.world.clock.elapsed)
	s2.party.gold = 10000
	s2._open_visit(home)
	s2._goto_page("hub")
	s2._investigate()
	check(s2._visit.get("investigated", false), "investigate sets its one-shot flag")
	s2._goto_page("market")
	s2._persuade()
	check(s2._visit.get("persuaded", false), "persuade sets its one-shot flag")
	s2._steal()
	check(s2._visit.get("stolen", false), "steal sets its one-shot flag")

	s2._goto_page("inn")
	s2._rest()
	check(s2._visit.get("investigated", false), "a rest does not reset the investigate flag")
	check(s2._visit.get("persuaded", false), "a rest does not reset the persuade flag")
	check(s2._visit.get("stolen", false), "a rest does not reset the steal flag")
	FactionOpinion.reset()

	# --- haggle: shown on an open market, hidden on a refused one, and vice
	# versa for persuade — they're mutually exclusive by construction.
	var s3 = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s3)
	for i in 10:
		await process_frame
	s3._open_visit(s3.world.settlements[0])
	s3._goto_page("market")
	check(has_button(s3._visit_panel, "Haggle over prices"), "an open market offers haggling")
	check(not has_button(s3._visit_panel, "Persuade them to trade"), "...but not persuasion")
	check(press(s3._visit_panel, "Haggle"), "the Haggle button works")
	check(s3._visit.get("haggled", false), "...and spends the one-per-visit attempt")

	print("test_world_visit_pages: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func WorldCampName() -> String:
	return preload("res://core/world_camp.gd").CAMP_KIT_NAME
