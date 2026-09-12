# T91 — monster lairs (core/world_lairs.gd) and the three world-target quest
# kinds it plugs into (core/quest.gd): hunt_party / raid_settlement / clear_lair.
#   godot --headless --path . -s tests/test_world_lairs.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Quest = preload("res://core/quest.gd")
const RNG = preload("res://core/rng.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _init() -> void:
	check(WorldAI.is_monster("dragon"), "dragon reads as a monster faction (not in CIVILIZED)")
	var idx: int = load("res://core/scaler.gd").FACTIONS.find("dragon")
	check(idx >= 0, "dragon is a real Scaler faction now, not just a Lair label")

	# --- discovery radius / state ---------------------------------------
	var w := World.new()
	var l := w.add_lair(World.Lair.new("test-warren", Vector2(100, 0), "goblinoid"))
	check(not l.discovered and not l.looted, "a fresh lair starts hidden and unlooted")
	check(WorldLairs.nearby_undiscovered(w, Vector2(100, 0), 10.0) == l, "found dead-on, inside radius")
	check(WorldLairs.nearby_undiscovered(w, Vector2(500, 0), 10.0) == null, "nothing found far outside radius")
	l.discovered = true
	check(WorldLairs.nearby_undiscovered(w, Vector2(100, 0), 10.0) == null,
		"a discovered lair no longer shows up as undiscovered")

	# --- search: both outcomes are reachable, and only success flips discovered ---
	var l2 := World.Lair.new("test-warren-2", Vector2.ZERO, "goblinoid")
	var party := _party()
	var saw_ok := false
	var saw_fail := false
	for seed_v in range(40):
		l2.discovered = false
		var roll: Dictionary = WorldLairs.search(l2, party, RNG.new(seed_v + 1))
		check(not roll.is_empty(), "search() rolls for a party that has members")
		if roll.get("ok", false):
			saw_ok = true
			check(l2.discovered, "a passed check discovers the lair")
		else:
			saw_fail = true
			check(not l2.discovered, "a failed check leaves it hidden")
	check(saw_ok and saw_fail, "both pass and fail are reachable across seeds (got ok=%s fail=%s)" % [saw_ok, saw_fail])

	# --- loot: pays once, not twice ---------------------------------------
	var l3 := World.Lair.new("test-warren-3", Vector2.ZERO, "giant")
	var first: Dictionary = WorldLairs.loot(l3)
	check(l3.looted and int(first["gold"]) > 0, "looting an unlooted lair pays out and marks it spent")
	var second: Dictionary = WorldLairs.loot(l3)
	check(int(second["gold"]) == 0, "looting an already-looted lair pays nothing")

	# --- Quest.world_quest_for: picks a real target, skips the giver's own town ---
	var w2 := World.new()
	var home := w2.add_settlement(World.Settlement.new("home", Vector2.ZERO, "human", "city"))
	check(Quest.world_quest_for(w2, home, RNG.new(1)).is_empty(),
		"nothing to quest about when the world has no hostile targets yet")
	var enemy_town := w2.add_settlement(World.Settlement.new("ashfell", Vector2(900, 0), "orc", "city"))
	var band := w2.add_party(World.RoamingParty.new("raiders", Vector2(1, 1), "bandit"))
	var lair := w2.add_lair(World.Lair.new("warren", Vector2(2, 2), "goblinoid"))
	var kinds_seen := {}
	for seed_v in range(30):
		# xorshift32's first output correlates for tiny sequential seeds (1, 2, 3,
		# ...) — scatter them the way real callers' hash(...)-derived seeds already
		# do, or roll_die(3) comes back "1" every time and this never sees variety.
		var q: Dictionary = Quest.world_quest_for(w2, home, RNG.new(absi(hash(seed_v))))
		if not q.is_empty():
			kinds_seen[q["kind"]] = true
			check(q["required"] == 1 and q["progress"] == 0 and q["state"] == "offered",
				"a fresh world quest starts offered, 0/1")
	check(kinds_seen.size() == 3, "all three world-target kinds turn up across enough seeds (got %s)" % str(kinds_seen.keys()))

	var wq: Dictionary = Quest.world_quest_for(w2, home, RNG.new(2))
	while String(wq.get("kind", "")) != "clear_lair":
		wq = Quest.world_quest_for(w2, home, RNG.new(randi()))
	Quest.accept(party, wq)
	check(not Quest.can_turn_in(wq), "not turned in before the lair is actually cleared")
	Quest.record_lair_cleared(party, "not-this-one")
	check(not Quest.can_turn_in(wq), "clearing an unrelated lair does not complete it")
	Quest.record_lair_cleared(party, "warren")
	check(Quest.can_turn_in(wq), "clearing the actual target completes the quest")

	var gold_before := party.gold
	check(Quest.turn_in(party, wq), "a completed world quest turns in like any other")
	check(party.gold > gold_before, "turning it in pays the reward")

	# hunt_party / raid_settlement recorders, same shape
	var hp := {"id": "x", "kind": "hunt_party", "target_party_id": "raiders",
		"state": "active", "progress": 0, "required": 1, "title": "t", "reward": {}}
	party.quests.append(hp)
	Quest.record_party_defeated(party, "someone-else")
	check(hp["state"] == "active", "defeating an unrelated party leaves hunt_party alone")
	Quest.record_party_defeated(party, "raiders")
	check(hp["state"] == "complete", "defeating the named party completes hunt_party")

	var rs := {"id": "y", "kind": "raid_settlement", "target_settlement_id": "ashfell",
		"state": "active", "progress": 0, "required": 1, "title": "t", "reward": {}}
	party.quests.append(rs)
	Quest.record_settlement_raided(party, "ashfell")
	check(rs["state"] == "complete", "raiding the named settlement completes raid_settlement")

	print("test_world_lairs: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
