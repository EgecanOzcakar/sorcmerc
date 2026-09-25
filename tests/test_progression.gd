# Meta-progression: starting unlocks, lifetime-XP thresholds, the 2-of-4 subclass
# choice, class-XP purchases, persistence — plus the viewer standing up on its own.
#   godot --headless --path . -s tests/test_progression.gd
extends SceneTree

const Prog = preload("res://core/progression.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Leveling = preload("res://core/leveling.gd")
const Creator = preload("res://scenes/creator/creator.gd")

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
	test_shipping_pace()
	test_species_threshold()
	test_class_threshold_and_picks()
	test_class_xp_subclasses()
	test_round_trip()
	test_unknown_ids()
	_wipe()
	test_campaign_banks_xp()
	_wipe()
	test_creator_gates()
	await test_viewer()
	_wipe()
	test_playtest_build_unlocks_everything()
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

# The shipping pace, restored 2026-09-25 (the design audit §5.5; see
# core/progression.gd's header). The ladder ran at a testing pace — every class
# open by 8,000 lifetime XP, partway through a first run — and this test used to
# pin that pace so putting the shipping numbers back would be a red test rather
# than a silent change. They are back, and pinned here by what they buy: where
# on a trio's climb each rung falls, read off core/leveling.gd's own table (fight
# XP only; quests and landmarks come on top, so these are the latest a rung can
# fall, not the earliest).
const TRIO := 3

static func trio_xp_at(level: int) -> int:
	return TRIO * Leveling.xp_for_level(level)

func test_shipping_pace() -> void:
	var species: Array = Prog.SPECIES_COST.values()
	species.sort()
	var classes: Array = Prog.CLASS_COST.values()
	classes.sort()
	check(species.size() == 5 and classes.size() == 7, "the ladder still has twelve rungs")
	check(species == [1500, 3000, 4500, 6000, 7500], "species at the shipping 1,500 step (%s)" % [species])
	check(classes == [10000, 15000, 20000, 25000, 30000, 35000, 40000],
		"classes at the shipping 5,000 step from 10,000 (%s)" % [classes])
	check(Prog.SUBCLASS_COST == 2500, "a paid subclass is the shipping 2,500 class XP")

	# Evenly spaced, so the pace holds between any two neighbours.
	var sstep: int = species[0]
	for i in species.size():
		check(species[i] == sstep * (i + 1), "species rung %d is %d, one even step" % [i, species[i]])
	var cstep: int = classes[1] - classes[0]
	for i in classes.size():
		check(classes[i] == classes[0] + cstep * i, "class rung %d is %d, one even step" % [i, classes[i]])

	# Where the rungs fall on a first trio's climb.
	check(trio_xp_at(3) < species[0] and trio_xp_at(4) >= species[0],
		"the first species opens as the trio reaches level 4 (%d..%d vs %d)" % [trio_xp_at(3), trio_xp_at(4), species[0]])
	check(trio_xp_at(8) < classes[0] and trio_xp_at(9) >= classes[0],
		"the first class opens in the Frontier, around level 9 (%d vs %d)" % [trio_xp_at(9), classes[0]])
	check(trio_xp_at(18) < classes[-1] and trio_xp_at(20) >= classes[-1],
		"the last class is about one whole run to level 20 (%d vs %d)" % [trio_xp_at(20), classes[-1]])
	# Class XP is one hero's share: a paid subclass around level 8, the second
	# around 11.
	check(Leveling.xp_for_level(7) < Prog.SUBCLASS_COST and Leveling.xp_for_level(8) >= Prog.SUBCLASS_COST,
		"one hero banks a paid subclass's class XP at about level 8")
	check(Leveling.xp_for_level(10) < 2 * Prog.SUBCLASS_COST and Leveling.xp_for_level(11) >= 2 * Prog.SUBCLASS_COST,
		"...and the second at about level 11")

func test_species_threshold() -> void:
	Prog.add_lifetime_xp(Prog.species_cost("gnome") - 1)
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
	check(Prog.is_subclass_unlocked(paid[0]), "SUBCLASS_COST class XP buys the first")
	check(not Prog.is_subclass_unlocked(paid[1]), "the second needs SUBCLASS_COST more")
	Prog.add_class_xp("cleric", Prog.SUBCLASS_COST)
	check(Prog.is_subclass_unlocked(paid[1]), "2x SUBCLASS_COST buys both")
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

# The wiring: a campaign victory's XP has to land here too, once for the account
# and per-class for whoever was in the fight.
func test_campaign_banks_xp() -> void:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	var c := Campaign.new(p, 99)
	var fighters: Array = c.party.party_characters()
	check(fighters.size() == 3, "the preset party fields 3")
	c.finish_combat({"outcome": "Victory", "xp": 300, "gold": 0})
	check(Prog.lifetime_xp_total() == 300, "the whole haul banks once as lifetime XP")
	for ch in fighters:
		check(Prog.class_xp_of(ch.class_id()) == 100,
			"%s's share feeds %s's class XP" % [ch.id, ch.class_id()])
	c.finish_combat({"outcome": "Victory", "xp": 300, "gold": 0})
	check(Prog.lifetime_xp_total() == 600, "a second win adds, never resets")
	check(Prog.load_state().lifetime_xp == 600, "and it is on disk, not just in memory")
	check(Prog.class_xp_of("cleric") == 200, "class XP accumulates across fights")
	# A loss banks nothing.
	c.finish_combat({"outcome": "Defeat", "xp": 300, "gold": 0})
	check(Prog.lifetime_xp_total() == 600, "a defeat banks no XP")

# The creator's gate: locked options carry a price, open ones carry nothing.
func test_creator_gates() -> void:
	check(Creator.lock_note("species", "human") == "", "a day-one species is open")
	check(Creator.lock_note("class", "cleric") == "", "a day-one class is open")
	check(Creator.lock_note("subclass", "lifedomain") == "", "its free subclass is open")
	var note := Creator.lock_note("species", "gnome")
	check(note.contains(str(Prog.species_cost("gnome"))) and note.contains("lifetime XP"),
		"a locked species quotes its lifetime-XP price: %s" % note)
	check(Creator.lock_note("class", "rogue").contains(str(Prog.class_cost("rogue"))),
		"a locked class quotes its lifetime-XP price")
	check(Creator.lock_note("subclass", "wardomain").contains("class XP"),
		"a paid subclass quotes class XP")
	Prog.add_lifetime_xp(Prog.species_cost("gnome"))
	check(Creator.lock_note("species", "gnome") == "", "crossing the threshold opens it")
	check(Creator.lock_note("class", "rogue") != "", "the classes are still out of reach")
	Prog.add_lifetime_xp(Prog.class_cost("rogue"))
	check(Creator.lock_note("class", "rogue") == "", "the class opens at its threshold")
	check(Creator.lock_note("subclass", "thief") != "",
		"but its subclasses stay shut until the 2 free picks are made")
	Prog.unlock_class("rogue", ["thief", "soulknife"])
	check(Creator.lock_note("subclass", "thief") == "", "a free pick opens")
	check(Creator.lock_note("subclass", "assassin") != "", "the other 2 still cost class XP")
	Prog.add_class_xp("rogue", Prog.SUBCLASS_COST)
	check(Creator.lock_note("subclass", Prog.paid_subclasses("rogue")[0]) == "",
		"class XP opens the next one")

# SORCMERC_PLAYTEST=1 mirrors what a "playtest" export-preset feature tag does
# at runtime (a live custom_features flag can't be forced from a headless test
# run) -- everything opens, no locked-anything left, subclasses included.
func test_playtest_build_unlocks_everything() -> void:
	check(not Prog.is_class_unlocked("rogue"), "rogue is locked in a normal build (sanity check)")
	OS.set_environment("SORCMERC_PLAYTEST", "1")
	check(Prog.is_species_unlocked("dragonborn"), "every species opens")
	check(Prog.is_lineage_unlocked("elf", "drow"), "and every lineage with it")
	check(Prog.is_class_unlocked("rogue") and Prog.is_class_unlocked("sorcerer"),
		"every class opens, XP threshold or not")
	check(not Prog.awaits_picks("rogue"),
		"...and never dangles a forced pick-2 flow just to get there")
	check(Prog.is_subclass_unlocked("thief") and Prog.is_subclass_unlocked("assassin"),
		"every subclass opens too, free and paid alike")
	check(Prog.current().lifetime_xp == 0, "none of this touches the actual saved progress")
	OS.set_environment("SORCMERC_PLAYTEST", "")
	check(not Prog.is_class_unlocked("rogue"), "and it's gone the moment the flag is")

func test_viewer() -> void:
	var v = load("res://scenes/progression/progression.tscn").instantiate()
	root.add_child(v)
	await process_frame
	check(v.get_child_count() > 0, "viewer builds its UI standalone")
	v.queue_free()
