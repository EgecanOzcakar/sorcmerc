# Dev-only: an enemy caster announcing itself (core/enemy_casters.gd). A level-8
# preset party against the cult's Frontier boss room — a Magister at the
# Frontier tier with two fanatics — past the first round, so the log shows the
# "... is a spellcaster" line and the Magister's first area spell.
#
#   SORCMERC_SEED=3 xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . -s tests/shot_caster.gd   ->  shots_caster/*.png
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")

func grab(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://shots_caster/%s.png" % name)
	print("saved shots_caster/%s.png" % name)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_caster"))
	var pty = Party.new()
	for ch in Presets.party_at(8):
		pty.add_member(ch)
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = pty
	main.spec = {"monsters": [{"id": "mage", "count": 1, "mult": 1.0, "caster": true, "caster_cap": 3},
		{"id": "cult-fanatic", "count": 2, "mult": 1.0}], "theme": "sunken-shrine"}
	root.add_child(main)
	for i in 90:
		await process_frame
	if main._mode == "deploy":
		main._press_hotkey(-1)
		for i in 120:
			await process_frame
	await create_timer(1.0).timeout
	await grab("1_announced")
	quit()
