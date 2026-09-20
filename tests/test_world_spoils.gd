# Issue #30: "no loot page after both won combat and finished lair".
#
# A won fight on the map paid in silence. The combat screen writes its own
# after-action lines — "+400 XP, +50 gold", "Taken from the dead: a handaxe" —
# but out here the screen is torn down the frame `result` is filled, so nobody
# ever read them. All that survived was one line on the HUD's lair label, which
# the next frame's button text could overwrite. The linear campaign never had
# the problem: it holds the fight screen up behind a "Back to the road" button.
#
#   godot --headless --path . -s tests/test_world_spoils.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Site = preload("res://core/site.gd")

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
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func key(main, code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	main._unhandled_key_input(ev)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	# --- a won fight out on the road ------------------------------------
	var p = main.world.player()
	var foe = World.RoamingParty.new("bandits-test", p.position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe)
	main._launch_combat(foe)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	check(main._combat != null, "the fight opened")
	main._combat.result = {"outcome": "Victory", "xp": 400, "gold": 50,
		"loot": ["handaxe"], "kills": [], "deaths": []}
	for i in 8:
		await process_frame

	check(main._combat == null, "the fight screen is torn down")
	check(main._spoils_panel != null, "...and a spoils page takes its place")
	check(main.world.clock.is_paused(), "which holds the clock until it is read")
	check(said(main._spoils_panel, "Victory"), "it says who won")
	check(said(main._spoils_panel, "+400 XP"), "it says what the XP was")
	check(said(main._spoils_panel, "+50 gold"), "it says what the purse got")
	check(said(main._spoils_panel, "Handaxe") or said(main._spoils_panel, "handaxe"),
		"it names what came off the bodies (%s)" % str(labels(main._spoils_panel)))
	var on := buttons(main._spoils_panel)
	check(on.size() == 1 and "Back to the map" in on[0].text, "one way on")

	# Esc takes it, and the world runs again.
	key(main, KEY_ESCAPE)
	await process_frame
	check(main._spoils_panel == null, "Esc dismisses it")
	# #98: the map waits for an order rather than running on into the next band
	check(main.world.clock.is_paused() and main._halted_on_arrival, "and the map waits, halted, for the next order")
	check(main._pause_btn.text == "Resume", "...with the HUD button agreeing")
	main.world.set_goal(main.world.player(), main.world.player().position + Vector2(300, 0))
	await process_frame
	check(not main.world.clock.is_paused(), "a new destination sets it running again")

	# --- a lost one says what it cost -----------------------------------
	var foe2 = World.RoamingParty.new("bandits-test-2", main.world.player().position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe2)
	main._launch_combat(foe2)
	guard = 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	main._combat.result = {"outcome": "Defeat", "xp": 0, "gold": 0, "loot": [], "kills": [], "deaths": []}
	for i in 8:
		await process_frame
	check(main._spoils_panel != null, "a lost fight gets a page too")
	check(said(main._spoils_panel, "Defeat"), "...headed as one")
	check(not said(main._spoils_panel, "+0 XP"), "...and does not claim a haul")
	main._close_spoils()
	await process_frame

	# --- and a whole delve totals itself --------------------------------
	var lair = main.world.lairs[0]
	lair.discovered = true
	main.world.player().position = lair.position
	var gold0: int = main.party.gold
	main._delve(lair)
	for i in 4:
		await process_frame
	check(main._site != null, "the delve opened")
	check(not main._delve_haul.is_empty(), "...and started counting")
	check(int(main._delve_haul["gold0"]) == gold0, "from the purse it walked in with")

	# Bank a room's fight the way _on_site_room_chosen does.
	main._bank({"outcome": "Victory", "xp": 120, "gold": 30, "loot": ["shortsword"], "kills": []})
	check(int(main._delve_haul["xp"]) == 120, "a room's XP joins the running total")
	check(int(main._delve_haul["fights"]) == 1, "...and its fight is counted")
	check((main._delve_haul["loot"] as Array).has("shortsword"), "...and its loot listed")

	# Reaching the bottom pays on top of the rooms — every fight on the way down
	# already paid its own, and a delve used to be worth strictly less than the
	# same fights out on the road.
	var bonus: int = Site.clear_xp(lair)
	check(bonus > 0, "clearing a lair is worth something (%d)" % bonus)
	var xp0: int = main.party.party_characters()[0].xp
	main._site.state = "cleared"
	main._on_site_done()
	for i in 4:
		await process_frame
	check(main.party.party_characters()[0].xp > xp0, "...and it lands on the party")
	check(main._spoils_panel != null, "finishing the lair opens the delve's page")
	check(said(main._spoils_panel, "cleared out"), "headed with what happened to it")
	check(said(main._spoils_panel, "+%d XP" % (120 + bonus)), "totalling the XP of the whole descent")
	check(said(main._spoils_panel, "for reaching the bottom"), "...and saying which part was the clear")
	check(said(main._spoils_panel, "+%d gold" % (main.party.gold - gold0)),
		"and every place it paid from, read off the purse")
	check(main._delve_haul.is_empty(), "the running total is closed out")
	main._close_spoils()
	await process_frame

	# Withdrawing keeps what the rooms paid and nothing else — that is the whole
	# tension of deciding to turn back.
	main._delve(main.world.lairs[0])
	for i in 4:
		await process_frame
	var xp1: int = main.party.party_characters()[0].xp
	main._site.state = "withdrawn"
	main._on_site_done()
	for i in 4:
		await process_frame
	check(main.party.party_characters()[0].xp == xp1, "walking back out pays no clear bonus")
	check(main._spoils_panel != null, "it still gets a page")
	check(not said(main._spoils_panel, "for reaching the bottom"), "...that does not claim one")
	main._close_spoils()
	await process_frame

	# A wipe is not a haul: _site_wiped() has already said what it cost.
	main._delve(main.world.lairs[0])
	for i in 4:
		await process_frame
	main._site.state = "wiped"
	main._on_site_done()
	for i in 4:
		await process_frame
	check(main._spoils_panel == null, "a party dragged out of a lair gets no spoils page")
	check(main._delve_haul.is_empty(), "...and the running total is dropped anyway")

	print("test_world_spoils: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
