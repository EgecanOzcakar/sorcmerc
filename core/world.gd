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

# World-time is counted in MINUTES: everything built on top of this clock (O2's
# Day/HH:MM readout, O6's RESTOCK, O7's DAY := 1440.0) reads `elapsed` that way.
const SPEED := 40.0   # map units per world-minute, every party for now

# Real-time-with-pause. RefCounted, not a Node: O2's world scene drives it with
# one line in _process (`world.tick(delta)`), which is also how headless tests
# drive it with fixed deltas.
class WorldClock extends RefCounted:
	const SPEEDS := [1.0, 2.0, 4.0, 8.0]   # cycled by set_speed_index / the UI's speed button

	var elapsed := 0.0     # world-minutes since start, paused time excluded
	var speed := 1.0       # multiplies every tick's delta — movement/AI/economy all speed up with it
	var _paused := false

	# Returns the world-time actually advanced: 0.0 while paused.
	func tick(delta: float) -> float:
		if _paused or delta <= 0.0:
			return 0.0
		var advanced := delta * speed
		elapsed += advanced
		return advanced

	func pause() -> void:
		_paused = true

	func resume() -> void:
		_paused = false

	func is_paused() -> bool:
		return _paused

	# Snaps to the nearest entry in SPEEDS rather than accepting anything, so the
	# UI only ever cycles through the four sanctioned rates.
	func set_speed(mult: float) -> void:
		speed = mult if mult in SPEEDS else SPEEDS[0]

	# 1x -> 2x -> 4x -> 8x -> 1x, whatever the current speed's nearest slot is.
	func cycle_speed() -> void:
		var i: int = maxi(0, SPEEDS.find(speed))
		speed = SPEEDS[(i + 1) % SPEEDS.size()]

class Settlement extends RefCounted:
	var id: String
	var sname: String            # `name` is taken on Node; match combatant.gd's `cname`
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS
	var kind: String             # "city" | "town" — enough for O2 to pick a sprite
	# O6 economy state. last_visited/battle_at are world-clock stamps, < 0 = never;
	# pending_opinion_delta is the O7 hook: O6 adds to it (theft), O7 drains it.
	var last_visited := -1.0
	var battle_at := -1.0
	var pending_opinion_delta := 0.0

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
# O15 — the only terrain the map has: hand-placed blobs of water, `{position, radius}`
# each. A circle is the whole vocabulary; a lake is one, a river is a chain of
# overlapping ones (see scenes/world/world.gd's _demo_world). Plain dictionaries
# rather than a class because water_depth() below is the only thing that reads them.
var waters: Array[Dictionary] = []

func add_settlement(s: Settlement) -> Settlement:
	settlements.append(s)
	return s

func add_party(p: RoamingParty) -> RoamingParty:
	parties.append(p)
	return p

func add_water(position: Vector2, radius: float) -> Dictionary:
	var w := {"position": position, "radius": radius}
	waters.append(w)
	return w

# Signed distance to the nearest shoreline: negative in the water (how far in),
# positive on land (how far from the bank), INF with no water at all. One number
# is all the renderer needs to pick a tile and fade the edge.
# ponytail: linear scan over a handful of hand-placed blobs. If terrain ever grows
# to hundreds, index them; a per-cell cache in the renderer is the cheaper fix.
func water_depth(p: Vector2) -> float:
	var d := INF
	for w in waters:
		d = minf(d, p.distance_to(w["position"]) - float(w["radius"]))
	return d

func player() -> RoamingParty:
	for p in parties:
		if p.is_player:
			return p
	return null

func set_goal(p: RoamingParty, goal: Vector2) -> void:
	p.goal = goal

# One frame: advance the clock, then move everyone by the time it actually gave
# us — so pause gates movement in exactly one place. Returns the world-time
# advanced (0.0 while paused), which is what O7's per-day decay runs on.
func tick(delta: float) -> float:
	var dt := clock.tick(delta)
	if dt <= 0.0:
		return 0.0
	for p in parties:
		move_toward_goal(p, dt)
	return dt

# move_toward never overshoots, so arriving is just position == goal.
func move_toward_goal(p: RoamingParty, delta: float) -> void:
	if delta <= 0.0:
		return
	p.position = p.position.move_toward(p.goal, p.speed * delta)
