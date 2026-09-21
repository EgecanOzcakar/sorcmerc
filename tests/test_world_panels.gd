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
const Leveling = preload("res://core/leveling.gd")   # #118: the level-up announcement

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

	# the quests are the lines above the ladder's Standing section
	var rows: Array = labels(main._quest_panel).filter(func(l): return l.text != "Quest log")
	for i in rows.size():
		if rows[i].text == "Standing":
			rows = rows.slice(0, i)
			break
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

	# --- issue #33: a long job title must not widen the counter ----------
	#
	# "quest complete screen stretches and overflows". A trade row's label had
	# no wrapping, so its minimum width was the whole string: one long title
	# pushed the row out, the row pushed the list out, and the list pushed the
	# settlement panel past the edge of the screen — while the panel was still
	# placing itself by arithmetic against the 460x460 it was told to expect.
	for q in main.party.quests:
		q["progress"] = int(q["required"])
		q["state"] = "complete"
		q["title"] = "Clear out the Zombie Graveyard on the Oakford road before the frost sets in"
	main._goto_page("board")
	for i in 3:
		await process_frame
	var board: PanelContainer = panels(main._visit_panel)[0]
	check(has_button(main._visit_panel, "Turn in"), "the board has completed jobs on it to turn in")
	check(board.size.x <= 480.0, "a long title does not widen the counter (%.0f)" % board.size.x)
	check(board.global_position.x >= 0.0 and board.global_position.x + board.size.x <= main.size.x,
		"...and it stays on the screen sideways")
	var mid2: Vector2 = board.global_position + board.size * 0.5
	check(absf(mid2.x - main.size.x * 0.5) < 2.0 and absf(mid2.y - main.size.y * 0.5) < 2.0,
		"the counter is centred on what it measures, not on what it guessed")

	# ...and a short window trims the list rather than running off the bottom.
	main.size = Vector2(1024, 600)
	main._build_visit_panel()
	for i in 3:
		await process_frame
	board = panels(main._visit_panel)[0]
	check(board.global_position.y >= 0.0 and board.global_position.y + board.size.y <= main.size.y,
		"the counter fits a short window (%.0f..%.0f of %.0f)" % [
			board.global_position.y, board.global_position.y + board.size.y, main.size.y])
	main.size = Vector2(1280, 1280)
	main._build_visit_panel()
	for i in 3:
		await process_frame

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

	await _level_up_announcement(main)
	print("test_world_panels: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Issue #118: a level used to arrive as one chime and a number two screens
# away. It gets the after-action page's own treatment now — the map stops, a
# gilt panel says who is ready, and its button is the trip to the party screen.
# It cannot appear over a fight: this runs off the map's own _process, which
# does not tick while combat owns the screen, and _overlay_up() holds it back
# behind every card and panel the map can raise.
func _level_up_announcement(main) -> void:
	check(main._levelup_panel == null, "nothing is announced with no level banked")
	var who = main.party.roster[0]
	who.xp = Leveling.xp_for_level(who.level() + 1)
	check(main._ready_to_level().size() == 1, "one character is owed a level")

	# Held back while anything else owns the screen.
	main._toggle_quests()
	for i in 3:
		await process_frame
	check(main._levelup_panel == null, "it waits behind an open panel")
	main._close_quests()
	for i in 4:
		await process_frame
	check(main._levelup_panel != null, "and comes up once the map is clear")
	if main._levelup_panel == null:
		return
	check(main.world.clock.is_paused(), "the map stops for it")
	var said := ""
	for l in labels(main._levelup_panel):
		said += l.text + "|"
	check(said.contains("Level up"), "it says what it is (%s)" % said)
	check(said.contains(who.cname), "and whose level it is")
	check(has_button(main._levelup_panel, "Open the party"), "its button is the way to spend it")

	# Centred like the spoils page it follows, and wholly on screen.
	var panel: PanelContainer = panels(main._levelup_panel)[0]
	var mid: Vector2 = panel.global_position + panel.size * 0.5
	check(absf(mid.x - main.size.x * 0.5) < 2.0 and absf(mid.y - main.size.y * 0.5) < 2.0,
		"the panel is centred (%s vs %s)" % [mid, main.size * 0.5])

	check(press(main._levelup_panel, "Open the party"), "press it")
	for i in 3:
		await process_frame
	check(main._levelup_panel == null and main._party_overlay != null,
		"it closes and the party screen is open")
	main._close_party()
	for i in 4:
		await process_frame

	# Once per level, per character: backing out does not put it straight back.
	check(main._levelup_panel == null, "it does not nag — the level was already announced")
	who.xp = Leveling.xp_for_level(who.level() + 2)
	who.add_level(who.class_id(), -1)
	for i in 4:
		await process_frame
	check(main._levelup_panel != null, "...and the NEXT level says so again")
	main._close_levelup()
	await process_frame
