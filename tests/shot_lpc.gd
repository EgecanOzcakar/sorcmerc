# Dev-only: a deliberately mixed roster - LPC humanoid (heroes + goblin), the
# three LPC creatures, and a monstrosity with no loadout that must still draw
# the old vector token - with one hero mid-swing, so both tiers and the attack
# row are in the same frame.
#   godot --path . -s tests/shot_lpc.gd     (non-headless; headless hangs on
#                                            viewport capture in this env)
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main.spec = {"theme": "shrine", "monsters": [
		{"id": "goblin"}, {"id": "bat"}, {"id": "ghost"},
		{"id": "gray-ooze"}, {"id": "worg"},
	]}
	root.add_child(main)
	for i in 40:
		await process_frame

	var LpcArt = load("res://core/lpc_art.gd")
	for c in main.cb.combatants:
		var lid: String = LpcArt.loadout_for(c)
		print("  %-18s src=%-12s sheet=%s -> %s" % [c.cname, c.src_id,
			"yes" if c.sheet != null else "no ", lid if lid != "" else "(vector token)"])

	for c in main.cb.combatants:
		print("    pos %-18s hex=%s tok=%s" % [c.cname, c.pos, main._board._tok.get(c.id)])
	# One hero knocked out, to show the downed tint on a sprite next to standing ones.
	main.cb.combatants[2].statuses["down"] = true
	main.cb.combatants[2].hp = 0
	# Swing: the real FX path, the same one a real attack queues.
	var hero = main.cb.combatants[0]
	var foe = main.cb.enemies_of(hero)[0]
	main._board.play_fx("melee", hero.id, hero.pos, foe.pos)
	main._board._flash[foe.id] = 0.35
	await create_timer(0.14).timeout
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://lpc_spike.png")
	print("saved lpc_spike.png %dx%d (swing: %s -> %s)"
		% [img.get_width(), img.get_height(), hero.cname, foe.cname])
	quit()
