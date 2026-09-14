# T8 — sizes an enemy roster against the party's power budget.
# Output is exactly encounter.build()'s spec: {"monsters": [{id, count, mult}]}.
#
# Two knobs, in this order: COUNT (up to MAX_FOES bodies drawn from ONE faction of
# data/bestiary.json — T16) then MULT (a stat multiplier applied at spawn — hp/ac/
# to-hit/damage, see encounter._scale). Count first because more goblins is the
# more honest kind of harder; the multiplier only closes what the bodies cannot.
#
# TUNING — 200-seed autoplay sweeps (tests/test_scaler.gd), level-3 preset party
# (Vera/Pike/Ilsa, team score 47.2), re-measured 2026-09-11 for T40, which raised
# test_scaler's TARGET to easy 95 / normal 85 / hard 75 (was 90/75/50). Same
# shape, the whole curve shifted easier; nothing about the fight itself changed,
# only what we are aiming at. One roster per seed, each its own faction, so this
# is the shipped distribution and not one warband repeated:
#   easy   TIER 0.96 -> avg 4.4 foes x0.91 : 189W/11L  (94.5%)  avg 8.6 rounds
#   normal TIER 1.10 -> avg 4.6 foes x0.94 : 167W/33L  (83.5%)  avg 9.0 rounds
#   hard   TIER 1.32 -> avg 5.3 foes x0.95 : 150W/50L  (75.0%)  avg 10.5 rounds
# Level-8 party (the presets levelled to 8, score 108.8), 60 seeds: 95 / 88 / 78%
# (was 92 / 73 / 58 at T38's tiers).
#
# RE-MEASURED 2026-09-13 (D1), same harness, no knob touched since:
#   easy   avg 4.4 foes x0.93 : 175W/25L (87.5%)  avg 9.3 rounds
#   normal avg 4.7 foes x0.96 : 166W/34L (83.0%)  avg 9.5 rounds
#   hard   avg 5.3 foes x0.95 : 138W/62L (69.0%)  avg 10.4 rounds
#   level-8, 60 seeds: 98.3 / 93.3 / 81.7%   (bosses and the shrine are unmoved,
#   matching this header's numbers exactly, so the boss path is not involved)
# Still inside test_scaler's +/-10 BAND, so nothing fails — but easy is 7 points
# down and hard 6, which is 2-3 standard errors at 200 seeds, and level-8 moved
# the other way. Do not "fix" this by turning TIER until the cause below is
# understood: hard draws the SAME roster shape as it did at T40 (5.3 foes,
# x0.95) and still loses 6 more points, so the budget is not what changed.
#
# WHY — measured the same day, then RE-measured because the first pass was
# unsound. The first split omitted `spec["seed"]` (encounter.gd: "omit for a
# random fight"), so every fight was randomly seeded and the per-faction numbers
# moved run to run; an earlier version of this header reported a bimodal
# "eleven factions at 100%, two at 54%" split that does not exist. Pin the seed
# the way _sweep() does, or do not quote the number.
#
# Easy tier, level-3 party, 450 seeds, fight seed PINNED, by the faction drawn:
#   fey 53%  cultist 73%  dragon 73%  giant 77%  elemental 90%  undead 93%
#   beast/bandit/orc/gnoll/goblinoid 97%  kobold/soldier/monstrosity/construct 100%
#   overall 89.6%
# So it is a gradient, not two clusters: one real outlier (fey), a 73-77% band
# (cultist, dragon, giant), and a long tail that is nearly a walkover. What the
# low end shares is not "casters" — giant and dragon are not — but *chunk*: a
# budget met with a handful of big bodies.
#
# MEASURED, and it inverts the obvious fix. Asked whether a weaker/"younger"
# variant of a monster would fix the low end (the same knob boss_for uses to
# scale UP), 30 pinned seeds a cell:
#   as shipped                    fey 53%  cultist 73%  giant 77%  dragon 73%
#   same bodies at x0.6           fey 100% cultist  90%  giant 90%
#   SAME SPEND, x0.6 bodies       fey  27% cultist  30%  giant 50%  dragon 30%
# Scaling a monster down works mechanically — _scale() already handles it and
# MULT_MIN is 0.6, so no new monster ids, data or models are needed. But spending
# the saving on MORE bodies, which is what a budget-neutral swap means, makes
# every one of these fights far worse. That is action economy: 5e punishes the
# number of turns the other side gets much harder than it punishes any stat line.
# (Scaling save_dc down with the mult — which _scale does NOT currently do —
# added almost nothing: 90% vs 93% on cultist. It is a real gap in _scale, but
# it is not what drives the outliers.)
#
# So the lever for the low end is FEWER bodies, not weaker ones, and the pricing
# gap is that _score() is linear in count: the Nth body costs the same as the
# first, when its real contribution is a whole extra turn every round. A
# superlinear term in body count is the targeted fix. Note _build() currently
# adds bodies first and only raises mult once they are placed, so the generator
# is already biased toward the expensive direction.
#
# The relevant change is therefore a body-count term in _score()/estimate(), or
# a cap on what the untethered wilderness draw may roll at low budgets — not
# TIER, and not a tier of weaker monsters.
#
# SPIKE, 2026-09-13: the body-count term was built and measured, and then
# REVERTED. Recorded here so the next attempt starts from the results rather
# than from the idea. What was tried: _score() multiplied by a crowd factor —
# first the 2014 DMG's own table (x1.5 at two monsters, x2 at three to six,
# x2.5 at seven to ten), then pow(n, k) for k in {0.15, 0.25, 0.40}, then
# pow(min(n, 5), 0.40) to stop the brake growing once rosters are already large.
# TIER was re-calibrated by measurement for each, not guessed.
#
# It WORKS for the thing it was for. With the multiplier in and TIER
# recalibrated, the level-3 faction spread tightened from 47 points to 30:
# fey 53% -> 73%, cultist 73% -> 90%, and the "coin flip or walkover depending
# on which family the seed drew" problem above is materially reduced.
#
# It breaks the level-8 curve, and that is why it is not here. Crowd pricing
# forces every TIER up by roughly half, and at a level-8 budget the generator
# answers a bigger budget with bigger monsters rather than more of them — which
# is exactly where the chunk overpricing in the Known ceiling note below lives.
# Measured outcomes at level 8: the DMG table flattened the tiers to 96.7/93.3/
# 95.0; pow(n, 0.40) INVERTED them (hard easier than easy); pow(n, 0.25) ordered
# them but flat (94/91/...); the capped version ordered them with real spread
# but only above an effective TIER of ~2.4, while the level-3 targets want
# ~1.05-2.03. No single TIER triple satisfies both ends.
#
# So the missing knob is CURVE, not TIER: what reconciles a level-3 and a
# level-8 party is how fast the budget grows with party power, and that was left
# at 0.90 throughout. The next attempt should calibrate CURVE and TIER together
# against both parties, and should probably fix estimate()'s chunk pricing
# first, since the crowd term and the chunk bias pull in opposite directions and
# compound. This is a three-knob measured exercise, not a one-line addition.
# TIER fell across the board (1.00/1.35/1.80 -> 0.96/1.10/1.32) and the three
# tiers now sit much closer together: hard is where nearly all of the target rise
# landed (+23.5 points), so the budget spread that used to separate the tiers
# has largely collapsed. CURVE stays 0.90 — level 8 still tracks level 3 within
# ~4 points. REF_SCORE stays 46.6: it is the anchor TIER is expressed against,
# not a measurement of today's preset party.
# TIER is steep and lumpy here: hard 1.30/1.32/1.33 measured 77.5/75.0/73.5% and
# normal 1.08/1.10/1.12/1.14 measured 87.5/83.5/83.5/84.0%, so do not read a
# 2-point miss as a knob that wants turning. Easy has a floor near 95: at TIER
# 0.90 the level-8 easy sweep goes 60W/0L and trips test_scaler's "neither end is
# a foregone conclusion" check, which is what pins easy at 0.96 rather than the
# 94.5 -> 95.0 point a lower tier would otherwise buy.
#
# Known ceiling: what power.gd still misprices is chaff vs chunk, not control —
# an 11-hp hobgoblin's damage is priced for a whole fight it does not survive,
# while a 32-hp multiattacking thug is priced like ~1.6 of them and plays like
# four. That is the boss spread's remaining outliers (see boss_for below), and it
# needs a survival term in estimate(), not another constant. Re-run the sweep
# after touching power.gd, the bestiary's features, adapter.gd's FT_PER_HEX/
# RANGE_CAP, or any verb.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const TIER := {"easy": 0.96, "normal": 1.10, "hard": 1.32}
const REF_SCORE := 46.6   # the level-3 preset party — where TIER was calibrated
const CURVE := 0.90       # budget grows sublinearly with party power (see the header)
const MAX_FOES := 8
const MULT_MIN := 0.6
const MULT_MAX := 2.5
const MULT_STEP := 0.05

# The base mix, cycled in order. Bias weights (T9) push an id to the front and
# make it repeat, so a quest target shows up more often without displacing the mix.
const MIX := ["snik", "vess", "kritch", "grull"]

# T16: one board, one faction — a roster never mixes a dragon with a goblin.
# T41: "sunken-shrine" used to map to "" (the hand-tuned MIX), which made it the
# one theme with no body budget of its own — always MAX_FOES with the whole tier
# in mult, so it swung wildly with every TIER retune (6% at T38, 47% at T40).
# "undead" (17 entries, all habitat "dungeon", so no THEME_HABITAT split needed)
# is the drowned-shrine roster: 3.4 foes x0.89, 64.5% against hard's 75%.
const THEME_FACTION := {
	"sunken-shrine": "undead", "goblin-camp": "goblinoid", "frozen-cave": "giant",
	"city-square": "bandit", "forest-clearing": "beast", "merchant-shop": "bandit",
}
# Most factions are already habitat-uniform (every "goblinoid" is "cave", every
# "giant" is "wild", ...) so pairing by faction alone is enough. "beast" is the
# one exception — it spans both "forest" (69 entries) and "water" (18), which is
# how a Killer Whale ended up in the same roster as a Giant Elk on a forest
# board. Only themes whose faction actually needs the extra split are listed.
const THEME_HABITAT := {"forest-clearing": "forest"}
const FACTIONS := ["goblinoid", "beast", "undead", "bandit", "giant", "kobold",
	"orc", "gnoll", "cultist", "soldier", "monstrosity", "fey", "elemental", "construct",
	# T91: added for lair encounters (dragon cave) — bestiary.json already carries
	# 22 dragon-faction entries, just never plugged into a roster before this.
	"dragon"]
const ROSTER_KINDS := 3   # distinct ids in one faction roster
const BIGGEST_SHARE := 0.6  # no single foe may be worth more than this of the budget

static var _fac_cache := {}   # faction -> [{id, score}], strongest first

# M6: the pools are built from the bestiary once and kept. A content pack that
# adds or retunes monsters changes what the bestiary IS, so the cache has to go
# with it — core/mod/registry.gd calls this whenever the overlay set changes.
static func forget_pools() -> void:
	_fac_cache.clear()

# `theme` is the board this fight is on (Encounter.THEMES); with none, `seed`
# picks a faction. A quest bias keeps the hand-tuned MIX — the quest target has
# to be in the roster, and a snik among sahuagin is not a coherent warband.
#
# T92 — `power_scale` multiplies the finished budget, for callers who know
# something about the party that TIER cannot: core/world_threat.gd reads the
# active party's wounds and asks for a thinner wilderness fight, because every
# win rate in the header above was measured on a party at FULL resources and a
# party limping home from a cleared site is not that party. It is deliberately
# the LAST parameter with a 1.0 default, so it is a knob bolted onto the side of
# the calibration rather than a change to it — at 1.0 the arithmetic below is
# bit-for-bit what it was, and every existing call site keeps its measured
# numbers. It multiplies the budget only; nothing about TIER, CURVE, REF_SCORE
# or the two knobs in _build() moves.
static func roster_for(party_characters: Array, difficulty: String, quest_bias: Dictionary = {},
		theme: String = "", seed: int = 0, power_scale: float = 1.0) -> Dictionary:
	var budget := _budget(party_characters, difficulty, power_scale)
	return _build(budget, _order(quest_bias) if not quest_bias.is_empty() else _faction_order(theme, seed, budget))

static func _budget(party_characters: Array, difficulty: String, power_scale: float = 1.0) -> float:
	var party: Array = []
	for ch in party_characters:
		party.append(Adapter.to_combatant(ch, "party", Vector2i.ZERO))
	var team: float = maxf(1.0, Power.team_score(party))
	return REF_SCORE * pow(team / REF_SCORE, CURVE) * float(TIER.get(difficulty, TIER["normal"])) * power_scale

# T18 — a boss fight: the same budget and the same MULT knob, aimed differently.
# One named lead (campaign.gd's BOSS_POOL entry) is pumped until it alone is worth
# BOSS_LEAD_SHARE of the budget — capped at BOSS_MULT_MAX, which is what makes an
# "elite" goblin archer a boss rather than a goblin archer with a title — and the
# rest of the budget buys its escort out of the theme's faction, exactly as a
# normal roster does. `boss` is the node dict: {lead, lead_count, lead_features,
# difficulty, theme}.
#
# TUNING — 40-seed sweeps per boss (tests/test_scaler.gd), level-3 preset party,
# re-measured 2026-09-11 for T40's target retune: oni 32.5%, assassin 75%,
# mammoth 67.5%, arrow-chief 32.5%, shop-captain 17.5% — pooled 45.0% against a
# 75.0% hard node (was 37.5/55/15/10/2.5, pooled 24.0%). These numbers are copied
# verbatim into campaign.gd's BOSS_POOL win_rate fields, which is what
# BOSS_REF_WIN_RATE's XP bonus reads. The lead-less shrine boss is swept as a
# plain hard node on its own theme (200 seeds, printed by the same test): 64.5%
# (was 47.0% at T40, 6.0% at T38). T41 closed that outlier the way T40's note
# asked — THEME_FACTION, not TIER: the shrine now draws an undead roster and
# scales on bodies like every other theme (3.4 foes x0.89, both knobs mid-range),
# so a TIER change moves it as much as it moves anything else. The ~10-point gap
# left under hard is the chaff-vs-chunk ceiling, not the mapping.
# A boss spends the *hard* budget, so cutting hard 1.80 -> 1.32 thinned every
# boss's escort, and the pool gained 21 points while the hard node it is measured
# against gained 23.5 — the pool tracks hard almost one-for-one because the lead
# itself is capped by BOSS_LEAD_SHARE and it is the escort that absorbs the
# budget change. The spread stays wide (17.5% to 75%) and the ends stayed put
# this time, which is the chaff-vs-chunk ceiling in the header above: power.gd
# misprices a lone big bruiser no matter what the budget is.
# BOSS_LEAD_SHARE stays 0.40 (T23 took it 0.45 -> 0.40) — the pool is still inside
# test_scaler's 15-85% climax band, and a lead-share change would have to be
# re-measured against a hard node that just moved. Fix the spread in estimate(),
# don't chase it with this constant.
const BOSS_LEAD_SHARE := 0.40   # how much of the fight the boss itself is
const BOSS_MULT_MAX := 3.0      # +6 AC / +8 to-hit / +8 dmg / 3x HP at the ceiling
# D6 — `power_scale` here is the SAME knob roster_for has, and it exists for one
# caller: core/regions.gd's band clamp, which has to be able to say "this lair is
# in the deeps, build its climax for the deeps" when an underlevelled party walks
# in. T92's rule still stands and is enforced at the call site rather than here —
# core/world_threat.gd never reaches a boss, and core/site.gd passes maxf(1.0, x),
# so a climax can be raised by the country it stands in and never lowered by
# anything.
static func boss_for(party_characters: Array, boss: Dictionary, seed: int = 0,
		power_scale: float = 1.0) -> Dictionary:
	var budget := _budget(party_characters, String(boss.get("difficulty", "hard")), power_scale)
	var lead := String(boss.get("lead", ""))
	var count: int = maxi(1, int(boss.get("lead_count", 1)))
	var extras: Array = boss.get("lead_features", [])
	var mult := MULT_MIN
	while mult < BOSS_MULT_MAX and _lead_score(lead, count, mult, extras) < budget * BOSS_LEAD_SHARE:
		mult += MULT_STEP
	mult = snappedf(minf(mult, BOSS_MULT_MAX), 0.01)
	var entry := {"id": lead, "count": count, "mult": mult}
	if not extras.is_empty():
		entry["features"] = extras
	var rest: float = budget - _lead_score(lead, count, mult, extras)
	var monsters: Array = [entry]
	# The escort is the lead's kin but never the lead itself — two entries of one id
	# would spawn two combatants sharing an id.
	var order: Array = _faction_order(String(boss.get("theme", "")), seed, rest).filter(
		func(id): return id != lead)
	if rest > 0.0 and not order.is_empty():
		monsters.append_array(_build(rest, order, MAX_FOES - count)["monsters"])
	return {"monsters": monsters}

static func _lead_score(id: String, count: int, mult: float, extras: Array) -> float:
	var roster: Array = []
	for i in count:
		var c = Encounter.spawn(id, mult, "foe", Vector2i.ZERO, 0, extras)
		if c != null:
			roster.append(c)
	return Power.team_score(roster)

# Bodies first, then the stat multiplier for whatever the bodies missed.
static func _build(budget: float, order: Array, max_foes: int = MAX_FOES) -> Dictionary:
	var counts := {}
	var n := 0
	while n < max_foes:
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

# One faction's ids, strongest first, capped so the bodies knob still has room to
# work. Falls back to the hand-tuned MIX when nothing in the faction is small
# enough for the party (a level-1 party meets no CR 8 giant).
static func _faction_order(theme: String, seed: int, budget: float) -> Array:
	var fac: String = String(THEME_FACTION.get(theme, "")) if THEME_FACTION.has(theme) \
		else FACTIONS[absi(seed) % FACTIONS.size()]
	if fac == "":
		return MIX.duplicate()
	var need_habitat: String = String(THEME_HABITAT.get(theme, ""))
	var pool: Array = _faction_pool(fac).filter(
		func(e): return _in_budget_and_habitat(e, budget, need_habitat))
	if pool.is_empty():
		return MIX.duplicate()
	var start: int = absi(seed) % maxi(1, pool.size() / 2)
	var out: Array = []
	for i in mini(ROSTER_KINDS, pool.size()):
		out.append(pool[(start + i) % pool.size()]["id"])
	return out

static func _in_budget_and_habitat(e: Dictionary, budget: float, need_habitat: String) -> bool:
	if float(e["score"]) > budget * BIGGEST_SHARE:
		return false
	return need_habitat == "" or String(e["habitat"]) in [need_habitat, "any"]

static func _faction_pool(fac: String) -> Array:
	if not _fac_cache.has(fac):
		var out: Array = []
		for m in Catalog.all("bestiary.json"):
			if m.get("faction", "") != fac:
				continue
			var c = Encounter.spawn(m["id"], 1.0, "foe", Vector2i.ZERO)
			if c != null:
				out.append({"id": m["id"], "score": Power.estimate(c)["score"],
					"habitat": m.get("habitat", "any")})
		out.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
		_fac_cache[fac] = out
	return _fac_cache[fac]

# Bias ids first and repeated proportionally to their weight (1.0 -> one extra slot).
static func _order(bias: Dictionary) -> Array:
	var weighted: Array = []
	var ids: Array = bias.keys()
	ids.sort_custom(func(a, b): return float(bias[a]) > float(bias[b]))
	for id in ids:
		for i in maxi(1, roundi(float(bias[id]))):
			weighted.append(id)
	# Interleaved, not front-loaded: a small roster must still hold both the quest
	# target and the rest of the mix.
	var out: Array = []
	for i in maxi(weighted.size(), MIX.size()):
		if i < weighted.size():
			out.append(weighted[i])
		if i < MIX.size():
			out.append(MIX[i])
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
