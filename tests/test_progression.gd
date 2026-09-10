# Meta-progression: starting unlocks, lifetime-XP thresholds, the 2-of-4 subclass
# choice, class-XP purchases, persistence — plus the viewer standing up on its own.
#   godot --headless --path . -s tests/test_progression.gd
extends SceneTree

const Prog = preload("res://core/progression.gd")
const Catalog = preload("res://core/rules/catalog.gd")

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
	test_starting_state()
	test_costs_ordered()
	test_species_threshold()
	test_class_threshold_and_picks()
	test_class_xp_subclasses()
	test_round_trip()
	test_unknown_ids()
	await test_viewer()
	_wipe()
	print("test_progression: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Prog.PATH))
	Prog._current = Prog.load_state()

func test_starting_state() -> void:
	check(Prog.lifetime_xp_total() == 0, "a fresh profile has no lifetime XP")
	for id in Prog.STARTING_SPECIES:
		check(Prog.is_species_unlocked(id), "%s is open from day one" % id)
		check(Prog.species_cost(id) == 0, "%s costs nothing" % id)
		for lin in Catalog.species_src(id).get("lineages", []):
			check(Prog.is_lineage_unlocked(id, lin["id"]),
				"%s lineage %s comes with it" % [id, lin["id"]])
	for id in Prog.SPECIES_COST:
		check(not Prog.is_species_unlocked(id), "%s starts locked" % id)
	for id in Prog.STARTING_CLASSES:
		check(Prog.is_class_unlocked(id), "%s is open from day one" % id)
		check(not Prog.awaits_picks(id), "%s already has its 2 picks" % id)
		var free: Array = Prog.free_subclasses(id)
		check(free.size() == 2, "%s ships with exactly 2 subclasses" % id)
		for s in free:
			check(s in Catalog.subclasses_of(id), "%s is a real %s subclass" % [s, id])
			check(Prog.is_subclass_unlocked(s), "%s is unlocked with zero class XP" % s)
		var paid: Array = Prog.paid_subclasses(id)
		check(paid.size() == 2, "%s keeps 2 subclasses behind class XP" % id)
		for s in paid:
			check(not Prog.is_subclass_unlocked(s), "%s stays locked at zero class XP" % s)
	for id in Prog.CLASS_COST:
		check(not Prog.is_class_unlocked(id), "%s starts locked" % id)

func test_costs_ordered() -> void:
	var dearest_species := 0
	for id in Prog.SPECIES_COST:
		dearest_species = maxi(dearest_species, Prog.species_cost(id))
	var cheapest_class := 999999
	for id in Prog.CLASS_COST:
		cheapest_class = mini(cheapest_class, Prog.class_cost(id))
	check(dearest_species < cheapest_class, "every species costs less than every class")

func test_species_threshold() -> void:
	Prog.add_lifetime_xp(2999)
	check(not Prog.is_species_unlocked("gnome"), "one XP short is still locked")
	check(not Prog.unlock_species("gnome"), "unlock_species reports the shortfall")
	Prog.add_lifetime_xp(1)
	check(Prog.is_species_unlocked("gnome"), "crossing the threshold unlocks it")
	check(Prog.unlock_species("gnome"), "unlock_species confirms it")
	check(Prog.is_lineage_unlocked("gnome", "forest"), "its lineages come with it")
	check(not Prog.is_species_unlocked("tiefling"), "the dearer ones stay locked")

func test_class_threshold_and_picks() -> void:
	Prog.add_lifetime_xp(Prog.class_cost("rogue") - Prog.lifetime_xp_total())
	check(Prog.is_class_unlocked("rogue"), "crossing the threshold unlocks the class")
	check(Prog.awaits_picks("rogue"), "an unlocked class owes 2 picks")
	check(not Prog.is_subclass_unlocked("thief"), "no subclass until the picks are made")
	check(not Prog.unlock_class("rogue", ["thief"]), "one pick is rejected")
	check(not Prog.unlock_class("rogue", ["thief", "assassin", "soulknife"]),
		"three picks are rejected")
	check(not Prog.unlock_class("rogue", ["thief", "thief"]), "a duplicate is rejected")
	check(not Prog.unlock_class("rogue", ["thief", "berserker"]),
		"another class's subclass is rejected")
	check(not Prog.unlock_class("bard", ["collegelore", "collegevalor"]),
		"a class below its threshold cannot pick")
	check(Prog.unlock_class("rogue", ["thief", "soulknife"]), "2 valid picks are taken")
	check(Prog.is_subclass_unlocked("thief") and Prog.is_subclass_unlocked("soulknife"),
		"the picks are unlocked")
	check(not Prog.is_subclass_unlocked("assassin"), "the other 2 still cost class XP")
	check(not Prog.unlock_class("rogue", ["assassin", "arcanetrickster"]),
		"picks cannot be made twice")

func test_class_xp_subclasses() -> void:
	var paid: Array = Prog.paid_subclasses("cleric")
	check(paid == ["trickerydomain", "wardomain"], "cleric's paid pair is the other 2")
	check(Prog.subclass_remaining(paid[0]) == Prog.SUBCLASS_COST, "full price at zero")
	Prog.add_class_xp("cleric", Prog.SUBCLASS_COST - 1)
	check(not Prog.is_subclass_unlocked(paid[0]), "one XP short is still locked")
	check(Prog.subclass_remaining(paid[0]) == 1, "remaining counts down")
	Prog.add_class_xp("cleric", 1)
	check(Prog.class_xp_of("cleric") == Prog.SUBCLASS_COST, "class XP accumulates")
	check(Prog.is_subclass_unlocked(paid[0]), "5000 class XP buys the first")
	check(not Prog.is_subclass_unlocked(paid[1]), "the second needs 5000 more")
	Prog.add_class_xp("cleric", Prog.SUBCLASS_COST)
	check(Prog.is_subclass_unlocked(paid[1]), "10000 buys both")
	check(Prog.class_xp_of("wizard") == 0, "class XP does not leak between classes")
	check(not Prog.is_subclass_unlocked("diviner"), "another class stays locked")

func test_round_trip() -> void:
	var back = Prog.load_state()
	check(back.lifetime_xp == Prog.lifetime_xp_total(), "lifetime XP survives a reload")
	check(back.class_xp.get("cleric") == 2 * Prog.SUBCLASS_COST, "class XP survives")
	check(back.chosen.get("rogue") == ["thief", "soulknife"], "the picks survive")

	# Garbage in the file falls back to a fresh, nothing-earned profile.
	var f := FileAccess.open(Prog.PATH, FileAccess.WRITE)
	f.store_string('{"format":"nope","lifetime_xp":99999}')
	f.close()
	check(Prog.load_state().lifetime_xp == 0, "unknown format falls back to defaults")
	# Junk inside a good file is dropped rather than trusted.
	f = FileAccess.open(Prog.PATH, FileAccess.WRITE)
	f.store_string('{"format":"%s","lifetime_xp":-5,"class_xp":{"gone":7},' % Prog.FORMAT
		+ '"chosen":{"bard":["thief","assassin"],"monk":["warriorofmercy","warriorofshadow"]}}')
	f.close()
	var pruned = Prog.load_state()
	check(pruned.lifetime_xp == 0, "a negative total clamps to zero")
	check(pruned.class_xp.is_empty(), "class XP for an unknown class is dropped")
	check(not pruned.chosen.has("bard"), "picks from the wrong class are dropped")
	check(pruned.chosen.get("monk") == ["warriorofmercy", "warriorofshadow"],
		"valid picks are kept")
	Prog._current = pruned

func test_unknown_ids() -> void:
	check(not Prog.is_species_unlocked("kobold"), "unknown species is locked")
	check(Prog.species_cost("kobold") == 0, "unknown species has no price")
	check(not Prog.unlock_species("kobold"), "unknown species cannot unlock")
	check(not Prog.is_class_unlocked("warlord"), "unknown class is locked")
	check(Prog.class_cost("warlord") == 0, "unknown class has no price")
	check(not Prog.unlock_class("warlord", ["a", "b"]), "unknown class cannot pick")
	check(Prog.class_xp_of("warlord") == 0, "unknown class has no XP")
	check(Prog.add_class_xp("warlord", 500) == 0, "unknown class banks nothing")
	check(not Prog.is_subclass_unlocked("nonesuch"), "unknown subclass is locked")
	check(Prog.subclass_remaining("nonesuch") == 0, "unknown subclass has no price")
	check(Prog.add_lifetime_xp(-100) == 0, "negative XP is ignored")

func test_viewer() -> void:
	var v = load("res://scenes/progression/progression.tscn").instantiate()
	root.add_child(v)
	await process_frame
	check(v.get_child_count() > 0, "viewer builds its UI standalone")
	v.queue_free()
