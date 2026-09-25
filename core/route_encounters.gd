# #231 — who the company meets on the road, once nobody walks the map.
#
# Today every monster on the overworld is a figure standing on it: WorldBands
# fills the map to a cap, WorldAI walks each band toward the nearest thing it
# hates, and a fight is two figures closing inside ENCOUNTER_RADIUS. The
# owner's call on #231 is that bands stop spawning on the map and stop being
# drawn on it: what a company meets is decided by where it is walking — the
# country (core/regions.gd's rings), the peoples and lairs near the road, and
# what every people thinks of the company (core/faction_opinion.gd). This file
# is that decision, as odds and a roster. It spawns nothing and moves nothing;
# core/world_routes.gd is the network it is rolled along, and
# docs/spike-route-travel.md says which later slice wires what.
#
#   RouteEncounters.factors(world, pos)        # why this stretch is as dangerous as it is
#   RouteEncounters.rate(world, pos)           # contacts per 1000 units of road
#   RouteEncounters.candidates(world, pos)     # who, each with its share of that rate
#   RouteEncounters.roll(world, pos, key, walked)   # {} most steps; a spec when one fires
#   RouteEncounters.band(spec, pos)            # the spec as a World.RoamingParty for the
#                                              # approach card and _launch_combat, unchanged
#
# THE RATE is per distance walked, not per world-minute: under the route model
# a company is only ever met while it is walking a road (a camp keeps its own
# ambush roll, core/world_camp.gd), so a stretch of road is what carries the
# danger. Three terms multiply, then a fourth adds:
#
#   BASE          how busy a road is. Measured, not chosen:
#                 tests/sweep_route_travel.gd walks today's free-roaming map and
#                 counts how often a hostile band actually reached the company
#                 per 1000 units walked. The model starts from the density the
#                 owner has been playing (see BASE's comment for why it is one
#                 number and not one per ring).
#   cover         a civilized town's patrols thin what walks near its walls — by
#                 how much it cares to: none for a company it is hostile to, all
#                 of COVER for one it holds dear. The opinion of every people the
#                 road passes near is in this term.
#   lure          a live lair thickens the roads near it, and so does a monster
#                 people's hold (an orc town is a lair with a market).
#   hunt          a people hostile to the company (opinion at or under
#                 FactionOpinion.HOSTILE) sends its own patrols out after it,
#                 near its towns. Added, not multiplied: a town that hates you
#                 does not make the goblins any keener.
#
# WHO is the rate split by source: the monster part among the factions whose
# country this is (Regions.HOMES, weighted by WorldBands.KINDS — the table the
# map already spawns from, so the mix a player has learned stays the mix) plus
# every nearby lair's own people, pulled in as the lair gets closer; the hunt
# part to the people doing the hunting. WHAT THEY ARE MADE OF is the KINDS row's
# troop template at the ring's levels (the rule WorldBands.spawn_one uses), and
# a people that hates the company past HOSTILE sends a heavier patrol, one more
# heavy per GRUDGE_STEP points below it.
#
# WHY MONSTER OPINION IS NOT A TERM. The issue asks for "the opinion of all
# factions" to shape the odds. Monster peoples keep no opinion of the company
# in this codebase and never have (core/approach.gd's parley_costs_opinion,
# core/contracts.gd's credit(), world.gd's KILLED_THEIRS): only the civilized
# peoples do. So opinion reaches the monsters through the peoples who keep the
# roads — the cover term — and reaches the peoples themselves through the hunt
# term. Giving monster peoples an opinion is its own design call, listed in the
# spike doc's open questions.
#
# DETERMINISM. A roll is seeded off the caller's key — the edge, the stretch of
# it, and the world-day (step_key()) — so walking the same stretch on the same
# day meets the same thing, and a reload cannot reroll a road the player did not
# like. The next day it is a fresh road.
#
# What this does NOT own: the fight (encounter_spec and Scaler, unchanged — a
# route band is fought exactly as a roaming one is), the card that asks how to
# meet it (core/approach.gd), any drawing, and walking (core/world_routes.gd).
extends RefCounted

const World = preload("res://core/world.gd")
const Regions = preload("res://core/regions.gd")
const WorldAI = preload("res://core/world_ai.gd")
const WorldBands = preload("res://core/world_bands.gd")
const FactionOpinion = preload("res://core/faction_opinion.gd")
const RNG = preload("res://core/rng.gd")

# Contacts per 1000 units walked, before cover, lure and hunt — the same in
# every ring. Calibrated so the model's mean rate along the sweep's itineraries
# equals the rate today's free-roaming map actually delivers, so switching the
# model in changes WHERE the danger is, not how much of it there is.
#
# Flat, not per ring, because the per-ring numbers today are upside down:
#   heartland 0.81, marches 0.71, frontier 0.25, deeps 0.43 (18 contacts)
# — the further out, the QUIETER — and the deeps' few contacts were mostly
# bandits, beasts and goblins that had followed the company out. A hunting band
# makes for the nearest hostile thing anywhere on the map (WorldAI._hunt_step),
# the towns sit in the middle, so the bands pile up where the towns are.
# Copying that shape would bake a safe frontier into the new model. The rings
# already make a contact out there harder (Regions.power_scale builds the fight
# at the ring's levels) and decide who it is (HOMES, below); how OFTEN is left
# flat until the owner wants a shape (docs/spike-route-travel.md §7).
# MEASURED 2026-09-25, tests/sweep_route_travel.gd, small + large + procedural
# seeds 1..4, 4 itineraries each, 30000 units walked per itinerary: 481 hostile
# contacts in 720 400 units walked, 0.67 per 1000; mean cover x lure along the
# same itineraries on the network 1.12; 0.67 / 1.12 = 0.60.
const BASE := 0.6

# One roll per this many units walked. Under the step a stretch of road is
# one stretch; the chance per roll is 1 - e^(-rate * STEP / 1000).
const STEP := 100.0

# Cover: each civilized town within COVER_RADIUS takes up to COVER off the
# monster rate at its gate, falling to nothing at the edge of the radius, and
# scaled by regard (0 at FactionOpinion.HOSTILE or worse, 0.5 neutral, 1 at
# +50 or better). Towns compound: two friendly towns on one road are safer
# than one.
# Taste numbers (spike, 2026-09-25): no sweep can measure them until phase 1
# puts a player on the roads; the doc lists them as the first thing to measure.
const COVER := 0.6
const COVER_RADIUS := 350.0
# Lure: each live lair (and monster people's town) within LURE_RADIUS adds up
# to LURE to the monster rate, and pulls LAIR_MIX of its own people into the
# mix, both falling off linearly. Taste numbers, as above.
const LURE := 1.0
const LURE_RADIUS := 350.0
const LAIR_MIX := 3.0
# A raided town (core/raids.gd) has the raiding lair's people on its roads,
# as if the lair stood at its gate, at this fraction of a lair's pull.
const RAID_PULL := 0.5
# Hunt: a people at or under FactionOpinion.HOSTILE adds up to HUNT contacts per
# 1000 units near each of its towns, within HUNT_RADIUS. One more heavy per
# GRUDGE_STEP points under HOSTILE, at most GRUDGE_MAX. Taste numbers.
const HUNT := 1.5
const HUNT_RADIUS := 500.0
const GRUDGE_STEP := 20.0
const GRUDGE_MAX := 2
# A faction with no KINDS row (dragon, elemental, construct, fey) weighs this
# in its home country's mix, and fields this troop template.
const RARE_WEIGHT := 1
const RARE_ROLES := ["heavy", "light"]

# --- the rate ----------------------------------------------------------------

static func _prox(d: float, radius: float) -> float:
	return clampf(1.0 - d / radius, 0.0, 1.0)

# 0 at FactionOpinion.HOSTILE or worse, 0.5 at neutral, 1 at +50 or better.
static func regard(faction: String) -> float:
	var op := FactionOpinion.get_opinion(faction)
	return clampf((op - FactionOpinion.HOSTILE) / (2.0 * absf(FactionOpinion.HOSTILE)), 0.0, 1.0)

static func _live_lair(l) -> bool:
	return not l.looted

# Everything that makes this point as dangerous as it is, for tests, the sweep
# and (phase 1) the map's "the road feels..." line:
#   {ring, base, cover, lure, monster, hunt: {faction: rate}, rate,
#    pulls: [{faction, pull}] — the lairs and holds dragging their people in}
static func factors(world, pos: Vector2) -> Dictionary:
	var ring: Dictionary = Regions.at(world, pos)
	var base: float = BASE
	var cover := 1.0
	var lure := 1.0
	var hunt := {}
	var pulls: Array = []
	for s in world.settlements:
		var d: float = pos.distance_to(s.position)
		if WorldAI.is_monster(s.faction):
			var p := _prox(d, LURE_RADIUS)
			if p > 0.0:
				lure += LURE * p
				pulls.append({"faction": s.faction, "pull": LAIR_MIX * p})
			continue
		cover *= 1.0 - COVER * _prox(d, COVER_RADIUS) * regard(s.faction)
		if FactionOpinion.is_hostile_to_player(s.faction):
			var h := HUNT * _prox(d, HUNT_RADIUS)
			if h > 0.0:
				hunt[s.faction] = float(hunt.get(s.faction, 0.0)) + h
		if s.raided_by != "":
			for l in world.lairs:
				if l.id == s.raided_by and _live_lair(l):
					var p := _prox(d, LURE_RADIUS) * RAID_PULL
					if p > 0.0:
						lure += LURE * p
						pulls.append({"faction": l.faction, "pull": LAIR_MIX * p})
	for l in world.lairs:
		if not _live_lair(l):
			continue
		var p := _prox(pos.distance_to(l.position), LURE_RADIUS)
		if p > 0.0:
			lure += LURE * p
			pulls.append({"faction": l.faction, "pull": LAIR_MIX * p})
	var monster := base * cover * lure
	var total := monster
	for f in hunt:
		total += float(hunt[f])
	return {"ring": ring["id"], "base": base, "cover": cover, "lure": lure, "monster": monster,
		"hunt": hunt, "rate": total, "pulls": pulls}

static func rate(world, pos: Vector2) -> float:
	return float(factors(world, pos)["rate"])

# --- who ---------------------------------------------------------------------

# The KINDS rows a faction can field as a hunting band, or [] for one the table
# does not have.
static func _rows(faction: String) -> Array:
	return WorldBands.KINDS.filter(func(k): return k["ai"] == "hunt" and k["faction"] == faction)

static func _home_weight(faction: String) -> float:
	var rows := _rows(faction)
	if rows.is_empty():
		return float(RARE_WEIGHT)
	var w := 0
	for k in rows:
		w += int(k["weight"])
	return float(w)

# Every source that could be met here, each carrying its share of rate():
#   [{faction, source: "country" | "lair" | "hunt", rate}]
# sorted by faction then source, so the order (and a seeded pick off it) is
# stable. Rates sum to rate(world, pos).
static func candidates(world, pos: Vector2) -> Array:
	var f := factors(world, pos)
	var mix := {}   # faction -> [country weight, lair weight]
	var ring_id: String = f["ring"]
	for faction in Regions.HOMES.get(ring_id, []):
		mix[faction] = [_home_weight(faction), 0.0]
	for pull in f["pulls"]:
		var faction: String = pull["faction"]
		if not mix.has(faction):
			mix[faction] = [0.0, 0.0]
		mix[faction][1] += float(pull["pull"]) * _home_weight(faction)
	var sum := 0.0
	for faction in mix:
		sum += float(mix[faction][0]) + float(mix[faction][1])
	var out: Array = []
	if sum > 0.0:
		for faction in mix:
			for i in 2:
				var w: float = mix[faction][i]
				if w > 0.0:
					out.append({"faction": faction, "source": ["country", "lair"][i],
						"rate": float(f["monster"]) * w / sum})
	for faction in f["hunt"]:
		out.append({"faction": faction, "source": "hunt", "rate": float(f["hunt"][faction])})
	out.sort_custom(func(a, b): return String(a["faction"]) + String(a["source"]) < String(b["faction"]) + String(b["source"]))
	return out

# --- the roll ------------------------------------------------------------------

# The seed for one stretch of one edge on one world-day: the same stretch walked
# twice in a day is the same stretch, and a reload is not a reroll.
static func step_key(edge: String, offset: float, world_minutes: float) -> String:
	return "%s|%d|%d" % [edge, int(floor(offset / STEP)), int(floor(world_minutes / FactionOpinion.DAY))]

# Chance that `walked` units of road at `pos` meet something.
static func chance(world, pos: Vector2, walked := STEP) -> float:
	return 1.0 - exp(-rate(world, pos) * walked / 1000.0)

# One roll for `walked` units at `pos`: {} when the road is quiet, else a spec
# (compose()). `key` seeds it (step_key()); `party` only colours the grudge.
static func roll(world, pos: Vector2, key: String, walked := STEP) -> Dictionary:
	var rng = RNG.new(maxi(1, absi(hash("route|%s" % key))))
	var cands := candidates(world, pos)
	var total := 0.0
	for c in cands:
		total += float(c["rate"])
	if total <= 0.0:
		return {}
	var p := 1.0 - exp(-total * walked / 1000.0)
	if _frac(rng) >= p:
		return {}
	var pick := _frac(rng) * total
	var chosen: Dictionary = cands[-1]
	for c in cands:
		pick -= float(c["rate"])
		if pick < 0.0:
			chosen = c
			break
	return compose(world, pos, chosen, rng, key)

# What the chosen source fields: {id, kind, faction, source, troops, hostile}.
# A monster people fields one of its KINDS rows (weighted); a hunting people its
# own patrol row, heavier for the grudge. Levels are the ring's, the rule
# WorldBands.spawn_one places a band by.
static func compose(world, pos: Vector2, cand: Dictionary, rng, key := "") -> Dictionary:
	var faction: String = cand["faction"]
	var hunting: bool = cand["source"] == "hunt"
	var rows: Array = WorldBands.KINDS.filter(func(k): return k["faction"] == faction and (k["ai"] == "patrol") == hunting)
	var kind := "%s-band" % faction
	var roles: Array = RARE_ROLES.duplicate()
	if not rows.is_empty():
		var total := 0
		for k in rows:
			total += int(k["weight"])
		var roll_w: int = rng.roll_die(total)
		for k in rows:
			roll_w -= int(k["weight"])
			if roll_w <= 0:
				kind = k["id"]
				roles = (k["roles"] as Array).duplicate()
				break
	if hunting:
		var below: float = FactionOpinion.HOSTILE - FactionOpinion.get_opinion(faction)
		for _i in mini(GRUDGE_MAX, int(floor(below / GRUDGE_STEP))):
			roles.append("heavy")
	var lv: Array = Regions.at(world, pos)["levels"]
	var troops: Array = []
	for role in roles:
		troops.append({"role": role, "level": int(lv[0]) + rng.roll_die(int(lv[1]) - int(lv[0]) + 1) - 1})
	return {"id": "met-%s-%d" % [kind, absi(hash("met|%s" % key)) % 100000], "kind": kind,
		"faction": faction, "source": cand["source"], "troops": troops,
		"hostile": WorldAI.is_monster(faction) or FactionOpinion.is_hostile_to_player(faction)}

# The spec as a band standing at `pos`: what the approach card and
# _launch_combat already take, so phase 1 needs no second fight path. Not added
# to the world — the caller decides whether a met band is kept at all.
static func band(spec: Dictionary, pos: Vector2):
	var b = World.RoamingParty.new(String(spec["id"]), pos, String(spec["faction"]))
	for t in spec["troops"]:
		b.troops.append((t as Dictionary).duplicate())
	b.ai = {"behavior": "met", "kind": spec["kind"], "source": spec["source"]}
	return b

static func _frac(rng) -> float:
	return (rng.roll_die(10000) - 1) / 10000.0
