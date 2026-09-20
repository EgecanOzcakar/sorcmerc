# Dev-only: the T32 walkthrough, one PNG per step, under res://shots_tmp/.
# What a PR touching core/tutorial.gd shows as its proof — the cards are the
# visible change, and they are only legible over a live combat screen.
#   godot --path . -s tests/shot_tutorial.gd        (SHOT_STEP=5 for one)
extends SceneTree

const Tutorial = preload("res://core/tutorial.gd")

# scenes/game/game.gd wraps the combat screen in a Control carrying the "Title"
# button, so the screen is a child of what _swap() put on the stack, not that.
static func _find_combat(n: Node):
	if n.has_method("_walk_show"):
		return n
	for c in n.get_children():
		var hit = _find_combat(c)
		if hit != null:
			return hit
	return null

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp"))
	var game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	game.show_tutorial()          # the fixed fight, with the overlay already up
	for i in 90:
		await process_frame
	var main = _find_combat(game)
	if main == null:
		printerr("no combat screen under the tutorial wrapper")
		quit(1); return
	var only := OS.get_environment("SHOT_STEP")
	for n in Tutorial.STEPS.size():
		if only != "" and int(only) != n + 1:
			continue
		main._walk_show(n)
		for i in 10:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var path := "res://shots_tmp/tutorial_%d.png" % (n + 1)
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved %s  —  %s" % [path, Tutorial.STEPS[n]["title"]])
	quit()
