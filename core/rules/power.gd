# Combat-power estimate for the T8 encounter scaler. Scores a Combatant, not a
# Character — it has to score monsters too. The contract T8 depends on is
# estimate()'s four keys and their meanings, not these constants.
extends RefCounted

const REF_AC := 14       # what a party member is assumed to be swinging at
const REF_ATK := 5       # what a party member is assumed to be swung at by
const REF_SAVE := 2      # reference save bonus for save-based effects
const ROUNDS := 4        # the fight length resources are amortized over

const TIER := {"easy": 0.55, "normal": 0.85, "hard": 1.15}  # calibration knobs, expected to move

static func p_hit(to_hit: int, ac: int, crit_range: int = 20) -> float:
	var need: int = ac - to_hit
	var p: float = clampf((21.0 - need) / 20.0, 0.05, 0.95)
	# a widened crit range is extra guaranteed hits on top
	return maxf(p, (21.0 - crit_range) / 20.0)

static func p_save(dc: int, bonus: int) -> float:
	return clampf((21.0 - (dc - bonus)) / 20.0, 0.05, 0.95)

static func avg(count: int, sides: int, bonus: int) -> float:
	return count * (sides + 1) / 2.0 + bonus

# {dpr, ehp, control, score}
static func estimate(c) -> Dictionary:
	var dpr := 0.0
	var attacks: Array = c.attacks
	if attacks.is_empty() and c.damage != "":
		attacks = [{"to_hit": c.atk_bonus, "dice_count": 0, "dice_sides": 0,
			"dmg_bonus": 0, "notation": c.damage}]
	var per_action := 1
	for v in c.verbs:
		if v["kind"] == "attacks_per_action":
			per_action = maxi(per_action, int(v["value"]))
	if not attacks.is_empty():
		var a: Dictionary = attacks[0]
		var d := _avg_of(a)
		var p := p_hit(int(a.get("to_hit", c.atk_bonus)), REF_AC, c.crit_range)
		var crit: float = (21.0 - c.crit_range) / 20.0
		dpr = per_action * (p * d + crit * d * 0.5)

	var control := 0.0
	for v in c.verbs:
		var uses: float = float(v.get("uses", ROUNDS))
		var share: float = minf(1.0, uses / ROUNDS)
		match v["kind"]:
			"passive_damage":
				dpr += 0.5 * avg(int(v.get("dice_count", 0)), int(v.get("dice_sides", 6)), 0)
			"damage_bonus", "self_buff":
				dpr += per_action * float(v.get("bonus_damage", 0)) * share
			"grant_action":
				dpr += dpr * share / ROUNDS
			"save_effect":
				control += 3.0 * share
			"grant_verb":
				control += 0.5 * share
			"attack_modifier":
				control += 0.5 * share
	# A caster's action is spent EITHER swinging or casting, so a cantrip replaces the
	# weapon action rather than stacking on it, and a leveled spell only contributes the
	# margin over that action, amortized across ROUNDS.
	var leveled := 0.0
	for sid in c.spell_ids:
		var s := _spell_power(sid, c)
		control += float(s["control"])
		if int(s["level"]) == 0:
			dpr = maxf(dpr, float(s["per_cast"]))
		else:
			leveled += maxf(0.0, float(s["per_cast"]) - dpr) * minf(float(s["uses"]), ROUNDS) / ROUNDS
	dpr += leveled

	var ehp := float(c.max_hp) * (0.55 / maxf(0.05, p_hit(REF_ATK, c.ac)))
	for v in c.verbs:
		if v["kind"] in ["heal_self", "heal_ally"]:
			ehp += avg(int(v.get("dice_count", 1)), int(v.get("dice_sides", 8)),
				int(v.get("dice_bonus", 0))) * float(v.get("uses", 1))
	var resists := false
	for v in c.verbs:
		if "bludgeoning" in v.get("resist", []):
			resists = true
	if resists:
		ehp *= 1.3

	return {"dpr": dpr, "ehp": ehp, "control": control,
		"score": sqrt(maxf(0.0, dpr) * maxf(0.0, ehp)) * (1.0 + 0.08 * control)}

static func _avg_of(a: Dictionary) -> float:
	if int(a.get("dice_sides", 0)) > 0:
		return avg(int(a["dice_count"]), int(a["dice_sides"]), int(a.get("dmg_bonus", 0)))
	var Dice = load("res://core/dice.gd")
	var p: Dictionary = Dice.parse(a.get("notation", "1d4"))
	return avg(int(p["count"]), int(p["sides"]), int(p["mod"]))

# {per_cast, uses, level, control} — per-cast damage, not amortized.
static func _spell_power(sid: String, c) -> Dictionary:
	var Effects = load("res://core/rules/effects.gd")
	var m: Dictionary = Effects.spell(sid)
	if m.is_empty():
		return {"per_cast": 0.0, "uses": 0.0, "level": 0, "control": 0.0}
	var lvl := int(m.get("level", 0))
	var uses: float = float(ROUNDS) if lvl == 0 else (float(c.slots[lvl - 1]) if lvl <= 9 else 0.0)
	var per_cast := 0.0
	for d in m.get("damage", []):
		var amount := avg(int(d.get("count", 1)), int(d.get("sides", 6)), int(d.get("plus", 0)))
		# A shaped spell rarely catches more than a pair on a 9-wide board.
		var targets: float = 1.5 if m.get("shape", "single") != "single" else 1.0
		var landed: float = 1.0
		if m.has("save"):
			landed = 1.0 - p_save(c.save_dc, REF_SAVE)
			if m.get("half_on_save", false):
				landed = landed + (1.0 - landed) * 0.5
		elif m.has("attack"):
			landed = p_hit(c.save_dc - 8, REF_AC)
		per_cast += amount * targets * landed
	var ctrl: float = 3.0 * minf(1.0, uses / ROUNDS) if m.has("conditions") else 0.0
	return {"per_cast": per_cast, "uses": uses, "level": lvl, "control": ctrl}

static func team_score(combatants: Array) -> float:
	var t := 0.0
	for c in combatants:
		t += float(estimate(c)["score"])
	return t

static func roster_budget(party: Array, tier: String) -> float:
	return team_score(party) * float(TIER.get(tier, 1.0))

static func fits(roster: Array, budget: float) -> bool:
	return team_score(roster) >= budget
