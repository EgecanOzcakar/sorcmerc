# T9x: _make_camp() end to end — a safe night grants the long rest and stamps
# the cooldown; an ambushed one launches a real combat scene with the right
# scouted_ahead/forced_ambush flag for whichever way the watch check went.
# Brute-forces a (time, position) pair for each branch off WorldCamp's own
# seed formula — same "scatter seeds until every branch shows up" trick
# test_world_lairs.gd already uses for its own seeded roll.
#   godot --headless --path . -s tests/test_world_camp_integration.gd
extends SceneTree

const WorldCamp = preload("res://core/world_camp.gd")
const Visit = preload("res://core/settlement_visit.gd")
const RNG = preload("res://core/rng.gd")
const World = preload("res://core/world.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _find(main, want_ambush: bool) -> float:
	for t in range(1, 3000):
		var elapsed := float(t)
		var rng := RNG.new(WorldCamp.camp_seed(elapsed, main.world.player().position))
		if WorldCamp.ambush_roll(rng) == want_ambush:
			return elapsed
	return -1.0   # not expected to happen — AMBUSH_CHANCE_PCT isn't that extreme

func _find_watch(main, want_ok: bool) -> float:
	for t in range(1, 3000):
		var elapsed := float(t)
		var rng := RNG.new(WorldCamp.camp_seed(elapsed, main.world.player().position))
		if not WorldCamp.ambush_roll(rng):
			continue
		if WorldCamp.watch_check(main.party, rng)["ok"] == want_ok:
			return elapsed
	return -1.0

func _init() -> void:
	# --- a safe night: the long rest actually happens ---
	var safe = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(safe)
	for i in 10:
		await process_frame
	safe.party.stash_add(WorldCamp.CAMP_KIT_ITEM)
	var t_safe := _find(safe, false)
	check(t_safe >= 0.0, "found a (time, position) pair with no ambush")
	safe.world.clock.elapsed = t_safe
	var kits0: int = safe.party.stash_count(WorldCamp.CAMP_KIT_ITEM)
	safe._make_camp()   # no ambush -> synchronous, no await inside it
	check(safe._event_card != null and safe._event_card._s("id") == "camp-night", "a quiet night is reported on the card")
	safe._event_card.acknowledged.emit()
	var elapsed_after: float = safe.world.clock.elapsed   # read before any more _process() ticks advance it further
	check(safe.party.stash_count(WorldCamp.CAMP_KIT_ITEM) == kits0 - 1, "a camp attempt always spends the kit")
	check(safe._combat == null, "no ambush -> no combat launched")
	check(is_equal_approx(elapsed_after, t_safe + Visit.LONG_REST_MINUTES),
		"no ambush -> the long rest actually happens")
	check(not Visit.can_long_rest(safe.party, safe.world), "...and stamps the cooldown like any other long rest")

	# --- ambushed, watch fails: forced_ambush, no deploy phase ---
	var bad = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(bad)
	for i in 10:
		await process_frame
	bad.party.stash_add(WorldCamp.CAMP_KIT_ITEM)
	var t_bad := _find_watch(bad, false)
	check(t_bad >= 0.0, "found an ambush+failed-watch pair")
	if t_bad >= 0.0:
		bad.world.clock.elapsed = t_bad
		bad._make_camp()
		for i in 5:
			await process_frame
		check(bad._event_card != null and bad._event_card._s("id") == "camp-jumped", "the night is reported on the card first, as jumped")
		check(bad._combat == null, "...and the fight waits behind its button")
		bad._event_card.acknowledged.emit()
		for i in 5:
			if bad._combat != null:
				break
			await process_frame
		check(bad._combat != null, "a failed watch launches a real fight")
		if bad._combat != null:
			check(bad._combat.forced_ambush and not bad._combat.scouted_ahead,
				"a failed watch sets forced_ambush, not scouted_ahead")
			bad._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5, "deaths": []}
			for i in 5:
				await process_frame
			check(bad._combat == null, "the fight resolves and clears like any other encounter")

	# --- ambushed, watch succeeds: scouted_ahead, the deploy-swap edge ---
	var good = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(good)
	for i in 10:
		await process_frame
	good.party.stash_add(WorldCamp.CAMP_KIT_ITEM)
	var t_good := _find_watch(good, true)
	check(t_good >= 0.0, "found an ambush+passed-watch pair")
	if t_good >= 0.0:
		good.world.clock.elapsed = t_good
		good._make_camp()
		for i in 5:
			await process_frame
		check(good._event_card != null and good._event_card._s("id") == "camp-watch", "a caught ambush is reported as caught")
		good._event_card.acknowledged.emit()
		for i in 5:
			if good._combat != null:
				break
			await process_frame
		check(good._combat != null, "a passed watch still means a fight (an ambush attempt happened)")
		if good._combat != null:
			check(good._combat.scouted_ahead and not good._combat.forced_ambush,
				"a passed watch sets scouted_ahead (deploy-swap), not forced_ambush")
			good._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5, "deaths": []}
			for i in 5:
				await process_frame
			check(good._combat == null, "the fight resolves and clears like any other encounter")

	# --- short rest: works when safe, refuses when a hostile is close ---
	var sr = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(sr)
	for i in 10:
		await process_frame
	var before_sr: float = sr.world.clock.elapsed
	sr._short_rest()
	check(is_equal_approx(sr.world.clock.elapsed, before_sr + Visit.SHORT_REST_MINUTES),
		"a short rest works out in the open when nothing hostile is near")

	var raider = sr.world.add_party(World.RoamingParty.new("raider", sr.world.player().position, "bandit"))
	var before_sr2: float = sr.world.clock.elapsed
	sr._short_rest()
	check(is_equal_approx(sr.world.clock.elapsed, before_sr2),
		"a short rest refuses with a hostile band right on top of the party")
	sr.world.parties.erase(raider)

	# --- settlement long rest: costs gold, gated on affording it ---
	var inn = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(inn)
	for i in 10:
		await process_frame
	var home = inn.world.settlements[0]
	inn._open_visit(home)
	var cost := Visit.inn_cost(home)
	inn.party.gold = cost - 1
	var clock0: float = inn.world.clock.elapsed
	inn._rest()
	check(is_equal_approx(inn.world.clock.elapsed, clock0), "can't afford the room -> no rest happens")
	check(inn.party.gold == cost - 1, "...and nothing was charged either")

	inn.party.gold = cost
	inn._rest()
	check(inn.party.gold == 0, "affording the room spends exactly its cost")
	check(inn.world.clock.elapsed > clock0, "and the rest actually happens once it's paid for")

	# --- #85: a hostile band met in the dark, with and without a watch that hears it ---
	var night = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(night)
	await process_frame
	var World = load("res://core/world.gd")
	var np = night.world.player()
	var band = night.world.add_party(World.RoamingParty.new("night-band", np.position + Vector2(5, 0), "goblinoid"))
	check(night.world.sight_radius() < World.VISION_RADIUS or not night.world.clock.is_night(), "sight is the day radius by day")
	# 2am: find a minute where the watch misses, and one where it hears
	var miss := -1.0
	var hear := -1.0
	for m in range(0, 180):
		var t: float = (24 + 2.0 - World.WorldClock.START_HOUR) * 60.0 + m   # 2am on day 2
		var ok: bool = WorldCamp.watch_check(night.party, RNG.new(maxi(1, absi(hash("night|%s|%d" % [band.id, int(t)])))))["ok"]
		if ok and hear < 0.0: hear = t
		if not ok and miss < 0.0: miss = t
	check(miss >= 0.0 and hear >= 0.0, "both outcomes of the night watch exist within a few hours")
	night.world.clock.elapsed = miss
	check(night.world.clock.is_night(), "2am is night")
	check(is_equal_approx(night.world.sight_radius(), World.VISION_RADIUS * World.NIGHT_SIGHT), "...and sight closes to the night radius")
	night._check_encounter()
	check(night._approach_card == null and night._event_card != null and "Jumped" in String(night._event_card._s("title")),
		"a missed watch: no approach card, the party is jumped")
	check(night.world.clock.is_paused(), "...and the clock stops for the card")
	night._on_event_ack()
	night.world.clock.elapsed = hear
	night._check_encounter()
	check(night._approach_card != null, "a heard band: the usual approach card, as by day")
	check(bool(night._combat == null), "nothing launched yet")
	night._close_approach()
	night.queue_free()

	print("test_world_camp_integration: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
