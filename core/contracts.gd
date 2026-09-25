# Contracts — who hires the company, and for what (the owner's call,
# 2026-09-24: "factions post contracts, and standing with each faction decides
# who hires you").
#
#   Contracts.open("raid_settlement", "dwarf")      # would the dwarves hand us this?
#   Contracts.why_closed("raid_settlement", "dwarf") # ...and if not, the line that says why
#   Contracts.pay_mult("dwarf")                     # what their regard is worth on the purse
#   Contracts.credit(quest, "elf")                  # a job handed in: who it counts for
#
# Every job on a board was already posted by somebody. What a job never said was
# WHOSE it was: Quest.turn_in credited the faction of the town it was handed in
# at, so a dwarven bounty cashed at an elven inn made the elves like you more
# and taught the dwarves nothing. A job now carries its `issuer` — the people
# of the settlement that posted it — and, when it is aimed at somebody, who it
# is `against`. Handing it in anywhere pays the issuer's regard and deeds.
#
# Standing decides the rest, on the two readings the game already keeps:
#   the ladder (core/ladder.gd) — deeds, never lost: what you have DONE for them.
#     War work (a raid on a settlement) waits until they know you.
#   opinion (core/faction_opinion.gd) — their mood, which drifts: whether they
#     will trust you with killing today. Bounty and war work wait for at least
#     neutral; everything else stays open down to QUEST_MIN, as the board did.
# And regard pays: pay_mult() scales a job's gold with their opinion, on top of
# the renown premium every job already gets (Ladder.pay_mult()).
#
# It does NOT own: which counter posts which kind, or how far a town's interest
# reaches (core/quest_posting.gd), what a quest is or how it progresses
# (core/quest.gd), or any drawing (scenes/world/world.gd's notice board).
extends RefCounted

const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ladder = preload("res://core/ladder.gd")
const WorldAI = preload("res://core/world_ai.gd")

# {kind: {rung, opinion}} — the least a people must think of you before they
# post this kind of job. A kind not listed is open to anyone the board is open
# to (opinion above FactionOpinion.QUEST_MIN), which is every job there was
# before contracts.
const GATE := {
	"hunt_party": {"rung": 0, "opinion": 0.0},
	"raid_settlement": {"rung": Ladder.KNOWN, "opinion": 0.0},
}

# TUNING — a taste number, not a measured one: gold is outside every sweep this
# project runs (world.gd's PURSE ponytail says the same of a caravan). +25% at
# +100 opinion, -6% at the QUEST_MIN floor; with the renown premium's +40% at
# Legends a job tops out at x1.75. It moves the gold only: a job's XP is the
# posting country's fights' worth (Quest.XP_FIGHTS, 2026-09-25), so standing
# can no longer carry XP past the region bands' level ranges.
const STANDING_PAY := 0.25
# What a job against a civilized people costs you with them: a band of theirs
# killed (FactionOpinion.KILLED_THEIRS), since that is what it was.
const AGAINST_COST := FactionOpinion.KILLED_THEIRS

static func gate(kind: String) -> Dictionary:
	return GATE.get(kind, {"rung": 0, "opinion": FactionOpinion.QUEST_MIN})

static func open(kind: String, faction: String) -> bool:
	var g := gate(kind)
	if Ladder.rung(faction) < int(g["rung"]):
		return false
	var op: float = FactionOpinion.get_opinion(faction)
	# The ungated floor is the board's own (quest_posting: "<= QUEST_MIN has no
	# work"), so it is exclusive; a named gate is inclusive — neutral is enough.
	return op > float(g["opinion"]) if not GATE.has(kind) else op >= float(g["opinion"])

# The line the notice board shows for a kind this people will not post you,
# "" when they will.
static func why_closed(kind: String, faction: String) -> String:
	if open(kind, faction):
		return ""
	var g := gate(kind)
	var who: String = Ladder.people(faction)
	var work := String(WORK.get(kind, "That work"))
	if Ladder.rung(faction) < int(g["rung"]):
		return "%s goes to those the %s know — %s, at %d deeds (you have %d)." % [work, who,
			String(Ladder.RUNGS[int(g["rung"])]), int(Ladder.RUNG_AT[int(g["rung"])]), Ladder.deeds(faction)]
	return "%s waits until the %s think better of you." % [work, who]

const WORK := {"hunt_party": "Bounty work", "raid_settlement": "War work"}

# Their regard, as a multiplier on a job's gold. Clamped at the board's floor,
# since below it there is no job to pay for.
static func pay_mult(faction: String) -> float:
	var op: float = clampf(FactionOpinion.get_opinion(faction), FactionOpinion.QUEST_MIN, FactionOpinion.RANGE)
	return 1.0 + STANDING_PAY * op / FactionOpinion.RANGE

# Stamp a freshly posted job with who posted it and who it is aimed at.
static func stamp(q: Dictionary, issuer: String) -> void:
	q["issuer"] = issuer
	q["against"] = String(q.get("chain_faction", ""))

# A job handed in: the issuer's regard and a deed, whoever's counter took it.
# `fallback` is the hand-in town's people, for a job posted before contracts
# carried an issuer — exactly what turn_in credited before. A job against a
# civilized people costs you with them; a monster faction keeps no opinion.
# Returns the faction credited ("" for none).
static func credit(q: Dictionary, fallback: String) -> String:
	var issuer := String(q.get("issuer", fallback))
	if issuer != "":
		FactionOpinion.raise(issuer, FactionOpinion.QUEST_DONE)
		Ladder.deed(issuer)
	var against := String(q.get("against", ""))
	if against != "" and against != issuer and WorldAI.CIVILIZED.has(against):
		FactionOpinion.lower(against, AGAINST_COST)
	return issuer
