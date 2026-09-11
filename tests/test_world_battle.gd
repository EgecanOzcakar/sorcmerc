# O5: two non-player parties that meet fight it out off-screen — instantly,
# headless, seeded, and with no scene involved.
#   godot --headless --path . -s tests/test_world_battle.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldBattle = preload("res://core/world_battle.gd")

const RADIUS := 24.0      # scenes/world/world.gd's ENCOUNTER_RADIUS

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_hostile_pair_fights_and_one_dies()
	test_same_seed_same_survivor()
	test_civilized_pair_does_not_fight()
	test_player_pairs_are_left_to_o4()
	test_out_of_radius_is_peace()
	print("test_world_battle: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Stand-in for the map scene's encounter_spec(): the real one prices the roster
# off the player's party via Scaler, which is O4's code and already covered —
# here the rosters are fixed so what is under test is the resolution, not the
# scaling.
static func _spec(p) -> Dictionary:
	var id := "bandit" if p.faction == "bandit" else (
		"goblin" if p.faction == "goblinoid" else "guard")
	return {"monsters": [{"id": id, "count": 3}], "theme": "forest-clearing"}

func _world(pairs: Array) -> World:
	var w = World.new()
	for d in pairs:
		w.add_party(World.RoamingParty.new(d[0], d[1], d[2], d.size() > 3 and d[3]))
	return w

func test_hostile_pair_fights_and_one_dies() -> void:
	var w := _world([["raiders", Vector2.ZERO, "bandit"],
		["patrol", Vector2(RADIUS - 4.0, 0), "soldier"]])
	var before: Array = w.parties.duplicate()
	var out: Array = WorldBattle.check(w, RADIUS, _spec)
	check(out.size() == 1, "one meeting, one battle (got %d)" % out.size())
	check(w.parties.size() == 1, "exactly one party survives (%d left)" % w.parties.size())
	var r: Dictionary = out[0]
	check(w.parties[0] == r["winner"], "the survivor is the reported winner")
	check(not w.parties.has(r["loser"]), "the loser is off the map")
	check(before.has(r["winner"]) and before.has(r["loser"]), "both sides were parties that met")
	check(r["outcome"] in ["Victory", "Defeat", "ongoing"], "the fight reports a real outcome")

	# Resolved and gone: nothing left to re-fight next tick.
	check(WorldBattle.check(w, RADIUS, _spec).is_empty(), "a survivor alone fights nobody")

func test_same_seed_same_survivor() -> void:
	var first := ""
	for i in 2:
		var w := _world([["raiders", Vector2.ZERO, "bandit"],
			["patrol", Vector2(10, 0), "soldier"]])
		WorldBattle.check(w, RADIUS, _spec)
		if i == 0:
			first = w.parties[0].id
		else:
			check(w.parties[0].id == first,
				"the same meeting resolves the same way twice (%s vs %s)" % [first, w.parties[0].id])

func test_civilized_pair_does_not_fight() -> void:
	var w := _world([["patrol-a", Vector2.ZERO, "soldier"],
		["patrol-b", Vector2(2, 2), "soldier"]])
	check(WorldBattle.check(w, RADIUS, _spec).is_empty(), "two garrisons touching do not fight")
	check(w.parties.size() == 2, "and both are still on the map")

func test_player_pairs_are_left_to_o4() -> void:
	# Mixed scene: the player is stacked on a hostile band (O4's trigger fires on
	# this, not O5's), and two NPCs meet elsewhere.
	var w := _world([
		["player", Vector2.ZERO, "soldier", true],
		["ambushers", Vector2(3, 0), "bandit"],
		["raiders", Vector2(500, 0), "goblinoid"],
		["patrol", Vector2(505, 0), "soldier"]])
	var out: Array = WorldBattle.check(w, RADIUS, _spec)
	check(out.size() == 1, "only the NPC-vs-NPC meeting resolved (got %d)" % out.size())
	check(w.player() != null, "the player is never resolved away")
	check(w.parties.has(w.parties[1]) and w.parties[1].id == "ambushers",
		"the party ambushing the player is untouched — O4's real fight still has to happen")
	check(w.parties.size() == 3, "one party died, and it was one of the two NPCs")

func test_out_of_radius_is_peace() -> void:
	var w := _world([["raiders", Vector2.ZERO, "bandit"],
		["patrol", Vector2(RADIUS + 1.0, 0), "soldier"]])
	check(WorldBattle.check(w, RADIUS, _spec).is_empty(), "just outside the radius, nothing happens")
	check(w.parties.size() == 2, "and nobody is removed")
