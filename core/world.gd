# O1 — the open-world model: a free 2D map (no hexes; the hex grid stays inside
# a single combat), settlements at arbitrary points, parties steering toward a
# goal, and a pausable real-time clock. Pure data + math, no rendering, no
# scenes — O2 draws it, O3 sets party goals, O4/O5 read positions.
#
#   var w = World.new()
#   w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "soldier", "city"))
#   var p = w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "soldier", true))
#   w.set_goal(p, Vector2(100, 0))    # what a map click eventually supplies
#   w.tick(delta)                     # call from _process: clock + movement; paused = nothing
#   w.clock.pause() / w.clock.resume() / w.clock.is_paused()
extends RefCounted

const Scaler = preload("res://core/scaler.gd")

const SPEED := 40.0   # map units per world-second, every party for now

# Real-time-with-pause. RefCounted, not a Node: O2's world scene drives it with
# one line in _process (`world.tick(delta)`), which is also how headless tests
# drive it with fixed deltas.
class WorldClock extends RefCounted:
	var elapsed := 0.0     # world-seconds since start, paused time excluded
	var _paused := false

	# Returns the world-time actually advanced: 0.0 while paused.
	func tick(delta: float) -> float:
		if _paused or delta <= 0.0:
			return 0.0
		elapsed += delta
		return delta

	func pause() -> void:
		_paused = true

	func resume() -> void:
		_paused = false

	func is_paused() -> bool:
		return _paused

class Settlement extends RefCounted:
	var id: String
	var sname: String            # `name` is taken on Node; match combatant.gd's `cname`
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS
	var kind: String             # "city" | "town" — enough for O2 to pick a sprite

	func _init(id_v: String, position_v: Vector2, faction_v: String,
			kind_v: String = "town", name_v: String = "") -> void:
		id = id_v
		position = position_v
		faction = faction_v
		kind = kind_v
		sname = name_v if name_v != "" else id_v.capitalize()

class RoamingParty extends RefCounted:
	var id: String
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS
	var is_player := false
	var goal: Vector2            # O3 drives this; O1 just steers toward it
	var speed := SPEED
	var ai := {}                 # O3's behavior + its state; see core/world_ai.gd

	func _init(id_v: String, position_v: Vector2, faction_v: String, is_player_v := false) -> void:
		id = id_v
		position = position_v
		faction = faction_v
		is_player = is_player_v
		goal = position_v

	func at_goal() -> bool:
		return position.is_equal_approx(goal)

var clock := WorldClock.new()
var settlements: Array[Settlement] = []
var parties: Array[RoamingParty] = []

func add_settlement(s: Settlement) -> Settlement:
	settlements.append(s)
	return s

func add_party(p: RoamingParty) -> RoamingParty:
	parties.append(p)
	return p

func player() -> RoamingParty:
	for p in parties:
		if p.is_player:
			return p
	return null

func set_goal(p: RoamingParty, goal: Vector2) -> void:
	p.goal = goal

# One frame: advance the clock, then move everyone by the time it actually gave
# us — so pause gates movement in exactly one place.
func tick(delta: float) -> void:
	var dt := clock.tick(delta)
	if dt <= 0.0:
		return
	for p in parties:
		move_toward_goal(p, dt)

# move_toward never overshoots, so arriving is just position == goal.
func move_toward_goal(p: RoamingParty, delta: float) -> void:
	if delta <= 0.0:
		return
	p.position = p.position.move_toward(p.goal, p.speed * delta)
