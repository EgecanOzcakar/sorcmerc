# T8 — sizes an enemy roster against the party's power budget.
# Output is exactly encounter.build()'s spec: {"monsters": [{id, count, mult}]}.
#
# Two knobs, in this order: COUNT (up to MAX_FOES bodies from the four archetypes
# in data/monsters.json) then MULT (a stat multiplier applied at spawn — hp/ac/
# to-hit/damage, see encounter._scale). Count first because more goblins is the
# more honest kind of harder; the multiplier only closes what four archetypes and
# a body cap cannot.
#
# TUNING — 200-seed autoplay sweeps (tests/test_scaler.gd), level-3 preset party
# (Vera/Pike/Ilsa, team score 46.6), measured 2026-09-10:
#   easy   TIER 1.11 -> 8 foes  mult 0.85 : 188W/12L  (94.0%)  avg 9.0 rounds
#   normal TIER 1.36 -> 8 foes  mult 1.00 : 156W/44L  (78.0%)  avg 10.4 rounds
#   hard   TIER 1.55 -> 8 foes  mult 1.15 : 101W/99L  (50.5%)  avg 10.1 rounds
# Level-8 party (the presets levelled to 8, score 107.8), 100 seeds: 89 / 69 / 39%.
# CURVE is what makes that hold: budget grows as score^0.75, because power.gd's
# estimate() scales faster with party level than eight goblins ever can.
#
# Known ceiling: four archetypes and a body cap mean the mult knob does all the
# work past ~level 5, and its win-rate curve is lumpy (+1 AC / +1 to-hit lands in
# integer steps, so 1.80 -> 1.90 is a 30-point swing). Rates land within ~5 points
# of target at level 3 and ~11 at level 8; closing that needs a real bestiary, not
# more constants. Re-run the sweep after touching power.gd, adapter.gd's
# FT_PER_HEX/RANGE_CAP, or any verb — those move the win rate more than these do.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")

const TIER := {"easy": 1.11, "normal": 1.36, "hard": 1.55}
const REF_SCORE := 46.6   # the level-3 preset party — where TIER was calibrated
const CURVE := 0.75       # budget grows sublinearly with party power (see the header)
const MAX_FOES := 8
const MULT_MIN := 0.6
const MULT_MAX := 2.5
const MULT_STEP := 0.05

# The base mix, cycled in order. Bias weights (T9) push an id to the front and
# make it repeat, so a quest target shows up more often without displacing the mix.
const MIX := ["snik", "vess", "kritch", "grull"]

static func roster_for(party_characters: Array, difficulty: String, quest_bias: Dictionary = {}) -> Dictionary:
	var party: Array = []
	for ch in party_characters:
		party.append(Adapter.to_combatant(ch, "party", Vector2i.ZERO))
	var team: float = maxf(1.0, Power.team_score(party))
	var budget: float = REF_SCORE * pow(team / REF_SCORE, CURVE) * float(TIER.get(difficulty, TIER["normal"]))

	var order := _order(quest_bias)
	var counts := {}
	var n := 0
	while n < MAX_FOES:
		var id: String = order[n % order.size()]
		counts[id] = int(counts.get(id, 0)) + 1
		n += 1
		if _score(counts, 1.0) >= budget:
			break
	# Whatever the bodies could not reach (or overshot), the stat multiplier closes.
	var mult := MULT_MIN
	while mult < MULT_MAX and _score(counts, mult) < budget:
		mult += MULT_STEP
	return {"monsters": _spec(counts, snappedf(mult, 0.01))}

# Bias ids first and repeated proportionally to their weight (1.0 -> one extra slot).
static func _order(bias: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = bias.keys()
	ids.sort_custom(func(a, b): return float(bias[a]) > float(bias[b]))
	for id in ids:
		for i in maxi(1, roundi(float(bias[id]))):
			out.append(id)
	for id in MIX:
		out.append(id)
	return out

static func _score(counts: Dictionary, mult: float) -> float:
	var roster: Array = []
	for id in counts:
		for i in int(counts[id]):
			var c = Encounter.spawn(id, mult, "foe", Vector2i.ZERO)
			if c != null:
				roster.append(c)
	return Power.team_score(roster)

static func _spec(counts: Dictionary, mult: float) -> Array:
	var out: Array = []
	for id in MIX:
		if counts.has(id):
			out.append({"id": id, "count": int(counts[id]), "mult": mult})
	for id in counts:
		if not id in MIX:
			out.append({"id": id, "count": int(counts[id]), "mult": mult})
	return out
