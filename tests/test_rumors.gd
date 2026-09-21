# D5 — how a place gets onto your map. The model only, headless.
#
# The thing being pinned: a lair found by asking in a town is the SAME kind of
# found as one walked into. There is one `discovered` flag and one meaning of
# it, so nothing downstream (the map marker, the lair button, core/site.gd) has
# to learn about a second way in.
#   godot --headless --path . -s tests/test_rumors.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Rumors = preload("res://core/rumors.gd")
const Party = preload("res://core/party.gd")
const WorldLairs = preload("res://core/world_lairs.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party(gold := 500) -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.gold = gold
	return p

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _ids(offers: Array) -> Array:
	return offers.map(func(o): return String(o["lair_id"]))

func _init() -> void:
	var w := _world()
	var town = w.settlements[0]
	var near = w.add_lair(World.Lair.new("goblin-warren", Vector2(200, 0), "goblinoid"))
	var far = w.add_lair(World.Lair.new("dragon-cave", Vector2(Rumors.RANGE + 400, 0), "dragon"))
	var mid = w.add_lair(World.Lair.new("sunken-ruins", Vector2(500, 0), "undead", "Sunken Ruins"))

	# --- what a town knows -------------------------------------------------
	var offers: Array = Rumors.offers(town, w)
	check("goblin-warren" in _ids(offers), "the locals know what is close")
	check("sunken-ruins" in _ids(offers), "...and what is a few hours out")
	check(not "dragon-cave" in _ids(offers),
		"...but nobody here has heard about something %d units away" % int(Rumors.RANGE + 400))
	check(_ids(offers)[0] == "goblin-warren", "the nearest lead is the one they talk about first")
	for o in offers:
		check(String(o["text"]) != "", "%s comes with something a person would actually say" % o["lair_id"])
		check(int(o["price"]) > 0, "%s costs something" % o["lair_id"])
		# D6: and it says which country it is in. A lead you cannot price against
		# your own level is a lead sold blind.
		check(String(o["where"]).find("levels") >= 0,
			"%s says what it is going to take (%s)" % [o["lair_id"], o["where"]])
		check(String(o["region"]) != "", "...and names the country")

	# Danger is what a rumour is worth: a whisper about a dragon is not priced
	# like one about goblins.
	var dragon_far = World.Lair.new("d", Vector2(100, 0), "dragon")
	check(Rumors.price_of(town, dragon_far) > Rumors.price_of(town, near),
		"a dangerous lead costs more (%d vs %d)" % [
			Rumors.price_of(town, dragon_far), Rumors.price_of(town, near)])

	# A city charges what a city charges.
	var city = World.Settlement.new("big", Vector2.ZERO, "human", "city")
	var camp = World.Settlement.new("small", Vector2.ZERO, "human", "camp")
	check(Rumors.price_of(city, near) > Rumors.price_of(camp, near),
		"a city's common room is dearer than a camp's (%d vs %d)" % [
			Rumors.price_of(city, near), Rumors.price_of(camp, near)])

	# --- buying one --------------------------------------------------------
	var party := _party(500)
	var offer: Dictionary = Rumors.offers(town, w)[0]
	var price := int(offer["price"])
	var r: Dictionary = Rumors.buy(offer, party, w)
	check(bool(r["ok"]), "a lead can be bought")
	check(party.gold == 500 - price, "...for exactly the posted price (%d)" % price)
	check(near.discovered, "...and the place is on the map")
	check(String(r["text"]).find(near.sname) >= 0, "...named, so the player knows what they bought")

	# The same flag a Survival check sets — one meaning of "found", not two.
	# Rolled until it passes, because what is being compared is the effect of a
	# SUCCESSFUL search, not whether this particular d20 came up.
	var RNG = preload("res://core/rng.gd")
	var walked := _world()
	var wl = walked.add_lair(World.Lair.new("goblin-warren", Vector2(10, 0), "goblinoid"))
	for seed_v in range(1, 200):
		if bool(WorldLairs.search(wl, _party(), RNG.new(seed_v)).get("ok", false)):
			break
	check(wl.discovered, "walking into one and passing the check sets `discovered`")
	check(near.discovered, "...and hearing about one sets the very same flag")

	# A lead already taken is not sold twice.
	check(not "goblin-warren" in _ids(Rumors.offers(town, w)), "a known place is not still for sale")
	var again: Dictionary = Rumors.buy(offer, party, w)
	check(not bool(again["ok"]), "...and buying it again is refused")
	check(String(again["text"]) != "", "...out loud, rather than silently")

	# Nor is a lair that has already been emptied.
	mid.looted = true
	check(not "sunken-ruins" in _ids(Rumors.offers(town, w)),
		"nobody sells a lead on a place that is already cleared out")

	# --- no gold, no lead --------------------------------------------------
	var w2 := _world()
	var l2 = w2.add_lair(World.Lair.new("goblin-warren", Vector2(200, 0), "goblinoid"))
	var broke := _party(0)
	var o2: Dictionary = Rumors.offers(w2.settlements[0], w2)[0]
	var poor: Dictionary = Rumors.buy(o2, broke, w2)
	check(not bool(poor["ok"]), "a party that cannot pay hears nothing")
	check(not l2.discovered, "...and the place stays off the map")
	check(broke.gold == 0, "...and is not charged for the privilege")
	check(String(poor["text"]).find(str(int(o2["price"]))) >= 0, "...but is told the price")

	# --- the free lead, for a job done -------------------------------------
	var w3 := _world()
	var l3 = w3.add_lair(World.Lair.new("giant-hold", Vector2(300, 0), "giant"))
	var p3 := _party(100)
	var lead: Dictionary = Rumors.free_lead(w3.settlements[0], p3, w3)
	check(bool(lead["ok"]), "a turned-in job earns a lead")
	check(int(lead["price"]) == 0 and p3.gold == 100, "...and it really is free")
	check(l3.discovered, "...and puts a real place on the map")

	# Nothing left to tell is not a failure and must not be narrated as one.
	check(Rumors.free_lead(w3.settlements[0], p3, w3).is_empty(),
		"with nothing left to tell, they say nothing rather than something empty")

	# --- degenerate ---------------------------------------------------------
	var bare := _world()
	check(Rumors.offers(bare.settlements[0], bare).is_empty(), "a world with no lairs sells no leads")
	check(Rumors.free_lead(bare.settlements[0], _party(), bare).is_empty(), "...and gives none away")
	var bad: Dictionary = Rumors.buy({"lair_id": "nope", "price": 10}, _party(), bare)
	check(not bool(bad["ok"]), "a lead on a lair that does not exist is refused")
	# downtime's bad lead: a rumour that names nothing, and marks nothing
	var dud: Dictionary = Rumors.dud(bare.settlements[0])
	check(bool(dud["ok"]) and bool(dud["dud"]) and int(dud["price"]) == 0 and not dud.has("lair_id") and not dud.has("landmark_id"),
		"a dud is a free lead to nowhere")
	check(dud["text"].begins_with("A man at the bar knew exactly where the treasure was."), "...with the bar's line on it")

	print("test_rumors: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
