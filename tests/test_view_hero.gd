# #72: looking at a party member's bar and sheet while it is not their turn.
#   godot --headless --path . -s tests/test_view_hero.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _labels(main) -> Array:
	await process_frame
	var out: Array = []
	for b in main._buttons.get_children():
		var tip := String(b.tooltip_text)
		out.append(tip.get_slice("\n", 0) if tip != "" else String(b.text))
	return out

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	# Skip deployment and get to a hero's turn.
	var guard := 0
	while main._mode == "deploy" and guard < 5:
		main._press_hotkey(-1); guard += 1
		await process_frame
	guard = 0
	while (main.cb.current().team != "party" or main._busy) and guard < 400:
		await process_frame; guard += 1
	var cur = main.cb.current()
	check(cur.team == "party" and not main._viewing, "a hero's turn, their own bar up")
	var other = null
	for c in main.cb.combatants:
		if c.team == "party" and c != cur and c.conscious():
			other = c
	check(other != null, "there is another hero to look at")

	main.view_hero(other)
	var labels: Array = await _labels(main)
	check(main._viewing, "clicking another hero's tile enters viewing")
	check(other.cname in main._actor.text and "not their turn" in main._actor.text, "the actor line names them and says it is not their turn")
	check(labels.size() == 11 and labels[10] == "Back", "their bar, nine slots + Swap, ending in Back rather than End turn (%s)" % str(labels))
	var kids: Array = main._buttons.get_children()
	check(kids[0].disabled, "Attack is greyed — nothing fires off-turn")
	var spells: Button = kids[1]
	if not spells.disabled:
		spells.pressed.emit()
		labels = await _labels(main)
		check(main._submenu == "spells" and labels.size() > 1, "...but the Spells list opens to read (%s)" % str(labels))
		check(main._buttons.get_children().slice(0, -1).all(func(b): return b.disabled), "and every spell in it is greyed")
	main._press_hotkey(-1)   # Space: the last button — Back from the list, then Back from the bar
	await process_frame
	if main._viewing:
		main._press_hotkey(-1)
		await process_frame
	check(not main._viewing and main.cb.current() == cur, "Back returns to the acting hero")
	labels = await _labels(main)
	check(labels[10].begins_with("End turn"), "...whose bar ends in End turn again")

	main.view_hero(other)
	await process_frame
	main.board_cancel()
	await process_frame
	check(not main._viewing, "Esc leaves viewing too")
	main.view_hero(cur)
	await process_frame
	check(not main._viewing, "looking at the acting hero is just their own bar")

	# #97: the strip marks who is being looked at, and a board click while
	# looking never moves the acting hero.
	main.board_hex_clicked(other.pos)
	await process_frame
	check(main._viewing and main._viewed_id == other.id, "clicking another hero's token looks at them")
	var tile = main._order_tiles[other.id]
	check(tile.get_theme_stylebox("panel").border_color == main.COL_PARTY, "...and their strip tile is boxed in the party's green")
	var was: Vector2i = cur.pos
	var free: Vector2i = Vector2i(999, 999)
	for hx in main.cb.move_field(cur):
		if hx != cur.pos:
			free = hx
			break
	check(free != Vector2i(999, 999), "there is a hex the acting hero could move to")
	main.board_hex_clicked(free)
	await process_frame
	check(cur.pos == was, "a click on the board while looking does not move the acting hero")
	check(not main._viewing, "...it just puts their bar back")
	main.board_hex_clicked(free)
	await process_frame
	check(cur.pos == free, "and the next click moves them, as before")

	print("test_view_hero: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
