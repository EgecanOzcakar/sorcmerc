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
	"frozen-cave", "merchant-shop"]

static func board_for(theme: String) -> Dictionary:
	match theme:
		"goblin-camp": return goblin_camp_board()
		"city-square": return city_square_board()
		"forest-clearing": return forest_clearing_board()
		"frozen-cave": return frozen_cave_board()
		"merchant-shop": return merchant_shop_board()
	return shrine_board()

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

static func monsters() -> Array:
	var out: Array = []
	for m in Catalog.all("monsters.json"):
		out.append(Adapter.from_monster(m, "foe", START[m["id"]]))
	return out

static func all() -> Array:
	var a = party()
	a.append_array(monsters())
	return a

# --- T7: generated encounters -----------------------------------------
# Where the live party stands when a campaign node drops them into a room.
const PARTY_STARTS := [Vector2i(2, 0), Vector2i(2, 2), Vector2i(1, 1), Vector2i(1, 0)]
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
# spec.mult or 1.0)}], "seed": int (optional — omit for a random fight)}.
# `mult` is T8's difficulty knob; it scales the spawned instance, never
# data/monsters.json.
static func build(spec: Dictionary, party_combatants: Array, board: Dictionary = {}) -> Combat:
	var b: Dictionary = board if not board.is_empty() else board_for(String(spec.get("theme", "")))
	var all_c: Array = party_combatants.duplicate()
	var spots := _foe_spots(b, party_combatants)
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else PARTY_STARTS[0]
			var c = spawn(e["id"], mult, "foe", pos, n + 1 if count > 1 else 0, e.get("features", []))
			if c != null:
				all_c.append(c)
			i += 1
	var RNG = load("res://core/rng.gd")
	var sd: int = int(spec.get("seed", 0))
	return Combat.new(RNG.new(sd if sd > 0 else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)),
		all_c, b)

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
	var out: Array = []
	var far: Array = []
	for h in b["hexes"]:
		if h in taken or h in blocked:
			continue
		var d := 99
		for p in taken:
			d = mini(d, Hex.distance(h, p))
		if d >= SPAWN_GAP:
			out.append([d, h])
		else:
			far.append([d, h])
	out.sort_custom(func(a, c): return a[0] < c[0])
	far.sort_custom(func(a, c): return a[0] > c[0])
	out.append_array(far)   # overflow: the least-bad remaining hexes
	return out.map(func(e): return e[1])

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
	var loot: Array = []
	var kills: Array[String] = []
	for c in cb.team_of("foe"):
		if not c.is_dead():
			continue
		kills.append(c.src_id)
		power += float(Power.estimate(c)["score"])
		loot.append_array(Catalog.monster(c.src_id).get("loot", []))
	var deaths: Array[String] = []
	for c in cb.team_of("party"):
		if c.is_dead():
			deaths.append(c.id)
	var res: String = cb.outcome()
	return {
		"outcome": "Victory" if res == "Victory" else "Defeat",   # a round-cap timeout is not a win
		"xp": roundi(power * XP_PER_POWER),
		"gold": roundi(power * GOLD_PER_POWER),
		"loot": loot,
		"deaths": deaths,
		"kills": kills,   # source monster ids, for T9's kill-count quests
		"downed": cb.downed.keys(),   # T19: party ids that hit 0 HP, even if they got back up
	}
