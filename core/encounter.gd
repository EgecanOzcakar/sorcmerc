# The Sunken Shrine — the one hand-authored MVP encounter (combat-design.md §7).
# Numbers live here and nowhere else; tune by editing this file.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Presets = preload("res://core/presets.gd")
const Combat = preload("res://core/combat.gd")
const Hex = preload("res://core/hex.gd")
const Power = preload("res://core/rules/power.gd")
const EnemyNames = preload("res://core/enemy_names.gd")
const Loot = preload("res://core/loot.gd")
const Ach = preload("res://core/achievements.gd")
const Objectives = preload("res://core/objectives.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")

# --- ranges (hexes) — tune here ---------------------------------------
const REACH_MELEE := 1

# Where each combatant starts. Ranges, kit and numbers come from the sheet
# (core/presets.gd) and data/monsters.json — this file owns the room.
const START := {"vera": Vector2i(2, 0), "pike": Vector2i(2, 2), "ilsa": Vector2i(1, 1),
	"grull": Vector2i(4, 1), "snik": Vector2i(4, 0), "vess": Vector2i(5, 0), "kritch": Vector2i(7, 1)}

# --- the room ---------------------------------------------------------
# Flat-top axial hexes, laid left->right along +q:
#   Threshold (q 0..2)  ][ choke q3 ][  Brazier Hall (q 4..6)  ][ choke q7 ][  Alcove (q 8)
# The single-hex chokes force the fight through the Brazier Hall.
const BRAZIER := Vector2i(5, 1)

static func _room() -> Array:
	var h: Array = []
	for r in 3:
		h.append(Vector2i(0, r)); h.append(Vector2i(1, r)); h.append(Vector2i(2, r))  # Threshold
	h.append(Vector2i(3, 1))                                                            # choke
	for r in 3:
		h.append(Vector2i(4, r)); h.append(Vector2i(5, r)); h.append(Vector2i(6, r))  # Brazier Hall
	h.append(Vector2i(7, 1))                                                            # choke
	for r in 3:
		h.append(Vector2i(8, r))                                                        # Alcove
	return h

static func board() -> Dictionary:
	return shrine_board()

# --- T11: board themes ------------------------------------------------
# A board is {hexes, cover, rough, objects, palette, reach_melee, region_at}.
# `objects` are the interactables combat.gd reads: {type, pos, hazard?, hp?,
# blocks_movement?, explosive?}. A hazard object is shovable-into (2d6 fire);
# an hp object can be smashed (one action); explosive ones burst on death.
const THEMES := ["sunken-shrine", "goblin-camp", "city-square", "forest-clearing",
	"frozen-cave", "merchant-shop", "downs", "marsh"]

# `seed` shapes the ground around the authored room (see _grow); 0 means "the
# theme's own fixed shape", so a caller without a fight seed still gets the
# same board every time.
static func board_for(theme: String, seed: int = 0) -> Dictionary:
	var b: Dictionary
	match theme:
		"goblin-camp": b = goblin_camp_board()
		"city-square": b = city_square_board()
		"forest-clearing": b = forest_clearing_board()
		"frozen-cave": b = frozen_cave_board()
		"merchant-shop": b = merchant_shop_board()
		"downs": b = downs_board()
		"marsh": b = marsh_board()
		_: b = shrine_board()
	return _grow(_widen(b), seed if seed != 0 else theme.hash())

# --- the ground around the room ----------------------------------------
#
# The room and its mirror are a 14x4 strip: a road, not a place. _grow pads it
# to BOARD_ROWS rows, then takes seeded bites out of the perimeter and adds
# seeded bulges beyond it, so every fight's footprint is its own lumpy shape —
# inlets, lobes, a pinch here and there. The core (the authored hexes, the
# party starts) is never touched and the result is always one connected
# floor. Fresh ground gets a few rough patches; props and cover stay authored.
const BOARD_ROWS := 9        # rows of floor, room rows included (the room is 4)
const BOARD_BITES := 8       # perimeter discs removed — how badly shaped it gets
const BOARD_BULGES := 5      # perimeter discs added outside the rectangle
const BOARD_ROUGH := 6       # rough patches sprinkled on the new ground
# #156: raised ground. ONE shelf per board, a disc of one or two rings, exactly
# ONE level up — see combat.gd's height notes for what a level buys.
#
# One level is deliberate: a step of two is a cliff nothing can walk, so a
# generator that cut one would have to prove the board still joined up
# afterwards. One level can never disconnect anything (it only ever costs a
# point to climb), so the shape _grow worked to keep connected stays connected.
# An authored board, or a content pack's, is free to cut a real cliff and take
# that proof on itself.
#
# ONE SHELF IS A BALANCE NUMBER, not a taste one, and tests/test_scaler.gd owns
# it. Ground that costs a point to climb taxes whoever is APPROACHING, and at
# level 3 that is mostly the monsters while the party shoots and casts — so
# raised ground moves the win rate the party's way. Measured, level-3 preset
# party on hard, 200 fights a tier: flat 83.5%, one shelf 85.0%, two shelves
# 87.5%. The band is 65-85%, so two shelves puts the game outside the
# difficulty it is calibrated to and one keeps it in. Raising this means
# re-measuring core/scaler.gd's knobs, which is a balance pass and not a
# side-effect of a map feature.
const BOARD_SHELVES := 1
const SHELF_RINGS := 2       # the widest a shelf gets

static func _grow(b: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var core := {}
	for h in b["hexes"]:
		core[h] = true
	for p in PARTY_STARTS:
		core[p] = true
	var q0 := 1 << 30; var q1 := -(1 << 30); var r0 := 1 << 30; var r1 := -(1 << 30)
	for h in core:
		q0 = mini(q0, h.x); q1 = maxi(q1, h.x); r0 = mini(r0, h.y); r1 = maxi(r1, h.y)
	# pad: rows above and below the room, alternating so it stays centred
	var extra := maxi(0, BOARD_ROWS - (r1 - r0 + 1))
	r0 -= extra / 2
	r1 += extra - extra / 2
	var floor := {}
	for h in _rect(q0, q1, r0, r1):
		floor[h] = true
	# bulges first (they only add), then bites (checked against the core and connectivity)
	for _i in BOARD_BULGES:
		var edge := _perimeter(floor)
		var at: Vector2i = edge[rng.randi_range(0, edge.size() - 1)]
		var out: Vector2i = at + Hex.DIRS[rng.randi_range(0, 5)]
		if floor.has(out):
			continue
		for h in [out] + Hex.within(out, rng.randi_range(1, 2)):
			if h.x >= q0 - 1 and h.x <= q1 + 1:   # lumps grow up and down, not along the road
				floor[h] = true
	for _i in BOARD_BITES:
		var edge := _perimeter(floor)
		var at: Vector2i = edge[rng.randi_range(0, edge.size() - 1)]
		var bite: Array = [at] + Hex.within(at, rng.randi_range(1, 2))
		if bite.any(func(h): return core.has(h)):
			continue
		var trial := floor.duplicate()
		for h in bite:
			trial.erase(h)
		if _all_connected(trial):
			floor = trial
	b["hexes"] = floor.keys()
	# a little texture on the new ground, never on a hex that already means something
	var taken := {}
	for h in b["cover"]: taken[h] = true
	for h in b["rough"]: taken[h] = true
	for o in b["objects"]: taken[o["pos"]] = true
	var fresh: Array = b["hexes"].filter(func(h): return not core.has(h) and not taken.has(h))
	var rough: Array = b["rough"].duplicate()
	for _i in mini(BOARD_ROUGH, fresh.size()):
		var h: Vector2i = fresh[rng.randi_range(0, fresh.size() - 1)]
		if not (h in rough):
			rough.append(h)
	b["rough"] = rough
	_raise(b, rng, core, floor)
	return b

# #156: the shelves. On the grown apron only — never on `core`, which is the
# authored room and the hexes the party stands on, so a fight always opens on
# the flat and the high ground is somewhere to go rather than somewhere one
# side starts. An authored board that wants its own relief declares "height"
# and keeps it: this only fills the key in when it is not already there.
static func _raise(b: Dictionary, rng: RandomNumberGenerator, core: Dictionary, floor: Dictionary) -> void:
	if b.has("height"):
		return
	var apron: Array = b["hexes"].filter(func(h): return not core.has(h))
	if apron.is_empty():
		return
	var height := {}
	for _i in BOARD_SHELVES:
		var at: Vector2i = apron[rng.randi_range(0, apron.size() - 1)]
		for h in [at] + Hex.within(at, rng.randi_range(1, SHELF_RINGS)):
			if floor.has(h) and not core.has(h):
				height[h] = 1
	if not height.is_empty():
		b["height"] = height

# Floor hexes with at least one non-floor neighbour.
static func _perimeter(floor: Dictionary) -> Array:
	var out: Array = []
	for h in floor:
		for n in Hex.neighbors(h):
			if not floor.has(n):
				out.append(h)
				break
	return out

static func _all_connected(floor: Dictionary) -> bool:
	if floor.is_empty():
		return false
	var start: Vector2i = floor.keys()[0]
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var h: Vector2i = q.pop_front()
		for n in Hex.neighbors(h):
			if floor.has(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen.size() == floor.size()

# The authored rooms are 5-9 hexes wide: docs/spike-hex-ranges.md measured
# that on them SPAWN_GAP is unreachable on four of six, first contact is round
# 1 in 150/150 fights, and every range from 30 ft up is the same range. So a
# fight is played on the room plus its mirror image along q: the party starts
# in the authored half, foes spawn a real SPAWN_GAP away in the other, and
# cover/rough/objects come along so the far half is the same kind of place.
# region_at answers for the mirrored hex's twin, so narration keeps its names.
# ponytail: a mirror, not a second authored half per theme — author one when
# a board needs an asymmetric far end.
const BOARD_OVERLAP := 3     # columns the mirror shares with the room: 0 is a full-length road

static func _widen(b: Dictionary) -> Dictionary:
	var qmax := 0
	for h in b["hexes"]:
		qmax = maxi(qmax, h.x)
	# a narrow room (the shop, 5 wide) overlaps less so the far side still sits a SPAWN_GAP away
	var overlap: int = clampi(2 * (qmax + 1) - 10, 0, BOARD_OVERLAP)
	var flip := func(p: Vector2i) -> Vector2i: return Vector2i(2 * qmax + 1 - overlap - p.x, p.y)
	# the shared columns keep the room's own furniture; the mirror only adds what lands on fresh ground
	for k in ["hexes", "cover", "rough"]:
		var have: Array = b[k]
		b[k] = have + have.map(flip).filter(func(h): return not (h in have))
	var taken: Array = b["objects"].map(func(o): return o["pos"])
	var twins: Array = b["objects"].duplicate(true)
	for o in twins:
		o["pos"] = flip.call(o["pos"])
	b["objects"] = b["objects"] + twins.filter(func(o): return not (o["pos"] in taken))
	var src: Callable = b["region_at"]
	b["region_at"] = func(p: Vector2i) -> String: return src.call(p if p.x <= qmax else flip.call(p))
	return b

# Same dict; named so build()'s `board` parameter can still reach the default.
static func shrine_board() -> Dictionary:
	return {
		"hexes": _room(),
		"objects": [{"type": "brazier", "pos": BRAZIER,
			"hazard": {"dice": "2d6", "damage_type": "fire"}}],
		"cover": [Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2)],  # the Alcove
		"rough": [Vector2i(4, 1), Vector2i(6, 1)],                  # scorched ground either side of the brazier
		"palette": "shrine",
		# The turn resolver reads these off the board rather than preloading this file,
		# so T7/T8 can hand it a generated encounter instead.
		"reach_melee": REACH_MELEE,
		"region_at": region_at,
	}

static func region_at(p: Vector2i) -> String:
	if p.x <= 3:
		return "Threshold"
	if p.x <= 6:
		return "Brazier Hall"
	return "Alcove"

static func _rect(q0: int, q1: int, r0: int, r1: int) -> Array:
	var h: Array = []
	for q in range(q0, q1 + 1):
		for r in range(r0, r1 + 1):
			h.append(Vector2i(q, r))
	return h

# Open clearing, a campfire in the middle and the warband's stores stacked around it.
static func goblin_camp_board() -> Dictionary:
	return {
		"hexes": _rect(0, 6, 0, 3),
		"objects": [
			{"type": "campfire", "pos": Vector2i(3, 1), "hazard": {"dice": "2d6", "damage_type": "fire"}},
			{"type": "crate", "pos": Vector2i(2, 3), "hp": 6, "blocks_movement": true},
			{"type": "crate", "pos": Vector2i(5, 0), "hp": 6, "blocks_movement": true},
			{"type": "barrel", "pos": Vector2i(4, 3), "hp": 5, "blocks_movement": true,
				"explosive": true, "hazard": {"dice": "2d6", "damage_type": "fire"}},
			{"type": "torch", "pos": Vector2i(6, 2)},
		],
		"cover": [Vector2i(1, 3), Vector2i(6, 0)],      # hide tents
		"rough": [Vector2i(3, 0), Vector2i(3, 2)],      # ash and cook-pots
		"palette": "camp",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the treeline" if p.x <= 2 else "the camp",
	}

# Market day. Stalls give cover, the fountain is solid stone, lamps burn on the corners.
static func city_square_board() -> Dictionary:
	return {
		"hexes": _rect(0, 6, 0, 3),
		"objects": [
			{"type": "fountain", "pos": Vector2i(3, 1), "blocks_movement": true},
			{"type": "fountain", "pos": Vector2i(3, 2), "blocks_movement": true},
			{"type": "crate", "pos": Vector2i(5, 2), "hp": 6, "blocks_movement": true},
			{"type": "torch", "pos": Vector2i(0, 2)},
			{"type": "torch", "pos": Vector2i(6, 1)},
		],
		"cover": [Vector2i(1, 0), Vector2i(1, 3), Vector2i(5, 0), Vector2i(5, 3)],  # market stalls
		"rough": [],                                    # cobblestone: palette only
		"palette": "city",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the stalls" if p.x <= 2 else "the square",
	}

static func forest_clearing_board() -> Dictionary:
	var h := _rect(0, 6, 0, 3)
	h.erase(Vector2i(0, 0))
	h.erase(Vector2i(6, 3))
	return {
		"hexes": h,
		"objects": [],
		"cover": [Vector2i(2, 0), Vector2i(1, 2), Vector2i(4, 3), Vector2i(5, 1)],  # trees
		"rough": [Vector2i(2, 1), Vector2i(3, 3), Vector2i(4, 0)],                  # undergrowth
		"palette": "forest",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the treeline" if p.x <= 2 else "the clearing",
	}

# O-biome's two boards, and the reason DEFAULT_THEME could finally die: every
# open-country fight used to be drawn on `forest-clearing` whatever ground the
# band was standing on, so a marsh and a moor were a wood with different foes.
#
# Both are deliberately the same SIZE and carry the same COUNTS as the six that
# came before — three cover, three or four rough, one light source — because the
# first pass of the biome design is flavour-only on purpose. Every knob that
# would make a marsh play differently from a moor (rough density, shelves,
# cover, what is lit) is a real difficulty change wearing a terrain costume, and
# core/scaler.gd's numbers are measured, not eyeballed. What differs here is
# what the pieces ARE, not how many. See docs/expansion-plan.md's biome note for
# the four knobs and what each one actually moves.
#
# The light source is not decoration. core/combat.gd's lit()/can_see() give an
# unlit hex disadvantage to swing into and advantage to be struck from, and most
# monsters have darkvision while the party's edge is ranged — so a dark board is
# a one-sided gift to the foes. A board authored without one is a balance change
# nobody asked for.

# Open country under a wide sky: standing stones, gorse, and a drover's fire at
# the wayside. The board the map's default ground never had.
static func downs_board() -> Dictionary:
	var h := _rect(0, 6, 0, 3)
	h.erase(Vector2i(0, 3))
	h.erase(Vector2i(6, 0))
	return {
		"hexes": h,
		"objects": [{"type": "campfire", "pos": Vector2i(3, 1)}],
		"cover": [Vector2i(1, 1), Vector2i(4, 3), Vector2i(5, 0)],   # standing stones
		"rough": [Vector2i(2, 2), Vector2i(3, 0), Vector2i(5, 3)],   # gorse and tussock
		"palette": "downs",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the low ground" if p.y >= 2 else "the ridge",
	}

# Reedbed and standing water, a bog-lamp burning on a pole where the causeway
# gives out. The one biome that makes content the game already had reachable:
# 18 aquatic beasts no roster could field while forest-clearing was the only
# board that drew beasts.
static func marsh_board() -> Dictionary:
	var h := _rect(0, 6, 0, 3)
	h.erase(Vector2i(0, 0))
	h.erase(Vector2i(6, 3))
	return {
		"hexes": h,
		"objects": [{"type": "lamp", "pos": Vector2i(3, 2)}],
		"cover": [Vector2i(1, 3), Vector2i(4, 0), Vector2i(5, 2)],              # reed banks
		"rough": [Vector2i(2, 1), Vector2i(2, 3), Vector2i(4, 2), Vector2i(5, 1)],  # bog
		"palette": "marsh",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the causeway" if p.y <= 1 else "the shallows",
	}

# Two chambers joined by a crawl, the floor sheeted in ice.
static func frozen_cave_board() -> Dictionary:
	var h := _rect(0, 2, 0, 2)
	h.append(Vector2i(3, 1))
	h.append_array(_rect(4, 6, 0, 2))
	h.append(Vector2i(7, 1))
	h.append(Vector2i(8, 1))
	return {
		"hexes": h,
		"objects": [{"type": "torch", "pos": Vector2i(4, 1)}],
		"cover": [Vector2i(0, 0), Vector2i(6, 2), Vector2i(8, 1)],                  # stalactite columns
		"rough": [Vector2i(1, 1), Vector2i(4, 0), Vector2i(5, 2)],                  # ice
		"palette": "ice",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the outer chamber" if p.x <= 3 else "the deep hollow",
	}

# A tight room: shelves down the walls, stock stacked in the aisle.
static func merchant_shop_board() -> Dictionary:
	return {
		"hexes": _rect(0, 4, 0, 3),
		"objects": [
			{"type": "barrel", "pos": Vector2i(3, 0), "hp": 6, "blocks_movement": true},
			{"type": "barrel", "pos": Vector2i(3, 3), "hp": 6, "blocks_movement": true},
			{"type": "torch", "pos": Vector2i(0, 1)},
		],
		"cover": [Vector2i(4, 0), Vector2i(4, 3), Vector2i(0, 3)],   # shelves
		"rough": [],
		"palette": "shop",
		"reach_melee": REACH_MELEE,
		"region_at": func(p: Vector2i) -> String: return "the counter" if p.x <= 1 else "the back room",
	}

static func party() -> Array:
	var out: Array = []
	for ch in Presets.party():
		out.append(Adapter.to_combatant(ch, "party", START[ch.id]))
	return out

# The demo room's fixed foes. START is the roster, not just the geometry: it has
# always been indexed blindly by every monsters.json id, so the file quietly
# doubled as "the four things standing in the sandbox". T-summon put a fifth
# entry in it — Invoke Duplicity's double, a stat block that is summoned and
# never spawned — and it walked straight into the demo fight, on top of Vera,
# because START had nothing to say about it. The filter is that assumption
# written down.
static func monsters() -> Array:
	var out: Array = []
	for m in Catalog.all("monsters.json"):
		if not START.has(m["id"]):
			continue
		out.append(Adapter.from_monster(m, "foe", START[m["id"]]))
	return out

static func all() -> Array:
	var a = party()
	a.append_array(monsters())
	return a

# --- T7: generated encounters -----------------------------------------
# Where the live party stands when a campaign node drops them into a room.
const PARTY_STARTS := [Vector2i(2, 0), Vector2i(2, 2), Vector2i(1, 1), Vector2i(1, 0)]

# #114: where the party stands when the fight opens — a different cluster of
# four along the low-q edge each fight, off the seed, so the deployment is not
# the same picture every time. The marching order still fills it front-first
# (the two highest-q hexes are the front rank, as PARTY_STARTS' are), and the
# foes still spawn ahead of the front rank (_foe_spots). Falls back to
# PARTY_STARTS on a board too small to offer a cluster.
static func party_starts(b: Dictionary, seed: int) -> Array:
	var blocked: Array = b.get("objects", []).filter(
		func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
	var open: Array = b["hexes"].filter(func(h): return not (h in blocked))
	if open.size() < 8:
		return PARTY_STARTS
	var q0 := 1 << 30
	for h in open:
		q0 = mini(q0, h.x)
	var edge: Array = open.filter(func(h): return h.x <= q0 + 2)
	if edge.is_empty():
		return PARTY_STARTS
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchor: Vector2i = edge[rng.randi() % edge.size()]
	var near: Array = open.duplicate()
	near.sort_custom(func(a, c): return Hex.distance(a, anchor) < Hex.distance(c, anchor))
	var cluster: Array = near.slice(0, 4)
	cluster.sort_custom(func(a, c): return a.x > c.x or (a.x == c.x and a.y < c.y))
	return cluster

# Where the party stands for this spec: the low-q edge as always, or — for a
# breakout — the middle of the board with the foes on both sides. The one
# place scenes/main.gd and the co-op guest ask, so both peers agree.
static func starts_for(spec: Dictionary, b: Dictionary, seed: int) -> Array:
	if String(spec.get("objective", {}).get("kind", "")) == "breakout":
		return middle_starts(b, seed)
	return party_starts(b, seed)

# Open = on the board, not blocked by an object, not in `taken`.
static func _open(b: Dictionary, taken: Array) -> Array:
	var blocked: Array = b.get("objects", []).filter(
		func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
	return b["hexes"].filter(func(h): return not (h in blocked) and not (h in taken))

# party_starts' shape, anchored near the board's centre instead of its low-q edge.
static func middle_starts(b: Dictionary, seed: int) -> Array:
	var open: Array = _open(b, [])
	if open.size() < 8:
		return PARTY_STARTS
	var cx := 0.0
	var cy := 0.0
	for h in open:
		cx += h.x
		cy += h.y
	var mid := Vector2i(roundi(cx / open.size()), roundi(cy / open.size()))
	var near: Array = open.duplicate()
	near.sort_custom(func(a, c): return Hex.distance(a, mid) < Hex.distance(c, mid))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchor: Vector2i = near[rng.randi() % mini(6, near.size())]   # a little seeded jitter, as party_starts has
	near.sort_custom(func(a, c): return Hex.distance(a, anchor) < Hex.distance(c, anchor))
	var cluster: Array = near.slice(0, 4)
	cluster.sort_custom(func(a, c): return a.x > c.x or (a.x == c.x and a.y < c.y))
	return cluster

# The n open hexes nearest the far (high-q) end: the road out of a breakout,
# the treeline a quarry runs for, where a wave comes in. Deterministic order,
# so both co-op peers hold the same hexes.
static func far_hexes(b: Dictionary, taken: Array, n: int) -> Array:
	var open: Array = _open(b, taken)
	open.sort_custom(func(a, c): return a.x > c.x or (a.x == c.x and a.y < c.y))
	return open.slice(0, n)

# The open hex farthest from every party member (ties: higher q, then lower r):
# where a captive is chained.
static func deepest_hex(b: Dictionary, party_c: Array, taken: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := -1
	for h in _open(b, taken):
		var d := 1 << 30
		for c in party_c:
			d = mini(d, Hex.distance(h, c.pos))
		if d > best_d or (d == best_d and (h.x > best.x or (h.x == best.x and h.y < best.y))):
			best_d = d
			best = h
	return best

# The open hex closest to everyone in the party at once: where the carter huddles.
static func huddle_hex(b: Dictionary, party_c: Array, taken: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var best_s := 1 << 30
	for h in _open(b, taken):
		var s := 0
		for c in party_c:
			s += Hex.distance(h, c.pos)
		if s < best_s or (s == best_s and (h.x < best.x or (h.x == best.x and h.y < best.y))):
			best_s = s
			best = h
	return best

# Breakout: foes on both sides of a party standing in the middle — ahead and
# behind alternating, nearest first, never on the road out (`exclude`).
static func surround_spots(b: Dictionary, party_c: Array, exclude: Array) -> Array:
	var taken: Array = party_c.map(func(c): return c.pos)
	var front := -(1 << 30)
	var back := 1 << 30
	for p in taken:
		front = maxi(front, p.x)
		back = mini(back, p.x)
	var open: Array = _open(b, taken + exclude)
	# Bucket by side at a gap; a board too narrow for the full gap on one side
	# takes half of it there — surrounded means both sides, closer if it must be.
	var bucket := func(gap: int) -> Array:
		var ahead: Array = []
		var behind: Array = []
		var rest: Array = []
		for h in open:
			var d := 99
			for p in taken:
				d = mini(d, Hex.distance(h, p))
			if d >= gap and h.x > front:
				ahead.append([d, h])
			elif d >= gap and h.x < back:
				behind.append([d, h])
			else:
				rest.append([-d, h])   # overflow: the least-bad remaining hexes, as _foe_spots does
		return [ahead, behind, rest]
	var sides: Array = bucket.call(SPAWN_GAP)
	if sides[0].is_empty() or sides[1].is_empty():
		sides = bucket.call(SPAWN_GAP / 2)
	var ahead: Array = sides[0]
	var behind: Array = sides[1]
	var rest: Array = sides[2]
	ahead.sort_custom(func(a, c): return a[0] < c[0])
	behind.sort_custom(func(a, c): return a[0] < c[0])
	rest.sort_custom(func(a, c): return a[0] < c[0])
	var out: Array = []
	while not ahead.is_empty() or not behind.is_empty():
		if not ahead.is_empty():
			out.append(ahead.pop_front()[1])
		if not behind.is_empty():
			out.append(behind.pop_front()[1])
	for e in rest:
		out.append(e[1])
	return out

# Hunt: the strongest foe is the quarry, and it trades places with whichever foe
# stands nearest the party — it has the whole board to cross, and the party has
# a chance to close before it does.
static func mark_quarry(foes: Array, party_c: Array) -> void:
	if foes.is_empty():
		return
	var quarry = foes[0]
	for f in foes:
		if float(Power.estimate(f)["score"]) > float(Power.estimate(quarry)["score"]):
			quarry = f
	quarry.statuses["quarry"] = true
	var nearest = foes[0]
	var nd := 1 << 30
	for f in foes:
		var d := 1 << 30
		for c in party_c:
			d = mini(d, Hex.distance(f.pos, c.pos))
		if d < nd:
			nd = d
			nearest = f
	var p: Vector2i = quarry.pos
	quarry.pos = nearest.pos
	nearest.pos = p

const SPAWN_GAP := 6    # no foe spawns closer than this to any party member
# T36/T37: measured lever, not a guess -- 150-seed sweeps found this the best
# single difficulty knob (+6.6 win-rate points over gap 3, no fight-length
# cost) with current board sizes (5-9 hexes wide) saturating right around
# here, so going further needs bigger boards first. Ranged-attack usage is
# flat under every gap tested (roster composition, not geometry -- see
# docs/expansion-plan.md's T35/T36/T37 entries) -- this is a difficulty
# tune, not a fix for that.

# Difficulty multiplier -> stat deltas (T8 picks the multiplier, this owns the shape).
const AC_PER_MULT := 3
const ATK_PER_MULT := 4
const DMG_PER_MULT := 4

# XP/gold per point of power.estimate() score. Grull ~= 200 XP, a goblin ~= 50,
# which is roughly the SRD's numbers for the Sunken Shrine roster.
const XP_PER_POWER := 4.0
const GOLD_PER_POWER := 0.6

# spec: {"monsters": [{"id": String, "count": int, "mult": float (optional, default
# spec.mult or 1.0)}], "seed": int (optional — omit for a random fight),
# "named": {monster_id: "Name"} (optional — the first spawn of that id is
# "Name the <Species>", the pit's champion; the rest keep EnemyNames' own)}.
# `mult` is T8's difficulty knob; it scales the spawned instance, never
# data/monsters.json.
static func build(spec: Dictionary, party_combatants: Array, board: Dictionary = {}) -> Combat:
	var b: Dictionary = board if not board.is_empty() else board_for(String(spec.get("theme", "")), int(spec.get("seed", 0)))
	if spec.get("night", false):
		b["night"] = true   # #85
	var o: Dictionary = spec.get("objective", {}).duplicate(true)
	var kind := String(o.get("kind", ""))
	var all_c: Array = party_combatants.duplicate()
	# The road out / the treeline: the far edge, held free of spawns. Never
	# narrower than the party — a breakout needs a distinct hex for every
	# conscious hero.
	var exit: Array = far_hexes(b, [], maxi(Objectives.EXIT_W, party_combatants.size())) if kind in ["breakout", "hunt"] else []
	var spots: Array = surround_spots(b, party_combatants, exit) if kind == "breakout" else _foe_spots(b, party_combatants)
	if kind == "hunt":
		spots = spots.filter(func(h): return not (h in exit))
	var i := 0
	# A spawn's copy number is counted per ID across the WHOLE spec, not per
	# entry. Two entries may legitimately name the same monster — a boss and an
	# escort of its own kin, when the faction has only that one creature in
	# budget (core/scaler.gd's boss_for), or a pack that authors two groups of
	# one id — and per-entry numbering gave both an unsuffixed `id`, so the
	# fight carried two combatants answering to the same name. Everything in
	# core/combat.gd that looks a combatant up by id (statuses, concentration,
	# a target list) would then have found whichever came first.
	#
	# Unchanged for every spec that names an id once, which is all of them until
	# now: the first copy of a lone single-count entry still spawns unsuffixed,
	# and a count > 1 entry still numbers 1..n.
	var copies := {}
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else PARTY_STARTS[0]
			var seen: int = int(copies.get(e["id"], 0))
			copies[e["id"]] = seen + 1
			var c = spawn(e["id"], mult, "foe", pos,
				seen + 1 if (count > 1 or seen > 0) else 0, e.get("features", []))
			if c != null:
				if n == 0 and spec.get("named", {}).has(e["id"]):
					c.cname = "%s the %s" % [spec["named"][e["id"]], Catalog.monster(e["id"])["cname"]]
				all_c.append(c)
			i += 1
	var foes: Array = all_c.filter(func(c): return c.team == "foe")
	match kind:
		"rescue":
			all_c.append(Objectives.captive(deepest_hex(b, party_combatants, all_c.map(func(c): return c.pos))))
		"escort":
			all_c.append(Objectives.carter(huddle_hex(b, party_combatants, all_c.map(func(c): return c.pos)), Objectives.party_level(party_combatants)))
		"hunt":
			mark_quarry(foes, party_combatants)
	var RNG = load("res://core/rng.gd")
	var sd: int = int(spec.get("seed", 0))
	var cb := Combat.new(RNG.new(sd if sd > 0 else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)),
		all_c, b)
	cb.purse = float(spec.get("purse", 1.0))
	if kind != "":
		if kind in ["breakout", "hunt"]:
			o["exit"] = exit
		cb.objective = o
		cb.log.append(Objectives.brief(o))
	return cb

# `extra_features` (T18) bolts feature ids onto this one spawn — how a boss gets a
# second attack out of the existing verb machinery instead of a second stat block.
static func spawn(id: String, mult: float, team: String, pos: Vector2i, n := 0, extra_features: Array = []):
	var m: Dictionary = Catalog.monster(id)
	if m.is_empty():
		return null
	if not extra_features.is_empty():
		m = m.duplicate(true)
		m["features"] = m.get("features", []) + extra_features
	var c = Adapter.from_monster(m, team, pos)
	c.src_id = id
	if n > 0:
		c.id = "%s-%d" % [id, n]
	# Named humanoid foes ("Grix the Goblin") instead of a bare species label —
	# deterministic per (monster, copy, spawn hex) so a reload of the same seed
	# still shows the same names.
	if team == "foe" and String(m.get("type", "")) == "humanoid":
		var who := EnemyNames.name_for(String(m.get("faction", "")), "%s|%d|%s" % [id, n, pos])
		c.cname = "%s the %s" % [who, c.cname]
	elif n > 0:
		c.cname = "%s %d" % [c.cname, n]
	if not is_equal_approx(mult, 1.0):
		_scale(c, mult)
	return c

static func _scale(c, mult: float) -> void:
	var d := mult - 1.0
	c.max_hp = maxi(1, roundi(c.max_hp * mult))
	c.hp = c.max_hp
	c.ac = maxi(5, c.ac + roundi(d * AC_PER_MULT))
	c.atk_bonus += roundi(d * ATK_PER_MULT)
	# A scaled caster's spells get harder to shrug off at the same rate its
	# swings get harder to dodge (BG3 does the same: +2 to hit and +2 DC on
	# Tactician). A monster with no save DC has nothing to scale.
	if c.save_dc > 0:
		c.save_dc += roundi(d * ATK_PER_MULT)
	var bump := roundi(d * DMG_PER_MULT)
	c.damage = _bump(c.damage, bump)
	for a in c.attacks:
		a["to_hit"] = int(a.get("to_hit", c.atk_bonus)) + roundi(d * ATK_PER_MULT)
		a["dmg_bonus"] = int(a.get("dmg_bonus", 0)) + bump
		a["notation"] = _bump(a.get("notation", c.damage), bump)

static func _bump(notation: String, by: int) -> String:
	var Dice = load("res://core/dice.gd")
	var p: Dictionary = Dice.parse(notation)
	var m: int = int(p["mod"]) + by
	return "%dd%d%s" % [p["count"], p["sides"], ("+%d" % m) if m > 0 else (str(m) if m < 0 else "")]

# Free hexes far enough from the party, nearest-first so foes come at you rather
# than camping the far cover.
static func _foe_spots(b: Dictionary, party_c: Array) -> Array:
	var taken: Array = party_c.map(func(c): return c.pos)
	var blocked: Array = b.get("objects", []).filter(
		func(o): return o.get("blocks_movement", false)).map(func(o): return o["pos"])
	# The party enters from the low-q end, so "ahead" is past its front rank:
	# a foe a gap away but behind the party is the ground's shape, not an ambush.
	var front := -(1 << 30)
	for p in taken:
		front = maxi(front, p.x)
	var out: Array = []
	var behind: Array = []
	var far: Array = []
	for h in b["hexes"]:
		if h in taken or h in blocked:
			continue
		var d := 99
		for p in taken:
			d = mini(d, Hex.distance(h, p))
		if d >= SPAWN_GAP:
			(out if h.x > front else behind).append([d, h])
		else:
			far.append([d, h])
	out.sort_custom(func(a, c): return a[0] < c[0])
	behind.sort_custom(func(a, c): return a[0] < c[0])
	far.sort_custom(func(a, c): return a[0] > c[0])
	out.append_array(behind)   # only once the ground ahead is full
	out.append_array(far)      # overflow: the least-bad remaining hexes
	return out.map(func(e): return e[1])

# --- T39: surprise ----------------------------------------------------
# One group Stealth check at the top of the fight: the party's best Stealth
# (d20 + bonus, same shape as campaign.gd's opportunity_check) against the
# average foe passive Perception. Beat it and the party is unseen — a surprise
# round, see combat.gd. A node the party already scouted (T30) succeeds
# outright: scouting must never be worse than not scouting. A miss costs
# nothing. Rolls on its own stream derived from the combat seed (same trick as
# barks) so the fight itself rolls identically whether or not this is called.
const PASS_WITHOUT_TRACE := "pass-without-trace"
const PASS_WITHOUT_TRACE_BONUS := 10
static func surprise_check(cb: Combat, scouted_ahead := false) -> bool:
	var foes: Array = cb.team_of("foe")
	var heroes: Array = cb.team_of("party")
	if foes.is_empty() or heroes.is_empty():
		return false
	if scouted_ahead:
		cb.log.append("The ground was read ahead of time — the party comes in unseen.")
		cb.begin_surprise_round()
		return true
	var bonus := -99
	var who = heroes[0]
	for c in heroes:
		if int(c.stealth) > bonus:
			bonus = int(c.stealth)
			who = c
	# Pass Without Trace in the party's repertoire: the spell's +10, the same
	# "a known spell changes the roll" hook the road uses (core/party.gd caster_of).
	var veiled: bool = heroes.any(func(c): return PASS_WITHOUT_TRACE in c.spell_ids)
	if veiled:
		bonus += PASS_WITHOUT_TRACE_BONUS
	var pp := 0
	for c in foes:
		pp += int(c.passive_perception)
	var dc: int = roundi(float(pp) / foes.size())
	var Dice = load("res://core/dice.gd")
	var RNG = load("res://core/rng.gd")
	var nat: int = int(Dice.d20(RNG.new((cb.rng.seed_value ^ 0x5117EA17) & 0xFFFFFFFF))["nat"])
	if veiled:
		cb.log.append("A veil of shadow goes with them (Pass Without Trace, +%d)." % PASS_WITHOUT_TRACE_BONUS)
	if nat + bonus < dc:
		cb.log.append("%s leads them in badly (Stealth %d+%d vs %d) — they are seen coming."
			% [who.cname, nat, bonus, dc])
		return false
	cb.log.append("%s leads them in quietly (Stealth %d+%d vs %d)." % [who.cname, nat, bonus, dc])
	cb.begin_surprise_round()
	return true

# After is_over(): persist the fight to the Characters and report the spoils.
# `party` is a core/party.gd or a plain Array of Character. HP/pools/slots are
# written back here; xp/gold/loot are reported, not banked — T5 does that.
static func resolve_outcome(cb: Combat, party) -> Dictionary:
	var chars: Array = []
	if party is Array:
		chars = party
	elif party != null and party.has_method("party_characters"):
		chars = party.party_characters()
	Adapter.write_back_all(cb.team_of("party"), chars)

	var power := 0.0
	var roster := 0.0
	var loot: Array = []
	var kills: Array[String] = []
	for c in cb.team_of("foe"):
		roster += float(Power.estimate(c)["score"])
		if not c.is_dead() or c.has("escaped"):   # the quarry that got away took its loot with it
			continue
		kills.append(c.src_id)
		power += float(Power.estimate(c)["score"])
		loot.append_array(Catalog.monster(c.src_id).get("loot", []))   # a pack author's explicit drops, always
	var deaths: Array[String] = []
	for c in cb.team_of("party"):
		if c.is_dead() and c.sheet != null:   # a faded summon is not a fallen member
			deaths.append(c.id)
	var res: String = cb.outcome()
	# On top of anything hand-authored: what the dead were actually carrying.
	# Not one of the 316 bestiary entries declares a `loot` key, so before
	# core/loot.gd this array was always empty and a won fight paid in gold and
	# XP and nothing you could hold. Rolled on the fight's own RNG, so the drops
	# replay with the seed; only on a win, because a wipe does not loot the room.
	if res == "Victory":
		loot.append_array(Loot.for_kills(kills, cb.rng))
		# "We came through that together": every member still on their feet
		# warms a little to every other who was (PartyOpinion.FOUGHT_BESIDE).
		# cb.party is the hooks' party too, and null in the sandbox and the
		# NPC scraps; a summon or a carter has no sheet and is not in it.
		if cb.party != null:
			PartyOpinion.fought_beside(cb.party, cb.team_of("party").filter(
				func(c): return c.conscious() and c.sheet != null).map(func(c): return c.id))
	_score_fight(cb, res == "Victory")
	# Spec §4: an objective done pays half the whole roster's worth in XP on
	# top of the kills — dead or standing, because holding against them,
	# slipping past them or dropping their leader is the deed. Gold and loot
	# stay kills-only: a foe you did not kill did not drop anything.
	var done: bool = res == "Victory" and cb.objective_result()
	var bonus: int = roundi(roster * XP_PER_POWER * Objectives.BONUS_XP_SHARE) if done else 0
	return {
		"outcome": "Victory" if res == "Victory" else "Defeat",   # a round-cap timeout is not a win
		"xp": roundi(power * XP_PER_POWER) + bonus,
		"gold": roundi(power * GOLD_PER_POWER * cb.purse),
		"loot": loot,
		"deaths": deaths,
		"kills": kills,   # source monster ids, for T9's kill-count quests
		"downed": cb.downed.keys(),   # T19: party ids that hit 0 HP, even if they got back up
		"rounds": cb.round_num,       # world.gd bills the clock an hour a round
		"objective": {"kind": cb.objective_kind(), "done": done, "xp": bonus},
	}


# T19 — the achievements that are about a whole fight rather than one blow.
# Here rather than in combat.gd because this is the one function every real
# fight ends in (core/world_battle.gd's NPC-vs-NPC scraps never call it, and
# carry cb.tracked = false besides).
static func _score_fight(cb, won: bool) -> void:
	if not cb.tracked:
		return
	if not won:
		Ach.unlock("first_wipe")
		return
	Ach.bump("wins")
	if cb.round_num <= 1:
		Ach.unlock("one_round")
	if cb.round_num >= 15:
		Ach.unlock("long_fight")
	if cb.unseen:
		Ach.unlock("surprise_win")
	if cb.ambushed:
		Ach.unlock("ambush_win")
	# The heroes, not the wolf one of them called: a summon carries the
	# monsters.json id it was spawned from, a character carries nothing. A
	# bystander carries nothing either, but it is not a hero — a scratched
	# carter must not spoil "whole", and all_down must stay reachable.
	var heroes: Array = cb.team_of("party").filter(func(c): return String(c.src_id) == "" and not c.has("bystander"))
	if heroes.is_empty():
		return
	var whole := true
	var all_down := heroes.size() > 1
	for c in heroes:
		if c.hp < c.max_hp:
			whole = false
		if not cb.downed.has(c.id):
			all_down = false
	if whole and cb.downed.is_empty():
		Ach.unlock("untouched")
	# Everybody hit the floor and the party still took the room.
	if all_down:
		Ach.unlock("all_down_win")
