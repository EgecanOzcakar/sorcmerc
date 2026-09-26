# #232 — the road asks, for the PR: the choice card over the map (the camp in
# the hollow, three things to do about it), and the answer on D3's own card.
# #232's meetings: a caravan's new offers, and demand against a weak band.
# The research batch: the rope that makes the ford certain, and a triumph.
# Not a test.
#
# Not headless — the capture needs a real rendering driver (xvfb-run is enough):
#   godot --path . -s tests/shot_road_choice.gd   # -> docs/shots/road-choice*.png
extends SceneTree

const RoadEvents = preload("res://core/road_events.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const Travel = preload("res://core/travel.gd")
const RoadChoiceCard = preload("res://scenes/world/road_choice_card.gd")

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shot-%d" % randi())
	OS.set_environment(RouteTravel.FLAG, "")
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	for i in 40:
		await process_frame
	w.world.road_chain.append({"event": "the-camp", "due": w.world.clock.elapsed})
	w._last_travel_at = w.world.clock.elapsed - Travel.EVENT_INTERVAL - 1.0
	RouteTravel.go(w.world, "settlement:greenmarch")
	w.world.clock.resume()
	for i in 200:
		w._process(0.1)
		await process_frame
		if w._event_card is RoadChoiceCard:
			break
	await _shoot(w, "res://docs/shots/road-choice.png")
	if w._event_card is RoadChoiceCard:
		for b in w._event_card.buttons():
			if String(b.name) == "choice_watch":
				b.pressed.emit()
	for i in 40:
		await process_frame
	if w._event_card != null and w._event_card.has_method("_land_now"):
		w._event_card._land_now()
	await _shoot(w, "res://docs/shots/road-choice-answer.png")
	if w._event_card != null:
		w._event_card.acknowledged.emit()
	for i in 4:
		await process_frame
	# #232's meetings: a caravan (trade, news, a job) and a weak band (demand).
	var World = load("res://core/world.gd")
	var p = w.world.player()
	var caravan = World.RoamingParty.new("shot-caravan", p.position, "human")
	caravan.troops.append({"role": "light", "level": 2})
	caravan.ai = {"behavior": "met", "source": "caravan"}
	w.world.add_party(caravan)
	w._party3d.reset(w.world)
	w._open_approach(caravan, false)
	await _shoot(w, "res://docs/shots/road-meeting-caravan.png")
	w._close_approach()
	var weak = World.RoamingParty.new("shot-weak", p.position, "goblinoid")
	weak.troops.append({"role": "light", "level": 1})
	w.world.add_party(weak)
	w._party3d.reset(w.world)
	w._open_approach(weak, true)
	await _shoot(w, "res://docs/shots/road-meeting-demand.png")
	w._close_approach()
	# The research batch: a rope of climbing makes the ford a certainty, and a
	# roll that clears the DC by 8 is a triumph with its own outcome.
	w.party.stash_add("rope-of-climbing")
	w.world.road_chain.append({"event": "ford", "due": w.world.clock.elapsed})
	w._halted_on_arrival = false
	RouteTravel.go(w.world, "settlement:greenmarch")
	w.world.clock.resume()
	for i in 200:
		w._process(0.1)
		await process_frame
		if w._event_card is RoadChoiceCard:
			break
	await _shoot(w, "res://docs/shots/road-choice-rope.png")
	if w._event_card != null:
		w._event_card.queue_free()
		w._event_card = null
	var triumph := {}
	for seed in range(1, 400):
		var o: Dictionary = RoadEvents.choose(RoadEvents.event("rough-going"), "push", w.party, w.world, load("res://core/rng.gd").new(seed))
		if String(o.get("degree", "")) == "triumph":
			triumph = o
			break
	var EventCard = load("res://scenes/world/event_card.gd")
	w._event_card = EventCard.new()
	w.add_child(w._event_card)
	w._event_card.show_event(triumph)
	for i in 40:
		await process_frame
	if w._event_card.has_method("_land_now"):
		w._event_card._land_now()
	await _shoot(w, "res://docs/shots/road-triumph.png")
	quit()

func _shoot(w, path: String) -> void:
	for i in 8:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path.get_file())
