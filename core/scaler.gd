# T8 — sizes an enemy roster against the party's power budget.
# Output is exactly encounter.build()'s spec: {"monsters": [{id, count, mult}]}.
#
# Two knobs, in this order: COUNT (up to MAX_FOES bodies drawn from ONE faction of
# data/bestiary.json — T16) then MULT (a stat multiplier applied at spawn — hp/ac/
# to-hit/damage, see encounter._scale). Count first because more goblins is the
# more honest kind of harder; the multiplier only closes what the bodies cannot.
#
# TUNING — 200-seed autoplay sweeps (tests/test_scaler.gd), level-3 preset party
# (Vera/Pike/Ilsa, team score 47.2), re-measured 2026-09-11 after T36's SPAWN_GAP
# 3 -> 6 landed: foes now start six hexes out, so the party gets a free round of
# ranged fire and the melee arrives piecemeal. One roster per seed, each its own
# faction, so this is the shipped distribution and not one warband repeated:
#   easy   TIER 1.00 -> avg 4.3 foes x0.93 : 182W/18L  (91.0%)  avg 8.7 rounds
#   normal TIER 1.35 -> avg 5.4 foes x0.96 : 148W/52L  (74.0%)  avg 10.3 rounds
#   hard   TIER 1.80 -> avg 5.9 foes x1.08 : 103W/97L  (51.5%)  avg 10.6 rounds
# Level-8 party (the presets levelled to 8, score 108.8), 60 seeds: 92 / 73 / 58%
# (was 88 / 73 / 52 before the gap change).
# TIER rose across the board (0.85/1.06/1.50 -> 1.00/1.35/1.80) purely to pay for
# the wider gap: at the old tiers the same rosters measured 95.5/86.5/68.5%, i.e.
# the distance alone was worth +5 easy / +11 normal / +19.5 hard, the harder tier
# gaining most because it fields the most bodies to walk in. CURVE stays 0.90 —
# level 8 still tracks level 3 within ~7 points. REF_SCORE stays 46.6: it is the
# anchor TIER is expressed against, not a measurement of today's preset party.
# TIER is steep here: hard 1.50/1.80/2.00/2.20 measured 68.5/51.5/40.5/30.0%, and
# easy 0.98/1.00/1.02 measured 94.5/91.0/89.5%, the mult knob being lumpy, so do
# not read a 2-point miss as a knob that wants turning.
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

const TIER := {"easy": 1.00, "normal": 1.35, "hard": 1.80}
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
# "sunken-shrine" deliberately maps to nothing: the shrine fights stay the four
# hand-tuned archetypes every difficulty target was calibrated against.
const THEME_FACTION := {
	"sunken-shrine": "", "goblin-camp": "goblinoid", "frozen-cave": "giant",
	"city-square": "bandit", "forest-clearing": "beast", "merchant-shop": "bandit",
}
# Most factions are already habitat-uniform (every "goblinoid" is "cave", every
# "giant" is "wild", ...) so pairing by faction alone is enough. "beast" is the
# one exception — it spans both "forest" (69 entries) and "water" (18), which is
# how a Killer Whale ended up in the same roster as a Giant Elk on a forest
# board. Only themes whose faction actually needs the extra split are listed.
const THEME_HABITAT := {"forest-clearing": "forest"}
const FACTIONS := ["goblinoid", "beast", "undead", "bandit", "giant", "kobold",
	"orc", "gnoll", "cultist", "soldier", "monstrosity", "fey", "elemental", "construct"]
const ROSTER_KINDS := 3   # distinct ids in one faction roster
const BIGGEST_SHARE := 0.6  # no single foe may be worth more than this of the budget

static var _fac_cache := {}   # faction -> [{id, score}], strongest first

# `theme` is the board this fight is on (Encounter.THEMES); with none, `seed`
# picks a faction. A quest bias keeps the hand-tuned MIX — the quest target has
# to be in the roster, and a snik among sahuagin is not a coherent warband.
static func roster_for(party_characters: Array, difficulty: String, quest_bias: Dictionary = {},
		theme: String = "", seed: int = 0) -> Dictionary:
	var budget := _budget(party_characters, difficulty)
	return _build(budget, _order(quest_bias) if not quest_bias.is_empty() else _faction_order(theme, seed, budget))

static func _budget(party_characters: Array, difficulty: String) -> float:
	var party: Array = []
	for ch in party_characters:
		party.append(Adapter.to_combatant(ch, "party", Vector2i.ZERO))
	var team: float = maxf(1.0, Power.team_score(party))
	return REF_SCORE * pow(team / REF_SCORE, CURVE) * float(TIER.get(difficulty, TIER["normal"]))

# T18 — a boss fight: the same budget and the same MULT knob, aimed differently.
# One named lead (campaign.gd's BOSS_POOL entry) is pumped until it alone is worth
# BOSS_LEAD_SHARE of the budget — capped at BOSS_MULT_MAX, which is what makes an
# "elite" goblin archer a boss rather than a goblin archer with a title — and the
# rest of the budget buys its escort out of the theme's faction, exactly as a
# normal roster does. `boss` is the node dict: {lead, lead_count, lead_features,
# difficulty, theme}.
#
# TUNING — 40-seed sweeps per boss (tests/test_scaler.gd), level-3 preset party,
# re-measured 2026-09-11 after SPAWN_GAP 3 -> 6 and the TIER retune above: oni
# 37.5%, assassin 55%, mammoth 15%, arrow-chief 10%, shop-captain 2.5% — pooled
# 24.0% against a 51.5% hard node (was 35/30/60/37.5/15, pooled 35.5%). These
# numbers are copied verbatim into campaign.gd's BOSS_POOL win_rate fields, which
# is what BOSS_REF_WIN_RATE's XP bonus reads. The lead-less shrine boss is swept
# as a plain hard node on its own theme (200 seeds, printed by the same test):
# 6.0%, down from 24.5% at the old hard 1.50 — "sunken-shrine" maps to no faction
# (THEME_FACTION) so it always fields MAX_FOES of the hand-tuned MIX and dumps the
# entire tier rise into mult (x1.15 -> x1.40). It has been an outlier since T16,
# the wider tier only sharpened it; it wants THEME_FACTION or MAX_FOES, not TIER.
# A boss spends the *hard* budget, so raising hard 1.50 -> 1.80 bought every boss
# a fatter escort, and an escort walking in from six hexes still beats a party
# that has to split fire between it and a pumped lead: the pool fell 11 points
# while the hard node it is measured against rose 2.5. The spread also flipped
# ends (mammoth 60 -> 15, assassin 30 -> 55) because distance rewards the bosses
# whose lead is slow and punishes a party that must chase one, which is the same
# chaff-vs-chunk ceiling in the header above seen from the other side.
# BOSS_LEAD_SHARE stays 0.40 (T23 took it 0.45 -> 0.40) — the pool is still inside
# test_scaler's 15-85% climax band, and a lead-share change would have to be
# re-measured against a hard node that just moved. Fix the spread in estimate(),
# don't chase it with this constant.
const BOSS_LEAD_SHARE := 0.40   # how much of the fight the boss itself is
const BOSS_MULT_MAX := 3.0      # +6 AC / +8 to-hit / +8 dmg / 3x HP at the ceiling
static func boss_for(party_characters: Array, boss: Dictionary, seed: int = 0) -> Dictionary:
	var budget := _budget(party_characters, String(boss.get("difficulty", "hard")))
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
