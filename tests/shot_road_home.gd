# Dev-only: the proof shot for docs/plan/2026-09-25-road-home.md — the map just
# after a company backs out of a lair: the lair's exit line with the road
# home's sentence on the end, and the top bar's "the road home, until dawn"
# beside the country. Needs a display (the world renders 3D); not part of
# run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 3400x1200x24" godot --path . --resolution 3400x1200 -s tests/shot_road_home.gd
#   (wide: the map's bottom bar is one unwrapped row, and at 1400 the line runs off it)
#     -> docs/shots/road-home-exit.png   the exit line and the bar's note
extends SceneTree

const World = preload("res://core/world.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()
	var p = s.world.player()
	var lair = World.Lair.new("road-home-warren", p.position + Vector2(10, 0), "goblinoid", "the Ash Warren")
	lair.discovered = true
	s.world.add_lair(lair)
	s._delve(lair)
	for _i in 6:
		await process_frame
	# Backed out at the mouth, the way a hurt company does.
	s._site.withdraw()
	s._on_site_done()
	for _i in 6:
		await process_frame
	if s._spoils_panel != null:
		s._close_spoils()
	s.world.clock.pause()
	# The controls hint takes most of the bottom row; this shot is about the
	# message at its end, so the hint steps aside for it.
	for l in s.find_children("*", "Label", true, false):
		if String(l.text).begins_with("Click marches"):
			l.visible = false
	for _i in 12:
		await process_frame
	await _save("docs/shots/road-home-exit.png")
	quit()

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
