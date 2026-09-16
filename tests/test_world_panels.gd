# Issue #28: "quests page has verticality issue".
#
# The quest log's list sat in a ScrollContainer that still allowed horizontal
# scrolling. A ScrollContainer hands its child the child's own MINIMUM size on
# any axis it can scroll, and an autowrapping Label's minimum width is one
# pixel — so every quest line came out as a 1px-wide, ~570px-tall column of
# stacked single characters. Eight quests made 4096px of scroll for text that
# fits in eight lines.
#
# Measures the real panels the real screen builds.
#   godot --headless --path . -s tests/test_world_panels.gd
extends SceneTree

const Quest = preload("res://core/quest.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(labels(c))
	return out

func scrolls(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is ScrollContainer:
			out.append(c)
		out.append_array(scrolls(c))
	return out

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

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text and not b.disabled:
			b.pressed.emit()
			return true
	return false

func panels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is PanelContainer:
			out.append(c)
		out.append_array(panels(c))
	return out

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	# A real pile of quests, taken through the real API.
	var rng = RNG.new(7)
	for s in main.world.settlements:
		for q in Quest.world_quest_offers(main.world, s, main.party, rng):
			Quest.accept(main.party, q)
	var live: Array = Quest.active(main.party)
	check(live.size() >= 4, "the party is carrying a pile of quests (%d)" % live.size())

	main._toggle_quests()
	for i in 6:
		await process_frame
	check(main._quest_panel != null, "the quest log opens")

	var rows: Array = labels(main._quest_panel).filter(func(l): return l.text != "Quest log")
	check(rows.size() == live.size(), "one line per quest (%d of %d)" % [rows.size(), live.size()])
	for l in rows:
		# A wrapped line is as wide as the column and one or two lines tall. The
		# bug made every one of them a pixel wide and hundreds tall.
		check(l.size.x > 200.0, "a quest line is as wide as the column, not 1px (%.0f)" % l.size.x)
		check(l.size.y < 120.0, "...and a couple of lines tall, not hundreds (%.0f)" % l.size.y)

	for sc in scrolls(main._quest_panel):
		check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"the list scrolls vertically only")
		check(sc.get_child(0).size.y < sc.size.y * 4.0,
			"the column is not a skyscraper (%.0f in a %.0f window)" % [sc.get_child(0).size.y, sc.size.y])

	# Centred by a container rather than by arithmetic, so a panel that measures
	# bigger than its guess still lands on the screen instead of off an edge.
	var panel: PanelContainer = panels(main._quest_panel)[0]
	var mid: Vector2 = panel.global_position + panel.size * 0.5
	check(absf(mid.x - main.size.x * 0.5) < 2.0 and absf(mid.y - main.size.y * 0.5) < 2.0,
		"the panel is centred on the screen (%s vs %s)" % [mid, main.size * 0.5])
	check(panel.global_position.x >= 0.0 and panel.global_position.y >= 0.0
		and panel.global_position.y + panel.size.y <= main.size.y,
		"...and wholly on it")

	main._close_quests()
	await process_frame

	# The settlement's own two lists are built the same way, and were not.
	var s0 = main.world.settlements[0]
	main.world.player().position = s0.position
	main._check_visit()
	await process_frame
	check(not main._visit.is_empty(), "a settlement opens")
	for page in ["market", "board"]:
		main._goto_page(page)
		for i in 3:
			await process_frame
		var found := scrolls(main._visit_panel)
		check(not found.is_empty(), "the %s page has a list" % page)
		for sc in found:
			check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
				"the %s list scrolls vertically only" % page)
			check(sc.get_child(0).size.x >= sc.size.x - 1.0,
				"...and its column fills the width instead of collapsing (%.0f of %.0f)" % [
					sc.get_child(0).size.x, sc.size.x])

	# --- issue #27: the roster reshuffles at an inn, not in a field -------
	main._goto_page("inn")
	for i in 3:
		await process_frame
	check(has_button(main._visit_panel, "Sort out the party"), "the inn offers to sort the party out")
	check(press(main._visit_panel, "Sort out the party"), "...and it opens")
	for i in 3:
		await process_frame
	check(main._party_overlay != null, "the party screen is up")
	var at_inn = main._party_overlay.get_child(0)
	check(not at_inn.roster_locked, "opened from the inn it is unlocked")
	main._close_party()
	await process_frame
	check(not main._visit.is_empty(), "backing out of it leaves the settlement open")
	check(main.world.clock.is_paused(), "...and does not set the map running behind the panel")

	main._close_visit()
	await process_frame
	main._open_party()
	for i in 3:
		await process_frame
	check(main._party_overlay != null, "the HUD button opens it out on the road")
	var on_road = main._party_overlay.get_child(0)
	check(on_road.roster_locked, "...locked, because a field is not an inn")
	check("inn" in String(on_road.locked_note), "...and it says where to go instead")
	main._close_party()
	await process_frame

	print("test_world_panels: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
