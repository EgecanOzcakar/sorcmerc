# Dev-only: the proof shot for docs/plan/2026-09-25-deeps-teeth.md — the turn
# bar's short names in a Deeps fight. An adult red dragon used to read "Adult"
# on the bar and a giant rat "Giant"; they read "Red Dragon" and "Rat" now, the
# hill giant archer "Giant Archer". Needs a display; not part of run_tests.sh:
#
#   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 -s tests/shot_deeps_teeth.gd
#     -> docs/shots/deeps-teeth-turn-bar.png
extends SceneTree

const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	var main = load("res://scenes/main.tscn").instantiate()
	var party = Party.new()
	for ch in Presets.party_at(15):
		party.add_member(ch)
	main.party = party
	main.spec = {"monsters": [{"id": "adult-red-dragon", "count": 1}, {"id": "hill-giant-archer", "count": 1},
		{"id": "giant-rat", "count": 2}, {"id": "swarm-of-wasps", "count": 1}],
		"theme": "frozen-cave", "seed": 11}
	root.add_child(main)
	for _i in 60:
		await process_frame
	await create_timer(0.8).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://docs/shots/deeps-teeth-turn-bar.png")
	print("wrote docs/shots/deeps-teeth-turn-bar.png")
	quit()
