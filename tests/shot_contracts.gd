# Dev-only: the notice board under contracts (core/contracts.gd). Two frames of
# the first settlement's board — as strangers, with the war work it will not
# hand you yet noted and not listed; then Known to its people and liked, with
# the raid posted, the issuer on every job and their regard on the purse.
#
#   xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . --resolution 1400x860 -s tests/shot_contracts.gd  ->  shots_contracts/*.png
extends SceneTree

const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")

var game

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-%d" % randi())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_contracts"))
	FactionOpinion.reset()
	Ladder.reset()
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout
	game.show_world(null)
	await create_timer(1.5).timeout
	var w = game._screen
	var s = w.world.settlements[0]
	w._open_visit(s)
	w._goto_page("board")
	await shot("1_stranger")
	w._close_visit()
	Ladder.deed(s.faction, Ladder.RUNG_AT[Ladder.KNOWN])
	FactionOpinion.set_opinion(s.faction, 40.0)
	w._open_visit(s)
	w._goto_page("board")
	await shot("2_known")
	quit()

func shot(name: String) -> void:
	await create_timer(0.6).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_contracts/%s.png" % name)
	print("saved shots_contracts/%s.png" % name)
