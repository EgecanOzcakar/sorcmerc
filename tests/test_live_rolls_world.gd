# Live rolls on the world screen — a settlement's actions (steal, persuade,
# haggle, investigate, work at the healer's) and the inn's downtime (carouse,
# gamble) roll their die in a popup over the visit panel — never inside it, so
# the page does not move — before the line says what happened
# (scenes/world/world.gd's _say_rolled); the map's quick checks (a lair's or a
# landmark's search, sneaking past a lair, a forage) pop theirs up over the map,
# undarkened, and fade it out after (_map_roll). Drives the real world scene with SORCMERC_FAST off and the
# pace pinned, since that is the only way there is a die in the air at all.
#   godot --headless --path . -s tests/test_live_rolls_world.gd
extends SceneTree

const Visit = preload("res://core/settlement_visit.gd")
const Settings = preload("res://core/settings.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func _init() -> void:
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for i in 10:
		await process_frame
	var home = s.world.settlements[0]
	Visit.mark_battle(s.world, home.position, s.world.clock.elapsed)
	s.party.gold = 10000
	s._open_visit(home)
	s._goto_page("hub")

	OS.set_environment("SORCMERC_FAST", "")
	var pace: float = Settings.current().anim_speed_multiplier
	Settings.current().anim_speed_multiplier = 1.0

	var gold_before: int = s.party.gold
	s._investigate()
	await process_frame
	check(s._visit.get("investigated", false), "the action has happened: its one-shot flag is set")
	check(is_instance_valid(s._visit_dice) and s._visit_dice.is_playing(), "...and its die is in the air")
	check(s._visit_log.text == "", "...with the line held back until it lands")
	check(buttons(s._visit_panel).all(func(b): return b.disabled), "...and the panel's buttons waiting for it")
	check(is_instance_valid(s._visit_die_popup) and s._visit_die_popup.is_ancestor_of(s._visit_dice),
		"the die rolls in a popup")
	check(not s._visit_panel.is_ancestor_of(s._visit_dice), "...not in the page, which stays where it was")
	var popup = s._visit_die_popup
	s._unhandled_key_input(_key(KEY_ENTER))
	await process_frame
	await process_frame
	check(not is_instance_valid(popup) or popup.is_queued_for_deletion(), "landed, the popup goes")
	check(not is_instance_valid(s._visit_dice) or not s._visit_dice.is_playing(), "Enter lands it")
	check("Investigation" in s._visit_log.text, "...and the line is said: %s" % s._visit_log.text)
	check(s._visit_pending.is_empty(), "...nothing left held")
	check(buttons(s._visit_panel).any(func(b): return not b.disabled), "...and the buttons are back")
	check(s._visit.get("log", "") == s._visit_log.text, "the line is the visit's log, as _say keeps it")

	# A panel rebuilt under a die still in the air says the line before it goes.
	s._goto_page("market")
	s._steal()
	await process_frame
	check(is_instance_valid(s._visit_dice) and s._visit_dice.is_playing(), "the steal rolls live too")
	s._build_visit_panel()
	check(s._visit_pending.is_empty() and "Sleight of Hand" in String(s._visit.get("log", "")),
		"a rebuild mid-roll keeps the line rather than losing it: %s" % s._visit.get("log", ""))

	# --- the map's quick checks ------------------------------------------------
	s._close_visit()
	await process_frame
	var l = null
	for x in s.world.lairs:
		if not x.discovered:
			l = x
			break
	if l != null:
		s._lair_target = l
		s._lair_msg.text = "stale"
		s._lair_action()
		await process_frame
		check(is_instance_valid(s._map_die), "a lair's search rolls its die over the map")
		check(s._lair_msg.text == "", "...with the line held back")
		check(not s._map_die.find_children("*", "ColorRect", true, false).size()
			and s._map_die.get_parent() == s, "...nothing darkened: no wash, just the die")
		check(s._map_die.position.y + s._map_die.size.y > s.size.y * 0.8, "...near the bottom, over the HUD bar")
		var box = s._map_die
		s._map_dice.finish()
		await process_frame
		check("Survival" in s._lair_msg.text, "landed, the line is said: %s" % s._lair_msg.text)
		check(is_instance_valid(box) and not box.is_queued_for_deletion(), "...and the die stays up with its verdict")
		await create_timer(s.MAP_LINGER + s.MAP_FADE + 0.3).timeout
		check(not is_instance_valid(box) or box.is_queued_for_deletion(), "...then fades out on its own")
	else:
		check(false, "the map has an undiscovered lair to search")

	Settings.current().anim_speed_multiplier = pace
	OS.set_environment("SORCMERC_FAST", "1")
	# Under SORCMERC_FAST (every robot) the line is there at once, as before.
	s._open_visit(home)
	s._goto_page("hub")
	s._visit["investigated"] = false
	s._investigate()
	check(not is_instance_valid(s._visit_dice) and "Investigation" in s._visit_log.text,
		"SORCMERC_FAST: no die, the line at once")
	print("test_live_rolls_world: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)
