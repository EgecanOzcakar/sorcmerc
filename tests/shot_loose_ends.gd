# Dev-only: the proof shots for docs/plan/2026-09-25-loose-ends.md. Needs a
# display (the world renders 3D); not part of run_tests.sh. One shot per run:
#
#   SHOT=refused  xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --resolution 1600x1000 -s tests/shot_loose_ends.gd
#   SHOT=camp ...   SHOT=lodge ...
#     -> docs/shots/loose-ends-refused.png  the party screen on the open road: the swap refused, and where to go
#     -> docs/shots/loose-ends-camp.png     the same screen at a camp: the swap live, recruiting still the inn's
#     -> docs/shots/loose-ends-lodge.png    the lodge page's own door to who marches
extends SceneTree

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	match OS.get_environment("SHOT"):
		"refused": await _party_screen(false, "docs/shots/loose-ends-refused.png")
		"camp": await _party_screen(true, "docs/shots/loose-ends-camp.png")
		"lodge": await _lodge()
		_: printerr("SHOT=refused|camp|lodge")
	quit()

func _world():
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 40:
		await process_frame
	s.world.clock.pause()
	return s

func _party_screen(camp: bool, path: String) -> void:
	var s = await _world()
	if camp:
		s.world.camp_spot = s.world.player().position
	s._open_party()
	for _i in 12:
		await process_frame
	await _save(path)

func _lodge() -> void:
	var s = await _world()
	var town = s.world.settlements[0]
	s.party.gold = 600
	s.party.lodge = {"settlement_id": town.id, "rooms": ["strongroom"], "gold": 0, "garden_at": -1.0, "maproom_at": -1.0,
		"retrained": {}, "blessed_at": -1.0}
	s._open_visit(town)
	s._goto_page("lodge")
	for _i in 12:
		await process_frame
	await _save("docs/shots/loose-ends-lodge.png")

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
