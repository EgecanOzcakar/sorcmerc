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
			continue
		if main.cb.is_over():
			break
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
	if not ok:
		print("  verbs: ", _picked.keys())
		for c in main.cb.combatants:
			var st = "dead" if c.is_dead() else ("down" if c.is_down() else "%d/%d" % [c.hp, c.max_hp])
			print("  %-13s %-7s zone%d" % [c.cname, st, c.zone])
	quit(0 if ok else 1)

func _buttons() -> Array:
	var out: Array = []
	for b in main._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion():
			out.append(b)
	return out

# Rotate through verbs rather than mashing Attack, so every path gets exercised.
func _press(btns: Array) -> void:
	var pick: Button = null
	var wanted = ["Shove", "Burning Hands", "Healing Word", "Second Wind", "Sacred Flame", "Dodge", "Dash", "→", "←", "Attack"]
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
