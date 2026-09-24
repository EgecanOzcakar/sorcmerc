# T9x: "shorter rest" characters — matches 5e's elf Trance (feature id
# "elf-trance" in data/species.json), keyed off any feature id in
# TRANCE_FEATURES rather than the race name, so a subclass or homebrew
# feature granting the same thing works identically — same "features are a
# generic bag of flags" contract core/rules/resolved.gd already uses
# everywhere (has_feature()).
#
# RAW Trance doesn't shorten the PARTY's rest — everyone else still sleeps
# their 8 hours, so the world clock cost is untouched. It's what the Trance
# character does with their own spare hours while camp sleeps. Bundled here
# as one automatic bonus rather than a player-facing menu — every idea from
# the brief, applied together whenever eligible, no new UI to build or teach.
#
# Audit 4.3 (docs/audit-game-design.md): the short-rest top-up used to run the
# moment the long rest ended, when everyone was already full, so it did
# nothing at all. It is BANKED instead: a long rest with a Trance hero in the
# company leaves one free short rest on the party (party.trance_rest_until),
# good until the next long rest or for a day, whichever comes first. The
# company's next short rest spends it before the two RAW allows per long
# rest, and never counts against them (core/settlement_visit.gd's rest()).
#
#   Trance.bank(party, now)      # at a long rest: banks one, or clears a stale one
#   Trance.banked(party, now)    # is there one to take?
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Ach = preload("res://core/achievements.gd")

const TRANCE_FEATURES := ["elf-trance"]
const WATCH_BONUS := 5             # core/world_camp.gd's watch_check: sharper eyes on the ambush roll
const IDENTIFY_SKILL := "arcana"
const SCOUT_MULT := 1.8            # how far past World.VISION_RADIUS the extra reveal points sit
const BANK_MINUTES := 1440.0       # the banked short rest keeps for a day (and no later than the next long rest)

static func has_trance(party) -> bool:
	for ch in party.party_characters():
		var s = ch.sheet()
		for fid in TRANCE_FEATURES:
			if s.has_feature(fid):
				return true
	return false

# Every long rest calls this (core/settlement_visit.gd's rest(), so the inn,
# the camp and a downtime stay all bank alike). A long rest ends the old bank
# whether or not it starts a new one: a rest banked yesterday and not taken is
# gone, never stacked.
static func bank(party, now: float) -> bool:
	party.trance_rest_until = now + BANK_MINUTES if has_trance(party) else -1.0
	return party.trance_rest_until >= 0.0

static func banked(party, now: float) -> bool:
	return party.trance_rest_until >= 0.0 and now < party.trance_rest_until

# Spend the banked rest. False (and nothing changed) when there is none.
static func take(party, now: float) -> bool:
	if not banked(party, now):
		return false
	party.trance_rest_until = -1.0
	return true

# Applied once after a long rest on the map actually happens (the inn and the
# camp; the rest itself has already banked the short rest above):
#  - the surrounding area gets scouted a bit past the normal reveal radius
#  - one free shot at identifying a mystery item, off the same Arcana math
#    core/campaign.gd's own identify check uses
# A no-op (returns {}) when nobody in the party has the feature.
static func apply_rest_bonus(party, world, pos: Vector2, rng = null) -> Dictionary:
	if not has_trance(party):
		return {}
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		world.reveal(pos + d * world.VISION_RADIUS * SCOUT_MULT)
	return {"banked": banked(party, world.clock.elapsed), "scouted": true, "identify": _try_identify(party, rng)}

# {} when there's nothing unidentified to try. Otherwise the full roll
# breakdown — same shape as every other check in this session
# (WorldLairs.search, WorldCamp.watch_check) — so the caller can narrate
# exactly what was rolled and how it went, not just "something happened".
static func _try_identify(party, rng = null) -> Dictionary:
	var mystery: Array = party.unidentified()
	if mystery.is_empty():
		return {}
	var item_id := String(mystery[0]["item_id"])
	var c = Campaign.new(party)
	var char_id: String = c.best_at(IDENTIFY_SKILL)
	if char_id == "":
		return {}
	var bonus: int = c.skill_bonus(char_id, IDENTIFY_SKILL)
	var dc: int = Campaign.identify_dc(item_id)
	if rng == null:
		rng = RNG.new()
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= dc
	if ok:
		party.stash_identify(item_id)
		Campaign._note_identified(item_id)
		Ach.unlock("trance_identify")
	return {"ok": ok, "item_id": item_id, "char_id": char_id, "skill": IDENTIFY_SKILL,
		"nat": nat, "bonus": bonus, "dc": dc}
