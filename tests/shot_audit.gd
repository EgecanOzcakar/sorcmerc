# Dev-only: the screens the 2026-09-23 audit pass changed, one PNG each. Needs a
# display (the town panel sits over the 3D map); not part of run_tests.sh.
#
#   godot --path . --resolution 1400x760 -s tests/shot_audit.gd
#     -> docs/shots/audit-title-delete.png     a Delete… beside every saved run
#     -> docs/shots/audit-title-confirm.png    ...and the confirmation it opens
#     -> docs/shots/audit-presets-locked.png   Vera and Pike wear the class lock (#200)
#     -> docs/shots/audit-wizard-shelf.png     a wizard's simple weapons on the shelf (#192)
#     -> docs/shots/preset-level-2.png        a preset starts a fresh run at level 2
#     -> docs/shots/audit-town-inn.png         the inn page fits a short window (#201);
#                                              hub, market and board are written too
#     -> docs/shots/audit-settings.png         the settings note that points at the title
#
# 760 px tall on purpose: #201 is a short window, and that is where it shows.
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Prog = preload("res://core/progression.gd")
const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_SAVE_DIR", "user://shot-audit/%d" % randi())
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
	root.theme = Icons.dark_theme()
	Prog._current = Prog.new()   # a fresh profile: the fighter and rogue still locked

	# The title, with three runs on it.
	for i in 3:
		WorldSave.new_slot()
		var w := World.new()
		w.origin = {"kind": "procedural", "seed": 40 + i}
		w.clock.elapsed = 1440.0 * (i + 1) + 300.0 * i
		var p := Party.new()
		for ch in Presets.party():
			p.add_member(ch)
		p.add_gold(120 * (i + 1))
		WorldSave.save(w, p)
	var game = load("res://scenes/game/game.tscn").instantiate()
	game.campaign = null
	root.add_child(game)
	await _frames(4)
	game.show_title()
	await _frames(6)
	await _save("docs/shots/audit-title-delete.png")
	game._confirm_delete_world_save(WorldSave.list_slots()[1])
	await _frames(6)
	await _save("docs/shots/audit-title-confirm.png")
	game.queue_free()
	await _frames(2)

	# The creator's first page, where the presets are.
	var cr = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(cr)
	await _frames(6)
	await _save("docs/shots/audit-presets-locked.png")
	cr._set_class("wizard")
	cr._goto(cr.STEPS.find("Equipment"))
	await _frames(6)
	await _save("docs/shots/audit-wizard-shelf.png")
	cr._load_preset("ilsa")   # a fresh run's preset: level 2, and Light is a spell
	await _frames(8)
	await _save("docs/shots/preset-level-2.png")
	cr.queue_free()
	await _frames(2)

	var st = load("res://scenes/settings/settings.tscn").instantiate()
	root.add_child(st)
	await _frames(6)
	await _save("docs/shots/audit-settings.png")
	st.queue_free()
	await _frames(2)

	# A city's square on a short window: every counter, the lodge, the doors.
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	await _frames(40)
	s.world.clock.pause()
	s.party.gold = 2000
	var city = null
	for t in s.world.settlements:
		if t.kind == "city":
			city = t
			break
	s._open_visit(city if city != null else s.world.settlements[0])
	await _frames(12)
	for page in ["hub", "inn", "market", "board"]:
		s._goto_page(page)
		await _frames(12)
		await _save("docs/shots/audit-town-%s.png" % page)
	quit()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
