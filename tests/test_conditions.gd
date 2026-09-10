# The condition-effects layer: data/effects/conditions.json wired into combat.
#   flatpak run org.godotengine.Godot --headless --path . -s tests/test_conditions.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Encounter = preload("res://core/encounter.gd")
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
	test_attack_mode_sources()
	test_auto_fail_save()
	test_action_economy_blocked()
	test_speed_zero()
	test_petrified_resists()
	test_paralyzed_auto_crit()
	test_exhaustion()
	test_charmed_and_frightened()
	test_auto_stand_from_prone()
	print("test_conditions: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------

func _guy(id: String, team: String, p: Vector2i):
	var c = Combatant.new()
	c.id = id; c.cname = id; c.team = team; c.pos = p
	c.ac = 12; c.max_hp = 40; c.hp = 40; c.atk_bonus = 5; c.damage = "1d6+3"
	c.speed = 4; c.save_dc = 13; c.saves = {"str": 2, "dex": 3, "con": 2, "wis": 1}
	c.athletics = 3; c.acro = 2
	return c

func _duo() -> Array:
	var a = _guy("hero", "party", Vector2i(4, 0))
	var b = _guy("ogre", "foe", Vector2i(4, 1))
	var cb = Combat.new(RNG.new(7), [a, b], Encounter.board())
	cb.begin_turn_for(a)
	cb.begin_turn_for(b)
	return [cb, a, b]

# --- tests ------------------------------------------------------------

func test_attack_mode_sources() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	check(cb._attack_mode(a, b) == Dice.NORMAL, "no conditions -> normal")
	b.statuses["restrained"] = true
	check(cb._attack_mode(a, b) == Dice.ADV, "restrained target -> advantage")
	b.statuses.erase("restrained")
	a.statuses["poisoned"] = true
	check(cb._attack_mode(a, b) == Dice.DIS, "poisoned attacker -> disadvantage")
	b.statuses["blinded"] = true
	check(cb._attack_mode(a, b) == Dice.NORMAL, "adv and dis cancel")
	a.statuses.clear(); b.statuses.clear()
	b.statuses["invisible"] = true
	check(cb._attack_mode(a, b) == Dice.DIS, "invisible target -> disadvantage")
	check(cb._attack_mode(b, a) == Dice.ADV, "invisible attacker -> advantage")

func test_auto_fail_save() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]
	a.statuses["paralyzed"] = true
	var fails := 0
	for i in 20:
		if not cb._saving_throw(a, 1, "dex"):
			fails += 1
	check(fails == 20, "paralyzed auto-fails every DEX save, even DC 1")
	check(cb._saving_throw(a, 1, "wis"), "a WIS save is still rolled")

func test_action_economy_blocked() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	check(not cb.available(a).is_empty(), "a healthy actor has verbs")
	a.statuses["stunned"] = true
	check(cb.available(a).is_empty(), "stunned offers nothing")
	for cost in ["action", "bonus", "reaction"]:
		check(not cb.can_spend(a, cost), "stunned cannot spend " + cost)
	check(cb.resolve_attack(a, b).has("error"), "stunned cannot swing even via ai.gd")
	a.statuses.erase("stunned")
	check(not cb.available(a).is_empty(), "ending the condition restores normal play")
	check(cb.can_spend(a, "action"), "action is spendable again")

func test_speed_zero() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]
	var free := cb.move_field(a).size()
	check(free > 0 and cb.move_left(a) == a.speed, "baseline movement")
	a.statuses["grappled"] = true
	check(cb.move_left(a) == 0, "grappled zeroes movement")
	check(cb.move_field(a).keys().all(func(h): return h == a.pos), "and offers no destination")
	cb.move_to(a, Vector2i(6, 0))
	check(a.pos == Vector2i(4, 0), "a grappled creature does not move")
	a.statuses.erase("grappled")
	check(cb.move_field(a).size() == free, "movement returns when the grapple ends")

func test_petrified_resists() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]
	a.statuses["petrified"] = true
	cb._apply_damage(a, 20, "fire")
	check(a.hp == 30, "petrified halves typed damage")
	cb._apply_damage(a, 20, "")
	check(a.hp == 20, "petrified halves untyped damage too")

func test_paralyzed_auto_crit() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	b.statuses["paralyzed"] = true
	b.max_hp = 9999; b.hp = 9999
	var crits := 0
	var hits := 0
	for i in 30:
		cb.begin_turn_for(a)
		var r = cb.resolve_attack(a, b)
		if r.get("hit", false):
			hits += 1
			crits += 1 if r["crit"] else 0
	check(hits > 0 and crits == hits, "every melee hit within reach of a paralyzed target crits")
	b.pos = Vector2i(6, 0)   # out of melee reach
	b.statuses["paralyzed"] = true
	a.ranged = true; a.atk_range = 6
	cb.begin_turn_for(a)
	var far = cb.resolve_attack(a, b)
	check(not far.get("crit", true) or far["nat"] >= 20, "a ranged attack gets no auto-crit")

func test_exhaustion() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]
	check(cb._d20_penalty(a) == 0, "no exhaustion, no penalty")
	cb.gain_exhaustion(a)
	check(cb.exhaustion_level(a) == 1 and cb._d20_penalty(a) == 2, "level 1 = -2")
	cb.gain_exhaustion(a, 2)
	check(cb.exhaustion_level(a) == 3 and cb._d20_penalty(a) == 6, "level 3 = -6, cumulative")
	check(cb.move_left(a) == a.speed - cb.hexes_from_ft(15) and cb.move_left(a) < a.speed,
		"level 3 costs 15 ft of speed")
	check(not cb._saving_throw(a, 25, "wis"), "the penalty reaches saves")
	cb.gain_exhaustion(a, 3)
	check(a.is_dead(), "level 6 kills")

func test_charmed_and_frightened() -> void:
	var d = _duo(); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	var atk := cb._basic("attack")
	check(cb.legal_target(a, atk, b), "an enemy in reach is targetable")
	cb.apply_condition(a, "charmed", b)
	check(not cb.legal_target(a, atk, b), "charmed cannot target its source")
	check(cb.resolve_attack(a, b).has("error"), "and cannot attack it directly either")
	a.statuses.erase("charmed")

	a.pos = Vector2i(4, 0); b.pos = Vector2i(6, 0)
	cb.begin_turn_for(a)
	var d0 := Hex.distance(a.pos, b.pos)
	check(cb.move_field(a).keys().any(func(h): return Hex.distance(h, b.pos) < d0),
		"normally you may close on an enemy")
	cb.apply_condition(a, "frightened", b)
	check(cb.move_field(a).keys().all(func(h): return Hex.distance(h, b.pos) >= d0),
		"frightened is offered no hex closer to its fear source")
	check(cb._attack_mode(a, b) == Dice.DIS, "frightened attacks at disadvantage")

func test_auto_stand_from_prone() -> void:
	var a = _guy("hero", "party", Vector2i(4, 0))
	var b = _guy("ogre", "foe", Vector2i(4, 1))
	a.statuses["prone"] = true
	var cb = Combat.new(RNG.new(7), [a, b], Encounter.board())
	cb.begin_turn_for(a)
	check(not a.has("prone"), "standing at the top of your turn clears prone")
	var half: int = a.speed / 2
	check(a.econ["move_left"] == a.speed - half,
		"standing costs half speed (%d of %d)" % [half, a.speed])

	# a feature that discounts the cost
	var c = _guy("scout", "party", Vector2i(4, 0))
	c.statuses["prone"] = true
	c.features["test-nimble-stand"] = true
	var cb2 = Combat.new(RNG.new(7), [c, _guy("foe2", "foe", Vector2i(4, 1))], Encounter.board())
	cb2.begin_turn_for(c)
	check(c.econ["move_left"] == c.speed, "a 0-cost discount feature leaves move untouched")
