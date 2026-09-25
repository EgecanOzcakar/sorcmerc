# The fireside on the world screen (spike-party-opinions §9 row 6): a safe
# night can end in a warming or a quarrel on the camp's card, or — for a pair
# that is past bonded — a question on the approach card, answered by the
# player and reported on a card of its own. The plain night is still there
# when the fire has nothing to say, and the inn asks the same question over
# the visit without letting go of its clock.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_fireside.gd
extends SceneTree

const PartyOpinion = preload("res://core/party_opinion.gd")
const Visit = preload("res://core/settlement_visit.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _set_all(party, v: float) -> void:
	for p in PartyOpinion.active_pairs(party):
		PartyOpinion.set_score(party, p[0], p[1], v)

# How many of the party's names the text says.
func _named(party, text: String) -> int:
	var n := 0
	for ch in party.roster:
		if ch.cname in text:
			n += 1
	return n

func _card_id(main) -> String:
	return String(main._event_card._e.get("id", "")) if main._event_card != null else ""

# One camp: the rest is owed again, the night is roped, and whatever card was
# up from last time is waved away first.
func _camp(main) -> void:
	if main._event_card != null:
		main._on_event_ack()
	main.world.clock.pause()   # nothing else on the map gets a word in
	main.party.safe_camp = true
	main.party.last_long_rest_at = -99999.0
	_quiet_night(main)
	main._make_camp()
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
	for i in 10:
		await process_frame
	var party = main.party

	# --- warming / quarrel: the moment is on the night's card ---
	_set_all(party, 30.0)
	var fired := false
	for i in 30:
		await _camp(main)
		if _card_id(main) == "camp-fireside":
			fired = true
			break
	check(fired, "thirty warm camps: at least one fireside moment (MOMENT_CHANCE_PCT %d)" % PartyOpinion.MOMENT_CHANCE_PCT)
	if fired:
		var text := String(main._event_card._e.get("text", ""))
		check(_named(party, text) >= 2, "the card names both of them: %s" % text)
		check("At the fire" in String(main._event_card._e.get("title", "")), "titled at the fire")
	main._on_event_ack()
	check(main._event_card == null and not main.world.clock.is_paused(), "acked: card down, clock running")

	# --- courtship: asked on the approach card, answered, reported ---
	_set_all(party, 70.0)
	var asked := false
	for i in 30:
		await _camp(main)
		if main._approach_card != null:
			asked = true
			break
	check(asked, "thirty bonded camps: at least one courtship asked")
	if asked:
		var ids: Array = []
		for o in main._approach_card._opts:
			ids.append(String(o.get("id", "")))
		check(ids == ["accept", "decline"], "the two rows: %s" % str(ids))
		check(main._event_card == null and main.world.clock.is_paused(), "the question holds the clock, with no card under it")
		main._approach_card.chosen.emit("accept")
		await process_frame
		var lovers: Array = []
		for p in PartyOpinion.active_pairs(party):
			if PartyOpinion.status(party, p[0], p[1]) == "lovers":
				lovers.append(p)
		check(lovers.size() == 1, "saying yes makes exactly one pair lovers (%d)" % lovers.size())
		check(main._approach_card == null, "the approach card is gone")
		check(_card_id(main) == "camp-courtship" and String(main._event_card._e.get("kind", "")) == "good",
			"...and the answer is reported on a good card: %s" % _card_id(main))
		if lovers.size() == 1:
			var text := String(main._event_card._e.get("text", ""))
			check(party.get_member(lovers[0][0]).cname in text and party.get_member(lovers[0][1]).cname in text,
				"the card names the pair: %s" % text)
		main._on_event_ack()
		check(main._event_card == null and not main.world.clock.is_paused(), "acked: card down, clock running")

	# --- declining: the fire never asks that pair again ---
	party.relations.clear()
	_set_all(party, 70.0)
	asked = false
	for i in 30:
		await _camp(main)
		if main._approach_card != null:
			asked = true
			break
	check(asked, "a courtship was asked within the attempts")
	if asked:
		main._approach_card.chosen.emit("decline")
		await process_frame
		var declined := 0
		for p in PartyOpinion.active_pairs(party):
			if PartyOpinion.status(party, p[0], p[1]) == "declined":
				declined += 1
		check(declined == 1, "letting it lie marks the pair declined (%d)" % declined)
		check(_card_id(main) == "camp-courtship" and String(main._event_card._e.get("kind", "")) == "bad",
			"...on a bad card: %s" % _card_id(main))
		main._on_event_ack()

	# --- the plain night is still there ---
	party.relations.clear()
	_set_all(party, 0.0)
	var quiet := false
	for i in 30:
		await _camp(main)
		if _card_id(main) == "camp-night":
			quiet = true
			break
	check(quiet, "thirty camps at 0: at least one plain 'The camp holds'")
	if main._event_card != null:
		main._on_event_ack()

	# --- the inn: the same fire, over the visit, and the visit keeps its clock ---
	var home = main.world.settlements[0]
	main.world.player().position = home.position
	main._open_visit(home)
	_set_all(party, 30.0)
	fired = false
	for i in 30:
		party.gold = Visit.inn_cost(home) + 1
		party.last_long_rest_at = -99999.0
		main._rest()
		await process_frame
		if _card_id(main) == "camp-fireside":
			fired = true
			break
		if main._event_card != null:
			main._event_card.acknowledged.emit()
	check(fired, "thirty inn nights: at least one fireside moment")
	if fired:
		check(not main._visit.is_empty() and main.world.clock.is_paused(), "the card is over the visit, clock held")
		main._event_card.acknowledged.emit()
		await process_frame
		check(main._event_card == null, "acked: the card is down")
		check(not main._visit.is_empty() and main.world.clock.is_paused(), "...the visit is still up and still holds the clock")
	main._close_visit()

	# --- Leave, while the inn's card is still up: acking afterward must not
	# leave the map stuck paused behind a visit that is already gone ---
	main._open_visit(home)
	_set_all(party, 30.0)
	fired = false
	for i in 30:
		party.gold = Visit.inn_cost(home) + 1
		party.last_long_rest_at = -99999.0
		main._rest()
		await process_frame
		if _card_id(main) == "camp-fireside":
			fired = true
			break
		if main._event_card != null:
			main._event_card.acknowledged.emit()
	check(fired, "thirty more inn nights: at least one fireside moment")
	if fired:
		main._close_visit()
		check(main._visit.is_empty(), "Leave closed the visit while the card was still up")
		# The loop above spends in-game days resting; push the road-event clock
		# forward so a stray travel event doesn't fire on the frame below and
		# mask what we're actually checking.
		main._last_travel_at = main.world.clock.elapsed
		# ...and, since the design audit's §1.7, those days are WALKED: the
		# hunters on this map spend them making for the town the company sleeps
		# in, and would meet it at the gate on that same frame. The world moving
		# is the point of that change; it is not what this block checks.
		var here: Vector2 = main.world.player().position
		for q in main.world.parties.duplicate():
			if not q.is_player and q.position.distance_to(here) < 300.0:
				main.world.parties.erase(q)
		# ...and the thirty nights put the benched merc past core/bench.gd's
		# RESTLESS_DAYS, whose warning is due on the first clear frame after
		# Leave. That card is test_bench's; this block is about the fire's.
		for id in main.party.bench_clock:
			main.party.bench_clock[id]["since"] = main.world.clock.elapsed
		main._event_card.acknowledged.emit()
		await process_frame
		check(not main.world.clock.is_paused(), "acking after Leave does not leave the map paused")
		check(main._pause_btn.text == "Pause", "...and the pause button says so, not stuck on Resume")
	main._close_visit()

	print("test_world_fireside: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
