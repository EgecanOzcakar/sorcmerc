# Callings on the world screen (docs/superpowers/specs/2026-09-21-callings-
# relations-design.md §2–§3): assigned the frame the map is up, told at the
# first fire — the target marked under the card — read on the quest log and
# the party page, done and paid on the road (in the same save the doing
# makes, so a quit at the outcome card loses nothing), and said on a card of
# its own the moment the outcome card is down — or the visit it was done at
# is left, which is where a past told at the inn of the very town it names
# is done. The fire that has nobody left to tell says something else.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_callings.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Landmarks = preload("res://core/landmarks.gd")
const Callings = preload("res://core/callings.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const WorldSave = preload("res://core/world_save.gd")
const Visit = preload("res://core/settlement_visit.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const RNG = preload("res://core/rng.gd")

const AMULET := "amulet-of-proof-against-detection-and-location"

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func _card_id(main) -> String:
	return String(main._event_card._e.get("id", "")) if main._event_card != null else ""

# One camp: the rest is owed again, the night is roped, and whatever card was
# up from last time is waved away first.
func _camp(main) -> void:
	if main._event_card != null:
		main._on_event_ack()
	main.world.clock.pause()
	main.party.safe_camp = true
	main.party.last_long_rest_at = -99999.0
	_quiet_night(main)
	main._make_camp()
	main._last_travel_at = main.world.clock.elapsed   # the night spent the road-event clock; keep the road quiet
	await process_frame

# Since the design audit's §1.6 a roped camp can still be jumped (Rope Trick
# is only the kit), and since §1.7 nobody camps with a hostile band in reach —
# and the walked nights bring the map's hunters to the town beside the camp.
# Neither is what this test is about: the clock is nudged to a minute whose
# camp seed rolls a quiet night (the camp integration test's own search), and
# a band standing on the camp is sent off the map.
func _quiet_night(main) -> void:
	var here: Vector2 = main.world.player().position
	for q in main.world.parties.duplicate():
		if not q.is_player and q.position.distance_to(here) < 300.0:
			main.world.parties.erase(q)
	while WorldCamp.ambush_roll(RNG.new(WorldCamp.camp_seed(main.world.clock.elapsed, here))):
		main.world.clock.elapsed += 1.0

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# An acolyte leading, a charlatan second, nobody else with a past — the
	# presets carry backgrounds of their own, and each would be handed a
	# calling too. The first frame has already dealt from those, so the deal
	# is wiped and made again.
	var party = main.party
	var w = main.world
	var p = w.player()
	var hero = party.roster[0]
	var mate = party.get_member(party.active[1])
	check(party.active[0] == hero.id, "the first of the roster leads the march")
	for id in party.active:
		party.get_member(id).background_id = {hero.id: "acolyte", mate.id: "charlatan"}.get(id, "")
	party.callings.clear()
	for l in w.landmarks:
		if l.kind == "shrine":
			l.spent = true
	# Out past VISION_RADIUS and clear of every beacon and the lake: hidden until told.
	var shrine = w.add_landmark(World.Landmark.new("t-shrine", "shrine", Vector2(80, -300)))
	for i in 10:
		await process_frame

	# --- assigned on the map, untold ---
	check(party.callings.has(hero.id) and party.callings[hero.id]["target_id"] == "t-shrine"
		and party.callings[hero.id]["state"] == "", "the acolyte is handed the shrine the frame the map is up")
	var town = w.settlements.filter(func(s): return s.id == "greenmarch")[0]
	check(party.callings.has(mate.id) and party.callings[mate.id]["target_id"] == town.id, "the charlatan is handed the town")
	check(not shrine.found, "...and the shrine stays hidden until the telling")
	check(Callings.describe(party, hero.id) == "", "untold: no line yet")

	# --- told at the fire: the beat outranks the moment, and marks the map ---
	await _camp(main)
	check(_card_id(main) == "calling-acolyte", "the first fire is the telling: %s" % _card_id(main))
	if main._event_card != null:
		check(shrine.sname in String(main._event_card._e.get("text", "")), "the tell names the shrine")
		check(String(main._event_card._e.get("title", "")) == Callings.TEMPLATES["acolyte"]["title"], "titled by the template")
	check(shrine.found and w.is_explored(shrine.position), "the shrine is on the map now, its ground revealed so it draws")
	check(party.callings[hero.id]["state"] == "told" and w.clock.is_paused(), "told, and the card holds the clock")
	main._on_event_ack()
	await process_frame
	check(main._event_card == null and not w.clock.is_paused(), "acked: card down, clock running")

	# --- read: the quest log and the party page say the same line ---
	var line := Callings.describe(party, hero.id)
	check("told, marked on the map" in line, "describe: %s" % line)
	main._toggle_quests()
	await process_frame
	check(said(main._quest_panel, "Callings") and said(main._quest_panel, line), "the quest log has a Callings section with the line")
	main._close_quests()
	var screen = load("res://scenes/party/party.tscn").instantiate()
	screen.party = party
	root.add_child(screen)
	await process_frame
	var rel: Array = labels(_named(screen, "CallingsRow"))
	check(rel.size() > 0 and rel[0] == "Callings" and rel.size() > 1 and hero.cname in rel[1] and line in rel[1],
		"the party page's Callings caption and line: %s" % str(rel.slice(0, 2)))
	screen.queue_free()
	await process_frame

	# --- done on the road: the row answered, the outcome acked, then the resolution ---
	p.position = shrine.position
	for i in 3:
		await process_frame
	main.party.gold = 500
	main._open_place(shrine)
	await process_frame
	var opts: Array = Landmarks.options(shrine, party, w)
	check(main._approach_card != null and opts.size() > 1, "the shrine asks (%d rows)" % opts.size())
	var xp_before: int = hero.xp
	# She will roll it herself, so the bond goes to whoever stands closest to her.
	var closest := Callings._closest(party, hero.id)
	var score_before: float = PartyOpinion.score(party, hero.id, closest)
	main._on_place_chosen(String(opts[0]["id"]))
	await process_frame
	check(_card_id(main).begins_with("landmark-shrine-"), "the outcome first: %s" % _card_id(main))
	var who := String(main._event_card._e.get("char_id", "")) if main._event_card != null else ""
	check(who == hero.id, "the acolyte rolls Religion at her own shrine: %s" % who)
	check(shrine.spent and main._calling_queue.size() == 1, "the calling's card waits behind the outcome card")
	# ...but the past is already paid, and already in the save the answer made:
	# a quit here loses the card, never the amulet or the bond.
	check(party.callings[hero.id]["state"] == "done" and party.stash_count(AMULET, true) == 1,
		"done and paid before the outcome card is acked")
	check(String(WorldSave.to_dict(w, party)["party"]["callings"][hero.id]["state"]) == "done",
		"...and the save already says so")
	main._on_event_ack()
	w.clock.pause()   # the player's own pause, the moment the card is down: the map is standing still
	for i in 3:
		await process_frame
	check(_card_id(main) == "calling-acolyte", "then the resolution, on its own card: %s" % _card_id(main))
	if main._event_card != null:
		var e: Dictionary = main._event_card._e
		check(String(e.get("text", "")) == Callings.TEMPLATES["acolyte"]["done"] % shrine.sname, "the done line names the shrine")
		check(int(e.get("xp", 0)) == Callings.CALLING_XP and String(e.get("item_name", "")) != "", "the XP chip and the heirloom on the card")
		check(String(e.get("kind", "")) == "good" and w.clock.is_paused(), "a good card, holding the clock")
	check(party.stash_count(AMULET, true) == 1, "the amulet, identified, in the stash")
	check(hero.xp > xp_before, "paid")
	check(party.callings[hero.id]["state"] == "done" and "done" in Callings.describe(party, hero.id), "describe says done")
	check(closest != "" and PartyOpinion.score(party, hero.id, closest) == score_before + PartyOpinion.CALLING_BOND,
		"she did it herself: the bond goes to the companion closest to her (%s)" % closest)
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._calling_queue.is_empty() and main._event_card == null, "acked: nothing queued, card down")
	check(w.clock.is_paused(), "...and a map that was standing still is left standing (#98)")

	# --- the inn's fire tells the second hero, in the very town her past names:
	# the gate was walked before she spoke, so the rest asks again, and the
	# card waits for the visit to close ---
	p.position = town.position
	main._open_visit(town)
	await process_frame
	check(not main._visit.is_empty() and main._calling_queue.is_empty() and party.callings[mate.id]["state"] == "",
		"walking in untold does nothing")
	party.gold = Visit.inn_cost(town) + 1
	party.last_long_rest_at = -99999.0
	score_before = PartyOpinion.score(party, mate.id, hero.id)
	main._rest()
	await process_frame
	check(_card_id(main) == "calling-charlatan", "the inn's fire tells the charlatan's: %s" % _card_id(main))
	if main._event_card != null:
		check(town.sname in String(main._event_card._e.get("text", "")), "the tell names this town")
	check(party.callings[mate.id]["state"] == "done" and main._calling_queue.size() == 1,
		"told here, done here: paid at once, the card waiting behind the visit")
	check(PartyOpinion.score(party, mate.id, hero.id) == score_before + PartyOpinion.CALLING_BOND,
		"the bond with the leader who walked her in")
	main._event_card.acknowledged.emit()
	await process_frame
	check(main._event_card == null and not main._visit.is_empty(), "the telling acked: the visit is still up, no second card over it")
	main._close_visit()
	for i in 3:
		await process_frame
	check(_card_id(main) == "calling-charlatan", "the visit closed: the resolution comes down: %s" % _card_id(main))
	check("done" in Callings.describe(party, mate.id), "describe says done")
	main._on_event_ack()
	await process_frame

	# --- a third fire has nothing to tell ---
	await _camp(main)
	check(not _card_id(main).begins_with("calling-"), "the third camp is not a calling: %s" % _card_id(main))
	if main._event_card != null:
		main._on_event_ack()
	if main._approach_card != null:
		main._approach_card.chosen.emit("decline")
		await process_frame
		if main._event_card != null:
			main._on_event_ack()

	# --- the band, and the hero who does not walk away from it ---------------
	# core/callings.gd has always refused a dead hero's past ("the bond and the
	# line are theirs to have"), and never got the chance to say so out here:
	# _launch_combat ran the band_beaten check up in its victory branch, several
	# lines ahead of _apply_deaths, so nobody in the fight was dead yet and the
	# one hero who fell putting their own band down was paid anyway.
	var third = party.get_member(String(party.active[2]))
	third.background_id = "soldier"
	var band = World.RoamingParty.new("t-deserters", p.position + Vector2(10, 0), "bandit")
	w.parties.append(band)
	party.callings[third.id] = {"id": "soldier", "target_kind": "band", "target_id": band.id,
		"state": "told", "told_at": w.clock.elapsed}
	check(await _open_fight(main, band), "the band fight opened")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [],
		"deaths": [third.id], "objective": {}})
	check(third.dead and not party.is_active(third.id), "the hero fell in the fight that beat their band")
	check(party.callings[third.id]["state"] == "told" and main._calling_queue.is_empty(),
		"...so the past is not paid: still told, no card queued")
	main._close_spoils()
	await process_frame

	# ...and the same fight, walked away from, does pay.
	third.dead = false
	party.activate(third.id)
	var band2 = World.RoamingParty.new("t-deserters-2", p.position + Vector2(10, 0), "bandit")
	w.parties.append(band2)
	party.callings[third.id]["target_id"] = band2.id
	var xp_was: int = third.xp
	check(await _open_fight(main, band2), "the rematch opened")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [],
		"deaths": [], "objective": {}})
	check(party.callings[third.id]["state"] == "done", "the survivor's past completes")
	check(third.xp > xp_was, "...and is paid")
	main._close_spoils()
	await process_frame

	print("test_world_callings: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The world screen's own fight hand-off, driven the way tests/test_world_
# objectives.gd drives it: put the overlay up, then fill `result` by hand
# rather than autoplaying a board nobody is asserting on.
func _open_fight(main, foe) -> bool:
	main._launch_combat(foe)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	return main._combat != null

func _finish(main, result: Dictionary) -> void:
	main._combat.result = result
	for i in 8:
		await process_frame

func _named(node: Node, want: String) -> Node:
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if c.name == want:
			return c
		var hit := _named(c, want)
		if hit != null:
			return hit
	return null
