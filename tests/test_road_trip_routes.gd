# The road between two towns, walked, with the books kept — on the roads.
# tests/test_road_trip.gd's readout for the default map (#231): the same large
# map, the same first two legs a new company walks (Riverhold -> Oakford ->
# Greenmarch), the same worst-case policy at every meeting, the same heroes'
# hand (core/ai.gd) in every fight, the same books and the same floors. It
# extends that file and overrides only the steps a route world does
# differently:
#
#   * **The order** is a click on the town (tests/road_screen.gd), marched by
#     the known roads; a town the march passes through does not open, and one
#     that opens anyway (the company halted inside its gate by a fight) is
#     walked out of, as the free trip walks through a waystation.
#   * **The next town** is the nearest one a known road goes to.
#   * **A different crowd each run.** Nothing walks the map, so there are no
#     bands to reseed: who the road sends is RouteEncounters' dice, keyed on
#     the edge and the road's odometer (step_key), so each run starts the
#     odometer at a different mile (ODOMETER_STRIDE apart) — the same roads, a
#     different stretch of the dice, the way the free trip reseeds its bands.
#     The rate itself is untouched; tests/sweep_route_travel.gd measured it.
#
# The floors are the free trip's, unchanged: a leg meets at most three bands
# on average and is not empty, four legs in five nobody dies, three in five
# arrive whole. The road's model was calibrated to deliver the free plane's
# contact rate (RouteEncounters.BASE), so the same walk should keep the same
# books; if one of these floors ever fails here and not there, that is the
# two maps' roads disagreeing, which is this file's finding to report.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_road_trip_routes.gd
extends "res://tests/test_road_trip.gd"

const RouteTravel = preload("res://core/route_travel.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

# Miles of road between one run's odometer and the next: well past any leg,
# so no two runs share a roll.
const ODOMETER_STRIDE := 100000.0

func _routes() -> bool:
	return true

func _new_crowd(w, run: int) -> void:
	check(RouteTravel.on(w), "the large map is a route world")
	w.route_walked = ODOMETER_STRIDE * run

func _order(screen, to) -> void:
	RoadScreen.click(screen, to.position)

func _reachable(world, from: Vector2, s) -> bool:
	return not world.routes.path_from(from, RoadScreen.node(s)).is_empty()
