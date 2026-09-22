# Area spells on the hex board (one hex / a corner circle / a line) and the
# concentration mechanism that holds their conditions.
#   godot --headless --path . -s tests/test_areas_concentration.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Hex = preload("res://core/hex.gd")
const Combat = preload("res://core/combat.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const AI = preload("res://core/ai.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_targeting_tiers()
	test_one_hex_area()
	test_corner_circle()
	test_line()
	test_concentration_holds_and_breaks()
	test_repeat_saves()
	test_concentration_lapses()
	test_autopilot_aims_areas()
	test_upcast_targets()
	print("test_areas_concentration: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# A cleric with the named spells prepared, on the shrine at (2,0), plus goblins where asked.
func _setup(spells: Array, goblins: Array, levels := 3) -> Combat:
	var ch := Presets.ilsa(levels)
	ch.prepared.assign(spells)
	var ilsa = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
	# the test hands the cleric level-3 slots for anything up to 3rd level
	ilsa.slots.assign([4, 2, 2])
	var all: Array = [ilsa]
	var n := 0
	for g in goblins:
		n += 1
		all.append(Encounter.spawn("goblin", 1.0, "foe", g, n))
	var cb := Combat.new(RNG.new(7), all, Encounter.board_for("marsh"))   # no walls on it: this file is about areas, not sight
	for c in cb.combatants:
		cb.begin_turn_for(c)
	return cb

func _verb(c, spell: String) -> Dictionary:
	for v in c.verbs:
		if String(v.get("spell", "")) == spell and not String(v["id"]).contains("@"):
			return v
	return {}

func test_targeting_tiers() -> void:
	var cb := _setup(["sleep", "fireball", "hypnotic-pattern", "lightning-bolt", "hold-person", "moonbeam", "arms-of-hadar"], [Vector2i(5, 1)])
	var ilsa = cb.combatants[0]
	var tiers := {"sleep": "hex", "moonbeam": "hex", "fireball": "corner", "hypnotic-pattern": "corner",
		"lightning-bolt": "line", "hold-person": "enemy", "arms-of-hadar": "self_area"}
	for sid in tiers:
		var v := _verb(ilsa, sid)
		check(not v.is_empty(), "%s is a verb the cleric can see" % sid)
		check(v.get("targeting", "") == tiers[sid], "%s targets a %s (got %s)" % [sid, tiers[sid], v.get("targeting", "")])
	check(int(_verb(ilsa, "lightning-bolt").get("length", 0)) == Adapter.RANGE_CAP, "a 100 ft bolt runs the capped %d hexes" % Adapter.RANGE_CAP)
	check(int(_verb(ilsa, "fireball").get("ring", 9)) == 0, "a 20 ft radius is the three corner hexes")

func test_one_hex_area() -> void:
	var cb := _setup(["sleep"], [Vector2i(5, 1), Vector2i(6, 1)])
	var ilsa = cb.combatants[0]
	var v := _verb(ilsa, "sleep")
	check(cb.legal_area(ilsa, v, Vector2i(5, 1)), "a hex in range is a legal aim")
	check(not cb.legal_area(ilsa, v, Vector2i(40, 40)), "off the board is not")
	check(cb.area_hexes(ilsa, v, Vector2i(5, 1)) == [Vector2i(5, 1)], "a 5 ft sphere is exactly the aimed hex")
	var r := cb.perform(ilsa, v, Vector2i(5, 1))
	check(r.get("area", []) == [Vector2i(5, 1)], "the cast reports what it covered")
	var g1 = cb.combatants[1]
	var g2 = cb.combatants[2]
	check(g2.statuses.is_empty() or not g2.has("incapacitated"), "the goblin next door is untouched")
	check(cb.log.any(func(l): return l.contains(g1.cname)), "the goblin on the hex rolled its save")

func test_corner_circle() -> void:
	var cb := _setup(["fireball"], [Vector2i(5, 1), Vector2i(6, 0), Vector2i(6, 1), Vector2i(4, 3)])
	var ilsa = cb.combatants[0]
	var v := _verb(ilsa, "fireball")
	# the corner shared by (5,1), (6,0), (6,1)
	var corner := Hex.corner(Vector2i(5, 1), 0)
	check(corner.has(Vector2i(6, 0)) and corner.has(Vector2i(6, 1)), "corner 0 of (5,1) touches (6,0) and (6,1)")
	var area := cb.area_hexes(ilsa, v, corner)
	check(area.size() == 3, "a 20 ft radius circle is three hexes (%d)" % area.size())
	check(cb.legal_area(ilsa, v, corner), "the corner is in range")
	var hp_before: Array = cb.combatants.slice(1).map(func(c): return c.hp)
	cb.perform(ilsa, v, corner)
	var hurt := 0
	for i in range(1, 5):
		if cb.combatants[i].hp < hp_before[i - 1]:
			hurt += 1
	check(hurt >= 2 and cb.combatants[4].hp == hp_before[3], "the three at the corner burn (%d hurt), the one at (4,3) does not" % hurt)
	check(ilsa.slots[2] == 1, "fireball spent a 3rd-level slot")
	# a corner with a hex off the board is still aimable if one hex is on it
	var edge := Hex.corner(Vector2i(0, 0), 3)
	check(cb.legal_area(ilsa, v, edge) == edge.any(func(h): return h in cb.board["hexes"]), "an edge corner counts if any hex is on the board")

func test_line() -> void:
	var cb := _setup(["lightning-bolt"], [Vector2i(4, 0), Vector2i(6, 0), Vector2i(4, 2)])
	var ilsa = cb.combatants[0]
	var v := _verb(ilsa, "lightning-bolt")
	var ray := cb.area_hexes(ilsa, v, Vector2i(3, 0))
	check(ray.size() == Adapter.RANGE_CAP and ray[0] == Vector2i(3, 0) and ray.has(Vector2i(6, 0)),
		"aimed at (3,0) the bolt runs the row past it to full length: %s" % str(ray))
	check(not ray.has(Vector2i(2, 0)), "the caster's own hex is not in the line")
	check(not cb.legal_area(ilsa, v, ilsa.pos), "a line needs a direction — not the caster's hex")
	var before: Array = cb.combatants.slice(1).map(func(c): return c.hp)
	cb.perform(ilsa, v, Vector2i(3, 0))
	check(cb.combatants[3].hp == before[2], "the goblin off the line at (4,2) is untouched")
	check(cb.log.any(func(l): return l.contains(cb.combatants[2].cname)), "the goblin at (6,0), past the aimed hex, still rolls")

func test_concentration_holds_and_breaks() -> void:
	var cb := _setup(["hideous-laughter"], [Vector2i(4, 0)])
	var ilsa = cb.combatants[0]
	var gob = cb.combatants[1]
	ilsa.save_dc = 30   # the goblin cannot make it
	var v := _verb(ilsa, "hideous-laughter")
	check(v["duration"] == "concentration" and v["repeat_save"] == "on_damage", "hideous laughter is held, shaken by damage")
	cb.perform(ilsa, v, gob)
	check(gob.has("prone") and gob.has("incapacitated"), "the goblin is laughing on the floor")
	check(gob.statuses["prone"] is Dictionary and gob.statuses["prone"].get("held_by") == ilsa, "the condition is held by the caster")
	check(ilsa.statuses["concentrating"]["spell"] == "hideous-laughter", "the cleric is concentrating on it")
	# a second concentration spell drops the first and frees the goblin
	var again := v.duplicate()
	again["spell"] = "other"
	again["id"] = "other"
	cb.cast(ilsa, again, gob)   # re-lands 'other' on the goblin; the laughter's hold is gone
	check(not gob.statuses["prone"].get("spell", "") == "hideous-laughter", "casting another concentration spell ended the laughter")
	# the goblin turn passes: a held condition does NOT expire on its own like a one-round one
	cb.begin_turn_for(gob)
	check(gob.has("prone"), "a held condition survives the target's turn start")
	# the caster goes down: everything held is released
	ilsa.max_hp = 10; ilsa.hp = 10
	cb._apply_damage(ilsa, 10)
	check(ilsa.is_down() and not ilsa.has("concentrating"), "a downed caster stops concentrating")
	check(not gob.has("prone") and not gob.has("incapacitated"), "...and the goblin is free")

func test_repeat_saves() -> void:
	# end_turn: hold-person's paralysis is rerolled at the end of the target's turn
	var cb := _setup(["hold-person"], [Vector2i(4, 0)])
	var ilsa = cb.combatants[0]
	var gob = cb.combatants[1]
	ilsa.save_dc = 30
	cb.perform(ilsa, _verb(ilsa, "hold-person"), gob)
	check(gob.has("paralyzed"), "hold person paralyzes on a failed save")
	gob.saves["wis"] = 100   # now it cannot fail
	cb._repeat_saves(gob, "on_damage")
	check(gob.has("paralyzed"), "an end-of-turn save does not fire on damage")
	cb._repeat_saves(gob, "end_turn")
	check(not gob.has("paralyzed"), "...but at the end of its turn the goblin shakes it off")
	# damage_ends: hypnotic pattern breaks on any damage, no roll
	var cb2 := _setup(["hypnotic-pattern"], [Vector2i(4, 0)])
	var i2 = cb2.combatants[0]
	var g2 = cb2.combatants[1]
	i2.save_dc = 30
	var hp := _verb(i2, "hypnotic-pattern")
	var corner := Hex.corner(Vector2i(4, 0), 0)
	cb2.perform(i2, hp, corner)
	var held: Array = g2.statuses.keys().filter(func(k): return g2.statuses[k] is Dictionary and g2.statuses[k].has("held_by"))
	check(not held.is_empty(), "hypnotic pattern lands a held condition (%s)" % str(held))
	g2.saves["wis"] = -100
	cb2._apply_damage(g2, 1)
	check(g2.statuses.keys().filter(func(k): return g2.statuses[k] is Dictionary and g2.statuses[k].has("held_by")).is_empty(),
		"any damage ends it, no save")
	# none: banishment holds for the duration regardless of turns or damage
	var cb3 := _setup(["banishment"], [Vector2i(4, 0)])
	var i3 = cb3.combatants[0]
	var g3 = cb3.combatants[1]
	i3.save_dc = 30
	cb3.perform(i3, _verb(i3, "banishment"), g3)
	var held3: Array = g3.statuses.keys().filter(func(k): return g3.statuses[k] is Dictionary and g3.statuses[k].has("held_by"))
	g3.saves["cha"] = 100
	cb3._repeat_saves(g3, "end_turn")
	cb3._apply_damage(g3, 1)
	check(held3.all(func(k): return g3.has(k)), "banishment is not shaken off by turns or damage")

func test_concentration_lapses() -> void:
	var cb := _setup(["hold-person"], [Vector2i(4, 0)])
	var ilsa = cb.combatants[0]
	var gob = cb.combatants[1]
	ilsa.save_dc = 30
	gob.saves["wis"] = -100
	cb.perform(ilsa, _verb(ilsa, "hold-person"), gob)
	check(int(ilsa.statuses["concentrating"]["until_round"]) == cb.round_num + Combat.CONCENTRATION_ROUNDS, "a minute of concentration")
	cb.round_num += Combat.CONCENTRATION_ROUNDS - 1
	cb.begin_turn_for(ilsa)
	check(gob.has("paralyzed"), "still held one round before the minute is up")
	cb.round_num += 1
	cb.begin_turn_for(ilsa)
	check(not ilsa.has("concentrating") and not gob.has("paralyzed"), "the spell lapses at the caster's turn after ten rounds")

func test_autopilot_aims_areas() -> void:
	# three goblins clustered on one corner: the autopilot finds it and fireballs
	var cb := _setup(["fireball"], [Vector2i(5, 1), Vector2i(6, 0), Vector2i(6, 1)])
	var ilsa = cb.combatants[0]
	var aim = AI._best_area(cb, ilsa, _verb(ilsa, "fireball"))
	check(aim is Array and aim.size() == 3 and aim.has(Vector2i(5, 1)) and aim.has(Vector2i(6, 0)),
		"the autopilot picks the corner all three share (%s)" % str(aim))
	# spread out, no corner nets two: it holds the slot
	var cb2 := _setup(["fireball"], [Vector2i(5, 1), Vector2i(1, 3)])
	check(AI._best_area(cb2, cb2.combatants[0], _verb(cb2.combatants[0], "fireball")) == null, "no aim worth a slot -> none")

# Hold Person from a 3rd-level slot also holds the nearest other humanoid
# within 30 ft of the aimed one; the base cast holds one; nobody far away.
func test_upcast_targets() -> void:
	var cb := _setup(["hold-person"], [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(13, 1)], 5)
	var ilsa = cb.combatants[0]
	var gobs := cb.combatants.slice(1)
	ilsa.save_dc = 30
	var base := _verb(ilsa, "hold-person")
	var up3: Dictionary = {}
	for v in ilsa.verbs:
		if String(v["id"]) == "hold-person@3":
			up3 = v
	check(not base.has("targets") and int(up3.get("targets", 1)) == 2,
		"a 3rd-level Hold Person is authored as two targets, the 2nd-level one as one")
	check(cb.extra_targets(ilsa, up3, gobs[0]).size() == 1, "one extra target is picked")
	check(cb.extra_targets(ilsa, up3, gobs[0])[0] == gobs[1], "...the nearest to the aimed one")
	check(cb.extra_targets(ilsa, up3, gobs[3]).is_empty(), "nobody within 30 ft: no extras")
	check(cb.extra_targets(ilsa, base, gobs[0]).is_empty(), "the base cast has no extras")
	up3["save_dc"] = 30
	cb.perform(ilsa, up3, gobs[0])
	check(gobs[0].has("paralyzed") and gobs[1].has("paralyzed"), "both are held")
	check(not gobs[2].has("paralyzed") and not gobs[3].has("paralyzed"), "the third and the far one are not")
	check(ilsa.slots[2] == 1, "one 3rd-level slot spent")
