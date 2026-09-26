# Callings on the world screen, on the roads — tests/test_world_callings.gd's
# tour of the default map (#231). It extends that file rather than copying it:
# the same assignment, the same telling at the first fire, the same quest-log
# and party-page lines, the same pay in the same save, the same card order, the
# same inn and the same band fights. Only the steps a route world does
# differently are overridden here:
#
#   * **The shrine is the map's own.** A landmark the test adds by hand has no
#     way on the roads, so the acolyte is handed the small map's shrine with
#     every other shrine spent (the parent spends them too). It is hidden
#     until the telling marks it found, and then — the telling being one of
#     the other doors a place is found by (RouteTravel's _follow_marks) — its
#     way is revealed: a place, drawn, clickable, and marched to by road.
#   * **At the shrine** the company arrives by that march, and the place
#     button offers the visit, before the parent opens the card.
#   * **Into the town** is a click on the town and the march there; a route
#     world opens a town only at the end of a march.
#   * **The soldier's band** stands pinned on the road ahead (core/route_pins.gd,
#     the way a bounty or a story's band stands there; the parent puts its band
#     beside the company, and nothing walks up to anybody here), is met as the
#     march walks up to it, and the fight is the card's own "engage".
#
# The road's own traffic met on a march is waved off, the way
# tests/drive_routes.gd answers it.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_callings_routes.gd
extends "res://tests/test_world_callings.gd"

const WorldAI = preload("res://core/world_ai.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

func _routes() -> bool:
	return true

func _the_shrine(w):
	var keep = null
	for l in w.landmarks:
		if l.kind != "shrine":
			continue
		if keep == null and not l.found and w.routes.nodes.has(WorldRoutes.poi_id("landmark", l.id)):
			keep = l
		else:
			l.spent = true
	check(keep != null, "the small map has a shrine on its roads, hidden")
	return keep

func _walk_to_shrine(main, shrine) -> void:
	var w = main.world
	w.clock.resume()
	await RoadScreen.frame(self, main)   # the road's frame follows the telling's mark
	check(w.routes.nodes[WorldRoutes.poi_id("landmark", shrine.id)]["known"], "told, the shrine's way is on the roads")
	var got: String = await RoadScreen.go(self, main, shrine.position)
	check(got == "arrived" and w.player().position.distance_to(shrine.position) <= 8.0,
		"a click on the shrine marches there by road (%s)" % got)
	for i in 3:
		await process_frame
	check(main._place_btn.visible and shrine.sname in main._place_btn.text, "the button offers the visit: %s" % main._place_btn.text)

func _walk_into(main, town) -> void:
	var got: String = await RoadScreen.go(self, main, town.position)
	check(got == "visit" and main._visit.get("settlement") == town, "a click on %s marches into it (%s)" % [town.sname, got])

func _far_town(main):
	var p = main.world.player()
	var best = null
	for s in main.world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		if best == null or s.position.distance_to(p.position) > best.position.distance_to(p.position):
			best = s
	return best

var _band_dest = null

func _stand_band(main, band) -> void:
	if main._event_card != null:
		main._on_event_ack()
	if not main._visit.is_empty():
		main._close_visit()
	_band_dest = _far_town(main)
	check(RoadScreen.pin_ahead(main, RoadScreen.node(_band_dest), 60.0, band), "the band stands on the road ahead")

func _open_fight(main, foe) -> bool:
	var got: String = await RoadScreen.go(self, main, _band_dest.position, foe)
	check(got == "card" and main._approach_foe == foe, "the march walks up to it (%s)" % got)
	if main._approach_foe != foe:
		return false
	main._on_approach_chosen("engage")
	if main._event_card != null:
		main._event_card.acknowledged.emit()
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	return main._combat != null
