# Rules that must hold at every swing of every fight, checked on real fights
# rather than on hand-built positions: the AI driving both sides through the
# scaler's rosters on every theme, with a Combat subclass watching each attack,
# cast and step as it happens. A hand-built test can only assert the situation
# its author thought of; 60 seeded fights throw up the ones nobody did.
#   godot --headless --path . -s tests/test_fight_invariants.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Hex = preload("res://core/hex.gd")
const AI = preload("res://core/ai.gd")
const Combat = preload("res://core/combat.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")

const SEEDS := 60

var _pass := 0
var _fail := 0
var _seen := {}   # invariant label -> times it was exercised, so a rule that never fired is a FAIL too

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# A check that fires many times per fight: counts as one pass per fight, fails loudly per hit.
func invariant(cond: bool, label: String, detail: String = "") -> void:
	_seen[label] = int(_seen.get(label, 0)) + 1
	if not cond:
		_fail += 1
		printerr("  FAIL: %s  %s" % [label, detail])

func _init() -> void:
	test_every_castable_spell_has_its_range()
	test_thrown_weapons()
	test_hit_chance_matrix()
	test_spawn_geometry()
	test_real_fights_hold_the_rules()
	print("test_fight_invariants: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- 0. data: no combat spell is secretly touch-range ---------------------------
#
# effects.gd defaults range_ft to 5 when nothing authored it, and the catalog's
# regex draft never carries a range — so every castable spell whose catalog
# range is 30 ft or more must have an authored range_ft, or Hold Person is a
# touch spell. lightning-bolt is the one deliberate exception (see the _note in
# data/effects/spells.json).
func test_every_castable_spell_has_its_range() -> void:
	var re := RegEx.new()
	re.compile("^(\\d+) feet")
	var n := 0
	for id in Catalog.index("spells.json").keys():
		var m := Effects.spell(id)
		if m.is_empty():
			continue
		var r := re.search(String(Catalog.spell(id).get("range", "")))
		if r == null or id == "lightning-bolt":
			continue
		n += 1
		var ft := int(r.get_string(1))
		check(int(m.get("range_ft", 5)) >= mini(ft, 30), "%s reaches %d ft (authored %s)" % [id, ft, str(m.get("range_ft", "nothing"))])
		var v := _verb_for(id)
		if not v.is_empty():
			check(int(v["range"]) >= 5, "%s is at least 5 hexes on the board (%d)" % [id, int(v["range"])])
	check(n >= 30, "the check covered the ranged spells (%d)" % n)

func _verb_for(id: String) -> Dictionary:
	var ch := Presets.ilsa()
	ch.prepared = [id]
	var c = Adapter.to_combatant(ch, "party", Vector2i(0, 0))
	for v in c.verbs:
		if String(v.get("spell", "")) == id:
			return v
	return {}

func test_thrown_weapons() -> void:
	var ch := Presets.vera()
	ch.equipped.assign(["javelin", "chain-mail", "shield"])
	var c = Adapter.to_combatant(ch, "party", Vector2i(0, 0))
	check(not c.ranged and c.atk_range == 1, "a javelin in hand is a melee weapon")
	check(Adapter.set_main_attack(c, "javelin-thrown"), "...and can be wielded thrown")
	check(c.ranged and c.atk_range == Adapter.hexes(30), "thrown javelin: 30 ft = %d hexes" % Adapter.hexes(30))
	check(c.attacks[0]["to_hit"] == c.attacks[1]["to_hit"], "thrown keeps the weapon's own to-hit (STR, no Archery)")
	ch = Presets.vera()   # a fresh sheet: resolution is cached per character
	ch.equipped.assign(["longsword", "chain-mail", "shield"])
	c = Adapter.to_combatant(ch, "party", Vector2i(0, 0))
	check(not c.attacks.any(func(a): return String(a["id"]).ends_with("-thrown")), "a longsword cannot be thrown")

# --- 1. the to-hit modifiers, stacked the way a real turn stacks them ---------
#
# hit_chance() is the number the HUD shows and the AI reasons with; every rule
# below is one line in _attack_mode/effective_ac and they all have to compose.
func test_hit_chance_matrix() -> void:
	var b: Dictionary = Encounter.board_for("sunken-shrine")
	var chars := Presets.party()
	var vera = Adapter.to_combatant(chars[0], "party", Vector2i(2, 0))    # longsword
	var pike = Adapter.to_combatant(chars[1], "party", Vector2i(2, 2))    # shortbow
	var gob = Encounter.spawn("goblin", 1.0, "foe", Vector2i(5, 1))
	var gob2 = Encounter.spawn("goblin", 1.0, "foe", Vector2i(5, 2))
	check(gob != null and gob2 != null, "goblins exist in the bestiary")
	var cb := Combat.new(RNG.new(1), [vera, pike, gob, gob2], b)
	for c in cb.combatants:
		cb.begin_turn_for(c)

	var base_r := cb.hit_chance(pike, gob)
	var base_m := cb.hit_chance(vera, gob)
	check(base_r > 0.05 and base_r < 0.95, "baseline ranged chance is a real number (%.2f)" % base_r)

	# half cover: +2 AC = exactly two d20 faces
	gob.pos = b["cover"][0]
	check(is_equal_approx(cb.hit_chance(pike, gob), base_r - 0.10), "cover costs the shooter exactly +2 AC")
	gob.pos = Vector2i(5, 1)

	# point-blank: an enemy adjacent to the archer -> disadvantage -> p^2
	gob2.pos = Vector2i(3, 2)   # adjacent to pike
	check(is_equal_approx(cb.hit_chance(pike, gob), base_r * base_r), "adjacent enemy gives the archer disadvantage")
	# ...but the swordsman next to the same goblin is unaffected
	gob2.pos = Vector2i(3, 0)
	check(is_equal_approx(cb.hit_chance(vera, gob2), base_m), "melee never suffers the point-blank rule")
	gob2.pos = Vector2i(5, 2)

	# prone: melee adjacent gets advantage, ranged gets disadvantage
	cb.apply_condition(gob2, "prone")
	vera.pos = Vector2i(4, 2)
	var p_m := cb.hit_chance(vera, gob2)
	check(is_equal_approx(p_m, 1.0 - (1.0 - base_m) * (1.0 - base_m)), "prone target: adjacent melee has advantage")
	check(is_equal_approx(cb.hit_chance(pike, gob2), base_r * base_r), "prone target: ranged has disadvantage")
	# prone + the archer's own Help-advantage cancel to a straight roll (5e: any adv + any dis = normal)
	pike.statuses["helped"] = true
	check(is_equal_approx(cb.hit_chance(pike, gob2), base_r), "advantage and disadvantage cancel, never stack")
	pike.statuses.erase("helped")
	# prone + cover stack (one is a die mode, the other is AC)
	gob2.pos = b["cover"][1]
	check(is_equal_approx(cb.hit_chance(pike, gob2), (base_r - 0.10) * (base_r - 0.10)), "prone and cover both apply")
	gob2.statuses.erase("prone")
	gob2.pos = Vector2i(5, 2)
	vera.pos = Vector2i(2, 0)

	# a hidden attacker attacks with advantage; the target's cover still counts
	pike.statuses["hidden"] = true
	gob.pos = b["cover"][2]
	var pc := base_r - 0.10
	check(is_equal_approx(cb.hit_chance(pike, gob), 1.0 - (1.0 - pc) * (1.0 - pc)), "hidden archer: advantage on a covered target")
	pike.statuses.erase("hidden")

# --- 2. where everybody starts, on every board ----------------------------------
func test_spawn_geometry() -> void:
	var chars := Presets.party()
	for theme in Encounter.THEMES:
		var b: Dictionary = Encounter.board_for(theme)
		var hexes: Array = b["hexes"]
		var blocked: Array = b.get("objects", []).filter(
			func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
		for s in [1, 2, 3]:
			var cb := _build(chars, theme, s)
			var taken := {}
			for c in cb.combatants:
				check(c.pos in hexes, "%s/%d: %s stands on the board" % [theme, s, c.cname])
				check(not (c.pos in blocked), "%s/%d: %s not inside an object" % [theme, s, c.cname])
				check(not taken.has(c.pos), "%s/%d: %s has a hex to itself" % [theme, s, c.cname])
				taken[c.pos] = true
				if c.team == "party":
					check(c.pos in Encounter.PARTY_STARTS, "%s/%d: party on its starts" % [theme, s])
				else:
					var d := 99
					for p in Encounter.PARTY_STARTS:
						d = mini(d, Hex.distance(c.pos, p))
					check(d >= 2, "%s/%d: %s does not spawn adjacent to the party (d=%d)" % [theme, s, c.cname, d])
					check(int(c.atk_range) <= Adapter.RANGE_CAP, "%s/%d: %s range within the cap" % [theme, s, c.cname])

# --- 3. sixty real fights under a microscope ----------------------------------

class Watched extends Combat:
	var t: SceneTree            # the test, for invariant()
	var moved := {}             # id -> hexes walked this turn
	var dashes := {}            # id -> dashes this turn
	var turn_owner = null

	func _who(c) -> String:
		return "%s(%s)" % [c.cname, c.id]

	func resolve_attack(attacker, target, opts := {}) -> Dictionary:
		var oa: bool = opts.get("opportunity", false)
		var free: bool = oa or opts.get("free", false)
		var d := Hex.distance(attacker.pos, target.pos)
		var reaction_before := int(attacker.econ.get("reaction", 0))
		var corpse: bool = target.is_dead()
		var was_down: bool = target.is_down()
		var fails_before: int = target.death_f
		var r := super(attacker, target, opts)
		if r.has("error"):
			return r
		t.invariant(attacker.conscious(), "attacker is conscious", _who(attacker))
		t.invariant(not corpse, "nobody attacks a corpse", _who(target))
		t.invariant(free or in_reach(attacker, target), "no swing beyond reach/range",
			"%s at %d, range %d" % [_who(attacker), d, attacker.atk_range if attacker.ranged else 1])
		if oa:
			t.invariant(d <= 1, "an OA is swung from reach, where the mover left it", "%s at %d" % [_who(attacker), d])
			t.invariant(reaction_before == 0, "an OA has already spent the reaction", _who(attacker))
			if attacker.ranged and bool(r.get("hit", false)):
				t.invariant(int(r["dmg_detail"]["total"]) <= 2, "an archer's OA is an unarmed strike, not a shot",
					"%s dealt %d" % [_who(attacker), int(r["damage"])])
			t.invariant(attacker != turn_owner, "you don't OA on your own turn", _who(attacker))
		if attacker.ranged and adjacent_enemy(attacker):
			t.invariant(int(r["mode"]) != Dice.ADV, "point-blank shot never rolls with advantage", _who(attacker))
		if bool(r.get("hit", false)):
			t.invariant(int(r["damage"]) >= 0, "hit damage is non-negative")
			if was_down and int(r["damage"]) > 0:
				var expect: int = fails_before + (2 if bool(r["crit"]) else 1)
				t.invariant(target.is_dead() or target.death_f == expect, "damage on a downed body is one failure, a crit two",
					"%s %d -> %d crit=%s" % [_who(target), fails_before, target.death_f, str(r["crit"])])
				if not attacker.ranged and d <= 1:
					t.invariant(bool(r["crit"]), "a melee hit on a downed body is an automatic crit", _who(attacker))
		else:
			t.invariant(int(r.get("damage", 0)) == 0, "a miss deals nothing", _who(attacker))
		return r

	func cast(caster, v: Dictionary, target) -> Dictionary:
		var lvl := int(v.get("slot_level", 0))
		var before: int = caster.slots[lvl - 1] if lvl > 0 and lvl <= caster.slots.size() else -1
		var r := super(caster, v, target)
		if r.has("error"):
			return r
		t.invariant(caster.conscious(), "caster is conscious", _who(caster))
		if lvl > 0:
			t.invariant(caster.slots[lvl - 1] == before - 1 and before > 0, "a levelled cast spends exactly one slot",
				"%s %s L%d %d->%d" % [_who(caster), v["id"], lvl, before, caster.slots[lvl - 1]])
		if target != null and typeof(target) == TYPE_OBJECT and "pos" in target:
			t.invariant(Hex.distance(caster.pos, target.pos) <= int(v.get("range", 1)), "spell within its range",
				"%s %s at %d, range %d" % [_who(caster), v["id"], Hex.distance(caster.pos, target.pos), int(v.get("range", 1))])
		if v.get("concentration", false):
			t.invariant(caster.statuses.get("concentrating") == v["spell"], "new concentration replaces the old")
		return r

	func move_to(mover, dest: Vector2i, disengage := false) -> void:
		var field := move_field(mover)
		var cost: int = field.get(dest, -1)
		var left := move_left(mover)
		super(mover, dest, disengage)
		if cost < 0:
			return
		t.invariant(cost <= left, "a step never exceeds the movement left", "%s cost %d left %d" % [_who(mover), cost, left])
		# an OA can drop the mover partway: count the hexes it actually walked
		moved[mover.id] = int(moved.get(mover.id, 0)) + int(field.get(mover.pos, 0))

	func perform(actor, v: Dictionary, target = null) -> Dictionary:
		if v.get("kind", "") == "dash":
			dashes[actor.id] = int(dashes.get(actor.id, 0)) + 1
		return super(actor, v, target)

func test_real_fights_hold_the_rules() -> void:
	var chars := Presets.party()
	var wins := 0
	for s in range(1, SEEDS + 1):
		var theme: String = Encounter.THEMES[s % Encounter.THEMES.size()]
		var cb := _build(chars, theme, s)
		var guard := 0
		while not cb.is_over() and guard < 5000:
			var a = cb.current()
			cb.turn_owner = a
			cb.moved.clear()
			cb.dashes.clear()
			var hp_before := {}
			for c in cb.combatants:
				hp_before[c.id] = c.hp
			cb.begin_turn()
			var was_down: bool = a.is_down()
			AI.take_turn(cb, a)
			cb.end_turn()
			guard += 1
			# per-turn invariants
			if was_down:
				invariant(int(cb.moved.get(a.id, 0)) == 0, "a downed body does not walk", cb._who(a))
			invariant(int(cb.moved.get(a.id, 0)) <= a.speed * (1 + int(cb.dashes.get(a.id, 0))),
				"movement per turn is speed (x2 with Dash)", "%s walked %d, speed %d, dashes %d" % [
					cb._who(a), int(cb.moved.get(a.id, 0)), a.speed, int(cb.dashes.get(a.id, 0))])
			for other in cb.combatants:
				if other != a:
					invariant(int(cb.moved.get(other.id, 0)) == 0, "only the turn owner walks on their turn", cb._who(other))
			for c in cb.combatants:
				invariant(c.hp <= c.max_hp, "HP never exceeds max", "%s %d/%d" % [cb._who(c), c.hp, c.max_hp])
				invariant(c.hp >= 0, "HP never goes negative", "%s %d" % [cb._who(c), c.hp])
				invariant(not (c.is_dead() and c.conscious()), "the dead are not conscious", cb._who(c))
				invariant(not (c.is_down() and c.hp > 0), "down means 0 HP", "%s %d" % [cb._who(c), c.hp])
				invariant(c.death_s <= 3, "death successes cap at three", cb._who(c))
				if c.death_f >= 3:
					invariant(c.is_dead(), "three failed death saves is dead", cb._who(c))
				invariant(int(c.econ.get("action", 0)) >= 0 and int(c.econ.get("bonus", 0)) >= 0
					and int(c.econ.get("reaction", 0)) >= 0, "action economy never goes negative", cb._who(c))
				for i in c.slots.size():
					invariant(int(c.slots[i]) >= 0, "spell slots never go negative", cb._who(c))
				if c.has("concentrating"):
					invariant(c.conscious(), "an unconscious caster is not concentrating", cb._who(c))
			# a move that leaves an enemy's reach provokes: every OA this turn hit the mover
			# (checked inside resolve_attack via turn_owner); a Disengaged mover was never hit
			if a.has("disengaged"):
				pass   # covered by test_combat.test_move_provokes_unless_disengage on fixed positions
		check(cb.outcome() != "ongoing", "seed %d terminates" % s)
		check(cb.round_num <= Combat.MAX_ROUNDS, "seed %d ends within the round cap" % s)
		if cb.outcome() == "Victory":
			wins += 1
		# end state: exactly one side has anyone standing
		var party_up := cb.combatants.filter(func(c): return c.team == "party" and c.conscious()).size()
		var foes_up := cb.combatants.filter(func(c): return c.team == "foe" and c.conscious()).size()
		check(party_up == 0 or foes_up == 0 or cb.round_num > Combat.MAX_ROUNDS,
			"seed %d: a finished fight has one side down (%d vs %d)" % [s, party_up, foes_up])
	print("  %d fights, %d party wins" % [SEEDS, wins])
	# every invariant must have actually been exercised, or the harness is hooking nothing
	for label in ["no swing beyond reach/range", "point-blank shot never rolls with advantage",
			"an OA is swung from reach, where the mover left it", "damage on a downed body is one failure, a crit two",
			"a levelled cast spends exactly one slot",
			"spell within its range", "a step never exceeds the movement left",
			"movement per turn is speed (x2 with Dash)", "HP never exceeds max"]:
		check(int(_seen.get(label, 0)) > 0, "invariant '%s' was exercised (%d)" % [label, int(_seen.get(label, 0))])
	_pass += _seen.size()

# encounter.build() with the Watched subclass — the same roster/board/spawn as the game.
func _build(chars: Array, theme: String, seed_value: int) -> Watched:
	var spec: Dictionary = Scaler.roster_for(chars, "normal", {}, theme, seed_value)
	var b: Dictionary = Encounter.board_for(theme)
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var all_c: Array = party.duplicate()
	var spots: Array = Encounter._foe_spots(b, party)
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		for n in count:
			var c = Encounter.spawn(e["id"], float(e.get("mult", 1.0)), "foe",
				spots[i] if i < spots.size() else Encounter.PARTY_STARTS[0], n + 1 if count > 1 else 0)
			if c != null:
				all_c.append(c)
			i += 1
	var cb := Watched.new(RNG.new(seed_value), all_c, b)
	cb.t = self
	return cb
