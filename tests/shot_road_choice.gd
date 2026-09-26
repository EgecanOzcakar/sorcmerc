# #232 — the road asks, for the PR: the choice card over the map (the camp in
# the hollow, three things to do about it), and the answer on D3's own card.
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
	quit()

func _shoot(w, path: String) -> void:
	for i in 8:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path.get_file())
