# #231 — tests/drive_world.gd's smoke test of the open-world map screen, on the
# roads. That robot keeps the free plane (SORCMERC_ROUTES=0), the opt-out it
# was written for. This one drives the default map the same way, section for
# section, wherever a section has a road counterpart:
#
#   * it renders, the clock runs, and a left-click on a TOWN is an order the
#     company walks, by road (a click on open ground is none — drive_routes.gd);
#   * pause freezes the march and resume starts it; 2x is faster; the speed
#     button wraps; a click on a town's roofs is a click on the town; the HUD
#     labels do not creep;
#   * #70: arriving at a found place halts the clock, and a new order starts it
#     (the place is a landmark whose path the march to its town noticed on the
#     way — on the roads a town at the end of a march opens instead of halting);
#   * the camera pans, turns, tilts, zooms and clamps;
#   * a hostile band on the road ahead is walked up to, charged from its card,
#     and hands off to a real scenes/main.tscn fight that freezes the map; won,
#     it pays, is torn down, the band is gone from the map and from the road,
#     and the map halts for the next order (#98) and marches again;
#   * O9 item 3's counterpart: at 8x the march cannot step over a band standing
#     on the road (core/route_pins.gd measures the whole frame's walk);
#   * O6: marching into a town opens the market — buy, steal once, rest at the
#     inn, take and turn in a job, the HUD's buttons inert, Leave — and it opens
#     again after the company has walked out and back;
#   * O7/O9: at a gate the company stands at, the three opinion bands (open,
#     refusing, guards out); a monster town's gate is a fight, marched into; a
#     town whose guards come out fights the company that marches up to it;
#   * the party and quest panels hold the clock; the way out saves the map, and
#     the saved map is still a route world.
#
# Free-plane only, and left to drive_world.gd: O5's band-on-band battle off
# screen (#229's clash) and O9's hunting band catching the company at 8x — on
# the roads no band walks the map, hunts, or meets another.
#
# Arranged, as drive_world.gd arranges its own: the bands met are pinned on the
# road ahead (core/route_pins.gd, the way a bounty or a story's band stands
# there; the free robot moves a map band up to the company) because the road
# sends its own by its own dice; the opinion bands are set by
# FactionOpinion.set_opinion, and a fight is won by filling its `result`, as
# there. The road's own traffic met on a march is waved off
# (tests/road_screen.gd's go()), the way tests/drive_routes.gd answers it.
#   godot --headless --path . -s tests/drive_world_routes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

var screen
var _fail := 0

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "1")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	screen = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(screen)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

func click(button: int, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	screen._gui_input(e)

# drive_world.gd's step, less its charge at every approach card: a card here
# is either the band a section is about, which the section answers, or the
# road's own traffic, which is waved off.
var _want = null
func step(n: int, dt := 0.1) -> void:
	for i in n:
		screen._process(dt)
		await process_frame
		if screen._event_card != null:
			screen._event_card.acknowledged.emit()
		if screen._approach_card != null and screen._approach_foe != null and screen._approach_foe != _want:
			RoadScreen.wave_off(screen)
		if screen._spoils_panel != null:
			screen._close_spoils()
		if screen._levelup_panel != null:
			screen._close_levelup()
		while screen._moment != null:
			screen._moment._skip_or_advance()

func _left_to(p, id: String) -> float:
	var way: Dictionary = screen.world.routes.path_from(p.position, id)
	return INF if way.is_empty() else float(way["length"])

func _far_town():
	var p = screen.world.player()
	var best = null
	for s in screen.world.settlements:
		if WorldAI.is_monster(s.faction):
			continue
		if best == null or s.position.distance_to(p.position) > best.position.distance_to(p.position):
			best = s
	return best

func _run() -> void:
	await process_frame
	screen.size = Vector2(1280, 800)
	await step(2)
	var w = screen.world
	var p = w.player()
	if p == null:
		fail("the scene has no player party")
		_done()
		return
	if not RouteTravel.on(w):
		fail("the default map is not a route world")
	if w.settlements.size() < 2:
		fail("the scene has nothing to render: %d settlements" % w.settlements.size())
	if not w.parties.all(func(q): return q.is_player):
		fail("somebody besides the company stands on a route world's map")

	# --- a left-click on a town is an order, walked by road ------------------
	# The march to the town whose road passes a landmark's noticed path, so #70
	# below has a found place to arrive at.
	var dest = null
	var mark = null
	for eid in w.routes.edges:
		var e: Dictionary = w.routes.edges[eid]
		if e["known"] or e["search"] or e["kind"] != "path" or not w.routes.nodes[e["notice"][0]]["known"]:
			continue
		var far: String = e["b"] if e["a"] == e["notice"][0] else e["a"]
		if w.routes.nodes[far]["kind"] != "landmark":
			continue
		for s in w.settlements:
			var way: Dictionary = w.routes.path_from(p.position, RoadScreen.node(s))
			if not way.is_empty() and (way["nodes"] as Array).has(e["notice"][0]) and s.position.distance_to(p.position) > 200.0:
				dest = s
				mark = w.landmark(String(w.routes.nodes[far]["ref"]))
				break
		if dest != null:
			break
	if dest == null:
		fail("no town's road passes a landmark's path to notice")
		dest = _far_town()
	var start: Vector2 = p.position
	var left0 := _left_to(p, RoadScreen.node(dest))
	RoadScreen.click(screen, dest.position)
	if p.at_goal():
		fail("a left-click on %s gave no order" % dest.sname)
	await step(5)
	if p.position.is_equal_approx(start):
		fail("the company never moved toward the clicked town")
	if _left_to(p, RoadScreen.node(dest)) >= left0:
		fail("the company moved, but not along the road to its town (%.0f -> %.0f)" % [left0, _left_to(p, RoadScreen.node(dest))])
	if float(w.routes.locate(p.position, true)["distance"]) > 0.5:
		fail("the march left the road")

	# --- pause freezes it, resume unfreezes --------------------------------
	screen._toggle_pause()
	if not w.clock.is_paused():
		fail("the pause button did not pause the clock")
	var held: Vector2 = p.position
	await step(5)
	if not p.position.is_equal_approx(held):
		fail("the party kept moving while paused")
	screen._toggle_pause()
	await step(5)
	if p.position.is_equal_approx(held):
		fail("resuming did not start the party moving again")

	# --- speed button cycles 1x/2x/4x/8x and actually speeds movement up ----
	var slow_step: Vector2 = p.position
	await step(1)
	slow_step = p.position - slow_step
	screen._cycle_speed()
	if w.clock.speed != 2.0:
		fail("the speed button did not move the clock to 2x")
	var fast_step: Vector2 = p.position
	await step(1)
	fast_step = p.position - fast_step
	if fast_step.length() <= slow_step.length() * 1.5:
		fail("2x did not noticeably speed up movement (%s vs %s)" % [fast_step, slow_step])
	screen._cycle_speed(); screen._cycle_speed(); screen._cycle_speed()
	if w.clock.speed != 1.0:
		fail("cycling four times did not wrap back to 1x")

	# --- #110/#113: a click on a town's roofs is a click on the town -----------
	var town = w.settlements[0]
	var town_px: Vector2 = screen._pix(town.position)
	var roof: Vector2 = town_px + Vector2(0, -30.0 * screen._zoom)
	if not screen._click_target(roof).is_equal_approx(town.position):
		fail("a click on the diorama above %s did not resolve to it (%s)" % [town.sname, screen._click_target(roof)])
	if screen._click_target(town_px + Vector2(400, 300)).is_equal_approx(town.position):
		fail("a click well away from the town snapped to it")

	# --- #94: the clock's neighbours do not creep as the digits change --------
	var gold_x: float = screen._gold_lbl.global_position.x
	var clock_text: String = screen._clock_lbl.text
	w.clock.elapsed += 1.0
	await step(2)
	if screen._clock_lbl.text == clock_text:
		fail("a minute on the clock did not change the face")
	if not is_equal_approx(screen._gold_lbl.global_position.x, gold_x):
		fail("the gold label moved when the clock ticked (%.1f -> %.1f)" % [gold_x, screen._gold_lbl.global_position.x])

	# --- #70: arriving halts the clock; a new order starts it again ----------
	var got: String = await RoadScreen.walk(self, screen)
	for i in 20:
		if got != "card":
			break
		RoadScreen.wave_off(screen)
		got = await RoadScreen.walk(self, screen)
	if got != "visit" or screen._visit.get("settlement") != dest:
		fail("the march to %s did not end at its open gate (%s)" % [dest.sname, got])
	if not screen._visit.is_empty():
		screen._close_visit()
	if mark == null or not mark.found:
		fail("the march past its fork did not find the landmark")
	else:
		got = await RoadScreen.go(self, screen, mark.position)
		if got != "arrived":
			fail("the march to %s did not arrive (%s)" % [mark.sname, got])
		await step(1)
		if not w.clock.is_paused() or screen._pause_btn.text != "Resume" or not screen._halted_on_arrival:
			fail("reaching %s did not halt the clock" % mark.sname)
		RoadScreen.click(screen, dest.position)
		await step(2)
		if w.clock.is_paused() or p.at_goal():
			fail("a new order did not start the clock again")

	# --- camera: drag-pan, middle-drag orbit and scroll-zoom ---------------
	var pan0: Vector2 = screen._pan
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_RIGHT
	m.position = Vector2(600, 400)
	m.relative = Vector2(-40, 25)
	screen._gui_input(m)
	if screen._pan.is_equal_approx(pan0):
		fail("drag did not pan the camera")
	var yaw0: float = screen.yaw()
	var pitch0: float = screen.pitch()
	var o := InputEventMouseMotion.new()
	o.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	o.position = Vector2(600, 400)
	o.relative = Vector2(90, -35)
	screen._gui_input(o)
	if is_equal_approx(screen.yaw(), yaw0) or is_equal_approx(screen.pitch(), pitch0):
		fail("middle-drag did not turn and tilt the camera")
	await step(2)
	screen.reset_view()
	if not (is_equal_approx(screen.yaw(), screen.ISO_YAW) and is_equal_approx(screen.pitch(), screen.ISO_PITCH)):
		fail("reset_view did not put the camera back")
	var at := Vector2(700, 350)
	var under: Vector2 = screen._unpix(at)
	click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._unpix(at).distance_to(under) > 1.0:
		fail("zoom did not keep the point under the cursor fixed")
	for i in 40:
		click(MOUSE_BUTTON_WHEEL_UP, at)
	if screen._zoom > screen.ZOOM_MAX:
		fail("zoom exceeded ZOOM_MAX")
	for i in 80:
		click(MOUSE_BUTTON_WHEEL_DOWN, at)
	if screen._zoom < screen.ZOOM_MIN:
		fail("zoom fell below ZOOM_MIN")
	await step(2)     # a frame at min zoom, the roads drawn far out
	screen.reset_view()

	await _encounter_handoff(p)
	await _band_at_8x(p)
	await _settlement_visit(p)
	await _hostile_settlement(p)
	await _party_and_quests()
	_exit_to_title()
	_done()

# --- a band on the road ahead: its card, the charge, a real fight ----------
func _encounter_handoff(p) -> void:
	var w = screen.world
	if not screen._visit.is_empty():
		screen._close_visit()
	var dest = _far_town()
	var foe = RoadScreen.band("road-goblins", "goblinoid")
	if not RoadScreen.pin_ahead(screen, RoadScreen.node(dest), 60.0, foe):
		fail("no road ahead to stand a band on")
		return
	_want = foe
	var got: String = await RoadScreen.go(self, screen, dest.position, foe, 800)
	if got != "card" or screen._approach_foe != foe:
		fail("the march never walked up to the band on the road (%s)" % got)
		_want = null
		RoutePins.drop(w, foe)
		return
	if not w.parties.has(foe):
		fail("the band met is not on the map for its meeting")
	screen._on_approach_chosen("engage")
	for i in 10:
		await step(1)
		if screen._combat != null:
			break
	_want = null
	if screen._combat == null:
		fail("charging the band from its card did not launch a fight")
		RoutePins.drop(w, foe)
		return
	if screen._combat.spec.get("monsters", []).is_empty():
		fail("the fight got an empty spec: %s" % [screen._combat.spec])
	if screen._combat.cb == null or screen._combat.cb.combatants.is_empty():
		fail("no live combat (Encounter-built Combat) inside the combat scene")
	elif screen._combat.cb.combatants.filter(func(c): return c.team == "foe").is_empty():
		fail("the live combat has no foes from the band")
	if not w.clock.is_paused():
		fail("the world clock kept running during the fight")
	var frozen: Vector2 = p.position
	await step(5)
	if not p.position.is_equal_approx(frozen):
		fail("the company kept marching during the fight")
	var gold0: int = screen.party.gold
	var xp0: int = screen.party.party_characters()[0].xp
	screen._combat.result = {"outcome": "Victory", "xp": 400, "gold": 50, "loot": ["handaxe"], "kills": []}
	await step(4)   # the spoils page read and closed, as drive_world.gd's step does
	if screen.party.gold != gold0 + 50:
		fail("winning a fight on the road paid no gold (%d -> %d)" % [gold0, screen.party.gold])
	if screen.party.party_characters()[0].xp <= xp0:
		fail("winning a fight on the road banked no XP")
	if screen.party.stash_count("handaxe") < 1:
		fail("the loot from a fight on the road never reached the stash")
	if screen._combat != null:
		fail("the combat scene was never torn down after the fight")
	if w.parties.has(foe) or w.pinned.has(foe):
		fail("the beaten band is still on the map or back on the road")
	if not w.clock.is_paused() or not screen._halted_on_arrival:
		fail("the map did not halt for an order after the fight (#98)")
	var Scaler = load("res://core/scaler.gd")
	var spec: Dictionary = screen.encounter_spec(World.RoamingParty.new("cult", Vector2.ZERO, "cultist"))
	var want := String(Scaler.BIOME_BOARD.get(w.biome_at(Vector2.ZERO), screen.DEFAULT_THEME))
	if spec.get("monsters", []).is_empty() or spec.get("theme", "") != want:
		fail("themeless faction got no usable spec (wanted the %s board): %s" % [want, spec])
	# ...and the map still runs: the company marches again.
	var back: Vector2 = p.position
	RoadScreen.click(screen, dest.position)
	await step(5)
	if p.position.is_equal_approx(back):
		fail("the map is not playable again after combat")

# --- O9 item 3, on the roads: at 8x the march cannot step over a band -------
func _band_at_8x(p) -> void:
	var w = screen.world
	if not screen._visit.is_empty():
		screen._close_visit()
	var dest = _far_town()
	var band = RoadScreen.band("road-hound", "goblinoid")
	if not RoadScreen.pin_ahead(screen, RoadScreen.node(dest), 40.0, band):
		fail("no road ahead to stand a band on at 8x")
		return
	_want = band
	RoadScreen.click(screen, dest.position)
	screen._halted_on_arrival = false
	w.clock.resume()
	w.clock.set_speed(8.0)
	var met := false
	for i in 30:
		await step(1)
		if screen._approach_foe == band:
			met = true
			break
	w.clock.set_speed(1.0)
	_want = null
	if not met:
		fail("at 8x the march stepped over a band standing on the road")
	else:
		RoadScreen.wave_off(screen)
	RoutePins.drop(w, band)

# --- O6: marching into a settlement opens the market, Leave closes it --------
func _settlement_visit(p) -> void:
	var w = screen.world
	var s = w.settlements[0]
	if not screen._visit.is_empty():
		screen._close_visit()
	var got: String = await RoadScreen.go(self, screen, s.position)
	if got != "visit" or screen._visit.get("settlement") != s:
		fail("marching into %s did not open the market (%s)" % [s.sname, got])
		return
	if not w.clock.is_paused():
		fail("the visit did not pause the world clock")
	if screen._visit_panel == null or screen._visit["stock"].is_empty():
		fail("the market panel came up with nothing on it")
		return
	screen.party.gold = 100000
	var id: String = String(screen._visit["stock"][0]["item_id"])
	var price: int = screen._visit["stock"][0]["price"]
	var gold0: int = screen.party.gold
	screen._buy(id)
	if screen.party.gold != gold0 - price or screen.party.stash_count(id) < 1:
		fail("buying from the market panel did not move gold/stash")
	var opinion0: float = s.pending_opinion_delta
	screen._steal()
	if s.pending_opinion_delta >= opinion0:
		fail("stealing did not queue an opinion delta for O7")
	var opinion1: float = s.pending_opinion_delta
	var purse: int = screen.party.gold
	screen._steal()
	if screen.party.gold != purse or s.pending_opinion_delta != opinion1:
		fail("a second Steal in the same visit still paid out or moved opinion")
	var clock0: float = w.clock.elapsed
	var ch = screen.party.party_characters()[0]
	ch.hp_current = 1
	screen._rest()
	if w.clock.elapsed <= clock0:
		fail("resting did not spend any world-time")
	if ch.hp_current == 1:
		fail("the long rest did not heal the party")
	var Quest = load("res://core/quest.gd")
	var offer: Dictionary = screen.Visit.quest_offer(s, screen.party)
	if offer.is_empty():
		fail("a neutral settlement offered no work at all")
	else:
		screen._take_quest(offer)
		var taken: Dictionary = Quest.get_quest(screen.party, offer["id"])
		if taken.is_empty() or taken["state"] != "active":
			fail("taking the offered job did not put it in the log")
		else:
			taken["progress"] = int(taken["required"])
			taken["state"] = "complete"
			if taken["kind"] in ["collect_item", "supply_item"]:
				screen.party.stash_add(String(taken["target_item_id"]), int(taken["required"]))
			var gold0b: int = screen.party.gold
			screen._turn_in(taken)
			if taken["state"] != "turned_in" or screen.party.gold <= gold0b:
				fail("turning the job in did not pay")
	screen._toggle_pause()
	screen._cycle_speed()
	if not w.clock.is_paused() or w.clock.speed != 1.0:
		fail("the pause/speed buttons still fired during a settlement visit")
	screen._close_visit()
	if not screen._visit.is_empty() or screen._visit_panel != null:
		fail("Leave did not close the market")
	if w.clock.is_paused():
		fail("Leave did not resume the world clock")
	screen._check_visit()
	if not screen._visit.is_empty():
		fail("the market reopened on the spot after Leave")
	# ...and it opens again once the company has walked out and come back.
	var other = null
	for t in w.settlements:
		if t != s and not WorldAI.is_monster(t.faction) and (other == null
				or t.position.distance_to(s.position) < other.position.distance_to(s.position)):
			other = t
	got = await RoadScreen.go(self, screen, other.position)
	if got != "visit":
		fail("the walk out to %s did not arrive (%s)" % [other.sname, got])
	if not screen._visit.is_empty():
		screen._close_visit()
	got = await RoadScreen.go(self, screen, s.position)
	if got != "visit" or screen._visit.get("settlement") != s:
		fail("coming back to %s did not open the market again (%s)" % [s.sname, got])
	elif not screen._visit.is_empty():
		screen._close_visit()

# --- O7: the opinion bands at a gate; the guards out, and a monster's gate ------
func _hostile_settlement(p) -> void:
	var FactionOpinion = load("res://core/faction_opinion.gd")
	var w = screen.world
	var s = w.settlements[0]   # the company stands at its gate (_settlement_visit)
	if p.position.distance_to(s.position) > screen.VISIT_RADIUS:
		fail("the company is not at %s's gate" % s.sname)
	FactionOpinion.set_opinion(s.faction, FactionOpinion.HOSTILE - 1.0)
	screen._left = null
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a merely hostile settlement refused to open its gate")
	elif screen._visit.get("refused", false):
		fail("a merely hostile settlement already refused to trade")
	else:
		screen._close_visit()
	FactionOpinion.set_opinion(s.faction, FactionOpinion.REFUSE_TRADE - 1.0)
	screen._left = null
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a trade-refusing settlement fought instead of refusing")
	elif not screen._visit.get("refused", false):
		fail("REFUSE_TRADE is still unreachable: the market traded normally")
	else:
		screen._close_visit()
	FactionOpinion.set_opinion(s.faction, 0.0)

	# A monster faction's town never opens a market: marched into, its gate is a fight.
	var monster_town = null
	for st in w.settlements:
		if WorldAI.is_monster(st.faction):
			monster_town = st
			break
	if monster_town == null:
		fail("the demo map has no monster-faction settlement to test")
	else:
		var got: String = await RoadScreen.go(self, screen, monster_town.position)
		if got == "visit":
			fail("a monster-faction settlement ran a friendly market")
			screen._close_visit()
		elif screen._combat == null:
			fail("marching into a monster-faction settlement did nothing at all (%s)" % got)
		else:
			screen._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5}
			await step(4)

	# Past GUARDS_ATTACK the town's guards come out for the company marching up.
	FactionOpinion.set_opinion(s.faction, FactionOpinion.GUARDS_ATTACK - 1.0)
	var got2: String = await RoadScreen.go(self, screen, s.position)
	if got2 == "visit":
		fail("a hostile settlement still opened its market")
		screen._close_visit()
	if screen._combat == null:
		fail("marching up to a hostile settlement did not trigger a fight (%s)" % got2)
		FactionOpinion.reset()
		return
	if not w.clock.is_paused():
		fail("the guard fight did not pause the world clock")
	var n: int = w.parties.size()
	screen._combat.result = {"outcome": "Victory", "xp": 10, "gold": 5}
	await step(4)
	if screen._combat != null:
		fail("the guard fight scene was never torn down")
	if w.parties.size() != n:
		fail("beating the garrison changed who is on the map")
	if FactionOpinion.get_opinion(s.faction) >= FactionOpinion.GUARDS_ATTACK - 1.0:
		fail("killing their garrison did not lower the faction further")
	FactionOpinion.set_opinion(s.faction, 0.0)
	screen._left = null
	w.clock.resume()
	screen._check_visit()
	if screen._visit.is_empty():
		fail("a settlement at neutral opinion did not open its market")
	else:
		screen._close_visit()
	FactionOpinion.reset()

# --- party/profile/inventory + quest log HUD buttons -------------------
func _party_and_quests() -> void:
	screen._halted_on_arrival = false
	screen.world.clock.resume()
	screen._open_party()
	if screen._party_overlay == null:
		fail("Party did not open an overlay")
	elif not screen.world.clock.is_paused():
		fail("opening Party did not pause the clock")
	screen._close_party()
	if screen._party_overlay != null:
		fail("closing Party left the overlay up")
	if screen.world.clock.is_paused():
		fail("closing Party did not resume the clock")
	screen._toggle_quests()
	if screen._quest_panel == null:
		fail("Quests did not open a panel")
	elif not screen.world.clock.is_paused():
		fail("opening Quests did not pause the clock")
	screen._toggle_quests()
	if screen._quest_panel != null:
		fail("toggling Quests again did not close it")
	if screen.world.clock.is_paused():
		fail("closing Quests did not resume the clock")

# --- the way out, and what persists a run: the roads too ----------------------
func _exit_to_title() -> void:
	var CharacterSave = load("res://core/character_save.gd")
	var FactionOpinion = load("res://core/faction_opinion.gd")
	var WorldSave = load("res://core/world_save.gd")
	if not WorldSave.has_save():
		fail("nothing during play wrote a world autosave")
	WorldSave.clear()
	FactionOpinion.set_opinion("soldier", -20.0)
	var p = screen.world.player()
	var where: Vector2 = p.position
	var elapsed: float = screen.world.clock.elapsed
	screen.party.add_gold(77)
	var purse: int = screen.party.gold
	screen._leave_world()
	if not FactionOpinion.all().is_empty():
		fail("leaving the world did not clear per-run faction opinion")
	for ch in screen.party.roster:
		if not FileAccess.file_exists(CharacterSave.path_for(ch.id)):
			fail("%s was not saved to the barracks on the way out" % ch.id)
	if not WorldSave.has_save():
		fail("leaving the world wrote no world autosave")
		return
	var saved = WorldSave.load_latest()
	if saved == null:
		fail("the world autosave did not load back")
		return
	if not RouteTravel.on(saved["world"]):
		fail("the saved world is no longer a route world")
	var loaded_p = saved["world"].player()
	if loaded_p == null or not loaded_p.position.is_equal_approx(where):
		fail("the saved world lost the player's position")
	if not is_equal_approx(saved["world"].clock.elapsed, elapsed):
		fail("the saved world lost the clock")
	if saved["party"].gold != purse:
		fail("the saved world lost the party's purse")
	if FactionOpinion.get_opinion("soldier") != -20.0:
		fail("loading the world did not re-apply faction opinion")
	FactionOpinion.reset()
	WorldSave.clear()

func _done() -> void:
	print("drive_world_routes: %s" % ["OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)
