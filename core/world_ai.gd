# O3 — movement goals for non-player roaming parties. Pure goal-setting: it
# never moves anything itself, it only writes `party.goal` and lets O1's
# `World.tick()` do the steering.
#
#   WorldAI.patrol(p, [Vector2(0,0), Vector2(100,0), Vector2(100,100)])
#   WorldAI.wander(p, home_settlement, 80.0, 1234)   # seeded
#   WorldAI.hunt(p)
#   WorldAI.update(world)    # once per frame, after/before world.tick(delta)
#
# Behavior state rides on the party in one additive `ai` Dictionary (see
# `_state()`), not in a module-level table: a party is the only thing that
# owns its own behavior, and a table keyed by id would need cleanup the
# moment O5 starts removing dead parties.
extends RefCounted

const Scaler = preload("res://core/scaler.gd")
const RNG = preload("res://core/rng.gd")

# The split: `soldier` is the one faction in Scaler.FACTIONS that reads as a
# settled, civilized power (it's what O1's settlements are garrisoned by);
# every other entry is a monster/bandit faction. Per the plan doc, conflict is
# monsters vs. settlements/player — never civilized vs. civilized — so one
# civilized bucket is all the hostility rule needs.
const CIVILIZED := ["soldier"]

static func is_monster(faction: String) -> bool:
	return not CIVILIZED.has(faction)

# Monsters are hostile to everything civilized (the player included, whatever
# faction they fly); civilized parties are hostile to nobody yet — O7's faction
# opinion is what will eventually make them hostile back.
static func is_hostile(party, other) -> bool:
	if party.is_player or not is_monster(party.faction):
		return false
	if "is_player" in other and other.is_player:
		return true
	return not is_monster(other.faction)

# --- behavior assignment ---------------------------------------------

static func patrol(party, waypoints: Array) -> void:
	if waypoints.is_empty():
		return
	party.ai = {"behavior": "patrol", "waypoints": waypoints, "index": 0}
	party.goal = waypoints[0]

static func wander(party, home, radius := 80.0, seed_value := 0) -> void:
	party.ai = {
		"behavior": "wander",
		"home": home.position if "position" in home else home,
		"radius": radius,
		"rng": RNG.new(seed_value),
	}

static func hunt(party) -> void:
	party.ai = {"behavior": "hunt"}

# --- driver ----------------------------------------------------------

# One pass over the world: refresh every non-player party's goal. `_delta` is
# unused (behaviors are event-driven off `at_goal()`), it's there so O2 can
# call this straight from `_process(delta)` alongside `world.tick(delta)`.
static func update(world, _delta := 0.0) -> void:
	for p in world.parties:
		if p.is_player:
			continue
		match String(_state(p).get("behavior", "")):
			"patrol": _patrol_step(p)
			"wander": _wander_step(p)
			"hunt": _hunt_step(world, p)

static func _state(party) -> Dictionary:
	return party.ai if "ai" in party else {}

static func _patrol_step(party) -> void:
	if not party.at_goal():
		return
	var s: Dictionary = party.ai
	var wps: Array = s["waypoints"]
	s["index"] = (int(s["index"]) + 1) % wps.size()
	party.goal = wps[int(s["index"])]

static func _wander_step(party) -> void:
	if not party.at_goal():
		return
	var s: Dictionary = party.ai
	var rng = s["rng"]
	var angle := deg_to_rad(float(rng.roll_die(360)))
	var dist := float(s["radius"]) * float(rng.roll_die(100)) / 100.0
	party.goal = Vector2(s["home"]) + Vector2(cos(angle), sin(angle)) * dist

# Chases the nearest hostile thing's *current* position, re-read every update —
# so the goal tracks a target that is itself moving.
# ponytail: linear scan over 3-8 parties/settlements; index it if the roster grows.
static func _hunt_step(world, party) -> void:
	var best = null
	var best_d := INF
	for other in world.parties:
		if other == party or not is_hostile(party, other):
			continue
		var d: float = party.position.distance_squared_to(other.position)
		if d < best_d:
			best_d = d
			best = other.position
	for s in world.settlements:
		if not is_hostile(party, s):
			continue
		var d: float = party.position.distance_squared_to(s.position)
		if d < best_d:
			best_d = d
			best = s.position
	if best != null:
		party.goal = best
