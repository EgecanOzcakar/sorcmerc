# Dev-only: live rolls in town — a haggle's die rolling in a popup over the shop before
# the line says how it went. Needs a display (the world renders 3D); not part
# of run_tests.sh. Run WITHOUT SORCMERC_FAST:
#
#   godot --path . --resolution 1400x900 -s tests/shot_live_roll_town.gd
#     -> docs/shots/live-roll-town-rolling.png   the popup die in the air over the dimmed shop
#     -> docs/shots/live-roll-town-landed.png    landed: the line, the buttons back
#     -> docs/shots/live-roll-map.png            a lair's search: the die over the HUD bar
extends SceneTree

const Settings = preload("res://core/settings.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "")
	# Slowed right down for the camera: the world renders in software under a
	# virtual display and each frame is slow, so at the real pace the die has
	# landed before the first capture.
	Settings.current().anim_speed_multiplier = 0.08
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	var home = s.world.settlements[0]
	s.party.gold = 500
	s._open_visit(home)
	s._goto_page("market")
	for _i in 10:
		await process_frame
	s._haggle()
	await create_timer(1.2).timeout
	await _save("docs/shots/live-roll-town-rolling.png")
	if is_instance_valid(s._visit_dice):
		s._visit_dice.finish()
	for _i in 6:
		await process_frame
	await _save("docs/shots/live-roll-town-landed.png")
	s._close_visit()
	for _i in 6:
		await process_frame
	for l in s.world.lairs:
		if not l.discovered:
			s._lair_target = l
			break
	s._lair_action()
	await create_timer(1.2).timeout
	await _save("docs/shots/live-roll-map.png")
	quit()

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
