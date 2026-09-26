# #232 / #234 on the real world screen: the road stops the company and asks.
# Driven the way a player plays it — the march is a click on a town, the
# choice is a press of the card's real button, the answer is D3's own card —
# on the default map (a route world):
#
#   * the clock stops on a card with two or three choices, each saying what it
#     would take;
#   * pressing one resolves it and reports it on the event card, die and all;
#   * a choice that turns to a fight puts a band in front of the company on the
#     approach card;
#   * a choice that chains puts its follow-up on the road ahead, and the road's
#     next event is that follow-up;
#   * waving the card away (what drive robots and Enter do) takes the first
#     choice, "as the orders have it".
#
# What is arranged, and why: WHICH event the road picks is its own dice
# (tests/test_road_events.gd covers the pick), so the robot sets up the one it
# wants to press through the road's own door for a chosen event — a follow-up
# due now, which is exactly how a chain arrives — rather than waiting on luck.
#   godot --headless --path . -s tests/drive_road_events.gd
extends SceneTree

const RoadEvents = preload("res://core/road_events.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const Travel = preload("res://core/travel.gd")
const RoadChoiceCard = preload("res://scenes/world/road_choice_card.gd")

var screen
var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	OS.set_environment(RouteTravel.FLAG, "")   # the default: a route world
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

func step(n := 1) -> void:
	for i in n:
		screen._process(0.1)
		await process_frame

# Put `id` on the road as due now, and march so the road checks.
func _arrange(id: String) -> void:
	var w = screen.world
	w.road_chain.append({"event": id, "due": w.clock.elapsed})
	screen._last_travel_at = w.clock.elapsed - Travel.EVENT_INTERVAL - 1.0
	screen._halted_on_arrival = false
	RouteTravel.go(w, "settlement:greenmarch")
	w.clock.resume()
	for i in 200:
		await step()
		if screen._event_card is RoadChoiceCard:
			return

func _press(choice_id: String) -> void:
	for b in screen._event_card.buttons():
		if String(b.name) == "choice_" + choice_id:
			b.pressed.emit()
			return
	check(false, "the card offers \"%s\"" % choice_id)

func _run() -> void:
	await process_frame
	var w = screen.world
	check(RouteTravel.on(w), "the default map is a route world")
	screen.party.add_gold(500)

	# 1. The camp: three choices, and "go in hard" turns to a fight.
	await _arrange("the-camp")
	var card = screen._event_card
	check(card is RoadChoiceCard, "the road stops the company on a choice card")
	check(w.clock.is_paused(), "...and stops the clock")
	check(card != null and card.buttons().size() == 3, "...with three choices")
	check(card != null and card.buttons().all(func(b): return String(b.text) != ""), "...each labelled")
	if card is RoadChoiceCard:
		_press("hit")
		await step()
		check(screen._event_card != null and not (screen._event_card is RoadChoiceCard), "the answer is reported on the event card")
		check(String(screen._event_card._e.get("choice", "")) == "hit", "...for the choice pressed")
		check(screen._event_card._e.has("fight"), "...and it is a fight")
		screen._event_card.acknowledged.emit()
		await step()
		check(screen._approach_card != null or screen._combat != null, "the band is in front of the company (approach card)")
		if screen._approach_card != null:
			var foe = screen._approach_foe
			screen._close_approach()
			screen._on_approach_reported(foe, {"fight": false})
		await step(2)

	# 2. The snare: finding the trapper chains to the trapper.
	var scout: String = screen.party.party_characters()[0].id
	Travel.set_orders(screen.party, "normal", scout, "")
	var chained := false
	for attempt in 12:
		await _arrange("snare")
		if not (screen._event_card is RoadChoiceCard):
			break
		_press("hunt")
		await step()
		var out: Dictionary = screen._event_card._e if screen._event_card != null else {}
		screen._event_card.acknowledged.emit()
		await step()
		if String(out.get("chained", "")) == "the-trapper":
			chained = true
			break
		w.road_chain.clear()
	check(chained, "finding the trapper puts him on the road ahead")
	if chained:
		screen._last_travel_at = w.clock.elapsed - Travel.EVENT_INTERVAL - 1.0
		screen._halted_on_arrival = false
		RouteTravel.go(w, "settlement:greenmarch")
		w.clock.resume()
		var next := ""
		for i in 200:
			await step()
			if screen._event_card is RoadChoiceCard:
				next = String(screen._event_card._e.get("id", ""))
				break
		check(next == "the-trapper", "...and he is the road's next event (%s)" % next)
		if screen._event_card is RoadChoiceCard:
			var g0: int = screen.party.gold
			_press("buy")
			await step()
			check(screen.party.gold == g0 - 15 and screen.party.stash_count("potions-of-healing") >= 1,
				"buying from him costs 15 and puts the draught in the pack")
			screen._event_card.acknowledged.emit()
			await step()

	# 3. Waving the card away takes the first choice: the standing orders.
	await _arrange("ford")
	if screen._event_card is RoadChoiceCard:
		screen._event_card.acknowledged.emit()
		await step()
		check(String(screen._event_card._e.get("choice", "")) == "orders", "waving the card away lets the orders decide")
		screen._event_card.acknowledged.emit()
		await step()
	check(not w.clock.is_paused() or screen._halted_on_arrival, "the clock is given back after the answer")

	screen.queue_free()
	await process_frame
	print("drive_road_events: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
