# core/world_homes.gd — a lair for every people (the design audit §8.3).
#   godot --headless --path . -s tests/test_world_homes.gd
#
# What is pinned: on every map the game builds, each faction with a home in
# Regions.HOMES has a lair standing in its home country, on dry ground, that
# the player can walk to; each of those lairs opens as a site with a boss that
# is a real creature; the pass is deterministic and does not move the maps'
# existing lairs; an old save of a built map gets the lairs it lacks, once,
# and a pack's map never does; and every lair draws, model or not.
# The small map is built by the world screen and is checked in
# tests/test_world_regions.gd, which already instantiates it.
extends SceneTree

const World = preload("res://core/world.gd")
const Regions = preload("res://core/regions.gd")
const Scaler = preload("res://core/scaler.gd")
const Site = preload("res://core/site.gd")
const Party = preload("res://core/party.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Campaign = preload("res://core/campaign.gd")
const WorldHomes = preload("res://core/world_homes.gd")
const WorldPath = preload("res://core/world_path.gd")
const WorldSave = preload("res://core/world_save.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const LairKit = preload("res://scenes/world/lair_kit.gd")

const SEEDS := [1, 2, 3, 7, 42, 99, 1234, 31337]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

func _init() -> void:
	test_home_factions()
	test_every_map(LargeWorld.build(), "large")
	for s in SEEDS:
		test_every_map(ProceduralWorld.build(s), "seed %d" % s)
	test_deterministic()
	test_sites(LargeWorld.build(), "large")
	test_sites(ProceduralWorld.build(42), "seed 42")
	test_backfill()
	test_packs_left_alone()
	test_every_lair_draws()
	print("test_world_homes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# Fourteen of the fifteen: soldier lives nowhere on Regions.HOMES.
func test_home_factions() -> void:
	var homed: Array = Scaler.FACTIONS.filter(func(f): return WorldHomes.has_home(f))
	check(homed.size() == 14, "fourteen factions have a home (%d)" % homed.size())
	check(not WorldHomes.has_home("soldier"), "soldier has none, and gets no lair")
	for f in homed:
		check(WorldHomes.LAIRS.has(f), "%s has a named lair to be given" % f)


func test_every_map(w, name: String) -> void:
	check(WorldHomes.homeless(w).is_empty(), "%s: nobody is homeless (%s)" % [name, str(WorldHomes.homeless(w))])
	var start: Vector2 = w.player().position
	var ids := {}
	for f in Scaler.FACTIONS:
		if not WorldHomes.has_home(f):
			continue
		var home: String = Regions.home_band(f)
		var housed = null
		for l in w.lairs:
			if l.faction == f and Regions.within(w, l.position, home):
				housed = l
				break
		check(housed != null, "%s: a %s lair stands in %s" % [name, f, home])
		if housed == null:
			continue
		check(not w.is_water(housed.position), "%s: %s is on dry ground" % [name, housed.id])
		check(WorldPath.clear_line(w, start, housed.position) or not WorldPath.route(w, start, housed.position).is_empty(),
			"%s: %s can be walked to" % [name, housed.id])
	for l in w.lairs:
		check(not ids.has(l.id), "%s: lair id %s is unique" % [name, l.id])
		ids[l.id] = true
		for s in w.settlements:
			check(s.position.distance_to(l.position) >= WorldHomes.TOWN_GAP * 0.5,
				"%s: %s is out of %s's front yard" % [name, l.id, s.id])


func test_deterministic() -> void:
	for s in [5, 42]:
		var a = ProceduralWorld.build(s)
		var b = ProceduralWorld.build(s)
		var same: bool = a.lairs.size() == b.lairs.size()
		for i in mini(a.lairs.size(), b.lairs.size()):
			same = same and a.lairs[i].id == b.lairs[i].id and a.lairs[i].position == b.lairs[i].position
		check(same, "seed %d: the same seed is the same set of lairs" % s)
		# The five named lairs come first and from the builder's own list; the
		# pass only appends after them.
		for i in ProceduralWorld.LAIRS.size():
			check(a.lairs[i].id == String(ProceduralWorld.LAIRS[i][0]), "seed %d: %s is still the builder's" % [s, a.lairs[i].id])
	# Filling a map that has everyone is a no-op.
	var w = LargeWorld.build()
	var n: int = w.lairs.size()
	check(WorldHomes.fill(w, 99).is_empty() and w.lairs.size() == n, "a second fill adds nothing")
	# The extent does not move: every new lair is placed inside it.
	var bare = LargeWorld.build()
	var ext: float = Regions.extent(bare)
	for l in bare.lairs:
		check(Regions.anchor(bare).distance_to(l.position) <= ext + 0.01, "%s is inside the measured extent" % l.id)


# Every lair opens as a site whose last room is built round a creature that
# exists (a BOSS_POOL lead for a faction with a board, FACTION_BOSS otherwise),
# and the boss room's fight has that creature in it.
func test_sites(w, name: String) -> void:
	var party := _party()
	for l in w.lairs:
		var s = Site.for_lair(l, party, w)
		check(s.depth_total() >= Site.MIN_DEPTH, "%s: %s has rooms" % [name, l.id])
		s.depth = s.depth_total() - 1
		s.enter(0)
		var room: Dictionary = s.room
		check(bool(room.get("boss", false)) or room.has("win_rate"), "%s: %s ends in a boss room" % [name, l.id])
		check(String(room.get("title", "")) != "WHAT THE LAIR WAS BUILT AROUND",
			"%s: %s's boss has a name (%s)" % [name, l.id, room.get("title", "")])
		var lead: String = String(room.get("lead", ""))
		if lead != "":
			check(not Catalog.monster(lead).is_empty(), "%s: %s's boss, %s, is a real creature" % [name, l.id, lead])
		var spec: Dictionary = s.combat_spec()
		check(not spec.get("monsters", []).is_empty(), "%s: %s's boss room has a roster" % [name, l.id])
		if lead != "":
			check(spec.get("monsters", []).any(func(m): return String(m["id"]) == lead),
				"%s: ...with %s in it" % [name, lead])
	# The one the audit named: the cult's voice, the enemy that casts from real
	# slots, can now be met at the bottom of a lair on a shipped map.
	var cult = null
	for l in w.lairs:
		if l.faction == "cultist":
			cult = l
	check(cult != null, "%s: the cult has a lair" % name)
	if cult != null:
		var s = Site.for_lair(cult, party, w)
		s.depth = s.depth_total() - 1
		s.enter(0)
		check(bool(s.room.get("lead_caster", false)), "%s: ...and at the bottom of it is the voice that casts" % name)


# A save written before this pass: the large map with only its five old lairs.
func test_backfill() -> void:
	var w = LargeWorld.build()
	var d: Dictionary = WorldSave.to_dict(w)
	check(bool(d["origin"].get("homes", false)), "a save marks the pass done")
	var old: Dictionary = d.duplicate(true)
	old["origin"].erase("homes")
	var five := ["goblin-warren", "giant-hold", "sunken-ruins", "zombie-graveyard", "dragon-cave"]
	old["lairs"] = old["lairs"].filter(func(ld): return five.has(String(ld["id"])))
	check(old["lairs"].size() == 5, "the old save holds the five old lairs (%d)" % old["lairs"].size())
	old["elapsed"] = 14400.0      # day ten
	var back = WorldSave.from_dict(old)["world"]
	check(WorldHomes.homeless(back).is_empty(), "loading it moves every people in (%s)" % str(WorldHomes.homeless(back)))
	check(back.lairs.size() == w.lairs.size(), "...one lair each (%d, %d)" % [back.lairs.size(), w.lairs.size()])
	var late := true
	for l in back.lairs.slice(5):
		late = late and l.raid_at == back.clock.elapsed and not l.discovered
	check(late, "...undiscovered, and none of them owed a raid on the first frame")
	# Written back out, the marker is on, and a second load changes nothing.
	var again = WorldSave.from_dict(WorldSave.to_dict(back))["world"]
	check(again.lairs.size() == back.lairs.size(), "a second load adds nothing")
	# A save that already has the marker is left exactly as it is, even short.
	var marked: Dictionary = old.duplicate(true)
	marked["origin"]["homes"] = true
	check(WorldSave.from_dict(marked)["world"].lairs.size() == 5, "a marked save is never refilled")


func test_packs_left_alone() -> void:
	var w := World.new()
	w.origin = {"kind": "pack:example", "seed": 0}
	w.add_settlement(World.Settlement.new("town", Vector2.ZERO, "human", "town"))
	w.add_lair(World.Lair.new("far", Vector2(900, 0), "goblinoid"))
	check(WorldHomes.backfill(w).is_empty() and w.lairs.size() == 1, "a pack's map is its author's")


# Every lair on every map draws something: its own kit, or its faction's.
func test_every_lair_draws() -> void:
	var lairs: Array = LargeWorld.build().lairs.duplicate()
	lairs.append(World.Lair.new("the-crown-vault", Vector2.ZERO, "construct"))   # a pack's own id
	lairs.append(World.Lair.new("something-new", Vector2.ZERO, "no-such-faction"))
	for l in lairs:
		check(not LairKit.plan_for(l.id, l.faction).is_empty(), "%s (%s) has a diorama" % [l.id, l.faction])
	for f in LairKit.FACTION_KITS:
		check(LairKit.has(String(LairKit.FACTION_KITS[f]["shape"])), "%s's kit is built on a real shape" % f)
	check(not LairKit.plan_for("x", "orc").is_empty() and LairKit.plan_for("x", "orc") == LairKit.plan_for("x", "orc"),
		"a faction kit is deterministic in the lair id")
	var n = LairKit.build_for("quiet-chapel", "cultist")
	check(n != null and n.get_child_count() > 0, "a cult chapel builds as a node")
	n.free()
