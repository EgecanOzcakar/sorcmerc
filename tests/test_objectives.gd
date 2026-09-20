# Encounter objectives — the same fight, asked a different question.
#   docs/superpowers/specs/2026-09-20-encounter-objectives-design.md
#   godot --headless --path . -s tests/test_objectives.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_bystander()
	print("test_objectives: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

# A fight from a spec, the way scenes/main.gd builds one: board from the theme
# and seed, starts from the objective, presets at level 3 for the party.
func _fight(spec: Dictionary, seed: int) -> Combat:
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), seed)
	# const Encounter = preload(...) makes Encounter.foo() a compile-time static call
	# here, so Encounter.has_method(...) is a parse error regardless of whether the
	# method exists — load() the same file at runtime just to ask the question.
	var enc = load("res://core/encounter.gd")
	var starts: Array = enc.starts_for(sp, board, seed) if enc.has_method("starts_for") \
		else Encounter.party_starts(board, seed)
	var chars: Array = Presets.party()
	var party_c: Array = []
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", starts[i]))
	return Encounter.build(sp, party_c, board)

func _autoplay(cb: Combat) -> void:
	var g := 0
	while not cb.is_over() and g < 5000:
		var a = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, a)
		cb.end_turn()
		g += 1

func _goblins(n: int) -> Dictionary:
	return {"monsters": [{"id": "snik", "count": n}], "theme": "goblin-camp"}

# --- Task 1: the contract and the bystanders --------------------------------

func test_bystander() -> void:
	var cb := _fight(_goblins(2), 5)
	check(cb.objective.is_empty() and cb.objective_kind() == "", "no objective on the spec = rout")
	check(cb.order.size() == cb.combatants.size(), "rout: everybody who is in the fight has a turn")

	var car = Objectives.carter(Vector2i(0, 1), 3)
	check(car.team == "party" and car.has("bystander") and car.hp == 12 and car.ac == 11,
		"a carter is a party-side bystander with 6 + 2/level HP")
	var cap = Objectives.captive(Vector2i(8, 0))
	check(cap.has("bystander") and cap.has("captive") and cap.hp == 4, "a captive is a bystander that is also a captive")

	# Stood in a fight: never in the order, never a target for a foe, no death saves.
	var party_c: Array = []
	var chars: Array = Presets.party()
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	party_c.append(car)
	party_c.append(cap)
	var foe = Encounter.spawn("snik", 1.0, "foe", Vector2i(7, 0))
	var cb2 = Combat.new(RNG.new(3), party_c + [foe], Encounter.board())
	check(cb2.order.size() == 4, "the two bystanders are not in the initiative order (%d)" % cb2.order.size())
	check(cb2.with_status("carter") == car and cb2.with_status("captive") == cap, "with_status finds them")
	check(cb2.heroes().size() == 3, "heroes() is the conscious party without bystanders")
	check(not cb2.enemies_of(foe).has(cap), "a captive is never an enemy for a foe")
	check(cb2.enemies_of(foe).has(car), "...but a carter is fair game")
	check(not cb2.legal_target(foe, cb2.attack_verb(), cap), "legal_target refuses the captive")
	cb2._apply_damage(car, 50)
	check(car.is_dead() and not car.is_down(), "a bystander at 0 HP is dead, not down")
	check(not cb2.downed.has("carter"), "...and is not in the downed list")
	for h in cb2.heroes():
		cb2._apply_damage(h, 500)
	check(cb2._team_out("party"), "a party with only a bystander standing is out")
	check(cb2.is_over() and cb2.outcome() == "Defeat", "...and that is a defeat")
