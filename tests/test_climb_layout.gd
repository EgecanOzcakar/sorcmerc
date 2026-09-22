# The climb's rungs do not draw on top of each other.
#
# A rung is a Button with its content ANCHORED inside it, and a Button does not
# grow to fit its children — so every rung was 46px tall whatever was in it, and
# a rung whose chips wrapped to a second line was drawn straight over the rung
# below. It shipped unnoticed because the level-up page is wide and a rogue's
# chips fit on one line: it took the creator's narrower column, and a monk,
# whose level 2 grants six things at once, to make it visible.
#
# So this is a LAYOUT test, which means it needs a real tree and real frames.
# The claim is only that no rung overlaps the next, checked at a width narrow
# enough to force the wrap that caused it.
#
#   godot --headless --path . -s tests/test_climb_layout.gd
extends SceneTree

const Climb = preload("res://core/climb.gd")
const Icons = preload("res://core/ui_icons.gd")

# Narrow on purpose. At the level-up page's width nothing wraps and this test
# would pass against the bug it was written for.
const NARROW := 520.0
const TALL := 1600.0

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _init() -> void:
	root.theme = Icons.dark_theme()
	await test_no_rung_overlaps_the_next()
	await test_a_wrapped_rung_is_taller_than_the_floor()
	print("test_climb_layout: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _view(class_id: String, subclass_id: String, at: int):
	var host := Control.new()
	host.custom_minimum_size = Vector2(NARROW, TALL)
	host.size = Vector2(NARROW, TALL)
	root.add_child(host)
	var view = load("res://scenes/creator/climb_view.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(view)
	view.show_track(Climb.build(class_id, subclass_id, at),
		Climb.paths_for(class_id), subclass_id, class_id)
	# _fit_rungs runs deferred and may take a pass or two to settle.
	for _i in 12:
		await process_frame
	return [host, view]


func _rungs(view) -> Array:
	return view._rungs.get_children()


func test_no_rung_overlaps_the_next() -> void:
	# Every class, because which rung wraps depends entirely on what the class
	# grants and when — the monk is the one that found it, not the only one.
	for cid in ["monk", "rogue", "barbarian", "cleric", "wizard", "paladin", "ranger", "bard"]:
		var pair = await _view(cid, "", 0)
		var rungs: Array = _rungs(pair[1])
		check(rungs.size() == 20, "%s: twenty rungs on screen (%d)" % [cid, rungs.size()])
		for i in range(rungs.size() - 1):
			var a: Control = rungs[i]
			var b: Control = rungs[i + 1]
			check(a.get_global_rect().end.y <= b.get_global_rect().position.y + 0.5,
				"%s: rung %d (ends %.1f) clears rung %d (starts %.1f)" % [
					cid, i + 1, a.get_global_rect().end.y, i + 2,
					b.get_global_rect().position.y])
		pair[0].queue_free()
		await process_frame


# The other half: a rung that wrapped must actually be TALLER than the floor.
# Without this, "nothing overlaps" would also be satisfied by a widget that
# failed to draw its chips at all.
func test_a_wrapped_rung_is_taller_than_the_floor() -> void:
	var pair = await _view("monk", "", 0)
	var rungs: Array = _rungs(pair[1])
	# The monk's level 2: Focus Points, Flurry of Blows, Patient Defense, Step of
	# the Wind, Unarmored Movement, Uncanny Metabolism — six, which wraps at any
	# width a column of this screen has ever had.
	var two: Control = rungs[1]
	check(two.size.y > 46.0,
		"the monk's level 2 grew past the 46px floor to fit six chips (%.1f)" % two.size.y)
	var one: Control = rungs[0]
	check(two.size.y > one.size.y,
		"...and is taller than level 1, which has three (%.1f vs %.1f)" % [two.size.y, one.size.y])
	pair[0].queue_free()
	await process_frame
