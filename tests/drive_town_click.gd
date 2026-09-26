# A click on a town with a band standing on it, on the real world screen and
# through its real input handler (_gui_input): a band the company has already
# met and parted with — slipped past, or under a truce — does not eat the click,
# and the march goes to the town; a fresh band on the same spot is still met
# (the click is an order to meet it, _seek). The owner's call, 2026-09-26, on
# the trap docs/plan/2026-09-25-completionist-gate-band.md found. On the free
# plane, where bands stand on the map (SORCMERC_ROUTES=0).
#   godot --headless --path . -s tests/drive_town_click.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RouteTravel = preload("res://core/route_travel.gd")

var screen
var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment(RouteTravel.FLAG, "0")
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

func _click(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = screen._pix(pos)
	screen._gui_input(e)

func _run() -> void:
	await process_frame
	var w = screen.world
	check(not RouteTravel.on(w), "SORCMERC_ROUTES=0: the free plane")
	var p = w.player()
	var gm = null
	for s in w.settlements:
		if s.id == "greenmarch":
			gm = s
	# Nobody on the map but the company and one band, standing on Greenmarch.
	for q in w.parties.duplicate():
		if not q.is_player:
			w.parties.erase(q)
	var band = w.add_party(World.RoamingParty.new("goblins-at-the-gate", gm.position, "goblinoid"))
	band.troops.append({"role": "heavy", "level": 1})
	screen._party3d.reset(w)
	w.clock.pause()
	w.marked_until = w.clock.elapsed + 100000.0   # the watch: every band in sight
	w.marked_at = gm.position
	screen.center_on(gm.position)
	await process_frame
	check(screen._band_at(screen._pix(gm.position)) == band, "the band's figure is under the click")

	# Parted with under a truce: the click is the town's.
	WorldAI.truce(band, p, w.clock.elapsed)
	_click(gm.position)
	check(screen._meet_id == "", "a truced band on the town: no meeting ordered")
	check(screen._destination(p).distance_to(gm.position) < 1.0, "...the march goes to the town")
	# Slipped past (no truce left): the same.
	band.ai.erase("truce_until")
	screen._slipped[band.id] = true
	w.set_goal(p, p.position)
	_click(gm.position)
	check(screen._meet_id == "" and screen._destination(p).distance_to(gm.position) < 1.0, "a slipped band on the town: the march goes to the town")
	# A fresh band on the same spot is met.
	screen._slipped.erase(band.id)
	w.set_goal(p, p.position)
	_click(gm.position)
	check(screen._meet_id == band.id, "a fresh band on the town: the click meets it")
	screen.queue_free()
	await process_frame
	print("drive_town_click: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
