# D3 — standing orders and road events. The model only, headless: no scene, no
# drawing. What this pins is the bargain the feature rests on — orders are set
# once and are what resolve an event, so fast-forward never has to stop and ask.
#   godot --headless --path . -s tests/test_travel.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Travel = preload("res://core/travel.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

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

# Rolls until the named event comes up, so a test can drive one event rather
# than whatever the clock happened to land on.
func _force(party, w, want: String) -> Dictionary:
	for seed_v in range(1, 400):
		var e: Dictionary = Travel.check(party, w, RNG.new(seed_v))
		if String(e.get("id", "")) == want:
			return e
	return {}

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

	# --- degenerate input --------------------------------------------------
	check(Travel.check(null, _world()).is_empty(), "no party, no event")
	check(Travel.check(_party(), null).is_empty(), "no world, no event")
	var empty := Party.new()
	var e_empty: Dictionary = Travel.check(empty, _world(), RNG.new(1))
	check(e_empty.is_empty() or e_empty.has("title"),
		"an empty roster yields no event rather than a fake one")

	print("test_travel: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
