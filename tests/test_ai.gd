# T21: the foe AI reaches for a special verb instead of always swinging.
#   godot --headless --path . -s tests/test_ai.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const AI = preload("res://core/ai.gd")
const Hex = preload("res://core/hex.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_special_over_plain_attack()
	test_special_after_closing()
	test_condition_verb_wins_the_tie()
	test_never_specials_a_downed_pc()
	test_falls_back_to_the_swing()
	print("test_ai: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------

# A punching bag that fails every save and can't be missed.
func _victim(p := Vector2i(4, 1)):
	var c = Combatant.new()
	c.id = "victim"; c.cname = "Victim"; c.team = "party"; c.pos = p
	c.ac = 5; c.max_hp = 200; c.hp = 200; c.speed = 4
	c.saves = {"str": -50, "dex": -50, "con": -50, "int": -50, "wis": -50, "cha": -50}
	return c

func _fight(monster_id: String, at: Vector2i, vpos := Vector2i(4, 1), extra: Array = []) -> Array:
	var m = Adapter.from_monster(Catalog.index("bestiary.json")[monster_id], "foe", at)
	var v = _victim(vpos)
	var all: Array = [m, v]
	all.append_array(extra)
	var cb = Combat.new(RNG.new(3), all, Encounter.board())
	for c in all:
		cb.begin_turn_for(c)
	return [cb, m, v]

# --- the new rule -----------------------------------------------------

# A giant spider 4 hexes off used to walk in and bite; now it shoots its web.
func test_special_over_plain_attack() -> void:
	var f := _fight("giant-spider", Vector2i(0, 1))
	var cb: Combat = f[0]
	AI.take_turn(cb, f[1])
	check(f[2].has("restrained"), "giant spider webs instead of closing to bite")
	check(f[2].hp == 200, "and the web deals no damage — it wasn't a plain attack")
	check(f[1].pool_left("monster-web-shot") == 1, "one of its two web uses is spent")

# Out of web range: it closes, then still webs rather than standing there.
func test_special_after_closing() -> void:
	var f := _fight("giant-spider", Vector2i(0, 1), Vector2i(8, 1))
	var cb: Combat = f[0]
	var d0: int = Hex.distance(f[1].pos, f[2].pos)
	AI.take_turn(cb, f[1])
	check(Hex.distance(f[1].pos, f[2].pos) < d0, "it moves toward the target first")
	check(f[2].has("restrained"), "and webs once the range closes")

# Two specials available: the one that inflicts a condition goes first.
func test_condition_verb_wins_the_tie() -> void:
	var m = Combatant.new()
	m.id = "thing"; m.cname = "Thing"; m.team = "foe"; m.pos = Vector2i(3, 1)
	m.ac = 12; m.max_hp = 30; m.hp = 30; m.atk_bonus = 5; m.damage = "1d6"
	m.speed = 4; m.save_dc = 13
	m.verbs = Effects.verbs_for(null, ["monster-breath-weapon", "monster-web-shot"])
	Adapter._finish_verbs(m, {})
	var v = _victim()
	var cb = Combat.new(RNG.new(3), [m, v], Encounter.board())
	cb.begin_turn_for(m)
	cb.begin_turn_for(v)
	AI.take_turn(cb, m)
	check(v.has("restrained"), "the condition verb (web) is picked over the damage breath")
	check(m.pool_left("monster-breath-weapon") == 1, "the breath weapon is still held")

# The mercy rule holds for specials too: legal_target won't aim at the unconscious.
func test_never_specials_a_downed_pc() -> void:
	var f := _fight("giant-spider", Vector2i(4, 0))
	var cb: Combat = f[0]
	f[2].hp = 0
	AI.take_turn(cb, f[1])
	check(not f[2].has("restrained"), "no web on a downed PC")
	check(f[1].pool_left("monster-web-shot") == 2, "the pool is untouched")

# A monster with nothing special still just attacks (the old path, intact).
func test_falls_back_to_the_swing() -> void:
	var f := _fight("giant-rat", Vector2i(4, 0))
	var cb: Combat = f[0]
	check(not cb.available(f[1]).any(func(v): return v["kind"] != "attack" and v.get("targeting", "self") == "enemy"),
		"giant rat has no offensive special")
	f[1].atk_bonus = 20
	AI.take_turn(cb, f[1])
	check(f[2].hp < 200, "it swings")
