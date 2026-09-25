# #245 — the combat log says what a blow was struck with.
#
# "Vera Kord hits Snik the Goblin — d20[14]+5 = 19 vs AC 15, …" told you who
# and how hard, never with what. Spells always named themselves ("casts Fire
# Bolt on …"); a swing now does too: the hero's main-hand weapon off the sheet,
# a monster's natural attack off its statblock (bestiary.json's attack_name),
# the off-hand blade, and the unarmed fist an archer throws on an opportunity
# attack. A combatant nothing names — a test's bare dummy — reads as it always
# did, so the line never says "with a ".
#
# The colouring in scenes/main.gd keys off " hits ", " CRITS " and "misses";
# those words stay exactly where they were, which this file also holds.
#   godot --headless --path . -s tests/test_attack_log.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Adapter = preload("res://core/adapter.gd")
const Presets = preload("res://core/presets.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_the_article()
	test_a_hero_names_the_weapon()
	test_a_monster_names_its_attack()
	test_the_off_hand_and_the_archers_fist()
	test_an_unnamed_swing_reads_as_before()
	print("test_attack_log: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ------------------------------------------------------------

# An RNG whose first d20s are exactly `wants` (test_combat_rules.gd's helper).
func _rolls(wants: Array):
	var s := 1
	while true:
		var r = RNG.new(s)
		var ok := true
		for w in wants:
			if r.roll_die(20) != int(w):
				ok = false
				break
		if ok:
			return RNG.new(s)
		s += 1
	return null

func _board() -> Dictionary:
	var hx: Array = []
	for q in 12:
		for r in 5:
			hx.append(Vector2i(q, r))
	return {"hexes": hx, "cover": [], "rough": [], "objects": [], "reach_melee": 1}

func _preset(id: String):
	for ch in Presets.party():
		if ch.id == id:
			return ch
	return null

func _fight(a, b) -> Combat:
	var cb = Combat.new(RNG.new(3), [a, b], _board())
	cb.tracked = false
	cb.begin_turn_for(a)
	cb.begin_turn_for(b)
	return cb

# The attack line a swing wrote: the last line that has the attacker's name
# and one of the three verbs in it.
func _swing(cb, a, b, nat: int, opts := {}) -> String:
	cb.rng = _rolls([nat])
	a.econ["action"] = 1
	a.econ["attacks_left"] = 0
	cb.resolve_attack(a, b, opts)
	for i in range(cb.log.size() - 1, -1, -1):
		var l: String = cb.log[i]
		if l.contains(a.cname) and (l.contains(" hits ") or l.contains(" attacks ") or l.contains(" misses ") or l.contains(" CRITS ")):
			return l
	return ""

# --- the words ----------------------------------------------------------

func test_the_article() -> void:
	check(Combat._with("Longsword") == " with a Longsword", "a Longsword")
	check(Combat._with("Unarmed Strike") == " with an Unarmed Strike", "an Unarmed Strike")
	check(Combat._with("Claws") == " with Claws" and Combat._with("Hooves") == " with Hooves",
		"a plural natural weapon takes no article")
	check(Combat._with("Glass") == " with a Glass", "...but a double s is not a plural")
	check(Combat._with("") == "", "nothing named: nothing said")

# --- heroes -------------------------------------------------------------

func test_a_hero_names_the_weapon() -> void:
	var vera = Adapter.to_combatant(_preset("vera"), "party", Vector2i(2, 1))
	var gob = Encounter.spawn("goblin", 1.0, "foe", Vector2i(3, 1), 1)
	gob.max_hp = 500; gob.hp = 500
	var cb := _fight(vera, gob)
	var weapon: String = String(vera.attacks[0]["name"])
	gob.ac = 1
	var hit := _swing(cb, vera, gob, 10)
	check(hit.begins_with("%s hits %s with a %s — d20[" % [vera.cname, gob.cname, weapon]),
		"a hit names the hero's weapon: %s" % hit)
	gob.ac = 40
	var miss := _swing(cb, vera, gob, 10)
	check(miss.begins_with("%s attacks %s with a %s — " % [vera.cname, gob.cname, weapon]) and miss.ends_with("misses."),
		"so does a miss: %s" % miss)
	var fumble := _swing(cb, vera, gob, 1)
	check(fumble.begins_with("%s misses %s badly with a %s — nat 1" % [vera.cname, gob.cname, weapon]),
		"and a fumble: %s" % fumble)
	gob.ac = 1
	var crit := _swing(cb, vera, gob, 20)
	check(crit.contains(" CRITS %s with a %s — " % [gob.cname, weapon]), "and a crit: %s" % crit)

# --- monsters -----------------------------------------------------------

func test_a_monster_names_its_attack() -> void:
	var vera = Adapter.to_combatant(_preset("vera"), "party", Vector2i(2, 1))
	vera.max_hp = 999; vera.hp = 999; vera.ac = 1
	var gob = Encounter.spawn("goblin", 1.0, "foe", Vector2i(3, 1), 1)
	var cb := _fight(gob, vera)
	var line := _swing(cb, gob, vera, 10)
	check(line.contains(" hits %s with a %s — " % [vera.cname, gob.attack_name]) and gob.attack_name != "",
		"a goblin names its %s: %s" % [gob.attack_name, line])
	var wolf = Encounter.spawn("wolf", 1.0, "foe", Vector2i(1, 1), 1)
	var cb2 := _fight(wolf, vera)
	line = _swing(cb2, wolf, vera, 10)
	check(line.contains(" with a Bite — "), "a wolf bites: %s" % line)

# --- the off hand, and an archer caught in melee ------------------------------

func test_the_off_hand_and_the_archers_fist() -> void:
	var vera = Adapter.to_combatant(_preset("vera"), "party", Vector2i(2, 1))
	var gob = Encounter.spawn("goblin", 1.0, "foe", Vector2i(3, 1), 1)
	gob.max_hp = 500; gob.hp = 500; gob.ac = 1
	var cb := _fight(vera, gob)
	var off := _swing(cb, vera, gob, 10, {"free": true, "no_mastery": true, "damage": "1d6", "weapon": "Shortsword"})
	check(off.contains(" with a Shortsword — "), "the off-hand swing names the off-hand blade: %s" % off)
	# Pike's bow is no use at arm's length: the opportunity attack is a fist.
	var pike = Adapter.to_combatant(_preset("pike"), "party", Vector2i(2, 1))
	check(pike.ranged, "Pike carries a bow")
	var runner = Encounter.spawn("goblin", 1.0, "foe", Vector2i(3, 1), 1)
	runner.max_hp = 500; runner.hp = 500; runner.ac = -50
	var cb2 := _fight(runner, pike)
	cb2.move_to(runner, Vector2i(6, 1))
	var oa: Array = Array(cb2.log).filter(func(l): return String(l).begins_with("OA %s" % pike.cname))
	check(oa.size() == 1 and String(oa[0]).contains(" with an Unarmed Strike"),
		"an archer's opportunity attack is an Unarmed Strike: %s" % str(oa))

# --- nobody named -------------------------------------------------------------

func test_an_unnamed_swing_reads_as_before() -> void:
	var a = Combatant.new()
	a.id = "hero"; a.cname = "hero"; a.team = "party"; a.pos = Vector2i(2, 1)
	a.ac = 12; a.max_hp = 100; a.hp = 100; a.atk_bonus = 5; a.damage = "1d6+3"; a.speed = 6
	var b = a.clone()
	b.id = "ogre"; b.cname = "ogre"; b.team = "foe"; b.pos = Vector2i(3, 1); b.ac = 1
	var cb := _fight(a, b)
	var line := _swing(cb, a, b, 10)
	check(line.begins_with("hero hits ogre — d20[") and not line.contains(" with "),
		"no weapon on record: the line is the old one, word for word: %s" % line)
