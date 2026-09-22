# The climb (core/climb.gd): twenty rungs for every class, the path's tiers
# merged into the class's, and veiling that both screens can agree on.
#   godot --headless --path . -s tests/test_climb.gd
extends SceneTree

const Climb = preload("res://core/climb.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Character = preload("res://core/character.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	# --- every class climbs to twenty ---------------------------------------
	for c in Catalog.all("classes.json"):
		var t := Climb.build(String(c["id"]))
		check(t.size() == 20, "%s: twenty rungs" % c["id"])
		var levels: Array = []
		for e in t:
			levels.append(int(e["level"]))
		check(levels == range(1, 21), "%s: rungs are 1..20 in order" % c["id"])

	check(Climb.build("not-a-class").is_empty(), "an unknown class climbs nowhere")

	# --- the merge, which is the whole point --------------------------------
	# Barbarian 14 is a level the CLASS grants nothing at: the path does.
	var bare := Climb.build("barbarian")
	check(bare[13]["grants"].is_empty(), "barbarian 14 is bare without a path")
	var berserk := Climb.build("barbarian", "berserker")
	check(not berserk[13]["grants"].is_empty(), "...and carries the path's tier with one")
	check(Climb.headline(berserk[13]) == "Intimidating Presence",
		"barbarian 14 is named by the path feature, got '%s'" % Climb.headline(berserk[13]))

	# A path tier never leaks into another path's track.
	var zealot := Climb.build("barbarian", "zealot")
	check(Climb.headline(zealot[13]) == "Rage of the Gods",
		"the Zealot's 14 is its own, got '%s'" % Climb.headline(zealot[13]))

	# --- the fork ------------------------------------------------------------
	var fork: Array = berserk[2]["fork"]
	check(fork.size() == 4, "barbarian 3 forks four ways, got %d" % fork.size())
	var ids: Array = []
	for p in fork:
		ids.append(String(p["id"]))
	check("berserker" in ids and "zealot" in ids, "the fork names the paths")
	check(berserk[4]["fork"].is_empty(), "a level with no subclass grant does not fork")
	check(Climb.paths_for("fighter").size() == 4, "fighter offers four paths")
	check(Climb.paths_for("not-a-class").is_empty(), "an unknown class offers none")

	# --- taken / next / veiled ----------------------------------------------
	var at5 := Climb.build("rogue", "thief", 5)
	check(at5[4]["taken"] and not at5[4]["next"] and not at5[4]["veiled"], "level 5 of 5 is taken")
	check(at5[5]["next"] and not at5[5]["veiled"] and not at5[5]["taken"], "level 6 is next")
	check(at5[6]["veiled"], "level 7 is veiled")
	check(not at5[0]["veiled"] and at5[0]["taken"], "level 1 is behind you")
	var fresh := Climb.build("rogue", "", 0)
	check(fresh[0]["next"] and fresh[1]["veiled"],
		"an untaken class: level 1 is next and everything above it is veiled")
	var maxed := Climb.build("rogue", "thief", 20)
	var any_open := false
	for e in maxed:
		if e["next"] or e["veiled"]:
			any_open = true
	check(not any_open, "at 20 nothing is next and nothing is veiled")

	# --- headlines -----------------------------------------------------------
	check(Climb.headline(at5[2]) == "Your path", "the subclass level is named for the fork")
	check(Climb.headline(at5[3]) == "Ability score or feat", "rogue 4 is the ASI")
	check(Climb.headline(Climb.build("warlock")[17]) == "Hit points only",
		"the warlock's bare 18 says so plainly")
	var fighter := Climb.build("fighter", "champion", 20)
	check(Climb.headline(fighter[10]) == "Extra Attack 2",
		"fighter 11, restored by the fill, got '%s'" % Climb.headline(fighter[10]))
	check(Climb.headline(Climb.build("rogue", "thief", 20)[19]) == "Stroke of Luck",
		"rogue 20, restored by the fill")

	# --- slots are news only when they change --------------------------------
	var wiz := Climb.build("wizard", "evoker", 20)
	check(not wiz[0]["slots"].is_empty(), "a wizard's first slots are news")
	var repeats := 0
	for e in wiz:
		if e["slots"].is_empty():
			repeats += 1
	check(repeats > 0 and repeats < 20, "some wizard levels repeat the slot row (%d of 20)" % repeats)
	check(Climb.build("fighter", "champion")[4]["slots"].is_empty(),
		"a fighter's rungs carry no slot row")

	# --- summary -------------------------------------------------------------
	var sum := Climb.summary(berserk)
	check(int(sum["forks"]) == 1, "one fork in a barbarian's climb")
	check(int(sum["features"]) > 10, "a climb of twenty has features on it (%d)" % sum["features"])
	check(int(sum["choices"]) > 0, "...and choices to make (%d)" % sum["choices"])

	# --- from a real build ---------------------------------------------------
	check(Climb.track(null).is_empty(), "no character, no climb")
	var ch = Character.new()
	check(Climb.track(ch).is_empty(), "a character with no levels has no climb")
	ch.add_level("rogue")
	ch.add_level("rogue")
	var t := Climb.track(ch)
	check(t.size() == 20, "a level 2 rogue still sees all twenty rungs")
	check(t[1]["taken"] and t[2]["next"], "the build's own level sets the mark")

	print("%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
