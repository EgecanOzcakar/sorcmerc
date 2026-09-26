# Combat-power estimate for the T8 encounter scaler. Scores a Combatant, not a
# Character — it has to score monsters too. The contract T8 depends on is
# estimate()'s four keys and their meanings, not these constants. It prices; it
# does not budget: the difficulty tiers and the curve a roster is bought against
# live in core/scaler.gd (Scaler.TIER, Scaler.CURVE) and nowhere else.
extends RefCounted

const REF_AC := 14       # what a party member is assumed to be swinging at
const REF_ATK := 5       # what a party member is assumed to be swung at by
const REF_SAVE := 2      # reference save bonus for save-based effects
const ROUNDS := 4        # the fight length resources are amortized over

# T23 — how much of a turn each condition denies the target it lands on. 1.0 is a
# full lockout (the target does nothing at all), 0.5 is about half a turn's worth
# of effectiveness gone (disadvantage on everything, or a movement lock), and the
# small ones are a nuisance tax. Anything unlisted is priced as a nuisance.
const DENIAL := {
	"paralyzed": 1.0, "stunned": 1.0, "unconscious": 1.0, "petrified": 1.0,
	"incapacitated": 0.9, "restrained": 0.6, "blinded": 0.5, "charmed": 0.5,
	"prone": 0.35, "frightened": 0.3, "poisoned": 0.3, "grappled": 0.3,
	"deafened": 0.05,
}
const DENIAL_OTHER := 0.25
const CTRL_WEIGHT := 36.0  # a full lockout that lands every round, before land odds
# The most a caster's best control SPELL adds to their score: +25%. Measured
# (tests/sweep_built.gd, 60 seeds, easy, the trio built like a player's):
#   pricing                              built L3   built L10
#   uncapped (1 + 0.08 * control)          81.7%      23.3%
#   capped at +50%                         83.3%      56.7%
#   control / 4 (one foe of four)          91.7%      68.3%
#   as damage the locked foe won't deal    93.3%      70.0%
#   capped at +25%                         95.0%      73.3%   <- this
#   not priced                             95.0%      91.7%
# The preset ruler carries no control spell and is unmoved (95.0% / 83.3%).
# What stays between 73% and 92% is the party autopilot never casting a lock,
# so a sweep charges the party for one it never throws. A player who does cast
# it gets that back.
const SPELL_LOCK_CAP := 1.25

static func p_hit(to_hit: int, ac: int, crit_range: int = 20) -> float:
	var need: int = ac - to_hit
	var p: float = clampf((21.0 - need) / 20.0, 0.05, 0.95)
	# a widened crit range is extra guaranteed hits on top
	return maxf(p, (21.0 - crit_range) / 20.0)

static func p_save(dc: int, bonus: int) -> float:
	return clampf((21.0 - (dc - bonus)) / 20.0, 0.05, 0.95)

static func avg(count: int, sides: int, bonus: int) -> float:
	return count * (sides + 1) / 2.0 + bonus

# How many targets a shaped spell (a cone, a line, a corner circle) is priced
# as catching. Two when the other side is not known — the party is priced before
# its foes exist, and the autopilot only throws an area where it nets two, so
# that stays what every sweep since T23 was measured on. When the other side IS
# known (a foe priced against the party it is being bought to fight, which is
# the only side core/scaler.gd knows the size of), the area catches that side,
# up to AREA_CAP: a Fireball on a party of three that fights shoulder to
# shoulder lands on all three, and pricing it as two is how a Magister came out
# at twice its price (tests/sweep_caster.gd, 2026-09-24). The owner's call:
# "area spells are counted against the other side's actual size".
const AREA_TARGETS := 2.0
const AREA_CAP := 4.0

static func area_targets(opponents: int) -> float:
	return AREA_TARGETS if opponents <= 0 else clampf(float(opponents), 1.0, AREA_CAP)

# {dpr, ehp, control, score}
# `opponents` is the size of the side this combatant will fight, 0 for unknown.
static func estimate(c, opponents := 0) -> Dictionary:
	var dpr := 0.0
	var attacks: Array = c.attacks
	if attacks.is_empty() and c.damage != "":
		attacks = [{"to_hit": c.atk_bonus, "dice_count": 0, "dice_sides": 0,
			"dmg_bonus": 0, "notation": c.damage}]
	var per_action := 1
	for v in c.verbs:
		if v["kind"] == "attacks_per_action":
			per_action = maxi(per_action, int(v["value"]))
	# Advantage is damage, not control: it re-rolls every attack the body makes.
	# ponytail: priced as if its `requires` (an ally next to the target) always
	# holds — true for the pack monsters that carry it, optimistic for a lone one.
	var adv := 1.0
	for v in c.verbs:
		if v["kind"] == "attack_modifier" and v.get("self", "") == "adv":
			adv = 2.0
	var road := road_buffs(c)
	if not attacks.is_empty():
		var a: Dictionary = attacks[0]
		var d := _avg_of(a) + float(road["damage"])
		var p := 1.0 - pow(1.0 - p_hit(int(a.get("to_hit", c.atk_bonus)) + int(road["to_hit"]), REF_AC, c.crit_range), adv)
		var crit: float = 1.0 - pow(1.0 - (21.0 - c.crit_range) / 20.0, adv)
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
				control += _control_value(v.get("conditions", []), c, share,
					String(v.get("trigger", "")) == "on_weapon_hit")
				dpr += _save_damage(v, c, share)
			"grant_verb":
				control += 0.5 * share
			"attack_modifier":
				if v.get("self", "") != "adv":
					control += 0.5 * share   # priced above as dpr when it is advantage
	# A caster's action is spent EITHER swinging or casting, so a cantrip replaces the
	# weapon action rather than stacking on it, and a leveled spell only contributes the
	# margin over that action, amortized across ROUNDS.
	#
	# The party autopilot has played it that way only since 2026-09-25 (core/ai.gd
	# _caster_bolt): before, a caster with no bow walked up and swung, so a
	# caster-heavy party won under the fights this bought it. tests/sweep_metamagic.gd
	# (the preset fighter and two built sorcerers, easy, 200 seeds) read 85.0 / 93.0 /
	# 79.5% at levels 3 / 5 / 10 on master and 92.5 / 97.0 / 86.5% after — nearer the
	# 95% target everywhere and over it nowhere past noise, so nothing here was re-priced.
	#
	# The spell list is a menu, not a stack: one action casts one spell and one
	# slot pays for one cast. This used to credit EVERY leveled spell with its
	# level's full slot count and add up every spell's control, so a caster's
	# score grew with the length of the prepared list, not with the fight they
	# could put up. A built level-10 cleric (fifteen prepared) scored 416 where
	# the same cleric without spells scored 20, at a credited 134 damage a round.
	# A control spell is priced as the one lock it is (_held_share).
	# The budget bought against that lost 93% of fights (tests/sweep_regions.gd,
	# docs/expansion-plan.md 2026-09-24). Now each slot is one cast of the best
	# spell it can pay for, at most ROUNDS casts in the fight (one a turn), and a
	# spell list's control is its best spell's, not their sum.
	var spells: Array = []
	var best_ctrl := 0.0
	for sid in c.spell_ids:
		var s := _spell_power(sid, c, opponents)
		best_ctrl = maxf(best_ctrl, float(s["control"]))
		if int(s["level"]) == 0:
			dpr = maxf(dpr, float(s["per_cast"]))
		else:
			spells.append(s)
	# A spell's lock rides its own capped bonus, not the uncapped (1 + 0.08 *
	# control) the rest of the kit shares. That multiplier was set for a monster
	# locking one of three heroes. A hero locking one foe of five or six is worth
	# less, and the uncapped product had one Hold Person tripling a level-10
	# cleric's whole score. Owner's call, 2026-09-24, measured with
	# tests/sweep_built.gd against five other pricings (docs/expansion-plan.md).
	var lock_mult: float = minf(1.0 + 0.08 * best_ctrl, SPELL_LOCK_CAP)
	var action_dpr := dpr   # the turn's action with no slot spent: the swing, or the best cantrip
	var casts: Array = []   # the margin each slot buys over the action it replaces
	for lvl in range(mini(c.slots.size(), 9), 0, -1):
		var margin := 0.0
		for s in spells:
			if int(s["level"]) <= lvl:
				margin = maxf(margin, float(s["per_cast"]) - dpr)
		for _i in int(c.slots[lvl - 1]):
			casts.append(margin)
	casts.sort()
	casts.reverse()
	var leveled := 0.0
	for i in mini(casts.size(), ROUNDS):
		leveled += float(casts[i])
	dpr += leveled / ROUNDS
	# Quickened Spell: a turn that casts its leveled spell as the Bonus Action
	# still has the action, so each one is a second action's worth of damage.
	dpr += action_dpr * float(quickened_turns(c, casts.size())) / ROUNDS

	var ehp := float(c.max_hp) * (0.55 / maxf(0.05, p_hit(REF_ATK, c.ac + int(road["ac"]))))
	for v in c.verbs:
		match v["kind"]:
			"heal_self", "heal_ally":
				ehp += avg(int(v.get("dice_count", 1)), int(v.get("dice_sides", 8)),
					int(v.get("dice_bonus", 0))) * float(v.get("uses", 1))
			"survive_damage":
				# T94 — one refused death is worth about the HP it takes to finish
				# the job again, and Undead Fortitude's save can fail.
				ehp += float(c.max_hp) * SURVIVE_SHARE * float(v.get("uses", 1))
			"save_modifier":
				ehp *= MAGIC_RESIST_MULT   # advantage on every save a spell forces
			"reaction":
				if int(v.get("ac_bonus", 0)) > 0:
					ehp *= PARRY_MULT
	var resists := false
	for v in c.verbs:
		if "bludgeoning" in v.get("resist", []):
			resists = true   # a held buff's resistance (Rage)
	if resists:
		ehp *= 1.3
	ehp *= _defense_mult(c)

	return {"dpr": dpr, "ehp": ehp, "control": control + best_ctrl,
		"score": sqrt(maxf(0.0, dpr) * maxf(0.0, ehp)) * (1.0 + 0.08 * control) * lock_mult}

# --- what the ruler did not see (the design audit §7.4) ---------------------
#
# Things a hero can carry into a fight that this file used to price at
# nothing, measured 2026-09-25 against the rosters they were fought on
# (tests/sweep_metamagic.gd, tests/sweep_unpriced.gd; the build log "The
# measured pass"). Priced here where a sweep saw them above noise:
#
#   Quickened Spell   the autopilot arms it (core/ai.gd's _quicken). A
#                     fighter beside two sorcerers who know it, against the
#                     rosters bought for the same party without it, easy:
#                     85.0 -> 85.5% at level 3, 93.0 -> 98.0% at 5, 79.5 ->
#                     88.0% at 10, fights a third shorter. Priced as a second
#                     action on each turn the points and slots can pay for
#                     (quickened_turns), it comes back to 83.5 / 95.0 / 83.0%:
#                     inside noise at every level. RE-MEASURED 2026-09-25 when
#                     casters stopped walking into melee (core/ai.gd
#                     _keep_range): without / with, priced, 92.5 / 93.5,
#                     97.0 / 96.5, 86.5 / 88.0% — still inside noise, the
#                     price stands.
#   road potions      a Potion of Heroism on each of the preset trio, or Giant
#                     Strength on its fighter, each +8.0 at hard, level 3
#                     (+4.0 at level 8). The buff's to-hit, damage and AC go on
#                     the numbers below as if they were the sheet's
#                     (road_buffs): priced, +3.5 / +0.0 at level 3, +3.3 / +0.7
#                     at 8. Its saves and a potion of resistance's one element
#                     stay unpriced, as the sheet's saves are.
#   bonds             every pair bonded, +8.0 at hard, level 3 — but a bond is
#                     the company's, not a hero's, so it is priced where the
#                     company is read: core/regions.gd's fresh_score.
#
# Weapon mastery was measured and NOT priced, judged at the noise line: every
# mastery off the preset trio is -2.5 at hard, level 3 (0.8 SE) and -4.3 at
# level 8 (300 seeds, 1.7 SE) — a third to a half of what the priced three
# measured, and each of the eight would need its own model (Vex and Sap are a
# roll's odds, Graze a miss's damage, Topple a condition) that no sweep has
# isolated yet. tests/test_power_pricing.gd holds it unpriced.

# The prefix a road-drunk potion's buff is filed under on a Combatant's
# statuses: core/potions.gd's STATUS_PREFIX (not preloaded; potions.gd pulls in
# the campaign, and this file prices monsters too).
const ROAD_BUFF_PREFIX := "potion:"

# {to_hit, damage, ac}: what the potions still running from the road add, summed.
# Only these three: a status the sheet has a number for. At pricing time a
# hero's statuses are what the adapter carried in (core/adapter.gd's ch.buffs),
# so nothing a fight grants is counted twice.
static func road_buffs(c) -> Dictionary:
	var out := {"to_hit": 0, "damage": 0, "ac": 0}
	for id in c.statuses:
		var s = c.statuses[id]
		if not (s is Dictionary and String(id).begins_with(ROAD_BUFF_PREFIX)):
			continue
		out["to_hit"] += int(s.get("bonus_to_hit", 0))
		out["damage"] += int(s.get("bonus_damage", 0))
		out["ac"] += int(s.get("ac", 0))
	return out

# How many turns of the fight Quickened Spell can buy: one a turn, each paying
# QUICKENED_POINTS sorcery points and one leveled slot, at most ROUNDS. 0 for
# anybody who does not know the option.
const QUICKENED_POINTS := 2
const SORCERY_POOL := "sorcery-points"

static func quickened_turns(c, leveled_casts: int) -> int:
	if not c.verbs.any(func(v): return String(v.get("kind", "")) == "metamagic" \
			and String(v.get("option", "")) == "quickened"):
		return 0
	var pts: int = int(c.pools.get(SORCERY_POOL, {}).get("cur", 0))
	return mini(mini(pts / QUICKENED_POINTS, leveled_casts), ROUNDS)

# T94 — the statblock defences (combatant.resist/immune/vulnerable), priced
# against what the party actually throws. Every weapon in data/weapons.json is
# one of the three physical types, so a physical line blunts nearly all of the
# party's damage and an elemental one only the caster's share of it — which is
# why the two are priced an order apart rather than per-entry. Immunity is worth
# about twice the resistance it beats. Replaces nothing: before this, a monster's
# whole damage-type line was invisible to the scaler because it was invisible to
# the engine (see core/combatant.gd's T94 note).
const PHYSICAL := ["bludgeoning", "piercing", "slashing"]
const PHYS_IMMUNE := 0.30
const PHYS_RESIST := 0.15
const PHYS_VULNERABLE := -0.10
const ELEM_IMMUNE := 0.06
const ELEM_RESIST := 0.03
const ELEM_VULNERABLE := -0.04
const SURVIVE_SHARE := 0.20      # of max HP, per use of a survive_damage feature
const MAGIC_RESIST_MULT := 1.10
const PARRY_MULT := 1.08

static func _defense_mult(c) -> float:
	var m := 1.0
	for t in PHYSICAL:
		if t in c.immune:
			m += PHYS_IMMUNE
		elif t in c.resist:
			m += PHYS_RESIST
		elif t in c.vulnerable:
			m += PHYS_VULNERABLE
	for t in c.immune:
		if not t in PHYSICAL:
			m += ELEM_IMMUNE
	for t in c.resist:
		if not t in PHYSICAL:
			m += ELEM_RESIST
	for t in c.vulnerable:
		if not t in PHYSICAL:
			m += ELEM_VULNERABLE
	return maxf(0.5, m)

# T23 — what a save-or-suffer effect is worth: how much of a turn it denies, times
# how often it actually lands (the save, and the attack roll first if it is an
# on-hit rider), times the share of the fight it is available for. The worst
# condition on the list is the one that decides the price; a rider that also
# poisons is not twice the stun.
static func _control_value(conditions, c, share: float, on_hit: bool) -> float:
	var worst := 0.0
	for cid in conditions:
		worst = maxf(worst, float(DENIAL.get(cid, DENIAL_OTHER)))
	if worst <= 0.0:
		return 0.0
	var land := 1.0 - p_save(c.save_dc, REF_SAVE)
	if on_hit:
		land *= p_hit(c.atk_bonus, REF_AC, c.crit_range)
	return CTRL_WEIGHT * worst * land * share

# A save_effect carrying dice is damage as well as control (breath weapons, poison
# riders) — priced at what lands, so dropping the old flat control score for them
# does not drop the monster's damage on the floor.
static func _save_damage(v: Dictionary, c, share: float) -> float:
	if int(v.get("dice_count", 0)) <= 0:
		return 0.0
	var d := avg(int(v["dice_count"]), int(v.get("dice_sides", 6)), int(v.get("dice_bonus", 0)))
	var land := 1.0 - p_save(c.save_dc, REF_SAVE)
	if v.get("halve_damage", false):
		land += (1.0 - land) * 0.5
	if String(v.get("trigger", "")) == "on_weapon_hit":
		land *= p_hit(c.atk_bonus, REF_AC, c.crit_range)
	return d * land * share

static func _avg_of(a: Dictionary) -> float:
	if int(a.get("dice_sides", 0)) > 0:
		return avg(int(a["dice_count"]), int(a["dice_sides"]), int(a.get("dmg_bonus", 0)))
	var Dice = load("res://core/dice.gd")
	var p: Dictionary = Dice.parse(a.get("notation", "1d4"))
	return avg(int(p["count"]), int(p["sides"]), int(p["mod"]))

# {per_cast, uses, level, control} — per-cast damage, not amortized.
static func _spell_power(sid: String, c, opponents := 0) -> Dictionary:
	var Effects = load("res://core/rules/effects.gd")
	var m: Dictionary = Effects.spell(sid)
	if m.is_empty():
		return {"per_cast": 0.0, "uses": 0.0, "level": 0, "control": 0.0}
	var lvl := int(m.get("level", 0))
	var uses: float = float(ROUNDS) if lvl == 0 else (float(c.slots[lvl - 1]) if lvl <= 9 else 0.0)
	var per_cast := 0.0
	for d in m.get("damage", []):
		var amount := avg(int(d.get("count", 1)), int(d.get("sides", 6)), int(d.get("plus", 0)))
		# A shaped spell: the autopilot only throws one where it nets two, and a
		# corner circle or a line through a cluster catches about that.
		var targets: float = area_targets(opponents) if m.get("shape", "single") != "single" else 1.0
		var landed: float = 1.0
		if m.has("save"):
			landed = 1.0 - p_save(c.save_dc, REF_SAVE)
			if m.get("half_on_save", false):
				landed = landed + (1.0 - landed) * 0.5
		elif m.has("attack"):
			landed = p_hit(c.save_dc - 8, REF_AC)
		per_cast += amount * targets * landed
	var ctrl := 0.0
	if uses >= 1.0:
		ctrl = _control_value(m.get("conditions", []), c, _held_share(m, c), false)
	return {"per_cast": per_cast, "uses": uses, "level": lvl, "control": ctrl}

# How much of the fight one cast of a control spell holds its one target, as a
# share of ROUNDS (the owner's call, 2026-09-24: a spell's control is priced as
# one concentration lock). It used to be min(1, slots / ROUNDS), a fresh lockout
# landing every round for as long as the slots lasted, where the spell really
# holds one creature until it saves its way out. The chance it lands is already
# in _control_value; this is how long it lasts once it has:
#   a one-round spell (Command, Vicious Mockery): one round;
#   a repeat save each turn, or damage ending it: rounds until the first made
#     save, expected sum of fail^k, capped at the fight;
#   no repeat save (Banishment, Polymorph): the rest of the fight.
static func _held_share(m: Dictionary, c) -> float:
	if String(m.get("duration", "")) == "round":
		return 1.0 / ROUNDS
	var rep := String(m.get("repeat_save", "none"))
	if rep == "none" or rep == "":
		return 1.0
	var fail := 1.0 - p_save(c.save_dc, REF_SAVE)
	var held := 0.0
	var stays := 1.0
	for _r in ROUNDS:
		held += stays
		stays *= fail
	return held / ROUNDS

static func team_score(combatants: Array, opponents := 0) -> float:
	var t := 0.0
	for c in combatants:
		t += float(estimate(c, opponents)["score"])
	return t

static func fits(roster: Array, budget: float) -> bool:
	return team_score(roster) >= budget
