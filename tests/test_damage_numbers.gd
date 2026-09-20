# T-dmg: one damage number per blow.
#
# The number used to be spawned off the HP bar's easing — every frame the bar
# was still travelling, carrying the gap it had left rather than the damage. A
# 14-damage hit drew 21 of them stacked inside 11 px, counting down through the
# colour bands to a pile of "-0" in yellow, and the newest drew last and opaque,
# so "-0" was what the player read. It was worse at a slower pace (39 at
# Weighty) and on a faster monitor (53 at 144 fps), and correct only at Instant,
# where the easing constant clamps to 1 — which is why the headless robots ran
# past it for as long as they did. docs/spike-damage-numbers.md measures it.
#
# Everything here drives Board.tick() with an explicit dt rather than letting
# _process feed it, precisely so the pathological case (small dt, slow pace) is
# the one under test and not the Instant one the suite otherwise runs at.
#   godot --headless --path . -s tests/test_damage_numbers.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Enough ticks for the bar to finish travelling at `dt`, which is exactly the
# window the old code spawned into.
func _settle(board, dt: float, frames := 40) -> void:
	for i in frames:
		board.tick(dt)

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var board = main._board
	var foes: Array = []
	for c in main.cb.combatants:
		if c.team != "party" and not c.is_dead():
			foes.append(c)
	if foes.size() < 2:
		printerr("  FAIL: expected at least two foes on the board")
		quit(1)
		return

	# 60fps at the Normal pace: k = 0.2, the case that drew 21 numbers.
	var dt := 1.0 / 60.0
	_settle(board, dt)
	board._floats.clear()

	var a = foes[0]
	a.hp = maxi(1, a.max_hp - 9)
	_settle(board, dt)
	check(board._floats.size() == 1, "one blow leaves one number, not one per frame")
	if board._floats.size() == 1:
		check(String(board._floats[0].text) == "-9",
			"and it says the damage, not the gap the bar had left")
		check(String(board._floats[0].id) == String(a.id), "and it knows whose it is")
		check(float(board._floats[0].fs) > 0.0, "and carries a size of its own")

	# Weighty is 0.55 and a 144Hz monitor is 1/144: between them the old code
	# spawned 39 and 53. The count must not depend on either.
	for pace in [0.55, 1.0, 1.6]:
		for hz in [30.0, 60.0, 144.0]:
			board._floats.clear()
			var b = foes[1]
			b.hp = b.max_hp
			_settle(board, 1.0 / hz)
			board._floats.clear()
			b.hp = maxi(1, b.max_hp - 5)
			_settle(board, pace / hz, 120)
			check(board._floats.size() <= 1,
				"pace %s at %s fps still spawns at most one" % [pace, hz])

	# A body that has never been hit must still report its first hit: the latch
	# has to be primed by a real write, not by defaulting to the current hp.
	board._floats.clear()
	# Guarded so that against a build without the latch this reports FAILs
	# rather than erroring out of _init, which the runner can only see as a hang.
	check("_dmg_goal" in board, "the latch the numbers hang off exists")
	if "_dmg_goal" in board:
		board._dmg_goal.clear()
	var c2 = foes[1]
	c2.hp = c2.max_hp
	_settle(board, dt, 2)          # seen once, nothing to report
	check(board._floats.is_empty(), "walking onto the board is not damage")
	c2.hp = c2.max_hp - 4
	_settle(board, dt)
	check(board._floats.size() == 1, "and the FIRST hit on it still draws a number")

	# Healing stays silent, as it always has — the spawn is one-directional.
	board._floats.clear()
	c2.hp = c2.max_hp
	_settle(board, dt)
	check(board._floats.is_empty(), "healing draws no number")

	print("test_damage_numbers: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
