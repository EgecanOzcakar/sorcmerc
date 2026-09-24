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
const Ach = preload("res://core/achievements.gd")
const WorldPath = preload("res://core/world_path.gd")   # #95

# World-time is counted in MINUTES: everything built on top of this clock (O2's
# Day/HH:MM readout, O6's RESTOCK, O7's DAY := 1440.0) reads `elapsed` that way.
const SPEED := 40.0   # map units per world-minute, every party for now

# #164: an NPC band's SPEED multiplier by faction — beasts and dragons outrun a
# soldier company, undead and constructs shamble. The player's own speed does
# not read this table at all; core/travel.gd's slowest-walker rule owns that.
const FACTION_SPEED := {
	"beast": 1.3, "gnoll": 1.2, "kobold": 1.0, "goblinoid": 1.0, "bandit": 1.0,
	"human": 1.0, "elf": 1.0, "dwarf": 0.9, "orc": 1.0, "undead": 0.6,
	"giant": 0.8, "construct": 0.7, "monstrosity": 1.1, "dragon": 1.5,
	"elemental": 1.2, "fey": 1.2, "cultist": 0.9, "soldier": 1.0,
}

# Real-time-with-pause. RefCounted, not a Node: O2's world scene drives it with
# one line in _process (`world.tick(delta)`), which is also how headless tests
# drive it with fixed deltas.
class WorldClock extends RefCounted:
	const SPEEDS := [1.0, 2.0, 4.0, 8.0]   # cycled by set_speed_index / the UI's speed button

	# #85: a new world starts in the morning, not at midnight — the first thing
	# a player sees should not be the night's shrunken sight. `elapsed` still
	# counts from zero; the hour on the clock face is elapsed + START_HOUR.
	const START_HOUR := 8
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

	# #85: how bright the world is right now, 0 (deep night) to 1 (full day),
	# from the hour of the day. Dawn 5-7, dusk 18-20, a night floor of 0.22 so
	# the map is still readable. Pure: the map, the dioramas and anything else
	# that wants to look like the time of day read this one number.
	const NIGHT_FLOOR := 0.22
	func hour_of_day() -> float:
		return fmod(elapsed / 60.0 + START_HOUR, 24.0)

	func daylight() -> float:
		var h := hour_of_day()
		var k := 0.0
		if h >= 5.0 and h < 7.0:
			k = (h - 5.0) / 2.0
		elif h >= 7.0 and h < 18.0:
			k = 1.0
		elif h >= 18.0 and h < 20.0:
			k = 1.0 - (h - 18.0) / 2.0
		k = smoothstep(0.0, 1.0, k)
		return lerpf(NIGHT_FLOOR, 1.0, k)

	# Dark enough that the mechanics call it night: sight closes in, a band can
	# jump the party unseen, and a fight begun now is fought by torchlight.
	func is_night() -> bool:
		return daylight() < 0.5

	# The colour the light has: warm at the edges of the day, blue at night.
	func daylight_tint() -> Color:
		var d := daylight()
		var night := Color(0.55, 0.62, 0.95)
		var gold := Color(1.0, 0.82, 0.62)
		var h := hour_of_day()
		var edge: float = 1.0 - minf(1.0, absf(h - 6.0) / 1.5) if h < 12.0 else 1.0 - minf(1.0, absf(h - 19.0) / 1.5)
		return night.lerp(Color.WHITE, (d - NIGHT_FLOOR) / (1.0 - NIGHT_FLOOR)).lerp(gold, edge * 0.6) * d

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
	var stolen_at := -1.0        # the last theft attempt here; the stall is watched for a while after
	var pending_opinion_delta := 0.0
	# Raids: the lair whose raid stands on this town, "" when none. The market
	# reads it (halved shelf), the board reads it (that lair's job pays more),
	# the road reads it (refugees). Lifted when that lair is spent.
	var raided_by := ""
	var raided_at := -1.0

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
	# D1: how many rooms of the interior the party fought through on its last
	# (or current) delve (core/site.gd). A record, not a resume point: since the
	# design audit (§3.3, 2026-09-24) every entry starts at the mouth and the
	# rooms fill in again behind a party that walks out.
	var depth_cleared := 0
	# Which treasure rooms were emptied ("floor|room id", core/site.gd's
	# _cache_key) since something last moved in. The rooms regrow on re-entry;
	# the coin already carried out does not. Cleared by WorldLairs.respawn.
	var caches_taken: Array = []
	# D1: world-clock stamp of the first time the party went in, < 0 = never.
	# Kicking the door starts a clock: see core/world_lairs.gd's WINDOW — a
	# disturbed lair does not sit there waiting forever for you to come back.
	var entered_at := -1.0
	# How it ended if it ended without the party: "cleared" (somebody else got
	# there) or "abandoned" (they packed up and left). "" while it is still live.
	var resolved_as := ""
	# World-clock stamp of the moment it was spent, < 0 = still live. A hole in
	# the ground does not stay empty: core/world_lairs.gd's RESPAWN lets
	# something move back into it, and this is the clock that runs.
	var cleared_at := -1.0
	# Raids (core/raids.gd): the clock a lair left alone runs against the
	# nearest town. raid_at is what it counts from — world start, the last
	# set-out, or the last raid turned — and is never < 0; raids counts the ones
	# that LANDED (the second seeds a child); raid_band names the band out
	# raiding right now; spawned_from names a child's parent, and a child never
	# spawns one of its own.
	var raid_at := 0.0
	var raids := 0
	var raid_band := ""
	var spawned_from := ""

	func _init(id_v: String, position_v: Vector2, faction_v: String, name_v: String = "") -> void:
		id = id_v
		position = position_v
		faction = faction_v
		sname = name_v if name_v != "" else id_v.capitalize()

# A place on the map that is not a fight: ruins, a shrine, standing stones…
# (core/landmarks.gd owns the kinds and what happens there). Found = drawn
# and visitable; spent = answered, once, for good.
class Landmark extends RefCounted:
	var id: String
	var kind: String            # one of Landmarks.KINDS
	var sname: String
	var position: Vector2
	var found := false
	var spent := false

	func _init(_id: String, _kind: String, _position: Vector2, _sname := "") -> void:
		id = _id
		kind = _kind
		position = _position
		sname = _sname if _sname != "" else load("res://core/landmarks.gd").name_for(_id, _kind)   # load: landmarks.gd preloads this file

class RoamingParty extends RefCounted:
	var id: String
	var position: Vector2
	var faction: String          # one of Scaler.FACTIONS
	var is_player := false
	var goal: Vector2            # O3 drives this; O1 just steers toward it
	# #95: the waypoints still to come after `goal`, for a party the PLAYER
	# sent somewhere across water (set_goal routes it; move_toward_goal walks
	# it). Empty for every band the AI steers — core/world_ai.gd keeps its own.
	var route: Array[Vector2] = []
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
		if not is_player_v:
			speed = SPEED * FACTION_SPEED.get(faction_v, 1.0)

	# {} if this party has no troop roster at all.
	func highest_troop() -> Dictionary:
		var best := {}
		for t in troops:
			if best.is_empty() or int(t.get("level", 0)) > int(best.get("level", 0)):
				best = t
		return best

	func at_goal() -> bool:
		return position.is_equal_approx(goal) and route.is_empty()

var clock := WorldClock.new()
var settlements: Array[Settlement] = []
var parties: Array[RoamingParty] = []
var lairs: Array[Lair] = []
var landmarks: Array[Landmark] = []
# #142: monster bands put down and due back — {id, faction, position, troops,
# at}; core/world_ai.gd's fell()/respawn() are the only writers.
var fallen: Array[Dictionary] = []
# #163: when WorldBands.refill last put a band on the map (world-minutes).
var bands_refilled_at := 0.0
# O15 — the only terrain the map has: hand-placed blobs of water, `{position, radius}`
# each. A circle is the whole vocabulary; a lake is one, a river is a chain of
# overlapping ones (see scenes/world/world.gd's _demo_world). Plain dictionaries
# rather than a class because water_depth() below is the only thing that reads them.
# T-water: a blob is also a wall — is_water()/set_goal()/move_toward_goal() keep
# parties out of it, so this is terrain, not decoration.
var waters: Array[Dictionary] = []
# O-biome — the map's second terrain layer, after the water. A biome is a
# `{position, radius, kind}` disc, the same vocabulary `waters` already uses,
# and biome_at() below is the only reader: what KIND of country a point is.
#
# It deliberately does NOT say how dangerous the country is. core/regions.gd's
# rings own that, and the two axes are orthogonal on purpose — a marsh in the
# heartland and a marsh in the deeps are the same kind of place at two
# different levels. Collapsing them would make every measured number in
# regions.gd stop meaning what it says.
#
# THREE KINDS, and the set is argued rather than assumed. A biome only earns
# its place if it changes what a fight there fields, and a roster is filtered
# by ONE habitat with `any` riding along free (core/scaler.gd's
# _in_budget_and_habitat tests `habitat in [need, "any"]`), so each kind names
# exactly one habitat out of data/bestiary.json's vocabulary:
#
#   downs  -> ""        the default fill; no filter, all 240 faction-tagged entries
#   woods  -> "forest"  105 admitted, 76 of them distinctively forest
#   marsh  -> "water"    51 admitted, 22 distinctively water — and those 22 are
#                        unreachable today, which is what makes this the kind
#                        that pays for itself
#
# `cave` did NOT earn a kind (measured 2026-09-22): it admits 40, but 29 are
# the generic `any` humanoids and the 11 that are left are goblinoid, kobold
# and cave-monstrosity — which is the fight the goblin-camp board already
# fields. Like `dungeon`, it is an INTERIOR habitat, and its home is a lair's
# rooms (core/site.gd), not open country.
#
# The habitat mapping itself is not here and not wired yet — this slice is the
# terrain layer and what draws it. See docs/expansion-plan.md's biome note.
const BIOMES := ["downs", "woods", "marsh"]
const DEFAULT_BIOME := "downs"
var biomes: Array[Dictionary] = []
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
# A watchtower's "keep watch": every band draws as explored while this holds
# (world-minutes; < 0 = nothing marked). Runtime only — it lapses with the day.
var marked_until := -1.0
var marked_at := Vector2.ZERO   # where the watch was kept — band_seen()'s two-radii center

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
	# T19: how much of any one map this machine has ever put behind it. A
	# high-water mark, not a sum — a new world does not wipe the old score, and
	# walking the same map twice does not earn it twice.
	Ach.record("explored", explored.size())
	_reindex()

# The "remembered" tier: was ever within VISION_RADIUS of some point on the
# explored trail, or close enough to a settlement to see its beacon.
func is_explored(pos: Vector2) -> bool:
	if near_settlement(pos):
		return true
	return _near_waypoint(pos, VISION_RADIUS)

# A band is drawn if the fog is off it, or while a watchtower's watch holds
# and it is within two vision radii of the tower (core/landmarks.gd "marked").
func band_seen(pos: Vector2) -> bool:
	return is_explored(pos) or (marked_until > clock.elapsed and pos.distance_to(marked_at) <= 2.0 * VISION_RADIUS)

# The "currently visible" tier: within sight of the player's position RIGHT
# NOW, not just remembered from having passed through once.
func is_visible_now(pos: Vector2, from: Vector2) -> bool:
	return pos.distance_to(from) <= sight_radius()

# #85: how far the party sees right now. Full VISION_RADIUS by day, NIGHT_SIGHT
# of it in the dark; the ground shader's circle and every "is it in view" test
# read this, so a band walks out of the night at the same distance the fog
# opens. What is REMEMBERED (is_explored) stays at the day radius.
const NIGHT_SIGHT := 0.45
func sight_radius() -> float:
	var k := (clock.daylight() - WorldClock.NIGHT_FLOOR) / (1.0 - WorldClock.NIGHT_FLOOR)   # 0 at deep night
	return VISION_RADIUS * lerpf(NIGHT_SIGHT, 1.0, k)

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

func add_landmark(l: Landmark) -> Landmark:
	landmarks.append(l)
	return l

func landmark(id: String):
	for l in landmarks:
		if l.id == id:
			return l
	return null

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

func add_biome(position: Vector2, radius: float, kind: String) -> Dictionary:
	var b := {"position": position, "radius": radius, "kind": kind}
	biomes.append(b)
	return b

# What kind of country this point is, DEFAULT_BIOME when no disc claims it —
# which is most of any map, and costs one pass over a handful of discs.
#
# Overlaps are resolved by the SMALLEST RADIUS among the discs that actually
# contain the point: most specific wins. A big wood with a small marsh painted
# inside it reads as marsh across the whole marsh and as wood everywhere else,
# which is the point of being able to paint one inside the other.
#
# The obvious-looking alternative — smallest `distance / radius`, whoever's
# middle the point is relatively nearest — was tried first and is wrong, which
# tests/test_world_biomes.gd caught. It shrinks the inner disc instead of
# honouring it: a 60-radius marsh inside a 400-radius wood only wins where
# |x-100|/60 < |x|/400, which is about 30 units of the 120 it should own. The
# inner disc has to be nearly concentric with the outer one to keep its ground,
# so "paint a small one inside a big one" quietly does not work.
#
# Ties on radius fall to the nearer centre, so two discs of the same size share
# the ground between them on the midline rather than on list order.
#
# ponytail: a linear scan, exactly as water_depth() is and for the same reason —
# a handful of hand-placed blobs. Both are called per ground cell when the
# renderer rebuilds its mask; if either list ever grows past a handful, index
# them together rather than one at a time.
func biome_at(pos: Vector2) -> String:
	var best := DEFAULT_BIOME
	var best_r := INF
	var best_d := INF
	for b in biomes:
		var r := float(b["radius"])
		var d: float = pos.distance_to(b["position"])
		if d >= r:
			continue                      # outside: a disc never reaches past its own edge
		if r < best_r or (r == best_r and d < best_d):
			best_r = r
			best_d = d
			best = String(b["kind"])
	return best

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
	# #95: around the water, not into it. WorldPath (O16, built for the bands
	# nobody steers) already knows the way round every blob; the player's click
	# now takes the same route, one waypoint at a time. [] when the straight
	# march is dry, or when there is no way round — then the old rule holds:
	# march at it, stop at the bank.
	var way: Array[Vector2] = WorldPath.route(self, p.position, WorldPath.nearest_dry(self, goal))
	if way.is_empty():
		p.route = []
		p.goal = _land_goal(p.position, goal)
		return
	p.goal = way[0]
	p.route = way.slice(1)

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
		p.route = []
		return
	var remaining := p.speed * delta
	while remaining > 0.0:
		var hop := minf(remaining, WATER_STEP)
		remaining -= hop
		var before := p.position
		_hop(p, hop)
		if p.position.is_equal_approx(p.goal) and not p.route.is_empty():
			p.goal = p.route[0]          # #95: the next leg of a routed walk
			p.route.remove_at(0)
			continue
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
