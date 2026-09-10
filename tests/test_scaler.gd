# T8: the difficulty sweeps that back the constants at the top of core/scaler.gd.
# The bands are +/-10 points — autoplay is stochastic and the mult knob is lumpy.
#   godot --headless --path . -s tests/test_scaler.gd
extends SceneTree

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Presets = preload("res://core/presets.gd")
const Power = preload("res://core/rules/power.gd")
const Campaign = preload("res://core/campaign.gd")

const SEEDS := 200
const TARGET := {"easy": 90.0, "normal": 75.0, "hard": 50.0}
const BAND := 10.0

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_control_pricing()
	test_spec_shape()
	test_quest_bias()
	test_monotone_difficulty()
	test_win_rates()
	test_higher_level_party()
	test_boss_pool()
	print("test_scaler: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# T23 — the same body priced with a full lockout, a half-turn debuff and nothing
# at all: control must be worth something, and a lockout must be worth the most.
func test_control_pricing() -> void:
	var plain := _scored("goblin", [])
	var frighten := _scored("goblin", ["monster-frightful-presence"])
	var knock := _scored("goblin", ["monster-knockdown"])
	var stun := _scored("goblin", ["monster-stunning-blow"])
	check(frighten > plain, "a control effect is worth more than none (%.1f > %.1f)" % [frighten, plain])
	check(stun > knock and knock > frighten,
		"the more of a turn it denies, the more it scores (stun %.1f > prone %.1f > fright %.1f)" % [
			stun, knock, frighten])

func _scored(id: String, features: Array) -> float:
	return Power.estimate(Encounter.spawn(id, 1.0, "foe", Vector2i.ZERO, 0, features))["score"]

func test_spec_shape() -> void:
	var spec = Scaler.roster_for(Presets.party(), "normal")
	check(spec.has("monsters") and spec["monsters"] is Array, "roster_for returns a build() spec")
	for e in spec["monsters"]:
		check(e.has("id") and int(e["count"]) > 0, "every entry is {id, count}")
		check(float(e["mult"]) > 0.0, "every entry carries the difficulty multiplier")
	# and it is directly buildable
	var cb = Encounter.build(spec, _party_at(Presets.party()))
	check(cb.team_of("foe").size() == _total(spec), "build() spawns exactly the spec's foes")
	check(Scaler.roster_for([], "normal")["monsters"].size() > 0, "an empty party still gets a roster")

func test_quest_bias() -> void:
	var plain = _counts(Scaler.roster_for(Presets.party(), "normal"))
	var biased = _counts(Scaler.roster_for(Presets.party(), "normal", {"grull": 3.0}))
	check(int(biased.get("grull", 0)) > int(plain.get("grull", 0)),
		"a quest bias puts more of its target in the roster (%d -> %d)" % [
			int(plain.get("grull", 0)), int(biased.get("grull", 0))])
	check(biased.size() > 1, "the bias tilts the mix, it does not replace it")

func test_monotone_difficulty() -> void:
	var chars := Presets.party()
	var prev := 0.0
	for d in ["easy", "normal", "hard"]:
		var s := _spec_power(Scaler.roster_for(chars, d))
		check(s > prev, "%s is worth more than the tier below it (%.1f > %.1f)" % [d, s, prev])
		prev = s

func test_win_rates() -> void:
	var chars := Presets.party()
	print("  level-3 preset party (score %.1f):" % Power.team_score(_party_at(chars)))
	for d in ["easy", "normal", "hard"]:
		var r := _sweep(chars, d, SEEDS)
		check(absf(r["rate"] - TARGET[d]) <= BAND, "%s win rate %.1f%% is within %.0f of %.0f" % [
			d, r["rate"], BAND, TARGET[d]])

func test_higher_level_party() -> void:
	var chars := [_lvl(Presets.vera(), "fighter", 5), _lvl(Presets.pike(), "rogue", 5),
		_lvl(Presets.ilsa(), "cleric", 5)]
	print("  level-8 party (score %.1f):" % Power.team_score(_party_at(chars)))
	# Four archetypes cannot hit the targets this far up (see scaler.gd's ceiling note);
	# what must hold is that the tiers stay ordered and the fight stays a fight.
	var rates: Array = []
	for d in ["easy", "normal", "hard"]:
		rates.append(_sweep(chars, d, 60)["rate"])
	check(rates[0] > rates[1] and rates[1] > rates[2], "tiers stay ordered at level 8 (%s)" % str(rates))
	check(rates[0] < 100.0 and rates[2] > 0.0, "neither end is a foregone conclusion at level 8")

# T18 — every boss in the pool is one lead plus an escort, and the pool as a whole
# is a real climax: harder than a hard node, not a wall. Checked pooled, not per
# boss — per-monster rates swing wildly (see scaler.gd's BOSS_LEAD_SHARE note),
# because power.gd prices a lone big bruiser far above what it plays like.
const BOSS_SEEDS := 40
const BOSS_BAND := [15.0, 85.0]

func test_boss_pool() -> void:
	var chars := Presets.party()
	var wins := 0
	var fights := 0
	for boss in Campaign.BOSS_POOL:
		if not boss.has("lead"):
			continue
		var spec := Scaler.boss_for(chars, boss, 1)
		var lead: Dictionary = spec["monsters"][0]
		check(lead["id"] == boss["lead"] and int(lead["count"]) >= 1, "%s leads with its own monster" % boss["id"])
		check(float(lead["mult"]) >= Scaler.MULT_MIN and float(lead["mult"]) <= Scaler.BOSS_MULT_MAX,
			"%s: the lead's mult stays inside the knob's range (%.2f)" % [boss["id"], float(lead["mult"])])
		check(lead.get("features", []) == boss.get("lead_features", []),
			"%s carries its extra features onto the lead" % boss["id"])
		check(spec["monsters"].size() > 1, "%s brings an escort" % boss["id"])
		var ids := {}
		for e in spec["monsters"]:
			check(not ids.has(e["id"]), "%s: %s appears in one entry only" % [boss["id"], e["id"]])
			ids[e["id"]] = true
		wins += int(_sweep_boss(chars, boss, BOSS_SEEDS)["wins"])
		fights += BOSS_SEEDS
	var rate := 100.0 * wins / fights
	print("    boss pool overall: %dW/%dL (%.1f%%)" % [wins, fights - wins, rate])
	check(rate >= BOSS_BAND[0] and rate <= BOSS_BAND[1],
		"the boss pool is a real climax overall (%.1f%%, want %.0f-%.0f%%)" % [rate, BOSS_BAND[0], BOSS_BAND[1]])
	# the elite path: the same monster, pumped, is worth much more than its stat block
	var elite := {"lead": "goblin-archer", "difficulty": "hard", "theme": "goblin-camp",
		"lead_features": ["monster-multiattack-2"]}
	var plain = Encounter.spawn("goblin-archer", 1.0, "foe", Vector2i.ZERO)
	var boosted = Encounter.spawn("goblin-archer", float(Scaler.boss_for(chars, elite, 1)["monsters"][0]["mult"]),
		"foe", Vector2i.ZERO, 0, elite["lead_features"])
	check(boosted.ac > plain.ac and boosted.max_hp > plain.max_hp and boosted.atk_bonus > plain.atk_bonus,
		"the elite's AC/HP/to-hit are all pumped (%d/%d/%d vs %d/%d/%d)" % [boosted.ac, boosted.max_hp,
			boosted.atk_bonus, plain.ac, plain.max_hp, plain.atk_bonus])
	check(Power.estimate(boosted)["score"] > 3.0 * Power.estimate(plain)["score"],
		"and it is worth several of the common version")

func _sweep_boss(chars: Array, boss: Dictionary, seeds: int) -> Dictionary:
	var wins := 0
	for s in range(1, seeds + 1):
		var sp: Dictionary = Scaler.boss_for(chars, boss, s)
		sp["seed"] = s
		sp["theme"] = boss["theme"]
		var cb = Encounter.build(sp, _party_at(chars))
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		if cb.outcome() == "Victory":
			wins += 1
	var rate := 100.0 * wins / seeds
	print("    boss %-16s -> %dW/%dL (%.1f%%)" % [boss["id"], wins, seeds - wins, rate])
	return {"rate": rate, "wins": wins}

# --- helpers ----------------------------------------------------------

# T16: one roster per seed, each its own faction — the shipped distribution, not
# one lucky warband repeated 200 times.
func _sweep(chars: Array, difficulty: String, seeds: int) -> Dictionary:
	var wins := 0
	var rounds := 0
	var foes := 0
	var mult := 0.0
	for s in range(1, seeds + 1):
		var spec: Dictionary = Scaler.roster_for(chars, difficulty, {}, "", s)
		foes += _total(spec)
		mult += float(spec["monsters"][0]["mult"])
		var sp: Dictionary = spec.duplicate(true)
		sp["seed"] = s
		var cb = Encounter.build(sp, _party_at(chars))
		var g := 0
		while not cb.is_over() and g < 5000:
			var a = cb.current()
			cb.begin_turn()
			AI.take_turn(cb, a)
			cb.end_turn()
			g += 1
		rounds += cb.round_num
		if cb.outcome() == "Victory":
			wins += 1
	var rate := 100.0 * wins / seeds
	print("    %-7s avg %.1f foes x%.2f -> %dW/%dL (%.1f%%) avg %.1f rounds" % [
		difficulty, float(foes) / seeds, mult / seeds, wins, seeds - wins,
		rate, float(rounds) / seeds])
	return {"rate": rate, "wins": wins}

func _party_at(chars: Array) -> Array:
	var out: Array = []
	for i in chars.size():
		out.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return out

func _lvl(ch, class_id: String, extra: int):
	for i in extra:
		ch.add_level(class_id, -1)
	return ch

func _total(spec: Dictionary) -> int:
	var n := 0
	for e in spec["monsters"]:
		n += int(e["count"])
	return n

func _counts(spec: Dictionary) -> Dictionary:
	var d := {}
	for e in spec["monsters"]:
		d[e["id"]] = int(e["count"])
	return d

func _spec_power(spec: Dictionary) -> float:
	var roster: Array = []
	for e in spec["monsters"]:
		for i in int(e["count"]):
			roster.append(Encounter.spawn(e["id"], float(e["mult"]), "foe", Vector2i.ZERO))
	return Power.team_score(roster)
