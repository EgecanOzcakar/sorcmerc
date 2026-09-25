# Dev-only: the screens docs/plan/2026-09-25-downtime-nights.md changes — the
# inn with its head pinned and its list scrolled (#228), a night on the town the
# purse cannot cover and one that happened (#237) beside the pit's one-on-one
# row, a bout with one hero on the board (#236), and the level-up page naming what is
# left to choose (#235). Needs a display (it renders); not part of run_tests.sh.
#
#   xvfb-run -a -s "-screen 0 1920x1080x24" \
#       godot --path . -s tests/shot_downtime_nights.gd   ->  shots_downtime/*.png
extends SceneTree

const Recruits = preload("res://core/recruits.gd")
const Downtime = preload("res://core/downtime.gd")
const Leveling = preload("res://core/leveling.gd")
const Presets = preload("res://core/presets.gd")

var game

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(buttons(c))
	return out

func button_named(node: Node, text: String):
	for b in buttons(node):
		if String(b.text).begins_with(text):
			return b
	return null

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-downtime-%d" % randi())
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
	DirAccess.make_dir_recursive_absolute("res://shots_downtime")
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	var party = w.party
	for l in w.world.lairs:
		l.raid_at = 1e9
	w.world.clock.elapsed = 600.0
	var s = w.world.settlements[0]   # Riverhold, a city: the pit

	# 1. #228: the inn, its list scrolled down to the Downtime rows; the head stays.
	party.gold = 60   # the drinks, not the bed: Go out is grey and says why (#237)
	w._open_visit(s)
	w._goto_page("inn")
	await settle()
	w._visit_list.scroll_vertical = 240
	await shot("inn_scrolled")

	# 2. #237: a night that happened keeps its line under the row.
	party.gold = 900
	w._build_visit_panel()
	await settle(0.3)
	button_named(w._visit_panel, "Go out").pressed.emit()
	await settle(3.5)   # the die lands
	if w._event_card != null:
		w._event_card.acknowledged.emit()
	await settle(0.3)
	w._visit_list.scroll_vertical = 240
	await shot("inn_night_out")

	# 3. #236: the pit's row (in the shot above, who goes in beside Fight), and
	# the bout on the board: one hero, one champion.
	w._build_visit_panel()
	await settle(0.3)
	var fight = button_named(w._visit_panel, "Fight")
	if fight != null:
		fight.pressed.emit()
		await settle(4.0)
		await shot("pit_bout")
		if w._combat != null:
			w._combat.result = {"outcome": "Victory", "xp": 20, "gold": 0, "loot": [], "kills": [], "deaths": [], "rounds": 3,
				"objective": {"kind": "", "done": false, "xp": 0}}
		await settle(1.0)

	# 4. #235: a level-up with its choice still open, and Done pressed.
	var lvl = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(lvl)
	lvl.set_character(Presets.vera())
	lvl.commit()
	lvl._on_confirm()
	await shot("levelup_left")
	quit(0)

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_downtime/%s.png" % name)
	print("saved shots_downtime/%s.png" % name)
