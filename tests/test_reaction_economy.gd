# #247 — one reaction, and it comes back at the start of your OWN turn.
#
# RAW (2024 PHB, Reactions): "When you take a Reaction, you can't take another
# one until the start of your next turn." Not the top of the round, not the
# attacker's turn: yours. This file holds that for every kind of reaction the
# engine resolves — the opportunity attack move_to() rolls, and each branch of
# combat.gd's fire_reactions(): a damage halver (Uncanny Dodge), an AC bump from
# a feature (Parry) and from a spell (Shield), Disadvantage (Warding Flare),
# retaliation (Hellish Rebuke) and a counter (Counterspell). Whichever one is
# spent, every other one is gone with it until its owner's turn comes round.
#
# And a reaction with USES spends one (Warding Flare: WIS-mod per Long Rest).
# The dispatcher always refused an empty pool; until this test nothing emptied
# it, so a Light cleric flared once every round, forever.
#
# test_combat_rules.gd's test_reaction_once_per_round covers the halver alone;
# test_reactions.gd owns Counterspell's own rules. This one owns the economy.
#   godot --headless --path . -s tests/test_reaction_economy.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	for kind in KINDS:
		test_one_reaction_whichever_kind(kind)
	test_it_comes_back_on_its_own_turn_not_the_round()
	test_warding_flare_spends_its_uses()
	print("test_reaction_economy: %d passed, %d failed" % [_pass, _fail])
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
	c.ac = 12; c.max_hp = 1000; c.hp = 1000; c.atk_bonus = 5; c.damage = "10"
	c.speed = 6; c.save_dc = 13
	c.saves = {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0}
	return c

# Each reaction the dispatcher knows, as the verb adapter.gd would build it.
const KINDS := ["opportunity", "uncanny_dodge", "parry", "shield", "warding_flare", "hellish_rebuke", "counterspell"]
const VERBS := {
	"uncanny_dodge": {"id": "ud", "label": "Uncanny Dodge", "kind": "reaction", "cost": "reaction",
		"trigger": "hit_by_attack", "halve_damage": true},
	"parry": {"id": "parry", "label": "Parry", "kind": "reaction", "cost": "reaction",
		"trigger": "would_be_hit", "melee_only": true, "ac_bonus": 2},
	"shield": {"id": "shield", "spell": "shield", "label": "Shield", "kind": "spell", "cost": "reaction",
		"trigger": "would_be_hit", "slot_level": 1, "ac_bonus": 5, "shape": "self", "targeting": "self"},
	"warding_flare": {"id": "wf", "label": "Warding Flare", "kind": "reaction", "cost": "reaction",
		"trigger": "would_be_hit", "disadvantage": true, "pool": "wf"},
	"hellish_rebuke": {"id": "hr", "spell": "hellish-rebuke", "label": "Hellish Rebuke", "kind": "spell",
		"cost": "reaction", "trigger": "damaged_by_attack", "slot_level": 1, "range": 10, "shape": "single",
		"targeting": "enemy", "save": "dex", "save_dc": 13, "half_on_save": true,
		"dice_count": 2, "dice_sides": 10, "damage_type": "fire"},
	"counterspell": {"id": "cs", "spell": "counterspell", "label": "Counterspell", "kind": "spell",
		"cost": "reaction", "trigger": "spell_cast", "slot_level": 3, "counter": true, "min_level": 1,
		"range": 10, "shape": "single", "targeting": "enemy", "save": "con"},
}

# `a` the foe doing things, `b` the one holding the reaction, adjacent.
# `x` a third body, so a round has somebody else's turn in the middle of it.
func _fight(kind: String) -> Array:
	var a = _guy("attacker", "foe", Vector2i(3, 1))
	var b = _guy("reactor", "party", Vector2i(2, 1))
	var x = _guy("bystander", "foe", Vector2i(9, 4))
	if VERBS.has(kind):
		b.verbs = [VERBS[kind].duplicate(true)]
	b.slots = [4, 0, 4, 0, 0, 0, 0, 0, 0] as Array[int]
	b.pools = {"wf": {"cur": 5, "max": 5, "regen": "long-rest"}}
	a.saves["con"] = -100   # every Counterspell lands
	a.ac = -50              # and every opportunity attack: a hit is a fact, not a roll
	var cb = Combat.new(RNG.new(5), [a, b, x], _board())
	cb.tracked = false
	for c in [a, b, x]:
		cb.begin_turn_for(c)
	return [cb, a, b, x]

# Fire `kind` once at `b` and say whether it answered.
func _trigger(cb, a, b, kind: String) -> bool:
	var slots_before: Array = b.slots.duplicate()
	var pool_before: int = b.pool_left("wf")
	var hp_before: int = a.hp
	match kind:
		"opportunity":
			a.pos = Vector2i(3, 1)
			a.econ["move_left"] = a.speed
			cb.move_to(a, Vector2i(6, 1))   # out of b's reach: the one walk that provokes
			return a.hp < hp_before
		"uncanny_dodge":
			var out: Dictionary = cb.fire_reactions("hit_by_attack", {"attacker": a, "target": b, "damage": 10})
			return int(out["damage"]) == 5
		"parry", "shield":
			var out: Dictionary = cb.fire_reactions("would_be_hit",
				{"attacker": a, "target": b, "total": 13, "ac": 12, "ranged": false})
			return int(out["ac_bonus"]) > 0
		"warding_flare":
			var out: Dictionary = cb.fire_reactions("would_be_hit",
				{"attacker": a, "target": b, "total": 13, "ac": 12, "ranged": false})
			return out.has("second_d20") and b.pool_left("wf") == pool_before - 1
		"hellish_rebuke":
			cb.fire_reactions("damaged_by_attack", {"attacker": a, "target": b, "damage": 10})
			return b.slots[0] == int(slots_before[0]) - 1
		"counterspell":
			var out: Dictionary = cb.fire_reactions("spell_cast",
				{"caster": a, "verb": {"label": "Fireball", "kind": "spell"}, "level": 3})
			return out["countered"] and b.slots[2] == int(slots_before[2]) - 1
	return false

# --- one reaction, whichever it is ----------------------------------------

func test_one_reaction_whichever_kind(kind: String) -> void:
	var f := _fight(kind); var cb = f[0]; var a = f[1]; var b = f[2]
	check(_trigger(cb, a, b, kind), "%s: answers the first time" % kind)
	check(int(b.econ["reaction"]) == 0, "%s: and spends the reaction" % kind)
	# The same trigger again, before b's turn: nothing.
	check(not _trigger(cb, a, b, kind), "%s: a second one before its turn gets nothing" % kind)
	# Nor any other kind: the reaction is one, not one per trigger.
	for other in KINDS:
		if other == kind:
			continue
		if VERBS.has(other):
			b.verbs = [VERBS[other].duplicate(true)]
		check(not _trigger(cb, a, b, other), "%s spent: %s is gone too" % [kind, other])
		check(cb.reactors_for(String(VERBS.get(other, {}).get("trigger", "hit_by_attack")),
			{"attacker": a, "target": b, "caster": a, "level": 3, "damage": 10}).is_empty(),
			"%s spent: nobody is listed to answer with %s" % [kind, other])
	check(int(b.econ["reaction"]) == 0, "%s: the economy never goes negative" % kind)
	# Its own turn gives it back — and then it answers again.
	cb.begin_turn_for(b)
	if VERBS.has(kind):
		b.verbs = [VERBS[kind].duplicate(true)]
	check(int(b.econ["reaction"]) == 1, "%s: back at the start of its own turn" % kind)
	check(_trigger(cb, a, b, kind), "%s: and it answers again" % kind)

# --- refreshed on its OWN turn, not at the top of the round ------------------

func test_it_comes_back_on_its_own_turn_not_the_round() -> void:
	var f := _fight("uncanny_dodge"); var cb = f[0]; var a = f[1]; var b = f[2]; var x = f[3]
	# b goes first in the round, then the attacker, then the bystander.
	cb.order = [b, a, x]
	cb.turn_idx = 1
	cb.round_num = 1
	cb.begin_turn()   # the attacker's turn
	check(_trigger(cb, a, b, "uncanny_dodge") and int(b.econ["reaction"]) == 0,
		"spent on the attacker's turn")
	cb.end_turn()
	cb.begin_turn()   # the bystander's turn
	check(cb.current() == x and int(b.econ["reaction"]) == 0, "somebody else's turn gives nothing back")
	cb.end_turn()     # round 2 begins, with b first
	check(cb.round_num == 2 and cb.current() == b and int(b.econ["reaction"]) == 0,
		"a new round is not a new reaction: still spent until b's own turn starts")
	check(cb.reactors_for("hit_by_attack", {"attacker": a, "target": b}).is_empty(),
		"...so in the gap between rounds nothing can be answered")
	cb.begin_turn()
	check(int(b.econ["reaction"]) == 1, "b's own turn starts: the reaction is back")

# --- a reaction with uses spends one ----------------------------------------

func test_warding_flare_spends_its_uses() -> void:
	var f := _fight("warding_flare"); var cb = f[0]; var a = f[1]; var b = f[2]
	b.pools["wf"] = {"cur": 2, "max": 2, "regen": "long-rest"}
	check(_trigger(cb, a, b, "warding_flare") and b.pool_left("wf") == 1, "the first flare costs a use")
	cb.begin_turn_for(b)
	check(_trigger(cb, a, b, "warding_flare") and b.pool_left("wf") == 0, "the second costs the last")
	cb.begin_turn_for(b)
	check(not _trigger(cb, a, b, "warding_flare"), "out of uses: no third flare")
	check(int(b.econ["reaction"]) == 1, "...and the reaction it did not use is still there")
