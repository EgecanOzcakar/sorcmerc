# #231 — the monster peoples remember. A grudge, and only a grudge.
#
# Only the civilized peoples keep an opinion of the company (FactionOpinion):
# a monster people's bands were hostile whatever the company did, a failed
# parley cost nothing with them, and killing their bands moved no number
# anywhere (core/approach.gd's parley_costs_opinion, core/contracts.gd's
# credit(), world.gd's KILLED_THEIRS — all on purpose). #231 asks for "the
# opinion of all factions" to shape who the road sends, and the owner's call
# (2026-09-25) is the narrowest version of that: monster peoples hold a GRUDGE.
# Kill a people's bands and empty its lairs and it comes looking for you, in
# more and heavier bands (core/route_encounters.gd's grudge term). There is no
# other side to it — no truce, no tribute, no trade, no parley bonus — and it
# never feeds FactionOpinion, whose scores the ladder, the markets and the
# achievements all read and which a monster people must stay out of.
#
#   Grudges.add("gnoll", Grudges.BAND)     # a gnoll band put down
#   Grudges.get_grudge("gnoll")           # 0..100
#   Grudges.tick(dt_minutes)              # once a frame: the slow cooling
#   Grudges.all() / Grudges.load_all(d)   # the save (phase 1: world_save.gd, beside "opinion")
#
# Nothing calls add() yet: phase 1 wires the two deeds below where world.gd
# already credits FactionOpinion for a won fight and WorldLairs.loot empties a
# lair (docs/spike-route-travel.md §6).
#
# ponytail: process-global like FactionOpinion, for the same reason — one live
# world, and the readers are static. Move both onto World together.
extends RefCounted

const WorldAI = preload("res://core/world_ai.gd")

const MAX := 100.0
# What each deed adds. Taste numbers (spike, 2026-09-25), sized so a people
# notices a run of kills, not one: four bands and a lair is half of MAX.
const BAND := 10.0
const LAIR := 25.0
# Points of cooling per world-day, FactionOpinion.DECAY_PER_DAY's rate: a
# people forgets as slowly as a town does.
const DECAY_PER_DAY := 2.0
const DAY := 1440.0

static var _scores: Dictionary = {}

static func reset() -> void:
	_scores = {}

static func get_grudge(faction: String) -> float:
	return float(_scores.get(faction, 0.0))

# Only a monster people holds one; a civilized people's anger is FactionOpinion.
static func add(faction: String, amount: float) -> void:
	if faction == "" or not WorldAI.is_monster(faction):
		return
	_scores[faction] = clampf(get_grudge(faction) + absf(amount), 0.0, MAX)

static func set_grudge(faction: String, value: float) -> void:
	if faction == "" or not WorldAI.is_monster(faction):
		return
	if value <= 0.0:
		_scores.erase(faction)
	else:
		_scores[faction] = minf(value, MAX)

static func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	var step := DECAY_PER_DAY * dt / DAY
	for f in _scores.keys():
		var v: float = maxf(0.0, float(_scores[f]) - step)
		if v <= 0.0:
			_scores.erase(f)
		else:
			_scores[f] = v

static func all() -> Dictionary:
	return _scores.duplicate()

# Missing or junk entries read as no grudge, the rule every save follows.
static func load_all(d: Dictionary) -> void:
	reset()
	for f in d:
		set_grudge(String(f), float(d[f]))
