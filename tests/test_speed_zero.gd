# #249 — which conditions stop a creature moving, and which only stop it acting.
#
# The 2024 rules split the two cleanly, and the engine has to as well:
#   Incapacitated   no actions, Bonus Actions or Reactions — and NOTHING about
#                   Speed. A creature under Hideous Laughter or Confusion walks
#                   (a laughing one crawls: the spell holds it Prone too).
#   Speed 0         Grappled, Restrained, Paralyzed, Petrified, Unconscious (0
#                   HP is the engine's "down"), and Stunned as this repo's SRD
#                   export words it. The ones that are ALSO incapacitating carry
#                   both halves — Petrified was missing its Bonus Action and
#                   Reaction until this test existed.
# And a Speed of 0 has no half to pay to stand up with (2024 Prone), so a
# creature held down stays down until whatever is holding it lets go.
#   godot --headless --path . -s tests/test_speed_zero.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Effects = preload("res://core/rules/effects.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_the_data()
	test_speed_zero_blocks_the_walk()
	test_incapacitated_alone_still_walks()
	test_incapacitating_conditions_take_the_whole_economy()
	test_no_standing_up_at_speed_zero()
	test_a_grip_that_lets_go_frees_the_stand()
	print("test_speed_zero: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures ------------------------------------------------------------

func _board() -> Dictionary:
	var hx: Array = []
	for q in 12:
		for r in 5:
			hx.append(Vector2i(q, r))
	return {"hexes": hx, "cover": [], "rough": [], "objects": [], "reach_melee": 1}

func _guy(id: String, team: String, p: Vector2i):
	var c = Combatant.new()
	c.id = id; c.cname = id; c.team = team; c.pos = p
	c.ac = 12; c.max_hp = 100; c.hp = 100; c.atk_bonus = 5; c.damage = "1d6+3"
	c.speed = 6; c.save_dc = 13
	c.saves = {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0}
	return c

# A hero far enough from the ogre that walking provokes nothing.
func _fight() -> Array:
	var a = _guy("hero", "party", Vector2i(1, 1))
	var b = _guy("ogre", "foe", Vector2i(9, 3))
	var cb = Combat.new(RNG.new(7), [a, b], _board())
	cb.tracked = false
	return [cb, a, b]

# --- the data -----------------------------------------------------------

const SPEED_ZERO := ["grappled", "restrained", "paralyzed", "petrified", "stunned", "unconscious"]
const INCAPACITATING := ["incapacitated", "paralyzed", "petrified", "stunned", "unconscious"]

func test_the_data() -> void:
	check(not Effects.condition("incapacitated").has("speed"),
		"Incapacitated says nothing about Speed (2024 RAW)")
	for id in SPEED_ZERO:
		check(int(Effects.condition(id).get("speed", -1)) == 0, "%s sets Speed to 0" % id)
	for id in INCAPACITATING:
		var e := Effects.condition(id)
		check(e.get("no_action", false) and e.get("no_bonus", false) and e.get("no_reaction", false),
			"%s is Incapacitated: no action, Bonus Action or Reaction" % id)

# --- moving -------------------------------------------------------------

func test_speed_zero_blocks_the_walk() -> void:
	for id in SPEED_ZERO + ["down"]:
		var f := _fight(); var cb = f[0]; var a = f[1]
		cb.begin_turn_for(a)
		a.statuses[id] = true
		if id == "down":
			a.hp = 0
		var from: Vector2i = a.pos
		check(cb.speed_zero(a) and cb.move_left(a) == 0, "%s: no movement left" % id)
		check(not cb.move_field(a).has(Vector2i(3, 1)), "%s: nowhere to walk to" % id)
		cb.move_to(a, Vector2i(3, 1))
		check(a.pos == from, "%s: move_to refuses and the token stays put" % id)
		# Dash adds Speed, and a Speed of 0 doubled is still 0.
		a.econ["move_left"] = int(a.econ["move_left"]) + a.speed
		check(cb.move_left(a) == 0, "%s: a Dash on top buys nothing" % id)

func test_incapacitated_alone_still_walks() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]
	cb.begin_turn_for(a)
	a.statuses["incapacitated"] = true
	check(not cb.speed_zero(a) and cb.move_left(a) == a.speed,
		"Incapacitated alone: the full Speed is still there")
	cb.move_to(a, Vector2i(3, 1))
	check(a.pos == Vector2i(3, 1), "...and the creature walks")
	check(cb.available(a).is_empty() or not cb.available(a).any(func(v): return v.get("cost", "action") in ["action", "bonus"]),
		"...while nothing that costs an action or a Bonus Action is on offer")
	check(not cb.can_spend(a, "reaction"), "...and its reaction is denied")

func test_incapacitating_conditions_take_the_whole_economy() -> void:
	for id in INCAPACITATING:
		var f := _fight(); var cb = f[0]; var a = f[1]
		cb.begin_turn_for(a)
		a.statuses[id] = true
		for cost in ["action", "bonus", "reaction"]:
			check(not cb.can_spend(a, cost), "%s: no %s" % [id, cost])

# --- prone at Speed 0 ----------------------------------------------------

func test_no_standing_up_at_speed_zero() -> void:
	for id in ["paralyzed", "restrained", "stunned", "petrified"]:
		var f := _fight(); var cb = f[0]; var a = f[1]
		a.statuses["prone"] = true
		a.statuses[id] = true
		cb.begin_turn_for(a)
		check(a.has("prone"), "%s and prone: no Speed to stand up with, so it stays down" % id)
	# The control: prone and merely Incapacitated still gets up, for half its Speed.
	var f := _fight(); var cb = f[0]; var a = f[1]
	a.statuses["prone"] = true
	a.statuses["incapacitated"] = true
	cb.begin_turn_for(a)
	check(not a.has("prone") and int(a.econ["move_left"]) == a.speed - a.speed / 2,
		"prone and Incapacitated: stands, paying half its Speed")

func test_a_grip_that_lets_go_frees_the_stand() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.pos = Vector2i(2, 1)
	a.statuses["prone"] = true
	a.statuses["grappled"] = {"source": b}
	cb.begin_turn_for(a)
	check(a.has("prone") and a.has("grappled"), "grappled and prone: held down, cannot stand")
	# The grappler drops: the grip is gone before the stand is tried, not after.
	b.statuses["down"] = true; b.hp = 0
	cb.begin_turn_for(a)
	check(not a.has("grappled") and not a.has("prone"),
		"the grappler goes down: the grip lets go at the top of the turn and the creature stands")
