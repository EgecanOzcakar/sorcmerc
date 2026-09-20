# O5 — off-screen battle resolution: when two NON-player parties meet, the fight
# happens instantly, headless, with no scene and no pause (O4 owns the player's
# fights; this never touches a pair the player is in). The loser is removed from
# the world, the winner marches on.
#
#   WorldBattle.check(world, ENCOUNTER_RADIUS, encounter_spec)   # once per frame
#
# It lives in core/ rather than in scenes/world/world.gd because none of it is
# rendering: it is the same seeded `AI.take_turn` autoplay loop tests/
# test_scaler.gd's sweeps run, so it wants to be testable without a Control.
# The one thing it cannot own is the faction -> roster mapping, which is O4's
# `encounter_spec()` in the map scene — that comes in as a Callable instead of
# being re-derived here.
extends RefCounted

const Encounter = preload("res://core/encounter.gd")
const AI = preload("res://core/ai.gd")
const WorldAI = preload("res://core/world_ai.gd")

const MAX_TURNS := 5000     # the same runaway guard test_scaler.gd's sweeps use

# One pass over every non-player pair; each hostile pair inside `radius` fights
# to a finish and loses a party. Returns one {winner, loser, outcome} per fight.
# ponytail: O(n^2) over 3-8 parties once a frame, per O1's own "no index yet" note.
static func check(world, radius: float, spec_for: Callable) -> Array:
	var results: Array = []
	var gone := {}
	var ps: Array = world.parties.duplicate()
	for i in ps.size():
		var a = ps[i]
		if a.is_player or gone.has(a):
			continue
		for j in range(i + 1, ps.size()):
			var b = ps[j]
			# The player's encounters are O4's job — never resolve one here.
			if b.is_player or gone.has(b):
				continue
			if a.position.distance_to(b.position) > radius:
				continue
			# Hostility is one-directional (world_ai.gd): either side wanting the
			# other dead is a fight.
			if not (WorldAI.is_hostile(a, b) or WorldAI.is_hostile(b, a)):
				continue
			var r := resolve(world, a, b, spec_for)
			gone[r["loser"]] = true
			results.append(r)
			if gone.has(a):
				break
	return results

# `a` fights as the "party" team (Encounter.build only builds the foe side), so
# a Victory is a's win. Deterministic: the seed is the pair's ids, so the same
# two bands meeting on the same map always resolve the same way.
static func resolve(world, a, b, spec_for: Callable) -> Dictionary:
	var spec_a: Dictionary = spec_for.call(a)
	var spec_b: Dictionary = spec_for.call(b).duplicate(true)
	spec_b["seed"] = maxi(1, absi(hash("%s|%s" % [a.id, b.id])))
	var side_a: Array = _spawn_side(spec_a)
	# Both sides fight on the attacker's terrain; one board, one fight.
	var cb = Encounter.build(spec_b, side_a, Encounter.board_for(String(spec_a.get("theme", ""))))
	# T19: neither of these bands is the player's. Nothing in here counts.
	cb.tracked = false
	var guard := 0
	while not cb.is_over() and guard < MAX_TURNS:
		var actor = cb.current()
		cb.begin_turn()
		AI.take_turn(cb, actor)
		cb.end_turn()
		guard += 1
	var outcome := cb.outcome()
	var a_wins := outcome == "Victory" if outcome != "ongoing" else _ahead(cb)
	var loser = b if a_wins else a
	world.parties.erase(loser)
	return {"winner": a if a_wins else b, "loser": loser, "outcome": outcome}

# A fight that hit combat.gd's MAX_ROUNDS is decided on who is left standing,
# then on remaining HP — never on a coin flip, so the result stays seed-stable.
static func _ahead(cb) -> bool:
	var up := {"party": 0, "foe": 0}
	var hp := {"party": 0, "foe": 0}
	for c in cb.combatants:
		if c.conscious():
			up[c.team] += 1
			hp[c.team] += c.hp
	if up["party"] != up["foe"]:
		return up["party"] > up["foe"]
	return hp["party"] >= hp["foe"]

# A roster spec as "party"-team combatants. Encounter.build only spawns the foe
# side, and it places that side away from whatever it is handed — so putting one
# side on the board's first free hexes is enough to keep the two apart.
static func _spawn_side(spec: Dictionary) -> Array:
	var spots: Array = Encounter._foe_spots(
		Encounter.board_for(String(spec.get("theme", ""))), [])
	var out: Array = []
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else Encounter.PARTY_STARTS[0]
			var c = Encounter.spawn(e["id"], mult, "party", pos,
				n + 1 if count > 1 else 0, e.get("features", []))
			if c != null:
				out.append(c)
			i += 1
	return out
