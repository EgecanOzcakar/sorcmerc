# Headless player: loads the real scene and presses real buttons until the fight ends.
# Exercises every _hero_* path and the UI wiring, which no other test touches.
#   SORCMERC_SEED=123 godot --headless --path . -s tests/drive_ui.gd
extends SceneTree

const MAX_PRESSES = 600

var main
var _presses = 0
var _picked = {}

func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	var idle = 0
	while _presses < MAX_PRESSES:
		await process_frame
		if main.cb == null:
			idle += 1
			if idle > 120:
				print("*** main.cb never initialised — script broken? ***")
				quit(1)
			continue
		if main.cb.is_over():
			break
		if main._busy:
			continue
		# board-driven modes: aiming / cone need a hex click, not a button
		if main._mode == "cone" or main._mode == "target":
			_board_click()
			idle = 0
			continue
		# in idle, sometimes just walk toward a foe (exercises default click-to-move)
		if main._mode == "idle" and main.cb.current().team == "party" and _presses % 4 == 0 and main.cb.move_left > 0:
			_move_click()
			idle = 0
			continue
		var btns = _buttons()
		if btns.is_empty():
			idle += 1
			if idle > 900:  # AI timer is 0.5s; ~15s of no buttons means we are wedged
				break
			continue
		idle = 0
		_press(btns)

	var res = main.cb.outcome() if main.cb else "no combat"
	var ok = res == "Victory" or res == "Defeat"
	print("seed=%d presses=%d rounds=%d outcome=%s %s" % [
		main._seed, _presses, main.cb.round_num, res, "OK" if ok else "*** WEDGED ***",
	])
	print("  exercised: ", _picked.keys())
	if not ok:
		for c in main.cb.combatants:
			var st = "dead" if c.is_dead() else ("down" if c.is_down() else "%d/%d" % [c.hp, c.max_hp])
			print("  %-13s %-7s @%v" % [c.cname, st, c.pos])
	quit(0 if ok else 1)

const Hex = preload("res://core/hex.gd")

func _board_click() -> void:
	_presses += 1
	var cb = main.cb
	var h = cb.current()
	var foes = cb.enemies_of(h)
	if main._mode == "cone":
		_picked["cone"] = true
		if not foes.is_empty():
			main.board_hex_clicked(foes[0].pos)
		else:
			main.board_cancel()
		return
	# target mode: click the first valid target, else cancel
	_picked["target:" + main._tgt_kind] = true
	for c in cb.combatants:
		if main._valid_target(h, c):
			main.board_hex_clicked(c.pos)
			return
	main.board_cancel()

func _move_click() -> void:
	_presses += 1
	_picked["move"] = true
	var cb = main.cb
	var h = cb.current()
	var foes = cb.enemies_of(h)
	if foes.is_empty():
		return
	var field = cb.move_field(h)
	var goal = h.pos
	var best = 1 << 30
	for hx in field:
		var d = Hex.distance(hx, foes[0].pos)
		if d < best:
			best = d
			goal = hx
	if goal != h.pos:
		main.board_hex_clicked(goal)

func _buttons() -> Array:
	var out: Array = []
	for b in main._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion():
			out.append(b)
	return out

# Rotate through verbs rather than mashing Attack, so every path gets exercised.
func _press(btns: Array) -> void:
	var pick: Button = null
	var wanted = ["Attack", "Shove", "Attack", "Burning Hands", "Healing Word", "Attack", "Help", "Hide",
		"Second Wind", "Attack", "Sacred Flame", "Dodge", "Attack", "Dash"]
	var verb = wanted[_presses % wanted.size()]
	for b in btns:
		if verb in b.text:
			pick = b
			break
	if pick == null:
		for b in btns:
			if b.text.begins_with("Attack"):
				pick = b
				break
	if pick == null:
		pick = btns[btns.size() - 1]  # End turn
	_picked[pick.text.split(" ")[0]] = true
	_presses += 1
	pick.pressed.emit()
