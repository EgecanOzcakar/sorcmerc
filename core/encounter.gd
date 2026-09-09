# The Sunken Shrine — the one hand-authored MVP encounter (combat-design.md §7).
# Numbers live here and nowhere else; tune by editing this file.
extends RefCounted

const Combatant = preload("res://core/combatant.gd")

const ZONE_THRESHOLD := 0
const ZONE_BRAZIER := 1
const ZONE_ALCOVE := 2

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
			"ac": 18, "max_hp": 28, "init_mod": 0, "zone": ZONE_THRESHOLD,
			"atk_bonus": 5, "damage": "1d8+3", "crit_range": 19,
			"athletics": 5, "dex_save": 1,
			"second_wind": "1d10+3", "action_surge": true,
		}),
		_make({
			"id": "pike", "cname": "Pike Sallow", "team": "party",
			"ac": 15, "max_hp": 21, "init_mod": 3, "zone": ZONE_THRESHOLD,
			"atk_bonus": 5, "damage": "1d6+3", "ranged": true,
			"sneak_attack": "2d6", "cunning_action": true,
			"stealth": 7, "acro": 5, "dex_save": 3, "passive_perception": 12,
		}),
		_make({
			"id": "ilsa", "cname": "Ilsa Vane", "team": "party",
			"ac": 16, "max_hp": 22, "init_mod": 1, "zone": ZONE_THRESHOLD,
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
			"ac": 16, "max_hp": 27, "init_mod": 2, "zone": ZONE_BRAZIER,
			"atk_bonus": 4, "damage": "2d8+2", "athletics": 6, "acro": 2, "dex_save": 2,
			"surprise_attack": "2d6",
		}),
		_make({
			"id": "snik", "cname": "Snik", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "zone": ZONE_BRAZIER,
			"atk_bonus": 4, "damage": "1d6+2", "acro": 4, "dex_save": 2,
			"nimble_escape": true, "stealth": 6,
		}),
		_make({
			"id": "vess", "cname": "Vess", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "zone": ZONE_BRAZIER,
			"atk_bonus": 4, "damage": "1d6+2", "acro": 4, "dex_save": 2,
			"nimble_escape": true, "stealth": 6,
		}),
		_make({
			"id": "kritch", "cname": "Kritch", "team": "foe",
			"ac": 15, "max_hp": 7, "init_mod": 2, "zone": ZONE_ALCOVE,
			"atk_bonus": 4, "damage": "1d6+2", "ranged": true, "acro": 4, "dex_save": 2,
			"nimble_escape": true, "stealth": 6,
		}),
	]

static func all() -> Array:
	var a = party()
	a.append_array(monsters())
	return a
