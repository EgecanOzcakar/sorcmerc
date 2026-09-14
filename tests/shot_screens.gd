# Dev-only: every menu screen, one PNG each, under res://shots_tmp/.
#   godot --headless --path . -s tests/shot_screens.gd      (SHOT_ONLY=party for one)
extends SceneTree
const Icons = preload("res://core/ui_icons.gd")
const SCREENS := ["game", "party", "creator/creator", "campaign", "profile", "settings",
	"achievements", "progression", "mods"]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp"))
	var only := OS.get_environment("SHOT_ONLY")
	root.theme = Icons.dark_theme()
	for scene in SCREENS:
		if only != "" and scene.get_file() != only:
			continue
		var path := "res://scenes/%s.tscn" % (scene if "/" in scene else "%s/%s" % [scene, scene])
		var n = load(path).instantiate()
		root.add_child(n)
		for i in 30: await process_frame
		RenderingServer.force_draw()
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://shots_tmp/%s.png" % scene.get_file())
		n.queue_free()
		await process_frame
	quit()
