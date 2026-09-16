# Issue #29: "the spell/attack targeted enemy can be highlighted on the top
# turn bar". Hovering a token mid-aim already prints its odds over its own
# head, but the strip along the top — whose turn, who is hurt, who is next — is
# where a fight is actually read, and nothing up there said which of those
# tiles the thing in hand was pointed at. For a cone or a burst it is worse:
# the board lights the hexes, and the names standing in them are exactly what
# the strip knows.
#
#   godot --headless --path . -s tests/test_order_aim.gd
extends SceneTree

const Hex = preload("res://core/hex.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	# Fast-forward to a party turn with an attack in hand.
	var guard := 0
	while main.cb.current().team != "party" and not main.cb.is_over() and guard < 40:
		main.cb.end_turn()
		guard += 1
	var cur = main.cb.current()
	check(cur != null and cur.team == "party", "a party member is up")

	var foe = null
	for c in main.cb.combatants:
		if c.team != "party" and not c.is_dead():
			foe = c
			break
	check(foe != null, "there is somebody to aim at")
	# Whether the seed put anyone in reach of a plain melee swing is not this
	# test's business, so put one there: an adjacent, unoccupied board hex.
	if foe != null and cur != null:
		var taken := {}
		for c in main.cb.combatants:
			if c != foe and not c.is_dead():
				taken[c.pos] = true
		for h in Hex.neighbors(cur.pos):
			if h in main.cb.board["hexes"] and not taken.has(h):
				foe.pos = h
				break
	if cur == null or foe == null:
		print("test_order_aim: %d passed, %d failed" % [_pass, _fail])
		quit(1); return

	main._build_hero_menu(cur)
	await process_frame
	check(main.aimed_ids().is_empty(), "nothing is highlighted while idle")

	# The strip has a tile per combatant, and they are the things that get lit.
	check(main._order_tiles.size() == main.cb.order.size(), "one tile per combatant")
	check(main._order_tiles.has(foe.id), "...including the one about to be aimed at")

	# Aim the plain attack and put the cursor on the foe.
	var attack := {}
	for v in main.cb.all_verbs(cur):
		if String(v.get("kind", "")) == "attack" and String(v.get("targeting", "")) == "enemy":
			attack = v
			break
	check(not attack.is_empty(), "the character has a targeted attack")
	main._enter_target(cur, attack)
	main._board._hover = foe.pos
	main._paint_order_aim()
	var lit: Dictionary = main.aimed_ids()
	check(lit.has(foe.id), "hovering a legal target lights its tile")
	check(lit.size() == 1, "...and only its tile")
	var box: StyleBox = main._order_tiles[foe.id].get_theme_stylebox("panel")
	check(box != main._order_tiles[foe.id].get_meta("base_box"), "the tile is wearing something other than its resting box")
	check(box is StyleBoxFlat and (box as StyleBoxFlat).border_color == main.COL_FOE,
		"...and what it is wearing is the target border")

	# Off the board again: the highlight goes with the cursor.
	main._board._hover = Vector2i(999, 999)
	main._paint_order_aim()
	check(main.aimed_ids().is_empty(), "the highlight follows the cursor off the token")
	check(main._order_tiles[foe.id].get_theme_stylebox("panel") == main._order_tiles[foe.id].get_meta("base_box"),
		"...and the tile goes back to its resting box")

	# Dropping out of aim clears it too, even with the cursor left on the foe.
	main._enter_target(cur, attack)
	main._board._hover = foe.pos
	main._paint_order_aim()
	check(not main.aimed_ids().is_empty(), "re-aimed")
	main.board_cancel()
	await process_frame
	check(main.aimed_ids().is_empty(), "cancelling the aim clears the strip")
	check(main._order_tiles[foe.id].get_theme_stylebox("panel") == main._order_tiles[foe.id].get_meta("base_box"),
		"...and the tile with it")

	# An area verb lights everyone standing in it, not one token.
	var burst := {}
	for v in main.cb.all_verbs(cur):
		if String(v.get("targeting", "")) in ["hex", "corner", "line", "direction"]:
			burst = v
			break
	if not burst.is_empty():
		var hexes: Array = main.cb.area_hexes(cur, burst, foe.pos) if String(burst["targeting"]) != "direction" else []
		if not hexes.is_empty():
			var standing := 0
			for c in main.cb.combatants:
				if not c.is_dead() and c.pos in hexes:
					standing += 1
			main._enter_area(cur, burst)
			main._board._hover = foe.pos
			main._paint_order_aim()
			check(main.aimed_ids().size() == standing,
				"an area lights everyone inside it (%d of %d)" % [main.aimed_ids().size(), standing])
			main.board_cancel()
			await process_frame

	# Rebuilding the strip (a turn passing, a death) must not strand a highlight.
	main._build_order_strip()
	await process_frame
	check(main._order_aimed.is_empty(), "a rebuilt strip starts clean")

	print("test_order_aim: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
