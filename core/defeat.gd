# What a lost fight in the open world costs beyond the fight itself, and the
# one loss that ends a run.
#
# The map's retreat (scenes/world/world.gd's _retreat) always took gold: 15%
# of what the company carried. The design audit (docs/audit-game-design.md
# §1.8) found that the whole price then read the purse, and the strongroom
# (core/lodge.gd) holds a purse out of reach, so a company that banked
# everything lost a fight for nearly nothing. The owner's call was a floor the
# purse cannot touch. It is two things, both paid by every open-world defeat,
# a site wipe included:
#
#   - DAYS. The beaten company comes to DAYS_LOST day(s) later, and the world
#     walks through the time the proper way (core/world_rest.gd's pass_time:
#     bands move, raids land, opinion drifts, and a quest's deadline runs down,
#     core/quest.gd). It is not a rest: nothing refills, and the 24-hour gate
#     does not move. The company is not hunted while it lies there, for the
#     same reason a sleeping one is not.
#   - AN INJURY. Every hero the fight put on the ground who is still alive
#     makes a seeded CON save (core/traits.gd's after_defeat): failed, Wounded;
#     failed badly, Maimed. The same wound traits a failed death save or a
#     hardship leaves, mended the same way.
#
# And the end of the company (the owner's call, 2026-09-25). Until now, when
# the whole roster was dead after a defeat, the highest-level hero came to
# alone (a ponytail: the open world had no end screen to send a wiped company
# to). Now the run ENDS: finished() says so, ending() writes the record the
# closing screen reads (who fell, how many days the company lasted, its renown
# title, the roll of everyone who marched under it), the world save is marked
# finished (core/world_save.gd; the title screen lists it but will not resume
# it), and to_barracks() sends the living home and keeps the dead out.
#
#   var line := Defeat.lose_time(world, party, each)       # after the retreat's move
#   var hurt := Defeat.injure(party, result["downed"], now) # {moments, lines}
#   if Defeat.finished(party): party.finished = Defeat.ending(party, world, fell)
#   Defeat.end_lines(party.finished)                       # the closing screen's words
#
# What this does NOT own: the gold tax and where the company wakes up
# (world.gd's _retreat), who comes to and who stays dead (Party.revive_downed),
# the wound rows themselves (data/traits.json, core/traits.gd), the save
# format (core/world_save.gd), or drawing the end (scenes/game/game.gd).
extends RefCounted

const WorldRest = preload("res://core/world_rest.gd")
const Traits = preload("res://core/traits.gd")
const Ladder = preload("res://core/ladder.gd")
const CharacterSave = preload("res://core/character_save.gd")

const DAY := 1440.0   # world-minutes
# TUNING: a taste number, not a sweep's. One day is three long rests' worth of
# the world moving on (a band walks the whole small map in under an hour), a
# bounty's deadline a third gone (core/quest_posting.gd's DEADLINE_DAYS), and
# no refill. Two days read as a punishment for a fight the scaler meant to be
# winnable; revisit with the §3.2 wounds-curve sweep.
const DAYS_LOST := 1

# The whole roster dead: the company is finished. An empty roster is not a
# company that died, it is one that has not been founded yet.
static func finished(party) -> bool:
	if party == null or party.roster.is_empty():
		return false
	for ch in party.roster:
		if not ch.dead:
			return false
	return true

# The day the beaten company loses, walked by the world. `each` is the map's
# per-step hook (its off-screen battles), as for a night's rest. Returns the
# raid lines the time produced, for the caller to show.
static func lose_time(world, party, each := Callable()) -> Array:
	if world == null:
		return []
	return WorldRest.pass_time(world, party, DAYS_LOST * DAY, each)

# The injury half: every id in `downed` (the fight's result["downed"]: party
# ids that hit 0 HP at any point) who is still alive rolls for a wound.
static func injure(party, downed: Array, now: float) -> Dictionary:
	var chars: Array = []
	for id in downed:
		var ch = party.get_member(String(id))
		if ch != null and not ch.dead:
			chars.append(ch)
	return Traits.after_defeat(chars, now)

# The record a finished company leaves: plain data, so the save carries it and
# the title screen can show it again without a world. `fell` is the last
# fight's dead, named first on the closing screen.
static func ending(party, world, fell: Array) -> Dictionary:
	var elapsed: float = world.clock.elapsed if world != null else 0.0
	var roll: Array = []
	for ch in party.roster:
		roll.append({"id": String(ch.id), "name": String(ch.cname), "class_id": String(ch.class_id()),
			"level": int(ch.level()), "dead": bool(ch.dead)})
	var last: Array = []
	for id in fell:
		var ch = party.get_member(String(id))
		if ch != null:
			last.append(String(ch.cname))
	return {"elapsed": elapsed, "days": int(elapsed / DAY) + 1, "title": Ladder.title(),
		"renown": Ladder.renown(), "fell": last, "roll": roll, "gold": int(party.gold)}

# The closing screen's words, off the record alone: a head line, then one line
# of what it came to, then the roll. Here rather than in the screen so the
# words and the record are tested together.
static func end_lines(e: Dictionary) -> Dictionary:
	var days := int(e.get("days", 1))
	var fell: Array = e.get("fell", [])
	var last := ""
	if fell.size() == 1:
		last = "%s was the last of them to fall." % String(fell[0])
	elif fell.size() > 1:
		last = "%s and %s were the last of them to fall." % [", ".join(fell.slice(0, fell.size() - 1)), String(fell[-1])]
	var title := String(e.get("title", Ladder.TITLES[0]))
	var lasted := "one day" if days == 1 else "%d days" % days
	var roll: Array = []
	for r in e.get("roll", []):
		roll.append("%s, level %d %s%s" % [String(r.get("name", "?")), int(r.get("level", 1)),
			String(r.get("class_id", "")).capitalize(), ", dead" if bool(r.get("dead", false)) else ", living"])
	return {
		"head": "The company is finished",
		"lead": "Nobody gets up this time. %s" % last if last != "" else "Nobody gets up this time.",
		"lasted": "It lasted %s on the road, and they were %s when it ended." % [lasted, title],
		"roll": roll,
	}

# The barracks after the end: the living go home as they would from any run,
# and the dead do not — their files are taken out, so an inn never offers a
# dead hero back as a veteran (core/recruits.gd reads the barracks). Returns
# how many went home.
static func to_barracks(party) -> int:
	var home := 0
	for ch in party.roster:
		if ch.dead:
			if CharacterSave.exists(String(ch.id)):
				CharacterSave.delete(String(ch.id))
		else:
			CharacterSave.save(ch)
			home += 1
	return home
