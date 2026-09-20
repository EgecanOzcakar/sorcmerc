# Dev-only: the landmarks, one PNG each, into docs/shots/landmarks/ — the
# pictures behind PR #138. Needs a display (it renders); not part of
# run_tests.sh.
#   godot --path . --resolution 1400x860 -s tests/shot_landmarks.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Landmarks = preload("res://core/landmarks.gd")

const OUT := "res://docs/shots/landmarks/%s.png"
var game
var _n := 0

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-lm-%d" % randi())
	OS.set_environment("SORCMERC_SEED", "7")
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	var p = w.world.player()
	w.party.gold = 200

	# a shrine by the road: found by walking up, a button to visit, a marker on the map
	var shrine = w.world.add_landmark(World.Landmark.new("shot-shrine", "shrine", p.position + Vector2(34, 8)))
	await settle(1.0)
	await shot("map-visit-button")

	# the card: two rolled rows priced with who rolls, and the cleric's own row
	w._place_btn.pressed.emit()
	await settle()
	await shot("card-shrine")
	w._on_place_chosen("offering")
	await settle()
	await shot("outcome-offering")
	w._on_event_ack()
	await settle()

	# the ruins: a dig, and what it came to
	var ruins = w.world.add_landmark(World.Landmark.new("shot-ruins", "ruins", p.position + Vector2(-34, 10)))
	ruins.found = true
	shrine.spent = true
	await settle()
	w._place_btn.pressed.emit()
	await settle()
	await shot("card-ruins")
	w._on_place_chosen("dig")
	await settle()
	await shot("outcome-dig")
	w._on_event_ack()
	await settle()

	# the tower's watch: bands marked for two vision radii, drawn past the fog
	var tower = w.world.add_landmark(World.Landmark.new("shot-tower", "tower", p.position + Vector2(0, 40)))
	tower.found = true
	ruins.spent = true
	await settle()
	w._place_btn.pressed.emit()
	await settle()
	await shot("card-tower")
	w._close_approach()
	w.world.marked_at = tower.position
	w.world.marked_until = w.world.clock.elapsed + 1440.0
	tower.spent = true
	w.world.clock.resume()
	await settle(1.0)
	await shot("map-watch-marks")

	# the inn sells a hidden hut, cheaper than a lair
	var s = w.world.settlements[0]
	w.world.add_landmark(World.Landmark.new("shot-hut", "hut", s.position + Vector2(300, -120)))
	w._open_visit(s)
	w._goto_page("inn")
	await shot("inn-hut-lead")
	w._close_visit()
	quit()

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	_n += 1
	root.get_viewport().get_texture().get_image().save_png(OUT % ("%02d-%s" % [_n, name]))
	print("saved %02d-%s.png" % [_n, name])
