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
# is what made a trip home from a cleared lair deadlier than the lair itself.
# A tier down, not off: it is still a fight, just not a second climax.
const BASELINE := "easy"

# MEASURED (2026-09-13), not reasoned. tests/test_scaler.gd's sweep starts every
# party at full HP by construction, so it could never see the case this file
# exists for; a throwaway harness that damages the party before round 1 and then
# autoplays it produced this grid — level-3 preset party, easy tier, 60 seeds a
# cell, so roughly +/-6 points of noise per number:
#
#     hp%      x1.00  x0.90  x0.75  x0.60  x0.50      <- budget scale
#     100%       87%    93%   100%    97%   100%
#      70%       85%    82%    92%   100%    97%
#      50%       68%    77%    82%    97%   100%
#      30%       40%    60%    83%    72%    72%
#
# Three things fall straight out of it, and all three moved the numbers below:
#
#  1. The hole is real and it is big. A party at 30% HP on an UNSCALED easy
#     roster wins 40% of the time. Walking home from a cleared lair was, before
#     this file, a coin flip you were losing.
#  2. x0.75 is the flat spot — 100/92/82/83 across the whole HP range. That is
#     the number the floor should land on.
#  3. Scaling FURTHER DOWN stops helping and starts hurting: at 30% HP, x0.60
#     and x0.50 both measured 72%, worse than x0.75's 83%. That is scaler.gd's
#     own chaff-vs-chunk mispricing (see its TUNING header) — a smaller budget
#     can buy a roster of fewer, chunkier foes that is nastier for a weakened
#     party than more small ones. "Just scale it down more" is wrong, and the
#     floor exists to stop exactly that.

# The flat part, and the user's own ask: open-world bands are some percent
# easier than the tier alone, always. Measured 93% at full HP against 87%
# unscaled — the road is not the content and should not cost a reload.
const WILDERNESS_SCALE := 0.90

# Where the condition curve starts biting. 0.80, not 0.70: the grid shows an
# unscaled party already down to 85% at 70% HP and 68% at 50%, so protection
# that only begins at 0.70 begins too late to catch the fall.
const HURT_AT := 0.80

# The most the party's condition can thin a fight, on top of WILDERNESS_SCALE.
# 0.83 because 0.90 * 0.83 ~= 0.75, which is the grid's flat spot — and because
# finding 3 above says going below it buys a worse fight, not a safer one.
const CONDITION_FLOOR := 0.83

# Derived, and the two numbers anything outside this file should reason about:
# the kindest and the harshest multiplier the wilderness can ever ask for.
const SCALE_MAX := WILDERNESS_SCALE
const SCALE_FLOOR := WILDERNESS_SCALE * CONDITION_FLOOR

# What the party's condition is worth as a budget multiplier, flat discount
# included — this is the number that goes to Scaler.roster_for(). Linear from
# WILDERNESS_SCALE at HURT_AT down to WILDERNESS_SCALE * CONDITION_FLOOR at zero
# HP: continuous at the threshold (no cliff the player can feel themselves
# crossing) and monotone, which is all this proxy can honestly claim.
#
# Note the invariant this DOES still hold and the one it no longer does: it is
# never above 1.0, so the wilderness can never be made harsher here. It is no
# longer exactly 1.0 for a fresh party — that is the point of WILDERNESS_SCALE,
# and it is a deliberate change from this file's first version.
static func power_scale(hp_frac: float) -> float:
	var t: float = clampf(hp_frac, 0.0, HURT_AT) / HURT_AT
	return clampf(WILDERNESS_SCALE * lerpf(CONDITION_FLOOR, 1.0, t), SCALE_FLOOR, SCALE_MAX)

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
