# #246 — a spell your species (or a feat) gives you is free once per Long Rest.
#
# 2024 PHB, Fiendish Legacy: "You can cast [it] once without a spell slot, and
# you regain the ability to cast it in that way when you finish a Long Rest.
# You can also cast [it] using any spell slots you have." Elven and Gnomish
# Lineage, Fey Touched and Shadow Touched say the same thing. The engine used to
# read these as ordinary always-prepared spells, so a tiefling warlock paid a
# pact slot for its Hellish Rebuke and a tiefling fighter — no slots at all —
# carried a Hellish Rebuke that could never fire.
#
# Held here: which spells are innate (leveled, from a species or feat bundle;
# never a cantrip, never a subclass's prepared list), that the free cast is a
# pool of one that the fight spends FIRST and slots after, that a refused cast
# spends neither, and that the pool rides write_back, a short rest (it stays
# spent), a long rest (it comes back) and the save file like every other pool.
#   godot --headless --path . -s tests/test_innate_spells.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Character = preload("res://core/character.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const PassSpells = preload("res://core/rules/pass_spells.gd")
const Party = preload("res://core/party.gd")
const RoadSpells = preload("res://core/road_spells.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_what_counts_as_innate()
	test_the_non_caster_rebukes_for_free_once()
	test_free_first_then_a_slot()
	test_a_button_spell_is_free_once_too()
	test_the_pool_survives_the_road()
	test_a_road_spell_is_free_too()
	print("test_innate_spells: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ------------------------------------------------------------

func _hero(id: String, cls: String, lvl: int, species: String, lineage := "", feats: Array = []):
	var ch = Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = species
	ch.background_id = "soldier"
	ch.base_abilities = {"str": 15, "dex": 14, "con": 14, "int": 8, "wis": 10, "cha": 12}
	if lineage != "":
		ch.decide("lineage-choice:species:%s:0" % species, {"type": "lineage-choice", "lineageId": lineage})
	for i in lvl:
		ch.add_level(cls, -1)
	for f in feats:
		ch.feats.append(String(f))
	ch.equipped = ["longsword"] as Array[String]
	return ch

func _board() -> Dictionary:
	return Encounter.board()

const POOL := "innate-hellish-rebuke"

# --- which spells --------------------------------------------------------

func test_what_counts_as_innate() -> void:
	var tf = _hero("tf", "fighter", 3, "tiefling", "infernal").sheet()
	var innate: Array = tf.spellcasting.get("innate", [])
	check("hellish-rebuke" in innate and "darkness" in innate, "infernal tiefling: Hellish Rebuke and Darkness are innate")
	check(not "fire-bolt" in innate, "...the cantrip is not: it needs no slot to begin with")
	check(tf.pool_max(POOL) == 1, "...one free cast of each")
	var pool: Dictionary = tf.pools.filter(func(p): return p["id"] == POOL)[0]
	check(String(pool["regen"]) == "long-rest", "...back on a Long Rest")
	check(tf.spellcasting["ability"] in ["int", "wis", "cha"] and int(tf.spellcasting["save_dc"]) > 0,
		"a fighter's species spells still have a casting ability and a DC (%s, DC %d)"
			% [tf.spellcasting["ability"], int(tf.spellcasting["save_dc"])])
	check(tf.spellcasting["ability"] == "cha", "...the best of INT/WIS/CHA — this build's is CHA")
	var drow = _hero("dr", "rogue", 1, "elf", "drow").sheet()
	check("faerie-fire" in drow.spellcasting["innate"] and "darkness" in drow.spellcasting["innate"]
		and not "dancing-lights" in drow.spellcasting["innate"], "drow: Faerie Fire and Darkness, not the cantrip")
	var fey = _hero("fey", "fighter", 4, "human", "", ["fey-touched"]).sheet()
	check("misty-step" in fey.spellcasting.get("innate", []), "Fey Touched: Misty Step is free once a Long Rest too")
	var human = _hero("hu", "wizard", 3, "human").sheet()
	check(human.spellcasting.get("innate", []).is_empty() and human.pools.all(func(p): return not String(p["id"]).begins_with(PassSpells.INNATE_POOL_PREFIX)),
		"a class's own spells are never innate")

# --- a fighter with no slots -------------------------------------------------

func test_the_non_caster_rebukes_for_free_once() -> void:
	var ch = _hero("brand", "fighter", 3, "tiefling", "infernal")
	var tf = Adapter.to_combatant(ch, "party", Vector2i(2, 1))
	var ogre = Encounter.spawn("ogre", 1.0, "foe", Vector2i(3, 1), 1)
	ogre.max_hp = 500; ogre.hp = 500
	var cb = Combat.new(RNG.new(4), [tf, ogre], _board())
	cb.tracked = false
	cb.begin_turn_for(tf)
	check(tf.slots.all(func(n): return n == 0), "the fighter has no spell slots")
	var hr: Dictionary = tf.verb("hellish-rebuke")
	check(String(hr.get("innate_pool", "")) == POOL, "Hellish Rebuke carries its free cast")
	check(tf.pool_left(POOL) == 1, "...one of it")
	check(not cb.reaction_verb(tf, "damaged_by_attack").is_empty(), "so it CAN answer a blow, slots or no slots")
	cb.fire_reactions("damaged_by_attack", {"attacker": ogre, "target": tf, "damage": 8})
	check(ogre.hp < 500, "the ogre is rebuked (%d HP left)" % ogre.hp)
	check(tf.pool_left(POOL) == 0 and tf.slots.all(func(n): return n == 0), "the free cast is spent, and no slot")
	check(cb.log.any(func(l): return l.contains("casts Hellish Rebuke")), "and the log says so")
	cb.begin_turn_for(tf)   # the reaction is back; the free cast is not
	var hp_mid: int = ogre.hp
	check(cb.reaction_verb(tf, "damaged_by_attack").is_empty(), "spent: nothing left to rebuke with until a Long Rest")
	cb.fire_reactions("damaged_by_attack", {"attacker": ogre, "target": tf, "damage": 8})
	check(ogre.hp == hp_mid and int(tf.econ["reaction"]) == 1, "the second blow goes unanswered, and costs nothing")

# --- a warlock: the free cast first, then a pact slot -------------------------

func test_free_first_then_a_slot() -> void:
	var ch = _hero("mal", "warlock", 3, "tiefling", "infernal")
	var tf = Adapter.to_combatant(ch, "party", Vector2i(2, 1))
	var ogre = Encounter.spawn("ogre", 1.0, "foe", Vector2i(3, 1), 1)
	ogre.max_hp = 500; ogre.hp = 500
	var cb = Combat.new(RNG.new(4), [tf, ogre], _board())
	cb.tracked = false
	cb.begin_turn_for(tf)
	var pact: Array = tf.slots.duplicate()
	check(int(pact[1]) == 2, "a level-3 warlock: two 2nd-level pact slots")
	cb.fire_reactions("damaged_by_attack", {"attacker": ogre, "target": tf, "damage": 8})
	check(tf.pool_left(POOL) == 0 and tf.slots == pact, "the first rebuke is the free one: no pact slot spent")
	cb.begin_turn_for(tf)
	var hp_mid: int = ogre.hp
	cb.fire_reactions("damaged_by_attack", {"attacker": ogre, "target": tf, "damage": 8})
	check(ogre.hp < hp_mid and int(tf.slots[1]) == 1, "the second is paid from a pact slot, as RAW allows")

# --- a button, not a reaction: Faerie Fire -----------------------------------

func test_a_button_spell_is_free_once_too() -> void:
	var ch = _hero("vex", "rogue", 3, "elf", "drow")
	var dr = Adapter.to_combatant(ch, "party", Vector2i(2, 1))
	var ogre = Encounter.spawn("ogre", 1.0, "foe", Vector2i(4, 1), 1)
	var cb = Combat.new(RNG.new(4), [dr, ogre], _board())
	cb.tracked = false
	cb.begin_turn_for(dr)
	var ff: Dictionary = dr.verb("faerie-fire")
	var pid := PassSpells.innate_pool("faerie-fire")
	check(cb.available(dr).any(func(v): return v["id"] == "faerie-fire"), "a rogue with no slots is offered Faerie Fire")
	var res: Dictionary = cb.perform(dr, ff, ogre)
	check(not res.has("error") and dr.pool_left(pid) == 0, "...casts it, spending the free use (%s)" % str(res))
	cb.begin_turn_for(dr)
	check(not cb.available(dr).any(func(v): return v["id"] == "faerie-fire"), "and then it is greyed out until a Long Rest")
	var action_before: int = int(dr.econ["action"])
	check(cb.cast(dr, ff, ogre).has("error") and int(dr.econ["action"]) == action_before,
		"a cast forced past the button is refused and spends nothing")

# --- the pool rides the road -----------------------------------------------

func test_the_pool_survives_the_road() -> void:
	var ch = _hero("brand", "fighter", 3, "tiefling", "infernal")
	var tf = Adapter.to_combatant(ch, "party", Vector2i(2, 1))
	tf.pools[POOL]["cur"] = 0
	Adapter.write_back(tf, ch)
	check(int(ch.pools.get(POOL, -1)) == 0, "write_back carries the spent free cast home")
	check(Adapter.to_combatant(ch, "party", Vector2i.ZERO).pool_left(POOL) == 0, "...and into the next fight")
	var round_trip = CharacterSave.from_dict(CharacterSave.to_dict(ch))
	check(int(round_trip.pools.get(POOL, -1)) == 0, "...and through the save file")
	Adapter.rest(ch, "short-rest")
	check(int(ch.pools.get(POOL, -1)) == 0, "a Short Rest does not bring it back")
	Adapter.rest(ch, "long-rest")
	check(int(ch.pools.get(POOL, -1)) == 1, "a Long Rest does")

# --- off the board: a wood elf's Longstrider ----------------------------------

func test_a_road_spell_is_free_too() -> void:
	var ch = _hero("fen", "fighter", 3, "elf", "wood-elf")
	var p := Party.new()
	p.add_member(ch)
	var known: Array = RoadSpells.known(p, ch).filter(func(k): return k["id"] == "longstrider")
	check(known.size() == 1 and known[0]["castable"], "a fighter wood elf can cast Longstrider on the road, slotless")
	var line := RoadSpells.cast(p, ch, "longstrider", 0.0)
	check(line != "" and RoadSpells.free_left(ch, "longstrider") == 0, "...spending the free use")
	check(not RoadSpells.known(p, ch).filter(func(k): return k["id"] == "longstrider")[0]["castable"],
		"...and not again until a Long Rest")
