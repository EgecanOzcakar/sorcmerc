# Headless player for the whole game loop: loads the campaign screen and presses
# real buttons — pick a node, fight the fight (through the real combat screen),
# shop, take a quest, rest — until the run is won or lost.
#   godot --headless --path . -s tests/drive_campaign.gd
extends SceneTree

const Hex = preload("res://core/hex.gd")
const Quest = preload("res://core/quest.gd")

const MAX_STEPS := 4000

var main
var _presses := 0
var _fail := 0
var _did := {}

func _init() -> void:
	OS.set_environment("SORCMERC_FAST", "1")   # the combat screen skips its pauses
	main = load("res://scenes/campaign/campaign.tscn").instantiate()
	root.add_child(main)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

# Every Button under `node`, in tree order.
func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion() and not c.disabled:
			out.append(c)
		out.append_array(buttons(c))
	return out

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text:
			_presses += 1
			_did[label] = true
			b.pressed.emit()
			return true
	return false

func _run() -> void:
	await process_frame
	await process_frame
	var steps := 0
	while steps < MAX_STEPS and main.run.state in ["picking", "visiting", "combat"]:
		steps += 1
		await process_frame
		if main._combat != null:
			_fight_step()
			continue
		if main._combat_overlay != null:
			if not press(main._combat_overlay, "Back to the road"):
				fail("no way back out of the combat screen")
				break
			continue
		match main.run.state:
			"picking":
				# Prefer the road we can actually use (shop / rest / treasure); a
				# button-mashing driver loses fights, and the boss is unavoidable
				# anyway, so combat still gets walked.
				var roads := buttons(main._body).filter(func(b): return "Take this road" in b.text)
				if roads.is_empty():
					fail("no road to take on stage %d" % main.run.stage)
					break
				var opts: Array = main.run.options()
				var pick := 0
				for i in opts.size():
					if opts[i]["kind"] != "combat":
						pick = i
						break
				_presses += 1
				_did["Take this road"] = true
				_did["node:" + String(opts[pick]["kind"])] = true
				roads[mini(pick, roads.size() - 1)].pressed.emit()
			"visiting":
				_visit_step()
			"combat":
				await process_frame   # the overlay is coming up

	# --- assertions on the walked run ------------------------------------
	if main.run.state not in ["won", "lost"]:
		fail("the run never finished (state=%s, stage=%d)" % [main.run.state, main.run.stage])
	if not _did.has("Take this road"):
		fail("never picked a node")
	if not _did.has("Continue"):
		fail("never left a node")
	if main.run.log.is_empty():
		fail("the run journal stayed empty")
	for kind in ["combat", "treasure", "merchant", "rest"]:
		if not _did.has("node:" + kind):
			fail("never walked a %s node" % kind)
	if not _did.has("fight"):
		fail("never reached the combat screen")
	if not _did.has("Accept:"):
		fail("never took a quest")
	if main.party.quests.is_empty() or main.party.quests[0]["state"] == "offered":
		fail("the quest never made it into the party log as active")
	if not _did.has("Buy  "):
		fail("never bought anything")
	if not _did.has("Take a long rest"):
		fail("never rested")
	print("drive_campaign: %d presses, stage %d/%d, state=%s, %d gp, %d XP, %d quests — %s" % [
		_presses, main.run.stage, main.run.STAGES.size(), main.run.state,
		main.party.gold, main.run.xp, main.party.quests.size(),
		"OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	print("  exercised: ", _did.keys())
	quit(1 if _fail > 0 else 0)

# On a node: use whatever it offers, then move on.
func _visit_step() -> void:
	var kind: String = main.run.node.get("kind", "")
	if kind == "merchant":
		if press(main._body, "Accept:"):
			return
		if press(main._body, "Turn in:"):
			return
		if main.party.gold >= 30 and press(main._body, "Buy  "):
			return
		if press(main._body, "Sell  "):
			return
	elif kind == "rest":
		if not _did.has("Take a short rest") and press(main._body, "Take a short rest"):
			return
		if not _did.has("Take a long rest") and press(main._body, "Take a long rest"):
			return
	if not press(main._body, "Continue"):
		fail("no Continue on the %s node" % kind)
		main.run.leave()

# One press of the real combat screen, drive_ui style: close to melee, swing,
# end the turn. Deliberately dumb — this smoke test is about the wiring, and
# tests/drive_ui.gd already exercises the verb menu properly.
func _fight_step() -> void:
	var fight = main._combat
	var cb = fight.cb
	if cb == null or fight._busy or not fight.result.is_empty():
		return
	_presses += 1
	_did["fight"] = true
	if fight._mode in ["cone", "target"]:
		var h = cb.current()
		for c in cb.combatants:
			if fight._valid_target(h, c):
				fight.board_hex_clicked(c.pos)
				return
		fight.board_cancel()
		return
	var btns: Array = []
	for b in fight._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion():
			btns.append(b)
	if btns.is_empty():
		return
	# "Attack…", never "Reckless Attack" — the free toggle does not spend the action.
	for b in btns:
		if "] Attack" in b.text:
			b.pressed.emit()
			return
	if _step_toward_a_foe(cb):
		return
	btns[btns.size() - 1].pressed.emit()   # End turn

func _step_toward_a_foe(cb) -> bool:
	var h = cb.current()
	if h.econ["move_left"] <= 0:
		return false
	var foes = cb.enemies_of(h)
	if foes.is_empty():
		return false
	var goal = h.pos
	var best := 1 << 30
	for hx in cb.move_field(h):
		var d: int = Hex.distance(hx, foes[0].pos)
		if d < best:
			best = d
			goal = hx
	if goal == h.pos:
		return false
	_did["move"] = true
	main._combat.board_hex_clicked(goal)
	return true
