# Landmarks — places on the map that are not a fight.
#   docs/superpowers/specs/2026-09-20-landmarks-design.md
#   godot --headless --path . -s tests/test_landmarks.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldSave = preload("res://core/world_save.gd")
const Landmarks = preload("res://core/landmarks.gd")
const Party = preload("res://core/party.gd")
const RNG = preload("res://core/rng.gd")
const Approach = preload("res://core/approach.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Travel = preload("res://core/travel.gd")
const Adapter = preload("res://core/adapter.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Rumors = preload("res://core/rumors.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/landmarks-%d-%d" % [OS.get_process_id(), randi()])
	test_model()
	test_placement()
	test_cards()
	test_resolve()
	test_discovery()
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

# --- Task 3: the cards and the doors ----------------------------------------

func _mark(w, kind: String, pos := Vector2(200, 40)):
	var m = w.add_landmark(World.Landmark.new("m-" + kind, kind, pos))
	m.found = true
	return m

func test_cards() -> void:
	var w := _world()
	var p := _party()
	p.gold = 500   # so a zero-skill choice (the offering) survives into rows below
	for k in Landmarks.KINDS:
		var card: Array = Landmarks.CARDS[k]
		check(card.size() == 2, "%s: two choices" % k)
		for c in card:
			for s in c["skills"]:
				check(Catalog.skills().has(s), "%s/%s rolls a real skill (%s)" % [k, c["id"], s])
			check(c.has("win") and c.has("lose") and c.has("label") and c.has("note"), "%s/%s has its words" % [k, c["id"]])
		var m = _mark(w, k)
		var rows: Array = Landmarks.options(m, p, w)
		check(rows.back()["id"] == Landmarks.LEAVE, "%s: Leave is last" % k)
		# priced by the card's own choices, matched by id, not by a "skills" key rows never carry
		for c2 in card:
			var matches: Array = rows.filter(func(r): return r["id"] == c2["id"])
			if matches.is_empty():
				continue
			var row: Dictionary = matches[0]
			if not c2["skills"].is_empty():
				check(row.has("cname") and row.has("needs") and row.has("dc") and row.has("bonus"), "%s/%s is priced with who rolls and what they need" % [k, c2["id"]])
			else:
				check(row.has("toll"), "%s/%s is priced with a toll" % [k, c2["id"]])
	# a choice nobody can roll is dropped; a paid choice the purse cannot cover is dropped
	var poor := Party.new()
	var shrine = _mark(w, "shrine", Vector2(300, 300))
	var rows: Array = Landmarks.options(shrine, poor, w)
	check(rows.size() == 1 and rows[0]["id"] == Landmarks.LEAVE, "an empty party can only leave")
	p.gold = 0
	rows = Landmarks.options(shrine, p, w)
	check(not rows.any(func(r): return r["id"] == "offering"), "no purse, no offering")
	p.gold = 500
	rows = Landmarks.options(shrine, p, w)
	check(rows.any(func(r): return r["id"] == "offering"), "...with one, it is offered")
	# DC climbs with the ring
	var far = _mark(w, "ruins", Vector2(4000, 4000))
	var near = _mark(w, "ruins", Vector2(60, 60))
	check(Landmarks.dc_for(Landmarks.CARDS["ruins"][0], w, far.position) > Landmarks.dc_for(Landmarks.CARDS["ruins"][0], w, near.position),
		"further out, the same check is harder")

func _roll(w, kind: String, id: String, p, seed: int) -> Dictionary:
	var m = _mark(w, kind, Vector2(200 + seed, 40))
	return Landmarks.resolve(m, id, p, w, RNG.new(seed))

# Find a seed where the named choice passes (or fails), so each door can be
# opened deliberately — the roll is a d20, so a few tries always find one.
# `w`/`p` are unused (always null from the callers below): a fresh world and
# party are built per attempt so the search never disturbs the caller's own.
# `at`, when given, is the landmark's position — the DC the search rolls
# against has to be the DC the real resolve() call will use, and that climbs
# with the ring (dc_for), so a search at the default near-origin spot would
# find a seed that passes there and still fails at a landmark placed further
# out (the tower tests park theirs at (900, 900) to also probe is_explored).
func _seed_where(w, kind: String, id: String, p, ok: bool, at = null) -> int:
	for s in range(1, 60):
		var w2 := _world()
		var p2 := _party()
		p2.gold = 500
		var r: Dictionary
		if at == null:
			r = _roll(w2, kind, id, p2, s)
		else:
			r = Landmarks.resolve(_mark(w2, kind, at), id, p2, w2, RNG.new(s))
		if bool(r.get("ok", false)) == ok:
			return s
	return -1

func test_resolve() -> void:
	# every win pays the deed; a spent landmark is spent; leave spends nothing
	for k in Landmarks.KINDS:
		for c in Landmarks.CARDS[k]:
			var s := _seed_where(null, k, String(c["id"]), null, true)
			check(s > 0, "%s/%s can be passed" % [k, c["id"]])
			var w := _world()
			var p := _party()
			p.gold = 500
			var xp0: int = p.party_characters()[0].xp
			var r := _roll(w, k, String(c["id"]), p, s)
			check(r["ok"] and r.has("cname") and r.has("nat") and r.has("dc") or c["skills"].is_empty(), "%s/%s names its roll" % [k, c["id"]])
			check(int(r.get("xp", 0)) > 0 and p.party_characters()[0].xp > xp0, "%s/%s: the deed pays" % [k, c["id"]])
			check(w.landmark("m-" + k).spent, "%s/%s: spent" % [k, c["id"]])
			check(Landmarks.options(w.landmark("m-" + k), p, w).is_empty(), "...and offers nothing more")
	var w := _world()
	var p := _party()
	var m = _mark(w, "wreck")
	check(Landmarks.resolve(m, Landmarks.LEAVE, p, w, RNG.new(1)).is_empty() and not m.spent, "leave spends nothing")

	# the doors, one by one
	w = _world(); p = _party(); p.gold = 100
	var r := _roll(w, "shrine", "kneel", p, _seed_where(null, "shrine", "kneel", null, true))
	check(p.blessed, "kneel: blessed")
	var cs: Array = p.to_combatants([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	check(cs[0].temp_hp == 2 * p.party_characters()[0].level() and not p.blessed, "the blessing is temp HP at the next fight, once")
	w = _world(); p = _party(); p.gold = 100
	var gold0: int = p.gold
	r = _roll(w, "shrine", "offering", p, 1)
	check(p.gold == gold0 - Landmarks.OFFERING_GOLD and p.blessed and not r.has("nat"), "offering: costs, blesses, no roll")
	w = _world(); p = _party()
	r = _roll(w, "stones", "marks", p, _seed_where(null, "stones", "marks", null, true))
	check(p.scouted_next, "marks: the next fight starts scouted")
	w = _world(); p = _party()
	var t0: float = w.clock.elapsed
	w.clock.elapsed = 1000.0
	r = _roll(w, "stones", "sleep", p, _seed_where(null, "stones", "sleep", null, true))
	check(w.clock.elapsed == 1000.0 - Travel.TIME_SAVED and int(r["minutes"]) < 0, "sleep: the road is quicker")
	w = _world(); p = _party()
	w.clock.elapsed = 10.0
	r = _roll(w, "stones", "sleep", p, _seed_where(null, "stones", "sleep", null, true))
	check(w.clock.elapsed == 0.0, "sleep: the refund floors at zero, not negative")
	w = _world(); p = _party()
	r = _roll(w, "hut", "road", p, _seed_where(null, "hut", "road", null, true))
	check(p.safe_camp, "road: a safe camp tonight")
	w = _world(); p = _party()
	p.stash_add("adamantine-armor", 1, false)
	r = _roll(w, "hut", "knock", p, _seed_where(null, "hut", "knock", null, true))
	check(p.unidentified().is_empty(), "knock: the hermit identifies it")
	check(r["item_name"] != "", "knock: and names it")
	check(r.has("lair") or w.lairs.any(func(l): return l.discovered), "knock: a lead too")
	w = _world(); p = _party()
	r = _roll(w, "wreck", "salvage", p, _seed_where(null, "wreck", "salvage", null, true))
	check(p.stash_count("camp-kit") == 1 and r["item_name"] != "", "salvage: a camp kit")
	w = _world(); p = _party()
	gold0 = p.gold
	r = _roll(w, "wreck", "search", p, _seed_where(null, "wreck", "search", null, true))
	check(p.gold > gold0 and int(r["gold"]) == p.gold - gold0, "search: a cache")
	w = _world(); p = _party()
	var hp0: int = p.party_characters()[0].sheet().max_hp
	r = _roll(w, "wreck", "search", p, _seed_where(null, "wreck", "search", null, false))
	check(int(r["hurt"]) > 0 and p.party_characters().all(func(ch): return ch.hp_current == -1 or ch.hp_current >= 1), "a snare hurts and never drops")
	w = _world(); p = _party()
	r = _roll(w, "ruins", "read", p, _seed_where(null, "ruins", "read", null, true))
	check(w.lairs.any(func(l): return l.discovered) or w.landmarks.any(func(x): return x.found and Landmarks.is_hidden(x.kind)), "read: a lead marks something")
	w = _world(); p = _party()
	var m2 = _mark(w, "tower", Vector2(900, 900))
	var before: int = w.explored.size()
	r = Landmarks.resolve(m2, "climb", p, w, RNG.new(_seed_where(null, "tower", "climb", null, true, m2.position)))
	check(w.explored.size() > before and w.is_explored(Vector2(900, 900)), "climb: the map opens")
	w = _world(); p = _party()
	m2 = _mark(w, "tower", Vector2(900, 900))
	r = Landmarks.resolve(m2, "watch", p, w, RNG.new(_seed_where(null, "tower", "watch", null, true, m2.position)))
	check(w.marked_until > w.clock.elapsed, "watch: bands are marked for the day")

# --- Task 4: discovery — exploring, searching, and the inn -----------------

func test_discovery() -> void:
	var w := _world()
	var p := _party()
	var seen = w.add_landmark(World.Landmark.new("m-ruins", "ruins", Vector2(90, 130)))
	var hid = w.add_landmark(World.Landmark.new("m-hut", "hut", Vector2(100, 150)))
	check(Landmarks.found_on_explore(w).is_empty() and not seen.found, "nothing explored, nothing found")
	w.reveal(Vector2(90, 130))
	var just: Array = Landmarks.found_on_explore(w)
	check(just == [seen] and seen.found and not hid.found, "exploring finds the ruins, not the hut")
	check(Landmarks.found_on_explore(w).is_empty(), "...and says so once")
	check(Landmarks.nearby_hidden(w, Vector2(100, 140)) == hid, "the hut is there to search for")
	check(Landmarks.nearby_hidden(w, Vector2(900, 900)) == null, "...within the lair's radius")
	check(Landmarks.nearest_open(w, Vector2(95, 135)) == seen, "the found ruins are open to visit")
	seen.spent = true
	check(Landmarks.nearest_open(w, Vector2(95, 135)) == null, "...until spent")
	# the search is the lair's check, on the same skill and DC
	var found := false
	for s in range(1, 40):
		var r: Dictionary = Landmarks.search(hid, p, RNG.new(s))
		check(r["skill"] == WorldLairs.DISCOVER_SKILL and int(r["dc"]) == WorldLairs.DISCOVER_DC, "seed %d: Survival vs the lair's DC" % s)
		if r["ok"]:
			found = true
			break
	check(found and hid.found, "a passed search finds the hut")
	# the inn sells a hidden landmark, cheaper than a lair
	w = _world()
	var hut = w.add_landmark(World.Landmark.new("m-hut2", "hut", Vector2(150, 150)))
	var offers: Array = Rumors.offers(w.settlements[0], w)
	var mine: Array = offers.filter(func(o): return o.get("landmark_id", "") == "m-hut2")
	check(mine.size() == 1 and int(mine[0]["price"]) < Rumors.PRICE_BASE, "the inn offers the hut, under a lair's price")
	p.gold = 500
	var bought: Dictionary = Rumors.buy(mine[0], p, w)
	check(bought["ok"] and hut.found and bought["text"].contains(hut.sname), "buying it marks it, and says so")
	check(Rumors.offers(w.settlements[0], w).filter(func(o): return o.get("landmark_id", "") == "m-hut2").is_empty(), "...and it is off the list")
	w.add_landmark(World.Landmark.new("m-ruins2", "ruins", Vector2(160, 160)))
	check(Rumors.offers(w.settlements[0], w).filter(func(o): return o.get("landmark_id", "") == "m-ruins2").is_empty(), "a visible kind is never sold — it is found by walking")
