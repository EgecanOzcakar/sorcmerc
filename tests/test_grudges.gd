# #231 — the monster peoples' grudge (core/grudges.gd). The model only, headless.
#   godot --headless --path . -s tests/test_grudges.gd
extends SceneTree

const Grudges = preload("res://core/grudges.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	Grudges.reset()
	FactionOpinion.reset()
	check(Grudges.get_grudge("gnoll") == 0.0 and Grudges.all().is_empty(), "none to start")
	Grudges.add("gnoll", Grudges.BAND)
	Grudges.add("gnoll", -Grudges.BAND)   # amounts are sizes: a deed only ever adds
	check(is_equal_approx(Grudges.get_grudge("gnoll"), 2.0 * Grudges.BAND), "two bands put down (%.1f)" % Grudges.get_grudge("gnoll"))
	for _i in 20:
		Grudges.add("gnoll", Grudges.LAIR)
	check(is_equal_approx(Grudges.get_grudge("gnoll"), Grudges.MAX), "capped at MAX")
	# Only a monster people holds one, and it never touches FactionOpinion.
	Grudges.add("human", Grudges.LAIR)
	Grudges.add("", Grudges.LAIR)
	check(Grudges.get_grudge("human") == 0.0 and not Grudges.all().has(""), "a civilized people holds none")
	check(FactionOpinion.all().is_empty(), "FactionOpinion untouched")
	# Cooling: DECAY_PER_DAY a day, gone at zero.
	Grudges.set_grudge("orc", 3.0)
	Grudges.tick(Grudges.DAY)
	check(is_equal_approx(Grudges.get_grudge("orc"), 3.0 - Grudges.DECAY_PER_DAY), "a day cools it by DECAY_PER_DAY")
	Grudges.tick(Grudges.DAY)
	check(not Grudges.all().has("orc"), "cooled to nothing, gone")
	Grudges.tick(0.0)
	Grudges.tick(-5.0)
	check(is_equal_approx(Grudges.get_grudge("gnoll"), Grudges.MAX - 2.0 * Grudges.DECAY_PER_DAY), "the same two days cooled the gnolls; no time, no more cooling")
	# The save: a round trip, junk read as nothing.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Grudges.all()))
	Grudges.reset()
	Grudges.load_all(saved)
	check(is_equal_approx(Grudges.get_grudge("gnoll"), Grudges.MAX - 2.0 * Grudges.DECAY_PER_DAY), "survives a save")
	Grudges.load_all({"human": 40, "kobold": -3, "beast": 250})
	check(Grudges.all().keys() == ["beast"] and Grudges.get_grudge("beast") == Grudges.MAX, "junk reads as nothing, too much as MAX")
	Grudges.reset()
	print("test_grudges: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
