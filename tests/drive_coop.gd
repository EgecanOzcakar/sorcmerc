# One co-op peer, headless: loads the real combat screen under SORCMERC_COOP and
# presses real buttons whenever one of its own heroes is up, waits otherwise.
# Prints the fight's final state hash so two of these can be compared. Run by
# tools/coop_smoke.sh, which starts the relay and both peers.
#   SORCMERC_COOP=host:ABCDEF SORCMERC_RELAY=ws://127.0.0.1:8799 godot --headless --path . -s tests/drive_coop.gd
#   SORCMERC_COOP_QUIT_AFTER=N   quit (exit 3) after N presses — the guest's "crash"
extends SceneTree

const Coop = preload("res://core/coop.gd")
const Hex = preload("res://core/hex.gd")

const MAX_PRESSES = 400
const PATIENCE := 60.0   # seconds of nothing to press before giving up on the other peer

var main
var _presses = 0
var _quit_after: int = int(OS.get_environment("SORCMERC_COOP_QUIT_AFTER")) if OS.get_environment("SORCMERC_COOP_QUIT_AFTER") != "" else -1

func _init() -> void:
	OS.set_environment("SORCMERC_FAST", "1")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()

func _run() -> void:
	var waited_since := Time.get_ticks_msec()
	while _presses < MAX_PRESSES:
		await process_frame
		if main.cb != null and main.cb.is_over():
			break
		if main.cb == null or main._busy or (main._mode == "deploy" and main._coop.role == "guest"):
			if Time.get_ticks_msec() - waited_since > PATIENCE * 1000:
				print("*** %s waited %ds for the other peer — wedged ***" % [OS.get_environment("SORCMERC_COOP"), PATIENCE])
				quit(1)
				return
			continue
		waited_since = Time.get_ticks_msec()
		if _presses == _quit_after:
			print("%s: quitting on purpose after %d presses" % [main._coop.role, _presses])
			quit(3)
			return
		if main._mode == "cone" or main._mode == "target":
			_board_click()
		elif main._mode == "idle" and _presses % 3 == 0 and main.cb.current().econ["move_left"] > 0:
			_move_click()
		else:
			var btns := _buttons()
			if btns.is_empty():
				continue
			_press(btns)
	await create_timer(1.0).timeout   # let the last message leave
	var cb = main.cb
	print("%s: seed=%d room=%s presses=%d rounds=%d outcome=%s hash=%d" % [
		main._coop.role, main._seed, main._coop.code, _presses, cb.round_num, cb.outcome(), Coop.state_hash(cb)])
	quit(0 if cb.is_over() else 1)

func _board_click() -> void:
	_presses += 1
	var cb = main.cb
	var h = cb.current()
	if main._mode == "cone":
		var foes = cb.enemies_of(h)
		if foes.is_empty():
			main.board_cancel()
		else:
			main.board_hex_clicked(foes[0].pos)
		return
	for c in cb.combatants:
		if main._valid_target(h, c):
			main.board_hex_clicked(c.pos)
			return
	main.board_cancel()

func _move_click() -> void:
	_presses += 1
	var cb = main.cb
	var h = cb.current()
	var foes = cb.enemies_of(h)
	if foes.is_empty():
		return
	var goal = h.pos
	for hx in cb.move_field(h):
		if Hex.distance(hx, foes[0].pos) < Hex.distance(goal, foes[0].pos):
			goal = hx
	if goal != h.pos:
		main.board_hex_clicked(goal)

func _name(b: Button) -> String:
	var tip := String(b.tooltip_text)
	return tip.get_slice("\n", 0) if tip != "" else String(b.text)

func _buttons() -> Array:
	var out: Array = []
	for b in main._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion() and not b.disabled:
			out.append(b)
	return out

func _press(btns: Array) -> void:
	var wanted = ["Attack", "Sacred Flame", "Attack", "Cure Wounds", "Second Wind", "Attack", "Dodge", "End turn"]
	var verb = wanted[_presses % wanted.size()]
	var pick: Button = null
	for b in btns:
		if verb in _name(b):
			pick = b
			break
	if pick == null:
		pick = btns[-1]   # End turn / Begin the ambush sits last
	_presses += 1
	pick.pressed.emit()
