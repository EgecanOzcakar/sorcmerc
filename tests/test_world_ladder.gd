# The ladder on the world screen: the standing line, the HUD title, the quest
# log's Standing section, the Back room tab, the audience.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_ladder.gd
extends SceneTree

const Ladder = preload("res://core/ladder.gd")
const Visit = preload("res://core/settlement_visit.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(buttons(c))
	return out

func button_named(node: Node, text: String):
	for b in buttons(node):
		if text in String(b.text):
			return b
	return null

func stash_count(party) -> int:
	var n := 0
	for e in party.stash:
		n += int(e["quantity"])
	return n

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	Ladder.reset()
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var town = w.settlements[0]          # Riverhold, human city
	w.clock.pause()
	main._open_visit(town)
	await process_frame
	check(said(main, "Strangers here, for now."), "a stranger's town square")
	check(button_named(main, "Inn.  A night is 40") != null, "the city's bed at 40")
	check(button_named(main, "Seek an audience") == null, "no audience for a stranger")
	main._close_visit()
	await process_frame
	main._lair_msg.text = "Riverhold breathes again."   # the deed's own line, said the same frame
	Ladder.deed("human", 4)
	main._open_visit(town)
	await process_frame
	check(said(main, "Known here — they will pass you a neighbour's work."), "Known: the line")
	check(main._lair_msg.text == "Riverhold breathes again.  Known among the humans now.", "the rung gained is said after the deed's own line, not over it: %s" % main._lair_msg.text)
	check(button_named(main, "Inn.  A night is 20") != null, "Known: half a bed")
	main._close_visit()
	await process_frame
	Ladder.deed("human", 8)
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(said(main, "Trusted here — the back room is open to you."), "Trusted: the line")
	main._goto_page("market")
	await process_frame
	var tab = button_named(main, "Back room")
	check(tab != null, "the Back room tab is there")
	if tab != null:
		tab.pressed.emit()
		await process_frame
	check(not Visit.stock_by_service(town, main._visit).get("backroom", []).is_empty() and said(main, "The back room"), "...and shows the shelf")
	# buying the last of it: the tab goes, and the page falls back to a counter
	main.party.gold = 100000
	for e in Visit.stock_by_service(town, main._visit).get("backroom", []):
		Visit.buy(main._visit, main.party, String(e["item_id"]))
	main._build_visit_panel()
	await process_frame
	check(main._market_tab != "backroom" and button_named(main, "Back room") == null, "the last back-room item bought: the tab is gone and the page is not stranded on it (%s)" % main._market_tab)
	main._goto_page("board")
	await process_frame
	check(said(main, "The patron's table: word of work from all over."), "the patron's board line")
	check(said(main, "Hirelings — work pays +10 %."), "renown's pay line (12 deeds: Hirelings)")
	main._close_visit()
	await process_frame
	# the HUD and the quest log
	check("Hirelings" in main._region_lbl.text, "the HUD carries the title: %s" % main._region_lbl.text)
	main._toggle_quests()
	await process_frame
	check(said(main, "Standing") and said(main, "Hirelings") and said(main, "Trusted") and said(main, "12"), "the quest log's Standing section")
	main._close_quests()
	await process_frame
	# Sworn: the audience, once
	Ladder.deed("human", 13)
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(said(main, "Sworn to this people. Their doors are yours."), "Sworn: the line")
	check(button_named(main, "Inn.  On the house.") != null, "Sworn: on the house")
	var aud = button_named(main, "Seek an audience with the lord")
	check(aud != null, "the audience button")
	var stash_before: int = stash_count(main.party)
	var xp_before: int = main.party.party_characters()[0].xp
	if aud != null:
		aud.pressed.emit()
	for i in 3:
		await process_frame
	# the card draws itself (scenes/world/event_card.gd has no Labels): read the dict it was shown
	check(main._event_card != null and "The hall is cleared for you." in String(main._event_card._e.get("text", "")), "the audience card")
	check(main._event_card != null and main._event_card._e.get("item_name", "") != "", "...naming the gift")
	check(stash_count(main.party) > stash_before, "the gift is in the pack")
	check(main.party.party_characters()[0].xp > xp_before, "the XP")
	check(Ladder.audience_held("human"), "held")
	check(w.clock.is_paused(), "the clock is paused under the card")
	main._on_event_ack()
	await process_frame
	check(not w.clock.is_paused(), "...and runs again after it")
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(button_named(main, "Seek an audience with the lord") == null, "once: no second audience")
	main._close_visit()
	await process_frame
	# the title-change line
	Ladder.deed("elf", 6)                  # 31: still a Company of Note
	Ladder.deed("elf", 9)                  # 40: Asked For by Name
	for i in 3:
		await process_frame
	check("The company is spoken of now: Asked For by Name." in main._lair_msg.text, "the title change is said: %s" % main._lair_msg.text)
	town.last_visited = -1.0
	main._open_visit(town)
	await process_frame
	check(said(main, "Sworn to this people. Their doors are yours.  Asked For by Name, they say."), "the fourth title rides the standing line")
	main._close_visit()
	await process_frame
	print("test_world_ladder: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
