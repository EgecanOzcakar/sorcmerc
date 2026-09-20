# Landmarks — places on the map that are not a fight.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#   godot --headless --path . -s tests/test_landmarks.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const Landmarks = preload("res://core/landmarks.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/landmarks-%d-%d" % [OS.get_process_id(), randi()])
	test_model()
	test_placement()
	print("test_landmarks: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ------------------------------------------------------------

func _world() -> World:
	var w = World.new()
	w.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w.add_settlement(World.Settlement.new("greenmarch", Vector2(420, -180), "elf", "town"))
	w.add_party(World.RoamingParty.new("player", Vector2(80, 120), "human", true))
	w.add_lair(World.Lair.new("goblin-warren", Vector2(330, 130), "goblinoid"))
	w.add_lair(World.Lair.new("giant-hold", Vector2(-520, -260), "giant"))
	return w

func _party() -> Party:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	return p

# --- Task 1: the model and the save -----------------------------------------

func test_model() -> void:
	check(Landmarks.KINDS == ["ruins", "shrine", "stones", "hut", "wreck", "tower"], "six kinds, in this order")
	check(Landmarks.is_hidden("hut") and Landmarks.is_hidden("tower") and not Landmarks.is_hidden("ruins"),
		"the hut and the tower are hidden; the rest are visible")
	for k in Landmarks.KINDS:
		check(Landmarks.NAMES.has(k) and Landmarks.NAMES[k].size() >= 3, "%s has names to draw from" % k)
	check(Landmarks.name_for("x-1", "shrine") == Landmarks.name_for("x-1", "shrine"), "a name is stable per id")
	var w := _world()
	var l = w.add_landmark(World.Landmark.new("chapel", "shrine", Vector2(200, 40)))
	check(w.landmarks.size() == 1 and w.landmark("chapel") == l and w.landmark("nope") == null, "added and found by id")
	check(l.sname != "" and not l.found and not l.spent, "named on creation, unfound, unspent")
	check(w.marked_until < 0.0, "nothing marked")
	# the save carries them, and an old save without the key loads with none
	var p := _party()
	p.blessed = true
	l.found = true
	l.spent = true
	var d: Dictionary = WorldSave.to_dict(w, p)
	check(d.has("landmarks") and d["landmarks"].size() == 1, "saved under \"landmarks\"")
	var back: Dictionary = WorldSave.from_dict(d)
	var w2 = back["world"]
	check(w2.landmarks.size() == 1 and w2.landmark("chapel").kind == "shrine" and w2.landmark("chapel").found
		and w2.landmark("chapel").spent and w2.landmark("chapel").sname == l.sname
		and w2.landmark("chapel").position == l.position, "round-trips every field")
	check(back["party"].blessed, "the blessing rides the road dict")
	d.erase("landmarks")
	check(WorldSave.from_dict(d)["world"].landmarks.is_empty(), "an old save loads with none")

# --- Task 2: placement ---------------------------------------------------

func test_placement() -> void:
	# count, gap, dry ground, round-robin kinds — on a hundred seeds
	var bad := 0
	for s in range(1, 101):
		var w := _world()
		w.add_water(Vector2(120, 120), 60.0)
		Landmarks.place(w, s)
		var want: int = ceili(Landmarks.LANDMARKS_PER_LAIR * w.lairs.size())
		if w.landmarks.size() != want:
			bad += 1
			continue
		var taken: Array = []
		for st in w.settlements: taken.append(st.position)
		for l in w.lairs: taken.append(l.position)
		for m in w.landmarks:
			if w.is_water(m.position):
				bad += 1
			for t in taken:
				if t.distance_to(m.position) < Landmarks.LANDMARK_GAP:
					bad += 1
			taken.append(m.position)
	check(bad == 0, "100 seeds: the right count, off the water, the gap kept (%d bad)" % bad)
	var w := _world()
	Landmarks.place(w, 7)
	var kinds: Array = w.landmarks.map(func(m): return m.kind)
	check(kinds.size() == 3 and kinds[0] != kinds[1] and kinds[1] != kinds[2], "kinds go round-robin")
	var w2 := _world()
	Landmarks.place(w2, 7)
	check(w2.landmarks.map(func(m): return [m.id, m.position]) == w.landmarks.map(func(m): return [m.id, m.position]),
		"the same seed places the same landmarks")
	check(w.landmarks.all(func(m): return m.id.begins_with("landmark-")), "ids are namespaced")
