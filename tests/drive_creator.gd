# Headless player for the creator: loads the real scene and presses real buttons
# through all six steps until a character is saved. Exercises the UI wiring that
# tests/test_creator.gd (which drives the model directly) never touches.
#   godot --headless --path . -s tests/drive_creator.gd
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Save = preload("res://core/character_save.gd")

var main
var _presses := 0
var _fail := 0

func _init() -> void:
	main = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(main)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

func _buttons(node: Node = null) -> Array:
	var out: Array = []
	for c in (node if node else main._body).get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out

# Presses the first enabled, not-already-selected button whose text contains `label`.
func press(label: String) -> bool:
	for b in _buttons():
		if not b.disabled and label in b.text and not b.text.begins_with("● "):
			_presses += 1
			b.pressed.emit()
			return true
	return false

func next_step() -> void:
	_presses += 1
	main._next.pressed.emit()

# Every choice the current step renders, picked by pressing its option buttons.
func settle_choices(types: Array = []) -> void:
	for _i in 40:
		var pend: Array = []
		for e in main.ch.sheet().pending:
			if types.is_empty() or e["type"] in types:
				pend.append(e)
		if pend.is_empty():
			return
		var p: Dictionary = pend[0]
		var opts := Creator.options_for(p, main.ch.sheet())
		if opts.is_empty():
			fail("%s has no options to press" % p["type"])
			return
		var pressed := false
		for o in opts:
			if press(o["label"]):
				pressed = true
				break
		if not pressed:
			fail("no button on screen for %s (%s)" % [p["type"], p["key"]])
			return

# T34: once every choice on this step is made, the widgets must still be there,
# marked "✓", and pressing an unpicked option must change the stored decision.
func reopen_a_decided_choice() -> void:
	var kids: Array = main._body.get_children()
	for i in kids.size():
		if not (kids[i] is Label and kids[i].text.begins_with("✓ ")):
			continue
		for j in range(i + 1, kids.size()):
			if not kids[j] is HFlowContainer:
				continue
			var before: Dictionary = main.ch.choices.duplicate(true)
			for b in _buttons(kids[j]):
				if not b.disabled and not b.text.begins_with("● "):
					_presses += 1
					b.pressed.emit()
					if main.ch.choices == before:
						fail("re-pressing a decided choice (%s) changed nothing" % kids[i].text)
					return
			fail("decided choice %s offers no alternative to press" % kids[i].text)
			return
	fail("no already-decided choice rendered on the choices step")

func _run() -> void:
	await process_frame
	await process_frame

	# 1. basics — a name, a species with a lineage to pick
	main._body.get_child(1).text = "Smoke Testerson"
	main._body.get_child(1).text_changed.emit("Smoke Testerson")
	if not press("Elf"):
		fail("no species button")
	settle_choices(["lineage-choice"])   # only the lineage widget is on this step
	next_step()
	if main._step != 1:
		fail("stuck on basics: " + main._status.text)

	# 2. class
	if not press("Wizard"):
		fail("no class button")
	next_step()

	# 3. abilities
	if not press("Use quick-build"):
		fail("no quick-build button")
	if main.ch.base_abilities["int"] != 15:
		fail("quick-build did not put the 15 in INT")
	if main.ch.background_id != "sage":
		fail("quick-build did not apply the class's suggested background")
	# Used to be a silent no-op here — the button did nothing at all with no
	# message once you'd switched to Point Buy, which read as "the
	# recommended build doesn't work". Confirmed fixed: it should still
	# apply the standard array (switching modes back) instead of no-op'ing.
	if not press("Point buy"):
		fail("no point-buy toggle")
	main.ch.base_abilities["int"] = 8
	if not press("Use quick-build"):
		fail("no quick-build button while in point-buy mode")
	if main.ch.base_abilities["int"] != 15 or main._abil_mode != "array":
		fail("quick-build silently did nothing from point-buy mode")
	next_step()

	# 4. background + every remaining choice — quick-build already applied
	# Sage above, so there's no unselected "Sage" button left to press here.
	if main.ch.background_id != "sage":
		fail("the background quick-build picked earlier didn't stick")
	settle_choices()
	reopen_a_decided_choice()
	next_step()
	if main._step != 4:
		fail("stuck on choices: " + main._status.text)

	# 5. equipment
	var wid: String = Creator.proficient_weapons(main.ch.sheet())[0]
	if not press(Catalog.weapon(wid)["name"]):
		fail("no weapon button")
	next_step()

	# 6. review -> confirm
	if main._step != 5:
		fail("did not reach review")
	next_step()
	if main._confirmed == null:
		fail("confirm did not produce a character: " + main._status.text)
	else:
		var slug := Save.slugify(main.ch.cname)
		if Save.load_slug(slug) == null:
			fail("the confirmed character did not save")
		Save.delete(slug)

	var s = main.ch.sheet()
	print("drive_creator: %d presses, %s, AC %d HP %d, %d pending — %s" % [
		_presses, main.ch.cname, s.ac, s.max_hp, s.pending.size(),
		"OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)
