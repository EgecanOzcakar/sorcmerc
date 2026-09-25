# A spent lair used to sit grey on the map for the rest of the run: cleared
# once, and that was the end of that landmark. Five lairs, five clears, and
# there was nothing left underground to do.
#
# Something moves back in now — one in-game day after the place was emptied,
# however it was emptied. What the party keeps is knowing WHERE it is; what
# starts over is everything about what is in it.
#
#   godot --headless --path . -s tests/test_lair_respawn.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const WorldSave = preload("res://core/world_save.gd")
const Party = preload("res://core/party.gd")
const Site = preload("res://core/site.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func a_world():
	var w = World.new()
	w.add_settlement(World.Settlement.new("oakford", Vector2(0, 0), "soldier", "town"))
	w.add_lair(World.Lair.new("goblin-warren", Vector2(300, 100), "goblinoid"))
	return w

# The design audit §5.4: a day near home, three on the Frontier, five in the
# Deeps, read off where the lair stands (core/regions.gd's bands). One map,
# one lair in each country, all cleared at the same minute.
func test_slower_past_the_marches() -> void:
	var Regions = load("res://core/regions.gd")
	var w = World.new()
	w.add_settlement(World.Settlement.new("home", Vector2.ZERO, "human", "city"))
	var at := {"heartland": 300.0, "marches": 600.0, "frontier": 800.0, "deeps": 1000.0}
	for band in at:
		w.add_lair(World.Lair.new(band, Vector2(float(at[band]), 0.0), "goblinoid"))
	for l in w.lairs:
		check(Regions.band_of(w, l.position) == l.id, "%s's lair stands in %s (%s)" % [l.id, l.id, Regions.band_of(w, l.position)])
		WorldLairs.mark_cleared(l, 0.0)
	check(WorldLairs.respawn_after(w, w.lairs[0]) == 1440.0 and WorldLairs.respawn_after(w, w.lairs[1]) == 1440.0,
		"a day in the Heartland and the Marches")
	check(WorldLairs.respawn_after(w, w.lairs[2]) == 4320.0, "three days on the Frontier")
	check(WorldLairs.respawn_after(w, w.lairs[3]) == 7200.0, "five in the Far Deeps")
	check(WorldLairs.respawn_after(null, w.lairs[3]) == WorldLairs.RESPAWN, "no map to read: the base day")
	var day1: Array = WorldLairs.respawn(w, 1440.0).map(func(l): return l.id)
	check(day1.size() == 2 and "heartland" in day1 and "marches" in day1, "after a day the near two are back (%s)" % [day1])
	check(WorldLairs.respawn(w, 4319.0).is_empty(), "the Frontier's is still empty a minute short of three days")
	check(WorldLairs.respawn(w, 4320.0).map(func(l): return l.id) == ["frontier"], "...and back at three")
	check(WorldLairs.respawn(w, 7199.0).is_empty() and w.lairs[3].looted, "the Deeps' is still empty on day five")
	check(WorldLairs.respawn(w, 7200.0).map(func(l): return l.id) == ["deeps"], "...and back at five")

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])

	# --- the clock starts when the place is emptied, not before -----------
	var w = a_world()
	var l = w.lairs[0]
	l.discovered = true
	check(l.cleared_at < 0.0, "a live lair has no respawn clock running")
	check(WorldLairs.respawn(w, 100000.0).is_empty(), "...and never comes back, because it never left")

	WorldLairs.mark_cleared(l, 500.0)
	check(l.looted, "clearing it spends it")
	check(l.cleared_at == 500.0, "...and stamps when")

	# --- a day, exactly -----------------------------------------------------
	check(WorldLairs.respawn(w, 500.0).is_empty(), "the same minute, still spent")
	check(WorldLairs.respawn(w, 500.0 + WorldLairs.RESPAWN - 1.0).is_empty(),
		"a minute short of the day, still spent")
	check(WorldLairs.RESPAWN == 1440.0, "the window is one in-game day")
	var back: Array = WorldLairs.respawn(w, 500.0 + WorldLairs.RESPAWN)
	check(back.size() == 1 and back[0] == l, "a day later it is reported back")
	check(not l.looted, "...and live again")
	check(WorldLairs.respawn_text(l).contains(l.sname), "with something to say about it")

	# What survives, and what starts over.
	check(l.discovered, "the party still knows where the hole is")
	check(l.depth_cleared == 0, "but not which rooms they fought through")
	check(l.entered_at < 0.0, "...and the new tenants have never met them")
	check(l.cleared_at < 0.0, "the respawn clock is wound down again")
	check(l.resolved_as == "", "and it is nobody else's story any more")
	check(WorldLairs.can_sneak(l), "an undisturbed lair can be talked past again")

	# Reported once, not every frame after.
	check(WorldLairs.respawn(w, 500.0 + WorldLairs.RESPAWN + 60.0).is_empty(),
		"a lair already back does not come back again")

	# --- every way of emptying one starts the same clock -------------------
	# The quiet way.
	var w2 = a_world()
	var l2 = w2.lairs[0]
	l2.discovered = true
	var stash: Dictionary = WorldLairs.loot(l2, 900.0)
	check(int(stash["gold"]) > 0, "the quiet way pays")
	check(l2.looted and l2.cleared_at == 900.0, "...and starts the clock")
	check(WorldLairs.respawn(w2, 900.0 + WorldLairs.RESPAWN).size() == 1,
		"a lair talked past comes back too")

	# Resolved without the party: the window ran out while they were away.
	var w3 = a_world()
	var l3 = w3.lairs[0]
	l3.discovered = true
	WorldLairs.mark_entered(l3, 0.0)
	var gone: Array = WorldLairs.expire(w3, WorldLairs.WINDOW + 1.0)
	check(gone.size() == 1, "an abandoned lair resolves without the party")
	check(l3.cleared_at >= 0.0, "...and that starts the clock as well")
	check(WorldLairs.respawn(w3, l3.cleared_at + WorldLairs.RESPAWN).size() == 1,
		"so it too refills eventually")

	# Fought to the bottom, through the site model.
	var party := Party.new()
	for ch in Party.demo_roster():
		party.add_member(ch)
	var w4 = a_world()
	var l4 = w4.lairs[0]
	l4.discovered = true
	w4.clock.elapsed = 2000.0
	var site = Site.for_lair(l4, party, w4)
	var guard := 0
	while not site.is_over() and guard < 40:
		guard += 1
		if site.state == "picking":
			site.enter(0)
		site.state = "visiting"
		site.leave()
	check(site.state == "cleared", "the delve reaches the bottom")
	check(l4.looted, "...which spends the lair")
	check(l4.cleared_at == 2000.0, "...and stamps the world clock it happened at (%s)" % l4.cleared_at)

	# --- and it survives a save --------------------------------------------
	var w5 = a_world()
	var l5 = w5.lairs[0]
	l5.discovered = true
	WorldLairs.mark_cleared(l5, 777.0)
	var p5 := Party.new()
	for ch in Party.demo_roster():
		p5.add_member(ch)
	var back5 = WorldSave.from_dict(WorldSave.to_dict(w5, p5, null))
	check(back5 != null, "the world round-trips through the save format")
	if back5 != null:
		var world5 = back5["world"] if back5 is Dictionary else back5
		var ll = world5.lairs[0]
		check(ll.looted, "a spent lair is still spent after a reload")
		check(ll.cleared_at == 777.0, "...with its respawn clock where it was (%s)" % ll.cleared_at)
		check(WorldLairs.respawn(world5, 777.0 + WorldLairs.RESPAWN).size() == 1,
			"so the day it is owed still comes")
		# An old save has no stamp at all, and must not repopulate every lair
		# the moment it is loaded.
		var raw: Dictionary = WorldSave.to_dict(w5, p5, null)
		for ld in raw["lairs"]:
			ld.erase("cleared_at")
		var old_save = WorldSave.from_dict(raw)
		var world_old = old_save["world"] if old_save is Dictionary else old_save
		check(world_old.lairs[0].cleared_at < 0.0, "a save from before the rule has no clock")
		check(WorldLairs.respawn(world_old, 1e9).is_empty(),
			"...and stays spent rather than refilling on load")

	# raids: something new moved in, with its own patience — the clock restarts
	var wq := World.new()
	var lq := wq.add_lair(World.Lair.new("q", Vector2.ZERO, "goblinoid"))
	lq.raids = 2
	lq.raid_at = 100.0
	WorldLairs.mark_cleared(lq, 1000.0)
	var came: Array = WorldLairs.respawn(wq, 1000.0 + WorldLairs.RESPAWN)
	check(came.size() == 1 and lq.raids == 0 and lq.raid_at == 1000.0 + WorldLairs.RESPAWN,
		"a respawned lair's raid clock restarts at the respawn (%s, %d)" % [lq.raid_at, lq.raids])

	test_slower_past_the_marches()

	print("test_lair_respawn: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
