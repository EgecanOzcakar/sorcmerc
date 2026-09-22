# #156: height on the combat board — what a level costs to climb, what a cliff
# refuses, what the high ground buys, and what a ridge hides.
#   godot --headless --path . -s tests/test_height.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
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
	test_climb_cost()
	test_cliff()
	test_high_ground()
	test_ridge_blocks_sight()
	test_flat_boards_unchanged()
	test_generated_boards()
	print("test_height: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# A strip of nine hexes in a row, with whatever height the caller asks for.
func _strip(height := {}) -> Dictionary:
	var hexes: Array = []
	for q in range(0, 9):
		for r in range(-1, 2):
			hexes.append(Vector2i(q, r))
	return {
		"hexes": hexes, "objects": [], "cover": [], "rough": [],
		"height": height, "palette": "shrine", "reach_melee": 1,
	}

# A plain monster off the bestiary, so every field a fight reads is filled in
# the way the rest of the suite fills it.
func _fighter(id: String, team: String, at: Vector2i, speed := 6):
	var c = Adapter.from_monster(Catalog.all("monsters.json")[0], team, at)
	c.id = id
	c.cname = id.capitalize()
	c.speed = speed
	c.ranged = false
	c.atk_range = 1
	return c

func _fight(board: Dictionary, crew: Array):
	var cb = Combat.new(RNG.new(7), crew, board)
	for c in crew:
		cb.begin_turn_for(c)     # every one of them ready to act, so order does not matter here
	return cb

func test_climb_cost() -> void:
	var hero = _fighter("hero", "party", Vector2i(0, 0))
	var cb = _fight(_strip({Vector2i(1, 0): 1}), [hero])
	var field: Dictionary = cb.move_field(hero)
	check(field.get(Vector2i(1, 0), -1) == 2, "a step up one level costs two, like rough ground")
	check(field.get(Vector2i(0, 1), -1) == 1, "the flat hex beside it still costs one")
	# ...and coming back down is free.
	hero.pos = Vector2i(1, 0)
	cb.begin_turn_for(hero)
	field = cb.move_field(hero)
	check(field.get(Vector2i(0, 0), -1) == 1, "stepping down off a shelf costs one, not two")

func test_cliff() -> void:
	var hero = _fighter("hero", "party", Vector2i(0, 0))
	# A wall of two-level rock across the middle of the strip.
	var height := {}
	for r in range(-1, 2):
		height[Vector2i(4, r)] = 2
	var cb = _fight(_strip(height), [hero])
	check(cb.climb_cost(Vector2i(3, 0), Vector2i(4, 0)) == Hex.STEP_BLOCKED,
		"two levels up is a cliff, not a climb")
	check(cb.climb_cost(Vector2i(4, 0), Vector2i(3, 0)) == Hex.STEP_BLOCKED,
		"...and it is a cliff going down, too")
	hero.speed = 20
	cb.begin_turn_for(hero)
	var field: Dictionary = cb.move_field(hero)
	check(not field.has(Vector2i(4, 0)), "nothing walks onto a cliff top")
	check(not field.has(Vector2i(5, 0)), "...and the far side of a full-width cliff is cut off")
	check(cb.move_path(hero, Vector2i(5, 0)).is_empty(), "no path through it either")

func test_high_ground() -> void:
	var up = _fighter("up", "party", Vector2i(1, 0))
	var down = _fighter("down", "foe", Vector2i(2, 0))
	var cb = _fight(_strip({Vector2i(1, 0): 1}), [up, down])
	check(cb.high_ground(up, down) == cb.HIGH_GROUND_HIT, "shooting downhill is +2")
	check(cb.high_ground(down, up) == 0, "...and shooting uphill is not a penalty, just no bonus")
	# The odds chip and the roll have to agree, which is the only reason
	# hit_chance knows about height at all.
	var flat = _fight(_strip(), [_fighter("a", "party", Vector2i(1, 0)),
		_fighter("b", "foe", Vector2i(2, 0))])
	var p_high: float = cb.hit_chance(up, down)
	var p_flat: float = flat.hit_chance(flat.combatants[0], flat.combatants[1])
	check(p_high > p_flat, "hit_chance counts the high ground the way resolve_attack does")
	# And the swing itself carries it, in the roll and in the line.
	var before: int = cb.log.size()
	var res: Dictionary = cb.resolve_attack(up, down)
	check(int(res.get("high_ground", -1)) == cb.HIGH_GROUND_HIT, "the swing records where the bonus came from")
	check(int(res["bonus"]) == up.atk_bonus + cb.HIGH_GROUND_HIT, "...and the bonus on the roll includes it")
	var line := ""
	for i in range(before, cb.log.size()):
		if String(cb.log[i]).contains("high ground"):
			line = String(cb.log[i])
	check(line != "", "the log says the high ground is why (got: %s)" % ", ".join(cb.log.slice(before)))

func test_ridge_blocks_sight() -> void:
	var a = _fighter("a", "party", Vector2i(0, 0))
	var b = _fighter("b", "foe", Vector2i(4, 0))
	var cb = _fight(_strip({Vector2i(2, 0): 1}), [a, b])
	check(not cb.has_line_of_sight(a.pos, b.pos), "a ridge between two people on the flat hides them")
	# Standing on something as tall as the ridge, you can see over it again.
	cb.board["height"][Vector2i(0, 0)] = 1
	check(cb.has_line_of_sight(a.pos, b.pos), "level with the ridge, the line is open again")
	# A dip is never a wall.
	var low = _fight(_strip({Vector2i(0, 0): 1, Vector2i(4, 0): 1}), [a, b])
	check(low.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0)),
		"low ground between two shelves does not block")

func test_flat_boards_unchanged() -> void:
	var hero = _fighter("hero", "party", Vector2i(0, 0))
	var foe = _fighter("foe", "foe", Vector2i(3, 0))
	var cb = _fight(_strip(), [hero, foe])
	check(cb.height_at(Vector2i(4, 0)) == 0, "a board with no height reads as flat everywhere")
	check(cb.high_ground(hero, foe) == 0, "nobody has the high ground on the flat")
	check(cb.has_line_of_sight(hero.pos, foe.pos), "and the flat sees straight across")
	var field: Dictionary = cb.move_field(hero)
	check(field.get(Vector2i(1, 0), -1) == 1, "every step on the flat still costs one")

# The generator's contract: it only ever raises ground one level, it leaves the
# authored room and the party's own hexes alone, and the board stays walkable
# end to end with the climb rule applied.
func test_generated_boards() -> void:
	var themes: Array = ["", "goblin-camp", "city-square", "forest-clearing", "frozen-cave", "merchant-shop"]
	var raised := 0
	for theme in themes:
		for seed in [11, 5150, 99001, 424242]:
			var b: Dictionary = Encounter.board_for(String(theme), seed)
			var height: Dictionary = b.get("height", {})
			if not height.is_empty():
				raised += 1
			var floor := {}
			for h in b["hexes"]:
				floor[h] = true
			var label := "%s/%d" % [theme if theme != "" else "shrine", seed]
			for h in height:
				check(floor.has(h), "%s: every raised hex is on the board" % label)
				check(int(height[h]) == 1, "%s: the generator only ever raises one level" % label)
			for p in Encounter.PARTY_STARTS:
				check(int(height.get(p, 0)) == 0, "%s: the party starts on the flat" % label)
			# Walkable end to end, climbing allowed, cliffs not: one flood fill
			# from any hex has to reach every other.
			var cb = _fight(b, [_fighter("hero", "party", b["hexes"][0], 4000)])
			var seen: Dictionary = Hex.reachable(cb.passable, b["hexes"][0], 4000, [], [], cb.climb_cost)
			var reach := 0
			for h in floor:
				if seen.has(h) and cb.passable(h):
					reach += 1
			var walkable := 0
			for h in floor:
				if cb.passable(h):
					walkable += 1
			check(reach == walkable, "%s: every walkable hex is still reachable (%d of %d)" % [label, reach, walkable])
	check(raised > 0, "at least some generated boards have raised ground on them")
