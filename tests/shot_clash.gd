# #229: two bands locked in a clash on the overworld — the throbbing ring round
# the ground they are fighting over, both figures squared up and lunging, and
# the labels counting the rounds off. Staged beside the player so the fog has it.
#
# Not headless — the capture hangs without a real rendering driver:
#   godot --path . -s tests/shot_clash.gd     -> clash_screen.png
extends SceneTree

const World = preload("res://core/world.gd")
const WorldBattle = preload("res://core/world_battle.gd")

func _init() -> void:
	var w = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(w)
	for i in 40:
		await process_frame
	var p = w.world.player()
	var at: Vector2 = p.position + Vector2(60, 10)
	var gob = w.world.add_party(World.RoamingParty.new("goblins-ridge", at, "goblinoid"))
	gob.troops.append({"role": "light", "level": 2})
	var pat = w.world.add_party(World.RoamingParty.new("riverhold-patrol", at + Vector2(18, 4), "human"))
	pat.troops.append({"role": "heavy", "level": 3})
	pat.troops.append({"role": "light", "level": 2})
	w.world.reveal(at)
	w._party3d.reset(w.world)   # a figure is only built on reset (party3d.gd)
	WorldBattle.start(w.world, 24.0, w.encounter_spec)
	# A few rounds in, so the label has something to count.
	w.world.clock.elapsed += WorldBattle.MINUTES_PER_ROUND * 2.5
	w.world.clock.pause()
	print("clashes: %s" % str(w.world.clashes))
	w.set_zoom(2.2)
	w.center_on(at + Vector2(9, 2))
	for i in 20:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://clash_screen.png")
	print("saved clash_screen.png")
	quit()
