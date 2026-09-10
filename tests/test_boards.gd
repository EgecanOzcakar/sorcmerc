# T11: board themes + interactables.
#   godot --headless --path . -s tests/test_boards.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Presets = preload("res://core/presets.gd")
const RNG = preload("res://core/rng.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_every_theme_is_well_formed()
	test_shrine_is_unchanged()
	test_hazards_where_expected()
	test_barrel_blocks_until_smashed()
	test_explosive_barrel_burns_its_neighbours()
	test_every_combat_node_has_a_board()
	print("test_boards: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_every_theme_is_well_formed() -> void:
	for theme in Encounter.THEMES:
		var b: Dictionary = Encounter.board_for(theme)
		var hexes: Array = b["hexes"]
		var seen := {}
		for h in hexes:
			seen[h] = true
		check(hexes.size() >= 18 and hexes.size() <= 32, "%s is 18-32 hexes (%d)" % [theme, hexes.size()])
		check(seen.size() == hexes.size(), "%s has no duplicate hexes" % theme)
		check(b.get("cover", []).all(func(h): return seen.has(h)), "%s cover is on the board" % theme)
		check(b.get("rough", []).all(func(h): return seen.has(h)), "%s rough is on the board" % theme)
		check(b.get("objects", []).all(func(o): return seen.has(o["pos"])), "%s objects are on the board" % theme)
		var starts: Array = Encounter.PARTY_STARTS
		var blocked: Array = b.get("objects", []).filter(
			func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
		check(starts.all(func(p): return seen.has(p) and not p in blocked),
			"%s has room for every party start" % theme)
		check(_connected(b), "%s is walkable end to end" % theme)
		check(b.has("reach_melee") and b.has("region_at"), "%s carries the resolver's keys" % theme)

# The whole game's tuning assumes this room. If this test fails, someone drifted it.
func test_shrine_is_unchanged() -> void:
	var b := Encounter.shrine_board()
	var expect: Array = []
	for r in 3:
		expect.append_array([Vector2i(0, r), Vector2i(1, r), Vector2i(2, r)])
	expect.append(Vector2i(3, 1))
	for r in 3:
		expect.append_array([Vector2i(4, r), Vector2i(5, r), Vector2i(6, r)])
	expect.append(Vector2i(7, 1))
	for r in 3:
		expect.append(Vector2i(8, r))
	check(b["hexes"] == expect, "the Sunken Shrine layout is byte-for-byte unchanged")
	check(b["cover"] == [Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2)], "the Alcove is still the cover")
	check(b["rough"] == [Vector2i(4, 1), Vector2i(6, 1)], "the scorched ground is unchanged")
	check(b["objects"].size() == 1 and b["objects"][0]["pos"] == Vector2i(5, 1),
		"the brazier still stands at (5,1) and is the only object")
	check(b["objects"][0]["hazard"] == {"dice": "2d6", "damage_type": "fire"}, "the brazier is still 2d6 fire")
	check(not b["objects"][0].has("hp"), "the brazier is indestructible, as before")
	check(int(b["reach_melee"]) == 1, "melee reach is unchanged")

func test_hazards_where_expected() -> void:
	for theme in ["sunken-shrine", "goblin-camp"]:
		var haz: Array = Encounter.board_for(theme)["objects"].filter(func(o): return o.has("hazard"))
		check(not haz.is_empty(), "%s carries a shove-into hazard" % theme)
	var cb := _combat("sunken-shrine")
	var hero = cb.combatants[0]
	hero.pos = Vector2i(5, 0)   # beside the brazier
	check(cb.adjacent_to_hazard(hero), "adjacent_to_hazard finds the brazier")
	check(cb.adjacent_hazard(hero)["type"] == "brazier", "and reports which one")
	hero.pos = Vector2i(0, 0)
	check(not cb.adjacent_to_hazard(hero), "and nothing across the room")

func test_barrel_blocks_until_smashed() -> void:
	var cb := _combat("merchant-shop")
	var barrel: Dictionary = cb.objects().filter(func(o): return o["type"] == "barrel")[0]
	check(not cb.passable(barrel["pos"]), "a barrel is impassable")
	var hero = cb.combatants[0]
	hero.pos = barrel["pos"] + Vector2i(0, 1)
	cb.begin_turn_for(hero)
	check(not cb.move_field(hero).has(barrel["pos"]), "you cannot walk into it")
	var smash: Dictionary = cb.available(hero).filter(func(v): return v["kind"] == "smash")[0]
	cb.perform(hero, smash)
	check(cb.passable(barrel["pos"]), "smashing it clears the hex")
	check(cb.object_at(barrel["pos"]).is_empty(), "and removes the object")
	check(cb.available(hero).filter(func(v): return v["kind"] == "smash").is_empty(),
		"nothing left to smash, no button")

func test_explosive_barrel_burns_its_neighbours() -> void:
	var cb := _combat("goblin-camp")
	var keg: Dictionary = cb.objects().filter(func(o): return o.get("explosive", false))[0]
	var hero = cb.combatants[0]
	var bystander = cb.combatants[1]
	hero.pos = keg["pos"] + Vector2i(1, 0)
	bystander.pos = keg["pos"] + Vector2i(-1, 1)
	var far = cb.combatants[2]
	far.pos = Vector2i(0, 0)
	var hp_before: Array = [hero.hp, bystander.hp, far.hp]
	cb.begin_turn_for(hero)
	cb.perform(hero, cb.available(hero).filter(func(v): return v["kind"] == "smash")[0])
	check(hero.hp < hp_before[0], "the smasher eats the blast")
	check(bystander.hp < hp_before[1], "so does the hex on the other side")
	check(far.hp == hp_before[2], "someone across the camp does not")
	check(cb.passable(keg["pos"]), "the keg's hex is clear")

func test_every_combat_node_has_a_board() -> void:
	var Campaign = load("res://core/campaign.gd")
	for stage in Campaign.STAGES:
		for n in stage:
			if n.get("kind", "") != "combat":
				continue
			check(n.get("theme", "") in Encounter.THEMES, "%s names a real board (%s)" % [n["id"], n.get("theme", "")])
	var Party = load("res://core/party.gd")
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var run = Campaign.new(party, 3)
	run.enter(0)   # stage 0's combat node
	check(run.combat_spec().get("theme", "") == "forest-clearing", "combat_spec carries the node's theme")

# --- helpers ----------------------------------------------------------

func _combat(theme: String) -> Combat:
	var cs: Array = []
	var chars := Presets.party()
	for i in chars.size():
		cs.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return Combat.new(RNG.new(7), cs, Encounter.board_for(theme))

# Every walkable hex reachable from the first one (blocking props may not island the map).
func _connected(b: Dictionary) -> bool:
	var blocked: Dictionary = {}
	for o in b.get("objects", []):
		if o.get("blocks_movement", false):
			blocked[o["pos"]] = true
	var open: Array = b["hexes"].filter(func(h): return not blocked.has(h))
	if open.is_empty():
		return false
	var seen := {open[0]: true}
	var q: Array = [open[0]]
	while not q.is_empty():
		for n in Hex.neighbors(q.pop_back()):
			if n in open and not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen.size() == open.size()
