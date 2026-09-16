# D3 — standing orders, and what happens on the road between places.
#
# The open world has a 1x-8x fast-forward, and the user kept it deliberately:
# travel should be skippable when nothing is happening. The problem that
# creates is that nothing ever DID happen, so the map was a corridor between
# menus and 8x was a way to skip the game. This file is the other half of that
# bargain — the road gets events, and the clock stops for them.
#
#   Travel.set_orders(party, "careful", "vera", "pike")
#   world.player().speed = World.SPEED * Travel.speed_mult(party)
#   var e := Travel.check(party, world)   # {} most ticks; an event when one fires
#
# TWO RULES, both locked with the user, and they are what keep fast-forward
# honest without turning travel into a questionnaire:
#
#  1. **Standing orders, not per-watch prompts.** Pace, who scouts, who keeps
#     watch — set once on the party screen and left alone. Nothing is asked of
#     the player every few hours, so 8x stays fast.
#  2. **Orders are what RESOLVE the event.** An event does not stop to ask
#     anything; it rolls against the orders already standing and reports what
#     happened. The decision had teeth hours ago, when it was made. The clock
#     auto-pauses to show the result, which is what makes 8x "wake me when
#     something happens" rather than "skip the content".
#
# What this does NOT own: the encounter trigger (that is world.gd's
# _check_encounter, and D4 gives it the avoid/ambush/parley choice this file
# deliberately does not have), camping and the night ambush (core/world_camp.gd),
# foraging (core/world_forage.gd — a sibling on the same cadence idea), or any
# drawing. Pure math on a Party and a World.
#
# D3.1 grew the table from six events to fourteen without touching either rule.
# Six was enough to prove that a road with something on it beats a corridor; it
# was not enough to ride for an evening, because a table that small repeats
# before the party has crossed a country. The eight added events also widen what
# the road ASKS FOR — Athletics, History, Religion, Nature, Animal Handling,
# Intimidation and Deception all decide a stretch of road now — and what it
# deals: a wound taken off at a shrine, gear lost in a river, coin lost at a
# toll post, salvage out of a wreck, goodwill earned from the locals. Events
# that would describe something the map does not hold decline to fire at all
# (see `bands` and `needs` on EVENTS, and _table).
#
# ponytail: every event here resolves itself. Events that stop and ask the
# player something are D4's shape, not this one's — when they land, `check()`
# grows an "options" key and world.gd learns to wait for an answer.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const WorldLairs = preload("res://core/world_lairs.gd")

# One roll per six world-hours on the road. Foraging (world_forage.gd) is on
# four, so the two interleave rather than always landing together; at 8x that
# is an event every ~45 real seconds of travel, often enough to be why you are
# watching and rare enough not to be a metronome.
const EVENT_INTERVAL := 360.0

# --- standing orders --------------------------------------------------------

const PACES := ["careful", "normal", "forced"]
const DEFAULT_ORDERS := {"pace": "normal", "scout": "", "watch": ""}

# Pace is a straight trade of speed against how well the party reads the road.
# Careful is slower and sees things coming; a forced march covers ground and
# misses things. The bonus applies to every check this file rolls, which is
# what makes the setting matter rather than just being a speed slider.
const PACE := {
	"careful": {"speed": 0.70, "bonus": 2, "label": "Careful",
		"note": "Slower, but the party reads the ground as it goes (+2 on the road)."},
	"normal": {"speed": 1.00, "bonus": 0, "label": "Normal",
		"note": "A marching pace. No edge either way."},
	"forced": {"speed": 1.40, "bonus": -2, "label": "Forced march",
		"note": "Covers ground and misses things (-2 on the road)."},
}

static func orders(party) -> Dictionary:
	var o: Dictionary = DEFAULT_ORDERS.duplicate()
	if party == null:
		return o
	for k in o:
		if party.travel_orders.has(k):
			o[k] = party.travel_orders[k]
	if not o["pace"] in PACES:
		o["pace"] = DEFAULT_ORDERS["pace"]
	# An order naming somebody who is no longer marching is not an order. Falls
	# back to "whoever is best", the same contract every other check here uses.
	for role in ["scout", "watch"]:
		if String(o[role]) != "" and not party.is_active(String(o[role])):
			o[role] = ""
	return o

static func set_orders(party, pace: String, scout_id: String = "", watch_id: String = "") -> void:
	if party == null:
		return
	party.travel_orders = {
		"pace": pace if pace in PACES else DEFAULT_ORDERS["pace"],
		"scout": scout_id, "watch": watch_id,
	}

static func pace_label(pace: String) -> String:
	return String(PACE.get(pace, PACE["normal"])["label"])

static func pace_note(pace: String) -> String:
	return String(PACE.get(pace, PACE["normal"])["note"])

static func speed_mult(party) -> float:
	return float(PACE[orders(party)["pace"]]["speed"])

static func pace_bonus(party) -> int:
	return int(PACE[orders(party)["pace"]]["bonus"])

# --- the events -------------------------------------------------------------
#
# Each is a skill check against a DC, resolved by whoever the standing orders
# put on that job — or by the party's best at it when nobody was named. Every
# one names its check and its roll in the returned dict, so the card can say
# "Vera, Survival 14+5 vs DC 13" rather than "something happened", which is the
# house rule for every overworld check (world_lairs.search, world_camp.
# watch_check, world_forage.check).
#
# `role` is which standing order does the job — "scout" reads the ground,
# "watch" notices things, "" means anyone. `good` events pay out on a pass;
# `bad` ones cost on a fail, which is why a forced march's -2 is felt.
#
# Two optional keys keep an event from firing where it would ring hollow, which
# is the one thing a self-resolving table has to get right: a card the player
# cannot argue with had better not be describing a world they can see is not
# there (see _table).
#
#   "bands":  the D6 countries this can happen in (core/regions.gd ids). Absent
#             means anywhere. A toll post is a thing settled country does; a
#             company dead in its tracks is a thing the far country does.
#   "needs":  a state the world has to actually be in — "hurt" (somebody is
#             carrying a wound the shrine can do something about), "settlement"
#             (there are locals whose goodwill helping a carter could earn).
#
# Skills are spread on purpose. Before this table grew, the road asked for
# Survival, Perception, Persuasion, Insight, Investigation and Medicine and
# nothing else — so a party's Athletics, History, Religion, Nature and the two
# lying skills were dead weight the moment a fight ended. Every one of them now
# has a stretch of road where it is the thing that pays.
const EVENTS := [
	{"id": "rough-going", "role": "scout", "skills": ["survival"], "dc": 13, "kind": "bad",
		"title": "The going turns bad",
		"pass": "%s picks a line through it and the party barely slows.",
		"fail": "Nobody finds a way round. The detour costs the better part of a day's light."},
	{"id": "tracks", "role": "scout", "skills": ["survival", "perception"], "dc": 14, "kind": "good",
		"title": "Tracks across the road",
		"pass": "%s reads them: something has been coming and going, and not far.",
		"fail": "Tracks, crossing and re-crossing. Nobody can say whose, or how old."},
	{"id": "wayfarer", "role": "", "skills": ["persuasion", "insight"], "dc": 12, "kind": "good",
		"title": "Someone on the road",
		"pass": "%s gets them talking. They part with directions and a little coin for the company.",
		"fail": "They keep their hood up and their business to themselves."},
	{"id": "cache", "role": "", "skills": ["investigation", "perception"], "dc": 14, "kind": "good",
		"title": "Something half-buried",
		"pass": "%s turns it up: a stash, and whoever left it is past needing it.",
		"fail": "Roots and a rusted buckle. Whatever else was here is long gone."},
	{"id": "foul-water", "role": "watch", "skills": ["medicine", "survival"], "dc": 13, "kind": "bad",
		"title": "The stream runs wrong",
		"pass": "%s stops them drinking it in time.",
		"fail": "It is noticed too late. The party travels the next stretch sick and slow."},
	{"id": "good-ground", "role": "", "skills": [], "dc": 0, "kind": "good",
		"title": "Clear running",
		"pass": "Firm ground, a dry sky, and a road that goes where it says it does.",
		"fail": ""},
	# --- D3.1: the eight below ------------------------------------------------
	# Same contract as the six above — resolved before the card is built, nothing
	# asked of anyone — and sorted so that each new payoff kind has exactly one
	# event that deals it: gear in the river, coin at a toll post, a wound off at
	# a shrine, time back at a waystone, blood on a snare, salvage in a wreck,
	# an afternoon lost to weather, and goodwill earned from the locals.
	{"id": "ford", "role": "scout", "skills": ["athletics", "survival"], "dc": 13, "kind": "bad",
		"title": "The ford runs high",
		"pass": "%s finds the gravel bar under the brown water and walks them over it dry.",
		"fail": "Halfway across the current takes a pack off somebody's shoulder and keeps it."},
	{"id": "toll", "role": "", "skills": ["intimidation", "deception", "persuasion"], "dc": 14,
		"kind": "bad", "bands": ["heartland", "marches"],
		"title": "A pole across the road",
		"pass": "%s points out whose road this is and what the lord of it does about tolls. The pole goes up.",
		"fail": "They are not soldiers and it is not a toll. It is still six of them and one road."},
	{"id": "shrine", "role": "", "skills": ["religion", "medicine"], "dc": 12, "kind": "good",
		"needs": "hurt",
		"title": "A shrine at the crossroads",
		"pass": "%s knows whose it is and what it is owed. The hour spent there is worth more than the hour.",
		"fail": "Nobody can say whose shrine it was. The party leaves it the way they found it."},
	{"id": "waystone", "role": "scout", "skills": ["history", "investigation"], "dc": 13, "kind": "good",
		"title": "A waystone in the grass",
		"pass": "%s reads the old cut on it: the straight road ran here once, and most of it still does.",
		"fail": "Weathered past reading. Whatever it pointed at, it is not saying now."},
	{"id": "snare", "role": "watch", "skills": ["perception", "survival"], "dc": 14, "kind": "bad",
		"title": "Wire across the path",
		"pass": "%s catches the shine of it first. Somebody out here is hunting more than deer.",
		"fail": "It is found the way snares are usually found."},
	{"id": "wreck", "role": "", "skills": ["investigation", "perception"], "dc": 14, "kind": "good",
		"bands": ["marches", "frontier", "deeps"],
		"title": "What is left of a company",
		"pass": "%s works the wreck over properly. Whoever they were, they are long past minding.",
		"fail": "Picked over twice already, and not recently."},
	{"id": "storm", "role": "scout", "skills": ["nature", "survival"], "dc": 13, "kind": "bad",
		"title": "The sky goes the wrong colour",
		"pass": "%s calls it early and has them under cover before the worst of it comes through.",
		"fail": "It catches them in the open. There is nothing to do but sit in it and wait it out."},
	{"id": "carter", "role": "", "skills": ["animalhandling", "athletics"], "dc": 13, "kind": "good",
		"bands": ["heartland", "marches"], "needs": "settlement",
		"title": "A wheel in the ditch",
		"pass": "%s calms the team and lifts the cart clear. The carter pays what he has, and looks hard at the faces.",
		"fail": "The axle is sheared clean through. There is nothing to be done for him but wish him well."},
]

# What a failed "rough-going" costs, and what "good-ground" gives back — both in
# world-minutes, because time is what travel actually spends. Sized against
# EVENT_INTERVAL: a bad stretch costs most of the interval it happened in,
# which is felt without being a disaster.
const TIME_LOST := 240.0
const TIME_SAVED := 90.0
# "foul-water" is the one event that costs hit points. Deliberately small and a
# fraction, not dice: it is a tax on a bad marching order, not an encounter, and
# it must never be able to drop anybody (see the maxi(1, ...) below).
const SICK_HP_PCT := 0.12
const COIN_MIN := 10
const COIN_MAX := 45

# D3.1's costs and payoffs. Everything here is deliberately small: a road event
# is a thing that happened between two places, not a fight and not a reward
# node. The sizes are set against what the six originals already deal — a lost
# pack is worth a little more than a found one, a storm costs less than the
# worst ground, and nothing on this table can take the last hit point off
# anybody (see _hp_toll).
const STORM_LOST := 180.0        # weather sat out, vs TIME_LOST's day of detour
const WAYSTONE_SAVED := 120.0    # the old straight road, vs TIME_SAVED's good day
const SNARE_HP_PCT := 0.08       # under foul water's: one person walks into it
const SHRINE_HEAL_PCT := 0.25    # of max HP, to everyone still standing
const GEAR_MIN := 15             # the pack the ford takes, in gold
const GEAR_MAX := 55
const TOLL_MIN := 25             # what the pole costs when nobody talks it up
const TOLL_MAX := 90
const CARTER_MIN := 8            # a carter is not a patron; this is his day's coin
const CARTER_MAX := 30
const CARTER_GOODWILL := 3.0     # points with the locals' faction (core/faction_opinion.gd)
# What the road leaves in a wreck: plain gear, sellable, never magic. The stash
# is where a run's real finds live, and a roadside salvage that could roll a
# magic item would quietly become the best reason to travel.
#
# "shield" is deliberately NOT on this list though a dead company would have
# carried one: data/magic-items.json has an entry under that id too (the generic
# +1/+2/+3 shield), so Campaign.is_magic("shield") is true and a plain board of
# wood would read as a magic item everywhere that asks.
const SALVAGE := ["dagger", "handaxe", "spear", "shortsword", "light-crossbow",
	"leather", "studded-leather", "chain-shirt"]


# {} on most ticks — the caller only calls this once per EVENT_INTERVAL of road.
# Otherwise the resolved event: what happened, the roll behind it, and what it
# cost or paid. Already applied; nothing is left for the caller to decide.
static func check(party, world, rng = null) -> Dictionary:
	if party == null or world == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("travel|%d" % int(world.clock.elapsed)))))
	var table: Array = _table(party, world)
	if table.is_empty():
		return {}                      # nothing this country and this party could plausibly meet
	var e: Dictionary = table[rng.roll_die(table.size()) - 1]
	var out: Dictionary = {"id": e["id"], "title": e["title"], "kind": e["kind"]}

	# The one event with no check: good ground is good ground.
	if e["skills"].is_empty():
		world.clock.elapsed = maxf(0.0, world.clock.elapsed - TIME_SAVED)
		out["ok"] = true
		out["text"] = String(e["pass"])
		out["minutes"] = -TIME_SAVED
		return out

	var who := _assign(party, e, orders(party))
	if who.is_empty():
		return {}                      # nobody left to roll: no event rather than a fake one
	var bonus: int = int(who["bonus"]) + pace_bonus(party)
	var nat: int = int(Dice.d20(rng)["nat"])
	var ok: bool = nat + bonus >= int(e["dc"])
	out.merge({"ok": ok, "char_id": who["id"], "cname": who["cname"], "skill": who["skill"],
		"nat": nat, "bonus": bonus, "dc": int(e["dc"]),
		"named": bool(who["named"])}, true)
	out["text"] = (String(e["pass"]) % who["cname"]) if ok else String(e["fail"])
	_apply(e, ok, party, world, rng, out)
	return out


# Which of the EVENTS could actually happen here, to this party, right now.
#
# The filter is the price of a table that resolves itself: the player never gets
# to say "there is no shrine, I looked" — the card simply tells them there was
# one — so the table has to decline to roll anything the world it is describing
# would not hold. Two gates, both cheap enough to run on every tick:
#
#   bands  — the country under the party's feet (D6). A world too small to band
#            reads as the heartland, and a world with no player on it (a test
#            harness, a save mid-load) drops the gate rather than the event.
#   needs  — a state of the party or the map. Unknown requirements fail closed:
#            a key this version does not understand is a card it must not show.
static func _table(party, world) -> Array:
	var band := ""
	var p = world.player()
	if p != null:
		band = Regions.band_of(world, p.position)
	var out: Array = []
	for e in EVENTS:
		var bands: Array = e.get("bands", [])
		if band != "" and not bands.is_empty() and not band in bands:
			continue
		if not _needs_met(String(e.get("needs", "")), party, world):
			continue
		out.append(e)
	return out


static func _needs_met(need: String, party, world) -> bool:
	match need:
		"": return true
		"hurt": return _wounded(party) > 0
		"settlement": return not world.settlements.is_empty()
	return false


# How much healing the party has room for: the hit points the marching order is
# actually down, dead members excluded (a crossroads shrine is not a resurrection).
static func _wounded(party) -> int:
	var total := 0
	for ch in party.party_characters():
		if ch.dead:
			continue
		var max_hp: int = int(ch.sheet().max_hp)
		if ch.hp_current >= 0:
			total += maxi(0, max_hp - ch.hp_current)
	return total


# Who does this job: the standing order for the role if one is set and that
# character has any business doing it, otherwise the party's best. `named` says
# which it was, so the card can credit the player's own order.
static func _assign(party, e: Dictionary, o: Dictionary) -> Dictionary:
	var c = Campaign.new(party)
	var role := String(e.get("role", ""))
	var ordered := String(o.get(role, "")) if role != "" else ""
	var best_id := ""
	var best_skill := ""
	var best_bonus := -99
	for skill in e["skills"]:
		if ordered != "":
			var ob: int = c.skill_bonus(ordered, String(skill))
			if ob > best_bonus:
				best_bonus = ob
				best_id = ordered
				best_skill = String(skill)
			continue
		var id: String = c.best_at(String(skill))
		if id == "":
			continue
		var b: int = c.skill_bonus(id, String(skill))
		if b > best_bonus:
			best_bonus = b
			best_id = id
			best_skill = String(skill)
	if best_id == "":
		return {}
	var ch = party.get_member(best_id)
	return {"id": best_id, "cname": ch.cname if ch != null else "Someone",
		"skill": best_skill, "bonus": best_bonus, "named": best_id == ordered and ordered != ""}


static func _apply(e: Dictionary, ok: bool, party, world, rng, out: Dictionary) -> void:
	match String(e["id"]):
		"rough-going":
			if not ok:
				world.clock.elapsed += TIME_LOST
				out["minutes"] = TIME_LOST
		"foul-water":
			if not ok:
				out["hurt"] = _hp_toll(party, SICK_HP_PCT)
		"tracks":
			if ok:
				var found = _reveal_nearest_lair(party, world)
				if found != null:
					out["lair"] = found.sname
					out["text"] = "%s  %s is out there — it is on the map now." % [
						out["text"], found.sname]
				else:
					# Nothing left to find: say so rather than implying a discovery
					# the map cannot show.
					out["text"] = "%s  Nothing they do not already know about." % out["text"]
		"wayfarer", "cache":
			if ok:
				var gold: int = COIN_MIN + rng.roll_die(COIN_MAX - COIN_MIN + 1) - 1
				party.add_gold(gold)
				out["gold"] = gold
		"storm":
			if not ok:
				world.clock.elapsed += STORM_LOST
				out["minutes"] = STORM_LOST
		"waystone":
			if ok:
				world.clock.elapsed = maxf(0.0, world.clock.elapsed - WAYSTONE_SAVED)
				out["minutes"] = -WAYSTONE_SAVED
		"snare":
			if not ok:
				out["hurt"] = _hp_toll(party, SNARE_HP_PCT)
		"shrine":
			if ok:
				out["healed"] = _heal(party, SHRINE_HEAL_PCT)
		"ford":
			if not ok:
				var worth: int = _between(rng, GEAR_MIN, GEAR_MAX)
				var gone: int = _take_gold(party, worth)
				out["gold"] = -gone
				if gone < worth:
					# Same honesty as the toll below: a purse the road could not
					# empty is a different card, not a silent one.
					out["text"] = "%s  There was little enough in it to lose." % out["text"]
		"toll":
			if not ok:
				var asked: int = _between(rng, TOLL_MIN, TOLL_MAX)
				var paid: int = _take_gold(party, asked)
				out["gold"] = -paid
				if paid < asked:
					# A purse that could not cover it is the more interesting
					# outcome, and saying nothing would read as the check having
					# quietly done nothing at all.
					out["text"] = "%s  The purse will not cover it. They take what is in it and let the party past." % out["text"]
		"wreck":
			if ok:
				var item: String = SALVAGE[rng.roll_die(SALVAGE.size()) - 1]
				party.stash_add(item)
				out["item"] = item
				out["item_name"] = Campaign.item_name(item)
		"carter":
			if ok:
				var coin: int = _between(rng, CARTER_MIN, CARTER_MAX)
				party.add_gold(coin)
				out["gold"] = coin
				var home = _nearest_settlement(world)
				if home != null:
					# The same faction score a finished quest moves (O7), by a
					# fraction of one: goodwill is earned in towns, and this is a
					# reminder that it can also be earned on the way to one.
					FactionOpinion.raise(home.faction, CARTER_GOODWILL)
					out["thanks"] = home.sname
					out["text"] = "%s  He is bound for %s, and word will get there before the party does." % [
						out["text"], home.sname]


# A fraction of current HP off everyone still standing, never enough to drop
# anyone — bad water and a snare are taxes on the march, not fights. The
# maxi(1, ...) floor is the invariant every road event shares: nothing rolled
# between towns may drop a character, because there is no fight to drop them in
# and nobody out there to pick them back up.
static func _hp_toll(party, pct: float) -> int:
	var total := 0
	for ch in party.party_characters():
		var s = ch.sheet()
		var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
		var loss: int = maxi(1, int(floor(cur * pct)))
		var after: int = maxi(1, cur - loss)
		total += cur - after
		ch.hp_current = after
		ch.dirty()
	return total


# The other direction: a fraction of MAX HP back to everyone still standing,
# capped at full. Off max rather than off current so it is worth the same to the
# character who is nearly down as to the one who is barely scratched — and the
# dead are skipped, because a shrine by the road is not core/party.gd's
# resurrection and must not look like a cheaper one.
static func _heal(party, pct: float) -> int:
	var total := 0
	for ch in party.party_characters():
		if ch.dead:
			continue
		var max_hp: int = int(ch.sheet().max_hp)
		if ch.hp_current < 0 or ch.hp_current >= max_hp:
			continue                   # already full: -1 is full, and so is max
		var after: int = mini(max_hp, ch.hp_current + maxi(1, int(round(max_hp * pct))))
		total += after - ch.hp_current
		ch.hp_current = after
		ch.dirty()
	return total


# What the road actually got out of the purse, which is never more than is in
# it. Returned rather than assumed, so the card reports the coin that moved and
# a broke party is a different card rather than a silent one.
static func _take_gold(party, amount: int) -> int:
	var taken: int = clampi(amount, 0, party.gold)
	if taken > 0:
		party.spend_gold(taken)
	return taken


# An inclusive roll in [lo, hi] on the event's own RNG — the same shape the coin
# events have always used, pulled out now that four events want it.
static func _between(rng, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + rng.roll_die(hi - lo + 1) - 1


# Whose people the party just did a favour for: the settlement nearest the
# carter, which is the one his cart and his gossip are going to.
static func _nearest_settlement(world):
	var p = world.player()
	if p == null or world.settlements.is_empty():
		return null
	var best = null
	var best_d := INF
	for s in world.settlements:
		var d: float = p.position.distance_to(s.position)
		if d < best_d:
			best_d = d
			best = s
	return best


# The nearest lair the party has not found yet, revealed. Reuses the Lair's own
# `discovered` flag, so a lair found this way behaves exactly like one found by
# a Survival check on the map (core/world_lairs.gd) — there is no second kind of
# "discovered".
static func _reveal_nearest_lair(party, world):
	var p = world.player()
	if p == null:
		return null
	var best = null
	var best_d := INF
	for l in world.lairs:
		if l.discovered or l.looted:
			continue
		var d: float = p.position.distance_to(l.position)
		if d < best_d:
			best_d = d
			best = l
	if best != null:
		best.discovered = true
	return best
