# D3 — standing orders and road events. The model only, headless: no scene, no
# drawing. What this pins is the bargain the feature rests on — orders are set
# once and are what resolve an event, so fast-forward never has to stop and ask.
#   godot --headless --path . -s tests/test_travel.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Regions = preload("res://core/regions.gd")
const World = preload("res://core/world.gd")
const Travel = preload("res://core/travel.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const RoadSpells = preload("res://core/road_spells.gd")
const WorldSave = preload("res://core/world_save.gd")
const RNG = preload("res://core/rng.gd")

# #164: a duck-typed stand-in for Character, limited to the id/dead/sheet()
# surface Travel.gd reads — for a walking speed no real species data has today.
class _SlowChar extends RefCounted:
	var id: String
	var cname: String
	var dead := false
	var speeds: Dictionary
	func _init(id_v: String, name_v: String, walk: int) -> void:
		id = id_v; cname = name_v; speeds = {"walk": walk}
	func sheet(): return self

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

# The same world with the party standing `frac` of the map's extent out from
# the anchor, which is what decides the D6 band under their feet — and therefore
# which half of D3.1's table the road is allowed to roll (EVENTS' `bands`).
func _world_out(frac: float) -> World:
	var w := _world()
	w.player().position = Vector2(Regions.extent(w) * frac, 0.0)
	return w

# Rolls until the named event comes up, so a test can drive one event rather
# than whatever the clock happened to land on.
func _force(party, w, want: String) -> Dictionary:
	return _force_where(party, w, want, func(_e): return true)

# ...and the same with a condition on the outcome, for the tests that only care
# about a pass or only about a fail. `tries` is generous because D3.1's table is
# fourteen events deep and some of these want one specific side of one specific
# event's roll.
func _force_where(party, w, want: String, ok_when: Callable, tries := 1200) -> Dictionary:
	for seed_v in range(1, tries):
		var e: Dictionary = Travel.check(party, w, RNG.new(seed_v))
		if String(e.get("id", "")) == want and ok_when.call(e):
			return e
	return {}

# The SEED that produces the wanted event, rather than the event itself — for
# the tests that need to watch one event land on a party in a known state. A
# search cannot be that party: every roll it walks past is already applied, so
# by the time it finds a failed toll the purse it was told to empty has been
# paid twice over by wayfarers. The probe is kept topped up as it goes, because
# the table itself depends on the party (EVENTS' `needs`) and a probe quietly
# bleeding would stop looking at the same table the replay will roll on.
func _seed_of(w, want: String, ok_when: Callable, tries := 1200) -> int:
	var probe := _party()
	for seed_v in range(1, tries):
		var e: Dictionary = Travel.check(probe, w, RNG.new(seed_v))
		_top_up(probe)
		if String(e.get("id", "")) == want and ok_when.call(e):
			return seed_v
	return 0

# Everybody back to full. -1 is full (core/character.gd), which is also the
# state a freshly built roster is in.
func _top_up(party) -> void:
	for ch in party.party_characters():
		ch.hp_current = -1

func _init() -> void:
	# --- standing orders --------------------------------------------------
	var party := _party()
	check(String(Travel.orders(party)["pace"]) == "normal", "a party with no orders marches at normal")
	check(Travel.speed_mult(party) == 1.0, "...at unmodified speed")
	check(Travel.pace_bonus(party) == 0, "...with no edge on the road")

	Travel.set_orders(party, "careful", "", "")
	check(String(Travel.orders(party)["pace"]) == "careful", "a pace order sticks")
	check(Travel.speed_mult(party) < 1.0, "careful is slower (%.2f)" % Travel.speed_mult(party))
	check(Travel.pace_bonus(party) > 0, "...and reads the road better")

	Travel.set_orders(party, "forced", "", "")
	check(Travel.speed_mult(party) > 1.0, "a forced march covers ground (%.2f)" % Travel.speed_mult(party))
	check(Travel.pace_bonus(party) < 0, "...and misses things")

	Travel.set_orders(party, "nonsense", "", "")
	check(String(Travel.orders(party)["pace"]) == "normal", "an unknown pace falls back rather than breaking")

	# An order naming somebody who is not marching is not an order.
	var first: String = String(party.active[0])
	Travel.set_orders(party, "normal", first, first)
	check(String(Travel.orders(party)["scout"]) == first, "a named scout is remembered")
	party.bench(first)
	check(String(Travel.orders(party)["scout"]) == "", "...and forgotten once they are benched")
	check(String(Travel.orders(party)["watch"]) == "", "...same for the watch")

	# --- the orders are what resolve the event ----------------------------
	# The whole bargain: nothing is asked at the time, so who was named hours
	# ago has to be who actually rolls.
	var p2 := _party()
	var w2 := _world()
	var scout: String = String(p2.active[1])
	Travel.set_orders(p2, "normal", scout, scout)
	var tracks: Dictionary = _force(p2, w2, "tracks")
	check(not tracks.is_empty(), "the tracks event is reachable")
	check(String(tracks["char_id"]) == scout, "the named scout is who reads the tracks")
	check(bool(tracks["named"]), "...and the card can say it was the player's own order")

	var p3 := _party()
	var w3 := _world()
	Travel.set_orders(p3, "normal", "", "")
	var tracks3: Dictionary = _force(p3, w3, "tracks")
	check(not bool(tracks3["named"]), "with nobody named, the party's best rolls instead")
	check(String(tracks3["char_id"]) != "", "...and somebody still rolls")

	# Pace rides on top of whoever rolls, which is what makes it a real setting.
	var p4 := _party()
	var w4 := _world()
	Travel.set_orders(p4, "careful", "", "")
	var careful: Dictionary = _force(p4, w4, "rough-going")
	Travel.set_orders(p4, "forced", "", "")
	var forced: Dictionary = _force(p4, w4, "rough-going")
	check(int(careful["bonus"]) > int(forced["bonus"]),
		"a careful march rolls better than a forced one (%d vs %d)" % [
			int(careful["bonus"]), int(forced["bonus"])])

	# --- every event names its check and its roll -------------------------
	# The house rule: never "something happened".
	var seen := {}
	var p5 := _party()
	var w5 := _world()
	for seed_v in range(1, 300):
		var e: Dictionary = Travel.check(p5, w5, RNG.new(seed_v))
		if e.is_empty():
			continue
		seen[String(e["id"])] = true
		check(e.has("title") and String(e["title"]) != "", "%s has a title" % e["id"])
		check(e.has("text") and String(e["text"]) != "", "%s says what happened" % e["id"])
		check(String(e["kind"]) in ["good", "bad"], "%s reads as good or bad" % e["id"])
		if e.has("dc") and int(e["dc"]) > 0:
			check(e.has("nat") and e.has("bonus") and e.has("skill"),
				"%s names its check and its roll" % e["id"])
			check(int(e["nat"]) >= 1 and int(e["nat"]) <= 20, "%s rolled a real d20" % e["id"])
			check(bool(e["ok"]) == (int(e["nat"]) + int(e["bonus"]) >= int(e["dc"])),
				"%s's outcome follows its own roll" % e["id"])
	check(seen.size() >= 5, "the table is varied, not one event (%d kinds seen)" % seen.size())

	# --- what the events actually cost and pay ----------------------------
	var p6 := _party()
	var w6 := _world()
	var before: float = w6.clock.elapsed
	var rough: Dictionary = {}
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(p6, w6, RNG.new(seed_v))
		if String(e.get("id", "")) == "rough-going" and not bool(e["ok"]):
			rough = e
			break
	check(not rough.is_empty(), "a failed rough-going is reachable")
	check(float(rough.get("minutes", 0.0)) > 0.0, "...and costs time")

	# Good ground gives time back and never asks for a roll.
	var p7 := _party()
	var w7 := _world()
	w7.clock.elapsed = 5000.0
	var good := _force(p7, w7, "good-ground")
	check(not good.is_empty() and bool(good["ok"]), "clear running is a plain good thing")
	check(float(good["minutes"]) < 0.0, "...and hands time back")
	check(not good.has("nat"), "...with no check to pass or fail")

	# Foul water taxes the march without ever dropping anybody — it is a bad
	# marching order, not an encounter.
	var p8 := _party()
	var w8 := _world()
	for ch in p8.party_characters():
		ch.hp_current = 3
	var foul := {}
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(p8, w8, RNG.new(seed_v))
		if String(e.get("id", "")) == "foul-water" and not bool(e["ok"]):
			foul = e
			break
	if not foul.is_empty():
		for ch in p8.party_characters():
			check(ch.hp_current >= 1, "%s is sickened, never dropped" % ch.id)

	# Coin events pay the party, and say how much.
	var p9 := _party()
	var w9 := _world()
	var gold0: int = p9.gold
	var paid := {}
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(p9, w9, RNG.new(seed_v))
		if String(e.get("id", "")) in ["wayfarer", "cache"] and bool(e["ok"]):
			paid = e
			break
	if not paid.is_empty():
		check(int(paid["gold"]) > 0 and p9.gold > gold0, "a paying event actually pays (+%d)" % int(paid["gold"]))

	# Tracks put a real lair on the map — the same `discovered` flag a Survival
	# check on the map sets, not a second kind of found.
	var p10 := _party()
	var w10 := _world()
	w10.add_lair(World.Lair.new("goblin-warren", Vector2(200, 0), "goblinoid"))
	var found := {}
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(p10, w10, RNG.new(seed_v))
		if String(e.get("id", "")) == "tracks" and bool(e["ok"]):
			found = e
			break
	check(not found.is_empty(), "a successful tracks read is reachable")
	check(w10.lairs[0].discovered, "...and the lair really is on the map now")
	check(found.has("lair"), "...and the card is told which one")

	# --- D3.1: the country decides which table the road rolls ---------------
	# A self-resolving card cannot be argued with, so it must not describe a
	# world the player can see is not there: no toll posts past the last
	# waystone, no dead companies in the farmed heartland.
	var p11 := _party()
	var deeps := _world_out(0.95)
	check(Regions.band_of(deeps, deeps.player().position) == "deeps", "the test party really is in the deeps")
	var settled_out_there := 0
	var wilds_out_there := 0
	for seed_v in range(1, 300):
		var e: Dictionary = Travel.check(p11, deeps, RNG.new(seed_v))
		if String(e.get("id", "")) in ["toll", "carter"]:
			settled_out_there += 1
		if String(e.get("id", "")) == "wreck":
			wilds_out_there += 1
	check(settled_out_there == 0, "nobody is manning a toll post in the Far Deeps (%d)" % settled_out_there)
	check(wilds_out_there > 0, "...and the wrecks out there are (%d)" % wilds_out_there)

	var p12 := _party()
	var home := _world()
	check(Regions.band_of(home, home.player().position) == "heartland", "the starting town is in the heartland")
	var wrecks_at_home := 0
	for seed_v in range(1, 300):
		if String(Travel.check(p12, home, RNG.new(seed_v)).get("id", "")) == "wreck":
			wrecks_at_home += 1
	check(wrecks_at_home == 0, "no company lies dead on the farm road (%d)" % wrecks_at_home)

	# An event needing a state of the party waits for that state. A shrine is
	# worth stopping at when somebody is hurt and is scenery when nobody is.
	var p13 := _party()
	var w13 := _world()
	var shrines_at_full := 0
	for seed_v in range(1, 300):
		if String(Travel.check(p13, w13, RNG.new(seed_v)).get("id", "")) == "shrine":
			shrines_at_full += 1
		_top_up(p13)   # the road bites: a party left to bleed stops being the case under test
	check(shrines_at_full == 0, "a party at full HP never stops at the shrine (%d)" % shrines_at_full)

	for ch in p13.party_characters():
		ch.hp_current = 1
	var shrine := _force_where(p13, w13, "shrine", func(e): return bool(e["ok"]))
	check(not shrine.is_empty(), "a hurt party can find one")
	check(int(shrine.get("healed", 0)) > 0, "...and a passed check actually heals (%d)" % int(shrine.get("healed", 0)))
	var over_healed := false
	for ch in p13.party_characters():
		if ch.hp_current > int(ch.sheet().max_hp):
			over_healed = true
	check(not over_healed, "...never past full")

	# The dead are not what a roadside shrine is for.
	var p14 := _party()
	var w14 := _world()
	var corpse = p14.party_characters()[0]
	corpse.dead = true
	corpse.hp_current = 0
	for ch in p14.party_characters():
		if not ch.dead:
			ch.hp_current = 1
	var shrine2 := _force_where(p14, w14, "shrine", func(e): return bool(e["ok"]))
	if not shrine2.is_empty():
		check(corpse.hp_current == 0, "the shrine leaves the dead where they are")

	# --- what the new events cost and pay -----------------------------------
	# Time, both ways: weather sat out, and an old straight road found.
	var p15 := _party()
	var w15 := _world()
	w15.clock.elapsed = 5000.0
	var storm := _force_where(p15, w15, "storm", func(e): return not bool(e["ok"]))
	check(not storm.is_empty() and float(storm["minutes"]) > 0.0, "a storm sat out costs time")
	var waystone := _force_where(p15, w15, "waystone", func(e): return bool(e["ok"]))
	check(not waystone.is_empty() and float(waystone["minutes"]) < 0.0, "a read waystone hands time back")

	# Blood, and the floor under it: nothing on the road may drop anybody.
	var p16 := _party()
	var w16 := _world()
	for ch in p16.party_characters():
		ch.hp_current = 2
	var snare := _force_where(p16, w16, "snare", func(e): return not bool(e["ok"]))
	if not snare.is_empty():
		check(int(snare["hurt"]) > 0, "a snare walked into hurts")
		for ch in p16.party_characters():
			check(ch.hp_current >= 1, "%s is cut up, never dropped" % ch.id)

	# Coin, taken rather than given — and never more than there is. Both of
	# these replay one known seed onto a purse of a known size, because a search
	# spends and earns as it goes.
	var w17 := _world()
	var seed_ford := _seed_of(w17, "ford", func(e): return not bool(e["ok"]))
	var p17 := _party()
	p17.gold = 2000
	var ford: Dictionary = Travel.check(p17, w17, RNG.new(seed_ford)) if seed_ford > 0 else {}
	check(String(ford.get("id", "")) == "ford" and not bool(ford.get("ok", true)),
		"a bad crossing is reachable")
	check(int(ford["gold"]) < 0, "...and it is a cost, not a payout (%d)" % int(ford["gold"]))
	check(p17.gold == 2000 + int(ford["gold"]), "...and exactly that much left the purse (%d)" % p17.gold)

	var w18 := _world()
	var seed_toll := _seed_of(w18, "toll", func(e): return not bool(e["ok"]))
	var p18 := _party()
	p18.gold = 0
	var toll: Dictionary = Travel.check(p18, w18, RNG.new(seed_toll)) if seed_toll > 0 else {}
	check(String(toll.get("id", "")) == "toll", "a toll post is reachable in settled country")
	check(p18.gold == 0 and int(toll["gold"]) == 0, "a purse with nothing in it pays nothing")
	check(String(toll["text"]) != "", "...and the card still says what happened")

	var p18b := _party()
	p18b.gold = 10000
	var toll_paid: Dictionary = Travel.check(p18b, w18, RNG.new(seed_toll))
	check(int(toll_paid["gold"]) < 0 and p18b.gold == 10000 + int(toll_paid["gold"]),
		"a purse with something in it pays the toll (%d)" % int(toll_paid["gold"]))

	# Salvage: plain gear, in the stash, that the catalog has actually heard of.
	var p19 := _party()
	var w19 := _world_out(0.6)
	var wreck := _force_where(p19, w19, "wreck", func(e): return bool(e["ok"]))
	check(not wreck.is_empty(), "a wreck worth searching is reachable in the marches")
	var salvaged := String(wreck.get("item", ""))
	check(p19.stash_count(salvaged) > 0, "...and the salvage is in the stash (%s)" % salvaged)
	check(not Campaign.item_data(salvaged).is_empty(), "...and it is a real item, not an id nobody knows")
	check(not Campaign.is_magic(salvaged), "...and the road does not hand out magic items")

	# Goodwill: the one road event whose payoff is not on the party sheet at all.
	FactionOpinion.reset()
	var p20 := _party()
	var w20 := _world()
	var carter := _force_where(p20, w20, "carter", func(e): return bool(e["ok"]))
	check(not carter.is_empty(), "a carter in the ditch is reachable near a town")
	check(FactionOpinion.get_opinion("human") > 0.0,
		"...and helping him is remembered by the locals (%.1f)" % FactionOpinion.get_opinion("human"))
	check(String(carter.get("thanks", "")) == "Riverhold", "...by name, so the card can say who heard")
	FactionOpinion.reset()

	# Every event on the grown table still keeps D3's own house rule.
	var p21 := _party()
	for ch in p21.party_characters():
		ch.hp_current = 1
	var seen_ids := {}
	for frac in [0.1, 0.6, 0.95]:
		var w21 := _world_out(float(frac))
		for seed_v in range(1, 400):
			var e: Dictionary = Travel.check(p21, w21, RNG.new(seed_v))
			if e.is_empty():
				continue
			seen_ids[String(e["id"])] = true
			check(String(e["text"]) != "" and String(e["title"]) != "",
				"%s says what happened, wherever it fired" % e["id"])
	check(seen_ids.size() >= 12, "the whole table is reachable across the map (%d of %d)" % [
		seen_ids.size(), Travel.EVENTS.size()])

	# --- degenerate input --------------------------------------------------
	check(Travel.check(null, _world()).is_empty(), "no party, no event")
	check(Travel.check(_party(), null).is_empty(), "no world, no event")
	var empty := Party.new()
	var e_empty: Dictionary = Travel.check(empty, _world(), RNG.new(1))
	check(e_empty.is_empty() or e_empty.has("title"),
		"an empty roster yields no event rather than a fake one")

	# --- refugees: only on a raided road, and their pass finds the lair --------
	var wf := _world()
	var pf := _party()
	var raided_town = wf.settlements[0]
	var hidden = wf.add_lair(World.Lair.new("raider-hole", raided_town.position + Vector2(300, 0), "goblinoid", "the Raider Hole"))
	var fired := false
	for seed_v in range(1, 300):
		if String(Travel.check(pf, wf, RNG.new(seed_v)).get("id", "")) == "refugees":
			fired = true
	check(not fired, "no raid on the map: no refugees")
	raided_town.raided_by = "raider-hole"
	var passed := {}
	for seed_v in range(1, 400):
		hidden.discovered = false
		var e: Dictionary = Travel.check(pf, wf, RNG.new(seed_v))
		if String(e.get("id", "")) != "refugees":
			continue
		passed[bool(e["ok"])] = e
		check(bool(e["ok"]) == hidden.discovered, "a pass finds the lair, a fail does not (ok=%s)" % e["ok"])
	check(passed.has(true) and passed.has(false), "both outcomes reachable")
	check("on the map now" in String(passed[true]["text"]) and String(passed[true].get("lair", "")) == "the Raider Hole",
		"the pass says where they came from: %s" % passed[true]["text"])
	hidden.discovered = true
	fired = false
	for seed_v in range(1, 300):
		if String(Travel.check(pf, wf, RNG.new(seed_v)).get("id", "")) == "refugees":
			fired = true
	check(not fired, "the lair already found: nothing left for them to tell, no event")

	# --- relations (spike-party-opinions §7): morale rides every roll -------
	var pm := _party()
	var wm := _world()
	for pair in PartyOpinion.active_pairs(pm):
		PartyOpinion.set_score(pm, pair[0], pair[1], 40.0)
	var em: Dictionary = _force(pm, wm, "tracks")
	check(int(em.get("morale", 0)) == 1, "a party that pulls together reads +1 (%s)" % em.get("morale"))
	var cm := Campaign.new(pm)
	check(int(em["bonus"]) - Travel.pace_bonus(pm) - cm.skill_bonus(String(em["char_id"]), String(em["skill"])) == 1,
		"...and the +1 is actually on the roll's bonus")

	var pc := _party()
	var wc := _world()
	for pair in PartyOpinion.active_pairs(pc):
		PartyOpinion.set_score(pc, pair[0], pair[1], -30.0)
	var ec: Dictionary = _force(pc, wc, "tracks")
	check(int(ec.get("morale", 0)) == -1, "a party at odds reads -1 (%s)" % ec.get("morale"))

	var pn := _party()
	var wn := _world()
	var en: Dictionary = _force(pn, wn, "tracks")
	check(not en.has("morale"), "a neutral party carries no morale term at all")

	# The roll feeds back: a pass earns the roller a little from everyone else
	# marching; a failed "bad" event costs them instead.
	var wp := _world()
	var seed_pass := _seed_of(wp, "tracks", func(e): return bool(e["ok"]))
	var pp := _party()
	var ep: Dictionary = Travel.check(pp, wp, RNG.new(seed_pass)) if seed_pass > 0 else {}
	check(not ep.is_empty(), "a passed tracks is reachable")
	var roller_p: String = String(ep.get("char_id", ""))
	for id in pp.active:
		if String(id) != roller_p:
			check(PartyOpinion.score(pp, roller_p, String(id)) ==
				PartyOpinion.baseline_of(pp, roller_p, String(id)) + PartyOpinion.ROAD_PASS,
				"a passed event warms the roller to %s" % id)

	var wb := _world()
	var seed_fail := _seed_of(wb, "rough-going", func(e): return not bool(e["ok"]))
	var pb := _party()
	var eb: Dictionary = Travel.check(pb, wb, RNG.new(seed_fail)) if seed_fail > 0 else {}
	check(not eb.is_empty(), "a failed rough-going is reachable")
	var roller_b: String = String(eb.get("char_id", ""))
	for id in pb.active:
		if String(id) != roller_b:
			check(PartyOpinion.score(pb, roller_b, String(id)) ==
				PartyOpinion.baseline_of(pb, roller_b, String(id)) - PartyOpinion.ROAD_FAIL,
				"a failed bad event costs the roller with %s" % id)

	# #164: the party moves at its slowest active member's walking speed (5e
	# RAW). No species in data/species.json is under 30 ft today, so a slow
	# walker is faked here — a duck-typed stand-in with the id/dead/sheet()
	# surface Travel.gd actually reads (party.gd's real Character is 5e-rules
	# heavy and has no "give this hero a 25 ft stride" knob to turn).
	var pd := _party()
	for id in ["thrun", "gera"]:   # demo_roster's two extra heroes, unused here
		pd.remove_member(id)
	pd.roster.append(_SlowChar.new("thrun", "Thrun Stonefist", 25))
	pd.active.append("thrun")
	Travel.set_orders(pd, "normal")
	check(is_equal_approx(Travel.speed_mult(pd), 25.0 / 30.0),
		"a 25 ft straggler caps normal pace at 25/30 (%.3f)" % Travel.speed_mult(pd))
	check(String(Travel.slowest_walker(pd)["name"]) == "Thrun Stonefist",
		"...and Thrun is named as the one setting it")
	Travel.set_orders(pd, "forced")
	check(is_equal_approx(Travel.speed_mult(pd), 1.40 * 25.0 / 30.0),
		"...and a forced march still stacks its ×1.4 on top (%.3f)" % Travel.speed_mult(pd))

	# ...and the real way a hero gets there: heavy armour under its Str floor
	# (core/rules/resolve.gd, #164). Vera in chain mail needs Str 13.
	var weak := Presets.vera()
	weak.base_abilities["str"] = 9   # 11 with the soldier background's +2, under chain mail's 13
	weak.dirty()
	check(int(weak.sheet().speeds["walk"]) == 20, "chain mail under Str 13 is 20 ft (%d)" % int(weak.sheet().speeds["walk"]))
	check(int(Presets.vera().sheet().speeds["walk"]) == 30, "...and at her own Str it is 30")
	var pw := Party.new()
	pw.add_member(weak)
	Travel.set_orders(pw, "normal")
	check(is_equal_approx(Travel.speed_mult(pw), 20.0 / 30.0), "so she sets the company's pace at 20/30")

	# All-standard-speed party: no penalty, no note.
	var p30 := Party.new()
	for ch in [Presets.vera(), Presets.pike(), Presets.ilsa()]:
		p30.add_member(ch)
	Travel.set_orders(p30, "normal")
	check(is_equal_approx(Travel.speed_mult(p30), 1.0),
		"a party of 30-ft heroes marches at ×1.0 (%.3f)" % Travel.speed_mult(p30))
	check(Travel.walk_note(p30) == "", "...and gets no walk-speed note")
	check(Travel.walk_note(pd) != "", "...while the straggler's company does")

	# Fly / Longstrider still wins over a slow walker.
	pd.swift_until = 1.0
	pd.world_now = 0.0
	check(is_equal_approx(Travel.speed_mult(pd), RoadSpells.SWIFT_MULT),
		"a swift spell outruns even a 25 ft straggler (%.3f)" % Travel.speed_mult(pd))

	# Nobody active: keeps the pace multiplier alone, no divide-by-nothing.
	var p_empty := Party.new()
	Travel.set_orders(p_empty, "normal")
	check(is_equal_approx(Travel.speed_mult(p_empty), 1.0),
		"an empty marching order keeps ×1.0")

	# #164: NPC bands read World.FACTION_SPEED off their faction, set once at
	# creation — undead shamble, beasts outrun a soldier company.
	var w_bands := World.new()
	var undead_band = w_bands.add_party(World.RoamingParty.new("u1", Vector2.ZERO, "undead"))
	var beast_band = w_bands.add_party(World.RoamingParty.new("b1", Vector2.ZERO, "beast"))
	check(undead_band.speed < beast_band.speed, "undead lags beast (%.1f vs %.1f)" %
		[undead_band.speed, beast_band.speed])
	check(is_equal_approx(undead_band.speed, World.SPEED * 0.6), "...at exactly the faction multiplier")

	# A saved-and-reloaded band keeps its faction speed (it round-trips as a
	# plain field, core/world_save.gd never recomputes it).
	var loaded: Dictionary = WorldSave.from_dict(WorldSave.to_dict(w_bands))
	var undead_loaded = loaded["world"].parties.filter(func(p): return p.id == "u1")[0]
	check(is_equal_approx(undead_loaded.speed, World.SPEED * 0.6),
		"a reloaded undead band still shambles (%.1f)" % undead_loaded.speed)

	print("test_travel: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
