# T9x: _make_camp() end to end — a safe night grants the long rest and stamps
# the cooldown; an ambushed one launches a real combat scene with the right
# scouted_ahead/forced_ambush flag for whichever way the watch check went.
# Brute-forces a (time, position) pair for each branch off WorldCamp's own
# seed formula — same "scatter seeds until every branch shows up" trick
# test_world_lairs.gd already uses for its own seeded roll.
#
# Run twice, once per kind of map (#231): on the free plane (SORCMERC_ROUTES=0,
# the opt-out it was written for) and on the roads (the default). A camp may be
# made anywhere on a road (the owner's call), and there the night is as risky
# as that stretch — RouteTravel.camp_ambush_pct instead of WorldCamp's flat
# AMBUSH_CHANCE_PCT — so the search for each branch's minute reads the odds the
# screen will roll (_pct), and the roads' pass also asks that a minute the flat
# odds would have slept through and the road's would not is jumped
# (_road_odds). The company camps where the map sets it down, on a road. What
# else differs on the roads:
#   * the inn is walked into by a click on the town (tests/road_screen.gd), not
#     opened from wherever the company stands;
#   * the band that stops a short rest is stood at the company's feet with
#     world.add_party(), as on the free plane — which is also how the road's
#     own RouteTravel.band_for stands a band it sent for its meeting;
#   * the band in the dark is a band pinned on the road ahead
#     (core/route_pins.gd), met as the march walks up to it, so the meeting
#     goes through _check_routes to the same _meet and night watch. The watch's
#     roll is seeded off the band and the minute it is met, so each meeting's
#     own minute says what the screen must have done, and bands are met until
#     both outcomes have been seen (_night_on_the_road).
#   godot --headless --path . -s tests/test_world_camp_integration.gd
extends SceneTree

const WorldCamp = preload("res://core/world_camp.gd")
const Visit = preload("res://core/settlement_visit.gd")
const RNG = preload("res://core/rng.gd")
const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

var _pass := 0
var _fail := 0
var _mode := ""

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", _mode, label)

# The night's odds the screen rolls where the company stands: the stretch of
# road's on a route world, the flat odds on the free plane.
func _pct(main) -> int:
	if RouteTravel.on(main.world):
		return RouteTravel.camp_ambush_pct(main.world, main.world.player().position)
	return WorldCamp.AMBUSH_CHANCE_PCT

func _find(main, want_ambush: bool) -> float:
	for t in range(1, 3000):
		var elapsed := float(t)
		var rng := RNG.new(WorldCamp.camp_seed(elapsed, main.world.player().position))
		if WorldCamp.ambush_roll(rng, _pct(main)) == want_ambush:
			return elapsed
	return -1.0   # not expected to happen — AMBUSH_CHANCE_PCT isn't that extreme

func _find_watch(main, want_ok: bool) -> float:
	for t in range(1, 3000):
		var elapsed := float(t)
		var rng := RNG.new(WorldCamp.camp_seed(elapsed, main.world.player().position))
		if not WorldCamp.ambush_roll(rng, _pct(main)):
			continue
		if WorldCamp.watch_check(main.party, rng)["ok"] == want_ok:
			return elapsed
	return -1.0

func _init() -> void:
	await _run(false)
	await _run(true)
	print("test_world_camp_integration: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run(routes: bool) -> void:
	# "0" is the free plane, where bands walk the map (#231: routes are the default)
	OS.set_environment("SORCMERC_ROUTES", "1" if routes else "0")
	_mode = "[roads] " if routes else "[free plane] "
	# --- a safe night: the long rest actually happens ---
	var safe = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(safe)
	for i in 10:
		await process_frame
	check(RouteTravel.on(safe.world) == routes, "the map is the kind this pass is for")
	safe.party.stash_add(WorldCamp.CAMP_KIT_ITEM)
	var t_safe := _find(safe, false)
	check(t_safe >= 0.0, "found a (time, position) pair with no ambush")
	safe.world.clock.elapsed = t_safe
	var kits0: int = safe.party.stash_count(WorldCamp.CAMP_KIT_ITEM)
	safe._make_camp()   # no ambush -> synchronous, no await inside it
	# The first safe night is the fire's: a hero with an untold calling speaks
	# first (world.gd's _fireside, "calling-<background>"), else the night itself.
	check(safe._event_card != null and (safe._event_card._s("id") in ["camp-night", "camp-fireside"]
		or safe._event_card._s("id").begins_with("calling-")), "a quiet night is reported on the card: %s" % (safe._event_card._s("id") if safe._event_card != null else "none"))
	safe._event_card.acknowledged.emit()
	var elapsed_after: float = safe.world.clock.elapsed   # read before any more _process() ticks advance it further
	check(safe.party.stash_count(WorldCamp.CAMP_KIT_ITEM) == kits0 - 1, "a camp attempt always spends the kit")
	check(safe._combat == null, "no ambush -> no combat launched")
	check(is_equal_approx(elapsed_after, t_safe + Visit.LONG_REST_MINUTES),
		"no ambush -> the long rest actually happens")
	check(not Visit.can_long_rest(safe.party, safe.world), "...and stamps the cooldown like any other long rest")
	safe.queue_free()
	if routes:
		await _road_odds()

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
	bad.queue_free()

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
	good.queue_free()

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
	sr.queue_free()

	# --- settlement long rest: costs gold, gated on affording it ---
	var inn = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(inn)
	for i in 10:
		await process_frame
	var home = inn.world.settlements[0]
	if routes:
		var got: String = await RoadScreen.go(self, inn, home.position)
		check(got == "visit" and inn._visit.get("settlement") == home, "a click on the town marches to its inn (%s)" % got)
	else:
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
	inn.queue_free()

	# --- #85: a hostile band met in the dark, with and without a watch that hears it ---
	var night = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(night)
	await process_frame
	if routes:
		for i in 9:
			await process_frame
		await _night_on_the_road(night)
		night.queue_free()
		await process_frame
		return
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
	await process_frame

# The roads' pass only: a minute the flat odds would sleep through and the
# stretch's own odds would not (or the other way round) goes the stretch's way
# — the camp rolls the road it is on. Askable only where the two odds differ,
# as they do at the company's first camp on the road out of Riverhold.
func _road_odds() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.party.stash_add(WorldCamp.CAMP_KIT_ITEM)
	var here: Vector2 = main.world.player().position
	var pct := _pct(main)
	check(pct != WorldCamp.AMBUSH_CHANCE_PCT, "the road's night is not the flat odds here (%d%% vs %d%%)" % [pct, WorldCamp.AMBUSH_CHANCE_PCT])
	var t := -1.0
	for m in range(1, 6000):
		var flat := WorldCamp.ambush_roll(RNG.new(WorldCamp.camp_seed(float(m), here)), WorldCamp.AMBUSH_CHANCE_PCT)
		var road := WorldCamp.ambush_roll(RNG.new(WorldCamp.camp_seed(float(m), here)), pct)
		if flat != road:
			t = float(m)
			break
	check(t >= 0.0, "a minute the two odds disagree on")
	if t >= 0.0:
		main.world.clock.elapsed = t
		main._make_camp()
		for i in 3:
			await process_frame
		var id: String = main._event_card._s("id") if main._event_card != null else "none"
		var road_says := WorldCamp.ambush_roll(RNG.new(WorldCamp.camp_seed(t, here)), pct)
		check((id in ["camp-jumped", "camp-watch"]) == road_says,
			"the camp rolled the road's %d%%, not the flat %d%% (%s)" % [pct, WorldCamp.AMBUSH_CHANCE_PCT, id])
		if main._event_card != null:
			main._on_event_ack()   # the plain handler: an ambush's fight is the passes above's to launch
	main.queue_free()
	await process_frame

# The roads' pass: a hostile band met in the dark is a band on the road, met by
# the march (_check_routes -> _meet -> the night watch).
func _night_on_the_road(night) -> void:
	var w = night.world
	var np = w.player()
	check(w.sight_radius() < World.VISION_RADIUS or not w.clock.is_night(), "sight is the day radius by day")
	w.clock.elapsed = (24 + 2.0 - World.WorldClock.START_HOUR) * 60.0   # 2am on day 2
	check(w.clock.is_night(), "2am is night")
	check(is_equal_approx(w.sight_radius(), World.VISION_RADIUS * World.NIGHT_SIGHT), "...and sight closes to the night radius")
	var jumped := 0
	var heard := 0
	for n in 12:
		if jumped > 0 and heard > 0:
			break
		if not night._visit.is_empty():
			night._close_visit()
		# Back to 2am if the walking has run the night out.
		while not w.clock.is_night():
			w.clock.elapsed += 60.0
		# The farthest friendly town: a long road with the band on it.
		var dest = null
		for s in w.settlements:
			if WorldAI.is_monster(s.faction):
				continue
			if dest == null or s.position.distance_to(np.position) > dest.position.distance_to(np.position):
				dest = s
		var band = RoadScreen.band("night-band-%d" % n, "goblinoid")
		check(RoadScreen.pin_ahead(night, RoadScreen.node(dest), 30.0, band), "a band stands on the road ahead in the dark")
		RoadScreen.click(night, dest.position)
		night._halted_on_arrival = false
		w.clock.resume()
		for i in 200:
			await RoadScreen.frame(self, night)
			if w.parties.has(band) or night._approach_card != null or night._event_card != null \
					or not night._visit.is_empty() or np.at_goal():
				break
		if not w.parties.has(band):
			# The road sent somebody else first, or the march stopped short: not this band's meeting.
			if night._approach_card != null:
				RoadScreen.wave_off(night)
			elif night._event_card != null:
				night._on_event_ack()
			RoutePins.drop(w, band)
			continue
		var at := int(w.clock.elapsed)
		var ok: bool = WorldCamp.watch_check(night.party, RNG.new(maxi(1, absi(hash("night|%s|%d" % [band.id, at])))))["ok"]
		check(w.clock.is_paused(), "the clock stops for the meeting in the dark")
		if ok:
			heard += 1
			check(night._approach_card != null and night._approach_foe == band and night._event_card == null,
				"a heard band: the usual approach card, as by day")
			check(night._combat == null, "nothing launched yet")
			RoadScreen.wave_off(night)
		else:
			jumped += 1
			check(night._approach_card == null and night._event_card != null and "Jumped" in String(night._event_card._s("title")),
				"a missed watch: no approach card, the party is jumped")
			night._on_event_ack()   # the plain handler: the fight behind the card is not launched
		RoutePins.drop(w, band)
	check(jumped > 0 and heard > 0, "both outcomes of the night watch, met on the road (%d jumped, %d heard)" % [jumped, heard])
