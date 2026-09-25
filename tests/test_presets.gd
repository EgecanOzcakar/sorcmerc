# #200 — the ready-made heroes, as the player gets them and as the sweeps do.
#   godot --headless --path . -s tests/test_presets.gd
#
# Two promises, one file (core/presets.gd's header):
#   * the ruler is bare — party(), party_at() and the trio's own builders carry
#     no personality trait, so no sweep's measured number moves (#176);
#   * the content is whole — every preset the creator lists builds through the
#     rules engine with nothing left to choose, carries its temperament and
#     origin, and every starting class has one a fresh profile can load.
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Traits = preload("res://core/traits.gd")
const Prog = preload("res://core/progression.gd")
const Leveling = preload("res://core/leveling.gd")
const Adapter = preload("res://core/adapter.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Creator = preload("res://scenes/creator/creator.gd")

const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	_ruler_is_bare()
	_hero_is_the_build_plus_traits()
	_every_preset_builds()
	_every_starting_class_has_one()
	_the_gate()
	print("test_presets: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The sweeps' door: nothing here may carry a trait, at any level.
func _ruler_is_bare() -> void:
	var parties: Array = [Presets.party()]
	for n in [1, 3, 8, 20]:
		parties.append(Presets.party_at(n))
	for pty in parties:
		check(pty.size() == 3, "the ruler is the trio")
		for ch in pty:
			check(ch.traits.is_empty(), "%s (level %d) carries no trait for the sweeps" % [ch.id, ch.level()])
			check(Traits.ids(ch).is_empty(), "%s: Traits sees none either" % ch.id)
	check(Presets.party().map(func(c): return c.id) == ["vera", "pike", "ilsa"],
		"party() is still Vera, Pike and Ilsa, in that order")
	for id in Presets.ROSTER:
		check(Presets.build(id).traits.is_empty(), "build(%s) is bare" % id)
	check(Presets.vera().traits.is_empty() and Presets.pike().traits.is_empty()
		and Presets.ilsa().traits.is_empty(), "vera()/pike()/ilsa() are bare")

# The creator's door: the same build, with a temperament and an origin.
func _hero_is_the_build_plus_traits() -> void:
	for id in Presets.ROSTER:
		var bare = Presets.build(id)
		var hero = Presets.hero(id)
		var pick: Array = Presets.PERSONALITY.get(id, [])
		check(pick.size() == 2, "%s has a temperament and an origin listed" % id)
		if pick.size() != 2:
			continue
		check(Traits.row(pick[0]).get("family", "") == "temperament", "%s: %s is a temperament" % [id, pick[0]])
		check(Traits.row(pick[1]).get("family", "") == "origin", "%s: %s is an origin" % [id, pick[1]])
		check(Traits.of(hero, "temperament") == pick[0], "%s is %s" % [id, pick[0]])
		check(Traits.of(hero, "origin") == pick[1], "%s is %s" % [id, pick[1]])
		check(Traits.ids(hero).size() == 2, "%s holds exactly two traits" % id)
		check(not Traits.needs_offer(hero), "%s is never offered the pick again" % id)
		var a := CharacterSave.to_dict(bare)
		var b := CharacterSave.to_dict(hero)
		a.erase("traits")
		b.erase("traits")
		check(JSON.stringify(a) == JSON.stringify(b), "%s: hero() changes the traits and nothing else" % id)
		# The creator's Confirm fills an empty family from the background; a
		# preset's own picks must survive it.
		Traits.fill_defaults(hero)
		check(Traits.of(hero, "temperament") == pick[0] and Traits.of(hero, "origin") == pick[1],
			"%s keeps its own picks through Confirm's fill_defaults" % id)
	check(Presets.hero("nobody") == null and Presets.build("nobody") == null, "an unknown id is null")

# Each one through the rules engine: whole at 3, whole at the level a run
# starts it at, legal gear, and a Combatant that fights.
func _every_preset_builds() -> void:
	for id in Presets.ROSTER:
		var ch = Presets.hero(id)
		var s = ch.sheet()
		check(s.level == 3, "%s is level 3" % id)
		check(s.pending.is_empty(), "%s has no unmade choice (%s)" % [id, s.pending.map(func(p): return p["key"])])
		check(Leveling.can_finalize(ch), "%s can be finalized" % id)
		check(String(s.subclasses.get(ch.class_id(), "")) != "", "%s has a subclass at 3" % id)
		for w in s.warnings:
			check(String(w).contains("SCHEMA gap #2"), "%s: only the export's known gap warns (%s)" % [id, w])
		var weapons: Array = Creator.proficient_weapons(s)
		var armor: Array = Creator.proficient_armor(s)
		for item in ch.equipped:
			if not Catalog.weapon(item).is_empty():
				check(item in weapons, "%s is proficient with the %s they carry" % [id, item])
			elif not Catalog.armor(item).is_empty():
				check(item in armor, "%s is proficient in the %s they wear" % [id, item])
			else:
				check(false, "%s carries %s, which is neither weapon nor armor" % [id, item])
		var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
		check(c.max_hp == s.max_hp and c.max_hp > 0, "%s fights with the sheet's HP" % id)
		check(not c.attacks.is_empty(), "%s has an attack" % id)
		if not s.spellcasting.is_empty():
			check(not c.spell_ids.is_empty(), "%s has spells to cast" % id)
		# A run starts a preset at the creator's PRESET_START_LEVEL: whole there
		# too, its subclass waiting for the level that asks.
		var young = Presets.hero(id, Creator.PRESET_START_LEVEL)
		check(young.sheet().pending.is_empty(), "%s at level %d has nothing to choose" % [id, Creator.PRESET_START_LEVEL])
		check(young.sheet().subclasses.is_empty(), "%s at level %d has no subclass yet" % [id, Creator.PRESET_START_LEVEL])
	# The four added for #200 spend the same budget as a hero made in the
	# creator: the standard array, before the background's +2/+1.
	for id in ["brakka", "sael", "marit", "dagna"]:
		var base: Array = Presets.build(id).base_abilities.values()
		base.sort()
		base.reverse()
		check(base == STANDARD_ARRAY, "%s is built on the standard array (%s)" % [id, base])

# Every class a fresh profile can play has a ready-made hero it can load.
func _every_starting_class_has_one() -> void:
	for cid in Prog.STARTING_CLASSES:
		var found := ""
		for id in Presets.ROSTER:
			var ch = Presets.build(id)
			if ch.class_id() != cid:
				continue
			found = id
			check(String(ch.sheet().subclasses.get(cid, "")) in Prog.STARTING_CLASSES[cid],
				"%s's subclass is one of the %s's starting two" % [id, cid])
			check(ch.species_id in Prog.STARTING_SPECIES, "%s is a starting species" % id)
		check(found != "", "the %s, open from day one, has a preset" % cid)

# The lock gate on a fresh profile: the starting-class presets load, the
# Fighter and the Rogue wear their locks (#200's first half).
func _the_gate() -> void:
	var was = Prog._current
	Prog._current = Prog.new()
	for id in Presets.ROSTER:
		var note: String = Creator.build_lock_note(Presets.hero(id))
		var open: bool = Presets.build(id).class_id() in Prog.STARTING_CLASSES
		check((note == "") == open, "%s on a fresh profile: %s" % [id, note if note != "" else "open"])
	check(Creator.build_lock_note(Presets.hero("vera")) == Creator.lock_note("class", "fighter"),
		"Vera wears the Fighter's lock")
	check(Creator.build_lock_note(Presets.hero("pike")) == Creator.lock_note("class", "rogue"),
		"Pike wears the Rogue's lock")
	Prog._current = was
	check(Creator.preset_blurb(Presets.hero("brakka")) == "Orc Barbarian (Path of the Berserker), Farmer. Wrathful, Downs-rider.",
		"the tooltip says who they are (%s)" % Creator.preset_blurb(Presets.hero("brakka")))
