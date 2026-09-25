# Mercs remembered on the world screen (the design audit,
# docs/audit-game-design.md §2.1, §2.2, §2.5): a road fight where one of the
# company dies and a friend strikes the blows — the spoils page credits the
# killer on each kill and says the grief, the dead go on the roll of the
# fallen with where they fell, the next fire speaks of them once, the lodge's
# wall and the party page list them, and the inn's chairs each carry a line
# of who they are. Drives the real world scene. Headless.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_fallen.gd
extends SceneTree

const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Recruits = preload("res://core/recruits.gd")
const Service = preload("res://core/service.gd")
const Ach = preload("res://core/achievements.gd")

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
	return labels(node).any(func(l): return text in l)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/fallen-world-%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var party = main.party
	var dead = party.party_characters()[0]
	var friend = party.party_characters()[1]
	PartyOpinion.set_score(party, dead.id, friend.id, 60.0)   # bonded
	var deaths0 := Ach.count("deaths")

	# --- a road fight: the friend kills two goblins, and the other dies -------------
	var p = main.world.player()
	var foe = World.RoamingParty.new("goblins-test", p.position + Vector2(10, 0), "goblinoid")
	main.world.parties.append(foe)
	main._launch_combat(foe)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	check(main._combat != null, "the fight opened")
	main._combat.result = {"outcome": "Victory", "xp": 100, "gold": 5, "loot": [], "kills": ["goblin", "goblin"],
		"deaths": [dead.id], "downed": [dead.id], "rounds": 1, "objective": {},
		"credit": {friend.id: {"kills": ["goblin", "goblin"], "downed_by": [], "revived_by": []},
			dead.id: {"kills": [], "downed_by": [{"by": "goblin", "team": "foe", "dtype": "slashing"}], "revived_by": []}}}
	for i in 8:
		await process_frame
	check(main._spoils_panel != null, "the spoils page is up")
	check(said(main._spoils_panel, "struck by %s ×2" % friend.cname),
		"each kill says who struck the blow: %s" % str(labels(main._spoils_panel).filter(func(l): return "Goblin" in l)))
	check(said(main._spoils_panel, "%s did not get up." % dead.cname), "the death is said")
	check(labels(main._spoils_panel).any(func(l): return l.begins_with(friend.cname + " ") and "vs DC" in l),
		"...and the friend's grief, a save always asked: %s" % str(labels(main._spoils_panel)))
	check(dead.dead and not party.is_active(dead.id), "the dead are dead and benched")
	check(Ach.count("deaths") == deaths0 + 1, "an open-world death counts toward The Cost of Doing Business")
	check(party.fallen.size() == 1 and String(party.fallen[0]["where"]).begins_with("on the road near "),
		"on the roll, with where: %s" % str(party.fallen))
	check(String(party.fallen[0]["by"]) == "goblin" and int(party.fallen[0]["day"]) >= 1, "...to what, and the day")
	main._close_spoils()
	main._moment_queue.clear()
	await process_frame

	# --- the next fire speaks of them, once ---------------------------------------------
	var spoke: bool = main._fireside(RNG.new(1), func(): pass)
	check(spoke and main._event_card != null and String(main._event_card._e.get("id", "")) == "camp-fallen",
		"the first fire after a death is about the dead")
	check(main._event_card != null and String(main._event_card._e.get("text", "")).contains(dead.cname)
		and String(main._event_card._e.get("text", "")).begins_with(friend.cname),
		"...a mourner at the fire says the name: %s" % (String(main._event_card._e.get("text", "")) if main._event_card != null else ""))
	main._on_event_ack()
	main._fireside(RNG.new(1), func(): pass)
	check(main._event_card == null or String(main._event_card._e.get("id", "")) != "camp-fallen", "...and only once")
	if main._event_card != null:
		main._on_event_ack()

	# --- the lodge's wall -----------------------------------------------------------------
	var s = main.world.settlements[0]
	party.lodge = {"settlement_id": s.id, "rooms": [], "gold": 0, "garden_at": -1.0, "maproom_at": -1.0,
		"retrained": {}, "blessed_at": -1.0}
	var box := VBoxContainer.new()
	root.add_child(box)
	main._build_lodge_page(box, s)
	check(said(box, "The roll of the fallen"), "the lodge page has the roll")
	check(said(box, "%s, " % dead.cname) and said(box, "Fell to a goblin on the road near"),
		"...with the dead's line: %s" % str(labels(box).filter(func(l): return "Fell" in l)))
	box.queue_free()
	party.lodge = {}

	# --- the party page -------------------------------------------------------------------
	var page = load("res://scenes/party/party.tscn").instantiate()
	page.party = party
	root.add_child(page)
	await process_frame
	check(said(page, "The fallen · 1"), "the party page lists the fallen under the roster")
	check(said(page, "Fell to a goblin"), "...with where and to what")
	page.queue_free()

	# --- the inn: who each chair is --------------------------------------------------------
	var city = null
	for t in main.world.settlements:
		if t.kind == "city":
			city = t
	var inn := VBoxContainer.new()
	root.add_child(inn)
	main._hiring_rows(inn, city)
	var offers: Array = Recruits.offers(city, main.world, party)
	check(not offers.is_empty(), "somebody is looking for work")
	for o in offers:
		var ch = Recruits.build(o)
		check(Recruits.intro(ch) != "" and said(inn, Recruits.intro(ch)), "each chair carries its intro: %s" % Recruits.intro(ch))
	inn.queue_free()

	print("test_world_fallen: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)
