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
#
# T-path: a behavior no longer writes `party.goal` itself. It names a
# DESTINATION and `_steer()` turns that into the next goal, routing round the
# water (core/world_path.gd) when the straight march would wade. The two are
# the same point whenever the line is dry, which is every point of a map with
# no water in it — so a band on dry land behaves exactly as it did before there
# was a pathfinder. What changes is the band whose prey is across the river:
# it used to walk to the bank and stand there forever, and a patrol whose next
# waypoint was over the water never arrived, so it never advanced to the one
# after it either.
#
# Whatever the behavior, a band too weak for something that would fight it
# runs from it first (_flee_step; core/world_flee.gd owns who is too weak).
# Only a truce's walk-away outranks that, and it is walking away already.
extends RefCounted

const Scaler = preload("res://core/scaler.gd")
const RNG = preload("res://core/rng.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const WorldPath = preload("res://core/world_path.gd")
const World = preload("res://core/world.gd")   # respawn() builds a RoamingParty; world.gd never preloads this file
const EnemyNames = preload("res://core/enemy_names.gd")
const WorldFlee = preload("res://core/world_flee.gd")   # who is too weak to stand; that file never preloads this one

# How close to a waypoint counts as having walked it: slack for a band that
# slid along a bank on its way there, not an arrival radius. Arrival at the
# DESTINATION stays exact (`_arrived`), because `move_toward` lands exactly on
# a goal it can reach and a band that rounds its last waypoint a whole unit
# early would tick its patrol on a leg it has not finished.
const WAYPOINT_SLACK := 1.0
# How far a destination may move from where the route to it was planned before
# that route is replanned. A hunted player at map speed covers this in three
# world-minutes, and the tail of a detour is the only part that goes stale.
const REPLAN_DRIFT := 120.0
# At most this many routes are planned per update() call, so a map full of
# blocked bands cannot all pay for Dijkstra on the same frame. A band that is
# over budget keeps the route it has for one more frame (or, with none, marches
# straight at its destination, which is exactly the old behavior).
const REPLAN_BUDGET := 2
# ...and a band the pathfinder could find no way round for waits this long, in
# world-minutes, before asking again. Without it a band walled in by water (or
# aiming at an island) re-runs the search every single frame and eats the whole
# budget, so the bands that COULD be helped never get a turn.
const REPLAN_RETRY_MINUTES := 5.0
# How near the player has to come to a band standing siege for it to come
# for them: the siege is a thing you meet at the town's edge, not a dot you
# can walk round. The same 140 as settlement_visit.gd's BATTLE_RADIUS, so a
# fight it starts is a fight "at the town".
const RAID_SIGHT := 140.0

# The split: `soldier` is the one faction in Scaler.FACTIONS that reads as a
# settled, civilized power (it's what O1's settlements are garrisoned by);
# every other entry is a monster/bandit faction. Per the plan doc, conflict is
# monsters vs. settlements/player — never civilized vs. civilized — so one
# civilized bucket is all the hostility rule needs.
const CIVILIZED := ["dwarf", "elf", "human"]   # orc settlements are hostile, same role "cultist" had

static func is_monster(faction: String) -> bool:
	return not CIVILIZED.has(faction)

# Monsters are hostile to everything civilized (the player included, whatever
# faction they fly) — that rule never changes. O7: a civilized faction's own
# parties turn on the player once its opinion has fallen past FactionOpinion
# .HOSTILE, and on nobody else (conflict is still never civilized-vs-civilized).
static func is_hostile(party, other) -> bool:
	if party.is_player:
		return false
	var other_is_player: bool = "is_player" in other and other.is_player
	if not is_monster(party.faction):
		return other_is_player and FactionOpinion.is_hostile_to_player(party.faction)
	return other_is_player or not is_monster(other.faction)

# --- #142: a band put down comes back ----------------------------------------
#
# A monster band the player (or another band) beat used to be erased and that
# was that: five bands, five fights, and an empty map for the rest of the run.
# fell() keeps a note of it on the world instead, and respawn() — polled once a
# frame like WorldLairs.respawn — puts it back after BAND_RESPAWN, hunting
# again, at its home: the nearest live lair of its faction, else the nearest
# hold of its faction (orcs), else where it fell. Same id, same troops; what
# the world keeps is that this band exists, not that it has met you.
#
# Raiders (ai.behavior == "raid") are NOT kept: their lair sends the next lot
# on its own clock (core/raids.gd). Civilized patrols are not kept either —
# that is the town's loss, not a spawn.
const BAND_RESPAWN := 2880.0   # two in-game days; a lair takes one (WorldLairs.RESPAWN)

static func fell(world, band) -> void:
	if band.is_player or not is_monster(band.faction) \
			or String(band.ai.get("behavior", "")) == "raid":
		return
	world.fallen.append({"id": band.id, "faction": band.faction, "sname": band.sname, "position": band.position,
		"troops": band.troops.duplicate(true), "at": world.clock.elapsed})

static func respawn(world, now: float) -> Array:
	var lines: Array = []
	for f in world.fallen.duplicate():
		if now - float(f["at"]) < BAND_RESPAWN:
			continue
		world.fallen.erase(f)
		var home = _home_of(world, String(f["faction"]), f["position"])
		var at: Vector2 = f["position"] if home == null else home.position
		var b = world.add_party(World.RoamingParty.new(String(f["id"]), at, String(f["faction"])))
		b.sname = String(f.get("sname", ""))
		for t in f["troops"]:
			b.troops.append(t)
		hunt(b)
		lines.append("%s are on the roads again%s." % [EnemyNames.upper_first(EnemyNames.band_name(b, world)),   # the same id, so the same name
			"" if home == null else ", out of " + home.sname])
	return lines

# Nearest live lair of the faction, else its nearest settlement, else null.
static func _home_of(world, faction: String, near: Vector2):
	var best = null
	for l in world.lairs:
		if l.faction == faction and not l.looted \
				and (best == null or l.position.distance_to(near) < best.position.distance_to(near)):
			best = l
	if best != null:
		return best
	for s in world.settlements:
		if s.faction == faction \
				and (best == null or s.position.distance_to(near) < best.position.distance_to(near)):
			best = s
	return best

# --- behavior assignment ---------------------------------------------

static func patrol(party, waypoints: Array) -> void:
	if waypoints.is_empty():
		return
	party.ai = {"behavior": "patrol", "waypoints": waypoints, "index": 0}
	party.goal = waypoints[0]

static func wander(party, home, radius := 80.0, seed_value := 0) -> void:
	party.ai = {
		"behavior": "wander",
		# Either a settlement (anything with a position) or a bare point. The
		# Vector2 half is what the header has always documented and what M3's
		# data-driven placement passes; `"position" in <Vector2>` is an error,
		# not a false, so the type test has to come first.
		"home": home if home is Vector2 else home.position,
		"radius": radius,
		"rng": RNG.new(seed_value),
	}

static func hunt(party) -> void:
	party.ai = {"behavior": "hunt"}

# A lair's raiders (core/raids.gd): walk to `to`, stand there, walk home.
# The band only ever names where it is going; raids.gd advances `phase` and
# rewrites `to` by reading the band each frame. `to` is deliberately not
# `dest` — that key is _steer()'s own, the dry point it actually aims at.
static func raid(party, to: Vector2, target: String, home: String) -> void:
	party.ai = {"behavior": "raid", "to": to, "phase": "march",
		"target": target, "home": home, "until": -1.0}

# A band met and left without blood — slipped, paid off, talked round — loses
# interest in the player for a while: it breaks off, walks away from them, and
# the hunt skips the player until the truce runs out. Free-form `ai` state, so
# world_save.gd carries it.
const TRUCE_MINUTES := 120.0
const BREAK_OFF_DIST := 400.0

static func truce(party, player, now_minutes: float) -> void:
	party.ai["truce_until"] = now_minutes + TRUCE_MINUTES
	var away: Vector2 = party.position - player.position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	party.goal = party.position + away.normalized() * BREAK_OFF_DIST
	# Walking away outranks the behavior until it is done or the truce lapses —
	# a patrolling band used to break off only because `at_goal()` was false
	# and its own step happened to leave the goal alone, which stopped being
	# true once a destination went through `_steer()` every frame. And the
	# route it was walking is a route to somewhere it is no longer going.
	party.ai["break_off"] = party.goal
	party.ai["dest"] = party.goal
	party.ai.erase("route")
	party.ai.erase("route_for")

static func in_truce(party, now_minutes: float) -> bool:
	return float(_state(party).get("truce_until", -1.0)) > now_minutes

# --- driver ----------------------------------------------------------

# One pass over the world: refresh every non-player party's goal. `_delta` is
# unused (behaviors are event-driven off arrival), it's there so O2 can call
# this straight from `_process(delta)` alongside `world.tick(delta)`.
#
# A behavior returns the destination it wants, or null to leave the goal alone
# (a hunter with nothing to chase keeps whatever it was doing). `_steer()` is
# the only writer of `party.goal` in this file.
static func update(world, _delta := 0.0) -> void:
	var budget := REPLAN_BUDGET
	for p in world.parties:
		if p.is_player:
			continue
		var dest = _break_off_step(world, p)
		if dest == null:
			dest = _flee_step(world, p)
		if dest == null:
			match String(_state(p).get("behavior", "")):
				"patrol": dest = _patrol_step(p)
				"wander": dest = _wander_step(p)
				"hunt": dest = _hunt_step(world, p)
				"raid": dest = _raid_step(world, p)
		if dest == null:
			continue
		if _steer(world, p, dest, budget > 0):
			budget -= 1

static func _state(party) -> Dictionary:
	return party.ai if "ai" in party else {}

# Would these two fight if they met? The player only ever fights a band that
# is hostile to it (the player's side is never the hostile one); two bands
# fight when either wants the other dead, the rule core/world_battle.gd
# resolves by.
static func would_fight(a, b) -> bool:
	if b.is_player:
		return is_hostile(a, b)
	if a.is_player:
		return is_hostile(b, a)
	return is_hostile(a, b) or is_hostile(b, a)

# A band too weak for something that would fight it runs from it
# (core/world_flee.gd says who is too weak). It notices a threat inside
# WorldFlee.SIGHT and, once running, keeps running until it is CLEAR of it, so
# a band at the edge of SIGHT does not turn back and forth every frame. The
# destination is a point STEP straight away from the threat, re-set every
# frame so the band bends away as the threat moves; _steer() keeps it on dry
# land. Outranks every behavior but a truce's walk-away (which is already
# away), and a hunt never picks what it would run from (_hunt_step), so a
# hunter does not close to SIGHT, turn, and come back.
static func _flee_step(world, party):
	var s: Dictionary = party.ai
	var from_id := String(s.get("fleeing_from", ""))
	var threat = null
	var best_d := INF
	for other in world.parties:
		if other == party or not would_fight(party, other) or not WorldFlee.outmatched(world, party, other):
			continue
		var d: float = party.position.distance_to(other.position)
		if d > (WorldFlee.CLEAR if other.id == from_id else WorldFlee.SIGHT):
			continue
		if d < best_d:
			best_d = d
			threat = other
	if threat == null:
		s.erase("fleeing_from")
		return null
	s["fleeing_from"] = threat.id
	var away: Vector2 = party.position - threat.position
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	return party.position + away.normalized() * WorldFlee.STEP

static func is_fleeing(party) -> bool:
	return _state(party).has("fleeing_from")

# The walking-away leg a truce starts, while it is still being walked: the
# destination every behavior yields to. null once the band has got there, or
# once the truce has run out from under it.
static func _break_off_step(world, party):
	var s: Dictionary = _state(party)
	if not s.has("break_off"):
		return null
	var away: Vector2 = s["break_off"]
	if in_truce(party, world.clock.elapsed) and party.position.distance_to(away) > WAYPOINT_SLACK:
		return away
	s.erase("break_off")
	return null

# Where the band is actually trying to end up, as the last `_steer()` left it:
# the behavior's destination, nudged out of the water if that is where it
# landed. Vector2.INF while a band has never been steered.
static func destination(party) -> Vector2:
	return _state(party).get("dest", Vector2.INF)

# Standing on that destination — not on `party.goal`, which on a detour is a
# waypoint halfway round a lake. Confusing the two is what would make a patrol
# tick through its whole waypoint list while walking one shoreline. Exact, the
# same test `RoamingParty.at_goal()` makes: O1's `move_toward` lands on a
# reachable goal to the unit, and anything looser advances a patrol one tick
# before it gets where it was going.
static func _arrived(party) -> bool:
	var dest: Vector2 = destination(party)
	if dest == Vector2.INF:
		return false
	return party.position.is_equal_approx(dest)

# The same test, for the module that advances a raid's phases — but never
# while a truce is walking the band away, or while it is running from
# something (_flee_step): standing on the break-off point is not arriving
# anywhere, and nor is a band backed against a lake, whose flee point
# nearest_dry() has snapped to where it already stands.
static func arrived(party) -> bool:
	return not _state(party).has("break_off") and not _state(party).has("fleeing_from") and _arrived(party)

# The waypoints still to walk before the destination, outermost first. Empty
# when the march is a straight line (which is every march on a dry map).
static func pending_route(party) -> Array:
	return _state(party).get("route", [])

# Turns a destination into the next goal. The straight march wherever the
# straight march is dry; otherwise the first waypoint of a route around the
# water, kept on the party (so it survives a save) until the destination has
# wandered off it or the band has walked it out.
static func _steer(world, party, dest: Vector2, may_plan: bool) -> bool:
	var s: Dictionary = party.ai
	# A destination in a lake is a destination nobody can stand on: a wander
	# roll that landed in the water, a hand-placed patrol waypoint over it.
	# Left alone it is never "arrived at", so the behavior sitting on top of it
	# stalls for good — the patrol never takes its next leg, the wanderer never
	# rolls again.
	dest = WorldPath.nearest_dry(world, dest)
	s["dest"] = dest
	if WorldPath.clear_line(world, party.position, dest):
		s.erase("route")
		s.erase("route_for")
		party.goal = dest
		return false
	var route: Array = s.get("route", [])
	# Forget the waypoints already underfoot, and the whole route when it no
	# longer starts where the band is standing — a fight, a load or a shove can
	# put a party somewhere its old plan does not lead from.
	while not route.is_empty() and party.position.distance_to(route[0]) <= WAYPOINT_SLACK:
		route.remove_at(0)
	if not route.is_empty() and not WorldPath.clear_line(world, party.position, route[0]):
		route = []
	var planned := false
	var planned_for: Vector2 = s.get("route_for", dest)
	var stale: bool = route.is_empty() or planned_for.distance_to(dest) > REPLAN_DRIFT
	if stale and may_plan and world.clock.elapsed >= float(s.get("replan_at", -1.0)):
		route = WorldPath.route(world, party.position, dest)
		s["route_for"] = dest
		s["replan_at"] = world.clock.elapsed + (REPLAN_RETRY_MINUTES if route.is_empty() else 0.0)
		planned = true
	s["route"] = route
	# No way round at all — walled in, or a goal on an island. O1's own rule
	# (march at it, stop at the bank) is still better than standing still, and
	# it is what every band did before this file learned to route.
	party.goal = dest if route.is_empty() else route[0]
	return planned

static func _patrol_step(party):
	var s: Dictionary = party.ai
	var wps: Array = s["waypoints"]
	if wps.is_empty():
		return null
	if _arrived(party):
		s["index"] = (int(s["index"]) + 1) % wps.size()
	return wps[int(s["index"])]

static func _wander_step(party):
	var s: Dictionary = party.ai
	if s.has("dest") and not _arrived(party):
		return s["dest"]
	var rng = s["rng"]
	var angle := deg_to_rad(float(rng.roll_die(360)))
	var dist := float(s["radius"]) * float(rng.roll_die(100)) / 100.0
	return Vector2(s["home"]) + Vector2(cos(angle), sin(angle)) * dist

# Chases the nearest hostile thing's *current* position, re-read every update —
# so the goal tracks a target that is itself moving.
# ponytail: linear scan over 3-8 parties/settlements; index it if the roster grows.
static func _hunt_step(world, party):
	var best = null
	var best_d := INF
	for other in world.parties:
		if other == party or not is_hostile(party, other):
			continue
		if other.is_player and in_truce(party, world.clock.elapsed):
			continue
		if WorldFlee.outmatched(world, party, other):
			continue   # it would only run on arrival (_flee_step)
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
	# null when there is nothing to chase: a civilized band at peace, or a
	# truced hunter, which then keeps its break-off goal.
	return best

# At the gate they come for anyone who comes near, truce permitting; on the
# road there and back they keep to their own business.
static func _raid_step(world, party):
	var s: Dictionary = party.ai
	if String(s.get("phase", "")) == "siege":
		var p = world.player()
		if p != null and not in_truce(party, world.clock.elapsed) \
				and not WorldFlee.outmatched(world, party, p) \
				and party.position.distance_to(p.position) <= RAID_SIGHT:
			return p.position
	return s["to"]
