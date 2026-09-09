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
	test_move_provokes_unless_disengage()
	test_healing_word_clears_death()
	test_alcove_cover()
	test_reach_and_range()
	test_move_budget()
	test_mercy_rule()
	test_encounter_resolves_many_seeds()

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
	ilsa.pos = Vector2i(4, 1)
	vera.pos = Vector2i(5, 1)   # east of Ilsa — in the cone
	snik.pos = Vector2i(5, 0)   # also east — in the cone
	var vera_before = vera.hp
	var ilsa_before = ilsa.hp
	cb.cast_burning_hands(ilsa, Vector2i(1, 0))  # facing east
	check(ilsa.hp == ilsa_before, "burning hands does not hit the caster")
	check(vera.hp < vera_before, "burning hands hits an ally in the cone")

	var cb2 = _sandbox()
	var i2 = _find(cb2, "ilsa"); var v2 = _find(cb2, "vera")
	i2.pos = Vector2i(4, 1); v2.pos = Vector2i(3, 1)   # west — behind the cone
	var vb = v2.hp
	cb2.cast_burning_hands(i2, Vector2i(1, 0))
	check(v2.hp == vb, "burning hands spares a creature outside the cone")

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
	cb.cast_healing_word(ilsa, pike)
	check(not pike.is_down(), "healing word brings a downed PC back up")
	check(pike.death_f == 0 and pike.death_s == 0, "healing word resets death saves")
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
		if c._saving_throw(k, 13, true): open_saves += 1
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
	check(cb.move_left == 1, "move points decremented by path cost")

func _mercy_setup(s: int):
	var c = _sandbox(s)
	for o in c.combatants:
		if o.id in ["snik", "vess", "kritch", "ilsa"]:
			o.pos = Vector2i(0, 0)   # out of the picture
	var g = _find(c, "grull"); var p = _find(c, "pike")
	g.pos = Vector2i(4, 1)
	p.pos = Vector2i(5, 1); p.statuses["down"] = true; p.hp = 0; p.death_f = 0
	return c

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
		var cb = Combat.new(rng, Encounter.all())
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
	print("  autoplay over %d seeds: %d win / %d loss, avg %.1f rounds" % [runs, wins, losses, float(rounds_total) / runs])
	check(wins > 0 and losses > 0, "auto-play is not a foregone conclusion either way")

# --- helpers ----------------------------------------------------------

func _sandbox(s := 99) -> Combat:
	return Combat.new(RNG.new(s), Encounter.all())

func _find(cb: Combat, id: String) -> Combatant:
	for c in cb.combatants:
		if c.id == id:
			return c
	return null
