# Utility spells cast on the road, for a slot: the profile's "On the road"
# panel (scenes/profile/profile.gd) is the button, this is what it does.
# Each one sets a party flag the overworld already reads — the same doors
# the potions use (core/potions.gd): a scouted next fight, a swifter march,
# a camp that can't be jumped. A spell the game has no door for isn't here,
# and stays hidden from picks (Effects.pick_pool).
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Ach = preload("res://core/achievements.gd")

const SWIFT_MULT := 1.4   # a forced march's ground, without its -2 on the road

const ROAD := {
	"clairvoyance": {"do": "scout", "text": "The next fight starts scouted — surprise is yours."},
	"arcane-eye":   {"do": "scout", "text": "The next fight starts scouted — surprise is yours."},
	"fly":          {"do": "swift", "minutes": 10, "text": "The party covers ground at a forced march's pace for 10 minutes, with no penalty on the road."},
	"longstrider":  {"do": "swift", "minutes": 60, "text": "The party covers ground at a forced march's pace for an hour, with no penalty on the road."},
	"rope-trick":   {"do": "safe_camp", "text": "The next camp is made out of reach: no camp kit needed, no night ambush."},
	"alarm":        {"do": "alarm", "text": "The next camp is warded: an ambush is heard coming, and the party gets the drop."},
}

static func is_road(sid: String) -> bool:
	return ROAD.has(sid)

static func text(sid: String) -> String:
	return String(ROAD.get(sid, {}).get("text", ""))

static func level(sid: String) -> int:
	return int(Catalog.spell(sid).get("level", 0))

# The road spells `ch` knows, with whether a slot is there to pay for each.
static func known(party, ch) -> Array:
	var out: Array = []
	for sid in ROAD:
		if party.get_script()._knows(ch, sid):
			out.append({"id": sid, "level": level(sid), "castable": slot_for(ch, level(sid)) >= 0})
	return out

# Index of the lowest unspent slot at or above `lvl`, or -1.
static func slot_for(ch, lvl: int) -> int:
	var left := Adapter.slots_left(ch)
	for i in range(maxi(0, lvl - 1), left.size()):
		if left[i] > 0:
			return i
	return -1

static func cast(party, ch, sid: String, now: float) -> String:
	var m: Dictionary = ROAD.get(sid, {})
	var i := slot_for(ch, level(sid))
	if m.is_empty() or i < 0:
		return ""
	while ch.slots_used.size() < 9:
		ch.slots_used.append(0)
	ch.slots_used[i] += 1
	ch.dirty()
	Ach.unlock("road_spell")
	match String(m["do"]):
		"scout": party.scouted_next = true
		"swift": party.swift_until = maxf(party.swift_until, now + float(m["minutes"]))
		"safe_camp": party.safe_camp = true
		"alarm": party.alarm_set = true
	return "%s casts %s. %s" % [ch.cname, Catalog.spell(sid).get("name", sid), m["text"]]

static func is_swift(party) -> bool:
	return party.swift_until >= party.world_now and party.swift_until > 0.0
