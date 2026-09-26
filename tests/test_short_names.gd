# The initiative bar's short names (core/combatant.gd short_name/species_short).
# A creature known by its kind used to read as its kind's first word, so an
# adult red dragon was "Adult" on the bar and a giant rat "Giant" (the far-deeps
# build log's Still open, 2026-09-25).
#   godot --headless --path . -s tests/test_short_names.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Combatant = preload("res://core/combatant.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Presets = preload("res://core/presets.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_kinds()
	test_spawned()
	test_every_bestiary_kind()
	print("test_short_names: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_kinds() -> void:
	var want := {
		"Adult Red Dragon": "Red Dragon", "Ancient White Dragon": "White Dragon",
		"Young Silver Dragon": "Silver Dragon", "Giant Rat": "Rat", "Giant Rat (Diseased)": "Rat",
		"Giant Wolf Spider": "Wolf Spider", "Giant Poisonous Snake": "Snake", "Dire Wolf": "Wolf",
		"Hill Giant": "Hill Giant", "Giant": "Giant", "Wererat, Human Form": "Wererat",
		"Swarm of Wasps": "Wasps", "Goblin": "Goblin", "Adult Red Dragon 2": "Red Dragon",
		"Black Dragon Wyrmling": "Wyrmling", "Hill Giant Archer": "Giant Archer",
	}
	for name in want:
		check(Combatant.species_short(name) == want[name],
			"%s -> %s (got %s)" % [name, want[name], Combatant.species_short(name)])

func test_spawned() -> void:
	var dragon = Encounter.spawn("adult-red-dragon", 1.0, "foe", Vector2i.ZERO)
	check(dragon.short_name() == "Red Dragon", "an adult red dragon reads Red Dragon on the bar (%s)" % dragon.short_name())
	var second = Encounter.spawn("adult-red-dragon", 1.0, "foe", Vector2i(1, 0), 2)
	check(second.cname.ends_with(" 2") and second.short_name() == "Red Dragon",
		"its second copy too: the bar never showed the number (%s / %s)" % [second.cname, second.short_name()])
	var rat = Encounter.spawn("giant-rat", 1.0, "foe", Vector2i.ZERO)
	check(rat.short_name() == "Rat", "a giant rat is a Rat, not a Giant (%s)" % rat.short_name())
	# a foe with a name of its own keeps its first word, as it always did
	var gob = Encounter.spawn("goblin", 1.0, "foe", Vector2i(2, 0))
	check(" the " in gob.cname and gob.short_name() == gob.cname.split(" ")[0],
		"a named goblin is its own name (%s -> %s)" % [gob.cname, gob.short_name()])
	# and so does a hero
	var vera = Adapter.to_combatant(Presets.vera(), "party", Vector2i.ZERO)
	check(vera.short_name() == vera.cname.split(" ")[0], "a hero is her first name (%s)" % vera.short_name())
	# an explicit short (a summon, an objective's captive) wins
	dragon.short = "Ember"
	check(dragon.short_name() == "Ember", "an explicit short name wins")

# Every kind the bestiary can field reads as something: never empty, never a
# comma or bracket, never an age or size word unless that is the whole name,
# and short enough for the bar unless it is one word.
func test_every_bestiary_kind() -> void:
	var bad: Array = []
	for m in Catalog.all("bestiary.json"):
		var name := String(m["cname"])
		var s := Combatant.species_short(name)
		var ok := s != "" and not "," in s and not "(" in s \
			and (not s in Combatant.AGE_WORDS or s == name) \
			and (s.length() <= Combatant.SHORT_MAX or not " " in s)
		if not ok:
			bad.append("%s -> %s" % [name, s])
	check(bad.is_empty(), "every bestiary kind has a bar name (%s)" % str(bad))
