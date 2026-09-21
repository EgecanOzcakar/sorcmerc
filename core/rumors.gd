# D5 — how a place gets onto your map.
#
# Until now a lair was found one way: walk close enough to one you did not know
# was there and pass a Survival check (core/world_lairs.gd). That is discovery
# by collision — you cannot go looking for something you have no reason to think
# exists, so the map's content was found by sweeping it rather than by hearing
# about it. In a delve cycle the town is supposed to be where you learn where to
# go next, and this is that.
#
#   Rumors.offers(settlement, world)     # what the common room is selling
#   Rumors.buy(offer, party, world)      # pay, and it goes on the map
#   Rumors.free_lead(settlement, world)  # what they tell you for nothing, on a turn-in
#
# The Survival check stays, as the secondary path it always should have been:
# you can still stumble onto something, and D3's "tracks" road event still
# reveals the nearest one. What changes is that the primary path is now a
# conversation in a town, which is what makes a town worth walking back to.
#
# What this does NOT own: the lair itself or what is inside it
# (core/world_lairs.gd, core/site.gd), the quest board (core/quest.gd), the inn's
# bed (core/settlement_visit.gd), or any drawing. Pure data + math on a
# Settlement and a World.
extends RefCounted

const Scaler = preload("res://core/scaler.gd")
const Regions = preload("res://core/regions.gd")

# How far the locals' knowledge reaches. A town knows its own country — the
# charcoal-burners and drovers who come in have been somewhere — but nobody in
# a village has heard about a barrow four days' ride away. Sized against the
# hand-placed maps, where settlements sit 400-900 units apart: big enough that
# every town has something to sell, small enough that no town sells the whole
# map.
const RANGE := 800.0

# What a lead costs. The base is what a rumour is worth at all; the rest scales
# with how dangerous the thing is, on the same faction-index proxy
# world_lairs.gd's LOOT_PER_FACTION_INDEX and site.gd's depth already use — a
# whisper about a dragon is not priced like one about goblins, because it is not
# worth the same.
const PRICE_BASE := 30
const PRICE_PER_FACTION_INDEX := 14
# A city has more people coming through it and charges accordingly; a camp
# barely has a common room.
const PRICE_BY_KIND := {"city": 1.3, "town": 1.0, "camp": 0.7}

# What the locals actually say. Keyed by the lair's faction, because what is out
# there is the one thing a rumour is really about — the rest is where and how
# frightened they sound. One line per faction, with a fallback: an unnamed
# faction gets the generic line rather than an empty rumour.
const TALK := {
	"goblinoid": "Something has been taking goats off the high pasture, and not cleanly.",
	"undead": "Nobody will go near the old ground after dark. Nobody will say why, either.",
	"giant": "A drover came in white as milk. Said the treeline moved.",
	"dragon": "There is a burned stretch out that way that nothing has grown back on.",
	"bandit": "Three carters have paid a toll on a road that has no tollhouse.",
	"beast": "The dogs will not go past the ford any more.",
	"orc": "Somebody is sharpening something out there, and it is not us.",
	"kobold": "The mine workings are not empty. They are just not ours.",
	"gnoll": "There is laughing out on the flats at night. It is not people.",
	"cultist": "A few of the quiet ones stopped coming to market. All at once.",
}
const TALK_DEFAULT := "There is something out that way that was not out that way last year."

# What the locals say about a hidden landmark — keyed by kind, since a
# landmark has no faction to hang the line on the way a lair does.
const LANDMARK_TALK := {
	"hut": "There is an old one living out past the trees who sees everything that passes.",
	"tower": "The old watch still stands, if you know which ridge.",
}


# Every lair this settlement's people could plausibly know about: near enough,
# still hidden, still worth going to. Sorted nearest first, because the closest
# lead is the one a town talks about most.
static func offers(settlement, world) -> Array:
	var out: Array = []
	for l in world.lairs:
		if l.discovered or l.looted:
			continue
		var d: float = settlement.position.distance_to(l.position)
		if d > RANGE:
			continue
		# D6: a lead says which country the place is in. Buying directions to
		# something in the Far Deeps at level 3 is a decision the player is
		# allowed to make and is not allowed to make blind.
		var band: Dictionary = Regions.at(world, l.position)
		var lv: Array = band["levels"]
		out.append({
			"lair_id": l.id, "faction": l.faction, "distance": d,
			"price": price_of(settlement, l),
			"region": String(band["label"]), "levels": lv,
			"text": String(TALK.get(l.faction, TALK_DEFAULT)),
			"where": "%s, levels %d-%d" % [String(band["label"]), int(lv[0]), int(lv[1])],
		})
	# A hidden landmark is worth a word too — half a lair's base price, and
	# only the hidden kinds: a ruin you can see from the road nobody sells.
	var Landmarks = load("res://core/landmarks.gd")   # load: landmarks.gd preloads world.gd and friends; load() keeps this file out of that closure
	for m in world.landmarks:
		if m.found or not Landmarks.is_hidden(m.kind):
			continue
		var d: float = settlement.position.distance_to(m.position)
		if d > RANGE:
			continue
		var band: Dictionary = Regions.at(world, m.position)
		out.append({
			"landmark_id": m.id, "distance": d,
			"price": int(round(PRICE_BASE * 0.5 * float(PRICE_BY_KIND.get(settlement.kind, 1.0)))),
			"region": String(band["label"]),
			"text": String(LANDMARK_TALK.get(m.kind, "Somebody out there knows the country.")),
			"where": "%s" % String(band["label"]),
		})
	out.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	return out


static func price_of(settlement, lair) -> int:
	var idx: int = maxi(0, Scaler.FACTIONS.find(lair.faction))
	var raw: float = float(PRICE_BASE + idx * PRICE_PER_FACTION_INDEX)
	return maxi(1, int(round(raw * float(PRICE_BY_KIND.get(settlement.kind, 1.0)))))


# Pay for a lead. Returns what happened, named — never a silent success, same
# contract as every other purse movement in this codebase.
static func buy(offer: Dictionary, party, world) -> Dictionary:
	if offer.has("landmark_id"):
		var m = world.landmark(String(offer["landmark_id"]))
		if m == null or m.found:
			return {"ok": false, "text": "That is old news now."}
		var lprice := int(offer.get("price", 0))
		if not party.spend_gold(lprice):
			return {"ok": false, "price": lprice, "text": "They will not talk for less than %d ◉." % lprice}
		m.found = true
		return {"ok": true, "price": lprice, "landmark_id": m.id, "sname": m.sname,
			"text": "%s  %s is on the map now (-%d ◉)." % [String(offer.get("text", "")), m.sname, lprice]}
	var lair = _lair(world, String(offer.get("lair_id", "")))
	if lair == null or lair.discovered:
		return {"ok": false, "text": "That is old news now."}
	var price := int(offer.get("price", 0))
	if not party.spend_gold(price):
		return {"ok": false, "price": price,
			"text": "They will not talk for less than %d ◉." % price}
	lair.discovered = true
	return {"ok": true, "price": price, "lair_id": lair.id, "sname": lair.sname,
		"text": "%s  %s is on the map now (-%d ◉)." % [
			String(offer.get("text", "")), lair.sname, price]}


# What you are told for nothing, because you just did them a favour: the nearest
# thing they know about, free. Hooked to a quest turn-in — a job well done is
# how a town decides you are worth telling things to, and it gives the board a
# second payout that is not gold.
#
# {} when there is nothing left to tell, which is not a failure and should not
# be narrated as one.
static func free_lead(settlement, party, world) -> Dictionary:
	var avail: Array = offers(settlement, world)
	if avail.is_empty():
		return {}
	var offer: Dictionary = avail[0].duplicate()
	if offer.has("landmark_id"):
		var m = world.landmark(String(offer["landmark_id"]))
		if m == null:
			return {}
		m.found = true
		return {"ok": true, "price": 0, "landmark_id": m.id, "sname": m.sname,
			"text": "%s  They mark %s on your map, and will not take anything for it." % [
				String(offer["text"]), m.sname]}
	offer["price"] = 0
	var lair = _lair(world, String(offer["lair_id"]))
	if lair == null:
		return {}
	lair.discovered = true
	return {"ok": true, "price": 0, "lair_id": lair.id, "sname": lair.sname,
		"text": "%s  They mark %s on your map, and will not take anything for it." % [
			String(offer["text"]), lair.sname]}


# A rumour that names nothing — downtime's bad lead (core/downtime.gd). The
# shape of a bought lead so the screen shows it as one, at no price, marking
# no lair and no landmark: it goes nowhere, and that is the story.
static func dud(_settlement) -> Dictionary:
	return {"ok": true, "price": 0, "dud": true,
		"text": "A man at the bar knew exactly where the treasure was. He drew it on a napkin. The napkin is blank in daylight."}


static func _lair(world, id: String):
	for l in world.lairs:
		if l.id == id:
			return l
	return null
