# The world screen on the roads, driven the way a player drives it (not a test:
# the runner globs test_* and drive_*).
#
# Routes are the default map (#231 phase 2b). The world-screen tests that were
# written for the free plane pin themselves to SORCMERC_ROUTES=0 and keep
# testing the opt-out; their road counterparts (docs/plan/2026-09-26-road-
# tests.md) share the few verbs a route world is driven with, so each test says
# what it expects and not, again, how a click becomes a march:
#
#   RoadScreen.click(main, at)                 # the real left click on world point `at`
#   RoadScreen.frame(tree, main)               # one frame of map at a fixed delta
#   await RoadScreen.march(tree, main, at)     # click a place, walk until something stops the company
#   await RoadScreen.go(tree, main, at, want)  # ...the same, with the road's own traffic waved off on the way
#   RoadScreen.wave_off(main)                  # a card the road opened, answered "no fight"
#   RoadScreen.pin_ahead(main, to, d, band)    # a named band stood on the road `d` units ahead
#   RoadScreen.town(main, id) / node(s)        # a settlement by id, and its place id on the roads
#
# The march is the real thing: the click goes through world.gd's _gui_input to
# _route_click and RouteTravel.go, the frames are the screen's own _process, and
# what stops the company is whatever the map raised — the town at the end of
# the road opening, a card, a fight, or the halt on arrival. What only reports
# is waved away on the way, as every robot in tests/ does — a road event
# (core/travel.gd's card), the spoils page, a level's announcement, a trait's
# moment; anything that asks the player something is handed back.
#
# What this does NOT own: any assertion, the answer to any card but the road's
# own traffic in go() (each test answers its own, and says why; go() answers
# what the road sent by its dice with no fight, the way tests/drive_routes.gd
# does, because a test that is not about who walks the road is not about
# them either), and any write to the model but one:
# pin_ahead() stands a band on the road the way core/route_pins.gd stands a
# bounty, a raid or a story's spawn_party there — the road sends its own bands
# by its own dice (tests/test_route_travel.gd's subject), so a test that is
# about what happens at a meeting arranges the band it meets, the way the
# free-plane tests put a band next to the company with world.add_party().
extends RefCounted

const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const World = preload("res://core/world.gd")

const DT := 0.25   # world-seconds per frame; drive_routes.gd's walking pace

static func node(s) -> String:
	return "settlement:%s" % s.id

static func town(main, id: String):
	for s in main.world.settlements:
		if s.id == id:
			return s
	return null

# The real click, through the screen's own input handler, on world point `at`
# (the camera is centred on it first, so it is on the screen at any zoom).
static func click(main, at: Vector2) -> void:
	main.center_on(at)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = main._pix(at)
	main._gui_input(e)

static func frame(tree, main, dt := DT) -> void:
	main._process(dt)
	await tree.process_frame

# Is anything up that asks the player something?
static func asking(main) -> bool:
	return main._approach_card != null or main._combat != null or not main._visit.is_empty() \
		or main._spoils_panel != null or main._levelup_panel != null or main._moment != null

# Click the place at `at` and walk. Returns what stopped the company:
#   "visit"    a town opened (the one at the end of the road — a town passed through does not)
#   "card"     an approach card is up (a meeting on the road, or a place's card)
#   "fight"    a fight is up
#   "arrived"  the company is where it was sent and nothing opened
#   "no road"  the click gave no order
#   "timeout"  `cap` frames went by
# A click given while the clock stands paused (not halted — a halt is released
# by the new order itself) is followed by the HUD's Resume, as a player does.
static func march(tree, main, at: Vector2, cap := 1500, dt := DT) -> String:
	var p = main.world.player()
	_pass_reports(main)
	click(main, at)
	if p.at_goal() and not asking(main):
		return "arrived" if p.position.distance_to(at) <= 8.0 else "no road"
	if main.world.clock.is_paused() and not main._halted_on_arrival and not asking(main) \
			and main._event_card == null:
		main._toggle_pause()
	return await walk(tree, main, cap, dt)

# Keep walking the order already given; same answers as march().
static func walk(tree, main, cap := 1500, dt := DT) -> String:
	var p = main.world.player()
	for i in cap:
		await frame(tree, main, dt)
		if not main._visit.is_empty():
			return "visit"
		if main._approach_card != null:
			return "card"
		if main._combat != null:
			return "fight"
		if main._event_card != null:
			main._event_card.acknowledged.emit()
			continue
		if _pass_reports(main):
			continue
		if p.at_goal():
			return "arrived"
	return "timeout"

# What only reports is read and passed, as a player does: the spoils page, a
# level's announcement, a trait's moment. True when something was.
static func _pass_reports(main) -> bool:
	var any := false
	if main._spoils_panel != null:
		main._close_spoils()
		any = true
	if main._levelup_panel != null:
		main._close_levelup()
		any = true
	while main._moment != null:
		main._moment._skip_or_advance()
		any = true
	return any

# march(), with every meeting on the way that is not `want` waved off
# (wave_off) and the walk taken up again. Stops at `want`'s card when it opens.
static func go(tree, main, at: Vector2, want = null, cap := 1500) -> String:
	var got: String = await march(tree, main, at, cap)
	for i in 30:
		if got != "card" or main._approach_foe == null or (want != null and main._approach_foe == want):
			return got
		wave_off(main)
		got = await walk(tree, main, cap)
	return got

# The card the road opened, answered with no fight — the shape
# tests/drive_routes.gd answers the road's own traffic with: closed, and the
# report the screen acts on (a slip, whatever the dice would have said).
static func wave_off(main) -> void:
	var foe = main._approach_foe
	main._close_approach()
	if foe != null:
		main._on_approach_reported(foe, {"fight": false})

# Stand `band` on the road from where the company is to place id `to`, `d`
# units along it (core/route_pins.gd's own place(); see the header for why).
static func pin_ahead(main, to: String, d: float, band, why := "story") -> bool:
	var w = main.world
	var way: Dictionary = w.routes.path_from(w.player().position, to)
	if way.is_empty():
		return false
	var pts: PackedVector2Array = way["points"]
	var spot: Vector2 = pts[-1]
	var walked := 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if seg > 0.0 and walked + seg >= d:
			spot = pts[i - 1].lerp(pts[i], (d - walked) / seg)
			break
		walked += seg
	band.position = spot
	return RoutePins.pin(w, band, why)

# A band of `faction` with a small roster, the shape tests/drive_completionist_
# routes.gd meets.
static func band(id: String, faction: String) -> World.RoamingParty:
	var b := World.RoamingParty.new(id, Vector2.ZERO, faction)
	var roster: Array[Dictionary] = [{"role": "light", "level": 1}, {"role": "heavy", "level": 1}]
	b.troops = roster
	return b
