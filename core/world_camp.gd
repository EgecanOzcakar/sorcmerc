# T9x: "make camp" — a purchasable item (CAMP_KIT) lets the party take a long
# rest anywhere on the map instead of only inside a settlement, at a small
# risk of a night ambush. A separate file from settlement_visit.gd because
# this is a skill-check + combat-launch decision, not a market transaction.
#
#   var r := WorldCamp.make_camp(party, world, radius, each)
#   if not r["ok"]: say r["text"]                  # refused, nothing spent
#   elif r["ambush"]: launch combat, scouted_ahead = r["watch"]["ok"], forced_ambush = not
#   else: r["rest"] is Visit.rest()'s result, the night already passed
#
# make_camp() is the whole decision, so the map screen only draws it. It used to
# live in scenes/world/world.gd's _make_camp(), where two rules of the design
# audit (docs/audit-game-design.md) could not be tested headless:
#  - §1.6: Rope Trick is the camp kit and nothing more. The ambush roll is made
#    whether the night is roped or not, and the slot the spell cost is held
#    through the rest it made possible (party.camp_holds, re-spent by
#    Visit.rest(), let go here once the camp is made). Alarm is held the same
#    way and, like Rope Trick, is spent by the camp it was cast for — it used
#    to wait, ward up, through every quiet night until one was not.
#  - §1.7: no camp with a hostile band in reach, the same refusal the map's
#    short rest has always made (hostile_near()), and the eight hours of a
#    quiet night are walked by the world (core/world_rest.gd).
#
# What this file does NOT own: the rest itself (core/settlement_visit.gd),
# what the world does during the night (core/world_rest.gd), the fight an
# ambush opens and the cards that tell the night (the map screen).
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const Trance = preload("res://core/trance.gd")
const Visit = preload("res://core/settlement_visit.gd")
const WorldAI = preload("res://core/world_ai.gd")
const Ach = preload("res://core/achievements.gd")

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

# A hostile band within `radius` of the player's party — the map passes its
# ENCOUNTER_RADIUS, the reach at which that band would be met anyway. The short
# rest and the camp both refuse on it: nobody lies down with that in sight.
static func hostile_near(world, radius: float) -> bool:
	var p = world.player()
	if p == null:
		return false
	for q in world.parties:
		if q != p and WorldAI.is_hostile(q, p) and q.position.distance_to(p.position) <= radius:
			return true
	return false

const TIRED_TEXT := "The company is not tired enough for another long rest yet."
const HOSTILE_TEXT := "Too dangerous to make camp here: something hostile is close."
const NO_KIT_TEXT := "There is no camp kit in the stash, and no Rope Trick cast."

# Make camp: refuse (nothing spent) or spend the kit or the Rope Trick, then roll
# the night off camp_seed(). A quiet night is the long rest, with the world
# walking through it; an ambush is no rest at all, and the watch — or Alarm,
# which hears it whatever the watch rolled — says who gets the first round.
# Either way the camp spells are spent and their holds let go. `rng` rides out
# on the result because the screen's fireside reads the same stream after.
# `ambush_pct` is AMBUSH_CHANCE_PCT unless the caller knows better: on the roads
# (#231) a camp is as risky as its stretch (RouteTravel.camp_ambush_pct).
static func make_camp(party, world, radius: float, each := Callable(), ambush_pct := AMBUSH_CHANCE_PCT) -> Dictionary:
	if not Visit.can_long_rest(party, world):
		return {"ok": false, "why": "tired", "text": TIRED_TEXT}
	if hostile_near(world, radius):
		return {"ok": false, "why": "hostile", "text": HOSTILE_TEXT}
	var roped: bool = party.safe_camp
	if not roped and party.stash_count(CAMP_KIT_ITEM) < 1:
		return {"ok": false, "why": "kit", "text": NO_KIT_TEXT}
	if roped:
		party.safe_camp = false
	else:
		party.stash_remove(CAMP_KIT_ITEM, 1)
	var alarm: bool = party.alarm_set
	party.alarm_set = false
	Ach.bump("camps")
	var p = world.player()
	var rng := RNG.new(camp_seed(world.clock.elapsed, p.position if p != null else Vector2.ZERO))
	var out := {"ok": true, "roped": roped, "alarm": alarm, "rng": rng, "ambush": ambush_roll(rng, ambush_pct)}
	if not out["ambush"]:
		out["rest"] = Visit.rest(party, world, "long-rest", each)
	else:
		var watch: Dictionary = watch_check(party, rng)
		if alarm:   # the ward wakes them whatever the watch rolled
			watch = {"ok": true, "cname": "The alarm", "skill": "ward", "nat": 20, "bonus": 0, "dc": 0, "char_id": "alarm"}
		out["watch"] = watch
	party.camp_holds.clear()   # the camp they paid for is made: the next long rest gives the slots back
	return out

static func ambush_roll(rng = null, pct := AMBUSH_CHANCE_PCT) -> bool:
	if rng == null:
		rng = RNG.new()
	return rng.roll_die(100) <= pct

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
