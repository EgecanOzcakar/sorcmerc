# The Sunken Shrine — the one hand-authored MVP encounter (combat-design.md §7).
# Numbers live here and nowhere else; tune by editing this file.
extends RefCounted

const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Presets = preload("res://core/presets.gd")

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
