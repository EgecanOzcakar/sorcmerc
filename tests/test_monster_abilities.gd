# T16: the monster template library actually fires in a fight.
#   godot --headless --path . -s tests/test_monster_abilities.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_ids_resolve()
	test_riders_inflict()
	test_condition_expires()
	test_pack_tactics()
	test_regeneration()
	test_action_save_effect()
	print("test_monster_abilities: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _victim(p := Vector2i(4, 1)):
	var c = Combatant.new()
	c.id = "victim"; c.cname = "Victim"; c.team = "party"; c.pos = p
	c.ac = 5; c.max_hp = 200; c.hp = 200; c.speed = 4
	c.saves = {"str": -5, "dex": -5, "con": -5, "int": -5, "wis": -5, "cha": -5}
	return c

func _fight(monster_id: String, extra: Array = []) -> Array:
	var m = Adapter.from_monster(Catalog.index("bestiary.json")[monster_id], "foe", Vector2i(4, 0))
	m.atk_bonus = 20                     # the rider is what's under test, not the d20
	var v = _victim()
	var all: Array = [m, v]
	all.append_array(extra)
	var cb = Combat.new(RNG.new(3), all, Encounter.board())
	for c in all:
		cb.begin_turn_for(c)
	return [cb, m, v]

# Every tagged feature id resolves to a real template.
func test_ids_resolve() -> void:
	var missing := {}
	var tagged := 0
	for e in Catalog.all("bestiary.json"):
		if not e["features"].is_empty():
			tagged += 1
		for fid in e["features"]:
			if Effects.feature(fid).is_empty():
				missing[fid] = true
	check(missing.is_empty(), "unknown feature ids: " + ", ".join(missing.keys()))
	check(tagged > 200, "%d/316 bestiary entries carry a feature" % tagged)
	check(Effects.validate().is_empty(), "Effects.validate() clean")

# One representative monster per condition template, spawned and swung for real.
func test_riders_inflict() -> void:
	for pair in [["ghoul", "paralyzed"], ["giant-spider", "poisoned"], ["wolf", "prone"],
			["giant-constrictor-snake", "restrained"], ["giant-scorpion", "poisoned"], ["giant-scorpion", "grappled"]]:
		var f := _fight(pair[0])
		var cb: Combat = f[0]
		var got := false
		for i in 8:                      # the save can succeed; the DC is not the point
			cb.begin_turn_for(f[1])
			cb.resolve_attack(f[1], f[2])
			if f[2].has(pair[1]):
				got = true
				break
			f[2].statuses.clear()
		check(got, "%s inflicts %s on a hit" % [pair[0], pair[1]])

func test_condition_expires() -> void:
	var f := _fight("ghoul")
	var cb: Combat = f[0]
	cb.apply_condition(f[2], "paralyzed", f[1], "round")
	check(f[2].has("paralyzed"), "a round-duration condition lands")
	cb.turn_idx = 0
	cb.round_num += 1
	cb.begin_turn_for(f[2])
	check(not f[2].has("paralyzed"), "and lapses at the bearer's next turn")

	cb.apply_condition(f[2], "poisoned", f[1])
	cb.round_num += 1
	cb.begin_turn_for(f[2])
	check(f[2].has("poisoned"), "a durationless condition stays until something clears it")

func test_pack_tactics() -> void:
	var mate = Adapter.from_monster(Catalog.index("bestiary.json")["wolf"], "foe", Vector2i(3, 1))
	var f := _fight("wolf", [mate])
	var cb: Combat = f[0]
	check(cb._attack_mode(f[1], f[2]) == Dice.ADV, "pack tactics: ally adjacent to target -> advantage")
	mate.pos = Vector2i(0, 0)
	check(cb._attack_mode(f[1], f[2]) == Dice.NORMAL, "no adjacent ally -> normal")
	check(not cb.available(f[1]).any(func(v): return v["id"] == "monster-pack-tactics"),
		"a passive is never offered as a button")

func test_regeneration() -> void:
	var f := _fight("troll")
	var cb: Combat = f[0]
	f[1].hp = 10
	cb.begin_turn_for(f[1])
	check(f[1].hp > 10, "regeneration heals at the start of its turn (%d)" % f[1].hp)
	f[1].hp = f[1].max_hp
	cb.begin_turn_for(f[1])
	check(f[1].hp == f[1].max_hp, "and never overheals")

func test_action_save_effect() -> void:
	var f := _fight("mummy")
	var cb: Combat = f[0]
	var glare: Dictionary = f[1].verb("monster-frightful-presence")
	check(not glare.is_empty() and glare["range"] >= 1, "an action save_effect gets a hex range")
	check(cb.available(f[1]).any(func(v): return v["id"] == "monster-frightful-presence"),
		"and is offered while its use remains")
	cb.perform(f[1], glare, f[2])
	check(f[2].has("frightened"), "frightful presence frightens a hopeless save")
	check(f[1].pool_left("monster-frightful-presence") == 0, "one use, then spent")
	check(not cb.available(f[1]).any(func(v): return v["id"] == "monster-frightful-presence"),
		"an empty pool takes the verb off the list")
