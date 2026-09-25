# O5: two non-player parties that meet fight it out off-screen — headless,
# seeded, and with no scene involved. #229: and the fight takes world time: the
# two bands are locked in a clash for its rounds, an hour each, and the loser
# only falls when the clock has run through them. #227: and nobody hears it.
#   godot --headless --path . -s tests/test_world_battle.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldBattle = preload("res://core/world_battle.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldSave = preload("res://core/world_save.gd")
const Sound = preload("res://core/audio.gd")
const Encounter = preload("res://core/encounter.gd")

const RADIUS := 24.0      # scenes/world/world.gd's ENCOUNTER_RADIUS

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# #227: stands in for the Audio autoload, which a test's main loop never has —
# which is exactly why the suite never heard a band's fight. core/audio.gd's
# statics call these two on whatever `_i` is; this one just writes down what
# it was asked to play.
class Ear extends RefCounted:
	var heard: Array = []
	func _take_of(dir: String, id: String) -> String:
		return dir + id + ".wav"
	func _play_one_shot(path: String, _pitch := 1.0) -> void:
		heard.append(path)

func _init() -> void:
	test_meeting_opens_a_clash_and_nobody_falls_yet()
	test_the_clock_decides_when_it_ends()
	test_locked_bands_stand_still()
	test_same_seed_same_survivor()
	test_a_clash_rides_the_save()
	test_a_third_band_waits_its_turn()
	test_a_side_leaving_the_map_ends_it()
	test_civilized_pair_does_not_fight()
	test_player_pairs_are_left_to_o4()
	test_out_of_radius_is_peace()
	test_nobody_hears_it()
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

func _pair() -> World:
	return _world([["raiders", Vector2.ZERO, "bandit"],
		["patrol", Vector2(RADIUS - 4.0, 0), "human"]])

func test_meeting_opens_a_clash_and_nobody_falls_yet() -> void:
	var w := _pair()
	var out: Array = WorldBattle.check(w, RADIUS, _spec)
	check(out.is_empty(), "#229: nothing has ENDED the frame they meet (got %d)" % out.size())
	check(w.parties.size() == 2, "both bands are still on the map")
	check(w.clashes.size() == 1, "one meeting, one clash (got %d)" % w.clashes.size())
	var c: Dictionary = w.clashes[0]
	check(int(c["rounds"]) >= 1, "the fight lasted at least a round (%d)" % int(c["rounds"]))
	check(is_equal_approx(float(c["until"]) - float(c["from"]), int(c["rounds"]) * WorldBattle.MINUTES_PER_ROUND),
		"it is held for its rounds at an hour each")
	check(String(c["winner"]) in ["raiders", "patrol"], "the verdict names one of the two")
	check(String(c["outcome"]) in ["Victory", "Defeat", "ongoing"], "the fight reports a real outcome")
	check(not w.clash_of(w.parties[0]).is_empty() and not w.clash_of(w.parties[1]).is_empty(),
		"both bands know they are in it")
	check(WorldBattle.round_of(c, float(c["from"])) == 1, "it opens on round 1")
	check(WorldBattle.round_of(c, float(c["until"]) + 999.0) == int(c["rounds"]),
		"and the label never counts past its last round")
	# The next frame is not a second fight between the same two.
	check(WorldBattle.check(w, RADIUS, _spec).is_empty() and w.clashes.size() == 1,
		"a band already fighting does not start another fight")

func test_the_clock_decides_when_it_ends() -> void:
	var w := _pair()
	var before: Array = w.parties.duplicate()
	WorldBattle.check(w, RADIUS, _spec)
	var c: Dictionary = w.clashes[0]
	w.clock.elapsed = float(c["until"]) - 1.0
	check(WorldBattle.check(w, RADIUS, _spec).is_empty() and w.parties.size() == 2,
		"a minute short of its last round, still fighting")
	w.clock.elapsed = float(c["until"])
	var out: Array = WorldBattle.check(w, RADIUS, _spec)
	check(out.size() == 1, "the fight lands when its time is up (got %d)" % out.size())
	check(w.parties.size() == 1 and w.clashes.is_empty(), "exactly one party survives, and the clash is closed")
	var r: Dictionary = out[0]
	check(w.parties[0] == r["winner"] and r["winner"].id == String(c["winner"]),
		"the survivor is the verdict decided at contact")
	check(not w.parties.has(r["loser"]), "the loser is off the map")
	check(before.has(r["winner"]) and before.has(r["loser"]), "both sides were parties that met")
	check(int(r["rounds"]) == int(c["rounds"]), "the result says how long it went on")
	check(WorldBattle.check(w, RADIUS, _spec).is_empty(), "a survivor alone fights nobody")

func test_locked_bands_stand_still() -> void:
	var w := _pair()
	WorldBattle.check(w, RADIUS, _spec)
	var at: Array = w.parties.map(func(p): return p.position)
	for p in w.parties:
		p.goal = p.position + Vector2(500, 300)   # somewhere to be, if they could go
	w.tick(10.0)
	WorldAI.update(w)
	w.tick(10.0)
	check(w.parties[0].position == at[0] and w.parties[1].position == at[1],
		"World.tick walks neither band while they fight")
	# ...and once it is over the winner walks on.
	w.clock.elapsed = float(w.clashes[0]["until"])
	WorldBattle.check(w, RADIUS, _spec)
	var winner = w.parties[0]
	var was: Vector2 = winner.position
	winner.goal = was + Vector2(500, 0)
	w.tick(1.0)
	check(winner.position != was, "the winner is free the moment it ends")

func test_same_seed_same_survivor() -> void:
	var first := ""
	var first_rounds := 0
	for i in 2:
		var w := _world([["raiders", Vector2.ZERO, "bandit"],
			["patrol", Vector2(10, 0), "human"]])
		WorldBattle.check(w, RADIUS, _spec)
		var c: Dictionary = w.clashes[0]
		w.clock.elapsed = float(c["until"])
		WorldBattle.check(w, RADIUS, _spec)
		if i == 0:
			first = w.parties[0].id
			first_rounds = int(c["rounds"])
		else:
			check(w.parties[0].id == first,
				"the same meeting resolves the same way twice (%s vs %s)" % [first, w.parties[0].id])
			check(int(c["rounds"]) == first_rounds, "and takes as long")

# The determinism idiom: a reload mid-battle is the same battle, verdict and
# clock and all — not a re-fight that could come out the other way.
func test_a_clash_rides_the_save() -> void:
	var w := _pair()
	w.clock.elapsed = 500.0
	WorldBattle.check(w, RADIUS, _spec)
	var c: Dictionary = w.clashes[0]
	# Through JSON, the way it reaches the disk: numbers come back as floats.
	var d = JSON.parse_string(JSON.stringify(WorldSave.to_dict(w)))
	var w2 = WorldSave.from_dict(d)["world"]
	check(w2.clashes.size() == 1, "the clash is in the save")
	var c2: Dictionary = w2.clashes[0]
	check(c2["a"] == c["a"] and c2["b"] == c["b"] and c2["winner"] == c["winner"]
		and int(c2["rounds"]) == int(c["rounds"]) and is_equal_approx(float(c2["until"]), float(c["until"]))
		and c2["at"] is Vector2 and (c2["at"] as Vector2).is_equal_approx(c["at"]),
		"...every field of it, the midpoint as a Vector2")
	w2.clock.elapsed = float(c2["until"])
	var out: Array = WorldBattle.check(w2, RADIUS, _spec)
	check(out.size() == 1 and out[0]["winner"].id == String(c["winner"]), "and it ends the way it would have")
	# A save written before battles took time has no key at all.
	var old: Dictionary = WorldSave.to_dict(_pair())
	old.erase("clashes")
	check(WorldSave.from_dict(old)["world"].clashes.is_empty(), "an old save loads with no clashes")

func test_a_third_band_waits_its_turn() -> void:
	var w := _world([["raiders", Vector2.ZERO, "bandit"],
		["patrol", Vector2(10, 0), "human"],
		["watch", Vector2(5, 5), "human"]])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.clashes.size() == 1 and w.parties.size() == 3,
		"one fight at a time per band: the third stands by (%d clashes)" % w.clashes.size())
	var free = null
	for p in w.parties:
		if w.clash_of(p).is_empty():
			free = p
	check(free != null and free.id != "raiders", "and it is a patrol that waits, not the raiders")

func test_a_side_leaving_the_map_ends_it() -> void:
	var w := _pair()
	WorldBattle.check(w, RADIUS, _spec)
	var gone = w.parties[0]
	w.parties.erase(gone)   # what raids.gd does to raiders whose lair is gone
	var out: Array = WorldBattle.check(w, RADIUS, _spec)
	check(out.is_empty() and w.clashes.is_empty(), "the clash closes with nobody lost")
	check(w.parties.size() == 1 and w.clash_of(w.parties[0]).is_empty(), "the one left is free")

func test_civilized_pair_does_not_fight() -> void:
	var w := _world([["patrol-a", Vector2.ZERO, "human"],
		["patrol-b", Vector2(2, 2), "human"]])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.clashes.is_empty(), "two garrisons touching do not fight")
	check(w.parties.size() == 2, "and both are still on the map")

func test_player_pairs_are_left_to_o4() -> void:
	# Mixed scene: the player is stacked on a hostile band (O4's trigger fires on
	# this, not O5's), and two NPCs meet elsewhere.
	var w := _world([
		["player", Vector2.ZERO, "human", true],
		["ambushers", Vector2(3, 0), "bandit"],
		["raiders", Vector2(500, 0), "goblinoid"],
		["patrol", Vector2(505, 0), "human"]])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.clashes.size() == 1, "only the NPC-vs-NPC meeting fights (got %d)" % w.clashes.size())
	check(String(w.clashes[0]["a"]) != "player" and String(w.clashes[0]["b"]) != "player"
		and String(w.clashes[0]["a"]) != "ambushers" and String(w.clashes[0]["b"]) != "ambushers",
		"the party ambushing the player is untouched — O4's real fight still has to happen")
	w.clock.elapsed = float(w.clashes[0]["until"])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.player() != null, "the player is never resolved away")
	check(w.parties.size() == 3, "one party died, and it was one of the two NPCs")

func test_out_of_radius_is_peace() -> void:
	var w := _world([["raiders", Vector2.ZERO, "bandit"],
		["patrol", Vector2(RADIUS + 1.0, 0), "human"]])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.clashes.is_empty(), "just outside the radius, nothing happens")
	check(w.parties.size() == 2, "and nobody is removed")

# #227: with an ear on the Audio statics, a whole band-vs-band fight — hits,
# misses, kills — plays nothing. The control proves the ear works: the same
# kind of Combat, audible (the default), is heard.
func test_nobody_hears_it() -> void:
	var ear := Ear.new()
	Sound._i = ear
	var w := _pair()
	WorldBattle.check(w, RADIUS, _spec)
	w.clock.elapsed = float(w.clashes[0]["until"])
	WorldBattle.check(w, RADIUS, _spec)
	check(w.parties.size() == 1, "the fight really was fought")
	check(ear.heard.is_empty(), "#227: not one sting from a fight nobody saw (%s)" % str(ear.heard.slice(0, 5)))
	var cb = Encounter.build(_spec(w.parties[0]), [], Encounter.board_for("forest-clearing"))
	cb.bark(cb.combatants[0], "kill")
	check(not ear.heard.is_empty(), "control: a fight on the player's screen is still heard")
	ear.heard.clear()
	cb.audible = false
	cb.bark(cb.combatants[0], "kill")
	check(ear.heard.is_empty(), "and the flag alone is what silences it")
	Sound._i = null
