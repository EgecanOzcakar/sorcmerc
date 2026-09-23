# T9x: "make camp" — a purchasable item (CAMP_KIT) lets the party take a long
# rest anywhere on the map instead of only inside a settlement, at a small
# risk of a night ambush. A separate file from settlement_visit.gd because
# this is a skill-check + combat-launch decision, not a market transaction.
#
#   if WorldCamp.ambush_roll(rng):
#       var watch := WorldCamp.watch_check(party, rng)
#       ... launch combat, scouted_ahead = watch["ok"], forced_ambush = not watch["ok"]
#   else:
#       Visit.rest(party, world, "long-rest")
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Trance = preload("res://core/trance.gd")

const CAMP_KIT_ITEM := "camp-kit"
const CAMP_KIT_NAME := "Camp Kit"
const CAMP_KIT_PRICE := 150
# "Very low" per the brief — roughly 1 in 12, rare enough that the item is a
# real convenience, not a coin flip.
const AMBUSH_CHANCE_PCT := 8
const AMBUSH_DC := 13             # same DC as WorldLairs' Survival search
const AMBUSH_FACTION := "bandit"  # a universal, always-fielded faction — night raiders, not a themed monster

# The moment a camp is made pins its own outcome — same spot, same world-time,
# same result, matching this codebase's usual "seed off the moment" idiom
# (barks, lair search, ...). A shared static rather than inlined in world.gd
# so a test can reproduce the exact seed a real call would use.
static func camp_seed(elapsed: float, pos: Vector2) -> int:
	return maxi(1, absi(hash("%s|%s" % [str(elapsed), str(pos)])))

static func ambush_roll(rng = null) -> bool:
	if rng == null:
		rng = RNG.new()
	return rng.roll_die(100) <= AMBUSH_CHANCE_PCT

# The party's one shot at noticing it coming: best of Survival or Perception,
# same "whoever's best represents the group" shape as WorldLairs.search()'s
# Survival check and Encounter.surprise_check()'s Stealth roll — not a
# per-member roll, the party either has a scout sharp enough to catch it or
# it doesn't.
static func watch_check(party, rng = null) -> Dictionary:
	var c = Campaign.new(party)
	var best_id := ""
	var best_skill := ""
	var best_bonus := -99
	# #176 step 4: the watch is kept at camp, whatever the map says the party is
	# doing — a Street-raised hero is as lost out here as on the road.
	var at_camp: Dictionary = party.here.merged({"site": "camp"}, true)
	for skill in ["survival", "perception"]:
		var id: String = c.best_at(skill)
		if id == "":
			continue
		var b: int = c.skill_bonus(id, skill, at_camp)
		if b > best_bonus:
			best_bonus = b
			best_id = id
			best_skill = skill
	# T9x: a Trance character doesn't need to sleep — sharper eyes on watch.
	if best_id != "" and Trance.has_trance(party):
		best_bonus += Trance.WATCH_BONUS
	if rng == null:
		rng = RNG.new()
	var nat: int = int(Dice.d20(rng)["nat"])
	var ch = party.get_member(best_id)
	return {
		"ok": best_id != "" and nat + best_bonus >= AMBUSH_DC,
		"char_id": best_id, "cname": ch.cname if ch != null else "Someone", "skill": best_skill,
		"nat": nat, "bonus": best_bonus, "dc": AMBUSH_DC,
	}
