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
	test_grown_boards()
	test_shrine_is_unchanged()
	test_hazards_where_expected()
	test_barrel_blocks_until_smashed()
	test_explosive_barrel_burns_its_neighbours()
	test_cone_spell_destroys_a_barrel_in_its_blast()
	test_every_combat_node_has_a_board()
	test_hex_tips()
	print("test_boards: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_every_theme_is_well_formed() -> void:
	for theme in Encounter.THEMES:
		var b: Dictionary = Encounter.board_for(theme)
		var hexes: Array = b["hexes"]
		var seen := {}
		for h in hexes:
			seen[h] = true
		check(hexes.size() >= 60 and hexes.size() <= 170, "%s is 60-170 hexes, the room, its mirror and the ground around (%d)" % [theme, hexes.size()])
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

# The seeded ground around the room: every seed is a different lumpy shape,
# every shape keeps the room, the props and the starts, and is one floor.
func test_grown_boards() -> void:
	for theme in Encounter.THEMES:
		var shapes := {}
		for s in range(1, 13):
			var b: Dictionary = Encounter.board_for(theme, s)
			var seen := {}
			for h in b["hexes"]:
				seen[h] = true
			check(seen.size() == b["hexes"].size(), "%s/%d no duplicates" % [theme, s])
			check(_connected(b), "%s/%d is one connected floor" % [theme, s])
			check(Encounter.PARTY_STARTS.all(func(p): return seen.has(p)), "%s/%d keeps the party starts" % [theme, s])
			check(b["objects"].all(func(o): return seen.has(o["pos"])) and b["cover"].all(func(h): return seen.has(h))
				and b["rough"].all(func(h): return seen.has(h)), "%s/%d keeps props, cover and rough on the floor" % [theme, s])
			var rows := {}
			for h in b["hexes"]:
				rows[h.y] = true
			check(rows.size() >= Encounter.BOARD_ROWS - 2, "%s/%d is at least %d rows tall (%d)" % [theme, s, Encounter.BOARD_ROWS - 2, rows.size()])
			var key := ""
			var sorted: Array = b["hexes"].duplicate()
			sorted.sort()
			for h in sorted:
				key += str(h)
			shapes[key] = true
		check(shapes.size() >= 10, "%s: twelve seeds give at least ten different shapes (%d)" % [theme, shapes.size()])
		check(Encounter.board_for(theme, 0)["hexes"] == Encounter.board_for(theme)["hexes"], "%s: no seed is the fixed shape" % theme)
	# the room's own hexes survive growth on every seed
	var shrine_room: Array = Encounter._widen(Encounter.shrine_board())["hexes"]
	for s in range(1, 13):
		var hs: Array = Encounter.board_for("sunken-shrine", s)["hexes"]
		check(shrine_room.all(func(h): return h in hs), "shrine/%d: the room and its mirror are never bitten" % s)

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
	shove_into_the_brazier_needs_a_brazier()

# You can only put somebody in the fire if they are standing next to it — and
# that is the verb's rule, not just the button's. The resolver used to take the
# action, roll the contest and quietly do nothing when the target was across the
# room, so a shove aimed anywhere but beside the brazier burned the turn.
func shove_into_the_brazier_needs_a_brazier() -> void:
	var cb := _combat("sunken-shrine")
	var hero = cb.combatants[0]
	hero.athletics = 20          # the contest is never what refuses this
	var foe = Adapter.to_combatant(Presets.party()[1], "foe", Vector2i(1, 0))
	foe.athletics = -5
	foe.acro = -5
	cb.combatants.append(foe)
	var shove: Dictionary = cb._basic("shove_brazier")

	hero.pos = Vector2i(0, 0)    # both of them a room away from the brazier at (5,1)
	cb.begin_turn_for(hero)
	check(not cb.legal_target(hero, shove, foe), "an enemy across the room is not a legal target")
	check(cb.available(hero).filter(func(v): return v.get("choice", "") == "brazier").is_empty(),
		"and the verb is not offered at all")
	var hp: int = foe.hp
	var res: Dictionary = cb.perform(hero, shove, foe)
	check(res.has("error"), "performing it anyway is refused (got %s)" % str(res))
	check(foe.hp == hp, "the enemy takes no fire damage")
	check(int(hero.econ["action"]) == 1, "and the action is still there to spend on something else")

	hero.pos = Vector2i(4, 0)    # beside the brazier, and so is the foe
	foe.pos = Vector2i(5, 0)
	cb.begin_turn_for(hero)
	check(cb.legal_target(hero, shove, foe), "beside the brazier it is a legal target")
	res = cb.perform(hero, shove, foe)
	check(res.get("success", false) and foe.hp < hp, "and the shove burns them")

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

# A barrel doesn't need "smash" specifically to go — any AoE that reaches its
# hex claims it too, the same way a real explosion would.
func test_cone_spell_destroys_a_barrel_in_its_blast() -> void:
	var cb := _combat("merchant-shop")
	var barrel: Dictionary = cb.objects().filter(func(o): return o["type"] == "barrel")[0]
	var hero = cb.combatants[0]
	hero.pos = barrel["pos"] + Vector2i(0, 1)
	cb.begin_turn_for(hero)
	var v := {"id": "test-cone", "kind": "spell", "spell": "burning-hands", "label": "Burning Hands",
		"cost": "action", "slot_level": 0, "shape": "cone", "targeting": "direction",
		"range_ft": 15, "radius": 2, "dice_count": 3, "dice_sides": 6, "damage_type": "fire",
		"save": "dex", "save_dc": 13, "half_on_save": true}
	var dir: Vector2i = barrel["pos"] - hero.pos
	cb.cast(hero, v, dir)
	check(cb.object_at(barrel["pos"]).is_empty(), "the barrel in the cone's blast is destroyed")
	check(cb.passable(barrel["pos"]), "and its hex clears")

func test_every_combat_node_has_a_board() -> void:
	var Campaign = load("res://core/campaign.gd")
	for n in Campaign.POOL + Campaign.BOSS_POOL:
		if n.get("kind", "") != "combat":
			continue
		check(n.get("theme", "") in Encounter.THEMES, "%s names a real board (%s)" % [n["id"], n.get("theme", "")])
	var Party = load("res://core/party.gd")
	var party = Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var run = Campaign.new(party, 3)
	for i in run.options().size():        # T12: whichever fight this seed's stage 0 offers
		if run.options()[i]["kind"] != "combat":
			continue
		var picked: Dictionary = run.enter(i)
		check(run.combat_spec().get("theme", "") == picked["theme"],
			"combat_spec carries the node's theme")
		break

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

# Special tiles explain themselves on hover: what they are and what they change.
func test_hex_tips() -> void:
	var Board = load("res://scenes/main.gd").Board
	var cb = Encounter.build({"monsters": [{"id": "goblin", "count": 1}], "theme": "goblin-camp", "seed": 1}, [])
	var b: Dictionary = cb.board
	check(Board.hex_tip(cb, b["cover"][0]).contains("+2 AC"), "cover says what it does for AC")
	check(Board.hex_tip(cb, b["rough"][0]).contains("costs two"), "rough ground says what it costs")
	var plain := Vector2i(999, 999)
	for hx in b["hexes"]:
		if not cb.is_cover(hx) and not (hx in cb._rough()) and cb.object_at(hx).is_empty():
			plain = hx
			break
	check(Board.hex_tip(cb, plain) == "", "a plain hex says nothing")
	for o in cb.objects():
		var tip: String = Board.hex_tip(cb, o["pos"])
		check(tip.begins_with(String(o["type"]).capitalize()), "%s names itself" % o["type"])
		if o.has("hazard") and not o.get("explosive", false):
			check(tip.contains("Shove"), "%s explains the shove" % o["type"])
		if o.get("explosive", false):
			check(tip.contains("bursts"), "%s warns that it bursts" % o["type"])
