# O7 — what each faction thinks of the player. One float per faction, -100..100,
# 0 = neutral/unknown. Raised by finished quests and by killing monsters that were
# threatening a faction's settlements; lowered by theft (O6's hook) and by killing
# a faction's own people; drifts slowly back toward 0 when nothing happens.
#
#   FactionOpinion.raise("soldier", 10.0) / .lower("soldier", 5.0)
#   FactionOpinion.get_opinion("soldier")
#   FactionOpinion.tick(world, dt_minutes)   # once a frame: drain O6's hook + decay
#   FactionOpinion.reset()                   # tests / new game
#
# The score lives in a static dictionary rather than on the World: the two readers
# that matter (WorldAI.is_hostile, SettlementVisit.market) are static functions
# reached from places that have no handle on anything else, and there is exactly
# one live world at a time.
# ponytail: process-global state, fine for a single-player game with one world.
# Hang it on World (and thread it through is_hostile) the day two worlds coexist.
extends RefCounted

const RANGE := 100.0            # clamp, both ways

# Thresholds, on the same -100..100 scale. Spaced so a player has to work at it:
# one theft (-5/-10) is noise, a run of them (or a fight with the faction's own
# parties, -8 a band) is what walks the score down past them.
const HOSTILE := -50.0          # guards attack on sight; roaming parties hunt you
const REFUSE_TRADE := -75.0     # ...and below that nobody will even sell to you
const QUEST_MIN := -25.0        # below this a settlement has no work for you
const QUEST_GENEROUS := 40.0    # ...above it they will hand you a neighbour's job

const PRICE_SWING := 0.4        # x1.4 at -100, x0.6 at +100, on top of O6's markup

# Raise/lower amounts for the events wired in this phase.
const QUEST_DONE := 10.0        # a finished quest, per faction of the giver
const FOUGHT_FOR := 5.0         # killed a monster band near their settlement
const KILLED_THEIRS := 8.0      # ...or killed one of their own bands
const HELP_RADIUS := 140.0      # "near their settlement" — O6's BATTLE_RADIUS

const DECAY_PER_DAY := 2.0      # points of drift back toward 0 per world-day
const DAY := 1440.0             # world-minutes in a day (scenes/world/world.gd's HUD)

static var _scores: Dictionary = {}

static func reset() -> void:
	_scores = {}

static func get_opinion(faction: String) -> float:
	return float(_scores.get(faction, 0.0))

static func set_opinion(faction: String, value: float) -> void:
	_scores[faction] = clampf(value, -RANGE, RANGE)

static func raise(faction: String, amount: float) -> void:
	set_opinion(faction, get_opinion(faction) + absf(amount))

static func lower(faction: String, amount: float) -> void:
	set_opinion(faction, get_opinion(faction) - absf(amount))

static func all() -> Dictionary:
	return _scores.duplicate()

# --- the three questions the rest of the game asks ---------------------------

static func is_hostile_to_player(faction: String) -> bool:
	return get_opinion(faction) <= HOSTILE

static func refuses_trade(faction: String) -> bool:
	return get_opinion(faction) <= REFUSE_TRADE

# What O6's markup gets multiplied by: dearer when they dislike you, cheaper when
# they don't. One line, no branch — 0 opinion is x1.0, which is O6 unchanged.
static func price_factor(faction: String) -> float:
	return 1.0 - PRICE_SWING * get_opinion(faction) / RANGE

# --- per-frame upkeep --------------------------------------------------------

# Drain O6's hook (Settlement.pending_opinion_delta) into the settlement's faction
# and zero it, then decay. `dt` is world-minutes, i.e. what World.clock.tick()
# returned — so a paused clock neither drains nor decays.
static func tick(world, dt: float) -> void:
	drain(world)
	decay(dt)

static func drain(world) -> void:
	for s in world.settlements:
		if s.pending_opinion_delta == 0.0:
			continue
		set_opinion(s.faction, get_opinion(s.faction) + s.pending_opinion_delta)
		s.pending_opinion_delta = 0.0

# Slow drift toward neutral. move_toward never overshoots 0, and a faction already
# at 0 is left out of the dictionary entirely.
static func decay(dt: float) -> void:
	if dt <= 0.0:
		return
	var step := DECAY_PER_DAY * dt / DAY
	for faction in _scores.keys():
		var v: float = _scores[faction]
		if v == 0.0:
			continue
		_scores[faction] = move_toward(v, 0.0, step)

# --- events ------------------------------------------------------------------

# The player won a fight at `at`: every civilized faction with a settlement close
# by hears about it. Used for "helped in a fight" (a monster band died) and, with a
# negative amount, for killing a faction's own people.
static func credit_fight(world, at: Vector2, amount: float, skip_faction := "",
		radius := HELP_RADIUS) -> Array:
	var moved: Array = []
	for s in world.settlements:
		if s.faction == skip_faction or moved.has(s.faction) \
				or s.position.distance_to(at) > radius:
			continue
		moved.append(s.faction)
		set_opinion(s.faction, get_opinion(s.faction) + amount)
	return moved
