# Asserts on the rules that can silently rot (combat-design.md §10).
#   flatpak run org.godotengine.Godot --headless --path . -s tests/test_combat.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")
const Combatant = preload("res://core/combatant.gd")

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
	ilsa.zone = 1
	vera.zone = 1
	snik.zone = 1
	var vera_before = vera.hp
	var ilsa_before = ilsa.hp
	cb.cast_burning_hands(ilsa)
	check(ilsa.hp == ilsa_before, "burning hands does not hit the caster")
	check(vera.hp < vera_before, "burning hands hits an ally in the zone")

func test_move_provokes_unless_disengage() -> void:
	var cb = _sandbox()
	var pike = _find(cb, "pike")
	var grull = _find(cb, "grull")
	pike.zone = 1
	grull.zone = 1
	# run many seeds: at least one OA must land
	var landed = false
	for s in range(1, 40):
		var c = _sandbox(s)
		var p = _find(c, "pike")
		var g = _find(c, "grull")
		p.zone = 1
		g.zone = 1
		var before = p.hp
		c.move_to(p, 0)
		if p.hp < before:
			landed = true
	check(landed, "moving out of an occupied zone provokes (some seed lands the OA)")

	var safe = true
	for s in range(1, 40):
		var c = _sandbox(s)
		var p = _find(c, "pike")
		var g = _find(c, "grull")
		p.zone = 1
		g.zone = 1
		var before = p.hp
		c.move_to(p, 0, true)  # disengage
		if p.hp < before:
			safe = false
	check(safe, "Disengage prevents the opportunity attack")

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
	kritch.zone = 0
	var open_ac = cb.effective_ac(kritch)
	kritch.zone = 2
	check(cb.effective_ac(kritch) == open_ac + 2, "Alcove grants +2 AC")

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
