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
# assess() returns {difficulty, power_scale, hp_frac, slot_hold, counted}: the
# first two are the call above, the rest are there so the caller can say *why*
# in a log line or a tooltip. Pure math on a Party — no scenes, no RNG, no world
# state.
#
# WOUNDS THIN A FIGHT; SPENT SLOTS DO NOT (the owner's call, 2026-09-24). The
# budget Scaler builds is priced off core/rules/power.gd's reading of the party,
# which reads max HP and never current HP — so the one piece of a party's
# condition it CAN see is the spell slots left. Unchecked, that made every slot
# spent on the road buy a smaller, poorer next fight, which is magic refunding
# its own cost and the opposite of pillar 3 ("magic is powerful but costly").
# `slot_hold` undoes exactly that: Scaler.held_at(fresh, now), the correction
# core/site.gd already makes for a lair's rooms, so the budget comes out the
# size it would have been for this party with every slot back. It is 1.0 for a
# party that has spent nothing, so everything measured below (the harness only
# ever damaged HP) stands as it was. HP is still what thins the fight, through
# power_scale(), and that is this file's whole answer to a hurt party.
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

const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")

# Sites are the hard content now. Open country is the walk between them — the
# thing that used to be "normal" for every wilderness fight in world.gd, which
# is what made a trip home from a cleared lair deadlier than the lair itself.
# A tier down, not off: it is still a fight, just not a second climax.
const BASELINE := "easy"

# RE-MEASURED 2026-09-25 (tests/sweep_wounds.gd, the harness the first grid
# was taken with, committed at last), and RETUNED: the owner's call on the
# design audit (docs/audit-game-design.md §3.2, "flatten the wounds curve").
#
# The first grid (2026-09-13, 60 seeds a cell) was taken under TIER easy 0.96 /
# CURVE 0.90, before the swing fix, RAW cover and death saves and the autopilot
# that spends its whole turn. It had a party at 30% HP winning 35% of unscaled
# easy fights, and this curve was cut to hold the whole range near 85%. Under
# today's rules the same party is much stronger, and the grid is:
#
#   level-3 preset party, easy tier, 200 seeds a cell, fight seed pinned,
#   every slot back (PART=grid):
#
#     hp%      x1.00  x0.90  x0.75  x0.60  x0.50  x0.40    <- budget scale
#     100%     96.5   99.0   99.0  100.0  100.0  100.0
#      70%     89.5   93.0   96.5   99.5  100.0  100.0
#      50%     76.0   86.5   94.0   99.5   99.0   99.5
#      30%     60.0   69.5   81.0   92.5   96.5   98.0
#
# The old curve (HURT_AT 0.90, floor 0.39, x0.35 at zero) put a company at
# 70 / 50 / 30% HP on x0.79 / 0.67 / 0.53, which that grid reads as 98 / 98 /
# 96%: a hurt company won as often as a fresh one, and hit points were barely
# a resource on the road. The owner's call: pressing on hurt should carry a
# real risk. So the curve now aims at two numbers the game already names —
# tests/test_scaler.gd's own targets. A company at HALF its HP meets what a
# fresh one meets at "normal" (85%); at 30% it meets "hard" (75%). Hurt is a
# tier up, not a free pass, and the full-HP number does not move.
#
# The live curve, both columns this sweep (PART=curve), master (HURT_AT 0.90,
# floor 0.39) against this (HURT_AT 0.50, floor 0.80), 200 seeds a cell:
#
#                 every slot back           every slot spent (slot_hold)
#     hp%      master       now           master       now
#   level 3
#     100%   x0.90 99.0   x0.90 99.0    x1.29 95.0   x1.29 95.0
#      70%   x0.79 98.0   x0.90 93.0    x1.12 91.5   x1.29 85.5
#      50%   x0.67 97.5   x0.90 86.5    x0.95 94.0   x1.29 73.5
#      30%   x0.53 96.0   x0.82 74.5    x0.75 91.0   x1.18 63.0
#   level 8
#     100%   x0.90 97.5   x0.90 97.5    x1.58 80.0   x1.58 80.0
#      70%   x0.78 99.0   x0.90 92.5    x1.37 82.5   x1.58 59.0
#      50%   x0.66 99.0   x0.90 86.5    x1.16 85.5   x1.58 47.5
#      30%   x0.53 98.0   x0.83 72.5    x0.93 87.5   x1.45 38.5
#
# On master the wounds discount more than paid back the slots a drained
# company had spent: a level-8 company with no slots won MORE often the more
# hurt it was (80.0% fresh, 87.5% at 30% HP). Now both halves of its condition
# cost it. The right-hand column is the walk home from a cleared lair, and it
# is the number to watch: a level-8 company at half HP with nothing left to
# cast wins a road fight about half the time. That is the gamble the owner
# asked for, and the approach card's other three answers (slip past, parley,
# ambush) are how a hurt company avoids taking it.

# The flat part, and the user's own ask: open-world bands are some percent
# easier than the tier alone, always. Measured 99.0% at full HP (level 3,
# sweep_wounds, 2026-09-25) against 96.5% unscaled — the road is not the
# content and should not cost a reload. Unchanged by the 2026-09-25 retune.
const WILDERNESS_SCALE := 0.90

# Where the condition curve starts biting. 0.50: above half HP the company
# meets the fresh company's roster, body for body, and pays for its wounds in
# win rate (93.0% at 70% HP, 86.5% at 50%, level 3). Was 0.90, which started
# the discount at the first scratch.
const HURT_AT := 0.50

# The most the party's condition can thin a fight, on top of WILDERNESS_SCALE:
# 0.80, so the combined floor is 0.90 * 0.80 = 0.72. Chosen off the grid for
# 30% HP to land on hard's 75%: the curve puts it on x0.82, which measured
# 74.5% (level 3) and 72.5% (level 8). Was 0.39 (a floor of 0.35, a fight a
# third of the size) when the aim was to make getting home near-certain.
# It must never reach 0.0 — Scaler._build() appends a body before it checks the
# budget, so a zero budget still fields one monster; the floor is about the
# fight staying a fight, not about avoiding an empty roster.
const CONDITION_FLOOR := 0.80

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

# The budget multiplier that prices the party as if every slot were back (see
# the header). >= 1.0 whenever a slot is spent, and exactly 1.0 when none is,
# or when there is nobody to read — both readings then floor at the same 1.0.
# It never makes a fight bigger than the one a fresh party of this build would
# meet; it only stops the spent slots from making it smaller.
# Since 2026-09-25 "a fresh party of this build" includes its bonds
# (Regions.fresh_score prices a bonded pair's shoulder AC, which no single
# hero's reading can see), so a bonded company's hold is above 1.0 even with
# every slot in hand: the one place on the road a bond is priced.
static func slot_hold(party) -> float:
	return Scaler.held_at(Regions.fresh_score(party), Scaler.party_score(party.party_characters()))

# The whole module in one call. `counted` is how many members the fraction was
# pooled from, so a caller can tell "full strength" from "nobody to read".
# `power_scale` is the condition curve times slot_hold(): callers pass it
# through untouched and get both.
static func assess(party) -> Dictionary:
	var frac := party_hp_frac(party)
	var counted := 0
	for id in party.active:
		var ch = party.get_member(id)
		if ch != null and not ch.dead:
			counted += 1
	var hold := slot_hold(party)
	return {
		"difficulty": BASELINE,
		"power_scale": power_scale(frac) * hold,
		"hp_frac": frac,
		"slot_hold": hold,
		"counted": counted,
	}
