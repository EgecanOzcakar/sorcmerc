# T9c — the difficulty overlay: presets, clamping, and what apply() does to a fight.
#   godot --headless --path . -s tests/test_difficulty.gd
extends SceneTree

const Difficulty = preload("res://core/difficulty.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Settings = preload("res://core/settings.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _party() -> Array:
	var out: Array = []
	var chars := Presets.party()
	for i in chars.size():
		out.append(load("res://core/adapter.gd").to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

func _init() -> void:
	for name in Difficulty.PRESETS:
		check(Difficulty.preset_of(Difficulty.PRESETS[name]) == name, "%s is recognised as itself" % name)
	check(Difficulty.preset_of({"foe_hp": 1.1}) == "custom", "a nudged knob is custom")
	check(Difficulty.preset_of({}) == "balanced", "an empty overlay is balanced")
	var c := Difficulty.clamped({"foe_hp": 9.0, "foe_hit": -10, "trade_price": 0.1, "foe_crits": 0})
	check(c["foe_hp"] == 2.0 and c["foe_hit"] == -2 and c["trade_price"] == 0.5 and c["foe_crits"] == false,
		"clamped() pins every knob to RANGE and types the bool")
	check(c["camp_cost"] == 1.0, "missing knobs fall back to balanced")

	var spec := {"monsters": [{"id": "grull", "count": 2, "mult": 1.0}], "seed": 3}
	var base = Encounter.build(spec.duplicate(true), _party())
	var cb = Encounter.build(spec.duplicate(true), _party())
	Difficulty.apply(cb, Difficulty.PRESETS["tactician"])
	var b0 = base.combatants.filter(func(x): return x.team == "foe")[0]
	var t0 = cb.combatants.filter(func(x): return x.team == "foe")[0]
	check(t0.max_hp == roundi(b0.max_hp * 1.25) and t0.hp == t0.max_hp, "tactician: foe HP x1.25 (%d -> %d)" % [b0.max_hp, t0.max_hp])
	check(t0.atk_bonus == b0.atk_bonus + 2, "tactician: foe to-hit +2")
	check(t0.damage != b0.damage, "tactician: foe damage notation bumped (%s -> %s)" % [b0.damage, t0.damage])
	var hero_b = base.combatants.filter(func(x): return x.team == "party")[0]
	var hero_t = cb.combatants.filter(func(x): return x.team == "party")[0]
	check(hero_t.max_hp == hero_b.max_hp and hero_t.atk_bonus == hero_b.atk_bonus, "the party is untouched")
	check(cb.foe_crits, "tactician keeps foe crits")
	var ex = Encounter.build(spec.duplicate(true), _party())
	Difficulty.apply(ex, Difficulty.PRESETS["explorer"])
	check(not ex.foe_crits, "explorer switches foe crits off")
	check(ex.combatants.filter(func(x): return x.team == "foe")[0].max_hp < b0.max_hp, "explorer thins foe HP")

	check(Difficulty.camp_cost(40, Difficulty.PRESETS["explorer"]) == 20, "explorer halves the inn")
	check(Difficulty.camp_cost(40, Difficulty.PRESETS["tactician"]) == 80, "tactician doubles it")
	check(is_equal_approx(Difficulty.trade_scale(Difficulty.PRESETS["explorer"]), 0.8), "explorer discounts the market")

	# round-trips through the settings file shape
	var s = Settings.new()
	s.difficulty = Difficulty.PRESETS["tactician"].duplicate()
	var d := Settings.to_dict(s)
	check(d["difficulty"]["foe_hit"] == 2, "difficulty is written to the settings dict")

	print("test_difficulty: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
