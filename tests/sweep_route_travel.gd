# MEASUREMENT — #231's route travel, against the free roam it replaces.
# Not a test, and not part of tools/run_tests.sh (the runner globs test_* and
# drive_*). It is where core/route_encounters.gd's BASE comes from, and the
# graph numbers docs/spike-route-travel.md quotes:
#   godot --headless --path . -s tests/sweep_route_travel.gd
#   ITINERARIES=8 WALK=40000 godot --headless --path . -s tests/sweep_route_travel.gd
#
# Three parts, over the same maps (the small and large hand-placed ones, and
# procedural seeds 1..PROC_SEEDS):
#
#  A. TODAY. The free-roaming map as the world screen runs it: the bands
#     WorldBands seeded, WorldAI steering them every tick, WorldAI.respawn,
#     WorldBands.refill and Raids.tick on the clock. A company walks an
#     itinerary of random places (settlements, lairs, landmarks) at World.SPEED,
#     and every hostile band that closes to ENCOUNTER_RADIUS is a contact — put
#     down on the spot (WorldAI.fell), the way a won fight puts it down. Counted
#     per 1000 units walked, by the ring the company was standing in. What it
#     leaves out: band-vs-band fights (WorldBattle: every one is a full autoplay
#     combat, and they thin the map, so today's rate here is if anything a
#     little HIGH), fleeing (WorldFlee needs a gauge of the party, which is the
#     world screen's), and the fights' own time.
#  B. THE MODEL. The same itineraries walked along core/world_routes.gd's
#     network (every edge, hidden or not), sampled every RouteEncounters.STEP,
#     every opinion neutral. Per ring and over all of them: the mean of cover x
#     lure (what BASE is multiplied by), the model's mean rate with the BASE it
#     has, a seeded Monte-Carlo of roll() to show the rolls land where the rate
#     says, and the BASE that would reproduce part A's overall rate.
#  C. THE NETWORK. Nodes, edges by tier, known length, and how much longer the
#     known roads make a trip between two towns than the crow flies.
extends SceneTree

const World = preload("res://core/world.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBands = preload("res://core/world_bands.gd")
const WorldRoutes = preload("res://core/world_routes.gd")
const RouteEncounters = preload("res://core/route_encounters.gd")
const Regions = preload("res://core/regions.gd")
const Raids = preload("res://core/raids.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const LargeWorld = preload("res://scenes/world/large_world.gd")
const ProceduralWorld = preload("res://scenes/world/procedural_world.gd")
const RNG = preload("res://core/rng.gd")

const ENCOUNTER_RADIUS := 24.0   # scenes/world/world.gd's
const DT := 0.25                 # world-minutes a tick: SPEED * 2 * DT stays under the radius

var _itins := 4
var _walk := 30000.0
var _proc := 4
var _scene = null   # the world screen, for its _small_world(); freed before quit

func _env_int(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.get_environment(k) != "" else d

func _maps() -> Array:
	var out: Array = []
	_scene = load("res://scenes/world/world.tscn").instantiate()
	out.append(["small", func(): return _scene._small_world()])
	out.append(["large", func(): return LargeWorld.build()])
	for s in range(1, _proc + 1):
		out.append(["proc%d" % s, func(): return ProceduralWorld.build(s)])
	return out

func _places(w) -> Array:
	var out: Array = []
	for s in w.settlements: out.append(["settlement", s.id, s.position])
	for l in w.lairs: out.append(["lair", l.id, l.position])
	for m in w.landmarks: out.append(["landmark", m.id, m.position])
	return out

func _next(rng, places: Array, last: int) -> int:
	var i := last
	while i == last:
		i = rng.roll_die(places.size()) - 1
	return i

func _ring_i(w, pos: Vector2) -> int:
	return int(Regions.at(w, pos)["index"])

func _init() -> void:
	_itins = _env_int("ITINERARIES", 4)
	_walk = float(_env_int("WALK", 30000))
	_proc = _env_int("PROC_SEEDS", 4)
	var maps := _maps()
	# --- A ---
	# One slot per ring, however many Regions.BANDS has (the Unmapped made it
	# five; a hard-coded four hung the sweep on the first walk that got there).
	var nr: int = Regions.BANDS.size()
	var rings: Array = Regions.BANDS.map(func(b): return String(b["id"]))
	var a_walk := _zeros(nr, 0.0)
	var a_hit := _zeros(nr, 0)
	var a_mix := _dicts(nr)
	var t0 := Time.get_ticks_msec()
	for m in maps:
		for it in _itins:
			FactionOpinion.reset()
			var w = m[1].call()
			var p = w.player()
			var places := _places(w)
			var rng = RNG.new(1000 + it)
			var bands_rng = RNG.new(2000 + it)
			var at := _next(rng, places, -1)
			w.set_goal(p, places[at][2])
			var walked := 0.0
			var stuck := 0
			while walked < _walk:
				var before: Vector2 = p.position
				w.tick(DT)
				WorldAI.update(w, DT)
				var step: float = before.distance_to(p.position)
				walked += step
				var ri := _ring_i(w, p.position)
				a_walk[ri] += step
				for q in w.parties.duplicate():
					if q.is_player or not WorldAI.is_hostile(q, p):
						continue
					if q.position.distance_to(p.position) <= ENCOUNTER_RADIUS:
						a_hit[ri] += 1
						a_mix[ri][q.faction] = int(a_mix[ri].get(q.faction, 0)) + 1
						WorldAI.fell(w, q)
						w.parties.erase(q)
				var now: float = w.clock.elapsed
				WorldAI.respawn(w, now)
				WorldBands.refill(w, now, bands_rng)
				Raids.tick(w, now)
				stuck = stuck + 1 if step < 0.01 else 0
				if p.at_goal() or stuck > 40:
					at = _next(rng, places, at)
					w.set_goal(p, places[at][2])
					stuck = 0
	print("A. TODAY — hostile contacts per 1000 units walked (%d maps x %d itineraries x %d units, %.0fs)" % [
		maps.size(), _itins, int(_walk), (Time.get_ticks_msec() - t0) / 1000.0])
	var today := _zeros(nr, 0.0)
	for ri in nr:
		today[ri] = a_hit[ri] / maxf(1.0, a_walk[ri] / 1000.0)
		print("  %-9s walked %8d  contacts %4d  rate %.2f  mix %s" % [rings[ri], int(a_walk[ri]), a_hit[ri], today[ri], _mix_text(a_mix[ri])])
	# --- B and C ---
	var b_n := _zeros(nr, 0)
	var b_factor := _zeros(nr, 0.0)
	var b_rate := _zeros(nr, 0.0)
	var b_fired := _zeros(nr, 0)
	var b_mix := _dicts(nr)
	print("\nC. THE NETWORK")
	for m in maps:
		FactionOpinion.reset()
		var w = m[1].call()
		var t := Time.get_ticks_msec()
		var net = WorldRoutes.build(w)
		var ms := Time.get_ticks_msec() - t
		var st: Dictionary = net.stats()
		print("  %-6s nodes %2d (forks %2d)  edges %2d: road %2d track %2d path %2d byway %d  known %5d of %5d units  detour %s  build %dms" % [
			m[0], st["nodes"], st["forks"], st["edges"], st["road"], st["track"], st["path"], st["byway"],
			int(st["known_length"]), int(st["length"]), _detour(net, w), ms])
		var places := _places(w)
		for it in _itins:
			var rng = RNG.new(1000 + it)
			var at := _next(rng, places, -1)
			var here: String = WorldRoutes.poi_id(places[at][0], places[at][1])
			var walked := 0.0
			var k := 0
			while walked < _walk:
				var nxt := _next(rng, places, at)
				var there: String = WorldRoutes.poi_id(places[nxt][0], places[nxt][1])
				var way: Dictionary = net.path(here, there, false)
				at = nxt
				here = there
				if way.is_empty():
					continue
				for pos in _samples(way["points"]):
					var ri := _ring_i(w, pos)
					var f: Dictionary = RouteEncounters.factors(w, pos)
					b_n[ri] += 1
					b_factor[ri] += float(f["cover"]) * float(f["lure"])
					b_rate[ri] += float(f["rate"])
					var hit := RouteEncounters.roll(w, pos, "sweep|%s|%d|%d" % [m[0], it, k])
					k += 1
					if not hit.is_empty():
						b_fired[ri] += 1
						b_mix[ri][hit["faction"]] = int(b_mix[ri].get(hit["faction"], 0)) + 1
					walked += RouteEncounters.STEP
	print("\nB. THE MODEL — per ring, sampled every %d units along the same itineraries, BASE %.2f" % [
		int(RouteEncounters.STEP), RouteEncounters.BASE])
	var n_all := 0
	var f_all := 0.0
	var r_all := 0.0
	var fired_all := 0
	for ri in nr:
		var n: int = maxi(1, b_n[ri])
		n_all += b_n[ri]
		f_all += b_factor[ri]
		r_all += b_rate[ri]
		fired_all += b_fired[ri]
		print("  %-9s samples %5d  mean cover*lure %.2f  model rate %.2f (today %.2f)  rolled %.2f  mix %s" % [
			rings[ri], b_n[ri], b_factor[ri] / n, b_rate[ri] / n, today[ri],
			b_fired[ri] / maxf(1.0, n * RouteEncounters.STEP / 1000.0), _mix_text(b_mix[ri])])
	var hits_all: int = a_hit.reduce(func(acc, x): return acc + x, 0)
	var walk_all: float = a_walk.reduce(func(acc, x): return acc + x, 0.0)
	var today_all: float = hits_all / maxf(1.0, walk_all / 1000.0)
	var mean_f: float = f_all / maxi(1, n_all)
	print("  all rings: today %.2f (%d contacts in %d units)  model %.2f  rolled %.2f  mean cover*lure %.2f  -> implied BASE %.2f" % [
		today_all, hits_all, int(walk_all),
		r_all / maxi(1, n_all), fired_all / maxf(1.0, n_all * RouteEncounters.STEP / 1000.0), mean_f, today_all / maxf(0.001, mean_f)])
	_scene.free()
	quit(0)

func _zeros(n: int, v) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(v)
	return out

func _dicts(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({})
	return out

# Every STEP along a polyline, starting half a step in.
func _samples(pts: PackedVector2Array) -> Array:
	var out: Array = []
	var carry := RouteEncounters.STEP * 0.5
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		var d := carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += RouteEncounters.STEP
		carry = d - seg
	return out

# Mean and worst ratio of known-road distance to straight distance, over every
# pair of towns.
func _detour(net, w) -> String:
	var ratios: Array = []
	for i in w.settlements.size():
		for j in range(i + 1, w.settlements.size()):
			var a = w.settlements[i]
			var b = w.settlements[j]
			var way: Dictionary = net.path(WorldRoutes.poi_id("settlement", a.id), WorldRoutes.poi_id("settlement", b.id))
			if not way.is_empty():
				ratios.append(float(way["length"]) / a.position.distance_to(b.position))
	if ratios.is_empty():
		return "-"
	var sum := 0.0
	for r in ratios: sum += r
	return "mean %.2f worst %.2f" % [sum / ratios.size(), ratios.max()]

func _mix_text(mix: Dictionary) -> String:
	var total := 0
	for f in mix: total += int(mix[f])
	if total == 0:
		return "-"
	var keys: Array = mix.keys()
	keys.sort_custom(func(x, y): return int(mix[x]) > int(mix[y]))
	var parts: Array = []
	for f in keys.slice(0, 5):
		parts.append("%s %d%%" % [f, roundi(100.0 * int(mix[f]) / total)])
	return ", ".join(parts)
