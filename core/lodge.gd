# The lodge — one house, bought once in a town where the company is Known,
# and five rooms built onto it over time. The batch gave the party ways to
# earn and the shelf to spend on; what it had nowhere to put was itself. Each
# room is a gold sink with a use on the road:
#
#   Lodge.buy(party, world, s)            # the house: 400 ◉, a deed with the town's people
#   Lodge.build(party, world, "garden")   # a room, paid at once; the garden and the map room start their clocks
#   Lodge.deposit(party, 200) / withdraw  # the strongroom: gold the road cannot take
#   Lodge.collect(party, world)           # on arrival: the garden's potions, the map room's leads
#   Lodge.retrain(party, world, ch, "sentinel", "durable")   # the yard: one general feat for another, three days
#   Lodge.bless(party, world)             # the shrine: temp HP at the next fight, once a visit
#
# Static, in core/downtime.gd's shape. State lives on party.lodge (saved
# beside downtime): {} until bought, then
#   {"settlement_id": String, "rooms": [room_id], "gold": int,
#    "garden_at": float, "maproom_at": float,   # world-minutes; < 0 = not built
#    "retrained": {char_id: last_visited}, "blessed_at": float}
# The yard's and the shrine's "once a visit" is the visit's own last_visited
# stamp, the way downtime's game and bench are; restamp() moves them when the
# screen re-reads the visit. docs/superpowers/specs/2026-09-21-lodge-design.md.
extends RefCounted

const Downtime = preload("res://core/downtime.gd")
const Ladder = preload("res://core/ladder.gd")
const Rumors = preload("res://core/rumors.gd")
const Ach = preload("res://core/achievements.gd")
const Catalog = preload("res://core/rules/catalog.gd")

# A campaign's worth of jobs, visible as it goes: 1 500 ◉ for the lot.
const HOUSE_COST := 400
const ROOMS := {
	"strongroom": {"cost": 200, "title": "the strongroom"},
	"yard":       {"cost": 300, "title": "the training yard"},
	"garden":     {"cost": 150, "title": "the herb garden"},
	"shrine":     {"cost": 200, "title": "the shrine"},
	"maproom":    {"cost": 250, "title": "the map room"},
}
# The yard: three days, and a third of what the trainer asks at level 4.
const RETRAIN_COST := 100
const RETRAIN_DAYS := 3
# The garden and the map room grow while the party is away, to a cap: a
# reason to come home, not a reason to stay.
const GARDEN_DAYS := 3
const GARDEN_CAP := 3
const GARDEN_POTION := "potions-of-healing"
const MAPROOM_DAYS := 4
const MAPROOM_CAP := 2

const WORDS := ["no", "one", "two", "three"]   # indexed by a count; every cap above is <= 3

# --- the house --------------------------------------------------------------

static func settlement(party, world):
	if party.lodge.is_empty():
		return null
	for s in world.settlements:
		if s.id == party.lodge["settlement_id"]:
			return s
	return null

static func at(party, s) -> bool:
	return not party.lodge.is_empty() and party.lodge["settlement_id"] == s.id

# A house is a relationship with a town before it is a building: one lodge,
# in a civilized town that knows the company. for_sale is the square's
# button; can_buy is whether it is lit.
static func for_sale(party, s) -> bool:
	return party.lodge.is_empty() and not load("res://core/world_ai.gd").is_monster(s.faction) \
		and Ladder.rung(s.faction) >= Ladder.KNOWN

static func can_buy(party, _world, s) -> bool:
	return for_sale(party, s) and party.gold >= HOUSE_COST

static func buy(party, world, s) -> Dictionary:
	if not can_buy(party, world, s) or not party.spend_gold(HOUSE_COST):
		return {}
	party.lodge = {"settlement_id": s.id, "rooms": [], "gold": 0, "garden_at": -1.0, "maproom_at": -1.0,
		"retrained": {}, "blessed_at": -1.0}
	Ladder.deed(s.faction)
	Ach.record("lodges", 1)
	return {"text": "The deed is signed: a house at %s, and the company's name on the door (-%d ◉)." % [s.sname, HOUSE_COST]}

# --- the rooms --------------------------------------------------------------

static func has(party, room: String) -> bool:
	return not party.lodge.is_empty() and room in party.lodge["rooms"]

static func rooms_built(party) -> int:
	return 0 if party.lodge.is_empty() else party.lodge["rooms"].size()

static func can_build(party, room: String) -> bool:
	return not party.lodge.is_empty() and ROOMS.has(room) and not has(party, room) \
		and party.gold >= int(ROOMS[room]["cost"])

# Rooms build at once — the sink is the gold; the days are downtime's. The
# garden's and the map room's clocks start here.
static func build(party, world, room: String) -> Dictionary:
	if not can_build(party, room) or not party.spend_gold(int(ROOMS[room]["cost"])):
		return {}
	party.lodge["rooms"].append(room)
	if room == "garden":
		party.lodge["garden_at"] = world.clock.elapsed
	elif room == "maproom":
		party.lodge["maproom_at"] = world.clock.elapsed
	Ach.record("lodge_rooms", rooms_built(party))
	var title := String(ROOMS[room]["title"])
	return {"text": "%s is built onto the house (-%d ◉)." % [title[0].to_upper() + title.substr(1), int(ROOMS[room]["cost"])]}

# --- the strongroom ---------------------------------------------------------

static func stored(party) -> int:
	return 0 if party.lodge.is_empty() else int(party.lodge["gold"])

# A transfer, not a spend or an income: the purse and the strongroom move
# directly, so the tallies (gold_spent, gold_earned, "broke") stay honest.
static func deposit(party, n: int) -> bool:
	if n <= 0 or n > party.gold or not has(party, "strongroom"):
		return false
	party.gold -= n
	party.lodge["gold"] = stored(party) + n
	return true

static func withdraw(party, n: int) -> bool:
	if n <= 0 or n > stored(party):
		return false
	party.lodge["gold"] = stored(party) - n
	party.gold += n
	return true

# The one thing the road cannot take: a loss (the retreat's fifteenth, a tab
# run up) is computed from party.gold and taken from party.gold, and the
# strongroom is never in the sum. The rule lives in world.gd's _retreat;
# tests/test_world_lodge.gd drives it against a stocked strongroom.

# --- the garden and the map room ------------------------------------------

# Whole periods since the stamp, to the cap, and the stamp moved on by what
# was taken: a period half-grown is still growing when the party leaves
# again. A full garden is a different thing — nothing banks past the cap, so
# the clock starts over from now.
static func _accrue(lodge: Dictionary, key: String, days: int, cap: int, now: float) -> int:
	var at := float(lodge[key])
	if at < 0.0:
		return 0
	var period := days * Downtime.DAY
	var n := mini(cap, int((now - at) / period))
	if n >= cap:
		lodge[key] = now
	elif n > 0:
		lodge[key] = at + n * period
	return n

# On arrival. The potions go into the stash identified; each lead is the
# common room's free one (Rumors.free_lead marks its target), taken from the
# lodge's town, and a wall with nothing left to mark stays as it is.
static func collect(party, world) -> Dictionary:
	var out := {"potions": 0, "leads": [], "text": ""}
	var s = settlement(party, world)
	if s == null:
		return out
	var now: float = world.clock.elapsed
	var lines: Array = []
	var potions := _accrue(party.lodge, "garden_at", GARDEN_DAYS, GARDEN_CAP, now)
	if potions > 0:
		party.stash_add(GARDEN_POTION, potions, true)
		out["potions"] = potions
		lines.append("The garden has %s ready." % ("one potion" if potions == 1 else "%s potions" % WORDS[potions]))
	var leads := _accrue(party.lodge, "maproom_at", MAPROOM_DAYS, MAPROOM_CAP, now)
	for i in leads:
		var lead: Dictionary = Rumors.free_lead(s, party, world)
		if lead.is_empty():
			break
		out["leads"].append(lead)
	if not out["leads"].is_empty():
		lines.append("The map room has %s on the wall: %s." % [
			"a new mark" if out["leads"].size() == 1 else "%s new marks" % WORDS[out["leads"].size()],
			", ".join(out["leads"].map(func(l): return String(l["sname"])))])
	out["text"] = "  ".join(lines)
	return out

# --- the yard ---------------------------------------------------------------

static func general(feat_id: String) -> bool:
	return String(Catalog.feat_src(feat_id).get("category", "")) == Downtime.TRAIN_CATEGORY

# The yard takes a hero with a general feat to swap, once a visit.
static func can_retrain(party, world, ch) -> bool:
	var s = settlement(party, world)
	if ch == null or s == null or not has(party, "yard") or not ch.feats.any(func(f): return general(f)):
		return false
	return not is_equal_approx(float(party.lodge["retrained"].get(ch.id, -2.0)), s.last_visited)

# One general feat off the build for another off the trainer's list; every
# decision the old feat asked for — its +1, and a skill or an expertise if
# the level-up screen put it there — is forgotten with it (each sits in
# ch.choices under its grant's key) and the new one decided the way the
# trainer decides it. {} when the yard will not take them; {"ok": false} when
# the purse is short of the fee and the bed. The days are downtime's:
# spend_days pays the bed and rests.
static func retrain(party, world, ch, old_feat: String, new_feat: String) -> Dictionary:
	if not can_retrain(party, world, ch) or not old_feat in ch.feats or not general(old_feat) \
			or new_feat == old_feat or not new_feat in Downtime.trainable(ch):
		return {}
	var s = settlement(party, world)
	var bed: int = Downtime.bed_cost(s, RETRAIN_DAYS, party)
	if party.gold < RETRAIN_COST + bed:
		return {"ok": false, "cost": RETRAIN_COST, "bed": bed,
			"text": "The yard wants %d ◉ for the three days, and the bed %d more." % [RETRAIN_COST, bed]}
	party.spend_gold(RETRAIN_COST)
	ch.feats.erase(old_feat)
	for g in Catalog.feat_src(old_feat).get("grants", []):
		if String(g["type"]).ends_with("-choice"):
			ch.choices.erase(String(g["key"]))
	ch.feats.append(new_feat)
	ch.dirty()
	Downtime.decide_ability(ch, new_feat)
	Downtime.spend_days(party, world, s, RETRAIN_DAYS)
	party.lodge["retrained"][ch.id] = s.last_visited
	var old_name := String(Catalog.feat_src(old_feat).get("name", old_feat.capitalize()))
	var new_name := String(Catalog.feat_src(new_feat).get("name", new_feat.capitalize()))
	return {"ok": true, "old_name": old_name, "feat_name": new_name, "days": RETRAIN_DAYS, "cost": RETRAIN_COST, "bed": bed,
		"text": "Three days in the yard, and %s puts down %s for %s.  %s" % [
			ch.cname, old_name, new_name, Downtime.bed_line(s, RETRAIN_DAYS, party)]}

# --- the shrine -------------------------------------------------------------

# The landmark shrine's door: temp HP for everyone at the next fight
# (party.blessed, spent by Party when the fight starts). Taken on leaving,
# once a visit.
static func bless(party, world) -> Dictionary:
	var s = settlement(party, world)
	if s == null or not has(party, "shrine") or is_equal_approx(float(party.lodge["blessed_at"]), s.last_visited):
		return {}
	party.lodge["blessed_at"] = s.last_visited
	party.blessed = true
	return {"text": "A moment at the shrine on the way out, and the company carries something of it onto the road."}

# --- once a visit -------------------------------------------------------------

# Downtime.restamp's twin: the screen re-reads the visit through Visit.visit()
# (a rest, the inn reopening behind a fight), which stamps last_visited
# again; the stamps that were this visit's move with it, or the rows re-arm.
static func restamp(party, s, old: float, new: float) -> void:
	if not at(party, s):
		return
	if is_equal_approx(float(party.lodge["blessed_at"]), old):
		party.lodge["blessed_at"] = new
	var r: Dictionary = party.lodge["retrained"]
	for id in r:
		if is_equal_approx(float(r[id]), old):
			r[id] = new

# --- the save -----------------------------------------------------------------

static func to_dict(party) -> Dictionary:
	return party.lodge.duplicate(true)

# JSON hands every number back as a float; the strongroom is an int, the
# stamps the floats they are. A lodge with no town is no lodge (an old save,
# an empty one), and every other key falls back to the unbuilt default.
static func from_dict(party, d) -> void:
	party.lodge = {}
	if not d is Dictionary or String(d.get("settlement_id", "")) == "":
		return
	var rooms: Array = []
	if d.get("rooms") is Array:
		for r in d["rooms"]:
			if ROOMS.has(String(r)):
				rooms.append(String(r))
	var retrained := {}
	if d.get("retrained") is Dictionary:
		for id in d["retrained"]:
			retrained[String(id)] = float(d["retrained"][id])
	party.lodge = {
		"settlement_id": String(d["settlement_id"]),
		"rooms": rooms,
		"gold": maxi(0, int(d.get("gold", 0))),
		"garden_at": float(d.get("garden_at", -1.0)),
		"maproom_at": float(d.get("maproom_at", -1.0)),
		"retrained": retrained,
		"blessed_at": float(d.get("blessed_at", -1.0)),
	}
