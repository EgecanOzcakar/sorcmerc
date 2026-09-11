# Headless player for the whole game loop: loads the campaign screen and presses
# real buttons — pick a node, fight the fight (through the real combat screen),
# shop, take a quest, rest — until the run is won or lost.
#   godot --headless --path . -s tests/drive_campaign.gd
extends SceneTree

const AI = preload("res://core/ai.gd")

const MAX_STEPS := 4000
# T43: the fight is not a formality — the tuned win rates are 94.5% easy / 83.5%
# normal (scaler.gd's TUNING header), so a walked run can genuinely lose, and a
# stage-0 loss ends it before a merchant/rest/treasure node is ever reached. The
# driver therefore walks up to ATTEMPTS runs on consecutive seeds and asserts on
# the first one that wins; three tries put a false red under ~1 in 1000.
const ATTEMPTS := 3
const DIFFICULTY_RANK := {"easy": 1, "normal": 2, "hard": 3}

var main
var _presses := 0
var _fail := 0
var _quiet := false      # a retried attempt's failures are counted, not printed
var _did := {}

func _init() -> void:
	OS.set_environment("SORCMERC_FAST", "1")   # the combat screen skips its pauses
	_attempts()

# Walk runs until one satisfies _check(). A pinned SORCMERC_SEED replays exactly,
# so a retry has to move it; unseeded, route and fight reseed off the clock alone.
# A late loss that still walked every node kind passes on the spot — only a run
# cut short (a lost opening fight) costs an attempt.
func _attempts() -> void:
	var base := int(OS.get_environment("SORCMERC_SEED"))
	for attempt in ATTEMPTS:
		if base > 0:
			OS.set_environment("SORCMERC_SEED", str(base + attempt))
		if main != null:
			main.queue_free()
			await process_frame
		_did = {}
		_fail = 0
		_quiet = attempt < ATTEMPTS - 1
		main = load("res://scenes/campaign/campaign.tscn").instantiate()
		root.add_child(main)
		await _run()
		_check()
		if _fail == 0:
			break
		print("drive_campaign: attempt %d %s at stage %d, %d assertions unmet — retrying" % [
			attempt + 1, main.run.state, main.run.stage, _fail])
	_summary()

func fail(msg: String) -> void:
	_fail += 1
	if not _quiet:
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
	# T10: a leftover autosave makes the screen ask first. Always start fresh here.
	press(main, "Begin a new run")
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
				# T43: when every road is a fight — stage 0 always is — take the
				# *easiest* one. The old "first option" fallback walked into a normal
				# node (~68% on an AI-vs-AI sweep) while an easy one (~90%) sat right
				# beside it, which is what lost the opening fight on seeds 29 and 44.
				var pick := 0
				var best := 99
				for i in opts.size():
					var rank: int = 0 if opts[i]["kind"] != "combat" \
						else DIFFICULTY_RANK.get(opts[i].get("difficulty", "normal"), 2)
					if rank < best:
						best = rank
						pick = i
				_presses += 1
				_did["Take this road"] = true
				_did["node:" + String(opts[pick]["kind"])] = true
				roads[mini(pick, roads.size() - 1)].pressed.emit()
			"visiting":
				_visit_step()
			"combat":
				await process_frame   # the overlay is coming up

# --- assertions on the walked run --------------------------------------------
func _check() -> void:
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

func _summary() -> void:
	print("drive_campaign: %d presses, stage %d/%d, state=%s, %d gp, %d XP, %d quests — %s" % [
		_presses, main.run.stage, main.run.route.size(), main.run.state,
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

# One hero turn on the real combat screen: the party plays itself with the same
# AI the foes use, then the real End-turn button hands back to the turn loop.
# T41: the old version closed to melee and swung by hand, which lost the opening
# fight — and since T12 made stage 0 combat-only there is no road around it, so
# the run ended at stage 0 and every later assertion failed. This smoke test is
# about the campaign wiring; tests/drive_ui.gd exercises the verb menu properly.
func _fight_step() -> void:
	var fight = main._combat
	var cb = fight.cb
	if cb == null or fight._busy or not fight.result.is_empty():
		return
	_presses += 1
	_did["fight"] = true
	if fight._mode == "deploy":            # T39: a scouted node deploys first
		if not press(fight, "Begin"):
			fail("no way out of the deployment phase")
		return
	AI.take_turn(cb, cb.current())
	var btns: Array = []
	for b in fight._buttons.get_children():
		if b is Button and not b.is_queued_for_deletion():
			btns.append(b)
	if not btns.is_empty():
		btns[btns.size() - 1].pressed.emit()   # End turn
