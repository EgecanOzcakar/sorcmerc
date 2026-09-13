# T92 — how hard the open world hits a party that has already been through
# something. Sites (core/site.gd) are multi-encounter dungeons run on ONE set of
# resources, so the party that walks back out of a cleared lair is at half HP
# with no slots and still has to cross open country to reach a town. This module
# answers one question — *given the party's condition, how hard should a
# wilderness encounter be?* — and answers it as the two arguments Scaler wants:
#
#   var t := WorldThreat.assess(party)
#   var spec := Scaler.roster_for(party.party_characters(), t["difficulty"],
#       {}, theme, seed_v, t["power_scale"])
#
# assess() returns {difficulty, power_scale, hp_frac, counted}: the first two are
# the call above, the last two are there so the caller can say *why* in a log
# line or a tooltip. Pure math on a Party — no scenes, no RNG, no world state.
#
# It does NOT own: the fight itself (scenes/world/world.gd still builds and
# launches it), site difficulty (sites are the hard content and do not come
# through here), boss nodes (Scaler.boss_for — a climax never scales down), or
# healing of any kind. This makes the world kinder; it never heals anybody.
#
# WHY THIS IS NOT AN EXPLOIT, and why there is no compensating mechanism here:
# core/encounter.gd derives the payout straight off the roster's own power
# (`xp = power * XP_PER_POWER`, gold likewise), so a roster bought with a
# smaller budget pays proportionally less XP and less gold, automatically and
# with no code in this file. Staying wounded buys easier fights AND poorer ones,
# at the same ratio — the incentive is already neutral, and the long-rest
# cooldown (core/settlement_visit.gd) is untouched, so this is not a way to farm
# anything. Do not "fix" this with a payout penalty; that would double-count.
extends RefCounted

# Sites are the hard content now. Open country is the walk between them — the
# thing that used to be "normal" for every wilderness fight in world.gd, which
# is what made a trip home from a cleared lair deadlier than the lair. A tier
# down, not off: easy measured 94.5% for a FRESH party (scaler.gd's TUNING
# header), so it is still a fight, just not a second climax.
const BASELINE := "easy"

# Above this fraction of pooled HP the party is scuffed, not beaten, and gets
# the baseline untouched. 0.70 because a party that spent its healing but not
# its hit points should not be handed a discount — the case this exists for is
# the one where the trip home is genuinely in doubt.
const HURT_AT := 0.70

# The most this can ever thin a fight. 0.45 of an easy budget still buys a real
# roster — Scaler._build() always puts at least one body down and the MULT_MIN
# floor keeps it from being a joke — while being enough of a cut to be felt at
# 1 hp each. It must never reach 0.0: a budget of zero would still produce a
# one-monster roster (the body loop appends before it checks), so a floor here
# is about the fight staying meaningful, not about avoiding an empty spec.
#
# ponytail: no sweep backs 0.45 the way TIER's numbers are backed. The autoplay
# sweep in tests/test_scaler.gd starts every party at full HP by construction,
# so it cannot measure a wounded one without a harness that can deal damage
# before round 1. The number is reasoned, not measured, and the test only pins
# its shape (monotone, capped at 1.0, never below the floor).
const SCALE_FLOOR := 0.45

# What the party's condition is worth as a budget multiplier. Linear from 1.0 at
# HURT_AT down to SCALE_FLOOR at zero HP: continuous at the threshold (no cliff
# the player can feel themselves crossing) and monotone, which is all we can
# honestly claim. A curve would imply a precision this proxy does not have.
static func power_scale(hp_frac: float) -> float:
	var t: float = clampf(hp_frac, 0.0, HURT_AT) / HURT_AT
	# Never above 1.0: this feature can only ever make the world kinder. A party
	# at full strength gets exactly the baseline, and 1.0 is an exact identity
	# through Scaler._budget()'s multiply, so "fresh" means "unchanged".
	return clampf(lerpf(SCALE_FLOOR, 1.0, t), SCALE_FLOOR, 1.0)

# Pooled current/max HP over the active party — total hit points left, not the
# average of per-member fractions, because the pool is what actually has to
# survive the walk home. A 40-hp fighter at half is a bigger hole in the party
# than a 20-hp rogue at half, and pooling says so.
#
# Dead and benched members are not counted at all. Benched is obvious (they are
# not in the fight). Dead matters more: Scaler already prices the roster against
# party_characters(), so losing someone ALREADY thins the next encounter through
# the team score. Reading a corpse as 0/max here would take that same loss a
# second time and hand a three-person party a discount for being three people —
# so a party of three healthy survivors reads as full strength, and gets the
# baseline. Being short-handed is not the same thing as being hurt.
static func party_hp_frac(party) -> float:
	var hp := 0.0
	var max_hp := 0.0
	for id in party.active:
		var ch = party.get_member(id)
		if ch == null or ch.dead:
			continue
		# summary() is the one place the codebase's "hp_current < 0 means full"
		# convention is resolved; read it there rather than re-deriving it.
		var s: Dictionary = party.summary(id)
		hp += float(s.get("hp", 0))
		max_hp += float(s.get("max_hp", 0))
	# Nobody left standing (or a zero-hp sheet): there is no condition to read,
	# so read it as full and change nothing. Degenerate input never earns a
	# discount — and it never earns a penalty either.
	if max_hp <= 0.0:
		return 1.0
	return clampf(hp / max_hp, 0.0, 1.0)

# The whole module in one call. `counted` is how many members the fraction was
# pooled from, so a caller can tell "full strength" from "nobody to read".
static func assess(party) -> Dictionary:
	var frac := party_hp_frac(party)
	var counted := 0
	for id in party.active:
		var ch = party.get_member(id)
		if ch != null and not ch.dead:
			counted += 1
	return {
		"difficulty": BASELINE,
		"power_scale": power_scale(frac),
		"hp_frac": frac,
		"counted": counted,
	}
