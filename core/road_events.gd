# #231 phase 3 / #232 / #234 — the road asks.
#
# D3's road events (core/travel.gd) resolved themselves: the standing orders
# set on the party screen decided who rolled, and the card reported what had
# already happened. The owner's call on #232 (2026-09-26) reverses that rule:
# every road event now STOPS and offers two or three choices, and what the
# player picks leads to different outcomes — some of them more events, some of
# them a fight, some of them a way on the map that was not there before. The
# standing orders did not go anywhere: every event built on one of D3's offers
# "as the orders have it" as a choice (Travel.resolve, exactly as D3 rolled
# it), and every other choice that calls for a check rolls it with the
# standing order for its job, the pace, the party's morale and the roller's
# traits on it (Travel.roll). An order set hours ago is a bonus on whatever the
# player decides now.
#
#   RoadEvents.pick(party, world, rng)              # {} or an event that asks
#   RoadEvents.options(e, party, world)             # the choices, as the card shows them
#   RoadEvents.choose(e, "take-the-ford", party, world, rng)   # the outcome, applied
#
# THE EVENTS ARE DATA (the owner's call): data/road_events.json, plus whatever
# the live content packs add (a pack's `road_events` file, docs/modding.md
# §5.3; Registry.apply_data() hands them to set_packs()). A pack's event with
# the same id as a built-in one replaces it. validate() is the one gate: a
# mistyped effect or a follow-up to an event that does not exist is an error
# the mod browser shows, never a choice that silently does nothing.
#
# AN EVENT:
#   {"id", "title", "text",               the situation, before anything is chosen
#    "bands": [...]?, "needs": "..."?,    where and when it can happen (as D3's)
#    "chain": true?,                      only ever a follow-up (see "next")
#    "weight": 1?,                        how often it is picked, against the rest
#    "choices": [2 or 3 of them]}
# A CHOICE:
#   {"id", "label",
#    "orders": true?        resolve the D3 event of the same id by the standing
#                           orders (built-in events only: its outcome is D3's)
#    "check": {"skills": [...], "dc": N, "role": "scout"|"watch"|""}?
#    "spells": [...]?       a caster of one of these makes it without a roll
#    "cost": {"gold": N}?   paid when chosen; offered but disabled when short
#    "pass": OUTCOME, "fail": OUTCOME       with a check or spells
#    "then": OUTCOME}                       without one
# AN OUTCOME: "text" (a %s is the roller's name) and any of EFFECTS.
#
# CHAINS (#234): an outcome's "next": {"event": id, "after": minutes} puts that
# event on the road ahead. It fires at the first road check after `after`
# world-minutes of the clock, ahead of any random pick, so a choice made on one
# stretch of road can come back three stretches later. The pending chain is
# saved with the world (world.road_chain), so a reload cannot drop it.
#
# DETERMINISM: pick() and choose() take the caller's rng; the world screen
# seeds it off the clock, like D3's roll, so a reload is not a reroll.
#
# What this does NOT own: D3's own resolution (core/travel.gd, which it calls),
# the cards (scenes/world/road_choice_card.gd asks, event_card.gd reports), the
# fight (the approach card and _launch_combat — a "fight" outcome hands back a
# band spec, like the road's own meetings), or the map's network
# (core/world_routes.gd, which a "trail" outcome writes to).
extends RefCounted

const Travel = preload("res://core/travel.gd")
const Campaign = preload("res://core/campaign.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")

const DATA := "res://data/road_events.json"

# The closed vocabulary an outcome may use — what validate() accepts, what
# docs/modding.md §5.3 lists, and what tests/test_mod_api.gd freezes.
#   text      what happened; "%s" is whoever rolled
#   minutes   time lost (+) or saved (-)
#   gold      coin found (+) or lost (-): a number, or [low, high]; a loss is
#             never more than the purse holds
#   hurt      a fraction of current HP off everyone standing, never dropping
#             anyone (Travel's rule for everything rolled between towns)
#   heal      a fraction of max HP back to everyone standing
#   item      an item id into the pack, or "salvage" for D3's wreck table
#   xp        experience, split across the party (Campaign.split_xp)
#   opinion   a number (the nearest town's people) or {"faction", "delta"}
#   reveal    "lair" (the nearest hidden one goes on the map) or "raiders"
#             (the lair behind a raid, as D3's refugees tell it)
#   trail     {"known": bool} — a way to a place on no map (the landmark
#             lead's own target, WorldRoutes.lead_target), laid from the
#             nearest place the company knows; known: shown at once, false:
#             only noticed when the company passes where it starts (the owner's
#             call: each outcome says which). A free-roaming map has no roads:
#             it reveals the nearest lair instead.
#   fight     {"faction": id or "road"} — a band, who the road here would send
#             for "road"; the world screen puts it in front of the company on
#             the approach card
#   next      {"event": id, "after": minutes} — a follow-up (CHAINS above)
const EFFECTS := ["text", "minutes", "gold", "hurt", "heal", "item", "xp", "opinion", "reveal",
	"trail", "fight", "next"]
const NEEDS := ["", "hurt", "settlement", "raided", "routes"]
const ROLES := ["", "scout", "watch"]
const MIN_CHOICES := 2
const MAX_CHOICES := 3

static var _base: Array = []
static var _base_loaded := false
static var _packs: Array = []

# --- the table --------------------------------------------------------------

static func base() -> Array:
	if not _base_loaded:
		_base_loaded = true
		var src = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_base = src if src is Array else []
	return _base

# Every live pack's events, in scan order (Registry.apply_data()).
static func set_packs(list: Array) -> void:
	_packs = list.duplicate(true)

# The table in play: the built-in events, a pack's replacing any it names.
static func events() -> Array:
	var by_id := {}
	var order: Array = []
	for e in base() + _packs:
		var id := String(e.get("id", ""))
		if not by_id.has(id):
			order.append(id)
		by_id[id] = e
	return order.map(func(id): return by_id[id])

static func event(id: String) -> Dictionary:
	for e in events():
		if String(e["id"]) == id:
			return e
	return {}

# --- validation ---------------------------------------------------------------

# Errors in a list of events, [] when it is sound. `known` is every event id the
# follow-ups may name besides the list's own (a pack may chain into a built-in);
# `own_items` the item ids a pack adds itself, which the catalog does not hold
# until after the scan (the same allowance Registry._check_effects makes).
static func validate(src, known: Array = [], own_items: Dictionary = {}) -> Array:
	var errors: Array = []
	if not src is Array:
		return ["road_events must be a list of events"]
	var ids: Array = known.duplicate()
	for e in src:
		if e is Dictionary and e.has("id"):
			ids.append(String(e["id"]))
	for e in src:
		if not e is Dictionary:
			errors.append("an event must be an object")
			continue
		var id := String(e.get("id", ""))
		var where := "road event \"%s\"" % id
		if id == "":
			errors.append("a road event needs an id")
		for key in ["title", "text"]:
			if String(e.get(key, "")) == "":
				errors.append("%s needs a %s" % [where, key])
		if not NEEDS.has(String(e.get("needs", ""))):
			errors.append("%s: needs \"%s\" is not one of %s" % [where, e.get("needs"), NEEDS])
		for b in e.get("bands", []):
			if not Regions.BANDS.any(func(x): return String(x["id"]) == String(b)):
				errors.append("%s: band \"%s\" is not a country" % [where, b])
		var choices = e.get("choices", [])
		if not choices is Array or choices.size() < MIN_CHOICES or choices.size() > MAX_CHOICES:
			errors.append("%s must offer %d or %d choices" % [where, MIN_CHOICES, MAX_CHOICES])
			continue
		var seen := {}
		for c in choices:
			if not c is Dictionary:
				errors.append("%s: a choice must be an object" % where)
				continue
			var cid := String(c.get("id", ""))
			var cw := "%s, choice \"%s\"" % [where, cid]
			if cid == "" or seen.has(cid):
				errors.append("%s: every choice needs its own id" % where)
			seen[cid] = true
			if String(c.get("label", "")) == "":
				errors.append("%s needs a label" % cw)
			if bool(c.get("orders", false)):
				if Travel.event(id).is_empty():
					errors.append("%s: \"orders\" resolves a D3 event, and there is none called \"%s\"" % [cw, id])
				continue
			var rolled: bool = c.has("check") or c.has("spells")
			if c.has("check"):
				var ck = c["check"]
				if not ck is Dictionary or not ck.get("skills", []) is Array or (ck.get("skills", []) as Array).is_empty():
					errors.append("%s: a check needs skills" % cw)
				elif not ROLES.has(String(ck.get("role", ""))):
					errors.append("%s: role \"%s\" is not one of %s" % [cw, ck.get("role"), ROLES])
			for key in (["pass", "fail"] if rolled else ["then"]):
				if not c.get(key) is Dictionary:
					errors.append("%s needs a \"%s\" outcome" % [cw, key])
				else:
					errors.append_array(_check_outcome(c[key], "%s, %s" % [cw, key], ids, own_items))
	return errors

static func _check_outcome(o: Dictionary, where: String, ids: Array, own_items: Dictionary = {}) -> Array:
	var errors: Array = []
	if o.has("item"):
		var item := String(o["item"])
		if item != "salvage" and not own_items.has(item) and Campaign.item_data(item).is_empty():
			errors.append("%s: item \"%s\" is not an item" % [where, item])
	for k in o:
		if not EFFECTS.has(String(k)):
			errors.append("%s: \"%s\" is not an outcome effect (%s)" % [where, k, ", ".join(EFFECTS)])
	if o.has("reveal") and not String(o["reveal"]) in ["lair", "raiders"]:
		errors.append("%s: reveal is \"lair\" or \"raiders\"" % where)
	if o.has("next"):
		var n = o["next"]
		if not n is Dictionary or not ids.has(String(n.get("event", ""))):
			errors.append("%s: next names no road event (\"%s\")" % [where, n.get("event", "") if n is Dictionary else n])
	if o.has("trail") and not o["trail"] is Dictionary:
		errors.append("%s: trail is {\"known\": true|false}" % where)
	if o.has("fight") and not o["fight"] is Dictionary:
		errors.append("%s: fight is {\"faction\": id or \"road\"}" % where)
	return errors

# --- picking ------------------------------------------------------------------

# The event the road puts to the company now: a follow-up whose time has come,
# first; else one of the events this country and this party could meet (the
# gates D3 always had), weighted. {} when nothing fits.
static func pick(party, world, rng) -> Dictionary:
	if party == null or world == null:
		return {}
	for i in world.road_chain.size():
		var c: Dictionary = world.road_chain[i]
		if float(c["due"]) <= world.clock.elapsed:
			world.road_chain.remove_at(i)
			var e := event(String(c["event"]))
			if not e.is_empty():
				return e
	var band := ""
	var p = world.player()
	if p != null:
		band = Regions.band_of(world, p.position)
	var table: Array = []
	var total := 0
	for e in events():
		if bool(e.get("chain", false)):
			continue
		var bands: Array = e.get("bands", [])
		if band != "" and not bands.is_empty() and not bands.any(func(b): return Regions.holds(band, String(b))):
			continue
		if not _needs_met(String(e.get("needs", "")), party, world):
			continue
		table.append(e)
		total += maxi(1, int(e.get("weight", 1)))
	if table.is_empty():
		return {}
	var r: int = rng.roll_die(total)
	for e in table:
		r -= maxi(1, int(e.get("weight", 1)))
		if r <= 0:
			return e
	return table[-1]

static func _needs_met(need: String, party, world) -> bool:
	if need == "routes":
		return world.routes != null
	return Travel._needs_met(need, party, world)

# --- asking -------------------------------------------------------------------

# The choices as the card shows them: [{id, label, hint, disabled, why}]. The
# hint says who would do it and at what ("Vera, Survival +5 vs DC 13"), a spell
# that would answer it, or what it costs — the numbers a player decides on.
static func options(e: Dictionary, party, world) -> Array:
	var out: Array = []
	var c = Campaign.new(party)
	for ch in e.get("choices", []):
		var o := {"id": String(ch["id"]), "label": String(ch["label"]), "hint": "", "disabled": false, "why": ""}
		if bool(ch.get("orders", false)):
			o["hint"] = "the standing orders decide"
		var caster = party.caster_of(ch.get("spells", [])) if ch.has("spells") else null
		if caster != null:
			o["hint"] = "%s's %s answers it" % [caster.cname, String(ch["spells"][0]).replace("-", " ")]
		elif ch.has("check"):
			var ck: Dictionary = ch["check"]
			var who := Travel._assign(party, ck, Travel.orders(party))
			if who.is_empty():
				o["disabled"] = true
				o["why"] = "nobody can"
			else:
				o["hint"] = "%s, %s %+d vs DC %d" % [who["cname"], String(who["skill"]).capitalize(),
					int(who["bonus"]) + Travel.pace_bonus(party), int(ck.get("dc", 10))]
		elif ch.has("spells"):
			o["disabled"] = true
			o["why"] = "nobody knows the spell"
		var gold: int = int(ch.get("cost", {}).get("gold", 0))
		if gold > 0:
			o["hint"] = ("%s — " % o["hint"] if o["hint"] != "" else "") + "%d gold" % gold
			if party.gold < gold:
				o["disabled"] = true
				o["why"] = "not enough gold"
		out.append(o)
	return out

# --- choosing -----------------------------------------------------------------

# The outcome of `choice_id`, applied, in the shape the event card reports
# (the roll, the text, what moved), plus what the world screen still has to do:
#   "fight": a band spec to put in front of the company
#   "chained": the id of a follow-up now on the road ahead
#   "trail": the names of places a new way now leads to
# {} when the choice cannot be taken (disabled, or nobody to roll).
static func choose(e: Dictionary, choice_id: String, party, world, rng) -> Dictionary:
	var ch: Dictionary = {}
	for c in e.get("choices", []):
		if String(c["id"]) == choice_id:
			ch = c
	if ch.is_empty():
		return {}
	var opt: Array = options(e, party, world).filter(func(o): return o["id"] == choice_id)
	if not opt.is_empty() and bool(opt[0]["disabled"]):
		return {}
	if bool(ch.get("orders", false)):
		var d3: Dictionary = Travel.resolve(Travel.event(String(e["id"])), party, world, rng)
		if not d3.is_empty():
			d3["title"] = String(e["title"])
			d3["choice"] = choice_id
		return d3
	var out := {"id": String(e["id"]), "title": String(e["title"]), "kind": "good", "choice": choice_id}
	var gold: int = int(ch.get("cost", {}).get("gold", 0))
	if gold > 0:
		party.spend_gold(gold)
		out["paid"] = gold
	var outcome: Dictionary
	var who := ""
	var caster = party.caster_of(ch.get("spells", [])) if ch.has("spells") else null
	if caster != null:
		out.merge({"ok": true, "char_id": caster.id, "cname": caster.cname, "skill": "",
			"spell": String(ch["spells"][0]), "named": false}, true)
		outcome = ch["pass"]
		who = caster.cname
	elif ch.has("check"):
		var r := Travel.roll(party, ch["check"], rng)
		if r.is_empty():
			return {}
		out.merge(r, true)
		outcome = ch["pass"] if bool(r["ok"]) else ch["fail"]
		who = String(r["cname"])
		out["kind"] = "good" if bool(r["ok"]) else "bad"
	else:
		outcome = ch.get("then", {})
		out["ok"] = true
	var text := String(outcome.get("text", ""))
	out["text"] = (text % who) if "%s" in text else text
	apply(outcome, party, world, rng, out)
	Travel._note_event(String(e["id"]))
	return out

# An outcome's effects, applied, each recorded on `out` the way D3's card
# already reads them (minutes, gold, hurt, healed, item/item_name, lair).
static func apply(o: Dictionary, party, world, rng, out: Dictionary) -> void:
	if o.has("minutes"):
		var m := float(o["minutes"])
		world.clock.elapsed = maxf(0.0, world.clock.elapsed + m)
		out["minutes"] = m
	if o.has("gold"):
		var g = o["gold"]
		var amount: int = Travel._between(rng, int(g[0]), int(g[1])) if g is Array else int(g)
		if amount >= 0:
			party.add_gold(amount)
			out["gold"] = amount
		else:
			out["gold"] = -Travel._take_gold(party, -amount)
	if o.has("hurt"):
		out["hurt"] = Travel._hp_toll(party, float(o["hurt"]))
	if o.has("heal"):
		out["healed"] = Travel._heal(party, float(o["heal"]))
	if o.has("item"):
		var item := String(o["item"])
		if item == "salvage":
			item = Travel.SALVAGE[rng.roll_die(Travel.SALVAGE.size()) - 1]
		party.stash_add(item)
		out["item"] = item
		out["item_name"] = Campaign.item_name(item)
	if o.has("xp"):
		Campaign.split_xp(party, int(o["xp"]))
		out["xp"] = int(o["xp"])
	if o.has("opinion"):
		var op = o["opinion"]
		var faction := ""
		var delta := 0.0
		if op is Dictionary:
			faction = String(op.get("faction", ""))
			delta = float(op.get("delta", 0.0))
		else:
			var home = Travel._nearest_settlement(world)
			faction = home.faction if home != null else ""
			delta = float(op)
			if home != null:
				out["thanks"] = home.sname
		if faction != "":
			if delta >= 0.0:
				FactionOpinion.raise(faction, delta)
			else:
				FactionOpinion.lower(faction, -delta)
	if o.has("reveal"):
		var l = Travel._raiders_lair(world) if String(o["reveal"]) == "raiders" else Travel._reveal_nearest_lair(party, world)
		if l != null:
			l.discovered = true
			out["lair"] = l.sname
	if o.has("trail"):
		_trail(bool(o["trail"].get("known", true)), world, out)
	if o.has("fight"):
		var spec := _fight(String(o["fight"].get("faction", "road")), world, rng)
		if not spec.is_empty():
			out["fight"] = spec
	if o.has("next"):
		var n: Dictionary = o["next"]
		world.road_chain.append({"event": String(n["event"]),
			"due": world.clock.elapsed + float(n.get("after", 0.0))})
		out["chained"] = String(n["event"])

# A way to a place on no map, from the nearest place the company knows. On a
# free-roaming map there are no ways: the nearest hidden lair is revealed.
static func _trail(known: bool, world, out: Dictionary) -> void:
	var p = world.player()
	if p == null:
		return
	if world.routes == null:
		var l = Travel._reveal_nearest_lair(null, world)
		if l != null:
			out["lair"] = l.sname
		return
	var from: String = world.routes.nearest_node(p.position, true, false)
	if from == "":
		return
	var to: String = world.routes.lead_target(world, from, "road|%s|%d" % [from, int(world.clock.elapsed)])
	if to == "":
		return
	var laid: Array = world.routes.open_route(world, from, to, "road", known)
	if laid.is_empty():
		return
	if known:
		RouteTravel._sync(world, laid)   # the place at the end is found, by the rules already there
	out["trail"] = RouteTravel.place_name(world, to) if known else ""
	out["trail_known"] = known

# A band for a "fight" outcome: the named people, or who the road here sends.
static func _fight(faction: String, world, rng) -> Dictionary:
	var p = world.player()
	if p == null:
		return {}
	var cand := {}
	if faction != "road":
		cand = {"faction": faction, "source": "country"}
	else:
		var cands: Array = RouteEncounters.candidates(world, p.position).filter(
			func(c): return WorldAI.is_monster(String(c["faction"])))
		if cands.is_empty():
			cand = {"faction": "bandit", "source": "country"}
		else:
			var total := 0.0
			for c in cands:
				total += float(c["rate"])
			var pick := float(rng.roll_die(10000) - 1) / 10000.0 * total
			cand = cands[-1]
			for c in cands:
				pick -= float(c["rate"])
				if pick < 0.0:
					cand = c
					break
	var spec := RouteEncounters.compose(world, p.position, cand, rng, "roadfight|%d" % int(world.clock.elapsed))
	spec["hostile"] = true
	return spec
