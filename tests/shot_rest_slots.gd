# Dev-only: the real slots, three places (docs/plan/2026-09-24-rest-and-slots.md).
# Ilsa has spent her 1st-level slots and one 2nd in fights before these shots,
# so the sheet reads 0/4 and 1/2 with no edit buttons, the party page's row has
# the same pips, and in a fight her actor line starts with those slots hollow.
#
#   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . -s tests/shot_rest_slots.gd
#       ->  shots_tmp/rest-slots-{sheet,party,pips}.png
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")

func grab(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_tmp/rest-slots-%s.png" % name)
	print("saved shots_tmp/rest-slots-%s.png" % name)

func _party() -> Party:
	var pty := Party.new()
	for ch in Presets.party():
		pty.add_member(ch)
	var ilsa = pty.get_member("ilsa")
	ilsa.slots_used.assign([4, 1])
	ilsa.hp_current = maxi(1, ilsa.sheet().max_hp - 7)
	pty.gold = 240
	return pty

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shot-%d" % OS.get_process_id())
	OS.set_environment("SORCMERC_FAST", "1")   # no reaction prompt over the board
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_tmp"))
	root.theme = Icons.dark_theme()

	var pty := _party()
	var prof = load("res://scenes/profile/profile.tscn").instantiate()
	prof.set_party(pty)
	prof.set_character(pty.get_member("ilsa"))
	root.add_child(prof)
	for i in 30: await process_frame
	await grab("sheet")
	prof.queue_free()
	await process_frame

	var page = load("res://scenes/party/party.tscn").instantiate()
	page.party = _party()
	root.add_child(page)
	for i in 30: await process_frame
	await grab("party")
	page.queue_free()
	await process_frame

	var main = load("res://scenes/main.tscn").instantiate()
	main.party = _party()
	main.spec = {"monsters": [{"id": "goblin", "count": 2, "mult": 1.0}], "theme": "forest-clearing"}
	root.add_child(main)
	for i in 90: await process_frame
	if main._mode == "deploy":
		main._press_hotkey(-1)
		for i in 60: await process_frame
	for c in main.cb.combatants:
		if c.id == "ilsa":
			main.view_hero(c)
	for i in 10: await process_frame
	await grab("pips")
	quit()
