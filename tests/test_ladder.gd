# The ladder (core/ladder.gd): deeds per faction that never drop, four named
# rungs, one party-wide renown title, one audience per faction.
#   godot --headless --path . -s tests/test_ladder.gd
extends SceneTree

const Ladder = preload("res://core/ladder.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	Ladder.reset()
	check(Ladder.deeds("human") == 0 and Ladder.rung("human") == 0 and Ladder.rung_name("human") == "Stranger",
		"a fresh ladder: strangers everywhere")
	check(Ladder.renown() == 0 and Ladder.title_index() == 0 and Ladder.title() == "Nobodies" and Ladder.pay_mult() == 1.0,
		"...and nobodies")
	check(Ladder.deed("human") == -1 and Ladder.deeds("human") == 1, "one deed, still a stranger, no rung change reported")
	check(Ladder.deed("human", 2) == -1 and Ladder.deeds("human") == 3, "three")
	check(Ladder.deed("human") == Ladder.KNOWN and Ladder.rung("human") == Ladder.KNOWN and Ladder.rung_name("human") == "Known",
		"the fourth deed makes them Known, and says so once")
	check(Ladder.deed("human") == -1, "the fifth says nothing")
	check(Ladder.deed("human", 7) == Ladder.TRUSTED and Ladder.deeds("human") == 12, "twelve: Trusted")
	check(Ladder.deed("human", 13) == Ladder.SWORN and Ladder.deeds("human") == 25, "twenty-five: Sworn")
	check(Ladder.deed("human", 100) == -1 and Ladder.rung("human") == Ladder.SWORN, "nothing above Sworn")
	check(Ladder.deed("goblinoid", 5) == -1 and Ladder.deeds("goblinoid") == 0, "a monster faction takes no deeds")
	check(Ladder.deed("human", 0) == -1 and Ladder.deed("human", -3) == -1 and Ladder.deeds("human") == 125,
		"zero and negative deeds change nothing: standing never drops")
	# renown is the sum over civilized factions
	Ladder.reset()
	Ladder.deed("human", 3)
	Ladder.deed("elf", 2)
	Ladder.deed("orc", 50)
	check(Ladder.renown() == 5 and Ladder.title() == "Nobodies", "five deeds across two peoples; the orcs count for nothing")
	Ladder.deed("dwarf", 1)
	check(Ladder.title_index() == 1 and Ladder.title() == "Hirelings" and absf(Ladder.pay_mult() - 1.1) < 0.001, "six: Hirelings, +10 %")
	Ladder.deed("human", 12)
	check(Ladder.title() == "a Company of Note" and absf(Ladder.pay_mult() - 1.2) < 0.001, "eighteen")
	check(Ladder.title_cap() == "A Company of Note", "...capitalised for the start of a line, not title-cased: %s" % Ladder.title_cap())
	check(Ladder.people("elf") == "elves" and Ladder.people("goblin") == "goblins", "the plural people")
	Ladder.deed("human", 22)
	check(Ladder.title() == "Asked For by Name", "forty")
	Ladder.deed("elf", 40)
	check(Ladder.title() == "Sung Wrong in Taverns" and absf(Ladder.pay_mult() - 1.4) < 0.001, "eighty: Sung Wrong in Taverns, +40 %")
	# audiences
	check(not Ladder.audience_held("human"), "no audience yet")
	Ladder.hold_audience("human")
	check(Ladder.audience_held("human") and not Ladder.audience_held("elf"), "held once, per faction")
	Ladder.hold_audience("human")
	check(Ladder.all()["audiences"].size() == 1, "holding it twice records it once")
	# the save shape
	var d: Dictionary = Ladder.all()
	check(d["deeds"]["human"] == 37 and d["deeds"]["elf"] == 42 and not d["deeds"].has("orc") and d["audiences"] == ["human"],
		"all() is the two dictionaries the save writes (%s)" % str(d))
	Ladder.reset()
	check(Ladder.renown() == 0 and not Ladder.audience_held("human"), "reset clears both")
	Ladder.load(d)
	check(Ladder.deeds("human") == 37 and Ladder.rung("human") == Ladder.SWORN and Ladder.audience_held("human") and Ladder.title() == "Sung Wrong in Taverns",
		"load() restores them")
	Ladder.load({})
	check(Ladder.renown() == 0 and not Ladder.audience_held("human"), "load({}) is a fresh ladder")
	Ladder.load({"deeds": {"human": "7"}, "audiences": ["elf"]})
	check(Ladder.deeds("human") == 7 and Ladder.audience_held("elf"), "a value that came back as a string is read as an int")
	print("test_ladder: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
