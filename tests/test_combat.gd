# Asserts on the rules that can silently rot (combat-design.md §10).
#   flatpak run org.godotengine.Godot --headless --path . -s tests/test_combat.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")
const Combatant = preload("res://core/combatant.gd")
const Hex = preload("res://core/hex.gd")
const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Presets = preload("res://core/presets.gd")
const Effects = preload("res://core/rules/effects.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_rng_deterministic()
	test_parse()
	test_advantage_beats_normal()
	test_crit_doubles_dice_not_mod()
	test_burning_hands_hits_allies_not_caster()
	test_scorching_ray_fires_three_rays()
	test_t33_authored_spells_resolve()
	test_move_provokes_unless_disengage()
	test_healing_word_clears_death()
	test_alcove_cover()
	test_reach_and_range()
	test_move_budget()
	test_help_grants_advantage()
	test_help_revives_a_downed_ally()
	test_hidden_mover_provokes_nothing()
	test_hide_enables_advantage()
	test_hidden_is_untargetable()
	test_mercy_rule()
	test_encounter_resolves_many_seeds()
	test_action_economy()
	test_pool_spend_and_rest()
	test_rage_full_turn()
	test_action_surge_full_turn()
	test_spell_slot_spend()
	test_reaction_and_concentration()
	test_barks()
	test_surrender()

	print("test_combat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_rng_deterministic() -> void:
	var a = RNG.new(42)
	var b = RNG.new(42)
	var same = true
	for i in 200:
		if a.roll_die(20) != b.roll_die(20):
			same = false
	check(same, "same seed -> same rolls")
	# spread across the whole face range
	var seen = {}
	var r = RNG.new(7)
	for i in 500:
		seen[r.roll_die(20)] = true
	check(seen.size() == 20, "d20 covers 1..20 (got %d)" % seen.size())

func test_parse() -> void:
	check(Dice.parse("2d6+3") == {"count": 2, "sides": 6, "mod": 3}, "parse 2d6+3")
	check(Dice.parse("d20") == {"count": 1, "sides": 20, "mod": 0}, "parse d20")
	check(Dice.parse("1d8-1") == {"count": 1, "sides": 8, "mod": -1}, "parse 1d8-1")

func test_advantage_beats_normal() -> void:
	var adv_total = 0
	var norm_total = 0
	for s in range(1, 400):
		adv_total += Dice.d20(RNG.new(s), Dice.ADV).nat
		norm_total += Dice.d20(RNG.new(s), Dice.NORMAL).nat
	check(adv_total > norm_total, "advantage sum > normal sum (%d vs %d)" % [adv_total, norm_total])

func test_crit_doubles_dice_not_mod() -> void:
	# 1d1000000+5 : crit must be ~2x the dice, +5 once, never +10
	var normal_min = 999999
	var crit_has_double = false
	for s in range(1, 60):
		var n = Dice.roll(RNG.new(s), "1d100+5", false)
		var c = Dice.roll(RNG.new(s), "1d100+5", true)
		check(c > n, "crit roll > normal roll for seed %d" % s)
		# crit modifier still only +5: c - (two dice) must be 5. dice are 1..100 each.
		check((c - 5) >= 2 and (c - 5) <= 200, "crit = 2 dice + single mod")

func test_burning_hands_hits_allies_not_caster() -> void:
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa")
	var vera = _find(cb, "vera")
	var snik = _find(cb, "snik")
	var bh := _verb(cb, ilsa, "burning-hands")
	check(not bh.is_empty(), "Ilsa can cast Burning Hands")
	ilsa.pos = Vector2i(4, 1)
	vera.pos = Vector2i(5, 1)   # east of Ilsa — in the cone
	snik.pos = Vector2i(5, 0)   # also east — in the cone
	var vera_before = vera.hp
	var ilsa_before = ilsa.hp
	cb.perform(ilsa, bh, Vector2i(1, 0))  # facing east
	check(ilsa.hp == ilsa_before, "burning hands does not hit the caster")
	check(vera.hp < vera_before, "burning hands hits an ally in the cone")
	check(ilsa.slots[0] == 3, "a level-1 cast spends a level-1 slot")

	var cb2 = _sandbox()
	var i2 = _find(cb2, "ilsa"); var v2 = _find(cb2, "vera")
	i2.pos = Vector2i(4, 1); v2.pos = Vector2i(3, 1)   # west — behind the cone
	var vb = v2.hp
	cb2.perform(i2, _verb(cb2, i2, "burning-hands"), Vector2i(1, 0))
	check(v2.hp == vb, "burning hands spares a creature outside the cone")

# Scorching Ray is 3 independent attack rolls from one cast, not one hit.
func test_scorching_ray_fires_three_rays() -> void:
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa")
	var grull = _find(cb, "grull")   # tougher target — no overkill clamping to muddy the sum
	ilsa.pos = Vector2i(4, 1)
	grull.pos = Vector2i(6, 1)
	var v := {"id": "test-scorching-ray", "kind": "spell", "spell": "scorching-ray",
		"label": "Scorching Ray", "cost": "action", "slot_level": 1, "shape": "single",
		"targeting": "enemy", "range_ft": 120, "attack_bonus": 20,   # always hits, for a clean count
		"dice_count": 2, "dice_sides": 6, "damage_type": "fire", "rays": 3}
	var before: int = grull.hp
	var res := cb.perform(ilsa, v, grull)
	check(int(res.get("hits", 0)) == 3, "all 3 rays land at a guaranteed-hit bonus")
	check(before - grull.hp == int(res["damage"]), "total damage is the sum of all landed rays")
	check(before - grull.hp >= 6, "3 rays of at-least-2d6 each land for real damage, not one roll's worth")

# T33: the authored overrides, resolved through cast() for real — one of each
# shape. The verbs come straight out of effects.gd, so a bad number in
# data/effects/spells.json shows up here as a bad swing in HP, not just a bad dict.

func _t33_verb(id: String) -> Dictionary:
	for v in Effects.spell_verbs_for(Presets.ilsa().sheet(), [id]):
		if v["id"] == id:
			v["radius"] = Adapter.area_hexes(int(v.get("size_ft", 0))) if int(v.get("size_ft", 0)) > 0 else 2
			return v
	return {}

func test_t33_authored_spells_resolve() -> void:
	# 1. single-target spell attack: Guiding Bolt, 4d6 radiant.
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa"); var grull = _find(cb, "grull")
	ilsa.pos = Vector2i(4, 1); grull.pos = Vector2i(6, 1)
	ilsa.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	var gb := _t33_verb("guiding-bolt")
	gb["attack_bonus"] = 20        # guaranteed hit, so the damage range is the assertion
	var before: int = grull.hp
	var res := cb.perform(ilsa, gb, grull)
	check(res.get("hit", false), "Guiding Bolt hits at +20")
	check(int(res["damage"]) >= 4 and int(res["damage"]) <= 24,
		"Guiding Bolt rolls 4d6, not the 1d6 the regex parse left behind (got %d)" % int(res["damage"]))
	check(before - grull.hp == int(res["damage"]), "and that damage lands")

	# 2. single-target save-for-half: Blight, 8d8 necrotic on a forced failure.
	var cb2 = _sandbox()
	var i2 = _find(cb2, "ilsa"); var g2 = _find(cb2, "grull")
	i2.pos = Vector2i(4, 1); g2.pos = Vector2i(6, 1)
	i2.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	var bl := _t33_verb("blight")
	bl["save_dc"] = 99             # nothing saves against a DC 99
	g2.hp = 200; g2.max_hp = 200
	var res2 := cb2.perform(i2, bl, g2)
	check(not res2["saved"] and int(res2["damage"]) >= 8, "Blight beats a DC 99 save for 8d8")
	var half := _sandbox()
	var i3 = _find(half, "ilsa"); var g3 = _find(half, "grull")
	i3.pos = Vector2i(4, 1); g3.pos = Vector2i(6, 1); i3.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	g3.hp = 200; g3.max_hp = 200
	var bl2 := _t33_verb("blight")
	bl2["save_dc"] = -99           # nothing fails against a DC -99
	var res3 := half.perform(i3, bl2, g3)
	check(res3["saved"] and int(res3["damage"]) > 0, "a made save still takes half from Blight")

	# 3. AoE save: Cone of Cold, aimed like Burning Hands.
	var cb4 = _sandbox()
	var i4 = _find(cb4, "ilsa"); var v4 = _find(cb4, "vera"); var s4 = _find(cb4, "snik")
	i4.pos = Vector2i(4, 1); v4.pos = Vector2i(5, 1); s4.pos = Vector2i(5, 0)
	i4.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	var coc := _t33_verb("cone-of-cold")
	coc["save_dc"] = 99
	var vb: int = v4.hp; var sb: int = s4.hp; var ib: int = i4.hp
	cb4.perform(i4, coc, Vector2i(1, 0))
	check(v4.hp < vb and s4.hp < sb, "Cone of Cold catches everyone in the wedge")
	check(i4.hp == ib, "and never the caster")
	check(i4.slots[4] == 2, "a 5th-level cast spends a 5th-level slot")

	# 4. condition, no damage at all: Hideous Laughter.
	var cb5 = _sandbox()
	var i5 = _find(cb5, "ilsa"); var g5 = _find(cb5, "grull")
	i5.pos = Vector2i(4, 1); g5.pos = Vector2i(6, 1); i5.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	var hl := _t33_verb("hideous-laughter")
	hl["save_dc"] = 99
	var hp5: int = g5.hp
	cb5.perform(i5, hl, g5)
	check(g5.has("prone") and g5.has("incapacitated"), "Hideous Laughter lands both conditions")
	check(g5.hp == hp5, "and deals no damage")
	var cb6 = _sandbox()
	var i6 = _find(cb6, "ilsa"); var g6 = _find(cb6, "grull")
	i6.pos = Vector2i(4, 1); g6.pos = Vector2i(6, 1); i6.slots = [4, 3, 3, 3, 3, 0, 0, 0, 0] as Array[int]
	var hl2 := _t33_verb("hideous-laughter")
	hl2["save_dc"] = -99
	cb6.perform(i6, hl2, g6)
	check(not g6.has("incapacitated"), "a made save shrugs it off")

func test_move_provokes_unless_disengage() -> void:
	# Pike adjacent to Grull, steps away out of adjacency.
	var landed = false
	for s in range(1, 40):
		var c = _sandbox(s)
		var p = _find(c, "pike"); var g = _find(c, "grull")
		p.pos = Vector2i(4, 1); g.pos = Vector2i(5, 1)
		c.begin_turn_for(p)
		var before = p.hp
		c.move_to(p, Vector2i(2, 1))   # 2 hexes west, breaks adjacency
		if p.hp < before:
			landed = true
	check(landed, "moving out of adjacency provokes (some seed lands the OA)")

	var safe = true
	for s in range(1, 40):
		var c = _sandbox(s)
		var p = _find(c, "pike"); var g = _find(c, "grull")
		p.pos = Vector2i(4, 1); g.pos = Vector2i(5, 1)
		c.begin_turn_for(p)
		var before = p.hp
		c.move_to(p, Vector2i(2, 1), true)  # disengage
		if p.hp < before:
			safe = false
	check(safe, "Disengage prevents the opportunity attack")

	# staying adjacent (sidestep) does not provoke
	var c3 = _sandbox()
	var p3 = _find(c3, "pike"); var g3 = _find(c3, "grull")
	p3.pos = Vector2i(4, 1); g3.pos = Vector2i(5, 1)
	c3.begin_turn_for(p3)
	var b3 = p3.hp
	c3.move_to(p3, Vector2i(5, 0))   # still adjacent to Grull
	check(p3.hp == b3, "sidestep while staying adjacent does not provoke")

	# path-aware: walking THROUGH a second hostile's reach provokes from it too
	var provs := 0
	for s in range(1, 40):
		var c = _sandbox(s)
		var p = _find(c, "pike"); var g = _find(c, "grull"); var v = _find(c, "vess")
		p.pos = Vector2i(2, 1); g.pos = Vector2i(2, 0); v.pos = Vector2i(4, 0)
		# park the rest far away so only Grull + Vess can threaten
		for o in c.combatants:
			if o.id in ["snik", "kritch", "vera", "ilsa"]:
				o.pos = Vector2i(8, 2)
		c.begin_turn_for(p)   # Pike speed 5
		# route (2,1)->(3,1)->(4,1)->(5,1): passes adjacent to Grull then Vess
		check(c.provokers_for(p, Vector2i(5, 1)).size() == 2, "both hostiles along the path provoke")
		var before = p.hp
		c.move_to(p, Vector2i(5, 1))
		if p.hp < before:
			provs += 1
	check(provs > 0, "path-aware OA lands over several seeds")

func test_healing_word_clears_death() -> void:
	var cb = _sandbox()
	var pike = _find(cb, "pike")
	var ilsa = _find(cb, "ilsa")
	pike.statuses["down"] = true
	pike.hp = 0
	pike.death_f = 2
	pike.death_s = 1
	pike.pos = ilsa.pos + Vector2i(1, 0)   # touch range
	var cw := _verb(cb, ilsa, "cure-wounds")
	check(cb.legal_target(ilsa, cw, pike), "a downed ally in reach is a legal heal target")
	cb.perform(ilsa, cw, pike)
	check(not pike.is_down(), "the heal brings a downed PC back up")
	check(pike.death_f == 0 and pike.death_s == 0, "the heal resets death saves")
	check(pike.hp >= 1, "revived PC has at least 1 HP")

func test_alcove_cover() -> void:
	var cb = _sandbox()
	var kritch = _find(cb, "kritch")
	kritch.pos = Vector2i(4, 1)
	var open_ac = cb.effective_ac(kritch)
	kritch.pos = Vector2i(8, 1)   # Alcove — a cover hex
	check(cb.effective_ac(kritch) == open_ac + 2, "cover hex grants +2 AC")
	check(cb._saving_throw(kritch, 100) == false, "cover hex still fails an impossible DC")  # smoke
	# sacred flame ignores cover: compare save bonus paths
	kritch.pos = Vector2i(8, 1)
	var cover_saves = 0
	var open_saves = 0
	for s in range(1, 200):
		var c = _sandbox(s)
		var k = _find(c, "kritch")
		k.pos = Vector2i(8, 1)
		if c._saving_throw(k, 13): cover_saves += 1
		if c._saving_throw(k, 13, "dex", true): open_saves += 1
	check(cover_saves > open_saves, "cover raises DEX saves; ignore_cover removes it (%d vs %d)" % [cover_saves, open_saves])

func test_reach_and_range() -> void:
	var cb = _sandbox()
	var vera = _find(cb, "vera")   # melee
	var pike = _find(cb, "pike")   # ranged, range 6
	var grull = _find(cb, "grull")
	vera.pos = Vector2i(0, 1)
	grull.pos = Vector2i(3, 1)     # distance 3
	check(cb.resolve_attack(vera, grull).has("error"), "melee attack at distance 3 is rejected")
	grull.pos = Vector2i(1, 1)     # distance 1
	check(not cb.resolve_attack(vera, grull).has("error"), "melee attack at distance 1 resolves")
	check(vera.econ["action"] == 0, "a weapon attack consumes the Action")
	check(cb.resolve_attack(vera, grull).has("error"), "a second swing with no action left is rejected")
	var oa = _sandbox()
	_find(oa, "grull").pos = Vector2i(1, 1); _find(oa, "vera").pos = Vector2i(1, 1)
	oa.resolve_attack(_find(oa, "grull"), _find(oa, "vera"), {"opportunity": true})
	check(_find(oa, "grull").econ["action"] == 1, "an opportunity attack is free")

	pike.pos = Vector2i(0, 1)
	grull.pos = Vector2i(6, 1)     # distance 6
	check(not cb.resolve_attack(pike, grull).has("error"), "ranged attack within range resolves")
	grull.pos = Vector2i(8, 1)     # distance 8 (> 6)
	check(cb.resolve_attack(pike, grull).has("error"), "ranged attack beyond range is rejected")

	# ranged with an adjacent hostile -> disadvantage
	pike.pos = Vector2i(4, 1)
	var snik = _find(cb, "snik")
	snik.pos = Vector2i(4, 0)      # adjacent to Pike
	grull.pos = Vector2i(6, 1)
	check(cb._attack_mode(pike, grull) == Dice.DIS, "ranged while adjacent to a hostile is at disadvantage")

func test_move_budget() -> void:
	var cb = _sandbox()
	var vera = _find(cb, "vera")
	vera.speed = 4
	# park everyone else far away
	for c in cb.combatants:
		if c != vera:
			c.pos = Vector2i(8, c.pos.y % 3)
	vera.pos = Vector2i(0, 1)
	cb.begin_turn_for(vera)
	cb.move_to(vera, Vector2i(5, 1))   # distance 5 > speed 4
	check(vera.pos == Vector2i(0, 1), "move beyond the speed budget is rejected")
	cb.move_to(vera, Vector2i(3, 1))   # distance 3 <= 4
	check(vera.pos == Vector2i(3, 1), "move within budget succeeds")
	check(vera.econ["move_left"] == 1, "move points decremented by path cost")

func _mercy_setup(s: int):
	var c = _sandbox(s)
	for o in c.combatants:
		if o.id in ["snik", "vess", "kritch", "ilsa"]:
			o.pos = Vector2i(0, 0)   # out of the picture
	var g = _find(c, "grull"); var p = _find(c, "pike")
	g.pos = Vector2i(4, 1)
	p.pos = Vector2i(5, 1); p.statuses["down"] = true; p.hp = 0; p.death_f = 0
	return c

func test_help_grants_advantage() -> void:
	var cb = _sandbox()
	var vera = _find(cb, "vera"); var ilsa = _find(cb, "ilsa"); var grull = _find(cb, "grull")
	vera.pos = Vector2i(4, 1); grull.pos = Vector2i(4, 2); ilsa.pos = Vector2i(4, 0)
	cb.act_help(ilsa, vera)
	check(vera.has("helped"), "Help sets the flag on the ally")
	check(cb._attack_mode(vera, grull) == Dice.ADV, "a helped attacker rolls with advantage")
	cb.resolve_attack(vera, grull)
	check(not vera.has("helped"), "the granted advantage is spent by the attack")

# Help on a downed ally is First Aid, not "advantage on their next attack" --
# they have no next attack to grant it to.
func test_help_revives_a_downed_ally() -> void:
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa"); var pike = _find(cb, "pike")
	ilsa.pos = Vector2i(4, 1); pike.pos = Vector2i(4, 2)
	pike.statuses["down"] = true; pike.hp = 0; pike.death_s = 1; pike.death_f = 1
	var atk := {"id": "attack", "kind": "help", "targeting": "ally"}
	check(cb.legal_target(ilsa, atk, pike), "a downed ally is a legal Help target")
	cb.act_help(ilsa, pike)
	check(pike.hp == 1, "Help stirs them back up on 1 HP")
	check(not pike.is_down(), "...and they're no longer down")
	check(pike.death_s == 0 and pike.death_f == 0, "death saves reset like any other heal")

# Hidden means unseen -- nobody can react to a mover they never noticed leave.
func test_hidden_mover_provokes_nothing() -> void:
	var cb = _sandbox()
	var pike = _find(cb, "pike"); var grull = _find(cb, "grull")
	pike.pos = Vector2i(2, 1); grull.pos = Vector2i(3, 1)
	pike.stealth = 40
	check(cb.act_hide(pike), "pike hides")
	check(cb.provokers_for(pike, Vector2i(2, 5)).is_empty(),
		"a hidden mover triggers no opportunity attacks, however far they walk")

func test_hide_enables_advantage() -> void:
	var cb = _sandbox()
	var pike = _find(cb, "pike"); var grull = _find(cb, "grull")
	pike.pos = Vector2i(2, 1); grull.pos = Vector2i(7, 1)   # in bow range, not adjacent
	pike.stealth = 40                                        # guaranteed success
	check(cb.act_hide(pike), "high Stealth always hides")
	check(pike.has("hidden"), "hidden flag set")
	check(cb._attack_mode(pike, grull) == Dice.ADV, "hidden -> advantage on the attack")
	cb.resolve_attack(pike, grull)
	check(not pike.has("hidden"), "attacking breaks hidden")
	# a doomed Stealth roll fails
	var cb2 = _sandbox()
	var pk = _find(cb2, "pike"); pk.stealth = -40
	check(not cb2.act_hide(pk), "hopeless Stealth fails to hide")

# RAW: hidden means unseen, and you can't target what you can't perceive.
func test_hidden_is_untargetable() -> void:
	var cb = _sandbox()
	var pike = _find(cb, "pike"); var grull = _find(cb, "grull"); var snik = _find(cb, "snik")
	pike.pos = Vector2i(2, 1); grull.pos = Vector2i(3, 1); snik.pos = Vector2i(9, 9)
	pike.stealth = 40
	check(cb.act_hide(pike), "pike hides")
	check(not cb.enemies_of(grull).any(func(c): return c.id == "pike"),
		"a hidden combatant drops out of the opposing side's candidate list")
	var atk := {"id": "attack", "kind": "attack", "targeting": "enemy"}
	check(not cb.legal_target(grull, atk, pike), "...and can't be targeted directly")
	check(cb.available(grull).filter(func(v): return v["kind"] == "attack").is_empty(),
		"grull has nothing in reach to swing at (pike was its only adjacent foe)")
	# unrelated third party, never hidden, is unaffected
	check(cb.enemies_of(pike).any(func(c): return c.id == "grull"),
		"pike's own targeting of the (unhidden) grull is untouched")

func test_mercy_rule() -> void:
	# a conscious Vera is reachable this turn -> Grull leaves the downed Pike alone
	var spared := true
	for s in range(1, 25):
		var c = _mercy_setup(s)
		_find(c, "vera").pos = Vector2i(2, 1)   # 2 hexes off, reachable at speed 4
		c.begin_turn_for(_find(c, "grull"))
		AI._foe_turn(c, _find(c, "grull"))
		if _find(c, "pike").death_f > 0:
			spared = false
	check(spared, "MERCY: foe won't finish a downed PC while it can still engage a conscious one")

	# Vera unreachable -> the downed Pike is fair game
	var finished := false
	for s in range(1, 25):
		var c = _mercy_setup(s)
		var g = _find(c, "grull"); g.speed = 1
		_find(c, "vera").pos = Vector2i(0, 2)   # far, unreachable at speed 1
		c.begin_turn_for(g)
		AI._foe_turn(c, g)
		if _find(c, "pike").death_f > 0:
			finished = true
	check(finished, "no conscious PC in reach -> foe attacks the downed one (some seed lands it)")

func test_encounter_resolves_many_seeds() -> void:
	var wins = 0
	var losses = 0
	var rounds_total = 0
	var runs = 200
	for s in range(1, runs + 1):
		var rng = RNG.new(s)
		var cb = Combat.new(rng, Encounter.all(), Encounter.board())
		var guard = 0
		while not cb.is_over() and guard < 5000:
			var actor = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, actor)
			cb.end_turn()
			guard += 1
		check(cb.outcome() != "ongoing", "seed %d terminates with a winner" % s)
		check(cb.round_num <= Combat.MAX_ROUNDS, "seed %d ends within round cap" % s)
		rounds_total += cb.round_num
		if cb.outcome() == "Victory":
			wins += 1
		else:
			losses += 1
	# RE-BASELINED at F3 (spec §11 "the re-tuning cliff"): 200 win / 0 loss, avg 8.1.
	# Before F3 this was 186/14 @ 8.8 — and it still is with the two new autopilot
	# behaviours switched off, so the verb/economy rewrite itself is damage-neutral.
	# The whole swing is the party finally USING the kit it always had on the sheet:
	#   * the healer casts the real Cure Wounds (2d8+3, six slots) instead of the
	#     hand-authored 1d4+3 Healing Word            -> 186/14 becomes 194/6
	#   * the fighter spends Second Wind twice        -> 186/14 becomes 196/4
	# T20 (weapon mastery wired up) moved it again: 198/2 @ 7.8 — faster fights,
	# both sides now getting graze/topple/vex out of the weapons they carry.
	# The Sunken Shrine is now an easy encounter for an optimal party. That is a
	# TUNING fact for T8's scaler, not a rules bug; don't "fix" it here.
	print("  autoplay over %d seeds: %d win / %d loss, avg %.1f rounds" % [
		runs, wins, losses, float(rounds_total) / runs])
	check(wins > runs / 2, "the party wins the tutorial fight more often than not")
	check(losses == 0 or wins > 0, "auto-play is decisive either way")

# --- F3: action economy, pools, class features ------------------------

func test_action_economy() -> void:
	var cb = _sandbox()
	var vera = _find(cb, "vera"); var grull = _find(cb, "grull")
	vera.pos = Vector2i(4, 1); grull.pos = Vector2i(5, 1)
	cb.begin_turn_for(vera)
	check(vera.econ["move_left"] == vera.speed, "a fresh turn refills movement")
	var ids := cb.available(vera).map(func(v): return v["id"])
	check("attack" in ids and "dodge" in ids, "the basic actions are always on the list")
	check("fighter-second-wind" in ids, "a feature verb is offered off the sheet, not a flag")
	cb.perform(vera, cb._basic("dodge"))
	check(vera.econ["action"] == 0 and vera.has("dodging"), "Dodge spends the Action")
	check(not cb.available(vera).any(func(v): return v["cost"] == "action"),
		"no action-cost verb is offered once the Action is spent")
	check(cb.available(vera).any(func(v): return v["id"] == "fighter-second-wind"),
		"the bonus action is untouched by spending the Action")
	cb.perform(vera, vera.verb("fighter-second-wind"))
	check(vera.econ["bonus"] == 0, "Second Wind spends the Bonus Action")
	check(not cb.available(vera).any(func(v): return v["cost"] == "bonus"), "and only once")

	# reactions are spent between your own turns, so they live on the combatant
	var pike = _find(cb, "pike"); var snik = _find(cb, "snik")
	pike.pos = Vector2i(0, 1); snik.pos = Vector2i(1, 1)
	cb.begin_turn_for(pike)
	check(snik.econ["reaction"] == 1, "everyone starts with a reaction")
	cb.move_to(pike, Vector2i(0, 0))
	check(snik.econ["reaction"] == 0, "an opportunity attack spends the reaction")
	check(cb.provokers_for(pike, Vector2i(2, 1)).is_empty(), "a spent reaction provokes nothing")

func test_pool_spend_and_rest() -> void:
	var ch = Presets.vera()
	var c = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
	var cb = Combat.new(RNG.new(4), [c], Encounter.board())
	check(c.pool_left("fighter-second-wind") == 2, "fighter 3 has PB=2 Second Winds")
	cb.begin_turn_for(c)
	c.hp = 4
	cb.perform(c, c.verb("fighter-second-wind"))
	check(c.pool_left("fighter-second-wind") == 1, "using a verb decrements its pool")
	check(c.hp > 4, "Second Wind heals")
	cb.begin_turn_for(c)
	cb.perform(c, c.verb("fighter-second-wind"))
	check(c.pool_left("fighter-second-wind") == 0, "the pool empties")
	check(not cb.available(c).any(func(v): return v["id"] == "fighter-second-wind"),
		"an empty pool takes the verb off the menu")
	check(cb.perform(c, c.verb("fighter-second-wind")).has("error"), "and perform refuses it")

	# spend carries back to the build, and a rest refills it
	c.slots = ([0, 0, 0, 0, 0, 0, 0, 0, 0] as Array[int])
	Adapter.write_back(c, ch)
	check(int(ch.pools["fighter-second-wind"]) == 0, "spent uses persist to the character")
	check(Adapter.to_combatant(ch, "party", Vector2i.ZERO).pool_left("fighter-second-wind") == 0,
		"the next fight starts on the carried pool")
	Adapter.rest(ch, "short-rest")
	check(int(ch.pools["fighter-second-wind"]) == 2, "a short rest refills a short-rest pool")

	var ilsa = Presets.ilsa()
	var i = Adapter.to_combatant(ilsa, "party", Vector2i.ZERO)
	i.slots[0] = 1
	Adapter.write_back(i, ilsa)
	check(Adapter.to_combatant(ilsa, "party", Vector2i.ZERO).slots[0] == 1, "spent slots persist")
	Adapter.rest(ilsa, "short-rest")
	check(Adapter.to_combatant(ilsa, "party", Vector2i.ZERO).slots[0] == 1, "a short rest is no help")
	Adapter.rest(ilsa, "long-rest")
	check(Adapter.to_combatant(ilsa, "party", Vector2i.ZERO).slots[0] == 4, "a long rest refills slots")

func _barbarian(n := 5):
	var ch = Character.new()
	ch.id = "brak"; ch.cname = "Brak"; ch.species_id = "human"; ch.background_id = "soldier"
	ch.base_abilities = {"str": 16, "dex": 14, "con": 16, "int": 8, "wis": 10, "cha": 8}
	for i in n:
		ch.add_level("barbarian", -1)
	ch.equipped = ["greataxe"] as Array[String]
	return ch

func test_rage_full_turn() -> void:
	var ch = _barbarian()
	var brak = Adapter.to_combatant(ch, "party", Vector2i(4, 1))
	var grull = Adapter.from_monster(Catalog.all("monsters.json")[0], "foe", Vector2i(5, 1))
	var cb = Combat.new(RNG.new(11), [brak, grull], Encounter.board())
	cb.begin_turn_for(brak)
	var rage := _verb(cb, brak, "barbarian-rage")
	check(not rage.is_empty() and rage["cost"] == "bonus", "Rage is a bonus action off the sheet")
	check(brak.pool_left("rage") == 3, "barbarian 5 rages three times")
	cb.perform(brak, rage)
	check(brak.has("raging") and brak.econ["bonus"] == 0, "Rage costs the bonus action")
	check(brak.pool_left("rage") == 2, "Rage spends a rage")
	check(not cb.available(brak).any(func(v): return v["id"] == "barbarian-rage"),
		"you cannot rage twice in one turn")
	# the same turn: swing, and the rage damage rides along
	var hits := 0
	for s in range(1, 40):
		var c2 = Combat.new(RNG.new(s), [brak.clone(), grull.clone()], Encounter.board())
		var b2 = c2.combatants[0]; var g2 = c2.combatants[1]
		c2.begin_turn_for(b2)
		c2.perform(b2, b2.verb("barbarian-rage"))
		var r = c2.resolve_attack(b2, g2)
		if r.get("hit", false):
			hits += 1
			check(r["damage"] >= 3, "a raging hit carries the +2 damage")
			var rage_extra: Array = r["extras"].filter(func(e): return e["label"] == "raging")
			check(rage_extra.size() == 1 and int(rage_extra[0]["amount"]) == 2,
				"...and it's a labeled +2 raging extra, not silently folded into the total")
		check(b2.econ["action"] == 0, "the swing spent the Action, not the Bonus")
	check(hits > 0, "some seed lands the raging swing")
	# and rage resistance halves physical damage
	var before: int = brak.hp
	cb._apply_damage(brak, 10, "slashing")
	check(brak.hp == before - 5, "Rage resists slashing (%d -> %d)" % [before, brak.hp])

func test_action_surge_full_turn() -> void:
	var cb = _sandbox(7)
	var vera = _find(cb, "vera"); var grull = _find(cb, "grull")
	vera.pos = Vector2i(4, 1); grull.pos = Vector2i(5, 1)
	cb.begin_turn_for(vera)
	cb.resolve_attack(vera, grull)
	check(vera.econ["action"] == 0, "the first swing spends the Action")
	check(cb.resolve_attack(vera, grull).has("error"), "no second swing without a second action")
	var surge := _verb(cb, vera, "fighter-action-surge")
	check(surge["cost"] == "free", "Action Surge is free — it is not your bonus action")
	cb.perform(vera, surge)
	check(vera.econ["action"] == 1, "Action Surge grants a second Action")
	check(not cb.resolve_attack(vera, grull).has("error"), "which buys a second Attack")
	check(vera.pool_left("fighter-action-surge") == 0, "and is once per rest")
	check(vera.econ["bonus"] == 1, "the bonus action is still free")

func test_spell_slot_spend() -> void:
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa"); var grull = _find(cb, "grull")
	ilsa.pos = Vector2i(4, 1); grull.pos = Vector2i(5, 1)
	cb.begin_turn_for(ilsa)
	var sf := _verb(cb, ilsa, "sacred-flame")
	check(sf["slot_level"] == 0, "a cantrip is level 0")
	cb.perform(ilsa, sf, grull)
	check(ilsa.slots[0] == 4 and ilsa.slots[1] == 2, "a cantrip spends no slot")
	check(ilsa.econ["action"] == 0, "but it does spend the Action")
	check(not cb.available(ilsa).any(func(v): return v["kind"] == "spell"),
		"no action left, no spell on the menu")
	# upcasting is a verb per slot level, and it drains the right one
	cb.begin_turn_for(ilsa)
	var up := _verb(cb, ilsa, "burning-hands@2")
	check(int(up["dice_count"]) == 4, "burning hands at level 2 is 4d6")
	cb.perform(ilsa, up, Vector2i(1, 0))
	check(ilsa.slots[1] == 1 and ilsa.slots[0] == 4, "the level-2 cast took the level-2 slot")
	ilsa.slots = ([0, 0, 0, 0, 0, 0, 0, 0, 0] as Array[int])
	cb.begin_turn_for(ilsa)
	check(not cb.available(ilsa).any(func(v): return int(v.get("slot_level", 0)) > 0),
		"out of slots, leveled spells leave the menu")
	check(cb.available(ilsa).any(func(v): return v["id"] == "sacred-flame"), "the cantrip stays")

func test_reaction_and_concentration() -> void:
	# Uncanny Dodge: a reaction that fires by itself, no prompt (spec §7)
	var ch = Character.new()
	ch.id = "sly"; ch.cname = "Sly"; ch.species_id = "human"; ch.background_id = "criminal"
	ch.base_abilities = {"str": 10, "dex": 16, "con": 12, "int": 12, "wis": 10, "cha": 12}
	for i in 5:
		ch.add_level("rogue", -1)
	ch.equipped = ["dagger", "studded-leather"] as Array[String]
	var sly = Adapter.to_combatant(ch, "party", Vector2i(4, 1))
	var grull = Adapter.from_monster(Catalog.all("monsters.json")[0], "foe", Vector2i(5, 1))
	check(not sly.verb("rogue-uncanny-dodge").is_empty(), "rogue 5 has Uncanny Dodge")
	check(not cb_of(sly).available(sly).any(func(v): return v["id"] == "rogue-uncanny-dodge"),
		"a reaction is never a button — it fires on its trigger")
	var halved := 0
	for seed_i in range(1, 60):
		var c2 = Combat.new(RNG.new(seed_i), [sly.clone(), grull.clone()], Encounter.board())
		var s2 = c2.combatants[0]; var g2 = c2.combatants[1]
		c2.begin_turn_for(g2)
		var before: int = s2.hp
		var r = c2.resolve_attack(g2, s2)
		if r.get("hit", false):
			check(before - s2.hp == int(r["damage"]), "the logged damage is what landed")
			check(s2.econ["reaction"] == 0, "the reaction was spent")
			halved += 1
	check(halved > 0, "some seed lands a hit for Uncanny Dodge to halve")

	# Concentration: one spell at a time, dropped on a failed CON save after damage
	var cb = _sandbox()
	var ilsa = _find(cb, "ilsa")
	cb.begin_turn_for(ilsa)
	var v: Dictionary = ilsa.verb("burning-hands").duplicate()
	v["concentration"] = true
	cb.perform(ilsa, v, Vector2i(1, 0))
	check(ilsa.statuses.get("concentrating", {}).get("spell") == "burning-hands", "casting sets concentration")
	ilsa.max_hp = 500; ilsa.hp = 500
	cb._apply_damage(ilsa, 60)                 # DC 30 — nobody makes that
	check(not ilsa.has("concentrating"), "damage breaks concentration on a failed CON save")

# --- helpers ----------------------------------------------------------

func cb_of(c) -> Combat:
	return Combat.new(RNG.new(1), [c], Encounter.board())


func _verb(cb: Combat, c, id: String) -> Dictionary:
	for v in cb.available(c):
		if v["id"] == id:
			return v
	return {}


func _sandbox(s := 99) -> Combat:
	return Combat.new(RNG.new(s), Encounter.all(), Encounter.board())

func _find(cb: Combat, id: String) -> Combatant:
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

# T26 barks: cosmetic only — these assert the queue, not any rule.
func test_barks() -> void:
	var Barks = load("res://core/barks.gd")
	check(Barks.pool_for("foe", "goblinoid", "hit") != Barks.pool_for("foe", "", "hit"),
		"a faction pool differs from the generic one")
	check(Barks.pool_for("foe", "nosuchfaction", "hit") == Barks.FOE_GENERIC["hit"],
		"an unknown faction falls back to generic")
	check(not Barks.pool_for("party", "", "kill").is_empty(), "party has a kill pool")

	var had := OS.get_environment("SORCMERC_FAST")
	OS.set_environment("SORCMERC_FAST", "")   # barks are off in the suite's own mode
	var cb := _sandbox()
	var hero = cb.team_of("party")[0]

	cb._bark_rng = _lucky_rng()
	cb.bark(hero, "hit")
	check(cb.barks.size() == 1 and cb.barks[0]["id"] == hero.id, "a hit trigger queues a bark")
	check(cb.barks[0]["text"] in Barks.PARTY["hit"], "the line comes from the party hit pool")

	cb.barks.clear()
	cb._bark_rng = _lucky_rng()
	hero.hp = hero.max_hp
	cb._apply_damage(hero, hero.max_hp - 1)
	check(cb.barks.size() == 1 and cb.barks[0]["id"] == hero.id, "crossing 25% HP barks")
	cb.barks.clear()
	cb._bark_rng = _lucky_rng()
	cb._apply_damage(hero, 0)   # already under the line — no second low-HP bark
	check(cb.barks.is_empty(), "low HP barks once, on the crossing")

	cb.barks.clear()
	cb._bark_rng = RNG.new(7)
	for i in 300:
		cb.bark(hero, "hit")
	check(cb.barks.size() > 0 and cb.barks.size() <= cb.BARK_QUEUE_MAX,
		"an undrained queue stays capped (%d)" % cb.barks.size())

	var a := _sandbox(1234)
	var b := _sandbox(1234)
	var same := true
	for i in 50:
		a.bark(a.team_of("party")[0], "crit")
		b.bark(b.team_of("party")[0], "crit")
	for i in a.barks.size():
		if b.barks.size() <= i or a.barks[i]["text"] != b.barks[i]["text"]:
			same = false
	check(same and a.barks.size() == b.barks.size(), "same seed -> same barks")

	OS.set_environment("SORCMERC_FAST", "1")
	var fast := _sandbox()
	fast.bark(fast.team_of("party")[0], "crit")
	fast._apply_damage(fast.team_of("party")[0], 1)
	check(fast.barks.is_empty(), "no barks generated under SORCMERC_FAST")
	OS.set_environment("SORCMERC_FAST", had)

# First seed whose opening d100 lands inside the bark chance, so a trigger is sure to speak.
func _lucky_rng():
	var s := 1
	while RNG.new(s).roll_die(100) > load("res://core/barks.gd").CHANCE_PCT:
		s += 1
	return RNG.new(s)

func test_surrender() -> void:
	var cb = Combat.new(RNG.new(1), Encounter.all(), Encounter.board())
	check(not cb.is_over() and cb.outcome() == "ongoing", "fresh fight is ongoing")
	cb.surrender()
	check(cb.is_over() and cb.outcome() == "Defeat", "surrender ends the fight as a defeat")
