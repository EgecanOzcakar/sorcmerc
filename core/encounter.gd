# The Sunken Shrine — the one hand-authored MVP encounter (combat-design.md §7).
# Numbers live here and nowhere else; tune by editing this file.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Presets = preload("res://core/presets.gd")
const Combat = preload("res://core/combat.gd")
const Hex = preload("res://core/hex.gd")
const Power = preload("res://core/rules/power.gd")

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

# Same dict; named so build()'s `board` parameter can still reach the default.
static func shrine_board() -> Dictionary:
	return {
		"hexes": _room(),
		"brazier": BRAZIER,
		"cover": [Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2)],  # the Alcove
		"rough": [Vector2i(4, 1), Vector2i(6, 1)],                  # scorched ground either side of the brazier
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
const SPAWN_GAP := 3    # no foe spawns closer than this to any party member

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
	var b: Dictionary = board if not board.is_empty() else shrine_board()
	var all_c: Array = party_combatants.duplicate()
	var spots := _foe_spots(b, party_combatants)
	var i := 0
	for e in spec.get("monsters", []):
		var count: int = maxi(1, int(e.get("count", 1)))
		var mult: float = float(e.get("mult", spec.get("mult", 1.0)))
		for n in count:
			var pos: Vector2i = spots[i] if i < spots.size() else PARTY_STARTS[0]
			var c = spawn(e["id"], mult, "foe", pos, n + 1 if count > 1 else 0)
			if c != null:
				all_c.append(c)
			i += 1
	var RNG = load("res://core/rng.gd")
	var sd: int = int(spec.get("seed", 0))
	return Combat.new(RNG.new(sd if sd > 0 else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)),
		all_c, b)

static func spawn(id: String, mult: float, team: String, pos: Vector2i, n := 0):
	var m: Dictionary = Catalog.monster(id)
	if m.is_empty():
		return null
	var c = Adapter.from_monster(m, team, pos)
	c.src_id = id
	if n > 0:
		c.id = "%s-%d" % [id, n]
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
	var out: Array = []
	var far: Array = []
	for h in b["hexes"]:
		if h in taken:
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
	}
