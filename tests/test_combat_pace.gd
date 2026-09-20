# "we need to put some weight into the move and attack/spell animations during
# the combat, right now it feels like they are in fast mode, which settings
# would help enable"
#
# The answer to the last part was: none. anim_speed_multiplier was floored at
# 1.0 both on load and in anim() — the dial only turned one way, so the only
# thing the setting could ever do was make the fight quicker. This covers both
# halves of the fix: the setting can now ask for slower, and the animations
# themselves carry weight at 1x.
#
#   godot --headless --path . -s tests/test_combat_pace.gd
extends SceneTree

const Settings = preload("res://core/settings.gd")
const Board = preload("res://scenes/main.gd").Board

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var had := OS.get_environment("SORCMERC_FAST")

	# --- the setting turns both ways now ---------------------------------
	OS.set_environment("SORCMERC_FAST", "")
	var s = Settings.current()
	var was: float = s.anim_speed_multiplier
	check(Settings.ANIM_MIN < 1.0, "the dial goes below normal (%.2f)" % Settings.ANIM_MIN)
	s.anim_speed_multiplier = 0.55
	check(is_equal_approx(Settings.anim(), 0.55),
		"a slower pace is obeyed instead of floored at 1.0 (%.2f)" % Settings.anim())
	s.anim_speed_multiplier = 1.6
	check(is_equal_approx(Settings.anim(), 1.6), "and a quicker one still is")

	# SORCMERC_FAST still wins outright — the suite depends on it, and a test
	# run must not be slowed down by whatever settings.json is on the machine.
	s.anim_speed_multiplier = 0.55
	OS.set_environment("SORCMERC_FAST", "1")
	check(Settings.anim() == Settings.FAST, "SORCMERC_FAST overrides a slow setting")
	OS.set_environment("SORCMERC_FAST", "")

	# Clamped on the way in, so a hand-edited file cannot ask for a slideshow.
	var probe = Settings.new()
	probe.anim_speed_multiplier = 0.01
	Settings.save_settings(probe)
	var loaded = Settings.load_settings()
	check(loaded.anim_speed_multiplier >= Settings.ANIM_MIN,
		"an absurd slow value clamps to ANIM_MIN (%.2f)" % loaded.anim_speed_multiplier)
	probe.anim_speed_multiplier = 50.0
	Settings.save_settings(probe)
	loaded = Settings.load_settings()
	check(loaded.anim_speed_multiplier <= Settings.ANIM_MAX,
		"...and an absurd fast one to ANIM_MAX (%.2f)" % loaded.anim_speed_multiplier)
	# ...except FAST itself, which is a real stored choice (the Instant pace).
	probe.anim_speed_multiplier = Settings.FAST
	Settings.save_settings(probe)
	loaded = Settings.load_settings()
	check(loaded.anim_speed_multiplier == Settings.FAST, "Instant survives the round trip")

	# --- the paces the settings screen offers ----------------------------
	var speeds: Array = []
	for p in Settings.ANIM_PACES:
		check(p.has("id") and p.has("label") and p.has("speed") and p.has("note"),
			"every pace names itself")
		speeds.append(float(p["speed"]))
	check(speeds.size() >= 3, "there is more than a two-way toggle (%d paces)" % speeds.size())
	check(speeds[0] < 1.0, "the slowest pace is slower than normal (%.2f)" % speeds[0])
	check(speeds.has(1.0), "normal is one of them")
	check(speeds.has(Settings.FAST), "and the old fast toggle survives as a pace")
	var sorted: Array = speeds.duplicate()
	sorted.sort()
	check(speeds == sorted, "they are offered slowest first (%s)" % str(speeds))
	for sp in speeds:
		check(is_equal_approx(float(Settings.pace_for(sp)["speed"]), sp),
			"pace_for finds the pace a stored %.2f means" % sp)
	check(Settings.pace_for(0.9)["id"] == "normal", "...and the nearest one for anything else")

	s.anim_speed_multiplier = was

	# --- and the animations themselves carry weight at 1x ----------------
	#
	# The numbers, not the feel: a strike has to be on screen long enough to
	# find, and a token crossing six hexes has to take longer than one crossing
	# a single hex. The old lerp did neither — a fixed exponential rate meant
	# every move took the same ~0.25s whatever the distance, which is most of
	# why a fight read as "fast mode" even at normal speed.
	check(Board.FX_TTL["melee"] >= 0.40, "a melee swing is on screen long enough to read (%.2f)"
		% Board.FX_TTL["melee"])
	check(Board.FX_TTL["spell"] > Board.FX_TTL["melee"], "a spell takes longer than a swing")
	check(Board.FX_TTL["ranged"] > Board.FX_TTL["melee"], "...and so does a shot in flight")
	check(Board.LUNGE_REACH > 0.55, "the step-in actually leaves the tile (%.2f)" % Board.LUNGE_REACH)

	# Distance-aware: duration scales with hexes crossed, between the two caps.
	var one: float = clampf(1.0 / Board.TOKEN_HEXES_PER_SEC, Board.STEP_MIN, Board.STEP_MAX)
	var six: float = clampf(6.0 / Board.TOKEN_HEXES_PER_SEC, Board.STEP_MIN, Board.STEP_MAX)
	check(six > one * 2.0, "a six-hex dash takes far longer than a step (%.2fs vs %.2fs)" % [six, one])
	check(one >= Board.STEP_MIN, "even a single step gets a moment (%.2fs)" % one)
	check(six <= Board.STEP_MAX, "and the longest move is not a journey (%.2fs)" % six)

	# Eased, not linear: something with mass leans in and settles.
	check(is_equal_approx(Board._ease_move(0.0), 0.0) and is_equal_approx(Board._ease_move(1.0), 1.0),
		"the ease starts and ends where the move does")
	check(Board._ease_move(0.1) < 0.1, "it leans in rather than starting at full speed")
	check(Board._ease_move(0.9) > 0.9, "and settles rather than creeping in")
	check(is_equal_approx(Board._ease_move(0.5), 0.5), "symmetric through the middle")

	OS.set_environment("SORCMERC_FAST", had)
	print("test_combat_pace: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
