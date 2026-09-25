# Recruits — who is looking for work at an inn, and what it costs to take them on.
#
# The owner's call (2026-09-24): a run starts with ONE hero, made in the
# creator, who founds the company. Everybody after that is hired, from the
# handful of people sitting in a town's common room waiting for a company to
# walk in. They are somebody already — a species, a class, a background, the
# scores they were born and raised to, the skills and tongues and trade they
# picked up, the gear on their back, a temper and a past. The company does not
# get to redesign a stranger. What it does decide is what they become from here:
# the subclass, the spells, and the ordinary level-up choices (an ability
# increase or a feat, a fighting style) — which is exactly the set a player
# makes for a hero at the level-up screen anyway. So the hire is the creator's
# work done by the dice, minus the choices that level-up already owns, and the
# player finishes it on a settle-in page (scenes/creator/levelup.gd's recruit
# mode) before the fee changes hands.
#
#   Recruits.found(party)                 # a new run: hiring is the only way in
#   Recruits.hire_only(party)             # false for a save from before this (grandfathered)
#   Recruits.offers(s, world, party)      # [{slot, seed, level, fee, veteran, ...}], the common room today
#   Recruits.build(offer)                 # -> Character, fixed parts rolled, the player's parts open
#   Recruits.why_not(party, offer)        # "" when the company can take them on, else the reason, in words
#   Recruits.hire(party, world, s, offer, ch)   # "" and they are on the roster, else the reason
#   Recruits.players_pick(p)              # is this pending choice the player's to make?
#   Recruits.intro(ch)                    # the inn's one line: who they were, what they are like
#   Recruits.to_dict(party) / from_dict(party, d)   # the save's party["hiring"]
#
# THE POOL is seeded off the settlement and the DAY, the way the market's shelf
# is seeded off the settlement and its restock step (core/settlement_visit.gd):
# hash("recruit|<id>|<day>|<chair>"). Walking out and back in, or reloading, is
# the same faces; tomorrow is different ones. It is deliberately NOT seeded off
# last_visited — that moves on every visit, and a pool that rerolled whenever
# the gate was walked through would be a slot machine with a door. A hire is
# remembered per settlement and day (party.hiring["taken"]), so the person you
# took on is not still sitting at the table when you look back.
#
# THE LEVEL is the country's, not the company's: the band's level for a party
# like this one (Regions.level_here — the party's level pulled inside the band)
# minus one, floored at 1. A heartland inn sends a level-1 party level-1 hands;
# the Marches hand a level-1 party someone at 2, and so on out. A hireling is a
# step behind the fighting the country is built for, so the company is always
# worth more than the pool.
#
# VETERANS. Heroes from earlier runs stay in the barracks and do not walk into
# a new run's roster — the founder is made fresh. They are in the world,
# though, and now and then one is the first chair at an inn: at their own
# class, species and everything else, and at their OWN level, never rebuilt at
# a lower one (their file is their career, and the run writes it back on the
# way out, so a trimmed copy would cost them the levels for good). What keeps
# that fair is where they turn up: only at an inn whose country fights at
# their level or higher (their level <= Regions.level_here), so a level-9
# veteran is a Frontier hire, not a heartland walkover. The dead are not
# offered at all (the design audit §2.1): a hero who died in an earlier run and
# was never raised is filed dead, and stays that way — the old two lines that
# stood a returning hero up whatever their file said are gone. The inn shows a
# veteran's record from those runs (core/service.gd veteran_line), not just
# that they are one.
#
# WHO THEY ARE, IN A LINE (§2.5): every chair has an intro built from the
# background they grew up in and the temper they have (intro(), below), in the
# house voice, seeded off the name and both, so the same face says the same
# thing on every look.
#
# THE FEE is one-time — no wages, no upkeep, ever (owner's call). About 50 ◉ a
# level, and a name knocks some off it: people want to sign with a company
# they have heard of. The ROSTER CAP climbs with the same name, and it applies
# to hiring only: a grandfathered roster already over it keeps every hero.
#
# GRANDFATHERING, without a save version. A party from before this has
# party.hiring == {} and keeps the old rule — the party screen's Create new —
# AND gets the inns' pools as well. A new run sets {"rule": "hire"}, and from
# then on the one hero made at the start is the only one ever made.
#
# What this does NOT own: the settle-in page and the inn's list (scenes/creator/
# levelup.gd, scenes/world/world.gd's _build_inn_page — they draw this), the
# creator the founder is made in, the barracks files (core/character_save.gd),
# the band levels (core/regions.gd), the renown ladder (core/ladder.gd), or the
# meta-progression that decides which species and classes exist to be rolled
# (core/progression.gd).
extends RefCounted

const Character = preload("res://core/character.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const ChoicePick = preload("res://core/rules/choice_pick.gd")
const Leveling = preload("res://core/leveling.gd")
const Traits = preload("res://core/traits.gd")
const Prog = preload("res://core/progression.gd")
const Regions = preload("res://core/regions.gd")
const Ladder = preload("res://core/ladder.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const RNG = preload("res://core/rng.gd")
const Service = preload("res://core/service.gd")

# TUNING: the owner's figure, "about 50 gold x the recruit's level". Taste, not
# a sweep: a level-1 hand is two nights at a city inn and a bit, a level-5 one
# costs what a lodge room does.
const FEE_PER_LEVEL := 50
# TUNING: taken off the fee per renown title above Nobodies (core/ladder.gd's
# TITLES), so Legends pay 60% of the list price. The same step Ladder.PAY_PER_TITLE
# adds to a job's pay — a name is worth the same tenth on both sides of a deal.
const FEE_OFF_PER_TITLE := 0.1
# TUNING: how many a company can keep on the books, by renown title — Nobodies
# 6, then two more per title. More than a marching four (Party.MAX_ACTIVE) from
# the start, so there is always a bench to rotate the wounded onto.
const ROSTER_CAP := [6, 8, 10, 12, 14]
# TUNING: chairs in the common room, by settlement kind. Same three kinds the
# inn's price (Visit.INN_COST) and the pit (Downtime) key on; an unknown kind
# reads as a town.
const POOL_SIZE := {"city": 3, "town": 2, "camp": 1}
# The pool turns over once a world-day (World.clock.elapsed is in minutes).
const PERIOD := 1440.0
# TUNING: what the founder walks out of the creator with. The old start was up
# to four heroes for nothing; this is the same company at the same size if the
# founder spends it on three level-1 hands at Nobodies' fee — or fewer hands and
# a camp kit, which is the kind of choice the start was missing.
const FOUNDING_PURSE := 150
# TUNING: one day in three, a settlement's first chair is a veteran out of the
# barracks rather than a stranger — when there is one who fits the country.
const VETERAN_ODDS := 3

# The choices a hire leaves open. Everything else is rolled before they sit
# down. `subclass`, spells and a fighting style are the player's whatever
# grants them; an ability increase or a feat is the player's when a CLASS level
# grants it (a background's +2/+1 and a human's origin feat are who they were
# before they met you); anything a subclass grants follows from the subclass
# the player picks, so it is theirs too.
const PLAYERS_TYPES := ["subclass", "spell-choice", "fighting-style-choice"]
const LEVEL_UP_TYPES := ["asi", "feat-choice"]

static func players_pick(p: Dictionary) -> bool:
	var origin := String(p.get("source", {}).get("origin", ""))
	if String(p["type"]) in PLAYERS_TYPES or origin == "subclass":
		return true
	return String(p["type"]) in LEVEL_UP_TYPES and origin == "class"

# --- who they are, in a line (§2.5) --------------------------------------------
#
# Two sentences with the subject left off, the way a trait's text reads ("Looks
# at the floor before stepping on it."): what their background made of them,
# then what they are like. Two of each so two soldiers at one table are not the
# same soldier. A pack's new background or temperament has no line here and
# drops its half; a recruit with neither has no intro.
const PAST := {
	"acolyte": ["Kept the lamps lit in a temple that did not pay.",
		"Knows the rites for the dead by heart, and has said them more than once."],
	"artisan": ["Has calluses in the places a trade puts them.",
		"Left a workshop, and a master who is still owed a year."],
	"charlatan": ["Has been three other people this year, and liked one of them.",
		"Sold a cure for everything in a town that has since caught on."],
	"criminal": ["Knows how a lock is made, and how it is unmade.",
		"Is not welcome in two cities, and will not say which."],
	"entertainer": ["Has played to rooms that threw things, and rooms that threw coin.",
		"Can hold a crowd for an hour and a tune for a week."],
	"farmer": ["Left a field that will go to weeds without them.",
		"Has buried livestock in a hard winter, and a neighbour too."],
	"guard": ["Stood a gate for years and saw most of what came through it.",
		"Walked a wall at night long enough to learn what the dark sounds like."],
	"guide": ["Knows three ways over every ridge in the country they came from.",
		"Has brought people home that other guides left behind."],
	"hermit": ["Spent years alone somewhere, and came back quieter.",
		"Talks to themselves, and sometimes the answer is useful."],
	"merchant": ["Can price a sword by looking at the hilt.",
		"Lost a season's stock on a bad road, and learned from it."],
	"noble": ["Was raised to give orders, and is still learning to take them.",
		"Has a name that opens doors, and a family that would rather it did not."],
	"sage": ["Has read about most of the things that will try to kill the company.",
		"Carries more books than rations, and knows it."],
	"sailor": ["Walks like the ground might roll, and ties every knot twice.",
		"Has seen a ship go down, and swum away from it."],
	"scribe": ["Copied other people's histories until they wanted one of their own.",
		"Writes everything down, including what nobody asked them to."],
	"soldier": ["Served in someone else's war and walked away from it whole.",
		"Knows how to stand in a line, and what it costs when the line breaks."],
	"wayfarer": ["Has slept in more ditches than beds, and complains of neither.",
		"Has walked every road that goes anywhere near here."],
}
const TEMPER := {
	"brave": ["The first through a door, every time.", "Does not step back, and has the scars to show for it."],
	"craven": ["Finds the way out before the fight.", "Has outlived braver people, and does not apologise for it."],
	"wrathful": ["Slow to forgive, and quick with everything else.", "Holds a grudge the way other people hold a job."],
	"calm": ["Speaks quietly, even when the room is on fire.", "Nobody has heard them raise their voice."],
	"greedy": ["Asks about the pay before the job.", "Counts the purse twice and the company once."],
	"generous": ["Shares the last of the water and does not mention it.", "Buys the round when it is not their turn."],
	"curious": ["Wants to know what is behind the door, and the one behind that.", "Asks the questions everyone else thought better of."],
	"cautious": ["Checks the floor, the ceiling and the way out, in that order.", "Would rather be late than dead, and says so."],
}

static func intro(ch) -> String:
	if ch == null:
		return ""
	var temper := Traits.of(ch, "temperament")
	var h := absi(hash("intro|%s|%s|%s" % [ch.cname, ch.background_id, temper]))
	var parts: Array = []
	var past: Array = PAST.get(ch.background_id, [])
	if not past.is_empty():
		parts.append(String(past[h % past.size()]))
	var now: Array = TEMPER.get(temper, [])
	if not now.is_empty():
		parts.append(String(now[(h / 7) % now.size()]))
	return " ".join(parts)

# --- the rule ---------------------------------------------------------------

static func hire_only(party) -> bool:
	return party != null and String(party.hiring.get("rule", "")) == "hire"

# A new run. The purse is set, not earned (party.add_gold would count it as
# income for the gold achievements).
static func found(party) -> void:
	party.hiring = {"rule": "hire"}
	party.gold = maxi(party.gold, FOUNDING_PURSE)

static func roster_cap() -> int:
	return int(ROSTER_CAP[clampi(Ladder.title_index(), 0, ROSTER_CAP.size() - 1)])

static func fee(level: int) -> int:
	var off: float = FEE_OFF_PER_TITLE * float(Ladder.title_index())
	return maxi(1, int(round(FEE_PER_LEVEL * maxi(1, level) * (1.0 - off))))

static func period(world) -> int:
	return int(float(world.clock.elapsed) / PERIOD) if world != null else 0

static func level_for(world, s, party) -> int:
	return maxi(1, Regions.level_here(world, s.position, party) - 1)

# --- the pool -----------------------------------------------------------------

# Today's common room. A town that will not trade with the company has nobody
# who will sign with it either (FactionOpinion.refuses_trade — the same line the
# market draws).
static func offers(s, world, party) -> Array:
	var out: Array = []
	if s == null or world == null or FactionOpinion.refuses_trade(s.faction):
		return out
	var p := period(world)
	var level := level_for(world, s, party)
	var vet := _veteran_for(s, p, world, party)
	for i in int(POOL_SIZE.get(s.kind, POOL_SIZE["town"])):
		if _taken(party, String(s.id), p, i):
			continue
		var o := {"settlement": String(s.id), "period": p, "slot": i,
			"seed": maxi(1, absi(hash("recruit|%s|%d|%d" % [s.id, p, i]))),
			"level": level, "veteran": ""}
		if i == 0 and not vet.is_empty():
			o["veteran"] = String(vet["id"])
			o["level"] = int(vet["level"])
		o["fee"] = fee(int(o["level"]))
		out.append(o)
	return out

# Which barracks hero, if any, is today's first chair here. Anyone not already
# on this roster, at no more than the level this country fights at.
static func _veteran_for(s, p: int, world, party) -> Dictionary:
	var h := absi(hash("recruit-vet|%s|%d" % [s.id, p]))
	if h % VETERAN_ODDS != 0:
		return {}
	var here := Regions.level_here(world, s.position, party)
	var fits: Array = []
	var slugs: Array = CharacterSave.list_slugs()
	slugs.sort()
	for slug in slugs:
		if party != null and party.get_member(String(slug)) != null:
			continue
		var ch = CharacterSave.load_slug(String(slug))
		# The dead stay dead across runs (the design audit §2.1): a hero whose
		# file says dead died and was never raised, and is on a roll of the
		# fallen somewhere, not in a common room.
		if ch == null or ch.dead or ch.levels.is_empty() or ch.level() > here:
			continue
		fits.append({"id": String(slug), "level": ch.level()})
	if fits.is_empty():
		return {}
	return fits[(h / VETERAN_ODDS) % fits.size()]

static func _taken(party, sid: String, p: int, slot: int) -> bool:
	if party == null:
		return false
	var t: Dictionary = party.hiring.get("taken", {}).get(sid, {})
	return int(t.get("period", -1)) == p and slot in t.get("slots", [])

static func _mark_taken(party, sid: String, p: int, slot: int) -> void:
	var taken: Dictionary = party.hiring.get("taken", {})
	var t: Dictionary = taken.get(sid, {})
	if int(t.get("period", -1)) != p:
		t = {"period": p, "slots": []}   # yesterday's hires are yesterday's news
	if not slot in t["slots"]:
		t["slots"].append(slot)
	taken[sid] = t
	party.hiring["taken"] = taken

# --- who they are ------------------------------------------------------------

# Built once per (seed, level, veteran) and handed out as a fresh copy every
# time: the inn redraws on every click, and the settle-in page changes the copy
# it is given — a Cancel there must not leave its picks on the next look.
static var _built := {}
const BUILT_KEEP := 64

static func build(offer: Dictionary):
	var vet := String(offer.get("veteran", ""))
	var key := "%d|%d|%s|%d" % [int(offer.get("seed", 1)), int(offer.get("level", 1)), vet, Prog.lifetime_xp_total()]
	if _built.has(key):
		return CharacterSave.from_dict(_built[key])
	var ch = null
	if vet != "":
		ch = CharacterSave.load_slug(vet)
		if ch == null or ch.dead:
			return null        # _veteran_for never offers the dead; a stale offer does not raise them
		ch.hp_current = -1     # rested: a new run puts a returning hero at full HP
	else:
		ch = _roll(int(offer.get("seed", 1)), int(offer.get("level", 1)))
	if _built.size() >= BUILT_KEEP:
		_built.clear()
	_built[key] = CharacterSave.to_dict(ch)
	return CharacterSave.from_dict(_built[key])

# A stranger, from nothing but a seed. Everything here is a pick the creator
# would have asked the player for, answered by the dice inside the creator's
# own limits: an unlocked species and class, the standard array, proficient
# gear, and the choice points through core/rules/choice_pick.gd.
static func _roll(seed_v: int, level: int):
	var rng := RNG.new(maxi(1, seed_v))
	var ch := Character.new()
	ch.species_id = String(_pick(rng, _open("species.json", func(id): return Prog.is_species_unlocked(id))))
	var cid := String(_pick(rng, _open("classes.json", func(id): return Prog.is_class_unlocked(id))))
	ch.background_id = String(_pick(rng, _open("backgrounds.json", func(_id): return true)))
	ch.cname = _name(ch.species_id, rng)
	ch.base_abilities = _abilities(cid, rng)
	Leveling.grant_levels(ch, level, cid)   # granted, not earned: no lifetime XP, no milestones
	_outfit(ch, rng)
	# A temper of their own; a past that follows the background they had, the
	# way the creator pre-selects it, unless the background has none to give.
	Traits.set_family(ch, "temperament", String(_pick(rng, Traits.of_family("temperament"))), "born to it")
	var past := Traits.default_for(ch.background_id, "origin")
	Traits.set_family(ch, "origin", past if past != "" else String(_pick(rng, Traits.of_family("origin"))), "born to it")
	ch.traits_offered = true
	_settle_fixed(ch, rng)
	return ch

static func _open(file: String, open: Callable) -> Array:
	var out: Array = []
	for r in Catalog.all(file):
		if r is Dictionary and open.call(String(r["id"])):
			out.append(String(r["id"]))
	return out

static func _pick(rng, from: Array):
	return from[rng.roll_die(from.size()) - 1] if not from.is_empty() else ""

static func _shuffled(rng, from: Array) -> Array:
	var out: Array = from.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.roll_die(i + 1) - 1
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out

# data/recruit-names.json, by species; its `default` record names anyone whose
# species has no list (a pack's new species, until the pack adds one).
static func _name(species: String, rng) -> String:
	var rows: Dictionary = Catalog.index("recruit-names.json")
	var names: Array = rows.get(species, rows.get("default", {})).get("names", [])
	if names.is_empty():
		names = rows.get("default", {}).get("names", ["Nameless"])
	return String(_pick(rng, names))

# The standard array, dealt the way the creator's quick build deals it — the
# class's lead score and its second — and the other four shuffled, because
# not every fighter came up with the same weak spot. A class that leads with
# either of two scores (the fighter's STR or DEX) tosses for which. Always the
# array, so a recruit is inside the same budget a player builds in.
static func _abilities(cid: String, rng) -> Dictionary:
	var rec: Dictionary = ChoicePick.recommended_array(cid)
	var order: Array = ChoicePick.ABILS.duplicate()
	order.sort_custom(func(a, b): return int(rec.get(a, 0)) > int(rec.get(b, 0)))
	var lead: Array = Catalog.class_src(cid).get("quickBuild", {}).get("highestAbility", [])
	if lead.size() >= 2 and rng.roll_die(2) == 2:
		var t = order[0]
		order[0] = order[1]
		order[1] = t
	order = order.slice(0, 2) + _shuffled(rng, order.slice(2))
	var out := {}
	for i in order.size():
		out[order[i]] = int(ChoicePick.STANDARD_ARRAY[i])
	return out

# What they carry: one of the class's kits (data/recruit-kits.json), preferring
# one fought with the hand they are better with, and never an item the build
# is not proficient with or too weak to wear. A class with no kit — a pack's
# new one — carries the first weapon it can use.
static func _outfit(ch, rng) -> void:
	var sheet = ch.sheet()
	var weapons: Array = ChoicePick.proficient_weapons(sheet)
	var armor: Array = ChoicePick.proficient_armor(sheet)
	var strength := int(ch.base_abilities.get("str", 10))
	var hand := "str" if strength >= int(ch.base_abilities.get("dex", 10)) else "dex"
	var fit: Array = []
	var mine: Array = []
	for k in Catalog.index("recruit-kits.json").get(ch.class_id(), {}).get("kits", []):
		var ok := true
		for id in k.get("items", []):
			var need = Catalog.index("armor.json").get(String(id), {}).get("strengthRequirement")
			if not (String(id) in weapons or String(id) in armor) or (need != null and int(need) > strength):
				ok = false
		if ok:
			fit.append(k)
			if String(k.get("ability", "")) == hand:
				mine.append(k)
	var kit = _pick(rng, mine if not mine.is_empty() else fit)
	ch.equipped.clear()
	if kit is Dictionary:
		for id in kit["items"]:
			ch.equipped.append(String(id))
	elif not weapons.is_empty():
		ch.equipped.append(String(weapons[0]))
	ch.dirty()

# Every open choice that is not the player's, answered. One at a time and
# re-resolved between, because an answer can open another (a human's origin
# feat brings its own picks). A choice that stays open after it was answered —
# too few legal options to fill it — is left for the settle-in page rather
# than tried forever.
static func _settle_fixed(ch, rng) -> void:
	var given_up := {}
	for _step in 80:
		var sheet = ch.sheet()
		var todo: Array = sheet.pending.filter(func(p): return not players_pick(p) and not given_up.has(p["key"]))
		if todo.is_empty():
			return
		var p: Dictionary = todo[0]
		if ch.choices.has(p["key"]):
			given_up[p["key"]] = true   # answered once already and still open
			continue
		ch.decide(p["key"], ChoicePick.decision_for(p, _auto_picks(ch, p, sheet, rng)))

static func _auto_picks(ch, p: Dictionary, sheet, rng) -> Array:
	var n := ChoicePick.pick_count(p)
	var ids: Array = ChoicePick.options_for(p, sheet, []).map(func(o): return String(o["id"]))
	match String(p["type"]):
		"asi", "ability-choice":
			# Into what their trade leans on, the way the quick build reads it —
			# the class's lead and second score, then DEX and CON, which keep
			# anybody alive — and past those into what they are already best at:
			# +2 to the first of those the list allows, +1 to the next.
			var q: Dictionary = Catalog.class_src(ch.class_id()).get("quickBuild", {})
			var lean: Array = Array(q.get("highestAbility", [])) + [String(q.get("secondaryAbility", "")), "dex", "con"]
			var rank := func(a: String) -> int:
				return lean.find(a) if a in lean else 100 - int(sheet.abilities[a]["total"])
			var best: Array = ChoicePick.ABILS.filter(func(a): return a in ids)
			best.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
			var out: Array = []
			var per := ChoicePick.max_per_option(p)
			for a in best:
				for _i in mini(per, n - out.size()):
					out.append(a)
				if out.size() >= n:
					break
			return out
		"weapon-mastery-choice":
			# The weapons they actually carry first.
			var carried: Array = ids.filter(func(id): return id in ch.equipped)
			var rest: Array = _shuffled(rng, ids.filter(func(id): return not id in ch.equipped))
			return (carried + rest).slice(0, n)
	# A skill, tongue or trade they already have is a wasted pick, while there
	# is anything else to pick; so is a Metamagic option the board does not play
	# (core/metamagic.gd), which the player's own picker greys out.
	var wasted: Dictionary = ChoicePick.taken_elsewhere(p, [p], sheet.choice_points, ch.choices, sheet) \
		if String(p["type"]) in ["skill-choice", "language-choice", "tool-choice"] else {}
	wasted.merge(ChoicePick.unbuilt(p))
	var fresh: Array = _shuffled(rng, ids.filter(func(id): return not wasted.has(id)))
	var stale: Array = _shuffled(rng, ids.filter(func(id): return wasted.has(id)))
	return (fresh + stale).slice(0, n)

# --- taking them on ---------------------------------------------------------

# "" when the company can sign this one today; otherwise the reason, as the
# inn says it — a greyed button with no reason reads as a bug here.
static func why_not(party, offer: Dictionary) -> String:
	var cap := roster_cap()
	if party.roster.size() >= cap:
		return "The company keeps %d on the books at most while it is %s. The name has to grow before anyone else signs." \
			% [cap, Ladder.title()]
	if party.gold < int(offer.get("fee", 0)):
		return "The fee is %d ◉; the purse is %d short." % [int(offer["fee"]), int(offer["fee"]) - party.gold]
	return ""

# The hire. `ch` is build(offer) with the player's choices made on the settle-in
# page. Pays the fee, files them under an id nobody holds, puts them on the
# roster (marching, while there is a slot) and takes their chair out of today's
# pool. Returns "" when it went through, else why not, and changes nothing.
static func hire(party, world, s, offer: Dictionary, ch) -> String:
	if ch == null:
		return "Nobody to take on."
	var still := offers(s, world, party).filter(func(o): return int(o["slot"]) == int(offer.get("slot", -1)))
	if still.is_empty() or int(still[0]["period"]) != int(offer.get("period", -1)):
		return "They have gone — somebody else took them on, or the day turned."
	var why := why_not(party, still[0])
	if why != "":
		return why
	if not Leveling.can_finalize(ch):
		return "%d choice(s) still unmade." % Leveling.pending(ch).size()
	var vet := String(offer.get("veteran", ""))
	if vet != "":
		ch.id = vet   # a veteran is the hero in the barracks file, carrying on
		if party.get_member(vet) != null:
			return "%s is already with the company." % ch.cname
	else:
		ch.id = _free_id(party, ch.cname)
	if not party.spend_gold(int(still[0]["fee"])):
		return "The purse cannot cover the fee."
	party.add_member(ch)
	Service.enlist(ch)   # one more company on their record
	_mark_taken(party, String(s.id), int(still[0]["period"]), int(still[0]["slot"]))
	return ""

# CharacterSave.unique_slug() knows the barracks; a hire this session is not in
# it until the run writes the roster out, so the roster is asked too.
static func _free_id(party, name: String) -> String:
	var id := CharacterSave.unique_slug(name)
	var n := 2
	while party.get_member(id) != null or CharacterSave.exists(id):
		id = "%s-%d" % [CharacterSave.slugify(name), n]
		n += 1
	return id

# --- the save -----------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.hiring.duplicate(true)

# JSON hands the day and the chair numbers back as floats; put them back to the
# ints they are compared as. No key at all (a save from before hiring) is {} —
# the grandfathered rule.
static func from_dict(party, d) -> void:
	party.hiring = {}
	if not d is Dictionary:
		return
	if String(d.get("rule", "")) != "":
		party.hiring["rule"] = String(d["rule"])
	if d.get("taken") is Dictionary:
		var taken := {}
		for sid in d["taken"]:
			var t = d["taken"][sid]
			if t is Dictionary:
				taken[String(sid)] = {"period": int(t.get("period", -1)),
					"slots": Array(t.get("slots", [])).map(func(x): return int(x))}
		party.hiring["taken"] = taken
