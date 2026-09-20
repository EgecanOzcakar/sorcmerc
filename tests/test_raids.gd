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

# One frame of the world without the screen: steer, walk, then the raids poll —
# the same order scenes/world/world.gd's _process keeps.
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
	# A scratch save dir, so the deed counters below never touch the real
	# achievements file (the same isolation tests/test_landmarks.gd uses).
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/raids-%d-%d" % [OS.get_process_id(), randi()])
	FactionOpinion.reset()
	test_gates()
	test_march_siege_land_home()
	test_turned()
	test_lift()
	test_spread()
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

func test_lift() -> void:
	var w := _world()
	var l = w.lairs[0]
	var s = w.settlements[0]
	FactionOpinion.reset()
	Raids.land(w, l, s, 100.0)
	check(s.raided_by == "warren", "raided")
	var before: int = Ach.count("raids_lifted")
	var op: float = FactionOpinion.get_opinion("human")
	WorldLairs.mark_cleared(l, 200.0)
	var lines: Array = Raids.tick(w, 200.0)
	check(s.raided_by == "" and s.raided_at == -1.0, "clearing the lair lifts the raid")
	check(lines.size() == 1 and "Riverhold breathes again — the Ash Warren is done raiding." in lines[0],
		"...and it is said (%s)" % str(lines))
	check(FactionOpinion.get_opinion("human") == op + Raids.LIFTED_FOR, "the town's faction thanks you")
	check(Ach.count("raids_lifted") == before + 1, "the deed is counted")
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
