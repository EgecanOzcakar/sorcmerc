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
#   PartyOpinion.camp_moment(party, rng, true)     # ...at an inn or the lodge, where the bench sits in too
#   PartyOpinion.decay(party, dt_minutes)          # drift toward the pair's baseline
#
# Three things decided here that shape everything else:
#
#  1. It lives on the Party (party.relations), not in a static like
#     FactionOpinion's. A faction has exactly one live world; a relationship is
#     between two saved characters and has to round-trip with them.
#  2. Drift goes toward a BASELINE, not toward 0. sorcmerc has no authored
#     companions — the founder is made in the creator and everyone after is a
#     hire rolled at an inn (core/recruits.gd) — so the only "personality" a pair
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
const Traits = preload("res://core/traits.gd")   # #176 step 4: temperaments and a few traits pull on the baseline
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
	# #176 step 4 (spec §7): +5 per temperament shared, −10 per opposed pair,
	# and what a Greedy or Arrogant hero costs with the others. Drift already
	# pulls every pair toward this, so two Wrathful fighters warm to each other
	# on the road with no new machinery.
	v += float(Traits.opinion_terms(ca, cb)["n"])
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
	var line := "%s and %s — %s (%+d)" % [ca.cname, cb.cname, band(party, a, b), int(round(score(party, a, b)))]
	# #176 step 4 (spec §8): name the traits behind the pull — "...: Brave and
	# Craven" — so a cold pair the road has not explained is not a mystery.
	var why: Array = Traits.opinion_terms(ca, cb)["why"]
	return line + (": " + ", ".join(why) if not why.is_empty() else "")

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
	# #176 step 4: from a Wrathful caster it looks deliberate — half again.
	var hot: bool = Traits.has(party.get_member(caster), "wrathful")
	return adjust(party, caster, victim, -FRIENDLY_FIRE * (Traits.WRATHFUL_FIRE if hot else 1.0))

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
		var target := baseline(ca, cb)
		# #176 step 4: Generous — opinion of them warms a day faster (the drift
		# up, never the drift down).
		var s := step * 2.0 if target > float(e["score"]) and Traits.warms_faster(ca, cb) else step
		e["score"] = move_toward(float(e["score"]), target, s)

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

# The fire's lines (the design audit, docs/audit-game-design.md §2.6). Until
# 2026-09-25 there were eight in all — three warmings, three quarrels, two
# courtships — at up to one a long rest, so a long campaign heard each of them
# a dozen times, whoever sat at the fire. Now the pair's TEMPERAMENTS pick them
# (data/traits.json's `temperament` family), from three layers put together:
#
#   PAIR_LINES    the pairings that mean something on their own: the four
#                 opposed pairs (Brave and Craven, Calm and Wrathful, Generous
#                 and Greedy, Cautious and Curious) and the eight where both
#                 hold the same temperament;
#   TEMPER_LINES  what each temperament does at a fire, with whoever — three of
#                 each kind, so any pairing at all draws from six of its own
#                 (three from each side), plus the pair's own if it has some;
#   LINES         the old eight, spoken for whichever side holds no temperament
#                 this file has lines for (a hero from before traits, or one a
#                 content pack added) — the whole pool when neither side does.
#
# A line says {a} and {b}. In TEMPER_LINES {a} is the one who holds that
# temperament; in PAIR_LINES {a} holds the first of the key's two (the key is
# sorted, as _pair_key builds it), and either for a same-temperament pair. In a
# courtship {a} is always the one who asks — the card's answer line reads the
# moment's "a" as the asker (scenes/world/world.gd's _on_courtship_chosen), so
# a line that puts the other one in {a} swaps the pair round to match.
const LINES := {
	"warming": [
		"{a} and {b} sit up past the others, talking about nothing in particular.",
		"{a} shows {b} how to do the thing properly. It takes most of the evening.",
		"{a} and {b} share the last of the good wine and say nothing about it to anyone.",
	],
	"quarrel": [
		"{a} and {b} have it out over the fire, and the rest of the camp pretends to sleep.",
		"Something {b} said this morning is still sitting wrong with {a}.",
		"{a} takes the last watch rather than share the first with {b}.",
	],
	"courtship": [
		"{a} waits until the others are asleep, and asks {b} to walk a little way from the fire.",
		"{a} has been not-saying something to {b} for a week now. Tonight it gets said.",
	],
}

const TEMPER_LINES := {
	"brave": {
		"warming": [
			"{a} takes {b}'s watch as well as their own, and does not mention it in the morning.",
			"{a} tells {b} about the worst fight they ever walked into. {b} tells a worse one. They are up late.",
			"{b} asks {a} how they keep walking forward. {a} thinks about it a long while and says they do not know.",
		],
		"quarrel": [
			"{a} says {b} hung back today. {b} says somebody has to live long enough to bury the brave.",
			"{a} wants to go straight at the next one. {b} does not, and says so, and it goes on for an hour.",
			"{a} calls {b} careful as if it were an insult. {b} takes it as one.",
		],
		"courtship": [
			"{a} has walked at a great many things. Tonight, by the fire, {a} walks over to {b}.",
			"{a} asks {b} plainly, the way {a} does everything, whether they might walk a way from the fire.",
		],
	},
	"craven": {
		"warming": [
			"{a} admits to {b} how frightened they were today. {b} admits it too. It helps.",
			"{a} shows {b} the best way out of every place they have camped. {b} is quietly grateful.",
			"{b} catches {a} checking that everyone is still breathing, twice, and says nothing about it.",
		],
		"quarrel": [
			"{b} says {a} ran. {a} says they went for help. Neither of them believes the other.",
			"{a} wants to turn back. {b} will not hear of it, and the whole camp hears them not hearing it.",
			"{a} was nowhere near {b} when it counted, and {b} has not forgotten.",
		],
		"courtship": [
			"{a} has been working up to it for days and nearly runs again. Nearly. Then asks {b} to sit a while away from the fire.",
			"{a} tells {b} all at once and much too fast, and then waits for the answer with both eyes shut.",
		],
	},
	"wrathful": {
		"warming": [
			"{a} is still angry about today. {b} sits with them until they are not.",
			"{b} says the one thing that sets {a} laughing instead of shouting, which nobody else has managed.",
			"{a} went after the one who hurt {b} in the fight. Tonight {b} brings {a} the good end of the bread.",
		],
		"quarrel": [
			"{a} and {b} are shouting before the fire is lit. It does not get better once it is.",
			"{a} says something to {b} they will regret. {b} makes sure they do.",
			"{b} tells {a} to calm down, which has never once worked on {a} and does not work tonight.",
		],
		"courtship": [
			"{a} has never said a soft word to anyone in the company. Tonight {a} says one to {b}, and asks them to walk.",
			"{a} storms off from the fire. After a while {b} follows, and finds {a} waiting to ask.",
		],
	},
	"calm": {
		"warming": [
			"{a} cleans {b}'s cut without being asked. It is done well, and neither of them says much.",
			"{b} cannot sleep. {a} stays up and talks about nothing until they can.",
			"{a} and {b} keep the fire between them, saying nothing, and that is the whole evening.",
		],
		"quarrel": [
			"{a} will not raise their voice at {b}, which makes {b} raise theirs.",
			"{a} points out, very quietly, every mistake {b} made today. {b} takes it badly.",
			"{b} wants {a} to be angry about something. {a} will not be, and that is worse.",
		],
		"courtship": [
			"{a} waits until the camp is asleep and then asks {b}, quite simply, to walk a little way from the fire.",
			"{a} has thought for a week about how to say it. In the end {a} just says it to {b}.",
		],
	},
	"greedy": {
		"warming": [
			"{a} slips {b} a share of the take that was not in the count. {b} notices, and remembers.",
			"{a} and {b} go through the day's haul together and agree on everything, which is rare.",
			"{a} shows {b} how to tell good silver from bad. It takes the whole evening.",
		],
		"quarrel": [
			"{a} and {b} count the purse twice and get two different sums. It goes on long after the fire is out.",
			"{b} catches {a} weighing a ring that was meant for the pot.",
			"{a} says {b} gave away too much at the last town. {b} says it was never {a}'s to keep.",
		],
		"courtship": [
			"{a} offers {b} the best thing out of the last haul and asks nothing for it. Then asks for a walk.",
			"{a} has counted a great many things. Tonight {a} tells {b} they are the one {a} counts on.",
		],
	},
	"generous": {
		"warming": [
			"{a} gives {b} the last of the stew and says they were not hungry. {b} knows better.",
			"{a} mends {b}'s torn cloak by the fire. {b} did not ask, and does not forget.",
			"{a} shares a flask with {b}, and then a story, and then most of the night.",
		],
		"quarrel": [
			"{a} gave away something that was half {b}'s. {b} has not let it go.",
			"{b} says {a} cannot save everyone. {a} says watch me. It gets loud.",
			"{a} is hurt that {b} will not take the help. {b} is tired of being helped.",
		],
		"courtship": [
			"{a} brings {b} a cup of something warm, sits down beside them, and asks them to walk a little way off.",
			"{a} has given everyone something since they signed on. Tonight {a} asks {b} for something.",
		],
	},
	"curious": {
		"warming": [
			"{a} asks {b} a hundred questions about home. {b} answers most of them, and is glad somebody asked.",
			"{a} and {b} take apart something from the last fight, and very nearly put it back together.",
			"{b} tells {a} a story nobody else has heard. {a} listens to all of it.",
		],
		"quarrel": [
			"{a} opened the box {b} said to leave. {b} is still talking about it.",
			"{a} will not stop asking {b} about the scar. {b} will not stop not answering.",
			"{a} read something of {b}'s that was not meant for reading.",
		],
		"courtship": [
			"{a} has asked {b} about everything but this. Tonight {a} asks about this.",
			"{a} wants to know what {b} thinks of them. So {a} asks, away from the fire.",
		],
	},
	"cautious": {
		"warming": [
			"{a} checks {b}'s bedroll for scorpions without being asked. {b} pretends not to notice, and is touched.",
			"{a} and {b} walk the edge of the camp together, twice, and talk the whole way round.",
			"{a} shows {b} how they pack: everything where a hand can find it in the dark. {b} copies it.",
		],
		"quarrel": [
			"{a} says {b} walked the company into that. {b} says {a} would have them never walk anywhere.",
			"{b} laughs at {a} for checking the camp a third time. {a} does not laugh.",
			"{a} wants to wait a day. {b} does not. Neither of them sleeps much.",
		],
		"courtship": [
			"{a} has turned it over for weeks, looking for the trap in it. Tonight {a} asks {b} anyway.",
			"{a} makes sure the others are asleep, twice, and then asks {b} to walk a little way from the fire.",
		],
	},
}

const PAIR_LINES := {
	"brave|craven": {   # {a} Brave, {b} Craven
		"warming": [
			"{a} tells {b} everyone is afraid, and the trick is to walk anyway. {b} says the trick is to walk the other way. They both laugh.",
			"{b} pulled {a} back from something stupid today. {a} says thank you, and means it.",
		],
		"quarrel": [
			"{a} calls {b} a coward over the fire. {b} says a coward will at least be alive to hear it again.",
			"{b} will not follow {a} in first again. {a} takes it as desertion.",
		],
		"courtship": [
			"{a} walks toward {b} the way {a} walks toward everything, and asks. {b} had been hoping.",
		],
	},
	"calm|wrathful": {   # {a} Calm, {b} Wrathful
		"warming": [
			"{b} comes back to the fire still shaking with it. {a} hands over a cup and waits, and it passes.",
			"{a} is the only one {b} will listen to when the blood is up. Tonight {b} says so.",
		],
		"quarrel": [
			"{b} shouts. {a} does not. By the end of it {b} is shouting at {a} for not shouting.",
			"{a} tells {b} that temper will get somebody killed. {b} does not take it calmly.",
		],
		"courtship": [
			"{a} has watched {b} burn for weeks and never once stepped back. Tonight {a} asks {b} to walk away from the fire.",
		],
	},
	"generous|greedy": {   # {a} Generous, {b} Greedy
		"warming": [
			"{b} catches {a} giving away the last coin in the purse, and tops it up out of their own. Nobody sees but {a}.",
			"{a} gives {b} half the bread. {b} weighs it, then gives a bit back.",
		],
		"quarrel": [
			"{a} gave a farmer back his coin. {b} has not stopped counting what that cost.",
			"{b} says {a} is a soft touch who will beggar the company. {a} says {b} would sell the fire.",
		],
		"courtship": [
			"{a} tells {b} they would give them anything. {b}, for once, does not haggle.",
		],
	},
	"cautious|curious": {   # {a} Cautious, {b} Curious
		"warming": [
			"{b} wants to know why {a} checks everything twice. {a} explains, and {b} listens to every word.",
			"{a} kept {b} from opening the wrong door today. Tonight {b} brings {a} the first cup.",
		],
		"quarrel": [
			"{b} opened it. {a} said not to. The camp hears about it until the fire is out.",
			"{a} says {b}'s questions will get them all killed. {b} asks what {a} means by that.",
		],
		"courtship": [
			"{a} has looked at it from every side and found nothing wrong with it. Tonight {a} asks {b} to walk.",
		],
	},
	"brave|brave": {
		"warming": [
			"{a} and {b} argue over who goes in first tomorrow, and both enjoy it.",
			"{a} and {b} compare scars by the fire until the others beg them to stop.",
		],
		"quarrel": [
			"{a} and {b} both went in first today and nearly cut each other down. Neither will admit fault.",
			"{a} says {b} is reckless. {b} says {a} is jealous.",
		],
		"courtship": ["Neither {a} nor {b} has ever backed down from anything. Tonight {a} does not back down from asking."],
	},
	"craven|craven": {
		"warming": [
			"{a} and {b} agree that the whole business is madness, and feel much better for it.",
			"{a} and {b} plan three different ways out of tomorrow. It is the best evening either has had.",
		],
		"quarrel": [
			"{a} and {b} each say the other ran first. They both did.",
			"{a} and {b} argue over who has to take the dark watch. Nobody wins.",
		],
		"courtship": ["{a} and {b} have both been too frightened to say it. Tonight {a} is slightly less frightened."],
	},
	"wrathful|wrathful": {
		"warming": [
			"{a} and {b} spend the evening agreeing about who they would like to hit. It is warm, in its way.",
			"{a} and {b} have a shouting match that ends with both of them laughing.",
		],
		"quarrel": [
			"{a} and {b} have it out, loudly, and the rest of the camp moves its bedrolls.",
			"It takes two to break a pot. {a} and {b} manage three.",
		],
		"courtship": ["{a} and {b} fight about it first, of course. Then {a} asks, and it is a much quieter question."],
	},
	"calm|calm": {
		"warming": [
			"{a} and {b} keep the fire together without a word between them. It is a good night.",
			"{a} and {b} talk through tomorrow, slowly and properly, and both sleep well.",
		],
		"quarrel": [
			"{a} and {b} disagree, very politely, for two hours. It is somehow worse than shouting.",
			"{a} tells {b}, quietly, that they are wrong. {b} tells {a}, quietly, the same.",
		],
		"courtship": ["{a} and {b} have been circling it calmly for weeks. Tonight {a} simply asks."],
	},
	"greedy|greedy": {
		"warming": [
			"{a} and {b} divide the take down to the copper, and both are pleased with it.",
			"{a} and {b} spend the night planning what they will buy. It is a long list.",
		],
		"quarrel": [
			"{a} and {b} each think the other took the larger share. They are both right.",
			"{a} and {b} fight over one silver cup until somebody takes it off them both.",
		],
		"courtship": ["{a} has priced everything in the company. Tonight {a} tells {b} they are the one thing not for sale."],
	},
	"generous|generous": {
		"warming": [
			"{a} and {b} each try to give the other the last of the bread. It goes cold between them.",
			"{a} and {b} spend the evening mending other people's kit, and talking.",
		],
		"quarrel": [
			"{a} and {b} fall out over who gave away the camp's blankets.",
			"{a} thinks {b} gives too much. {b} thinks the same of {a}. Both are hurt.",
		],
		"courtship": ["{a} and {b} have given each other everything but this. Tonight {a} asks."],
	},
	"curious|curious": {
		"warming": [
			"{a} and {b} stay up asking each other questions until the fire is ash.",
			"{a} and {b} take something apart together and are delighted with what is inside.",
		],
		"quarrel": [
			"{a} and {b} argue about what that thing in the last room was. Neither will let it go.",
			"{a} opened the box first. {b} wanted to. That is the whole of it, and it is enough.",
		],
		"courtship": ["{a} and {b} have wondered about it out loud for weeks. Tonight {a} stops wondering and asks."],
	},
	"cautious|cautious": {
		"warming": [
			"{a} and {b} check the camp together, twice, and agree on everything.",
			"{a} and {b} sit the watch together, saying very little and missing nothing.",
		],
		"quarrel": [
			"{a} and {b} disagree about which way is safer, and take the watch at opposite ends of the camp.",
			"{a} says {b} is careless. Nobody has ever called {b} careless before. It stings.",
		],
		"courtship": ["{a} and {b} have both been careful about this. Tonight {a} stops being careful."],
	},
}

# Every line this pair could hear for `kind`, as [line, swapped] — `swapped`
# true when {a} is `b`, the second member drawn. Built from the members'
# temperaments: the pairing's own lines, then each side's, then the old shared
# ones for a side with no temperament lines of its own.
static func lines_for(ca, cb, kind: String) -> Array:
	var ta := Traits.of(ca, "temperament") if ca != null else ""
	var tb := Traits.of(cb, "temperament") if cb != null else ""
	var out: Array = []
	var pk := _pair_key(ta, tb)
	for ln in PAIR_LINES.get(pk, {}).get(kind, []):
		out.append([String(ln), ta != tb and pk.get_slice("|", 0) != ta])
	for ln in TEMPER_LINES.get(ta, {}).get(kind, []):
		out.append([String(ln), false])
	if tb != ta:
		for ln in TEMPER_LINES.get(tb, {}).get(kind, []):
			out.append([String(ln), true])
	if not TEMPER_LINES.has(ta) or not TEMPER_LINES.has(tb):
		for ln in LINES[kind]:
			out.append([String(ln), false])
	return out

# Who can sit at this fire: the marching party on the road; at an inn or the
# lodge (`bench` true) the whole living roster, because the bench is under the
# same roof (the audit's §2.4b).
static func fireside_ids(party, bench := false) -> Array:
	var ids: Array = Array(party.active).map(func(i): return String(i))
	if bench:
		for ch in party.bench_list():
			ids.append(String(ch.id))
	return ids.filter(func(id):
		var ch = party.get_member(id)
		return ch != null and not ch.dead)

# A long rest's one beat, or {} — the same self-resolving shape as a road event
# for warming and quarrel, and the ASKING shape (D4's "options") for courtship.
# The pair is drawn from the marching party — and, at an inn or the lodge
# (`bench` true), from the benched too, who are sleeping under the same roof. A
# quarrel is likelier between people who already do not get on, a warming
# between people who do, so a camp pushes a pair the way it is already leaning
# rather than scattering it. The line is picked by the pair's temperaments
# (lines_for, above); "benched" names whichever of the two is not marching.
static func camp_moment(party, rng, bench := false) -> Dictionary:
	var ps: Array = pairs(fireside_ids(party, bench))
	if ps.is_empty() or rng.roll_die(100) > MOMENT_CHANCE_PCT:
		return {}
	var p: Array = ps[rng.roll_die(ps.size()) - 1]
	var a := String(p[0])
	var b := String(p[1])
	if courtship_possible(party, a, b) and rng.roll_die(100) <= COURTSHIP_CHANCE_PCT:
		var out := _moment(party, rng, a, b, "courtship")
		out["options"] = ["accept", "decline"]
		return out
	var leaning_bad: bool = score(party, a, b) < 0.0
	var quarrel: bool = rng.roll_die(100) <= (60 if leaning_bad else 30)
	var out := _moment(party, rng, a, b, "quarrel" if quarrel else "warming")
	out["delta"] = -CAMP_QUARREL if quarrel else CAMP_WARMING
	var r := adjust(party, a, b, float(out["delta"]))
	out["score"] = r.get("score", score(party, a, b))
	out["broke_up"] = bool(r.get("broke_up", false))
	out["band"] = band(party, a, b)
	return out

# The moment's who and words: one line off lines_for, and the pair turned round
# when that line puts the second of them in {a}, so "a" is always who {a} is —
# which for a courtship is the one who asks.
static func _moment(party, rng, a: String, b: String, kind: String) -> Dictionary:
	var pool := lines_for(party.get_member(a), party.get_member(b), kind)
	var pick: Array = pool[rng.roll_die(pool.size()) - 1]
	if bool(pick[1]):
		var t := a
		a = b
		b = t
	var out := {"a": a, "b": b, "a_name": party.get_member(a).cname, "b_name": party.get_member(b).cname,
		"kind": kind, "benched": [a, b].filter(func(id): return not party.is_active(id))}
	out["text"] = String(pick[0]).replace("{a}", out["a_name"]).replace("{b}", out["b_name"])
	return out

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
