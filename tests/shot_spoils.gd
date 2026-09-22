# Dev-only: the after-action page as the map builds it — the company, the
# fallen, the tally, the haul as tiles — captured every few frames of its
# sequence so a PR can show the deal as a GIF. Needs a display (it renders);
# not part of run_tests.sh.
#   godot --path . --resolution 900x760 -s tests/shot_spoils.gd
#   -> spoils_NN.png (a frame every 3), then e.g.
#      ffmpeg -framerate 20 -i spoils_%02d.png spoils.gif
extends SceneTree

const World = preload("res://core/world.gd")

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "")
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var p = main.world.player()
	var foe = World.RoamingParty.new("bandits-shot", p.position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe)
	main._launch_combat(foe)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	main.party.get_member(main.party.active[1]).hp_current = 9
	main._combat.result = {"outcome": "Victory", "xp": 400, "gold": 50,
		"loot": ["handaxe", "potion-of-healing", "potion-of-healing"],
		"kills": ["bandit", "bandit", "bandit-captain"], "deaths": []}
	guard = 0
	while main._spoils_panel == null and guard < 60:
		await process_frame
		guard += 1
	var page = main._spoils_panel
	page._done = true          # driven by hand, frame by frame
	var n := 0
	var t := 0.0
	while t <= page._end + 0.3:
		page._t = t
		page._apply()
		for _f in 2:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://spoils_%02d.png" % n)
		n += 1
		t += 0.05
	print("saved %d frames" % n)
	quit()
