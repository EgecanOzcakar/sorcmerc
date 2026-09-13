# O1 — the open-world model: a free 2D map (no hexes; the hex grid stays inside
# a single combat), settlements at arbitrary points, parties steering toward a
# goal, and a pausable real-time clock. Pure data + math, no rendering, no
# scenes — O2 draws it, O3 sets party goals, O4/O5 read positions.
#
#   var w = World.new()
#   w.add_settlement(World.Settlement.new("riverhold", Vector2(0, 0), "soldier", "city"))
#   var p = w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "soldier", true))
#   w.set_goal(p, Vector2(100, 0))    # what a map click eventually supplies
#   w.is_water(Vector2(100, 0))       # terrain: water is impassable, so set_goal()
#                                     # snaps a wet goal to the bank and nobody
#                                     # steps off land into a blob
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
	var kind: String             # "city" | "town" | "camp" — enough for O2 to pick a sprite
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

# T91 — a hostile monster lair: hidden until a Survival check finds it (see
# core/world_lairs.gd), then attackable like a hostile settlement's guard for
# its own stash of loot. Not a Settlement: it has no economy, no visit/market,
# and can't be traded with or turned civilized — winning just loots it once.
# "camp" is deliberately not this class's name — Settlement.kind already uses
# "camp" for its smallest size tier, and the two are unrelated concepts.
class Lair extends RefCounted:
	var id: String
	var sname: String
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS — same field driving encounter_spec
	var discovered := false      # found by a Survival check yet? undiscovered lairs don't draw
	var looted := false          # cleared once — stays on the map, spent, not removed

	func _init(id_v: String, position_v: Vector2, faction_v: String, name_v: String = "") -> void:
		id = id_v
		position = position_v
		faction = faction_v
		sname = name_v if name_v != "" else id_v.capitalize()

class RoamingParty extends RefCounted:
	var id: String
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS
	var is_player := false
	var goal: Vector2            # O3 drives this; O1 just steers toward it
	var speed := SPEED
	var ai := {}                 # O3's behavior + its state; see core/world_ai.gd
	# T-party3d: who's actually in this band, for the overworld figure (Party3D
	# picks the highest-leveled one's model) -- flavour only, no stat effect;
	# combat rosters still come from Scaler.roster_for(faction), unrelated.
	# {"role": "heavy" | "light" | "spellcaster", "level": int} per troop.
	# Empty for the player (their own class figure already exists) and for any
	# NPC faction nobody's bothered seeding a roster for yet -- both read as
	# "no model," same fallback contract as everything else this session.
	var troops: Array[Dictionary] = []

	func _init(id_v: String, position_v: Vector2, faction_v: String, is_player_v := false) -> void:
		id = id_v
		position = position_v
		faction = faction_v
		is_player = is_player_v
		goal = position_v

	# {} if this party has no troop roster at all.
	func highest_troop() -> Dictionary:
		var best := {}
		for t in troops:
			if best.is_empty() or int(t.get("level", 0)) > int(best.get("level", 0)):
				best = t
		return best

	func at_goal() -> bool:
		return position.is_equal_approx(goal)

var clock := WorldClock.new()
var settlements: Array[Settlement] = []
var parties: Array[RoamingParty] = []
var lairs: Array[Lair] = []
# O15 — the only terrain the map has: hand-placed blobs of water, `{position, radius}`
# each. A circle is the whole vocabulary; a lake is one, a river is a chain of
# overlapping ones (see scenes/world/world.gd's _demo_world). Plain dictionaries
# rather than a class because water_depth() below is the only thing that reads them.
# T-water: a blob is also a wall — is_water()/set_goal()/move_toward_goal() keep
# parties out of it, so this is terrain, not decoration.
var waters: Array[Dictionary] = []
# T-water: which builder made this map, and the seed it used (0 for the two
# hand-placed ones) — saved and restored, so a resumed world can still say what
# it is instead of looking like a hand-placed map with the furniture moved.
# "small" is the default because that is what scenes/world/world.gd falls back
# to when nobody asked for anything else.
var origin := {"kind": "small", "seed": 0}

# Fog of war, three tiers: currently visible (near the player right now),
# explored (a waypoint list of everywhere that was ever true, remembered
# forever — not a per-cell grid), and never explored. reveal() only
# remembers a new waypoint every EXPLORE_STEP units so this list stays
# small over a long walk instead of growing every frame.
# T9x: VISION_RADIUS tripled (90 -> 260) — the original size read as "the
# map failed to load" on the large world, where the nearest settlement can
# be several hundred units from the start: a tiny lit circle in an
# otherwise solid-black multi-thousand-unit map has nothing to walk
# toward. EXPLORE_STEP grows with it so waypoints still overlap along a
# path with no gaps (must stay under 2x the radius).
const VISION_RADIUS := 260.0
const EXPLORE_STEP := 150.0
# T9x: settlements are landmarks, not surprises — a small always-on patch
# around each one (regardless of exploration) so there's something to
# aim for on a map that's otherwise still fogged. Lairs and roaming
# parties stay fog-gated; those are meant to be found, not signposted.
const SETTLEMENT_BEACON_RADIUS := 55.0
var explored: Array[Vector2] = []

# T9y: the waypoint trail, indexed. `explored` stays the flat, saved list —
# it is what world_save.gd round-trips and what a reader expects to find —
# but every query against it used to be a linear scan over the whole walk,
# and scenes/world/world.gd calls is_explored() once per ground cell per
# frame (hundreds of cells on screen, up to MAX_CELLS zoomed out). That is
# cells x waypoints distance checks every frame, and tripling VISION_RADIUS
# (32c4c88) put more of the map on screen to be checked.
#
# The index is a plain hash grid keyed by BUCKET-sized cells. Both queries
# have the same shape — "is there a waypoint within R of this point" — and
# both radii (VISION_RADIUS for is_explored, the smaller EXPLORE_STEP for
# reveal's dedupe) are <= BUCKET, so the answer can only live in the 3x3
# block of cells around the point. A long walk grows the number of buckets,
# not the work per query.
const BUCKET := VISION_RADIUS      # one cell per vision radius: 3x3 always covers a query
var _buckets := {}                 # Vector2i cell -> Array[Vector2] of waypoints in it
var _indexed := 0                  # how many entries of `explored` are in _buckets

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / BUCKET)), int(floor(pos.y / BUCKET)))

# `explored` is public and writable — world_save.gd appends to it directly on
# load, and a test may hand-build a trail — so the index cannot assume reveal()
# is the only writer. Rebuilding on a size mismatch keeps it honest without
# making the list private: append-only is the one shape it ever has.
func _reindex() -> void:
	if _indexed == explored.size():
		return
	if _indexed > explored.size():        # the list shrank or was replaced wholesale
		_buckets.clear()
		_indexed = 0
	while _indexed < explored.size():
		var e: Vector2 = explored[_indexed]
		var cell := _cell_of(e)
		if not _buckets.has(cell):
			_buckets[cell] = []
		_buckets[cell].append(e)
		_indexed += 1

# True when some remembered waypoint sits within `radius` of `pos`. Only the
# 3x3 block of cells around `pos` can hold one, because radius <= BUCKET.
func _near_waypoint(pos: Vector2, radius: float) -> bool:
	_reindex()
	var c := _cell_of(pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell := Vector2i(c.x + dx, c.y + dy)
			if not _buckets.has(cell):
				continue
			for e in _buckets[cell]:
				if e.distance_to(pos) <= radius:
					return true
	return false

func reveal(pos: Vector2) -> void:
	# `<` where _near_waypoint tests `<=`: a waypoint exactly EXPLORE_STEP away
	# is far enough to earn a new one, which is the original rule.
	if _near_waypoint(pos, EXPLORE_STEP - 0.0001):
		return
	explored.append(pos)
	_reindex()

# The "remembered" tier: was ever within VISION_RADIUS of some point on the
# explored trail, or close enough to a settlement to see its beacon.
func is_explored(pos: Vector2) -> bool:
	if near_settlement(pos):
		return true
	return _near_waypoint(pos, VISION_RADIUS)

# The "currently visible" tier: within sight of the player's position RIGHT
# NOW, not just remembered from having passed through once.
func is_visible_now(pos: Vector2, from: Vector2) -> bool:
	return pos.distance_to(from) <= VISION_RADIUS

func near_settlement(pos: Vector2) -> bool:
	for s in settlements:
		if pos.distance_to(s.position) <= SETTLEMENT_BEACON_RADIUS:
			return true
	return false

func add_settlement(s: Settlement) -> Settlement:
	settlements.append(s)
	return s

func add_lair(l: Lair) -> Lair:
	lairs.append(l)
	return l

func add_party(p: RoamingParty) -> RoamingParty:
	parties.append(p)
	return p

# How finely a line is sampled against the water — used both for walking a wet
# goal back to shore and for splitting a long move into hops. Well under the
# 40-unit radius of the river blobs the hand-placed maps stamp, so no single
# step can straddle a river and miss it.
const WATER_STEP := 12.0

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

# T-water: inside a blob. The bank itself (depth exactly 0) counts as land, so a
# party snapped to the shoreline is standing somewhere it is allowed to stand.
func is_water(pos: Vector2) -> bool:
	return water_depth(pos) < 0.0

func player() -> RoamingParty:
	for p in parties:
		if p.is_player:
			return p
	return null

# A goal inside water is snapped back to the bank — the last dry point on the
# straight line from the party toward it, which is where the party would have
# been stopped anyway. Clicking the middle of a lake therefore means "walk to
# that lake", not "walk nowhere"; no pathfinder is involved and none is wanted.
func set_goal(p: RoamingParty, goal: Vector2) -> void:
	p.goal = _land_goal(p.position, goal)

# `goal` when it is dry; otherwise the dry point closest to it on the segment
# back toward `from`. `goal` unchanged when the whole segment is wet — which can
# only happen when `from` is itself in water, and a swimming party is allowed to
# aim anywhere (see move_toward_goal).
func _land_goal(from: Vector2, goal: Vector2) -> Vector2:
	if not is_water(goal):
		return goal
	var back := from - goal
	var span := back.length()
	if span <= 0.0:
		return goal
	var dir := back / span
	var walked := WATER_STEP
	while walked < span:
		var candidate := goal + dir * walked
		if not is_water(candidate):
			return candidate
		walked += WATER_STEP
	return from if not is_water(from) else goal

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

# move_toward never overshoots, so arriving is just position == goal. Long
# travel (a fat delta, or 8x speed) is walked in WATER_STEP hops instead of one
# jump, so nobody tunnels clean across a river between two frames.
func move_toward_goal(p: RoamingParty, delta: float) -> void:
	if delta <= 0.0:
		return
	if waters.is_empty():        # no terrain to respect: the O1 behavior, undisturbed
		p.position = p.position.move_toward(p.goal, p.speed * delta)
		return
	var remaining := p.speed * delta
	while remaining > 0.0:
		var hop := minf(remaining, WATER_STEP)
		remaining -= hop
		var before := p.position
		_hop(p, hop)
		if p.position.is_equal_approx(before):
			return               # arrived, or stopped against a bank

# One bounded step toward the goal. Only a land->water step is refused; a party
# that is ALREADY in water (an old save from before this rule, a hand-placed
# spawn inside a blob, a blob added on top of it later) may move anywhere at
# all — a party wedged in a lake forever is a far worse bug than one seen
# swimming out of it.
# Blocked on land, the step gets one cheap retry as its x-only and y-only
# halves, taking whichever dry half ends up closer to the goal: a party skimming
# a shoreline then follows the bank instead of gluing itself to it.
func _hop(p: RoamingParty, dist: float) -> void:
	var next := p.position.move_toward(p.goal, dist)
	if is_water(p.position) or not is_water(next):
		p.position = next
		return
	var step := next - p.position
	var best := p.position
	var best_d := p.position.distance_to(p.goal)
	for slide in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		var candidate: Vector2 = p.position + slide
		var d := candidate.distance_to(p.goal)
		if d < best_d and not is_water(candidate):
			best = candidate
			best_d = d
	p.position = best
