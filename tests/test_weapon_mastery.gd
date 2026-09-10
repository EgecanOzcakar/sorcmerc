# The 2024 weapon-mastery properties wired into combat.gd (T20).
#   flatpak run org.godotengine.Godot --headless --path . -s tests/test_weapon_mastery.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
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
	test_graze()
	test_cleave()
	test_push()
	test_sap()
	test_slow()
	test_topple()
	test_vex()
	test_unknown_mastery_does_nothing()
	print("test_weapon_mastery: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ---------------------------------------------------------

const MOD := 3

# An open 10x3 room, so a push has somewhere to go.
func _board() -> Dictionary:
	var h: Array = []
	for q in 10:
		for r in 3:
			h.append(Vector2i(q, r))
	return {"hexes": h, "cover": [], "rough": [], "objects": [], "reach_melee": 1}

func _guy(id: String, team: String, p: Vector2i, mastery := ""):
	var c = Combatant.new()
	c.id = id; c.cname = id; c.team = team; c.pos = p
	c.ac = 12; c.max_hp = 200; c.hp = 200; c.atk_bonus = 5; c.damage = "1d6+%d" % MOD
	c.speed = 6; c.save_dc = 13; c.saves = {"str": 2, "dex": 3, "con": 2, "wis": 1}
	c.athletics = 3; c.acro = 2
	c.attacks = [{"id": "mace", "dice_count": 1, "dice_sides": 6, "dmg_bonus": MOD,
		"damage_type": "bludgeoning", "mastery": mastery}]
	return c

func _fight(mastery := "", extra := []) -> Array:
	var a = _guy("hero", "party", Vector2i(2, 1), mastery)
	var b = _guy("ogre", "foe", Vector2i(3, 1))
	var all: Array = [a, b]
	all.append_array(extra)
	var cb = Combat.new(RNG.new(7), all, _board())
	for c in all:
		cb.begin_turn_for(c)
	return [cb, a, b]

# Swing until it lands (or misses, when `want_hit` is false). Returns the result.
func _swing(cb: Combat, a, b, want_hit := true) -> Dictionary:
	for _i in 40:
		cb.begin_turn_for(a)
		var r = cb.resolve_attack(a, b)
		if r.get("hit", false) == want_hit:
			return r
	return {}

# --- tests ------------------------------------------------------------

func test_graze() -> void:
	var d = _fight("graze"); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	b.ac = 99   # nothing lands
	var before: int = b.hp
	var r := _swing(cb, a, b, false)
	check(not r.is_empty() and r["damage"] == 0, "the attack missed")
	check(b.hp == before - MOD, "graze still deals the ability modifier on a miss")

func test_cleave() -> void:
	var second = _guy("goblin", "foe", Vector2i(3, 0))   # beside both the target and the attacker
	var d = _fight("cleave", [second]); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	var r := _swing(cb, a, b)
	check(not r.is_empty(), "the first attack landed")
	check(second.hp < second.max_hp, "cleave carries into a second creature beside the first")
	check(second.max_hp - second.hp <= 6, "the cleave swing drops the ability modifier (%d)"
		% [second.max_hp - second.hp])

	# nobody adjacent to the first target -> no second swing
	second.pos = Vector2i(9, 2)
	second.hp = second.max_hp
	_swing(cb, a, b)
	check(second.hp == second.max_hp, "no second target in reach, no cleave")

func test_push() -> void:
	var d = _fight("push"); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	var d0 := Hex.distance(a.pos, b.pos)
	_swing(cb, a, b)
	check(Hex.distance(a.pos, b.pos) == d0 + cb.hexes_from_ft(10), "push drives the target 10 ft back")

	b.pos = Vector2i(3, 1)
	b.size = "Huge"
	_swing(cb, a, b)
	check(b.pos == Vector2i(3, 1), "a Huge creature is not pushed")

func test_sap() -> void:
	var d = _fight("sap"); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	_swing(cb, a, b)
	check(b.has("sapped"), "a sap hit marks the target")
	check(cb._attack_mode(b, a) == Dice.DIS, "the target's next attack has disadvantage")
	cb.begin_turn_for(b)
	cb.resolve_attack(b, a)
	check(not b.has("sapped"), "sap is spent on that one roll")
	check(cb._attack_mode(b, a) == Dice.NORMAL, "and the next roll is normal again")

func test_slow() -> void:
	var d = _fight("slow"); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	cb.begin_turn_for(b)
	var full := cb.move_left(b)
	_swing(cb, a, b)
	var penalty := cb.hexes_from_ft(10)
	check(cb.move_left(b) == full - penalty, "slow costs the target 10 ft of speed")
	_swing(cb, a, b)
	check(cb.move_left(b) == full - penalty, "a second slow refreshes, it does not stack")

func test_topple() -> void:
	var d = _fight("topple"); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	check(cb._weapon_dc(a) == 8 + a.atk_bonus, "the save DC is 8 + the weapon's attack bonus")
	_swing(cb, a, b)
	check(b.has("prone"), "a failed CON save against a huge DC drops the target prone")

	b.statuses.erase("prone")
	b.saves = {"con": 100}
	_swing(cb, a, b)
	check(not b.has("prone"), "making the save keeps it standing")

func test_vex() -> void:
	var third = _guy("goblin", "foe", Vector2i(2, 2))
	var d = _fight("vex", [third]); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	_swing(cb, a, b)
	check(cb._attack_mode(a, b) == Dice.ADV, "vex grants advantage against that target")
	check(cb._attack_mode(a, third) == Dice.NORMAL, "but not against anyone else")
	a.attacks[0]["mastery"] = ""   # so the swing that spends it cannot re-apply it
	cb.begin_turn_for(a)
	cb.resolve_attack(a, b)
	check(cb._attack_mode(a, b) == Dice.NORMAL, "and it is spent on the next swing")

func test_unknown_mastery_does_nothing() -> void:
	# pass_gear.gd leaves mastery "" when the wielder never picked that weapon.
	var d = _fight(""); var cb: Combat = d[0]; var a = d[1]; var b = d[2]
	a.atk_bonus = 40
	var pos: Vector2i = b.pos
	_swing(cb, a, b)
	check(b.pos == pos and b.statuses.is_empty(), "an unknown mastery adds nothing to a hit")
	b.ac = 99
	var hp: int = b.hp
	_swing(cb, a, b, false)
	check(b.hp == hp, "and nothing to a miss")
