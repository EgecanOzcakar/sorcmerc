# D6 — the map is banded, so "further out" means something.
#
# Everything in the overworld scaled to the party: a roaming band, a lair, the
# road. That is what a level-scaled sandbox does, and it has one fatal property
# for a delve cycle — no destination. A place you could not survive last week is
# never a place you can survive now, because it grew with you; levelling up
# bought nothing but bigger numbers on both sides of the fight.
#
# So the map gets rings, anchored on the party's home country and sized to the
# map's own extent (the three world builders span 800 to 2000 units; a fixed
# radius would put one whole map in the heartland and another entirely in the
# deeps):
#
#   Regions.at(world, pos)              # {id, label, levels, ...} for a point
#   Regions.power_scale(world, pos, party)   # the budget knob that band implies
#   Regions.suits("deeps", "dragon")    # where a faction belongs, for placement
#
# The rule is a CLAMP, not a replacement: inside its band a fight is still built
# for the party that is standing there, which keeps every measured number in
# core/scaler.gd meaning what it says. Outside the band the content stops
# following. A level 10 party walking the heartland meets what the heartland
# has — level 3 content, trivially beaten, and paying level 3 XP and gold for it
# (core/encounter.gd derives both from the roster's own power, so this needs no
# code here and cannot be farmed). A level 3 party walking into the deeps meets
# what the deeps have, and should not expect to walk back out.
#
# That is the destination the delve cycle was missing: the frontier is visibly
# there from the start, it is genuinely lethal, and the thing that opens it is
# levels — not a key, a quest flag, or a wall.
#
# What this does NOT own: the fight (core/scaler.gd), what a band is worth
# (core/encounter.gd), the party's condition (core/world_threat.gd — it composes
# with this, see power_scale), placement itself (the world builders call suits()
# and place), or any drawing.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")

# The rings, nearest first. `upto` is a fraction of the map's own extent (see
# extent()), so the same four bands fit the 800-unit small map and the
# 2000-unit large one. `levels` is [min, max] and is the whole mechanism: it
# clamps the level a fight out here is built for.
#
# The bands overlap at their seams on purpose — a level 6 party is at the top of
# the marches and the bottom of the frontier, and is meant to be able to work
# either. A gap would make some level nobody's level.
#
# The seams are EQUAL-AREA, which is not the same as equally spaced, and getting
# that wrong is what made the heartland read as a bubble. A ring's share of the
# map goes as the square of its radius, so the first seams shipped at
# 0.30/0.60/0.85 gave the four countries 9% / 27% / 36% / 28% of the map — the
# heartland was a third the size of any of its neighbours. A player explores
# area, not radius, so the seams now sit at sqrt(1/4), sqrt(2/4), sqrt(3/4):
# four countries, a quarter of the map each.
#
# What that bought, on the maps the game ships (measured 2026-09-13): the small
# map's heartland goes 237 -> 394 units and the large map's 592 -> 986, which is
# what finally puts Oakford — the second human town, and the obvious first ride
# out of Riverhold — in the country built for the party that can reach it. On a
# generated map it also gives the near ring room to hold a lair at all: the
# heartland ring has to clear ProceduralWorld.MIN_MONSTER_GAP (300) from the
# settlement sitting at its own centre, and at 0.30 that annulus was empty below
# a 1000-unit extent, so the rejection sampler ran out of tries and dropped the
# goblin warren in somebody's front yard on 4 of 400 seeds. At 0.50: none.
const BANDS := [
	{"id": "heartland", "label": "the Heartland", "upto": 0.50, "levels": [1, 3],
		"blurb": "Patrolled, farmed, and about as dangerous as a bad harvest."},
	{"id": "marches", "label": "the Marches", "upto": 0.71, "levels": [3, 6],
		"blurb": "Still somebody's country, but nobody rides it alone after dark."},
	{"id": "frontier", "label": "the Frontier", "upto": 0.87, "levels": [6, 10],
		"blurb": "Past the last waystone. What lives here has never been taxed."},
	{"id": "deeps", "label": "the Far Deeps", "upto": 999.0, "levels": [10, 20],
		"blurb": "Old ground, and old things on it. Nothing out here is anybody's problem but yours."},
]

# A map has to be at least this wide before banding it means anything — under
# that, everything is the heartland rather than four rings a stone's throw
# apart. Sized just under the small map's own extent (~790).
const MIN_EXTENT := 700.0

# Where each faction belongs, for the builders that place lairs and bands. Named
# per band rather than derived from Scaler.FACTIONS' index: that index is a
# danger proxy elsewhere in this codebase (world_lairs' loot, site's depth) but
# it is an authoring order, not a ladder — kobolds sit above giants in it — and
# "which country is this thing's country" is a flavour question, not an
# arithmetic one. A faction may live in several bands; the shallowest one it
# appears in is its home (home_band).
const HOMES := {
	"heartland": ["bandit", "beast", "goblinoid"],
	"marches": ["goblinoid", "kobold", "orc", "gnoll", "bandit", "beast"],
	"frontier": ["undead", "orc", "gnoll", "cultist", "monstrosity", "giant"],
	"deeps": ["dragon", "giant", "undead", "elemental", "construct", "fey", "monstrosity"],
}


# The heartland's centre: the human settlement every world builder starts the
# player beside, falling back to the first settlement on the map and then to the
# origin. Deliberately NOT the party's current position — a map whose rings
# follow you around is a map with no far away in it.
static func anchor(world) -> Vector2:
	if world == null or world.settlements.is_empty():
		return Vector2.ZERO
	for s in world.settlements:
		if s.faction == "human":
			return s.position
	return world.settlements[0].position


# How far this map reaches, measured rather than declared: the furthest thing
# anybody placed on it. Settlements and lairs only — roaming bands move, and a
# band wandering off the edge must not stretch the rings behind it.
static func extent(world) -> float:
	if world == null:
		return MIN_EXTENT
	var a := anchor(world)
	var far := 0.0
	for s in world.settlements:
		far = maxf(far, a.distance_to(s.position))
	for l in world.lairs:
		far = maxf(far, a.distance_to(l.position))
	return maxf(MIN_EXTENT, far)


# Which band a point is in, plus how it got there — `distance` and `frac` are
# for the UI (a "you are crossing into..." line wants to say how far out), and
# `index` is the band's depth, so a caller can compare two of them.
static func at(world, pos: Vector2) -> Dictionary:
	var d: float = anchor(world).distance_to(pos)
	var frac: float = d / maxf(1.0, extent(world))
	for i in BANDS.size():
		if frac <= float(BANDS[i]["upto"]):
			var out: Dictionary = BANDS[i].duplicate(true)
			out["index"] = i
			out["distance"] = d
			out["frac"] = frac
			return out
	var last: Dictionary = BANDS[-1].duplicate(true)
	last["index"] = BANDS.size() - 1
	last["distance"] = d
	last["frac"] = frac
	return last


static func band_of(world, pos: Vector2) -> String:
	return String(at(world, pos)["id"])


static func label_of(world, pos: Vector2) -> String:
	return String(at(world, pos)["label"])


static func band_by_id(id: String) -> Dictionary:
	for b in BANDS:
		if String(b["id"]) == id:
			return b
	return {}


# What the party is, in one number, because a band is expressed in levels. The
# mean rather than the max: a level 9 fighter dragging two level 3s is not a
# level 9 party, and the fight is going to be resolved by all three of them.
static func party_level(party) -> int:
	if party == null:
		return 1
	var chars: Array = party.party_characters()
	if chars.is_empty():
		return 1
	var total := 0
	for ch in chars:
		total += ch.level()
	return maxi(1, int(round(float(total) / chars.size())))


# The level a fight HERE is built for: the party's own, pulled inside the band.
static func level_here(world, pos: Vector2, party) -> int:
	var band: Dictionary = at(world, pos)
	var lv: Array = band["levels"]
	return clampi(party_level(party), int(lv[0]), int(lv[1]))


# The budget knob the band implies, as a multiplier on core/scaler.gd's own
# budget — 1.0 whenever the party is already inside the band, which is the
# common case and costs nothing.
#
# The maths is scaler's own: _budget() is REF_SCORE * (team/REF_SCORE)^CURVE *
# TIER * power_scale, so buying the budget of a level-L party instead of a
# level-P one is exactly (score(L)/score(P))^CURVE. Nothing is re-tuned and no
# measured win rate moves; the same curve is simply read at a different point.
#
# It COMPOSES with core/world_threat.gd rather than replacing it: the caller
# multiplies the two. The band says how dangerous this country is; the party's
# condition still thins whatever the country sends, in the same proportion. A
# wrecked party crawling home through the frontier gets the frontier's fights at
# the frontier's size, cut by how wrecked it is — which is the point of both.
static func power_scale(world, pos: Vector2, party) -> float:
	var want: int = level_here(world, pos, party)
	var have: int = party_level(party)
	if want == have:
		return 1.0
	return pow(ref_score(want) / maxf(1.0, ref_score(have)), Scaler.CURVE)


# What a level-N party is worth, on core/rules/power.gd's own scale. Measured
# from core/presets.gd's trio at that level rather than from a table baked into
# this file: a table would be a number that quietly stops being true the next
# time a class gains a feature. Built once per level per process (~5ms each,
# twenty levels in ~100ms measured 2026-09-13) and cached.
#
# For reference, what the ruler reads at the band seams: level 1 -> 23.8,
# 3 -> 47.2 (which is REF_SCORE 46.6, as it should be — the whole scaler is
# anchored on a level 3 party), 6 -> 93.9, 10 -> 127.6, 20 -> 203.0. So a level
# 3 party in the deeps buys a fight at (127.6/47.2)^0.90 = x2.44 budget, and a
# level 10 party in the heartland gets x0.41 — outgrown, exactly as intended.
static var _score_cache := {}

static func ref_score(level: int) -> float:
	var n: int = clampi(level, 1, 20)
	if _score_cache.has(n):
		return float(_score_cache[n])
	var chars: Array = Presets.party_at(n)
	var team: Array = []
	for i in chars.size():
		team.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	var s: float = maxf(1.0, Power.team_score(team))
	_score_cache[n] = s
	return s


# MEASURED (2026-09-13), 80 seeds a cell, fight seed pinned (spec["seed"] = s,
# the omission that made an earlier sweep in this repo unreproducible), preset
# trio, wilderness tier `easy` — which is what core/world_threat.gd sends into
# open country, so this is the road rather than a site interior:
#
#   party  content   scale   win
#   lvl 3   lvl 3    x1.00  92.5%   <- in band: untouched, and this is scaler's own number
#   lvl 10  lvl 10   x1.00  95.0%   <- in band, further up the map, same story
#   lvl 6   lvl 3    x0.54   100%   <- one band back: outgrown, and it reads as outgrown
#   lvl 10  lvl 3    x0.41   100%   <- the heartland is a memory
#   lvl 3   lvl 6    x1.86  37.5%   <- one band out: "not yet", said clearly
#   lvl 3   lvl 10   x2.45  27.5%   <- the deeps, at level 3. Survivable, barely, and only
#                                      because avoid/parley (core/approach.gd) exist.
#
# The shape that matters: in band nothing moves at all, so every win rate
# core/scaler.gd measured still stands; one band out is a wall you can see over
# but not climb; one band back is a victory lap that pays like one (the payout
# falls with the roster's power, automatically — see core/encounter.gd).
#
# RE-MEASURED 2026-09-24, and the shape above NO LONGER HOLDS — on master too.
# tests/sweep_regions.gd (this method, now committed; 80 seeds a cell, tier
# easy, fight seed pinned), run back to back on master (e50d6c6) and on the
# audit branch (RAW death saves, cover on DEX saves only):
#
#   party  content   scale   2026-09-13   master   branch
#   lvl 3   lvl 3    x1.00      92.5%     98.8%    95.0%
#   lvl 10  lvl 10   x1.00      95.0%     66.2%    61.2%
#   lvl 6   lvl 3    x0.41       100%      100%     100%
#   lvl 10  lvl 3    x0.24       100%      100%     100%
#   lvl 3   lvl 6    x2.42      37.5%     11.2%     8.8%
#   lvl 3   lvl 10   x4.24      27.5%      0.0%     0.0%
#
# The branch moves every row 0-5 points, the same shape tests/sweep_tier.gd
# showed for those rules. The rest is older. power_scale reads scaler's CURVE,
# which was 0.90 when this table was taken and is 1.15 since scaler's
# 2026-09-15 retune, so every scale off the diagonal is steeper than the table
# says (one band out x1.86 -> x2.42, the deeps x2.45 -> x4.24), and nothing
# re-ran this table when it moved. One band out is no longer "a wall you can
# see over" but one you cannot, and the deeps at level 3 are not "survivable,
# barely" but not at all. In band at level 10 is 61-66%, not 95%: the level-10
# party is weaker against its own content than scaler's level-8 column says.
#
# Level 10 in band had its own cause, found the same day. Power.estimate
# credited every leveled spell with its level's whole slot count and summed
# every spell's control, so a caster's score grew with the prepared list. The
# ruler's level-10 cleric (fourteen spell ids) was priced at 113, and a built one
# (fifteen prepared) at 416 where the same cleric without spells is 20. Fixed
# in core/rules/power.gd: each slot is one cast of the best spell it pays for, at
# most ROUNDS casts a fight, and control is the best spell's. Re-run:
#
#   party  content   scale   branch before   with the power fix
#   lvl 3   lvl 3    x1.00      95.0%           96.2%
#   lvl 10  lvl 10   x1.00      61.2%           81.2%
#   lvl 6   lvl 3    x0.44       100%            100%
#   lvl 10  lvl 3    x0.30       100%            100%
#   lvl 3   lvl 6    x2.26       8.8%           17.5%
#   lvl 3   lvl 10   x3.38       0.0%            2.5%
#
# (The scales moved because ref_score is Power.team_score of the ruler party.)
# What is left of the level-10 gap is spell CONTROL. A built level-10 party
# (choices made, a full prepared list) wins 33% at easy in band. Price its
# spells' control at zero and it wins 92%, because Hold Person alone is priced
# as a lockout landing every round (CTRL_WEIGHT * share) while the party
# autopilot never casts a spell without dice at all, and a concentration lock
# holds one target at a time.
# ponytail: two calls are open. (1) Does regions keep its own exponent (0.90
# would put the off-diagonal scales back where this design was argued) or
# accept the steeper country? (2) Is spell control priced for a concentration
# lock, or given no price, or does the autopilot learn to cast it? Re-run
# tests/sweep_regions.gd after either.

# --- placement, for the world builders ------------------------------------

static func suits(band_id: String, faction: String) -> bool:
	return HOMES.get(band_id, []).has(faction)


# The shallowest band a faction lives in — where a builder should put one if it
# has no other reason to prefer a ring.
static func home_band(faction: String) -> String:
	for b in BANDS:
		if suits(String(b["id"]), faction):
			return String(b["id"])
	return String(BANDS[-1]["id"])


# Where a band sits as a share of the map, [min, max]. The deeps' `upto` is a
# sentinel (everything past the last seam is the deeps), so it clamps to 1.0
# here — a builder placing INTO the deeps must stay on the map, even though a
# thing that wandered off it would still read as being there.
static func ring_fracs(band_id: String) -> Array:
	var lo := 0.0
	for b in BANDS:
		var hi: float = minf(float(b["upto"]), 1.0)
		if String(b["id"]) == band_id:
			return [lo, maxf(lo + 0.01, hi)]
		lo = hi
	return [0.0, 1.0]


# The distance from the anchor a thing belonging to this band should be placed
# at, as [min, max] world units on this map. Builders scatter inside it.
static func ring(world, band_id: String) -> Array:
	var ext: float = extent(world)
	var f: Array = ring_fracs(band_id)
	return [float(f[0]) * ext, maxf(float(f[0]) * ext + 1.0, float(f[1]) * ext)]


# One line for the UI: what this country is and who it is for.
static func describe(band: Dictionary) -> String:
	var lv: Array = band.get("levels", [1, 1])
	return "%s — levels %d-%d. %s" % [
		String(band.get("label", "")), int(lv[0]), int(lv[1]), String(band.get("blurb", ""))]


# What a party is told when it crosses out of one band and into another: which
# way it went matters more than where it is, so this says so.
static func crossing_text(from_band: Dictionary, to_band: Dictionary) -> String:
	if from_band.is_empty() or to_band.is_empty():
		return ""
	if String(from_band.get("id", "")) == String(to_band.get("id", "")):
		return ""
	var lv: Array = to_band.get("levels", [1, 1])
	var deeper: bool = int(to_band.get("index", 0)) > int(from_band.get("index", 0))
	return "%s %s — levels %d-%d. %s" % [
		"You are riding out into" if deeper else "You are back inside",
		String(to_band.get("label", "")), int(lv[0]), int(lv[1]),
		String(to_band.get("blurb", ""))]
