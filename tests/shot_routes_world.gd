# #231 phase 1 — the world screen as a route world, for the PR: the roads the
# company knows drawn on the map with the march on one of them, and the card
# the road opens when it sends a band. Not a test.
#
# Not headless — the capture needs a real rendering driver (xvfb-run is enough):
#   godot --path . -s tests/shot_routes_world.gd   # -> docs/shots/route-travel-*.png
extends SceneTree

const RouteTravel = preload("res://core/route_travel.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const RNG = preload("res://core/rng.gd")

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shot-%d" % randi())
	OS.set_environment(RouteTravel.FLAG, "1")
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	for i in 40:
		await process_frame
	# On the road to Greenmarch, a little way out of Riverhold.
	RouteTravel.go(w.world, "settlement:greenmarch")
	for i in 60:
		w._process(0.1)
	w.world.clock.pause()
	w.set_zoom(0.5)
	w.center_on(Vector2(40, 40))
	await _shoot(w, "res://docs/shots/route-travel-map.png")
	# What the road sends, on the card every band has always been met on.
	var p = w.world.player()
	var spec := RouteEncounters.compose(w.world, p.position, {"faction": "goblinoid", "source": "country"}, RNG.new(7), "shot")
	var band = RouteTravel.band_for(w.world, spec)
	w._party3d.reset(w.world)
	w._open_approach(band, true)
	await _shoot(w, "res://docs/shots/route-travel-met.png")
	quit()

func _shoot(w, path: String) -> void:
	for i in 8:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path.get_file())
