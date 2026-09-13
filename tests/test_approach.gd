# D4 — meeting a band is a decision. The model only, headless.
# What this pins is that the four ways are a real spread: each has an upside
# somebody would want and a downside somebody would fear, and none of them
# strictly dominates another. That is the whole difference between a choice
# and a menu.
#   godot --headless --path . -s tests/test_approach.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Approach = preload("res://core/approach.gd")
const Travel = preload("res://core/travel.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _foe(faction := "bandit"):
	return World.RoamingParty.new("band", Vector2(30, 0), faction)

func _ids(opts: Array) -> Array:
	return opts.map(func(o): return String(o["id"]))

# Rolls `way` until it passes (or fails), so an outcome can be driven.
func _until(party, foe, way: String, want_ok: bool) -> Dictionary:
	for seed_v in range(1, 200):
		var r: Dictionary = Approach.resolve(party, foe, way, RNG.new(seed_v))
		if bool(r.get("ok", false)) == want_ok:
			return r
	return {}

func _init() -> void:
	var party := _party()

	# --- what is on offer --------------------------------------------------
	var opts: Array = Approach.options(party, _foe("bandit"))
	check(opts.size() == 4, "a band that can be talked to offers all four ways (%d)" % opts.size())
	check(_ids(opts) == Approach.ORDER, "...in the escalating order the card reads down")

	# Who talks is its own question, not WorldAI.CIVILIZED's: a bandit is a
	# "monster" by that list and is the most bribable thing on the map, while a
	# zombie is not taking a toll.
	var dead_opts: Array = Approach.options(party, _foe("undead"))
	check(not "parley" in _ids(dead_opts), "the dead are not talked to")
	check("avoid" in _ids(dead_opts) and "ambush" in _ids(dead_opts),
		"...but they can still be slipped or ambushed")
	check(Approach.can_parley(_foe("bandit")), "bandits want paying, which is a conversation")
	check(Approach.can_parley(_foe("goblinoid")), "so do goblins")
	for f in ["beast", "undead", "construct", "elemental", "monstrosity"]:
		check(not Approach.can_parley(_foe(f)), "%s cannot be offered anything" % f)

	# A choice you cannot price is not a choice: everything but a straight
	# charge says who rolls, what, and against what, before it is pressed.
	for o in opts:
		if String(o["id"]) == "engage":
			check(int(o["dc"]) == 0 and not o.has("skill"), "engage asks for no roll")
			continue
		check(o.has("cname") and o.has("skill") and o.has("bonus") and int(o["dc"]) > 0,
			"%s is priced before it is chosen" % o["id"])
		check(String(o["note"]) != "", "%s says what it is for" % o["id"])

	# --- both halves of every gamble, before it is taken --------------------
	# A card that shows only what a way BUYS makes every way that rolls look
	# better than the one that cannot fail. So each option states its downside in
	# the same words the resolution will use, and prints the face the die has to
	# show — the subtraction that IS the decision.
	for o in opts:
		check(String(o.get("win", "")) != "", "%s says what it buys" % o["id"])
		if String(o["id"]) == "engage":
			check(not o.has("lose"), "engage has nothing to fail, and claims none")
			check(not o.has("needs"), "...and no die face to hit")
		else:
			check(String(o.get("lose", "")) != "", "%s says what it costs when it misses" % o["id"])
			check(int(o["needs"]) == int(o["dc"]) - int(o["bonus"]),
				"%s prints the face the die has to show (%d)" % [o["id"], int(o["needs"])])

	# The toll is a number, not "they will want something": a price nobody can
	# see is a price nobody can weigh against a fight.
	var flush2 := _party()
	flush2.gold = 400
	for o in Approach.options(flush2, _foe("bandit")):
		if String(o["id"]) == "parley":
			check(int(o["toll"]) > 0, "the parley prices itself (%d)" % int(o["toll"]))
			check(String(o["win"]).find(str(int(o["toll"]))) >= 0,
				"...in the line the player reads (%s)" % o["win"])
			var paid := _until(flush2, _foe("bandit"), "parley", true)
			check(int(paid["toll"]) == int(o["toll"]),
				"...and it is the toll actually taken (%d vs %d)" % [
					int(o["toll"]), int(paid["toll"])])

	# needs() is the whole odds display, so its ends have to be honest: 5.5e has
	# no natural 1 or 20 on an ability check, so a big enough bonus really is a
	# certainty and a far enough DC really is out of reach.
	check(Approach.needs(13, 6) == 7, "a DC 13 against +6 needs a 7")
	check(Approach.needs(10, 15) == 0, "a bonus past the DC cannot fail")
	check(Approach.needs(30, 2) == 21, "and a DC past the die cannot be hit")

	# --- the spread: no way strictly dominates another ---------------------
	# Engage is the baseline: no roll, no edge, and no way to end up worse.
	var eng: Dictionary = Approach.resolve(party, _foe(), "engage", RNG.new(1))
	check(bool(eng["fight"]), "engage fights")
	check(not bool(eng["scouted_ahead"]) and not bool(eng["forced_ambush"]),
		"...on even terms, which is the point of it")

	# Ambush is the gamble. Passing buys the first round; failing HANDS it over.
	# Without that downside ambush would dominate engage and there would be no
	# decision on this card at all.
	var amb_ok := _until(party, _foe(), "ambush", true)
	var amb_no := _until(party, _foe(), "ambush", false)
	check(bool(amb_ok["scouted_ahead"]) and bool(amb_ok["fight"]),
		"a set ambush takes the first round")
	check(not bool(amb_ok["forced_ambush"]), "...and is not also ambushed")
	check(bool(amb_no["forced_ambush"]), "a blown ambush hands the first round over")
	check(bool(amb_no["fight"]), "...and the fight happens regardless")

	# Avoid is the way out, and the cost is that nothing is gained.
	var av_ok := _until(party, _foe(), "avoid", true)
	var av_no := _until(party, _foe(), "avoid", false)
	check(not bool(av_ok["fight"]), "slipping away means no fight")
	check(bool(av_no["fight"]) and bool(av_no["forced_ambush"]),
		"being seen while slipping away is the worst outcome on the card")

	# Parley buys the fight off, and the price is real gold.
	var rich := _party()
	rich.gold = 500
	var par_ok := _until(rich, _foe("bandit"), "parley", true)
	check(not bool(par_ok["fight"]), "a parley that lands means no fight")
	check(int(par_ok["toll"]) > 0 and rich.gold < 500, "...and it is paid for (%d)" % int(par_ok["toll"]))
	var par_no := _until(_party(), _foe("bandit"), "parley", false)
	check(bool(par_no["fight"]) and not bool(par_no["forced_ambush"]),
		"a failed parley is a plain fight, not a disaster")

	# The toll scales, or it is not a decision at either end of the game.
	var poor := _party(); poor.gold = 20
	var flush := _party(); flush.gold = 5000
	var t_poor := _until(poor, _foe("bandit"), "parley", true)
	var t_rich := _until(flush, _foe("bandit"), "parley", true)
	check(int(t_rich["toll"]) > int(t_poor["toll"]),
		"a fat purse is charged more than a thin one (%d vs %d)" % [
			int(t_rich["toll"]), int(t_poor["toll"])])
	var broke := _party(); broke.gold = 3
	var t_broke := _until(broke, _foe("bandit"), "parley", true)
	check(int(t_broke["toll"]) <= 3 and broke.gold >= 0,
		"nobody is charged gold they do not have (%d)" % int(t_broke["toll"]))

	# --- standing orders reach in here too ---------------------------------
	# D3's orders decide who rolls, and the pace rides on top — so a careful
	# march is genuinely better at slipping past than a forced one.
	var p2 := _party()
	var scout: String = String(p2.active[1])
	Travel.set_orders(p2, "normal", scout, scout)
	var named := Approach.options(p2, _foe())
	for o in named:
		if String(o["id"]) in ["avoid", "ambush"]:
			check(String(o["char_id"]) == scout, "%s is rolled by the named scout" % o["id"])
			check(bool(o["named"]), "...and the card can say the order is why")

	Travel.set_orders(p2, "careful", scout, scout)
	var careful: Array = Approach.options(p2, _foe())
	Travel.set_orders(p2, "forced", scout, scout)
	var forced: Array = Approach.options(p2, _foe())
	var c_avoid: int = careful.filter(func(o): return o["id"] == "avoid")[0]["bonus"]
	var f_avoid: int = forced.filter(func(o): return o["id"] == "avoid")[0]["bonus"]
	check(c_avoid > f_avoid, "a careful march slips past better than a forced one (%d vs %d)" % [
		c_avoid, f_avoid])

	# --- every resolution names its check and its roll ---------------------
	for way in ["avoid", "ambush", "parley"]:
		for seed_v in range(1, 30):
			var r: Dictionary = Approach.resolve(_party(), _foe("bandit"), way, RNG.new(seed_v))
			check(r.has("nat") and r.has("bonus") and r.has("skill") and r.has("dc"),
				"%s names its check and its roll" % way)
			check(int(r["nat"]) >= 1 and int(r["nat"]) <= 20, "%s rolled a real d20" % way)
			check(bool(r["ok"]) == (int(r["nat"]) + int(r["bonus"]) >= int(r["dc"])),
				"%s's outcome follows its own roll" % way)
			check(String(r["text"]) != "", "%s says what happened" % way)

	# --- degenerate input --------------------------------------------------
	check(Approach.resolve(_party(), _foe(), "nonsense").is_empty(), "an unknown way does nothing")
	var empty := Party.new()
	var e_opts: Array = Approach.options(empty, _foe("bandit"))
	check("engage" in _ids(e_opts), "a party with nobody to roll can still charge")
	var e_res: Dictionary = Approach.resolve(empty, _foe(), "ambush")
	check(bool(e_res["fight"]) and not bool(e_res["ok"]),
		"...and an attempt nobody can make is a plain fight, not a silent nothing")
	check(String(e_res["text"]) != "", "...and it says so")

	print("test_approach: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
