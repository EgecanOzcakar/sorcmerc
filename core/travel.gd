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
# ponytail: every event here resolves itself. Events that stop and ask the
# player something are D4's shape, not this one's — when they land, `check()`
# grows an "options" key and world.gd learns to wait for an answer.
extends RefCounted

const Campaign = preload("res://core/campaign.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const RoadSpells = preload("res://core/road_spells.gd")

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
	var m := float(PACE[orders(party)["pace"]]["speed"])
	if RoadSpells.is_swift(party):   # Fly / Longstrider: the forced march's ground, none of its penalty
		m = maxf(m, RoadSpells.SWIFT_MULT)
	return m

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


# {} on most ticks — the caller only calls this once per EVENT_INTERVAL of road.
# Otherwise the resolved event: what happened, the roll behind it, and what it
# cost or paid. Already applied; nothing is left for the caller to decide.
# A spell in the party's repertoire answers some events without a roll: the
# animals say whose tracks, the water is purified before anyone drinks.
const SPELL_PASS := {
	"tracks": {"spells": ["speak-with-animals"],
		"text": "%s asks the birds. They know exactly whose tracks, and where they went."},
	"foul-water": {"spells": ["purify-food-and-drink"],
		"text": "%s purifies it before anyone drinks. The stream runs clean behind them."},
}

static func check(party, world, rng = null) -> Dictionary:
	if party == null or world == null:
		return {}
	if rng == null:
		rng = RNG.new(maxi(1, absi(hash("travel|%d" % int(world.clock.elapsed)))))
	var e: Dictionary = EVENTS[rng.roll_die(EVENTS.size()) - 1]
	var out: Dictionary = {"id": e["id"], "title": e["title"], "kind": e["kind"]}

	# The one event with no check: good ground is good ground.
	if e["skills"].is_empty():
		world.clock.elapsed = maxf(0.0, world.clock.elapsed - TIME_SAVED)
		out["ok"] = true
		out["text"] = String(e["pass"])
		out["minutes"] = -TIME_SAVED
		return out

	var sp: Dictionary = SPELL_PASS.get(String(e["id"]), {})
	var caster = party.caster_of(sp.get("spells", [])) if not sp.is_empty() else null
	if caster != null:
		out.merge({"ok": true, "char_id": caster.id, "cname": caster.cname, "skill": "",
			"spell": String(sp["spells"][0]), "text": String(sp["text"]) % caster.cname, "named": false}, true)
		_apply(e, true, party, world, rng, out)
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
				out["hurt"] = _sicken(party)
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


# A fraction of current HP off everyone still standing, never enough to drop
# anyone — bad water is a tax on the march, not a fight.
static func _sicken(party) -> int:
	var total := 0
	for ch in party.party_characters():
		var s = ch.sheet()
		var cur: int = ch.hp_current if ch.hp_current >= 0 else s.max_hp
		var loss: int = maxi(1, int(floor(cur * SICK_HP_PCT)))
		var after: int = maxi(1, cur - loss)
		total += cur - after
		ch.hp_current = after
		ch.dirty()
	return total


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
