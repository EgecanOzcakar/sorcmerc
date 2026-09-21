# The lodge on the world screen: the square's button, the page and its rows,
# the diorama beside the town growing a part group per room, the strongroom
# the retreat cannot reach, the garden's potion on coming home, the shrine's
# blessing on leaving, the label, the elsewhere line, the free bed.
#   docs/superpowers/specs/2026-09-21-lodge-design.md §3
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_lodge.gd
extends SceneTree

const Lodge = preload("res://core/lodge.gd")
const Downtime = preload("res://core/downtime.gd")
const Visit = preload("res://core/settlement_visit.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const Kit = preload("res://scenes/world/settlement_kit.gd")

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
		if c is Button and not c is OptionButton:
			out.append(c)
		out.append_array(buttons(c))
	return out

func button_named(node: Node, text: String):
	for b in buttons(node):
		if text in String(b.text):
			return b
	return null

func buttons_named(node: Node, text: String) -> Array:
	return buttons(node).filter(func(b): return String(b.text) == text)

# The row (an HBoxContainer) whose label says `text`: a _trade_row, or one of
# the lodge's own picker rows.
func row_of(node: Node, text: String) -> HBoxContainer:
	for c in node.get_children():
		if c is Label and text in String(c.text):
			var p: Node = c.get_parent()
			while p != null and not p is HBoxContainer:
				p = p.get_parent()
			if p != null:
				return p
		var r := row_of(c, text)
		if r != null:
			return r
	return null

func row_button(node: Node, text: String):
	var row := row_of(node, text)
	return null if row == null else buttons(row)[0]

func row_option(row: Node, i := 0) -> OptionButton:
	var opts: Array = row.get_children().filter(func(c): return c is OptionButton)
	return opts[i]

# The yard's row is the one with three pickers in it (who, the old feat, the new).
func pickers_row(node: Node, n: int) -> HBoxContainer:
	for c in node.get_children():
		if c is HBoxContainer and c.get_children().filter(func(x): return x is OptionButton).size() == n:
			return c
		var r := pickers_row(c, n)
		if r != null:
			return r
	return null

func lodge_parts(main) -> int:
	var d: Node3D = main._settlements3d._dioramas.get("lodge")
	return -1 if d == null else d.get_child(0).get_child_count()

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	Ladder.reset()
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var party = main.party
	var city = w.settlements[0]          # Riverhold, human city
	var town = w.settlements[1]          # Greenmarch, elf town
	w.clock.pause()
	party.gold = 5000
	party.last_long_rest_at = -1e9       # tired enough for a bed

	# --- the square: nothing until Known, then the buy button -----------------
	main._open_visit(city)
	await process_frame
	check(button_named(main, "Buy a lodge here") == null and not said(main, "lodge"), "strangers are not sold a house")
	check(not main._settlements3d._dioramas.has("lodge"), "and there is no lodge on the map")
	main._close_visit()
	Ladder.deed("human", 4)             # Known at Riverhold
	main._open_visit(city)
	await process_frame
	var buy = button_named(main, "Buy a lodge here (%d ◉)" % Lodge.HOUSE_COST)
	check(buy != null and not buy.disabled, "Known here: the square offers a house at %d ◉" % Lodge.HOUSE_COST)
	party.gold = Lodge.HOUSE_COST - 1
	main._build_visit_panel()
	await process_frame
	buy = button_named(main, "Buy a lodge here (%d ◉)" % Lodge.HOUSE_COST)
	check(buy != null and buy.disabled, "a purse short of the price sees the button, disabled")
	party.gold = 5000
	main._build_visit_panel()
	await process_frame
	button_named(main, "Buy a lodge here").pressed.emit()
	await process_frame
	check(Lodge.at(party, city) and party.gold == 5000 - Lodge.HOUSE_COST, "bought: the house at Riverhold, the price paid")
	check("The deed is signed" in String(main._visit.get("log", "")), "the square says so: %s" % main._visit.get("log", ""))
	check(button_named(main, "Your lodge") != null and button_named(main, "Buy a lodge here") == null, "the button is now the door")
	var house_parts: int = Kit.lodge_plan(city.faction, [], city.id).size()
	check(lodge_parts(main) == house_parts and house_parts > 0, "the lodge stands on the map, a house with no rooms (%d parts)" % lodge_parts(main))
	var lodge_node: Node3D = main._settlements3d._dioramas["lodge"]
	var town_node: Node3D = main._settlements3d._dioramas.get(city.id)
	main._settlements3d.reposition()
	check(town_node == null or lodge_node.position.x > town_node.position.x + main._settlements3d.footprint(city),
		"...beside the town, clear of its footprint")

	# --- the page: five rooms to build -------------------------------------
	button_named(main, "Your lodge").pressed.emit()
	await process_frame
	check(main._visit_page == "lodge" and said(main, "Riverhold, your lodge"), "the lodge page")
	check(buttons_named(main, "Build").size() == 5, "five Build rows (%d)" % buttons_named(main, "Build").size())
	check(said(main, "Build the herb garden (%d ◉)" % Lodge.ROOMS["garden"]["cost"]), "each names its room and its price")
	check(button_named(main, "Rest at the lodge (free)") != null, "the bed, free")
	check(button_named(main, "Town Square") != null, "and the way back")

	# --- build the garden: the diorama grows ---------------------------------
	var gold_before: int = party.gold
	row_button(main, "Build the herb garden").pressed.emit()
	await process_frame
	check(Lodge.has(party, "garden") and party.gold == gold_before - int(Lodge.ROOMS["garden"]["cost"]), "the garden is built and paid for")
	check(buttons_named(main, "Build").size() == 4 and said(main, "The herb garden"), "its Build row is now its own line")
	check(lodge_parts(main) == Kit.lodge_plan(city.faction, ["garden"], city.id).size() and lodge_parts(main) > house_parts,
		"the lodge on the map grew the garden (%d parts, was %d)" % [lodge_parts(main), house_parts])

	# --- the strongroom: deposit, the road's loss, withdraw -------------------
	row_button(main, "Build the strongroom").pressed.emit()
	await process_frame
	check(Lodge.has(party, "strongroom") and said(main, "The strongroom holds 0 ◉"), "the strongroom, empty")
	var dep := row_of(main, "Deposit")
	check(dep != null and row_option(dep).item_count == 4, "the deposit picker: 50, 100, 200 and all (%d)" % (row_option(dep).item_count if dep != null else -1))
	row_option(dep).select(row_option(dep).get_item_index(100))
	buttons(dep)[0].pressed.emit()
	await process_frame
	gold_before = party.gold
	check(Lodge.stored(party) == 100 and said(main, "The strongroom holds 100 ◉"), "100 ◉ in the strongroom")
	check(String(main._visit.get("log", "")) == "100 ◉ into the strongroom; it holds 100.", "the line: %s" % main._visit.get("log", ""))
	main._close_visit()
	main._retreat()
	check(party.gold == gold_before - roundi(gold_before * main.DEFEAT_GOLD_LOSS_PCT) and Lodge.stored(party) == 100,
		"beaten on the road: the purse pays its fifteenth, the strongroom keeps its 100")
	main._open_visit(city)
	await process_frame
	button_named(main, "Your lodge").pressed.emit()
	await process_frame
	var wd := row_of(main, "Withdraw")
	check(wd != null and row_option(wd).item_count == 3, "the withdraw picker: 50, 100 and all (%d)" % (row_option(wd).item_count if wd != null else -1))
	row_option(wd).select(row_option(wd).get_item_index(-1))
	gold_before = party.gold
	buttons(wd)[0].pressed.emit()
	await process_frame
	check(Lodge.stored(party) == 0 and party.gold == gold_before + 100, "withdrawn, all of it")
	check(String(main._visit.get("log", "")) == "100 ◉ out of the strongroom; it holds 0.", "the line: %s" % main._visit.get("log", ""))
	check(row_of(main, "Withdraw") == null, "an empty strongroom has nothing to withdraw")

	# --- the bed: free at the lodge ------------------------------------------
	gold_before = party.gold
	button_named(main, "Rest at the lodge (free)").pressed.emit()
	await process_frame
	check(party.gold == gold_before and "on the house" in String(main._visit.get("log", "")), "a night at the lodge costs nothing")
	check(Visit.inn_cost(city, party) == 0 and Visit.inn_cost(town, party) > 0, "the inn's price is the lodge's town's alone")
	if main._event_card != null:   # the fireside card over the bed
		main._on_inn_card_ack()
		await process_frame
	check(main._visit_page == "lodge" and not main._visit.is_empty(), "the lodge page is still up under it")

	# --- the yard: one general feat for another, the bed free ----------------
	var vera = party.get_member("vera")
	vera.feats.append("sentinel")
	vera.dirty()
	Downtime.decide_ability(vera, "sentinel")
	row_button(main, "Build the training yard").pressed.emit()
	await process_frame
	var yard := pickers_row(main, 3)
	check(yard != null and said(main, "Retrain %s in the yard (%d ◉, three days)" % [vera.cname, Lodge.RETRAIN_COST]), "the yard's row: who, the old feat, the new one")
	var old_pick := row_option(yard, 1)
	var new_pick := row_option(yard, 2)
	check(old_pick.item_count == 1 and String(old_pick.get_item_metadata(0)) == "sentinel", "the old-feat picker is the hero's general feats (%d)" % old_pick.item_count)
	for i in new_pick.item_count:
		if String(new_pick.get_item_metadata(i)) == "durable":
			new_pick.select(i)
	gold_before = party.gold
	var clock_before: float = w.clock.elapsed
	buttons(yard)[0].pressed.emit()
	await process_frame
	check("durable" in vera.feats and not "sentinel" in vera.feats, "the swap")
	check(party.gold == gold_before - Lodge.RETRAIN_COST, "the fee, and no bed to pay at the lodge (%d)" % (gold_before - party.gold))
	check(is_equal_approx(w.clock.elapsed, clock_before + Lodge.RETRAIN_DAYS * Downtime.DAY), "three days")
	check("puts down Sentinel for Durable" in String(main._visit.get("log", "")), "the row says so: %s" % main._visit.get("log", ""))
	check(pickers_row(main, 3) == null and said(main, "The training yard"), "once a visit: the row is a line until the next")

	# --- the garden after days away: potions on the step ---------------------
	# The yard's three days and the night's eight hours already count; the
	# garden's own clock says how many.
	main._close_visit()
	var had: int = party.stash_count(Lodge.GARDEN_POTION, true)
	w.clock.elapsed += Lodge.GARDEN_DAYS * Downtime.DAY
	var grown: int = mini(Lodge.GARDEN_CAP, int((w.clock.elapsed - float(party.lodge["garden_at"])) / (Lodge.GARDEN_DAYS * Downtime.DAY)))
	main._open_visit(city)
	await process_frame
	check(grown >= 1 and party.stash_count(Lodge.GARDEN_POTION, true) == had + grown, "home after days away: %d potions in the stash" % grown)
	check(("The garden has %s ready." % ("one potion" if grown == 1 else "%s potions" % Lodge.WORDS[grown])) in String(main._visit.get("log", "")),
		"and the square says so: %s" % main._visit.get("log", ""))

	# --- the shrine: the blessing on the way out -----------------------------
	main._close_visit()
	check(not party.blessed, "no shrine, no blessing")
	main._open_visit(city)
	await process_frame
	button_named(main, "Your lodge").pressed.emit()
	await process_frame
	row_button(main, "Build the shrine").pressed.emit()
	await process_frame
	check(Lodge.has(party, "shrine") and said(main, "The shrine"), "the shrine is built")
	main._close_visit()
	check(party.blessed and "shrine" in main._lair_msg.text, "leaving: the company carries the blessing (%s)" % main._lair_msg.text)

	# --- the label, and another town's square --------------------------------
	var marks: Array = main.ground_marks()
	check(marks.any(func(m): return m["pos"] == city.position and String(m["label"]).ends_with(" · your lodge")),
		"Riverhold's label says whose house is there")
	check(not marks.any(func(m): return m["pos"] == town.position and "lodge" in String(m["label"])), "Greenmarch's does not")
	main._open_visit(town)
	await process_frame
	check(said(main, "The company's lodge is at Riverhold."), "another square points home")
	check(button_named(main, "Buy a lodge here") == null and button_named(main, "Your lodge") == null, "one lodge only")
	main._close_visit()

	print("test_world_lodge: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
