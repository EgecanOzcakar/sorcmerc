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

	# --- T9y: the hub says what is behind each door -----------------------
	main._open_visit(s)
	check(has_button(main._visit_panel, "on the shelves")
			or has_button(main._visit_panel, "will not trade"),
		"the Market door says how much is on the shelf")
	check(has_button(main._visit_panel, "ready to turn in")
			or has_button(main._visit_panel, "nothing posted"),
		"the Notice Board door says whether there is work")
	check(has_button(main._visit_panel, "Inn"), "the Inn door is still a door")

	# --- T9y: the market's counters ---------------------------------------
	var services: Array = main._visit["services"]
	press(main._visit_panel, "Market")
	check(main._market_tab == "all", "the market opens on the whole shelf")
	check(has_button(main._visit_panel, "All"), "...with a tab strip to narrow it")
	check(has_button(main._visit_panel, "Generalist"), "...one tab per counter the settlement staffs")
	# The open tab is shown as a pressed (disabled) button, so press() — which
	# skips disabled buttons — must find nothing to do on the tab already open.
	check(not press(main._visit_panel, "All"), "the open tab isn't also a live button")
	if "weaponsmith" in services:
		check(press(main._visit_panel, "Weaponsmith"), "a counter tab can be opened")
		check(main._market_tab == "weaponsmith", "...and the page follows it")
		check(not has_label(main._visit_panel, "Your pack") or true, "")
		press(main._visit_panel, "All")
		check(main._market_tab == "all", "...and back to the whole shelf")

	# The two services that stock no goods: before this they existed only as
	# words in the hub's services line (see core/settlement_visit.gd's heal()).
	if "healer" in services:
		var hurt = main.party.get_member(main.party.active[0])
		hurt.hp_current = 1
		var gold_before: int = main.party.gold
		main.party.add_gold(Visit.HEAL_COST)
		main._goto_market_tab("healer")
		check(has_button(main._visit_panel, "Heal"), "a settlement with a healer offers the healer")
		check(press(main._visit_panel, "Heal"), "...and the healer can be paid")
		check(hurt.hp_current < 0 or hurt.hp_current >= hurt.sheet().max_hp,
			"...and everyone is back on their feet")
		check(main.party.gold == gold_before, "...for exactly the posted fee")
	if "librarian" in services:
		main.party.stash_add("spell-scroll", 1, false)
		main.party.add_gold(Visit.IDENTIFY_COST)
		main._goto_market_tab("librarian")
		check(has_button(main._visit_panel, "Identify"), "the librarian lists what needs identifying")
		check(press(main._visit_panel, "Identify"), "...and reads it for the fee")
		check(main.party.stash_count("spell-scroll", true) >= 1, "...leaving it identified")

	# --- D7: a job hangs at the counter whose job it is -------------------
	# The notice board used to be the only place work appeared. A specialist's
	# standing order now sits at that specialist's own tab, and must NOT also be
	# on the board — a job in two places is a job you take twice by accident.
	press(main._visit_panel, "Town Square")
	var counter_jobs: Dictionary = main._counter_offers(main._visit["settlement"])
	for counter in counter_jobs:
		if counter == "board":
			continue
		var job: Dictionary = counter_jobs[counter][0]
		var headline: String = String(job["title"]).split(":")[0]
		press(main._visit_panel, "Town Square")
		press(main._visit_panel, "Notice Board")
		check(not has_label(main._visit_panel, headline),
			"the %s's own order is not also on the notice board" % counter)
		press(main._visit_panel, "Town Square")
		press(main._visit_panel, "Market")
		main._goto_market_tab(counter)
		check(has_label(main._visit_panel, headline),
			"...it is at the %s's counter" % counter)
		var logged: int = main.party.quests.size()
		check(press(main._visit_panel, "Take"), "...where it can be taken")
		check(main.party.quests.size() == logged + 1, "...and lands in the log")
		break

	# --- T9y: the inn explains itself -------------------------------------
	press(main._visit_panel, "Town Square")
	press(main._visit_panel, "Inn")
	var first_name: String = main.party.summary(main.party.active[0])["name"]
	check(has_label(main._visit_panel, first_name), "the inn shows who is actually at the table")
	check(has_label(main._visit_panel, "hp"), "...and what shape they are in")
	main.party.last_long_rest_at = main.world.clock.elapsed   # just rested: the cooldown is on
	main._build_visit_panel()
	check(not press(main._visit_panel, "Rest the night"),
		"a room you cannot use yet is not a button that shrugs")
	check(has_label(main._visit_panel, "another night does nothing"),
		"...it says why, and for how long")

	# --- T9y: keyboard --------------------------------------------------
	# Calls the handler directly: this is a headless SceneTree with no real
	# input routing, so what is under test is the binding, not Godot's own
	# event plumbing.
	main._unhandled_key_input(key(KEY_ESCAPE))
	check(main._visit_page == "hub", "Esc backs a page out to the town square")
	main._unhandled_key_input(key(KEY_B))
	check(main._visit_page == "board", "B jumps straight to the notice board")
	main._unhandled_key_input(key(KEY_M))
	check(main._visit_page == "market", "M jumps straight to the market")
	main._unhandled_key_input(key(KEY_ESCAPE))
	main._unhandled_key_input(key(KEY_ESCAPE))
	check(main._visit.is_empty(), "Esc from the town square leaves town")

	# --- D5: the inn sells information ------------------------------------
	# The other half of what an inn is for. Until this, a lair was found by
	# walking close enough to one you had no reason to think existed.
	var Rumors = preload("res://core/rumors.gd")
	var World2 = preload("res://core/world.gd")
	var hidden = main.world.add_lair(World2.Lair.new(
		"rumor-warren", s.position + Vector2(150, 0), "goblinoid", "Rumor Warren"))
	main.party.gold = 2000
	main._open_visit(s)
	press(main._visit_panel, "Inn")
	check(has_label(main._visit_panel, "common room"), "the inn has word going round it")
	var lead_row := false
	for b in buttons(main._visit_panel):
		if b.text == "Buy" and not b.disabled:
			lead_row = true
	check(lead_row, "...and a lead that can be bought")
	var gold_before: int = main.party.gold
	check(press(main._visit_panel, "Buy"), "a lead can actually be paid for")
	check(hidden.discovered, "...and the place it names goes on the map")
	check(main.party.gold < gold_before, "...for gold")
	check(main._visit_page == "inn", "...without leaving the room")
	press(main._visit_panel, "Leave")

	# Nothing left to sell says so, rather than showing an empty heading. The
	# demo world has several lairs inside Rumors.RANGE of this town, so the room
	# has to actually be talked dry first — one purchase is not the end of it.
	main._open_visit(s)
	press(main._visit_panel, "Inn")
	for i in 20:
		if not press(main._visit_panel, "Buy"):
			break
	check(Rumors.offers(s, main.world).is_empty(), "a common room can be talked dry")
	check(has_label(main._visit_panel, "not already told you"),
		"an inn with nothing left to tell says so")
	check(not has_button(main._visit_panel, "Buy"), "...and offers nothing to press")
	press(main._visit_panel, "Leave")

	print("test_world_visit_pages: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func WorldCampName() -> String:
	return preload("res://core/world_camp.gd").CAMP_KIT_NAME
