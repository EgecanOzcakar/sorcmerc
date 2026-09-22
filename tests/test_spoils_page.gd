# #157: the after-action page plays its verdict instead of printing it. What
# is asserted here is the part a player cannot check and a reviewer cannot see
# in a screenshot — that the page is honest at every frame of the sequence and
# at the end of it.
#
#   godot --headless --path . -s tests/test_spoils_page.gd
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Spoils = preload("res://scenes/world/spoils.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

const ROWS := [
	["+400 XP,  +50 gold", Icons.COL_GOLD, "tally"],
	["Taken from the dead: Handaxe", Icons.COL_TEXT],
	["Vera Kord did not get up.", Icons.COL_FOE],
]

func _page(heading := "Victory"):
	var closed := [false]
	var p = Spoils.new()
	root.add_child(p)
	p.build(heading, ROWS, null, "Tip: shove somebody into the fire.",
		func(): closed[0] = true)
	return [p, closed]

func _init() -> void:
	await test_it_is_actually_a_modal()
	await test_fast_is_already_open()
	await test_played_out()
	await test_skip()
	print("test_spoils_page: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The page covers what it is over. set_anchors_preset() moves the anchors and
# then rewrites the offsets to PRESERVE the rect the control already has — on a
# Control built with new(), 0x0 — so the page used to come out with offsets
# (0, 0, -1280, -1280) and no area at all: the dim covered nothing, the
# CenterContainer centred the panel inside its own minimum size and so put it
# in the top-left corner, and a MOUSE_FILTER_STOP rect with no area caught no
# clicks, so the map kept taking them and "click anywhere to skip" could never
# fire. One word (set_anchors_AND_OFFSETS_preset), and nothing else in the file
# would have told anybody it was wrong.
func test_it_is_actually_a_modal() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 800)
	root.add_child(host)
	var p = Spoils.new()
	host.add_child(p)
	p.build("Victory", ROWS, null, "", func(): pass)
	await process_frame
	check(p.size.is_equal_approx(host.size),
		"the page fills what it is laid over (%s of %s)" % [str(p.size), str(host.size)])
	check(p.mouse_filter == Control.MOUSE_FILTER_STOP, "...and it is the one taking the clicks")
	for c in p.get_children():
		check(c.size.is_equal_approx(host.size),
			"%s fills it too, so the dim dims and the panel centres" % c.get_class())
	host.queue_free()
	await process_frame

# The contract every headless run and every UI robot depends on: under
# SORCMERC_FAST the page is fully open on the frame it is built. A test suite
# that had to wait out an animation would be a timing test.
func test_fast_is_already_open() -> void:
	check(Settings.anim() >= Settings.FAST, "the suite runs at Instant (SORCMERC_FAST)")
	var made: Array = _page()
	var p = made[0]
	await process_frame
	check(p._done, "at Instant the page is finished the moment it is built")
	var said := labels(p)
	check("+400 XP,  +50 gold" in said, "the tally row has landed on its real number (%s)" % str(said))
	var on := buttons(p)
	check(on.size() == 1, "exactly one button on the page — the way on")
	check(not on[0].disabled, "...and it is pressable straight away")
	on[0].pressed.emit()
	check(made[1][0], "pressing it closes the page")
	p.queue_free()
	await process_frame

# Wound forward by hand, so the played sequence is checked without waiting for
# it: every label carries its final text from the first frame (the stagger is
# opacity, not content), and the tally counts UP and lands exactly.
func test_played_out() -> void:
	var made: Array = _page()
	var p = made[0]
	await process_frame
	p._done = false
	var tally = p._rows[0]["node"]
	var seen: Array = []
	var was_hidden := false
	var t := 0.0
	while t <= p._end:
		p._t = t
		p._apply()
		# The non-tally rows never lie about what they say, at any point.
		check(String(p._rows[1]["node"].text) == "Taken from the dead: Handaxe",
			"a plain row carries its final text throughout")
		if p._rows[1]["node"].modulate.a < 0.5:
			was_hidden = true
		var n: int = String(tally.text).split(" ")[0].substr(1).to_int()
		if seen.is_empty() or n != int(seen[-1]):
			seen.append(n)
		t += 0.05
	check(was_hidden, "a row is faded out before its beat — the page is staggered, not static")
	check(seen.size() > 2, "the tally counts through more than a couple of values (%s)" % str(seen))
	var rising := true
	for i in range(1, seen.size()):
		if int(seen[i]) < int(seen[i - 1]):
			rising = false
	check(rising, "...and it only ever counts up (%s)" % str(seen))
	p._t = p._end
	p._apply()
	check(String(tally.text) == "+400 XP,  +50 gold",
		"and it lands on the exact string it started from (got %s)" % tally.text)
	# The way on is the last thing to arrive.
	p._t = 0.0
	p._apply()
	check(buttons(p)[0].disabled, "the button is not pressable while the page is still talking")
	p.queue_free()
	await process_frame

# A click anywhere finishes it. Not a button: the page has exactly one of those.
func test_skip() -> void:
	var made: Array = _page()
	var p = made[0]
	await process_frame
	p._done = false
	p._t = 0.0
	p._apply()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	p._skipped(ev)
	check(p._done, "a click finishes the sequence")
	check(String(p._rows[0]["node"].text) == "+400 XP,  +50 gold", "...at the real numbers")
	check(not buttons(p)[0].disabled, "...with the way on pressable")
	check(buttons(p).size() == 1, "and skipping did not add a button of its own")
	p.queue_free()
	await process_frame
