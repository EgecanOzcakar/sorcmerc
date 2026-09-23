# The 5e combat rules, one claim per rule, against the engine that implements
# them — the 2024 PHB "Combat" chapter and Rules Glossary, read line by line and
# asserted where this engine says it does the thing.
#
# What this file is NOT: a second copy of the suites that already exist. Each of
# those owns a slice and this one does not repeat it:
#   test_combat.gd            the MVP rules (OAs, cover, hide, help, rage, surge, slots)
#   test_conditions.gd        the adv/dis matrix per condition, auto-fail saves, exhaustion
#   test_reactions.gd         Counterspell, the reaction dispatcher, the prompt
#   test_weapon_mastery.gd    the 2024 mastery properties, two-weapon fighting
#   test_spell_buffs.gd       Bless/Haste/Stoneskin/Invisibility, summon spells
#   test_areas_concentration.gd  area shapes, concentration lifetime, repeat saves
#   test_monster_abilities.gd / test_monster_defenses.gd   the bestiary templates
#   test_summons.gd           Primal Companion, Invoke Duplicity
#   test_class_abilities.gd   every class/subclass built and its buttons pressed
#   test_encounter.gd         surprise, ambush, placement, outcome
# What is left is the rules between those — the arithmetic of a hit, what
# resistance does to an odd number, how a death save goes, what a downed body
# costs to finish, the order a turn's statuses lapse in — each pinned to a
# controlled d20 rather than a seed sweep, so a claim is a claim and not a
# probability.
#
# Two kinds of line come out of it. `check` is an assertion and fails the run.
# `note` is a QUESTION: a place where the engine and the printed rules (or BG3 /
# Solasta, the two 5e games this project cites) disagree and nothing in the
# repo says which was meant. Those are printed at the end, never counted as
# failures, and are the list to take to whoever owns the design.
#
#   godot --headless --path . -s tests/test_combat_rules.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Adapter = preload("res://core/adapter.gd")
const Presets = preload("res://core/presets.gd")
const Effects = preload("res://core/rules/effects.gd")
const Catalog = preload("res://core/rules/catalog.gd")

var _pass := 0
var _fail := 0
var _notes: Array = []

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# A deviation from the printed rules that the repo does not document as a
# decision. Reported, not failed — see the header.
func note(text: String) -> void:
	_notes.append(text)

func _init() -> void:
	test_dice_and_notation()
	test_hit_chance_math()
	test_initiative_order()
	test_turn_cycle()
	test_attack_roll_edges()
	test_attack_modifiers_on_the_roll()
	test_damage_defenses()
	test_concentration_checks()
	test_zero_hp_and_death()
	test_death_saves()
	test_healing()
	test_movement_rules()
	test_opportunity_attacks()
	test_forced_movement()
	test_dodge_dash_disengage_help()
	test_hide_dc()
	test_shove()
	test_grapple()
	test_smash_and_hazards()
	test_action_economy_rules()
	test_reaction_once_per_round()
	test_condition_gaps()
	test_spell_rules()
	test_new_spells()
	test_riders_and_extras()
	test_status_lifetimes()
	test_rage_clock()
	test_surprise_initiative()
	report()
	print("test_combat_rules: %d passed, %d failed, %d questions" % [_pass, _fail, _notes.size()])
	quit(1 if _fail > 0 else 0)

# --- fixtures ------------------------------------------------------------

# An open room with nothing in it: no cover, no hazards, no rough ground.
func _board(w := 12, h := 5) -> Dictionary:
	var hx: Array = []
	for q in w:
		for r in h:
			hx.append(Vector2i(q, r))
	return {"hexes": hx, "cover": [], "rough": [], "objects": [], "reach_melee": 1}

# One row of hexes: the only way past a creature is through it.
func _corridor(n := 7) -> Dictionary:
	var hx: Array = []
	for q in n:
		hx.append(Vector2i(q, 0))
	return {"hexes": hx, "cover": [], "rough": [], "objects": [], "reach_melee": 1}

func _guy(id: String, team: String, p: Vector2i):
	var c = Combatant.new()
	c.id = id; c.cname = id; c.team = team; c.pos = p
	c.ac = 12; c.max_hp = 100; c.hp = 100; c.atk_bonus = 5; c.damage = "1d6+3"
	c.speed = 6; c.save_dc = 13
	c.saves = {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0}
	c.athletics = 3; c.acro = 2; c.passive_perception = 10
	return c

# hero at (2,1), ogre at (3,1), adjacent, both with a fresh turn. `tracked`
# is off so nothing here touches the achievements profile on disk.
func _fight(board: Dictionary = {}, extra: Array = []) -> Array:
	var a = _guy("hero", "party", Vector2i(2, 1))
	var b = _guy("ogre", "foe", Vector2i(3, 1))
	var all: Array = [a, b]
	all.append_array(extra)
	var cb = Combat.new(RNG.new(7), all, board if not board.is_empty() else _board())
	cb.tracked = false
	for c in all:
		cb.begin_turn_for(c)
	return [cb, a, b]

# An RNG whose first d20s are exactly `wants`, so a roll is a fact and not a
# distribution. Installed as cb.rng right before the call that rolls.
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

func _extra(r: Dictionary, label: String) -> int:
	for e in r.get("extras", []):
		if String(e["label"]) == label:
			return int(e["amount"])
	return -1

# --- 1. dice -------------------------------------------------------------

func test_dice_and_notation() -> void:
	var r = Dice.d20(_rolls([4, 17]), Dice.ADV)
	check(r.nat == 17 and r.dice == [4, 17], "advantage keeps the higher of two dice, and keeps both")
	r = Dice.d20(_rolls([4, 17]), Dice.DIS)
	check(r.nat == 4, "disadvantage keeps the lower")
	r = Dice.d20(_rolls([4, 17]), Dice.NORMAL)
	check(r.nat == 4 and r.dice.size() == 1, "a normal roll is one die")
	check(Dice.combine(true, true) == Dice.NORMAL and Dice.combine(false, false) == Dice.NORMAL,
		"advantage and disadvantage cancel to a flat roll, however many of each (RAW)")
	check(Dice.combine(true, false) == Dice.ADV and Dice.combine(false, true) == Dice.DIS, "...and alone they apply")

	check(Dice.parse("1") == {"count": 0, "sides": 0, "mod": 1}, "a bare number is a flat modifier")
	check(Dice.parse("-2") == {"count": 0, "sides": 0, "mod": -2}, "...a negative one too")
	check(Dice.parse("3d8+2") == {"count": 3, "sides": 8, "mod": 2}, "NdS+M")
	check(Dice.parse("nonsense") == {"count": 0, "sides": 0, "mod": 0}, "garbage rolls zero rather than crashing a fight")
	var floor_ok := true
	for s in range(1, 30):
		if Dice.roll(RNG.new(s), "1d4-5") < 0:
			floor_ok = false
	check(floor_ok, "a roll never goes negative (RAW: damage has a floor of 0)")
	var d := Dice.roll_detailed(RNG.new(3), "2d6+3", true)
	check(d["rolls"].size() == 4 and d["mod"] == 3, "a crit rolls the dice twice and the modifier once (RAW)")
	check(Dice.roll(RNG.new(1), "5d1") == 5 and Dice.roll(RNG.new(1), "5d1", true) == 10,
		"d1 is the controllable die: 5d1 is 5, and 10 on a crit")

# --- 2. the numbers the UI promises --------------------------------------

func test_hit_chance_math() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ac = 15   # +5 vs 15: needs a 10, so 11 of 20 faces hit
	check(is_equal_approx(cb.hit_chance(a, b), 0.55), "hit chance is (21 - needed)/20 (%.3f)" % cb.hit_chance(a, b))
	check(is_equal_approx(cb.hit_chance(a, b, {"advantage": true}), 1.0 - 0.45 * 0.45),
		"advantage is 1-(1-p)^2, the same number BG3 shows")
	a.statuses["poisoned"] = true
	check(is_equal_approx(cb.hit_chance(a, b), 0.55 * 0.55), "disadvantage is p^2")
	a.statuses.erase("poisoned")
	b.ac = 100
	check(is_equal_approx(cb.hit_chance(a, b), 0.05), "a nat 20 always hits: floor 5%")
	b.ac = -100
	check(is_equal_approx(cb.hit_chance(a, b), 0.95), "a nat 1 always misses: ceiling 95%")
	b.ac = 15
	cb.board["cover"] = [b.pos]
	check(cb.effective_ac(b) == 17 and is_equal_approx(cb.hit_chance(a, b), 0.45), "half cover is +2 AC, and the chance says so")
	cb.board["cover"] = []

	# the caster's side of the same promise
	b.saves["dex"] = 3
	check(is_equal_approx(cb.save_fail_chance(b, 13, "dex"), 0.45), "save-fail chance: DC 13 vs +3 fails on 1-9")
	cb.board["cover"] = [b.pos]
	check(is_equal_approx(cb.save_fail_chance(b, 13, "dex"), 0.35), "cover is +2 on DEX saves (RAW half cover)")
	check(is_equal_approx(cb.save_fail_chance(b, 13, "dex", true), 0.45), "...unless the spell ignores cover (Sacred Flame)")
	b.saves["wis"] = 3
	check(is_equal_approx(cb.save_fail_chance(b, 13, "wis"), 0.45), "...and on DEX saves only: a wall is no help against Hold Person")
	# The roll itself, not just its preview: +3 on a d20 against DC 14 needs an
	# 11 without cover and a 9 with it, so over the same seeded rolls cover can
	# only ever move a DEX save, never a CON one (the concentration check).
	var made := {"dex": 0, "con": 0}
	b.saves["con"] = 3
	for ab in made.keys():
		for with_cover in [false, true]:
			cb.board["cover"] = [b.pos] if with_cover else []
			cb.rng = RNG.new(99)
			var n := 0
			for i in 200:
				if cb._saving_throw(b, 14, ab):
					n += 1
			made[ab] = n - int(made[ab]) if with_cover else n
	check(int(made["dex"]) > 0 and int(made["con"]) == 0,
		"cover adds to the DEX roll and not the CON one (extra saves made: %s)" % str(made))
	cb.board["cover"] = []
	# The preview reads what the roll reads. It used to see the save bonus,
	# cover and Dodge only.
	b.statuses["blessed"] = {"bonus_save": 2}
	check(is_equal_approx(cb.save_fail_chance(b, 13, "wis"), 0.35), "a +2 save buff shows in the odds")
	b.statuses.erase("blessed")
	cb.apply_condition(b, "paralyzed")
	check(is_equal_approx(cb.save_fail_chance(b, 13, "dex"), 1.0) and not cb._saving_throw(b, 2, "dex"),
		"a paralysed target auto-fails DEX, and the preview says 100%")
	b.statuses.erase("paralyzed")
	var hp_log: int = cb.log.size()
	b.statuses["inspired"] = {"dice_sides": 6}
	cb.save_fail_chance(b, 13, "wis")
	check(b.has("inspired") and cb.log.size() == hp_log, "the preview spends no inspiration and writes no line")
	b.statuses.erase("inspired")
	b.statuses["dodging"] = true
	check(is_equal_approx(cb.save_fail_chance(b, 13, "dex"), 1.0 - (1.0 - 0.45 * 0.45)),
		"a dodging target's DEX save is rolled with advantage in the preview")
	b.statuses.erase("dodging")

	# Shove / Grapple (2024): the target's save against DC 8 + STR mod + PB
	a.str_mod = 3; a.pb = 2
	b.saves["str"] = 1; b.saves["dex"] = 3
	check(cb.unarmed_dc(a) == 13, "the Unarmed Strike DC is 8 + STR mod + PB")
	check(is_equal_approx(cb.shove_chance(a, b), cb.save_fail_chance(b, 13, "dex")),
		"the shove readout is the target's fail chance on the better of STR and DEX")
	b.saves["str"] = 5
	check(is_equal_approx(cb.shove_chance(a, b), cb.save_fail_chance(b, 13, "str")), "...whichever that is")

# --- 3. initiative -------------------------------------------------------

func test_initiative_order() -> void:
	var a = _guy("a", "party", Vector2i(0, 0)); a.init_mod = 3
	var b = _guy("b", "foe", Vector2i(2, 0)); b.init_mod = -1
	var c = _guy("c", "party", Vector2i(4, 0)); c.init_mod = 0
	var cb = Combat.new(RNG.new(11), [a, b, c], _board())
	var sorted := true
	for i in cb.order.size() - 1:
		var x = cb.order[i]; var y = cb.order[i + 1]
		if x.init_roll < y.init_roll:
			sorted = false
	check(sorted, "the order is by initiative roll, highest first")
	for x in cb.combatants:
		check(x.init_roll - x.init_mod >= 1 and x.init_roll - x.init_mod <= 20, "%s rolled d20 + DEX mod" % x.id)
	check(cb.log[0].begins_with("Initiative:"), "the roll is printed (perfect information, combat-design.md §6)")

	# tie-breaks, on made-up rolls: modifier, then the party
	var p = _guy("p", "party", Vector2i.ZERO); var q = _guy("q", "foe", Vector2i.ZERO)
	p.init_roll = 15; q.init_roll = 12
	check(cb._init_before(p, q) and not cb._init_before(q, p), "higher roll first")
	q.init_roll = 15; p.init_mod = 1; q.init_mod = 2
	check(cb._init_before(q, p), "tied roll: higher modifier first (RAW's tie-break)")
	q.init_mod = 1
	check(cb._init_before(p, q) and not cb._init_before(q, p), "tied again: the party acts first (deterministic, no coin flip)")

# --- 4. the turn --------------------------------------------------------

func test_turn_cycle() -> void:
	var a = _guy("a", "party", Vector2i(0, 0)); var b = _guy("b", "foe", Vector2i(2, 0)); var c = _guy("c", "party", Vector2i(4, 0))
	var cb = Combat.new(RNG.new(1), [a, b, c], _board())
	cb.tracked = false
	var first = cb.current()
	cb.begin_turn(); cb.end_turn()
	check(first.has_acted and cb.current() == cb.order[1], "ending a turn marks the actor as having acted and moves on")
	cb.begin_turn(); cb.end_turn(); cb.begin_turn(); cb.end_turn()
	check(cb.round_num == 2 and cb.turn_idx == 0, "after everyone, a new round starts at the top")
	# the dead and the stable are skipped without a turn of their own
	cb.order[1].statuses["dead"] = true; cb.order[1].hp = 0
	cb.begin_turn(); cb.end_turn()
	check(cb.current() == cb.order[2], "a corpse is skipped")
	cb.order[1].statuses.erase("dead"); cb.order[1].hp = 0
	cb.order[1].statuses["down"] = true; cb.order[1].statuses["stable"] = true
	cb.turn_idx = 0
	cb.begin_turn(); cb.end_turn()
	check(cb.current() == cb.order[2], "a stable body is skipped — no more death saves once stable (RAW)")
	# a fresh turn refills the economy, and only the actor's
	var x = cb.order[2]
	x.econ["action"] = 0; x.econ["bonus"] = 0; x.econ["reaction"] = 0; x.econ["move_left"] = 0
	cb.begin_turn_for(x)
	check(x.econ["action"] == 1 and x.econ["bonus"] == 1 and x.econ["reaction"] == 1 and x.econ["move_left"] == x.speed,
		"your turn gives back one action, one bonus action, one reaction, full speed")
	for s in Combatant.TURN_STATUSES:
		x.statuses[s] = true
	cb.begin_turn_for(x)
	check(Combatant.TURN_STATUSES.all(func(s): return not x.has(s)),
		"Dodge, Disengage, Help's advantage and Reckless end at the start of your next turn")
	var fresh := _fight()
	fresh[0].round_num = Combat.MAX_ROUNDS + 1
	check(fresh[0].is_over() and fresh[0].outcome() == "ongoing",
		"the round cap ends the fight with no winner (encounter.resolve_outcome scores that as a Defeat, by design)")

# --- 5. the attack roll -------------------------------------------------

func test_attack_roll_edges() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ac = -50
	cb.rng = _rolls([1])
	var r = cb.resolve_attack(a, b)
	check(r["nat"] == 1 and not r["hit"], "a natural 1 misses whatever the AC")
	cb.begin_turn_for(a); b.ac = 99
	cb.rng = _rolls([20])
	r = cb.resolve_attack(a, b)
	check(r["hit"] and r["crit"], "a natural 20 hits whatever the AC, and is a critical hit")
	check(r["dmg_detail"]["rolls"].size() == 2 and r["dmg_detail"]["mod"] == 3, "the crit doubled the weapon die and not the +3")
	cb.begin_turn_for(a); a.crit_range = 19
	cb.rng = _rolls([19])
	check(cb.resolve_attack(a, b)["crit"], "a widened crit range (Champion) crits on the 19")
	a.crit_range = 20
	cb.begin_turn_for(a); b.ac = 15
	cb.rng = _rolls([10])
	r = cb.resolve_attack(a, b)
	check(r["total"] == 15 and r["hit"], "total equal to AC hits (RAW: 'equals or exceeds')")
	cb.begin_turn_for(a); b.ac = 16
	cb.rng = _rolls([10])
	check(not cb.resolve_attack(a, b)["hit"], "one under the AC misses")
	cb.begin_turn_for(a); b.ac = 12
	cb.rng = _rolls([19])
	r = cb.resolve_attack(a, b)
	check(r["hit"] and not r["crit"], "a 19 with a normal crit range is just a hit")
	# reach
	cb.begin_turn_for(a); b.pos = Vector2i(5, 1)
	check(cb.resolve_attack(a, b).get("error", "") == "out of range", "melee needs adjacency")
	check(a.econ["action"] == 1, "...and a refused swing costs nothing")
	a.ranged = true; a.atk_range = 3
	check(not cb.resolve_attack(a, b).has("error"), "a ranged weapon reaches its range")
	cb.begin_turn_for(a); b.pos = Vector2i(6, 1)
	check(cb.resolve_attack(a, b).has("error"), "...and not one hex past it")
	note("Q2 A ranged weapon's long range is not modelled: adapter.gd clamps to normal_ft and RANGE_CAP, so there is no 'disadvantage out to long range' band (RAW; BG3 also drops it, Solasta keeps it). Intentional?")

func test_attack_modifiers_on_the_roll() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ac = -50
	# Bless: +2 to hit (the engine averages the d4)
	a.statuses["spell:bless"] = {"bonus_to_hit": 2}
	cb.rng = _rolls([10])
	check(cb.resolve_attack(a, b)["bonus"] == 7, "a to-hit buff is added to the attack bonus")
	a.statuses.erase("spell:bless")
	# exhaustion: -2 per level on every d20 (2024)
	cb.begin_turn_for(a); a.statuses["exhaustion"] = {"level": 2}
	cb.rng = _rolls([10])
	check(cb.resolve_attack(a, b)["bonus"] == 1, "exhaustion 2 is -4 on the attack roll (2024 PHB)")
	a.statuses.erase("exhaustion")
	# Bardic Inspiration: one extra die, on the next roll, then gone
	cb.begin_turn_for(a); a.statuses["inspired"] = {"dice_sides": 8}
	cb.rng = _rolls([10])
	var r = cb.resolve_attack(a, b)
	check(r["bonus"] >= 6 and r["bonus"] <= 13 and not a.has("inspired"), "an inspiration die rides one attack and is spent")
	cb.begin_turn_for(a)
	a.statuses["inspired"] = {"dice_sides": 8}
	cb._saving_throw(a, 5, "wis")
	check(not a.has("inspired"), "...or one saving throw")
	# a spent Help is consumed by the swing, not by the turn
	cb.begin_turn_for(a); a.statuses["helped"] = true
	check(cb._attack_mode(a, b) == Dice.ADV, "Help: advantage on the next attack")
	cb.rng = _rolls([10, 10])
	cb.resolve_attack(a, b)
	check(not a.has("helped"), "...spent by that attack")
	# reckless: both ways
	cb.begin_turn_for(a); a.statuses["reckless"] = true
	check(cb._attack_mode(a, b) == Dice.ADV and cb._attack_mode(b, a) == Dice.ADV, "Reckless Attack: advantage for you and against you")
	a.statuses.erase("reckless")
	# vex is per target
	var c = _guy("c", "foe", Vector2i(2, 2))
	cb.combatants.append(c)
	a.statuses["vex"] = {"target": b}
	check(cb._attack_mode(a, b) == Dice.ADV and cb._attack_mode(a, c) == Dice.NORMAL, "Vex is advantage against that one creature")
	a.statuses.erase("vex")
	# prone target: melee advantage, ranged disadvantage
	b.statuses["prone"] = true
	check(cb._attack_mode(a, b) == Dice.ADV, "melee against a prone target has advantage")
	a.ranged = true; a.atk_range = 6
	check(cb._attack_mode(a, b) == Dice.DIS, "...and a ranged attack has disadvantage (RAW, both editions)")
	a.ranged = false; b.statuses.erase("prone")
	# hidden vs dodging cancel
	a.statuses["hidden"] = true; b.statuses["dodging"] = true
	check(cb._attack_mode(a, b) == Dice.NORMAL, "a hidden attacker against a dodging target rolls flat")
	a.statuses.clear(); b.statuses.clear()

# --- 6. damage -----------------------------------------------------------

func test_damage_defenses() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.resist = ["slashing"]
	cb._apply_damage(b, 7, "slashing")
	check(b.hp == 97, "resistance halves, rounding down (7 -> 3)")
	check(cb.log[-1].contains("resists slashing"), "...and says so in the log")
	b.hp = 100; b.resist = []; b.vulnerable = ["fire"]
	cb._apply_damage(b, 7, "fire")
	check(b.hp == 86, "vulnerability doubles")
	b.hp = 100; b.vulnerable = []; b.immune = ["poison"]
	cb._apply_damage(b, 50, "poison")
	check(b.hp == 100 and cb.log[-1].contains("immune"), "immunity is zero, and the log says why")
	b.immune = []
	b.hp = 100; b.resist = ["slashing"]; b.statuses["raging"] = {"resist": ["slashing"]}
	cb._apply_damage(b, 20, "slashing")
	check(b.hp == 90, "two sources of resistance halve once, never twice (RAW: resistance does not stack)")
	b.statuses.erase("raging")
	b.hp = 100
	cb._apply_damage(b, 10, "")
	check(b.hp == 90, "untyped damage bypasses a typed resistance")
	b.hp = 100; b.resist = ["fire"]; b.vulnerable = ["fire"]
	cb._apply_damage(b, 7, "fire")
	check(b.hp == 94, "resist+vulnerable to one type: RAW order, halve then double (7 -> 3 -> 6)")
	b.resist = []; b.vulnerable = []; b.hp = 100
	# the weapon's own damage type reaches the defence stack
	a.attacks = [{"id": "mace", "dice_count": 1, "dice_sides": 6, "dmg_bonus": 3, "damage_type": "bludgeoning", "mastery": ""}]
	b.immune = ["bludgeoning"]; b.ac = -50
	cb.begin_turn_for(a); cb.rng = _rolls([20])
	var r = cb.resolve_attack(a, b)
	check(r["hit"] and b.hp == 100, "a weapon hit carries the weapon's damage type into immunity")
	b.immune = []; a.attacks = []
	# temporary hit points: a buffer in front of HP, lost first, never stacking
	cb.grant_temp_hp(b, 10)
	cb.grant_temp_hp(b, 5)
	check(b.temp_hp == 10, "temp HP never stack: the higher amount stays")
	cb._apply_damage(b, 7, "")
	check(b.temp_hp == 3 and b.hp == 100, "damage comes off temp HP first")
	cb._apply_damage(b, 7, "")
	check(b.temp_hp == 0 and b.hp == 96, "...and the remainder off real HP")
	b.resist = ["fire"]
	cb.grant_temp_hp(b, 10)
	cb._apply_damage(b, 8, "fire")
	check(b.temp_hp == 6 and b.hp == 96, "resistance is applied before the buffer absorbs")
	b.resist = []; b.temp_hp = 0
	cb.heal(b, 50)
	check(b.hp == 100 and b.temp_hp == 0, "healing never refills temp HP")

# --- 7. concentration ---------------------------------------------------

func test_concentration_checks() -> void:
	var ally = _guy("ally", "party", Vector2i(1, 1))
	var f := _fight({}, [ally]); var cb = f[0]; var a = f[1]; var b = f[2]
	a.statuses["concentrating"] = {"spell": "bless", "until_round": 99}
	ally.statuses["spell:bless"] = {"held_by": a, "spell": "bless", "bonus_to_hit": 2}
	a.saves["con"] = 100
	cb._apply_damage(a, 30)
	check(a.has("concentrating"), "a made CON save keeps the spell")
	a.saves["con"] = -100
	cb._apply_damage(a, 0)
	check(a.has("concentrating"), "zero damage forces no save")
	cb._apply_damage(a, 1)
	check(not a.has("concentrating") and not ally.statuses.has("spell:bless"),
		"a failed save ends the spell and strips it from everyone it was holding")
	# the DC is 10 or half the damage, whichever is higher (2024: same, cap 30 not modelled)
	a.saves["con"] = 0
	a.statuses["concentrating"] = {"spell": "bless", "until_round": 99}
	cb.rng = _rolls([10]); cb._apply_damage(a, 10)
	check(a.has("concentrating"), "10 damage: DC 10, a 10 holds it")
	cb.rng = _rolls([10]); cb._apply_damage(a, 19)
	check(a.has("concentrating"), "19 damage: still DC 10 (half rounds down to 9, floor 10)")
	cb.rng = _rolls([10]); cb._apply_damage(a, 22)
	check(not a.has("concentrating"), "22 damage: DC 11, a 10 loses it")
	# going down or dying ends it, no roll
	a.hp = 5; a.saves["con"] = 100
	a.statuses["concentrating"] = {"spell": "bless", "until_round": 99}
	cb._apply_damage(a, 10)
	check(a.is_down() and not a.has("concentrating"), "dropping to 0 HP ends concentration")
	b.saves["con"] = 100
	b.statuses["concentrating"] = {"spell": "bless", "until_round": 99}
	cb._apply_damage(b, 999)
	check(b.is_dead() and not b.has("concentrating"), "so does dying")

# --- 8. 0 HP -------------------------------------------------------------

func test_zero_hp_and_death() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	cb._apply_damage(b, 100)
	check(b.is_dead() and b.hp == 0 and not b.conscious(), "a monster at 0 HP dies outright (RAW: DM's call; every 5e CRPG does this)")
	a.hp = 5; a.statuses["prone"] = true; a.death_f = 2
	cb._apply_damage(a, 5)
	check(a.is_down() and a.hp == 0 and not a.is_dead(), "a hero at 0 HP is down, not dead")
	check(not a.has("prone") and a.death_s == 0 and a.death_f == 0, "going down clears prone and starts the death saves fresh")
	check(cb.downed.has("hero"), "...and the fight remembers who went down (encounter scoring)")
	# instant death: remaining damage >= max HP
	var g := _fight(); var c2 = g[1]
	c2.hp = 5
	g[0]._apply_damage(c2, 105)
	check(c2.is_dead(), "damage that leaves 100 past 0 on a 100-HP hero is instant death (RAW massive damage)")
	var h := _fight(); var c3 = h[1]
	c3.hp = 5
	h[0]._apply_damage(c3, 104)
	check(c3.is_down() and not c3.is_dead(), "...and one point less is just down")
	# damage to the downed
	cb._apply_damage(a, 3)
	check(a.death_f == 1, "any damage to a downed creature is a failed death save")
	cb._apply_damage(a, 0)
	check(a.death_f == 1, "...but zero damage is not")
	cb._apply_damage(a, 3, "", true)
	check(a.is_dead(), "a critical hit is two failures: that was the third")
	# a melee hit on a body from reach is automatically a crit (Unconscious)
	var k := _fight(); var kb = k[0]; var ka = k[1]; var kk = k[2]
	ka.statuses["down"] = true; ka.hp = 0; ka.ac = -50
	kb.rng = _rolls([10, 10])
	var r = kb.resolve_attack(kk, ka)
	check(r["hit"] and r["crit"] and ka.death_f == 2, "a melee swing at a downed body auto-crits: two failures from one blow")
	check(kb._attack_mode(kk, ka) == Dice.ADV, "attacks against the unconscious have advantage")
	var m := _fight(); var mb = m[0]; var ma = m[1]; var mk = m[2]
	ma.statuses["down"] = true; ma.hp = 0; ma.ac = -50
	mk.ranged = true; mk.atk_range = 6; mk.pos = Vector2i(6, 1)
	mb.rng = _rolls([10, 10])
	r = mb.resolve_attack(mk, ma)
	check(r["hit"] and not r["crit"] and ma.death_f == 1, "a ranged hit on a body is one failure — no auto-crit from range")
	ma.max_hp = 30
	mb._apply_damage(ma, 30)
	check(ma.is_dead(), "damage to a downed body that meets its max HP is death outright (massive damage)")

func test_death_saves() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]
	a.statuses["down"] = true; a.hp = 0
	cb.rng = _rolls([20]); cb._death_save(a)
	check(not a.is_down() and a.hp == 1 and a.death_s == 0 and a.death_f == 0, "nat 20: back up on 1 HP, saves cleared")
	a.statuses["down"] = true; a.hp = 0
	cb.rng = _rolls([1]); cb._death_save(a)
	check(a.death_f == 2, "nat 1: two failures")
	cb.rng = _rolls([10]); cb._death_save(a)
	check(a.death_s == 1, "10 is a success")
	cb.rng = _rolls([9]); cb._death_save(a)
	check(a.is_dead(), "9 is a failure, and three failures is death")
	var g := _fight(); var gb = g[0]; var ga = g[1]
	ga.statuses["down"] = true; ga.hp = 0
	for i in 2:
		gb.rng = _rolls([15]); gb._death_save(ga)
	check(ga.is_down() and ga.death_s == 2, "two successes: still down")
	gb.rng = _rolls([15]); gb._death_save(ga)
	check(not ga.is_down() and ga.hp == 1 and ga.death_s == 0, "three successes: back on your feet at 1 HP (house rule, BG3's)")
	ga.statuses["down"] = true; ga.statuses["stable"] = true; ga.hp = 0
	gb.heal(ga, 4)
	check(not ga.is_down() and not ga.is_stable() and ga.hp == 4, "healing a stable body (one the road handed over) brings it up on the amount healed")

func test_healing() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	a.hp = 95
	cb.heal(a, 50)
	check(a.hp == 100, "healing caps at max HP")
	a.hp = 0; a.statuses["down"] = true; a.death_f = 2; a.death_s = 1
	cb.heal(a, 7)
	check(a.hp == 7 and not a.is_down() and a.death_f == 0, "healing the downed: up at the amount, saves reset")
	cb._apply_damage(b, 999)
	cb.heal(b, 50)
	check(b.is_dead() and b.hp == 0, "the dead cannot be healed")

# --- 9. movement ---------------------------------------------------------

func test_movement_rules() -> void:
	var f := _fight(_corridor()); var cb = f[0]; var a = f[1]; var b = f[2]
	a.pos = Vector2i(2, 0); b.pos = Vector2i(5, 0); a.speed = 2
	cb.begin_turn_for(a)
	var ally = _guy("ally", "party", Vector2i(3, 0))
	cb.combatants.append(ally)
	var field: Dictionary = cb.move_field(a)
	check(field.has(Vector2i(4, 0)) and not field.has(Vector2i(3, 0)), "you can move through an ally's space but not stop in it (RAW)")
	# #199: the fighter ended his move on the rogue bleeding out under him, and
	# the cleric's Cure Wounds then went to whichever token the list held first.
	ally.hp = 0; ally.statuses["down"] = true
	field = cb.move_field(a)
	check(field.has(Vector2i(4, 0)) and not field.has(Vector2i(3, 0)), "a downed ally's space can be crossed but not stopped in (#199)")
	check(not cb._hex_free(Vector2i(3, 0)), "a downed ally still fills the hex a shove or a summon would land in (#199)")
	ally.statuses["dead"] = true
	check(cb.move_field(a).has(Vector2i(3, 0)) and cb._hex_free(Vector2i(3, 0)), "a corpse is an object: it can be stood on")
	ally.statuses.erase("dead"); ally.statuses.erase("down"); ally.hp = ally.max_hp
	ally.pos = Vector2i(-5, 0)
	b.pos = Vector2i(3, 0)
	field = cb.move_field(a)
	check(not field.has(Vector2i(4, 0)) and field.has(Vector2i(0, 0)), "a hostile's space is a wall")
	b.pos = Vector2i(6, 0)
	cb.board["rough"] = [Vector2i(3, 0)]
	field = cb.move_field(a)
	check(int(field.get(Vector2i(3, 0), -1)) == 2 and not field.has(Vector2i(4, 0)), "difficult terrain costs double")
	cb.board["rough"] = []
	cb.perform(a, cb._basic("dash"))
	check(a.econ["move_left"] == 4 and a.econ["action"] == 0, "Dash: the Action buys another speed's worth of movement")
	cb.begin_turn_for(a)
	cb.move_to(a, Vector2i(4, 0))
	check(a.pos == Vector2i(4, 0) and a.econ["move_left"] == 0, "moving spends move points by path cost")
	cb.move_to(a, Vector2i(5, 0))
	check(a.pos == Vector2i(4, 0), "with no movement left you stay put")
	a.speed = 6
	a.statuses["slowed"] = {"until_tick": 999999}
	cb.begin_turn_for(a)
	check(cb.move_left(a) == 4, "Slow is -10 ft, which is two hexes here")
	a.statuses.erase("slowed")
	a.statuses["spell:haste"] = {"speed_mult": 2, "extra_action": 1, "until_tick": 999999}
	cb.begin_turn_for(a)
	check(cb.move_left(a) == 12 and a.econ["action"] == 2, "Haste: double speed and a second action")
	a.statuses.erase("spell:haste")
	a.statuses["prone"] = {"held_by": b}
	cb.begin_turn_for(a)
	check(a.has("prone") and a.econ["move_left"] == a.speed, "a prone that a spell holds you in (Hideous Laughter) is not stood up from, and costs nothing")
	a.statuses.erase("prone")

func test_opportunity_attacks() -> void:
	# an archer's OA is a melee swing for a flat 1 (no sidearm on the statblock)
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ranged = true; b.atk_range = 6
	cb.rng = _rolls([20])
	cb.move_to(a, Vector2i(0, 1))
	check(a.hp == 99 and b.econ["reaction"] == 0, "an archer's opportunity attack lands as melee for 1 and spends its reaction")
	check(cb.log.any(func(l): return l.begins_with("OA ")), "...and is logged as an OA")
	# a spent reaction provokes nothing more; an illusion never swings
	a.pos = Vector2i(2, 1)
	check(cb.provokers_for(a, Vector2i(0, 1)).is_empty(), "no reaction, no opportunity attack")
	cb.begin_turn_for(b)
	b.statuses["illusion"] = {"no_attack": true}
	check(cb.provokers_for(a, Vector2i(0, 1)).is_empty(), "a creature that cannot attack (Invoke Duplicity's double) threatens nothing")
	b.statuses.erase("illusion")
	# dropped mid-walk: the body lies where the blow fell
	var g := _fight(); var gb = g[0]; var ga = g[1]
	ga.hp = 1
	gb.rng = _rolls([20])
	gb.move_to(ga, Vector2i(0, 1))
	check(ga.is_down() and ga.pos == Vector2i(2, 1), "a mover dropped by the OA stops on the hex it was hit on")
	# the OA is judged from the hex you leave from, so cover there counts
	var h := _fight(); var hb = h[0]; var ha = h[1]; var hk = h[2]
	hb.board["cover"] = [Vector2i(2, 1)]
	hb.rng = _rolls([10])
	hb.move_to(ha, Vector2i(0, 1))
	var oa_line: String = ""
	for l in hb.log:
		if l.begins_with("OA "):
			oa_line = l
	check(oa_line.contains("vs AC 14"), "the OA is rolled against the AC you had on the hex you stepped out of (cover included)")
	# reach: a glaive threatens two hexes, and its OA fires when you leave the second
	var k := _fight(); var kb = k[0]; var ka = k[1]; var kk = k[2]
	kk.pos = Vector2i(4, 1)
	check(not kb.in_reach(ka, kk), "a 5-ft weapon does not reach two hexes")
	ka.reach = 2
	check(kb.in_reach(ka, kk) and not kb.resolve_attack(ka, kk).has("error"), "a reach weapon does (10 ft)")
	kb.begin_turn_for(ka); kb.begin_turn_for(kk)
	check(kb.provokers_for(kk, Vector2i(6, 1)).size() == 1, "...and leaving its 10-ft reach provokes")
	check(kb.provokers_for(kk, Vector2i(3, 1)).is_empty(), "stepping closer inside it does not")

func test_forced_movement() -> void:
	var f := _fight(_corridor()); var cb = f[0]; var a = f[1]; var b = f[2]
	a.pos = Vector2i(2, 0); b.pos = Vector2i(3, 0)
	check(cb._push_away(a, b, 2) == 2 and b.pos == Vector2i(5, 0), "a push moves the target straight away from the pusher")
	a.pos = Vector2i(4, 0)
	check(cb._push_away(a, b, 2) == 1 and b.pos == Vector2i(6, 0), "...and stops at the board's edge")
	var c = _guy("c", "party", Vector2i(3, 0)); cb.combatants.append(c)
	a.pos = Vector2i(1, 0); b.pos = Vector2i(2, 0)
	check(cb._push_away(a, b, 2) == 0 and b.pos == Vector2i(2, 0), "...or against another creature")
	check(cb.hexes_from_ft(10) == 2 and cb.hexes_from_ft(5) == 1 and cb.hexes_from_ft(15) == 3,
		"5 ft is a hex, 10 ft rounds to two, 15 ft to three (6 ft per hex, rounded)")
	check(Adapter.area_hexes(15) == 2, "...but an AREA floors: a 15-ft cone is the 2-hex wedge the room was tuned on")
	note("Q1 (re-checked, still true) Feet-to-hexes rounds for distances (hexes_from_ft: 15 ft -> 3) and floors for areas (adapter.area_hexes: 15 ft -> 2, documented there as the cone the room was tuned on). Recommend leaving both: a 15-ft push rounding to 3 hexes is generous, a cone flooring to 2 is the design's number.")

# --- 10. the other actions ----------------------------------------------

func test_dodge_dash_disengage_help() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	cb.perform(a, cb._basic("dodge"))
	check(a.has("dodging") and cb._attack_mode(b, a) == Dice.DIS, "Dodge: attacks against you have disadvantage")
	check(not cb.available(a).any(func(v): return v["id"] == "dodge"), "you cannot Dodge twice")
	cb.rng = _rolls([5, 18])
	check(cb._saving_throw(a, 12, "dex"), "Dodge: DEX saves with advantage (5 and 18: the 18 counts)")
	cb.rng = _rolls([5, 18])
	check(not cb._saving_throw(a, 12, "wis"), "...and no other save (a lone 5 fails: DEX only, RAW)")
	a.statuses["stunned"] = true
	check(cb._attack_mode(b, a) == Dice.ADV, "a dodging creature that is Stunned loses the Dodge (RAW)")
	cb.rng = _rolls([5, 18])
	check(not cb._saving_throw(a, 12, "con"), "...on saves too")
	a.statuses.erase("stunned")
	a.statuses["grappled"] = true
	cb.rng = _rolls([5, 18])
	check(not cb._saving_throw(a, 12, "dex"), "...and so does one held at speed 0 (a lone 5 again)")
	a.statuses.erase("grappled"); a.statuses.erase("dodging")
	cb.begin_turn_for(a)
	cb.perform(a, cb._basic("disengage"))
	cb.rng = _rolls([20])
	cb.move_to(a, Vector2i(0, 1))
	check(a.hp == 100 and b.econ["reaction"] == 1, "Disengage: leaving reach provokes nothing this turn")
	# Help: an ally's advantage, not your own
	var c = _guy("c", "party", Vector2i(1, 1)); cb.combatants.append(c)
	a.pos = Vector2i(2, 1)
	cb.begin_turn_for(c)
	var help: Dictionary = cb._basic("help")
	check(not cb.legal_target(c, help, c), "you cannot Help yourself")
	check(cb.legal_target(c, help, a), "an adjacent ally is a legal Help target")
	cb.perform(c, help, a)
	check(a.has("helped") and c.econ["action"] == 0, "Help costs the helper's Action and marks the ally")
	cb.begin_turn_for(a)
	check(a.has("helped"), "the ally's own turn does not take Help's advantage away")
	cb.begin_turn_for(c)
	check(not a.has("helped"), "...the helper's next turn does (RAW: 'before the start of your next turn')")
	note("Q10 Help is RAW 2024 'within 5 feet of the ally' here (range 1). 2024 also allows Help on an ability check, and Solasta lets the helper stand beside the TARGET. Fine as is; flagging the variant.")

func test_hide_dc() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.passive_perception = 12
	var c = _guy("c", "foe", Vector2i(6, 3)); c.passive_perception = 15
	cb.combatants.append(c)
	check(cb.hide_dc_against(b) == 12 and cb.hide_dc_against(c) == 15, "the DC is the observer's passive Perception")
	c.statuses["dead"] = true; c.hp = 0
	var dc_dead := 0
	for e in cb.enemies_of(a):
		dc_dead = maxi(dc_dead, cb.hide_dc_against(e))
	check(dc_dead == 12, "a dead observer sees nothing: the hardest LIVING enemy sets the DC")
	c.statuses.erase("dead"); c.hp = 100
	c.verbs = [{"id": "kh", "kind": "keen_senses", "relies_on": ["hearing"], "passive_bonus": 5}]
	check(cb.hide_dc_against(c) == 20, "Keen Hearing: +5 (advantage on the passive check)")
	c.statuses["deafened"] = true
	check(cb.hide_dc_against(c) == 15, "...gone while it is deafened")
	c.statuses.erase("deafened"); c.statuses["blinded"] = true
	check(cb.hide_dc_against(c) == 15, "blinded: -5 for the eyes, +5 for the ears it still has")
	c.statuses["deafened"] = true
	check(cb.hide_dc_against(c) == 10, "blinded and deafened: just the nose")
	c.statuses.clear(); c.verbs = []
	a.stealth = 100
	cb.begin_turn_for(a)
	check(cb.perform(a, cb._basic("hide")).is_empty() and a.has("hidden") and a.econ["action"] == 0, "Hide is an Action")
	check(not cb.available(a).any(func(v): return v["id"] == "hide"), "...and not offered while already hidden")
	# Hide needs no cover here — a plain Stealth check, by design (decided 2026-09-19).

# 2024 PHB: Shove and Grapple are Unarmed Strikes — one of your attacks, a
# STR-or-DEX save for the target against 8 + STR + PB, and a one-size cap.
func test_shove() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	a.str_mod = 100   # DC 110: nobody saves
	check(cb.act_shove(a, b, "prone")["success"] and b.has("prone"), "a failed save knocks prone")
	b.statuses.erase("prone")
	check(cb.act_shove(a, b, "push")["success"] and b.pos == Vector2i(4, 1), "...or pushes 5 ft straight back")
	a.str_mod = -100; b.pos = Vector2i(3, 1)
	check(not cb.act_shove(a, b, "prone")["success"] and not b.has("prone"), "a made save does nothing")
	a.str_mod = 3
	b.statuses["paralyzed"] = true
	check(cb.act_shove(a, b, "prone")["success"], "a paralyzed target auto-fails the STR/DEX save and goes down")
	b.statuses.clear()
	# economy: one of the Attack action's attacks, not the whole action
	a.str_mod = 100
	a.verbs = [{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	cb.begin_turn_for(a)
	var v: Dictionary = cb._basic("shove_prone")
	cb.perform(a, v, b)
	check(a.econ["action"] == 0 and a.econ["attacks_left"] == 1, "a Shove is one attack of the Attack action")
	check(not cb.resolve_attack(a, b).has("error"), "...so Extra Attack still swings after it")
	check(cb.perform(a, v, b).has("error"), "...and a third attempt has nothing left to spend")
	a.verbs = []
	# size: no more than one size larger than you
	b.size = "Large"
	check(cb.legal_target(a, v, b), "a Medium hero may shove a Large ogre")
	b.size = "Huge"
	check(not cb.legal_target(a, v, b), "...but not a Huge one")
	cb.begin_turn_for(a)
	check(cb.perform(a, v, b).has("error") and a.econ["action"] == 1, "the resolver refuses it too, before anything is spent")
	b.size = "Medium"
	var g := _fight(_corridor()); var gb = g[0]; var ga = g[1]; var gk = g[2]
	ga.pos = Vector2i(5, 0); gk.pos = Vector2i(6, 0); ga.str_mod = 100
	gb.act_shove(ga, gk, "push")
	check(gk.pos == Vector2i(6, 0) and gk.has("prone"), "a push with nowhere to go becomes a knockdown")
	var h := _fight(); var hb = h[0]; var ha = h[1]
	ha.athletics = 0
	check(hb.all_verbs(ha).any(func(x): return x["kind"] == "shove"), "anyone can try a Shove (no Athletics gate any more)")

func test_grapple() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	a.str_mod = 100
	var grapple: Dictionary = cb._basic("grapple")
	check(cb.available(a).any(func(x): return x["id"] == "grapple"), "Grapple is on the bar beside an enemy")
	check(not cb.available(b).any(func(x): return x["id"] == "escape"), "...and Break free is not, for someone not held")
	cb.perform(a, grapple, b)
	check(a.econ["action"] == 0, "a Grapple is one of the Attack action's attacks")
	check(b.has("grappled") and cb._grappler_of(b) == a, "a failed save: Grappled, and it remembers by whom")
	cb.begin_turn_for(b)
	check(cb.move_left(b) == 0, "Grappled: speed 0")
	check(not cb.legal_target(a, grapple, b), "one grapple per victim: no second Grapple on the same target")
	check(cb.available(b).any(func(x): return x["id"] == "escape"), "the held creature is offered Break free")
	b.athletics = -100; b.acro = -100
	cb.perform(b, cb._basic("escape"))
	check(b.has("grappled") and b.econ["action"] == 0, "a failed escape check costs the action and changes nothing")
	cb.begin_turn_for(b); b.acro = 200
	cb.perform(b, cb._basic("escape"))
	check(not b.has("grappled"), "Athletics or Acrobatics against the grappler's DC breaks it")
	cb.perform(a, grapple, b) if cb.can_afford(a, grapple) else cb.act_grapple(a, b)
	a.pos = Vector2i(6, 1)
	cb._release_grapples()
	check(not b.has("grappled"), "a grappler that ends up out of reach lets go")
	a.pos = Vector2i(2, 1); cb.act_grapple(a, b)
	a.statuses["stunned"] = true; cb._release_grapples()
	check(not b.has("grappled"), "a Stunned grappler lets go")
	a.statuses.clear(); cb.act_grapple(a, b)
	a.hp = 1; cb._apply_damage(a, 5)
	check(a.is_down() and not b.has("grappled"), "...and so does one who goes down")
	var g := _fight(); var gb = g[0]; var ga = g[1]; var gk = g[2]
	ga.str_mod = 100; gk.cond_immune = ["grappled"]
	check(not gb.act_grapple(ga, gk)["success"] and not gk.has("grappled"), "an ungrappleable creature is not grappled")
	var h := _fight(); var hb = h[0]; var ha = h[1]; var hk = h[2]
	ha.str_mod = -100
	check(not hb.act_grapple(ha, hk)["success"] and not hk.has("grappled"), "a made save: nothing")
	hk.size = "Huge"
	check(not hb.legal_target(ha, grapple, hk), "the one-size cap applies to Grapple too")

func test_smash_and_hazards() -> void:
	var board := _corridor()
	board["objects"] = [{"type": "barrel", "pos": Vector2i(3, 0), "hp": 5, "blocks_movement": true}]
	var f := _fight(board); var cb = f[0]; var a = f[1]; var b = f[2]
	a.pos = Vector2i(2, 0); b.pos = Vector2i(6, 0)
	check(not cb.passable(Vector2i(3, 0)), "a barrel blocks the hex")
	check(cb.available(a).any(func(v): return v["id"] == "smash"), "Smash is offered beside it")
	cb.perform(a, cb._basic("smash"))
	check(cb.objects().is_empty() and cb.passable(Vector2i(3, 0)) and a.econ["action"] == 0, "one Action, no roll, the hex clears")
	var hz := _corridor()
	hz["objects"] = [{"type": "brazier", "pos": Vector2i(4, 0), "hazard": {"dice": "2d6", "damage_type": "fire"}}]
	var g := _fight(hz); var gb = g[0]; var ga = g[1]; var gk = g[2]
	ga.pos = Vector2i(2, 0); gk.pos = Vector2i(3, 0); ga.athletics = 100
	var r: Dictionary = gb.perform(ga, gb._basic("shove_brazier"), gk)
	check(not r.has("error") and gk.hp < 100 and gb.log[-1].contains("fire"), "shoved into the brazier: 2d6 fire, no attack roll")
	gk.pos = Vector2i(1, 0); gk.hp = 100; gb.begin_turn_for(ga)
	r = gb.perform(ga, gb._basic("shove_brazier"), gk)
	check(r.has("error") and ga.econ["action"] == 1, "no hazard beside the target: refused before the Action is spent")
	gk.immune = ["fire"]; gk.pos = Vector2i(3, 0); gk.hp = 100
	gb.begin_turn_for(ga)
	gb.perform(ga, gb._basic("shove_brazier"), gk)
	check(gk.hp == 100, "the brazier's damage carries the hazard's type: a fire-immune creature is not burned")

# --- 11. the economy ---------------------------------------------------------

func test_action_economy_rules() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ac = -50
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(cb.resolve_attack(a, b).get("error", "") == "no action left", "one Attack action, one swing")
	a.verbs = [{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	cb.begin_turn_for(a)
	cb.rng = _rolls([10, 10]); cb.resolve_attack(a, b); cb.resolve_attack(a, b)
	check(cb.resolve_attack(a, b).has("error"), "Extra Attack: two swings per Attack action, not three")
	check(a.econ["bonus"] == 1, "...and the bonus action is untouched")
	a.verbs = []
	cb.begin_turn_for(a)
	cb.resolve_attack(a, b, {"free": true})
	check(a.econ["action"] == 1, "a free swing (Cleave, an OA) spends no action")
	# the bonus-action spell rule, both directions
	a.slots.assign([3, 0, 0, 0, 0, 0, 0, 0, 0])
	var bonus_spell := {"id": "bs", "kind": "spell", "spell": "x", "label": "Bonus Heal", "cost": "bonus", "slot_level": 1,
		"targeting": "self", "shape": "self", "range": 1, "heal_count": 1, "heal_sides": 4, "heal_bonus": 0}
	var action_spell := {"id": "as", "kind": "spell", "spell": "y", "label": "Action Heal", "cost": "action", "slot_level": 1,
		"targeting": "self", "shape": "self", "range": 1, "heal_count": 1, "heal_sides": 4, "heal_bonus": 0}
	var cantrip := {"id": "ct", "kind": "spell", "spell": "z", "label": "Cantrip", "cost": "action", "slot_level": 0,
		"targeting": "self", "shape": "self", "range": 1, "heal_count": 1, "heal_sides": 4, "heal_bonus": 0}
	cb.begin_turn_for(a)
	cb.perform(a, bonus_spell, a)
	check(a.slots[0] == 2 and a.econ["bonus"] == 0, "a bonus-action spell spends its slot and the bonus action")
	check(not cb._offerable(a, action_spell), "after a bonus-action leveled spell, no leveled spell with the Action (RAW)")
	check(cb._offerable(a, cantrip), "...but a cantrip is fine (RAW)")
	cb.begin_turn_for(a)
	cb.perform(a, action_spell, a)
	check(not cb._offerable(a, bonus_spell), "...and the other way round: after an Action leveled spell, no bonus-action leveled spell (RAW)")
	check(cb.cast(a, bonus_spell, a).has("error"), "the resolver refuses it as well")
	check(not cb.cast(a, cantrip, a).has("error"), "a cantrip still fits")
	cb.begin_turn_for(a)
	a.slots.assign([5, 0, 0, 0, 0, 0, 0, 0, 0])
	a.econ["action"] = 2   # Action Surge
	cb.perform(a, action_spell, a)
	check(cb._offerable(a, action_spell), "two Action leveled spells (Action Surge) are fine — the rule is about the bonus action")
	# a downed or dead actor has no economy
	a.statuses["down"] = true; a.hp = 0
	check(cb.available(a).is_empty() and cb.resolve_attack(a, b).has("error"), "the downed do nothing")

func test_reaction_once_per_round() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.max_hp = 1000; b.hp = 1000; b.ac = -50
	b.verbs = [{"id": "ud", "kind": "reaction", "cost": "reaction", "trigger": "hit_by_attack", "halve_damage": true, "label": "Uncanny Dodge"}]
	a.damage = "100"
	a.verbs = [{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(b.hp == 950 and b.econ["reaction"] == 0, "the reaction halves the first blow and is spent")
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(b.hp == 850, "the second blow in the same round lands in full: one reaction per round")
	cb.begin_turn_for(b)
	check(b.econ["reaction"] == 1, "it comes back at the start of its own turn")
	b.statuses["paralyzed"] = true
	cb.begin_turn_for(a)
	cb.rng = _rolls([10, 10]); cb.resolve_attack(a, b)
	check(b.hp == 750 and b.econ["reaction"] == 1, "a paralyzed creature cannot use its reaction: the blow (an auto-crit, flat 100) lands in full and the reaction is unspent")

# --- 12. conditions the matrix test does not reach ------------------------

func test_condition_gaps() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	a.statuses["incapacitated"] = true
	cb.begin_turn_for(a)
	check(not cb.can_spend(a, "action") and not cb.can_spend(a, "bonus") and not cb.can_spend(a, "reaction"),
		"Incapacitated: no action, bonus action or reaction")
	check(cb.move_left(a) == a.speed and cb.move_field(a).size() > 1, "...but you can still move (RAW: Incapacitated does not touch speed)")
	a.statuses.clear()
	a.statuses["restrained"] = true
	cb.rng = _rolls([18, 5])
	check(not cb._saving_throw(a, 12, "dex"), "Restrained: DEX saves at disadvantage (18 and 5: the 5 counts)")
	cb.rng = _rolls([18, 5])
	check(cb._saving_throw(a, 12, "str"), "...and STR saves are untouched")
	check(cb.move_left(a) == 0, "Restrained: speed 0")
	a.statuses.clear()
	a.statuses["stunned"] = true
	check(not cb._saving_throw(a, 1, "str") and not cb._saving_throw(a, 1, "dex"), "Stunned: STR and DEX saves fail automatically")
	cb.rng = _rolls([20])
	check(cb._saving_throw(a, 12, "con"), "...a CON save is still rolled")
	a.statuses.clear()
	# duration "round": gone at the bearer's next turn, "" lasts
	cb.apply_condition(b, "poisoned", a, "round")
	check(b.has("poisoned"), "a one-round condition lands")
	cb.round_num += 1
	cb.begin_turn_for(b)
	check(not b.has("poisoned"), "...and lapses at the bearer's next turn")
	cb.apply_condition(b, "poisoned", a)
	cb.round_num += 1
	cb.begin_turn_for(b)
	check(b.has("poisoned"), "an open-ended one stays")
	cb.apply_condition(b, "poisoned", a)
	check(b.statuses.keys().count("poisoned") == 1, "conditions never stack: a second poisoned is the same poisoned")
	b.statuses.erase("poisoned")
	b.cond_immune = ["poisoned"]
	cb.apply_condition(b, "poisoned", a)
	check(not b.has("poisoned") and cb.log[-1].contains("cannot be poisoned"), "condition immunity refuses it and says so")
	b.cond_immune = []
	# charmed: only the charmer is off limits
	var c = _guy("c", "foe", Vector2i(2, 2)); cb.combatants.append(c)
	cb.apply_condition(a, "charmed", b)
	var atk: Dictionary = cb._basic("attack")
	check(not cb.legal_target(a, atk, b) and cb.legal_target(a, atk, c), "Charmed: cannot attack the charmer, can attack its friends")
	a.statuses.clear()
	a.statuses["prone"] = true
	check(cb._attack_mode(a, b) == Dice.DIS, "Prone: your own attacks have disadvantage")
	a.statuses.clear()
	a.statuses["blinded"] = true
	check(cb._attack_mode(a, b) == Dice.DIS and cb._attack_mode(b, a) == Dice.ADV, "Blinded: disadvantage out, advantage in")
	a.statuses.clear()
	note("Q16 Blinded/Deafened auto-fail lists feed only the Hide DC. A blinded attacker gets the flat 'own_attacks dis' rather than the RAW 'cannot see the target' (which would also make a hidden/invisible target simply unseen). Same outcome for attacks; fine.")
	# Sleep (2024): WIS save or Unconscious for a minute; damage wakes it
	var s := _fight(); var sb = s[0]; var sa = s[1]; var sk = s[2]
	sk.saves["wis"] = -100
	sb._spell_hit(sk, {"save": "wis", "conditions": ["unconscious"], "duration": "minute", "repeat_save": "damage_ends", "label": "Sleep"}, "0d1", 10, sa)
	check(sk.has("unconscious") and not sb.can_spend(sk, "action") and sb.move_left(sk) == 0, "asleep: Unconscious, no actions, no movement")
	check(sb._attack_mode(sa, sk) == Dice.ADV, "...and attacks against it have advantage")
	sb.round_num += 1; sb.begin_turn_for(sk)
	check(sk.has("unconscious"), "it does not wake at its next turn on its own")
	sb._apply_damage(sk, 1)
	check(not sk.has("unconscious"), "damage wakes it")

# --- 13. spells ----------------------------------------------------------

func test_spell_rules() -> void:
	# cantrips scale with CHARACTER level at 5, 11, 17 — not with slots
	for pair in [[3, 1], [5, 2], [11, 3], [17, 4]]:
		var vs := Effects.spell_verbs_for(Presets.ilsa(int(pair[0])).sheet(), ["sacred-flame"])
		check(vs.size() == 1 and int(vs[0]["dice_count"]) == int(pair[1]), "Sacred Flame is %dd8 at level %d" % [int(pair[1]), int(pair[0])])
	var sheet = Presets.ilsa().sheet()
	check(int(sheet.spellcasting["save_dc"]) == 13 and int(sheet.spellcasting["attack_bonus"]) == 5,
		"a cleric 3 with WIS 16: DC 8+2+3 = 13, spell attack +5")
	var ids := Effects.spell_verbs_for(sheet, ["burning-hands"]).map(func(v): return String(v["id"]))
	check(ids == ["burning-hands", "burning-hands@2"], "one verb per slot level the caster actually has (4/2 slots: base and one upcast)")
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	var spell := {"id": "fb", "kind": "spell", "spell": "fireball", "label": "Test Bolt", "cost": "action", "slot_level": 1,
		"targeting": "enemy", "shape": "single", "range": 10, "dice_count": 7, "dice_sides": 1, "damage_type": "fire", "save": ""}
	a.slots.assign([0, 0, 0, 0, 0, 0, 0, 0, 0])
	check(cb.cast(a, spell, b).get("error", "") == "no slot", "no slot of that level: no cast")
	check(not cb._offerable(a, spell), "...and the button is not offered")
	a.slots.assign([1, 0, 0, 0, 0, 0, 0, 0, 0])
	cb.cast(a, spell, b)
	check(a.slots[0] == 0 and b.hp == 93, "a 1st-level cast spends a 1st-level slot; 7d1 with no save is 7")
	# save for half rounds down; no half means nothing
	b.hp = 100; b.saves["con"] = 100
	var sv := {"save": "con", "half_on_save": true, "damage_type": "fire", "label": "x"}
	cb._spell_hit(b, sv, "7d1", 10)
	check(b.hp == 97, "a made save halves 7 to 3 (round down)")
	cb._spell_hit(b, {"save": "con", "damage_type": "fire", "label": "x"}, "7d1", 10)
	check(b.hp == 97, "a made save against a no-half spell is zero")
	b.saves["con"] = 0
	# an area never touches its caster, does touch allies, and `spare_allies` spares them
	var ally = _guy("ally", "party", Vector2i(2, 1))
	var dbl = _guy("dbl", "party", Vector2i(3, 2)); dbl.statuses["illusion"] = {"no_attack": true}
	cb.combatants.append(ally); cb.combatants.append(dbl)
	var area := spell.duplicate(); area["targeting"] = "hex"; area["slot_level"] = 0
	cb.cast(a, area, a.pos)
	check(a.hp == 100 and ally.hp == 93, "an area aimed on your own hex hurts the ally beside you and never you")
	cb.cast(a, area, dbl.pos)
	check(dbl.hp == 93, "an illusion cannot be targeted but an area still catches it")
	area["spare_allies"] = true
	cb.cast(a, area, ally.pos)
	check(ally.hp == 93, "Spirit Guardians' shape spares the caster's side")
	area.erase("spare_allies"); b.hp = 100
	cb.cast(a, area, b.pos)
	check(b.hp == 93, "...and hits the enemy in it")
	# spell attacks: nat 1 misses, nat 20 crits and doubles the dice
	var ray := spell.duplicate(); ray["slot_level"] = 0; ray["attack_bonus"] = 100
	b.hp = 100; b.ac = 12
	cb.rng = _rolls([1]); cb.cast(a, ray, b)
	check(b.hp == 100, "a spell attack's nat 1 misses at +100")
	cb.rng = _rolls([20]); cb.cast(a, ray, b)
	check(b.hp == 86, "a spell attack's nat 20 crits: 7d1 becomes 14")
	# line of sight gates targeting
	var wall := _board()
	wall["hexes"] = wall["hexes"].filter(func(h): return not (h.x == 5 and h.y != 4))
	var g := _fight(wall); var gb = g[0]; var ga = g[1]; var gk = g[2]
	ga.pos = Vector2i(3, 1); gk.pos = Vector2i(7, 1)
	check(not gb.legal_target(ga, spell, gk), "a wall between caster and target blocks the spell")
	gk.pos = Vector2i(7, 4)
	check(not gb.legal_target(ga, spell, gk) or gb.has_line_of_sight(ga.pos, gk.pos), "...and around the corner is a matter of the line")
	# hand-picked targets for an upcast Hold Person: the player's list is the list
	var m := _fight(); var mb = m[0]; var ma = m[1]; var mk = m[2]
	var m2 = _guy("m2", "foe", Vector2i(3, 2)); var m3 = _guy("m3", "foe", Vector2i(2, 2))
	mb.combatants.append(m2); mb.combatants.append(m3)
	var multi := spell.duplicate(); multi["slot_level"] = 0; multi["targets"] = 2
	mb.cast(ma, multi, [mk, m3])
	check(mk.hp == 93 and m3.hp == 93 and m2.hp == 100, "an Array of targets hits exactly those")
	mb.cast(ma, multi, [mk])
	check(mk.hp == 86 and m2.hp == 100 and m3.hp == 93, "one picked target means one, no auto-fill")
	mb.cast(ma, multi, mk)
	check(mk.hp == 79 and (m2.hp == 93 or m3.hp == 86), "a bare Combatant still auto-fills the rest (the AI's path)")

# The five spells the export lacked, added 2026-09-19.
func test_new_spells() -> void:
	var sheet5 = Presets.ilsa(5).sheet()
	var mm := Effects.spell_verbs_for(Presets.ilsa().sheet(), ["magic-missile"])
	check(mm.size() == 2 and int(mm[0]["dice_count"]) == 3 and int(mm[0]["dice_sides"]) == 4 and int(mm[0]["dice_bonus"]) == 3,
		"Magic Missile: three darts, 3d4+3 force, no roll")
	check(int(mm[1]["dice_count"]) == 4 and int(mm[1]["dice_bonus"]) == 4 and mm[1]["id"] == "magic-missile@2", "...one more dart per slot level")
	check(mm[0].get("save", "") == "" and not mm[0].has("attack_bonus"), "...no save, no attack roll")
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	a.slots.assign([2, 0, 0, 0, 0, 0, 0, 0, 0])
	var dart: Dictionary = mm[0].duplicate(); dart["range"] = 20; dart["dice_sides"] = 1
	cb.cast(a, dart, b)
	check(b.hp == 94, "3d1+3 lands for 6 with nothing to roll against")
	var hw := Effects.spell_verbs_for(Presets.ilsa().sheet(), ["healing-word"])
	check(hw[0]["cost"] == "bonus" and int(hw[0]["heal_count"]) == 2 and int(hw[0]["heal_sides"]) == 4
		and int(hw[0]["heal_bonus"]) == Presets.ilsa().sheet().mod("wis") and int(hw[0]["range_ft"]) == 60,
		"Healing Word: bonus action, 2d4 + WIS, 60 ft (2024)")
	check(int(hw[1]["heal_count"]) == 4, "...+2d4 per slot level")
	var eb := Effects.spell_verbs_for(Presets.ilsa().sheet(), ["eldritch-blast"])
	check(eb.size() == 1 and int(eb[0]["rays"]) == 1 and int(eb[0]["dice_count"]) == 1 and int(eb[0]["dice_sides"]) == 10
		and eb[0].has("attack_bonus"), "Eldritch Blast: one beam of 1d10, a ranged spell attack")
	check(int(Effects.spell_verbs_for(sheet5, ["eldritch-blast"])[0]["rays"]) == 2, "...two beams at character level 5")
	check(int(Effects.spell_verbs_for(Presets.ilsa(11).sheet(), ["eldritch-blast"])[0]["rays"]) == 3, "...three at 11")
	check(int(Effects.spell_verbs_for(Presets.ilsa(11).sheet(), ["eldritch-blast"])[0]["dice_count"]) == 1, "...and the die never grows")
	var vm := Effects.spell_verbs_for(sheet5, ["vicious-mockery"])
	check(vm[0]["save"] == "wis" and int(vm[0]["dice_count"]) == 2 and "sapped" in vm[0]["conditions"],
		"Vicious Mockery: WIS save, 2d6 psychic at 5, disadvantage on the next attack")
	b.saves["wis"] = -100
	var mock: Dictionary = vm[0].duplicate(); mock["range"] = 20
	cb.begin_turn_for(a)
	cb.cast(a, mock, b)
	check(b.has("sapped") and cb._attack_mode(b, a) == Dice.DIS, "...the target swings its next at disadvantage")
	# Shield: a reaction that turns the blow that would have hit, and holds +5 until your next turn
	var sh := Effects.spell_verbs_for(Presets.ilsa().sheet(), ["shield"])
	check(sh.size() == 1 and sh[0]["cost"] == "reaction" and sh[0]["trigger"] == "would_be_hit" and int(sh[0]["ac_bonus"]) == 5,
		"Shield: a reaction to a blow that would hit, +5 AC")
	var g := _fight(); var gb = g[0]; var ga = g[1]; var gk = g[2]
	ga.verbs = sh.duplicate(true); ga.slots.assign([1, 0, 0, 0, 0, 0, 0, 0, 0]); ga.ac = 12
	check(not gb.available(ga).any(func(x): return x["id"] == "shield"), "never a button")
	gb.rng = _rolls([10])   # 10 + 5 = 15 vs 12: a hit, unless shielded
	var r = gb.resolve_attack(gk, ga)
	check(not r["hit"] and ga.slots[0] == 0 and ga.econ["reaction"] == 0, "the blow misses; the slot and the reaction are spent")
	check(gb.effective_ac(ga) == 17, "...and the +5 stays up")
	gb.begin_turn_for(gk); gb.rng = _rolls([10])
	check(not gb.resolve_attack(gk, ga)["hit"], "a second swing that round faces AC 17")
	gb.turn_idx += 1   # the clock moves on to the caster's own turn
	gb.begin_turn_for(ga)
	check(gb.effective_ac(ga) == 12, "gone at the start of the caster's next turn")
	gb.begin_turn_for(gk); gb.rng = _rolls([10])
	check(gb.resolve_attack(gk, ga)["hit"], "no slot left: the same swing lands")
	var h := _fight(); var hb = h[0]; var ha = h[1]; var hk = h[2]
	ha.verbs = sh.duplicate(true); ha.slots.assign([1, 0, 0, 0, 0, 0, 0, 0, 0]); ha.ac = 12
	hk.ranged = true; hk.atk_range = 6; hk.pos = Vector2i(7, 1)
	hb.rng = _rolls([10])
	check(not hb.resolve_attack(hk, ha)["hit"] and ha.slots[0] == 0, "Shield answers an arrow as well as a blade")
	hk.ranged = false; hk.pos = Vector2i(3, 1)
	ha.verbs = [{"id": "parry", "kind": "reaction", "cost": "reaction", "trigger": "would_be_hit", "ac_bonus": 3, "melee_only": true, "label": "Parry"}]
	hb.begin_turn_for(ha); hb.begin_turn_for(hk)
	ha.statuses.erase("spell:shield")   # the +5 from the cast above
	hk.ranged = true; hk.atk_range = 6; hk.pos = Vector2i(7, 1)
	hb.rng = _rolls([10])
	check(hb.resolve_attack(hk, ha)["hit"] and ha.econ["reaction"] == 1, "...while Parry, melee-only, lets the arrow through")

# --- 14. riders --------------------------------------------------------------

func test_riders_and_extras() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.ac = -50; b.max_hp = 1000; b.hp = 1000
	a.verbs = [{"id": "sa", "kind": "passive_damage", "trigger": "on_weapon_hit", "once_per": "turn", "label": "Sneak",
		"dice_count": 1, "dice_sides": 1, "requires": []},
		{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	cb.begin_turn_for(a)
	cb.rng = _rolls([10])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == 1, "a passive rider adds its dice to a hit")
	cb.rng = _rolls([10])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == -1, "...once per turn: the second swing gets none")
	cb.begin_turn_for(a)
	cb.rng = _rolls([20])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == 2, "next turn it is back, and a crit doubles the rider's dice too (RAW)")
	a.verbs[0]["requires"] = ["not_disadvantage"]
	cb.begin_turn_for(a); a.statuses["poisoned"] = true
	cb.rng = _rolls([15, 15])
	var r = cb.resolve_attack(a, b)
	check(r["hit"] and _extra(r, "Sneak") == -1, "Sneak Attack's 'not at disadvantage' clause holds even when the blow lands")
	a.statuses.erase("poisoned")
	a.verbs[0]["requires"] = ["advantage_or_ally_adjacent"]
	cb.begin_turn_for(a)
	cb.rng = _rolls([15])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == -1, "no advantage, no adjacent ally: no Sneak Attack")
	var ally = _guy("ally", "party", Vector2i(4, 1)); cb.combatants.append(ally)
	cb.begin_turn_for(a)
	cb.rng = _rolls([15])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == 1, "an ally adjacent to the target unlocks it")
	ally.pos = Vector2i(0, 4)
	cb.begin_turn_for(a); a.statuses["hidden"] = true
	cb.rng = _rolls([15, 15])
	check(_extra(cb.resolve_attack(a, b), "Sneak") == 1, "...so does advantage")
	a.statuses.clear()
	# a one-shot buff (Divine Smite) rides one blow; a standing one (Rage) rides all
	a.verbs = [{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	cb.begin_turn_for(a)
	a.statuses["divine-smite"] = {"once": true, "dice_count": 2, "dice_sides": 1}
	a.statuses["raging"] = {"bonus_damage": 2}
	cb.rng = _rolls([10])
	r = cb.resolve_attack(a, b)
	check(_extra(r, "divine-smite") == 2 and _extra(r, "raging") == 2, "both ride the first blow")
	cb.rng = _rolls([10])
	r = cb.resolve_attack(a, b)
	check(_extra(r, "divine-smite") == -1 and _extra(r, "raging") == 2, "only the standing one rides the second")
	cb.begin_turn_for(a)
	a.statuses["divine-smite"] = {"once": true, "dice_count": 2, "dice_sides": 1}
	cb.rng = _rolls([20])
	r = cb.resolve_attack(a, b)
	check(_extra(r, "divine-smite") == 4, "a critical hit doubles the Smite's dice too (2d1 -> 4)")
	a.statuses.clear()
	# Stunning Strike (2024): on a hit, a Focus Point, once a turn, CON save or Stunned
	a.verbs = [{"id": "ss", "kind": "save_effect", "cost": "none", "trigger": "on_weapon_hit", "pool": "focus-points",
		"once_per": "turn", "save": "con", "conditions": ["stunned"], "duration": "round", "label": "Stunning Strike",
		"on_save_vex": true, "targeting": "enemy"},
		{"id": "ea", "kind": "attacks_per_action", "value": 2}]
	a.pools["focus-points"] = {"cur": 2, "max": 2, "regen": "short-rest"}
	a.save_dc = 13
	check(not cb.all_verbs(a).any(func(x): return x["id"] == "ss"), "Stunning Strike is not a button")
	b.saves["con"] = -100
	cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(b.has("stunned") and a.pool_left("focus-points") == 1, "it rides the hit: a Focus Point spent, the target Stunned")
	cb.rng = _rolls([10, 10]); cb.resolve_attack(a, b)
	check(a.pool_left("focus-points") == 1, "once per turn: the second hit spends nothing")
	cb.round_num += 1; cb.begin_turn_for(b); b.saves["con"] = 100
	cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(not b.has("stunned") and a.pool_left("focus-points") == 0, "next turn, a made save: the point is spent, no stun")
	check(a.statuses.get("vex", {}).get("target") == b, "...but the monk has advantage on the next swing against it (2024)")
	cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	check(a.pool_left("focus-points") == 0, "no Focus Points left: nothing fires")
	a.verbs = []; a.pools.clear()

# --- 15. what lasts how long -------------------------------------------------

func test_status_lifetimes() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	# a mastery status set on the foe's turn survives to bite on the victim's own turn
	cb.turn_idx = 0; cb.round_num = 1
	b.statuses["sapped"] = {"until_tick": cb._next_round_tick()}
	cb.round_num = 2
	cb.begin_turn_for(b)
	check(b.has("sapped"), "Sap lands at the end of the attacker's turn and is still there when the victim acts")
	cb.round_num = 3
	cb.begin_turn_for(b)
	check(not b.has("sapped"), "...and is gone a round later")
	# a buff with `rounds` runs on the fight clock
	cb.round_num = 1
	cb._apply_buff(a, b, {"buff": {"ac": 2}, "rounds": 2, "spell": "sof", "id": "sof"})
	check(cb.effective_ac(b) == 14, "the buff is on")
	cb.round_num = 3
	cb.begin_turn_for(b)
	check(cb.effective_ac(b) == 14, "still on inside its rounds")
	cb.round_num = 4
	cb.begin_turn_for(b)
	check(cb.effective_ac(b) == 12, "off once its rounds are up")
	# concentration lapses at the caster's turn once the minute is over
	a.statuses["concentrating"] = {"spell": "bless", "until_round": 5}
	cb.round_num = 4; cb.begin_turn_for(a)
	check(a.has("concentrating"), "held until the round it expires on")
	cb.round_num = 5; cb.begin_turn_for(a)
	check(not a.has("concentrating"), "...and let go at the caster's turn that round")
	# 'encounter'-duration conditions and buffs never lapse on their own
	cb.apply_condition(b, "frightened", a, "encounter")
	cb.round_num = 30; cb.begin_turn_for(b)
	check(b.has("frightened"), "an encounter-long condition outlasts every round")

# Rage (2024): until the end of your next turn unless you attacked or forced a
# save that turn; ten rounds at most; over at once if Incapacitated.
func test_rage_clock() -> void:
	var f := _fight(); var cb = f[0]; var a = f[1]; var b = f[2]
	b.max_hp = 1000; b.hp = 1000; b.ac = -50
	var rage := {"id": "barbarian-rage", "kind": "self_buff", "cost": "bonus", "label": "Rage", "status": "raging",
		"duration": "rage", "bonus_damage": 2, "resist": ["slashing"]}
	cb.round_num = 1
	cb.perform(a, rage)
	check(a.has("raging") and a.statuses["raging"]["started_round"] == 1, "Rage is up, and dated")
	cb._rage_upkeep(a)
	check(a.has("raging"), "the turn it started on does not end it")
	cb.round_num = 2; cb.begin_turn_for(a)
	cb._rage_upkeep(a)
	check(not a.has("raging"), "a turn with no attack and no save forced: the rage subsides")
	cb.begin_turn_for(a); cb.perform(a, rage)
	cb.round_num = 3; cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	cb._rage_upkeep(a)
	check(a.has("raging"), "an attack roll that turn keeps it going")
	cb.round_num = 4; cb.begin_turn_for(a)
	cb._save_effect(a, {"save": "con", "label": "Roar", "conditions": []}, b)
	cb._rage_upkeep(a)
	check(a.has("raging"), "so does forcing a save")
	cb.round_num = 13; cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b)
	cb._rage_upkeep(a)
	check(not a.has("raging"), "ten rounds is the ceiling, fighting or not")
	cb.begin_turn_for(a); cb.perform(a, rage)
	a.statuses["stunned"] = true
	cb.begin_turn_for(a)
	check(not a.has("raging"), "Incapacitated ends it at once")
	a.statuses.clear()
	# an opportunity attack on someone else's turn counts as fighting
	cb.round_num = 20; cb.begin_turn_for(a); cb.perform(a, rage)
	cb.round_num = 21; cb.begin_turn_for(b); cb.begin_turn_for(a)
	cb.rng = _rolls([10]); cb.resolve_attack(a, b, {"opportunity": true})
	cb._rage_upkeep(a)
	check(a.has("raging"), "any attack roll counts, an opportunity attack included")

# 2024 surprise: disadvantage on the surprised side's initiative, no lost round.
func test_surprise_initiative() -> void:
	var a = _guy("a", "party", Vector2i(0, 0)); var b = _guy("b", "foe", Vector2i(3, 0)); var c = _guy("c", "foe", Vector2i(5, 0))
	var cb = Combat.new(RNG.new(3), [a, b, c], _board())
	var before: Array = [b.init_roll, c.init_roll]
	cb.begin_surprise_round()
	check(cb.unseen and cb.turn_idx == 0 and cb.log[-1].begins_with("Initiative, re-rolled"), "the surprised side re-rolls and the order restarts")
	var sorted := true
	for i in cb.order.size() - 1:
		if cb.order[i].init_roll < cb.order[i + 1].init_roll:
			sorted = false
	check(sorted, "...into a sorted order")
	var worse := 0
	for s in range(1, 41):
		var x = _guy("x", "party", Vector2i(0, 0)); var y = _guy("y", "foe", Vector2i(3, 0))
		var k = Combat.new(RNG.new(s), [x, y], _board())
		var plain: int = y.init_roll
		k.begin_surprise_round()
		if y.init_roll <= plain:
			worse += 1
	check(worse > 20, "over 40 seeds the surprised roll is mostly no better (%d of 40)" % worse)
	# advantage on initiative (Assassinate) is the same die, the other way
	var p = _guy("p", "party", Vector2i(0, 0)); p.init_adv = true
	var q = _guy("q", "foe", Vector2i(3, 0))
	var cb2 = Combat.new(_rolls([3, 18, 9]), [p, q], _board())
	check(p.init_roll == 18 and q.init_roll == 9, "an assassin rolls two dice for initiative and keeps the 18")

# --- the questions -------------------------------------------------------------

func report() -> void:
	if _notes.is_empty():
		return
	print("\n--- questions: places the engine and the printed rules disagree, and the repo does not say which was meant ---")
	for n in _notes:
		print("  ", n)
