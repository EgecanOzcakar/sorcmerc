# The combat screen with an objective on the spec: the party starts where the
# objective says, the header carries the objective's line, the road is known
# to the board, and a bystander is drawn but never offered as a hero.
#   godot --headless --path . -s tests/test_objectives_ui.gd
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Objectives = preload("res://core/objectives.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _open(spec: Dictionary):
	var main = load("res://scenes/main.tscn").instantiate()
	main.spec = spec
	root.add_child(main)
	for i in 20:
		await process_frame
	return main

func _init() -> void:
	OS.set_environment("SORCMERC_SEED", "7")
	var main = await _open({"monsters": [{"id": "snik", "count": 4}], "theme": "goblin-camp",
		"objective": Objectives.make("breakout")})
	check(main.cb.objective_kind() == "breakout", "the objective reached the fight")
	check("Road — " in main._header.text, "the header carries the objective line: %s" % main._header.text)
	var board: Dictionary = main.cb.board
	var mids: Array = Encounter.middle_starts(board, 7)
	check(main.cb.heroes().all(func(h): return h.pos in mids), "a breakout's party stands in the middle")
	check(main.cb.log.has(Objectives.brief(main.cb.objective)), "the brief is the fight's first line")
	check(main.COL_EXIT.a > 0.0 and main.COL_BYSTANDER.a > 0.0, "the road and the bystander have colours")
	main.queue_free()
	await process_frame

	main = await _open({"monsters": [{"id": "snik", "count": 2}], "theme": "goblin-camp",
		"objective": Objectives.make("escort")})
	var car = main.cb.with_status("carter")
	check(car != null and not main.cb.order.has(car), "the carter is on the board and off the order strip")
	check(Icons.combatant_glyph(car) == "⚑", "a bystander's token mark is the flag")
	check(not main.deploy_swappable(car), "the deploy phase never offers the carter")
	check("Carter — " in main._header.text, "escort's line: %s" % main._header.text)
	main.queue_free()
	await process_frame

	main = await _open({"monsters": [{"id": "snik", "count": 2}], "theme": "goblin-camp"})
	check(main.cb.objective.is_empty(), "rout: no objective")
	check(not ("Road" in main._header.text or "Carter" in main._header.text or "Hold" in main._header.text),
		"rout: the header has no objective line: %s" % main._header.text)
	print("test_objectives_ui: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
