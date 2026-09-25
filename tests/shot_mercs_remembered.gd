# Dev-only: the proof shots for docs/plan/2026-09-25-mercs-remembered.md — the
# profile's Service panel and an earned trait's origin line, the spoils page
# crediting who struck the blow (and a friend's grief), the roll of the fallen
# on the lodge's wall and on the party page, the fire's line about the dead,
# and the inn's chairs with their intros and a veteran's record. Needs a
# display (the world renders 3D); not part of run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 1600x1200x24" godot --path . --resolution 1600x1200 -s tests/shot_mercs_remembered.gd
#     -> docs/shots/mercs-remembered-service.png   the Service panel, and "Earned on day 4: ..." under a trait
#     -> docs/shots/mercs-remembered-spoils.png    "struck by Pike Sallow ×2", the death, the grief
#     -> docs/shots/mercs-remembered-fire.png      the first fire after: a mourner says the name
#     -> docs/shots/mercs-remembered-lodge.png     the roll of the fallen on the lodge page
#     -> docs/shots/mercs-remembered-party.png     ...and under the roster on the party page
#     -> docs/shots/mercs-remembered-inn.png       the inn's chairs: an intro each, a veteran's record
extends SceneTree

const Traits = preload("res://core/traits.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Recruits = preload("res://core/recruits.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const World = preload("res://core/world.gd")

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-mercs-%d" % randi())
	OS.set_environment("SORCMERC_FAST", "1")
	await process_frame

	# --- the profile: a hero with a record --------------------------------------
	var ch = Presets.vera(5)
	ch.trait_counts = {"fights": 31, "wins": 17, "downed:orc": 2, "downed:goblinoid": 1,
		"kill:goblinoid": 12, "kill:orc": 7, "kill:beast": 3, "kill:dragon": 1}
	Traits.grant(ch, "bane@goblinoid", "10 goblins killed", 1440.0 * 3 + 300.0)
	Traits.grant(ch, "hardened", "Lost Ilsa Vane", 1440.0 * 8 + 90.0)
	var prof = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(prof)
	prof.set_character(ch)
	for _i in 8:
		await process_frame
	await _save("docs/shots/mercs-remembered-service.png")
	prof.queue_free()
	await process_frame

	# --- the world: a fight where Vera dies and Pike strikes the blows ----------
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()
	s.world.clock.elapsed = 1440.0 * 5 + 600.0
	var party = s.party
	var vera = party.party_characters()[0]
	var pike = party.party_characters()[1]
	# lovers, written straight in: answer_courtship's achievement toast would sit over the shots
	party.relations[PartyOpinion.key(vera.id, pike.id)] = {"score": 70.0, "status": "lovers"}
	var result := {"outcome": "Victory", "xp": 150, "gold": 12, "loot": [], "kills": ["goblin", "goblin", "goblin-boss", "wolf"],
		"deaths": [vera.id], "downed": [vera.id], "rounds": 4, "objective": {},
		"credit": {pike.id: {"kills": ["goblin", "goblin", "goblin-boss"], "downed_by": [], "revived_by": []},
			vera.id: {"kills": ["wolf"], "downed_by": [{"by": "goblin-boss", "team": "foe", "dtype": "slashing"}], "revived_by": []}}}
	s._earn_from_fight(result, "normal", "road")
	s._apply_deaths(result)
	s._show_spoils(result)
	for _i in 10:
		await process_frame
	await _save("docs/shots/mercs-remembered-spoils.png")
	s._close_spoils()
	s._moment_queue.clear()
	s.world.clock.pause()
	for _i in 4:
		await process_frame

	# --- the first fire after ----------------------------------------------------
	s._fireside(RNG.new(1), func(): pass)
	for _i in 10:
		await process_frame
	await _save("docs/shots/mercs-remembered-fire.png")
	if s._event_card != null:
		s._on_event_ack()
	s.world.clock.pause()
	for _i in 4:
		await process_frame

	# --- the lodge's wall ---------------------------------------------------------
	var home = s.world.settlements[0]
	party.lodge = {"settlement_id": home.id, "rooms": ["strongroom"], "gold": 0, "garden_at": -1.0,
		"maproom_at": -1.0, "retrained": {}, "blessed_at": -1.0}
	s._open_visit(home)
	s._goto_page("lodge")
	for _i in 10:
		await process_frame
	await _scroll_to(s, "The roll of the fallen")
	await _save("docs/shots/mercs-remembered-lodge.png")
	s._close_visit()
	s.world.clock.pause()
	for _i in 4:
		await process_frame

	# --- the party page -------------------------------------------------------------
	var page = load("res://scenes/party/party.tscn").instantiate()
	page.party = party
	root.add_child(page)
	for _i in 10:
		await process_frame
	await _save("docs/shots/mercs-remembered-party.png")
	page.queue_free()
	await process_frame

	# --- the inn: a veteran in the first chair --------------------------------------
	var old = Presets.pike(1)
	old.id = "old-hand"
	old.cname = "Garrow Tallis"
	old.trait_counts = {"runs": 2, "fights": 27, "wins": 22, "kill:goblinoid": 9, "kill:bandit": 6}
	old.traits.append({"id": "burn-shy", "why": "Went down in the fire", "since": 900.0})
	CharacterSave.save(old)
	var city = null
	for t in s.world.settlements:
		if t.kind == "city":
			city = t
	for day in 60:
		s.world.clock.elapsed = 10.0 + Recruits.PERIOD * day
		if Recruits.offers(city, s.world, party).any(func(o): return String(o["veteran"]) == "old-hand"):
			break
	s.world.clock.pause()
	party.gold = 500   # so each chair's last line is who they are, not the purse's shortfall
	s._open_visit(city)
	s._goto_page("inn")
	for _i in 10:
		await process_frame
	await _scroll_to(s, "Looking for work")
	await _save("docs/shots/mercs-remembered-inn.png")
	CharacterSave.delete("old-hand")
	quit()

# Bring the label reading `text` to the top of the scrolling list it is in.
func _scroll_to(s, text: String) -> void:
	for l in s.find_children("*", "Label", true, false):
		if String(l.text) == text:
			for sc in s.find_children("*", "ScrollContainer", true, false):
				if sc.is_ancestor_of(l):
					sc.scroll_vertical = maxi(0, int(l.global_position.y - sc.global_position.y) + sc.scroll_vertical - 8)
	for _i in 4:
		await process_frame

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
