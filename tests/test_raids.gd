# Raids (core/raids.gd): a lair left alone sends a band at the nearest town,
# the band marches, stands siege, lands the raid and walks home; clearing the
# lair lifts it. Pure, no scene.
#   godot --headless --path . -s tests/test_raids.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const Ach = preload("res://core/achievements.gd")
const Ladder = preload("res://core/ladder.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Riverhold at the origin (the anchor), a lair 300 out: heartland ground on a
# map whose extent is Regions.MIN_EXTENT (700). A player far away.
func _world() -> World:
	var w := World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_party(World.RoamingParty.new("player", Vector2(0, -600), "human", true))
	w.add_lair(World.Lair.new("warren", Vector2(300, 0), "goblinoid", "the Ash Warren"))
	return w

# One frame of the world without the screen: steer, walk, then the raids poll.
# The screen walks before it steers (world.tick is first in _process); this
# steers before it walks. What both keep is that the steer precedes Raids.tick,
# so the poll reads a band whose destination is this frame's.
func _frame(w: World, minutes := 1.0) -> Array:
	WorldAI.update(w)
	w.tick(minutes)
	return Raids.tick(w, w.clock.elapsed)

func _run(w: World, minutes: int) -> Array:
	var lines: Array = []
	for i in minutes:
		lines.append_array(_frame(w))
	return lines

func _init() -> void:
	# Achievements' save path is fixed when the script loads, before _init can
	# point it anywhere — so the deed counters below start from a fresh state
	# in memory instead (the shape tests/test_achievements.gd uses).
	Ach._current = Ach.new()
	FactionOpinion.reset()
	Ladder.reset()
	test_gates()
	test_march_siege_land_home()
	test_turned()
	test_truce()
	test_lift()
	test_spread()
	test_settle()
	print("test_raids: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_gates() -> void:
	var w := _world()
	var l = w.lairs[0]
	var due: float = Raids.due_at(l)
	check(due >= Raids.RAID_AFTER and due < Raids.RAID_AFTER + Raids.RAID_JITTER,
		"the first raid is due RAID_AFTER plus under a day of jitter (%s)" % due)
	check(Raids.due_at(l) == due, "...and the same time every time it is asked")
	check(Raids.is_settled(w, l), "300 from the anchor on a 700 map is settled country")
	check(Raids.target_for(w, l) == w.settlements[0], "the town is its target")
	w.clock.elapsed = due - 1.0
	check(Raids.tick(w, w.clock.elapsed).is_empty() and l.raid_band == "", "a minute early: nothing")
	w.clock.elapsed = due
	var lines: Array = Raids.tick(w, w.clock.elapsed)
	check(lines.size() == 1 and "Raiders are out from the Ash Warren, making for Riverhold." in lines[0],
		"on the minute: the band sets out, and it is said (%s)" % str(lines))
	var b = Raids.band_of(w, l)
	check(b != null and b.id == "warren-raiders" and b.faction == "goblinoid" and l.raid_band == b.id,
		"the band is on the map and the lair names it")
	check(b.troops.size() == 2 and int(b.troops[0]["level"]) == 1, "two troops at the region's floor level")
	check(b.ai["behavior"] == "raid" and b.ai["target"] == "riverhold" and b.ai["home"] == "warren", "...with the raid behaviour")
	check(Vector2(b.ai["to"]).distance_to(Vector2.ZERO) == Raids.SIEGE_DIST
		and Vector2(b.ai["to"]).x > 0.0, "the siege point is SIEGE_DIST out on the lair's side")
	check(l.raid_at == due, "the clock counts from the set-out now")
	check(Raids.tick(w, w.clock.elapsed).is_empty(), "a lair with a band out does not send another")

	# the three gates that stop a raid
	var w2 := _world()
	w2.lairs[0].looted = true
	w2.clock.elapsed = 99999.0
	check(Raids.tick(w2, 99999.0).is_empty(), "a looted lair never raids")
	var w3 := _world()
	w3.lairs[0].entered_at = 10.0
	check(Raids.tick(w3, 99999.0).is_empty(), "a disturbed lair never raids (D1's window has it)")
	var w4 := _world()
	w4.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))   # extent 2000
	var deep = w4.add_lair(World.Lair.new("deep", Vector2(1900, 0), "undead"))
	check(not Raids.is_settled(w4, deep), "1900 of 2000 is the deeps")
	check(Raids.tick(w4, 99999.0).size() == 1 and deep.raid_band == "", "the deeps lair sits it out; the warren goes")
	var w5 := World.new()
	w5.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w5.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))
	var lonely = w5.add_lair(World.Lair.new("lonely", Vector2(900, 0), "goblinoid"))
	check(Raids.is_settled(w5, lonely) and Raids.target_for(w5, lonely) == null,
		"heartland ground, but no town inside RAID_REACH: no target")
	check(Raids.tick(w5, 99999.0).is_empty(), "...so it never raids")
	var w6 := _world()
	w6.settlements[0].faction = "orc"
	check(Raids.target_for(w6, w6.lairs[0]) == null, "a monster settlement is not a target")

	# One town, one raider. A second lair in reach used to land on a town the
	# first already held and overwrite `raided_by`.
	var w7 := _world()
	var second = w7.add_lair(World.Lair.new("den", Vector2(-300, 0), "gnoll", "the Gnoll Den"))
	Raids.set_out(w7, w7.lairs[0], w7.settlements[0], 0.0)
	check(Raids.target_for(w7, second) == null, "a town another lair is marching on is not a target")
	check(Raids.target_for(w7, w7.lairs[0]) == w7.settlements[0], "...though it still is for the lair marching on it")
	var village = w7.add_settlement(World.Settlement.new("millbrook", Vector2(-400, 100), "human", "town"))
	check(Raids.target_for(w7, second) == village, "the second lair makes for the next town in reach instead")
	w7.parties.erase(Raids.band_of(w7, w7.lairs[0]))
	w7.lairs[0].raid_band = ""
	w7.settlements[0].raided_by = "warren"
	check(Raids.target_for(w7, second) == village, "a town still raided by another lair is not a target either")

func test_march_siege_land_home() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	w.clock.elapsed = Raids.due_at(l)
	Raids.tick(w, w.clock.elapsed)
	var b = Raids.band_of(w, l)
	# 200 units at 40/minute: five minutes to the gate
	var lines: Array = _run(w, 4)
	check(b.ai["phase"] == "march" and lines.is_empty(), "four minutes in, still marching")
	lines = _run(w, 2)
	check(b.ai["phase"] == "siege", "at the siege point the phase turns")
	check(lines.size() == 1 and "Raiders from the Ash Warren are camped outside Riverhold." in lines[0],
		"...and it is said (%s)" % str(lines))
	var until: float = float(b.ai["until"])
	check(absf(until - (w.clock.elapsed + Raids.SIEGE)) < 1.5, "the siege runs SIEGE from arrival")
	check(Raids.settlement_tag(w, s, w.clock.elapsed) == " — raiders at the gate, 8 h", "the label counts the hours (%s)" % Raids.settlement_tag(w, s, w.clock.elapsed))
	check(Raids.lair_tag(l) == " — raiding", "the lair's label says its band is out")
	check(s.raided_by == "" and l.raids == 0, "nothing has landed yet")
	check(Raids.turnable(b), "a band at the gate can still be turned")
	# stand the siege out
	w.clock.elapsed = until - 1.0
	lines = _frame(w, 0.5)
	check(s.raided_by == "" and lines.is_empty(), "half a minute short: not yet")
	lines = _frame(w, 1.0)
	check(s.raided_by == "warren" and s.raided_at == w.clock.elapsed and s.battle_at == w.clock.elapsed,
		"on the hour the raid lands: the town names the lair, and the market feels it")
	check(l.raids == 1, "the lair counts a landing")
	check(lines.size() == 1 and "Riverhold is raided" in lines[0] and "the Ash Warren wants it answered" in lines[0],
		"...and it is said (%s)" % str(lines))
	check(b.ai["phase"] == "home" and Vector2(b.ai["to"]) == l.position, "then it heads home")
	check(not Raids.turnable(b), "a band on its way home is not a raid to turn")
	check(Raids.settlement_tag(w, s, w.clock.elapsed) == " — raided", "the label now says raided")
	lines = _run(w, 6)
	check(Raids.band_of(w, l) == null and l.raid_band == "" and not w.parties.has(b), "home, and gone inside")
	check(Raids.lair_tag(l) == "", "...and the lair's label is quiet")
	check(Raids.due_at(l) >= l.raid_at + Raids.RAID_EVERY, "the next raid is RAID_EVERY out")
	check(s.raided_by == "warren", "the raid stands on the town after the band is gone")
	# a second lair landing on the same town overwrites, never stacks
	var l2 = w.add_lair(World.Lair.new("den", Vector2(-300, 0), "bandit"))
	Raids.land(w, l2, s, w.clock.elapsed + 5.0)
	check(s.raided_by == "den" and s.raided_at == w.clock.elapsed + 5.0 and l2.raids == 1,
		"one raid at a time: the later lair takes the town over")

func test_turned() -> void:
	var w := _world()
	var l = w.lairs[0]
	w.clock.elapsed = Raids.due_at(l)
	Raids.tick(w, w.clock.elapsed)
	var b = Raids.band_of(w, l)
	_run(w, 2)
	w.parties.erase(b)                       # the party, or a patrol, beat it on the road
	var now: float = w.clock.elapsed + 10.0
	w.clock.elapsed = now
	var lines: Array = Raids.tick(w, now)
	check(l.raid_band == "" and l.raid_at == now and l.raids == 0 and w.settlements[0].raided_by == "",
		"a band gone before it landed: the clock resets, nothing landed, no line (%s)" % str(lines))
	check(lines.is_empty(), "the lair says nothing about a band it has lost")
	check(Raids.due_at(l) - now >= Raids.RAID_EVERY and Raids.due_at(l) - now < Raids.RAID_EVERY + Raids.RAID_JITTER,
		"the next try is RAID_EVERY plus the lair's own jitter (%s)" % (Raids.due_at(l) - now))

# A band met and left without blood walks its break-off leg and then carries
# on to the gate. Landing exactly on the break-off point must not read as
# arriving at the siege point: the phase stays march through the truce and
# turns only at the gate. (_break_off_step erases the leg the frame after the
# band reaches it, so the band turns for the gate at once, truce or no.)
func test_truce() -> void:
	var w := _world()
	var l = w.lairs[0]
	w.clock.elapsed = Raids.due_at(l)
	Raids.tick(w, w.clock.elapsed)
	var b = Raids.band_of(w, l)
	_frame(w)
	WorldAI.truce(b, w.player(), w.clock.elapsed)
	var away: Vector2 = b.ai["break_off"]
	check(away.distance_to(b.position) == WorldAI.BREAK_OFF_DIST, "the break-off point is BREAK_OFF_DIST off")
	var marched := true
	var reached := false
	for i in 60:
		_frame(w)
		marched = marched and b.ai["phase"] == "march"
		if b.position.distance_to(away) <= WorldAI.WAYPOINT_SLACK:
			reached = true
			break
	check(reached, "the band walks its break-off leg")
	check(marched, "standing on the break-off point is not arriving at the gate: still march")
	check(WorldAI.in_truce(b, w.clock.elapsed), "...and the truce is still running")
	for i in 600:
		if b.ai["phase"] == "siege":
			break
		_frame(w)
	check(b.ai["phase"] == "siege" and b.position.distance_to(Vector2(b.ai["to"])) <= 1.0,
		"then it reaches the gate and the phase turns there (%s at %s)" % [b.ai["phase"], b.position])

func test_lift() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	FactionOpinion.reset()
	Raids.land(w, l, s, 100.0)
	check(s.raided_by == "warren", "raided")
	var before: int = Ach.count("raids_lifted")
	var op: float = FactionOpinion.get_opinion("human")
	var lifted_before: int = Ladder.deeds("human")
	WorldLairs.mark_cleared(l, 200.0)
	var lines: Array = Raids.tick(w, 200.0)
	check(s.raided_by == "" and s.raided_at == -1.0, "clearing the lair lifts the raid")
	check(lines.size() == 1 and "Riverhold breathes again — the Ash Warren is done raiding." in lines[0],
		"...and it is said (%s)" % str(lines))
	check(FactionOpinion.get_opinion("human") == op + Raids.LIFTED_FOR, "the town's faction thanks you")
	check(Ach.count("raids_lifted") == before + 1, "the deed is counted")
	check(Ladder.deeds("human") == lifted_before + 2, "lifting a raid is two deeds")
	check(Raids.tick(w, 201.0).is_empty(), "lifted once")
	# a band out for a lair that gets cleared under it has nowhere to go
	var w2 := _world()
	var l2 = w2.lairs[0]
	w2.clock.elapsed = Raids.due_at(l2)
	Raids.tick(w2, w2.clock.elapsed)
	var b2 = Raids.band_of(w2, l2)
	WorldLairs.mark_cleared(l2, w2.clock.elapsed)
	Raids.tick(w2, w2.clock.elapsed)
	check(not w2.parties.has(b2) and l2.raid_band == "", "its band is gone from the map")
	# a lair gone from the map (settled) lifts too
	var w3 := _world()
	Raids.land(w3, w3.lairs[0], w3.settlements[0], 100.0)
	w3.lairs.clear()
	Raids.tick(w3, 200.0)
	check(w3.settlements[0].raided_by == "", "a lair no longer on the map lifts its raid")

func test_spread() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	Raids.land(w, l, s, 100.0)
	check(w.lairs.size() == 1, "the first landing seeds nothing")
	var lines: Array = Raids.land(w, l, s, 200.0)
	check(w.lairs.size() == 2, "the second landing seeds a child")
	check(lines.size() == 2 and "Something has dug in near the Ash Warren." in lines[1], "...and says so (%s)" % str(lines))
	var c = w.lairs[1]
	check(c.id == "warren-2" and c.sname == "the Ash Warren's outpost" and c.faction == "goblinoid",
		"named after its parent, same faction (%s / %s)" % [c.id, c.sname])
	check(c.spawned_from == "warren" and c.raid_at == 200.0 and c.raids == 0 and not c.discovered and not c.looted,
		"a child: parent named, clock started at the landing, hidden, live")
	var d: float = c.position.distance_to(l.position)
	check(d >= Raids.SPREAD_MIN and d <= Raids.SPREAD_MAX, "placed SPREAD_MIN..SPREAD_MAX from the parent (%.0f)" % d)
	check(c.position.distance_to(s.position) >= Raids.SPREAD_TOWN_GAP, "...and clear of the town")
	check(not w.is_water(c.position), "...on dry ground")
	var again = Raids.spread(w, l, 300.0)
	check(again == null and w.lairs.size() == 2, "a root spreads once, even asked again")
	Raids.land(w, l, s, 400.0)
	check(w.lairs.size() == 2, "the third landing seeds nothing")
	# a child never spreads
	Raids.land(w, c, s, 500.0)
	Raids.land(w, c, s, 600.0)
	check(w.lairs.size() == 2 and c.raids == 2, "a child's second landing seeds nothing")
	# a child that was settled is a child that was dug: no second one on its ground
	w.lairs.erase(c)
	w.add_settlement(World.Settlement.new("way-warren-2", c.position, "human", "camp", "Fairstead"))
	l.raids = 0
	Raids.land(w, l, s, 700.0)
	Raids.land(w, l, s, 800.0)
	check(w.lairs.size() == 1 and l.raids == 2, "a settled child stands in for the dug one")
	w.settlements.pop_back()
	# the possessive: a parent whose name ends in s takes a bare apostrophe
	var w4 := _world()
	w4.lairs[0].sname = "the Sunken Ruins"
	Raids.land(w4, w4.lairs[0], w4.settlements[0], 100.0)
	Raids.land(w4, w4.lairs[0], w4.settlements[0], 200.0)
	check(w4.lairs.size() == 2 and w4.lairs[1].sname == "the Sunken Ruins' outpost", "the Sunken Ruins' outpost (%s)" % w4.lairs[1].sname)
	# determinism: the same parent puts its child in the same place
	var w2 := _world()
	Raids.land(w2, w2.lairs[0], w2.settlements[0], 100.0)
	Raids.land(w2, w2.lairs[0], w2.settlements[0], 200.0)
	check(w2.lairs[1].position == c.position, "seeded off the parent's id")
	# no room: a town on every side of the parent
	var w3 := _world()
	for i in 12:
		var a := deg_to_rad(float(i) * 30.0)
		w3.add_settlement(World.Settlement.new("ring-%d" % i, w3.lairs[0].position + Vector2(cos(a), sin(a)) * 220.0, "human", "camp"))
	Raids.land(w3, w3.lairs[0], w3.settlements[0], 100.0)
	var lines3: Array = Raids.land(w3, w3.lairs[0], w3.settlements[0], 200.0)
	check(w3.lairs.size() == 1 and lines3.size() == 1, "nowhere to dig in: no child, no line")

func test_settle() -> void:
	var Party = load("res://core/party.gd")
	var w := _world()
	var l = w.lairs[0]
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	p.gold = 500
	check(Raids.settle_cost(w, l) == 0, "a live lair cannot be settled")
	WorldLairs.mark_cleared(l, 1000.0)
	check(Raids.settle_cost(w, l) == 120, "cleared, in the heartland: 120")
	l.cleared_at = -1.0                                   # spent before the respawn rule: no window
	check(Raids.settle_cost(w, l) == 0, "no respawn window, no settling")
	l.cleared_at = 1000.0
	var w2 := _world()
	w2.add_settlement(World.Settlement.new("far", Vector2(2000, 0), "elf", "town"))
	var m = w2.add_lair(World.Lair.new("m", Vector2(1100, 0), "orc"))   # 1100/2000 = marches
	WorldLairs.mark_cleared(m, 1000.0)
	check(Raids.settle_cost(w2, m) == 240, "the marches cost 240")
	var deep = w2.add_lair(World.Lair.new("d", Vector2(1900, 0), "undead"))
	WorldLairs.mark_cleared(deep, 1000.0)
	check(Raids.settle_cost(w2, deep) == 0, "the deeps cannot be settled")
	var w3 := _world()
	w3.settlements[0].faction = "orc"
	WorldLairs.mark_cleared(w3.lairs[0], 1000.0)
	check(Raids.settle_cost(w3, w3.lairs[0]) == 0, "nobody civilized to send settlers: no settling")
	# the purchase
	check(Raids.settlers_from(w, l.position) == w.settlements[0], "settlers come from the nearest civilized town")
	var name := Raids.waystation_name(w, l)
	check(name in Raids.WAYSTATION_NAMES, "named off the list (%s)" % name)
	w.add_settlement(World.Settlement.new("taken", Vector2(5000, 5000), "human", "camp", name))
	check(Raids.waystation_name(w, l) != name and Raids.waystation_name(w, l) in Raids.WAYSTATION_NAMES,
		"a name already on the map is skipped")
	w.settlements.pop_back()
	p.gold = 100
	check(Raids.settle(w, l, p, 1500.0) == null and w.lairs.has(l), "short of gold: nothing happens")
	p.gold = 500
	FactionOpinion.reset()
	var xp_before: int = p.party_characters()[0].xp
	var ways_before: int = Ach.count("waystations")
	var settle_before: int = Ladder.deeds("human")
	var s = Raids.settle(w, l, p, 1500.0)
	check(s != null and not w.lairs.has(l), "settled: the lair is gone for good")
	check(w.settlements.has(s) and s.id == "way-warren" and s.kind == "camp" and s.faction == "human"
		and s.position == Vector2(300, 0) and s.sname == name, "a camp of the settlers' faction stands where it was")
	check(s.last_visited == 1500.0, "with a fresh market")
	check(p.gold == 380, "120 paid")
	check(p.party_characters()[0].xp == xp_before + Raids.SETTLE_XP / p.party_characters().size(),
		"SETTLE_XP x (ring 0 + 1), split (%d -> %d)" % [xp_before, p.party_characters()[0].xp])
	check(FactionOpinion.get_opinion("human") == Raids.LIFTED_FOR, "the settlers' faction thanks you")
	check(Ach.count("waystations") == ways_before + 1, "the deed is collected")
	check(Ladder.deeds("human") == settle_before + 3, "settling a lair is three deeds")
	# a lair settled while its band is still out takes the band with it
	var w4 := _world()
	var l4 = w4.lairs[0]
	w4.clock.elapsed = Raids.due_at(l4)
	Raids.tick(w4, w4.clock.elapsed)
	var b4 = Raids.band_of(w4, l4)
	check(b4 != null, "a band is out")
	WorldLairs.mark_cleared(l4, w4.clock.elapsed)
	p.gold = 500
	check(Raids.settle(w4, l4, p, w4.clock.elapsed) != null, "settled with the band out")
	check(not w4.parties.has(b4), "...and the band is gone from the map with it")
	check(Raids.settle(w, l, p, 1600.0) == null, "a lair no longer on the map cannot be settled twice")
