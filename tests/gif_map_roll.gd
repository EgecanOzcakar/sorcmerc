# Dev-only: the frames for docs/shots/live-roll-map.gif — a lair's search on
# the campaign map: the die pops up over the undarkened map near the bottom,
# rolls, shows its verdict, and fades out. Needs a display; not part of
# run_tests.sh. Recorded with Godot's movie maker, whose fixed frame rate makes
# every frame exactly 1/25 s of game time however slowly it is drawn:
#
#   godot --path . --resolution 1400x900 --fixed-fps 25 \
#       --write-movie shots_tmp/map/f.png -s tests/gif_map_roll.gd
#     -> shots_tmp/map/fNNNNNNNN.png; the roll starts at the frame this prints.
#   Then Pillow, as tests/gif_dice_roll.gd's header shows.
extends SceneTree

const Settings = preload("res://core/settings.gd")

const SETTLE := 40             # frames for the world to come up before the roll
const SHOW := 125              # frames of the roll: pop, tumble, verdict, linger, fade

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "")
	Settings.current().anim_speed_multiplier = 1.0
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in SETTLE:
		await process_frame
	s.world.clock.pause()   # the party stands still for the picture
	for l in s.world.lairs:
		if not l.discovered:
			s._lair_target = l
			break
	print("roll starts at frame %d" % (SETTLE + 1))
	s._lair_action()
	for _i in SHOW:
		await process_frame
	quit()
