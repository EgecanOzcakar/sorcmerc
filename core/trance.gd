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
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Adapter = preload("res://core/adapter.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Ach = preload("res://core/achievements.gd")

const TRANCE_FEATURES := ["elf-trance"]
const WATCH_BONUS := 5             # core/world_camp.gd's watch_check: sharper eyes on the ambush roll
const IDENTIFY_SKILL := "arcana"
const SCOUT_MULT := 1.8            # how far past World.VISION_RADIUS the extra reveal points sit

static func has_trance(party) -> bool:
	for ch in party.party_characters():
		var s = ch.sheet()
		for fid in TRANCE_FEATURES:
			if s.has_feature(fid):
				return true
	return false

# Applied once after a long rest actually happens (both the settlement inn
# and the camp-kit path route through core/settlement_visit.gd's rest()):
#  - a short-rest top-up for the whole party, on top of the long rest just taken
#  - the surrounding area gets scouted a bit past the normal reveal radius
#  - one free shot at identifying a mystery item, off the same Arcana math
#    core/campaign.gd's own identify check uses
# A no-op (returns {}) when nobody in the party has the feature.
static func apply_rest_bonus(party, world, pos: Vector2, rng = null) -> Dictionary:
	if not has_trance(party):
		return {}
	for ch in party.party_characters():
		Adapter.rest(ch, "short-rest")
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		world.reveal(pos + d * world.VISION_RADIUS * SCOUT_MULT)
	return {"topped_up": true, "scouted": true, "identify": _try_identify(party, rng)}

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
