# The Sunken Shrine — the one hand-authored MVP encounter (combat-design.md §7).
# Numbers live here and nowhere else; tune by editing this file.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")

# --- ranges (hexes) — tune here ---------------------------------------
const REACH_MELEE := 1
const RANGE_SHORTBOW := 6
const CONE_BURNING_HANDS := 2        # wedge length
const RANGE_SPELL_LONG := 12         # sacred flame / healing word — whole map

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
	return {
		"hexes": _room(),
		"brazier": BRAZIER,
		"cover": [Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2)],  # the Alcove
		"rough": [Vector2i(4, 1), Vector2i(6, 1)],                  # scorched ground either side of the brazier
		# The turn resolver reads these off the board rather than preloading this file,
		# so T7/T8 can hand it a generated encounter instead.
		"reach_melee": REACH_MELEE,
		"cone_burning_hands": CONE_BURNING_HANDS,
		"region_at": region_at,
	}

static func region_at(p: Vector2i) -> String:
	if p.x <= 3:
		return "Threshold"
	if p.x <= 6:
		return "Brazier Hall"
	return "Alcove"

static func _make(d: Dictionary):
	var c = Combatant.new()
	for k in d:
		c.set(k, d[k])
	c.hp = d.get("hp", d["max_hp"])
	return c

static func party() -> Array:
	return [
		_make({
			"id": "vera", "cname": "Vera Kord", "team": "party",
			"ac": 18, "max_hp": 28, "init_mod": 0, "pos": Vector2i(2, 0), "speed": 4,
			"atk_bonus": 5, "damage": "1d8+3", "crit_range": 19,
			"athletics": 5, "dex_save": 1,
			"second_wind": "1d10+3", "action_surge": true,
		}),
		_make({
			"id": "pike", "cname": "Pike Sallow", "team": "party",
			"ac": 15, "max_hp": 21, "init_mod": 3, "pos": Vector2i(2, 2), "speed": 5,
			"atk_bonus": 5, "damage": "1d6+3", "ranged": true, "atk_range": RANGE_SHORTBOW,
			"sneak_attack": "2d6", "cunning_action": true,
			"stealth": 7, "acro": 5, "dex_save": 3, "passive_perception": 12,
		}),
		_make({
			"id": "ilsa", "cname": "Ilsa Vane", "team": "party",
			"ac": 16, "max_hp": 22, "init_mod": 1, "pos": Vector2i(1, 1), "speed": 4,
			"atk_bonus": 3, "damage": "1d6+1",
			"save_dc": 13, "dex_save": 1,
			"spells": ["burning_hands", "healing_word", "sacred_flame"],
			"slots1": 4, "slots2": 2,
		}),
	]

static func monsters() -> Array:
	return [
		_make({
			"id": "grull", "cname": "Grull", "team": "foe",
			"ac": 16, "max_hp": 27, "init_mod": 2, "pos": Vector2i(4, 1), "speed": 4,
			"atk_bonus": 4, "damage": "2d8+2", "athletics": 6, "acro": 2, "dex_save": 2,
			"surprise_attack": "2d6",
		}),
		_make({
			"id": "snik", "cname": "Snik", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "pos": Vector2i(4, 0), "speed": 5,
			"atk_bonus": 4, "damage": "1d6+2", "acro": 4, "dex_save": 2,
			"nimble_escape": true, "stealth": 6,
		}),
		_make({
			"id": "vess", "cname": "Vess", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "pos": Vector2i(5, 0), "speed": 5,
			"atk_bonus": 4, "damage": "1d6+2", "acro": 4, "dex_save": 2,
			"nimble_escape": true, "stealth": 6,
		}),
		_make({
			"id": "kritch", "cname": "Kritch", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "pos": Vector2i(7, 1), "speed": 5,
			"atk_bonus": 4, "damage": "1d6+2", "ranged": true, "atk_range": RANGE_SHORTBOW,
			"acro": 4, "dex_save": 2, "nimble_escape": true, "stealth": 6,
		}),
	]

static func all() -> Array:
	var a = party()
	a.append_array(monsters())
	return a
