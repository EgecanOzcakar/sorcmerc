# SPIKE (2026-09-16) — what the party thinks of each other, and whether two of
# them are more than friends. Write-up and the numbers behind every constant:
# docs/spike-party-opinions.md. The seven call sites the doc lists are wired
# (2026-09-21: the save, the party page, the road, decay, the fireside, the
# fight), and core/callings.gd adds an eighth — the bond a calling pays.
#
# One score per PAIR of members, -100..100, symmetric ("Vera and Pike" is one
# number, not two), plus a status on top of it: "" or "lovers" (a state the
# player agreed to at a camp), or "declined" (a courtship turned down, so the
# fire does not ask again). The score is what the game reads through `band()`;
# the status is what romance adds on top.
#
#   PartyOpinion.score(party, "vera", "pike")      # -100..100; an unrecorded pair sits at baseline()
#   PartyOpinion.band(party, "vera", "pike")       # rivals | cold | neutral | warm | bonded | lovers
#   PartyOpinion.saved(party, "ilsa", "vera")      # Ilsa got Vera back on her feet
#   PartyOpinion.travel_bonus(party)               # -1 / 0 / +1 on every road check
#   PartyOpinion.camp_moment(party, rng)           # a long rest's fireside beat, if one fires
#   PartyOpinion.decay(party, dt_minutes)          # drift toward the pair's baseline
#
# Three things decided here that shape everything else:
#
#  1. It lives on the Party (party.relations), not in a static like
#     FactionOpinion's. A faction has exactly one live world; a relationship is
#     between two saved characters and has to round-trip with them.
#  2. Drift goes toward a BASELINE, not toward 0. sorcmerc has no authored
#     companions — every member is player-made — so the only "personality" a pair
#     can have is what their sheets say: two soldiers get on, a noble and a
#     criminal do not, an elf and a dwarf need time. Left alone, a pair settles
#     where its baseline puts it, which is what makes an unrecorded pair already
#     mean something on day one.
#  3. Romance is CONSENSUAL and ASKED, never rolled. D3's rule is that road cards
#     resolve themselves; a courtship is the one beat that has to stop and ask,
#     so camp_moment() returns it with `options` (D4's approach-card shape) and
#     applies nothing until answer_courtship() is called with the answer.
extends RefCounted

const Hex = preload("res://core/hex.gd")
const Ach = preload("res://core/achievements.gd")

const RANGE := 100.0

# Bands on the score, spaced like FactionOpinion's: one event is noise, a run
# of them moves a pair across a line.
const RIVALS := -40.0
const COLD := -15.0
const WARM := 20.0
const BONDED := 50.0
const COURTSHIP_MIN := 60.0      # a camp can offer a courtship from here up
const LOVERS_BREAK := 0.0        # lovers whose score falls to this are lovers no longer

# What moves it. Sized against each other: being saved is the biggest single
# thing that can happen between two people in this game; a shared won fight is
# the smallest, and there are a lot of those.
const SAVED := 12.0              # brought back from 0 HP by this person (a heal, First Aid)
const FOUGHT_BESIDE := 1.0       # a won fight both were still standing at the end of
const FRIENDLY_FIRE := 6.0       # caught in this person's cone or area
const ROAD_PASS := 1.0           # the roller carried the party past a road event
const ROAD_FAIL := 2.0           # ...or walked it into one that cost (D3's kind "bad")
const CAMP_WARMING := 8.0
const CAMP_QUARREL := 8.0
const COURTSHIP_ACCEPTED := 15.0
const CALLING_BOND := 15.0       # a calling completed, with the one who did the thing (core/callings.gd)
const COURTSHIP_DECLINED := 10.0 # lowered: it is awkward around the fire for a while
const BREAKUP := 20.0            # the extra drop when lovers fall out

const DRIFT_PER_DAY := 1.0       # toward the pair's baseline; half FactionOpinion's — people are stickier
const DAY := 1440.0              # world-minutes (core/faction_opinion.gd's DAY)

# Combat. All three are read by core/combat.gd's hooks (shoulder_bonus on AC,
# bicker_penalty on to-hit, rally when a partner goes down); the sweep
# (tests/sweep_party_opinion.gd) measured them before they were wired.
const SHOULDER_AC := 1           # bonded/lovers adjacent to each other: +1 AC each
const BICKER_TO_HIT := 1         # rivals adjacent to each other: -1 to hit each
const RALLY_STATUS := "rallied"  # a partner just went down: advantage on the next attack

# Camp. One beat per long rest at most, and only half of them.
const MOMENT_CHANCE_PCT := 50
const COURTSHIP_CHANCE_PCT := 50 # ...of the moments where a courtship is possible at all

# --- baseline: what two sheets say about each other ----------------------------
#
# Backgrounds fall into a handful of tempers; same temper likes itself, a few
# pairs of tempers grate. Species carry the three classic grudges and a small
# kinship bonus. Everything here is a starting point the road can overwrite: a
# soldier and a thief who have saved each other's lives are past it.
const TEMPER := {
	"acolyte": "devout", "hermit": "devout",
	"sage": "learned", "scribe": "learned",
	"soldier": "martial", "guard": "martial",
	"criminal": "crooked", "charlatan": "crooked",
	"noble": "gentry", "merchant": "gentry",
	"farmer": "plain", "artisan": "plain", "guide": "plain", "sailor": "plain", "wayfarer": "plain",
	"entertainer": "showy",
}
const SAME_TEMPER := 10.0
const TEMPER_GRUDGE := {           # keys sorted, the way _pair_key() builds them
	"crooked|martial": -10.0, "crooked|gentry": -10.0,
	"gentry|plain": -5.0, "crooked|devout": -5.0, "devout|showy": -5.0,
}
const SAME_SPECIES := 5.0
const SPECIES_GRUDGE := {"dwarf|elf": -5.0, "dwarf|orc": -5.0, "elf|orc": -5.0}

static func baseline(ca, cb) -> float:
	if ca == null or cb == null:
		return 0.0
	var v := 0.0
	var ta := String(TEMPER.get(ca.background_id, ""))
	var tb := String(TEMPER.get(cb.background_id, ""))
	if ta != "" and ta == tb:
		v += SAME_TEMPER
	else:
		v += float(TEMPER_GRUDGE.get(_pair_key(ta, tb), 0.0))
	if ca.species_id != "" and ca.species_id == cb.species_id:
		v += SAME_SPECIES
	else:
		v += float(SPECIES_GRUDGE.get(_pair_key(ca.species_id, cb.species_id), 0.0))
	return v

static func baseline_of(party, a: String, b: String) -> float:
	return baseline(party.get_member(a), party.get_member(b))

# --- the score -----------------------------------------------------------------

static func key(a: String, b: String) -> String:
	return _pair_key(a, b)

static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % ([a, b] if a <= b else [b, a])

static func _entry(party, a: String, b: String) -> Dictionary:
	return party.relations.get(_pair_key(a, b), {})

static func _write(party, a: String, b: String, score: float, status: String) -> void:
	party.relations[_pair_key(a, b)] = {"score": clampf(score, -RANGE, RANGE), "status": status}

# An unrecorded pair sits at its baseline — two soldiers already get on the day
# they meet, and nothing has to be written for that to be true.
static func score(party, a: String, b: String) -> float:
	if a == b:
		return 0.0
	var e := _entry(party, a, b)
	return float(e["score"]) if e.has("score") else baseline_of(party, a, b)

static func status(party, a: String, b: String) -> String:
	return String(_entry(party, a, b).get("status", ""))

static func set_score(party, a: String, b: String, v: float) -> void:
	if a == b or a == "" or b == "":
		return
	_write(party, a, b, v, status(party, a, b))

# Every change comes through here, so a breakup is decided in exactly one place:
# lovers whose score reaches LOVERS_BREAK stop being lovers and take BREAKUP on
# top, because that is worse than never having been.
static func adjust(party, a: String, b: String, delta: float) -> Dictionary:
	if a == b or a == "" or b == "":
		return {}
	var s := score(party, a, b) + delta
	var st := status(party, a, b)
	var broke := false
	if st == "lovers" and s <= LOVERS_BREAK:
		st = ""
		s -= BREAKUP
		broke = true
	_write(party, a, b, s, st)
	# T19: the bands this pair has just landed in. adjust() is the one door
	# every score change comes through, so this is the one place to watch it.
	match band(party, a, b):
		"bonded":
			Ach.unlock("bonded")
		"rivals":
			Ach.unlock("rivals")
	if broke:
		Ach.unlock("breakup")
	return {"score": score(party, a, b), "broke_up": broke}

static func band(party, a: String, b: String) -> String:
	if status(party, a, b) == "lovers":
		return "lovers"
	var s := score(party, a, b)
	if s <= RIVALS:
		return "rivals"
	if s <= COLD:
		return "cold"
	if s >= BONDED:
		return "bonded"
	if s >= WARM:
		return "warm"
	return "neutral"

# "Vera and Pike — rivals (-44)": the one line a party page needs per pair.
static func describe(party, a: String, b: String) -> String:
	var ca = party.get_member(a)
	var cb = party.get_member(b)
	if ca == null or cb == null:
		return ""
	return "%s and %s — %s (%+d)" % [ca.cname, cb.cname, band(party, a, b), int(round(score(party, a, b)))]

# --- who is close to whom --------------------------------------------------------

static func pairs(ids: Array) -> Array:
	var out: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			out.append([String(ids[i]), String(ids[j])])
	return out

static func active_pairs(party) -> Array:
	return pairs(Array(party.active))

static func is_close(party, a: String, b: String) -> bool:
	return band(party, a, b) in ["bonded", "lovers"]

static func is_rival(party, a: String, b: String) -> bool:
	return band(party, a, b) == "rivals"

# The lover, or "" — one at a time (see the doc for why that is the default).
static func partner(party, id: String) -> String:
	for ch in party.roster:
		if ch.id != id and status(party, id, ch.id) == "lovers":
			return ch.id
	return ""

# Everybody in the roster this person is bonded to or in love with.
static func close_to(party, id: String) -> Array:
	var out: Array = []
	for ch in party.roster:
		if ch.id != id and is_close(party, id, ch.id):
			out.append(ch.id)
	return out

static func rivals_of(party, id: String) -> Array:
	var out: Array = []
	for ch in party.roster:
		if ch.id != id and is_rival(party, id, ch.id):
			out.append(ch.id)
	return out

# --- the two questions the overworld asks -----------------------------------------

# The mood of the marching order: the mean of every pair among the active
# party, cut into three. A party of one has nobody to get on with.
static func morale(party) -> int:
	var ps := active_pairs(party)
	if ps.is_empty():
		return 0
	var total := 0.0
	for p in ps:
		total += score(party, p[0], p[1])
	var mean := total / ps.size()
	if mean >= WARM:
		return 1
	if mean <= COLD:
		return -1
	return 0

# Added to every road check's bonus, next to Travel.pace_bonus(). A party that
# likes itself reads the road a little better; one that does not, worse.
static func travel_bonus(party) -> int:
	return morale(party)

# --- events: what moves a pair --------------------------------------------------

static func saved(party, saver: String, saved_id: String) -> Dictionary:
	return adjust(party, saver, saved_id, SAVED)

static func friendly_fire(party, caster: String, victim: String) -> Dictionary:
	Ach.unlock("friendly_fire")
	return adjust(party, caster, victim, -FRIENDLY_FIRE)

# A won fight: everyone still standing at the end of it warms to everyone else
# who was. Not the dead, and not the downed — "we came through that together"
# is only true of the ones who did.
static func fought_beside(party, standing: Array) -> void:
	for p in pairs(standing):
		adjust(party, p[0], p[1], FOUGHT_BESIDE)

# A D3 road event resolved by `roller`. A pass earns a little from everyone else
# marching; a failed "bad" event — the kind that costs the party something —
# costs the roller a little with each of them. A failed "good" event is nobody's
# fault: the cache was just not there.
static func road_result(party, roller: String, ok: bool, kind: String) -> void:
	if roller == "":
		return
	for id in party.active:
		if String(id) == roller:
			continue
		if ok:
			adjust(party, roller, String(id), ROAD_PASS)
		elif kind == "bad":
			adjust(party, roller, String(id), -ROAD_FAIL)

# Slow drift toward the pair's baseline — not toward 0. Only recorded pairs
# move; an unrecorded one is at baseline by definition. `dt` is world-minutes,
# so a paused clock drifts nothing, same contract as FactionOpinion.decay.
static func decay(party, dt: float) -> void:
	if dt <= 0.0:
		return
	var step := DRIFT_PER_DAY * dt / DAY
	for k in party.relations.keys():
		var ids: PackedStringArray = String(k).split("|")
		if ids.size() != 2:
			continue
		var ca = party.get_member(ids[0])
		var cb = party.get_member(ids[1])
		if ca == null or cb == null:
			continue
		var e: Dictionary = party.relations[k]
		e["score"] = move_toward(float(e["score"]), baseline(ca, cb), step)

# --- camp: the fireside beat -----------------------------------------------------

# Courtship can be offered when the pair is already past BONDED, neither is
# spoken for, both are alive, and this pair has not already said no.
static func courtship_possible(party, a: String, b: String) -> bool:
	if a == b or status(party, a, b) != "":
		return false
	var ca = party.get_member(a)
	var cb = party.get_member(b)
	if ca == null or cb == null or ca.dead or cb.dead:
		return false
	if partner(party, a) != "" or partner(party, b) != "":
		return false
	return score(party, a, b) >= COURTSHIP_MIN

const LINES := {
	"warming": [
		"%s and %s sit up past the others, talking about nothing in particular.",
		"%s shows %s how to do the thing properly. It takes most of the evening.",
		"%s and %s share the last of the good wine and say nothing about it to anyone.",
	],
	"quarrel": [
		"%s and %s have it out over the fire, and the rest of the camp pretends to sleep.",
		"Something %s said this morning is still sitting wrong with %s.",
		"%s takes the last watch rather than share the first with %s.",
	],
	"courtship": [
		"%s waits until the others are asleep, and asks %s to walk a little way from the fire.",
		"%s has been not-saying something to %s for a week now. Tonight it gets said.",
	],
}

# A long rest's one beat, or {} — the same self-resolving shape as a road event
# for warming and quarrel, and the ASKING shape (D4's "options") for courtship.
# The pair is drawn from the active party; a quarrel is likelier between people
# who already do not get on, a warming between people who do, so a camp pushes
# a pair the way it is already leaning rather than scattering it.
static func camp_moment(party, rng) -> Dictionary:
	var ps: Array = active_pairs(party).filter(func(p):
		var ca = party.get_member(p[0])
		var cb = party.get_member(p[1])
		return ca != null and cb != null and not ca.dead and not cb.dead)
	if ps.is_empty() or rng.roll_die(100) > MOMENT_CHANCE_PCT:
		return {}
	var p: Array = ps[rng.roll_die(ps.size()) - 1]
	var a := String(p[0])
	var b := String(p[1])
	var out := {"a": a, "b": b, "a_name": party.get_member(a).cname, "b_name": party.get_member(b).cname}
	if courtship_possible(party, a, b) and rng.roll_die(100) <= COURTSHIP_CHANCE_PCT:
		out["kind"] = "courtship"
		out["options"] = ["accept", "decline"]
		out["text"] = _line(rng, "courtship") % [out["a_name"], out["b_name"]]
		return out
	var leaning_bad: bool = score(party, a, b) < 0.0
	var quarrel: bool = rng.roll_die(100) <= (60 if leaning_bad else 30)
	out["kind"] = "quarrel" if quarrel else "warming"
	out["delta"] = -CAMP_QUARREL if quarrel else CAMP_WARMING
	out["text"] = _line(rng, out["kind"]) % [out["a_name"], out["b_name"]]
	var r := adjust(party, a, b, float(out["delta"]))
	out["score"] = r.get("score", score(party, a, b))
	out["broke_up"] = bool(r.get("broke_up", false))
	out["band"] = band(party, a, b)
	return out

static func _line(rng, kind: String) -> String:
	var ls: Array = LINES[kind]
	return String(ls[rng.roll_die(ls.size()) - 1])

# The player's answer to a courtship card. Accepting makes them lovers and
# warms the pair; declining marks the pair so the fire never asks again, and
# costs a little — it is awkward for a while.
static func answer_courtship(party, a: String, b: String, accepted: bool) -> Dictionary:
	if not courtship_possible(party, a, b):
		return {}
	if accepted:
		_write(party, a, b, score(party, a, b) + COURTSHIP_ACCEPTED, "lovers")
		Ach.unlock("lovers")
	else:
		_write(party, a, b, score(party, a, b) - COURTSHIP_DECLINED, "declined")
	return {"score": score(party, a, b), "status": status(party, a, b), "band": band(party, a, b)}

# --- combat: three hooks ----------------------------------------------------------
#
# Each takes the Combat (for allies_of and positions) and a Combatant whose `id`
# is a member id — Adapter.to_combatant copies it — and answers one question.
# Foes have no relations and get 0 from all three.

# Bonded or lovers standing next to each other: +SHOULDER_AC each. Reads like
# cover, and is worth the same as half cover's +2 only when both are in it.
static func shoulder_bonus(party, c, cb) -> int:
	if c.team != "party":
		return 0
	for ally in cb.allies_of(c):
		if ally != c and ally.conscious() and Hex.distance(ally.pos, c.pos) <= 1 \
				and is_close(party, c.id, ally.id):
			return SHOULDER_AC
	return 0

# Rivals standing next to each other: -BICKER_TO_HIT each, on every swing.
static func bicker_penalty(party, c, cb) -> int:
	if c.team != "party":
		return 0
	for ally in cb.allies_of(c):
		if ally != c and ally.conscious() and Hex.distance(ally.pos, c.pos) <= 1 \
				and is_rival(party, c.id, ally.id):
			return BICKER_TO_HIT
	return 0

# `fallen` just hit 0 HP. Everyone close to them who can still swing gets
# RALLY_STATUS: advantage on their next attack, spent by that attack. Its own
# status rather than Help's "helped" because "helped" belongs to a helper (it
# lapses at that helper's next turn, combat._release_helps) and a rally has none.
static func rally(party, fallen, cb) -> Array:
	var out: Array = []
	if fallen.team != "party":
		return out
	for ally in cb.allies_of(fallen):
		if ally != fallen and ally.conscious() and is_close(party, fallen.id, ally.id):
			ally.statuses[RALLY_STATUS] = true
			out.append(ally.id)
	return out

# --- persistence -------------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.relations.duplicate(true)

static func from_dict(party, d) -> void:
	party.relations = {}
	if not d is Dictionary:
		return
	for k in d:
		var e = d[k]
		var ids: PackedStringArray = String(k).split("|")
		if ids.size() != 2 or ids[0] == ids[1] or not (e is Dictionary and e.has("score")):
			continue
		# Re-keyed through _pair_key so a hand-edited "vera|pike" reads the same as
		# the "pike|vera" this file would have written.
		_write(party, ids[0], ids[1], float(e["score"]), String(e.get("status", "")))
