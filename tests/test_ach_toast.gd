# The achievement toast layer: a card per newly-earned achievement, top-right,
# capped, and silent when the player has turned the popups off.
#
#   godot --headless --path . -s tests/test_ach_toast.gd
#
# The autoload itself never exists in a run like this one (a script run as the
# main loop instantiates none), so the test stands the node up by hand. It also
# has to re-enable _process: toast.gd switches it off under the headless display
# server, which is the behaviour the real game wants and the one thing a test of
# it must undo.
extends SceneTree

const Ach = preload("res://core/achievements.gd")
const Toasts = preload("res://scenes/achievements/toast.gd")
const Settings = preload("res://core/settings.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	_wipe()
	await test_one_card()
	await test_cap()
	await test_popups_off()
	await test_headless_is_quiet()
	_wipe()
	print("test_ach_toast: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()
	# Between 02:00 and 05:00 local time Toasts._ready's own check_calendar()
	# would unlock night_owl and put a card up before the test's; earn it here,
	# where the queue is about to be drained (unlock is idempotent, so _ready's
	# second call queues nothing).
	Ach.check_calendar()
	Ach.take_toasts()
	var s = Settings.new()
	s.achievement_popups = true
	Settings._current = s

# A live layer with its _process switched back on. The frame in between is
# load-bearing: a node added to root from a SceneTree's own _init does not reach
# _ready until the tree is actually running, and _ready is what switches
# processing off under the headless display server.
func _layer():
	var t = Toasts.new()
	root.add_child(t)
	await process_frame
	t.set_process(true)
	return t

func _cards(t) -> int:
	return t._live.size()

func test_one_card() -> void:
	_wipe()
	var t = await _layer()
	check(_cards(t) == 0, "nothing earned, nothing on screen")
	Ach.unlock("first_victory")
	await process_frame
	check(_cards(t) == 1, "an unlock puts one card up")
	var card = t._live[0]
	check(card.get_combined_minimum_size().x >= Toasts.WIDTH, "the card is at least as wide as it asked to be")
	# Top-right: the left edge sits a card's width in from the right margin once
	# the slide has finished. Mid-slide it is further out, which is the point.
	t._slide(0.0, card)
	t._layout()
	var view := root.get_visible_rect().size
	check(is_equal_approx(card.position.x, view.x - Toasts.MARGIN.x - Toasts.WIDTH),
		"a settled card sits against the right margin")
	check(is_equal_approx(card.position.y, Toasts.MARGIN.y), "...and under the top one")
	check(card.get_meta("slide", -1.0) == 0.0, "the slide runs to zero")
	t.free()

func test_cap() -> void:
	_wipe()
	var t = await _layer()
	# Six at once: three go up, the rest wait their turn rather than stacking
	# down the whole side of the screen.
	for id in ["first_victory", "death_save", "identify_item", "level_5", "level_10", "retire_run"]:
		Ach.unlock(id)
	await process_frame
	check(_cards(t) == Toasts.MAX_VISIBLE, "never more than MAX_VISIBLE cards at once")
	check(t._waiting.size() == 3, "the rest are queued, not dropped")
	# Cards stack downwards, in order, without overlapping.
	t._layout()
	var last := -1.0
	var ordered := true
	for card in t._live:
		if card.position.y <= last:
			ordered = false
		last = card.position.y + card.size.y
	check(ordered, "the stack runs top to bottom without overlap")
	t.free()

func test_popups_off() -> void:
	_wipe()
	Settings.current().achievement_popups = false
	var t = await _layer()
	Ach.unlock("first_victory")
	await process_frame
	check(_cards(t) == 0, "popups off: no card")
	check(Ach.is_unlocked("first_victory"), "...but the achievement is still earned")
	check(t._waiting.is_empty(), "...and the queue does not pile up behind the setting")
	t.free()

func test_headless_is_quiet() -> void:
	_wipe()
	# The real _ready path: headless turns its own _process off, so nothing is
	# ever built during the test suite or a drive robot's run.
	var t = Toasts.new()
	root.add_child(t)
	Ach.unlock("first_victory")
	await process_frame
	await process_frame
	check(_cards(t) == 0, "headless builds no cards at all")
	t.free()
