# Plain data + runtime state for one creature. No engine/node dependency.
extends RefCounted

var id: String
var cname: String
var team: String  # "party" | "foe"

var ac: int
var max_hp: int
var hp: int
var init_mod: int = 0
var speed: int = 4          # move points (hexes) per turn
var pos: Vector2i = Vector2i.ZERO

# attack
var atk_bonus: int = 0
var damage: String = "1d4"
var ranged: bool = false
var atk_range: int = 1     # hexes; melee = 1, shortbow set in encounter.gd
var crit_range: int = 20  # Vera crits on 19

# checks / spellcasting
var save_dc: int = 0
var saves: Dictionary = {}          # "str" -> total save bonus
var athletics: int = 0
var acro: int = 0
var stealth: int = 0
var passive_perception: int = 10

# kit — everything a creature can do is a verb; nothing here names a class.
var attacks: Array = []             # from the sheet; [0] backs atk_bonus/damage
var features: Dictionary = {}       # feature_id -> true
var verbs: Array = []               # fully numeric combat verbs, built by adapter.gd
var pools: Dictionary = {}          # pool_id -> {cur, max, regen}
var spell_ids: Array[String] = []   # castable-now spells
var slots: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var sheet = null                    # ResolvedCharacter; null for monsters

# runtime
var statuses: Dictionary = {}       # "prone" | "dodging" | "hidden" | "down" | "stable" | "dead"
var death_s: int = 0
var death_f: int = 0
var has_acted: bool = false
var init_roll: int = 0

# Per-turn action economy (spec §7). Lives here, not on Combat, because a reaction
# is spent between your own turns. combat.begin_turn() calls new_turn().
var econ: Dictionary = {
	"action": 1, "bonus": 1, "reaction": 1, "move_left": 0,
	"attacks_left": 0, "attacks_per_action": 1, "used": {}, "cast_bonus_spell": false,
}

const TURN_STATUSES := ["dodging", "disengaged", "helped", "reckless"]

func new_turn() -> void:
	econ = {
		"action": 1, "bonus": 1, "reaction": 1, "move_left": speed,
		"attacks_left": 0, "attacks_per_action": 1, "used": {}, "cast_bonus_spell": false,
	}
	for v in verbs:
		if v["kind"] == "attacks_per_action":
			econ["attacks_per_action"] = maxi(int(econ["attacks_per_action"]), int(v["value"]))
	for s in TURN_STATUSES:
		statuses.erase(s)

func verb(id: String) -> Dictionary:
	for v in verbs:
		if v["id"] == id:
			return v
	return {}

func pool_left(id: String) -> int:
	return int(pools[id]["cur"]) if pools.has(id) else 0

func has(s: String) -> bool:
	return statuses.has(s)

func is_dead() -> bool:
	return statuses.has("dead")

func is_down() -> bool:
	return statuses.has("down") and not statuses.has("dead")

func is_stable() -> bool:
	return statuses.has("stable")

# Can act, be targeted normally, and counts toward its team still being in the fight.
func conscious() -> bool:
	return hp > 0 and not statuses.has("down") and not statuses.has("dead")

func clone() -> RefCounted:
	var c = get_script().new()
	for prop in [
		"id","cname","team","ac","max_hp","hp","init_mod","speed","pos",
		"atk_bonus","damage","ranged","atk_range","crit_range","save_dc","athletics",
		"acro","stealth","passive_perception","sheet",
	]:
		c.set(prop, get(prop))
	c.saves = saves.duplicate()
	c.slots = slots.duplicate()
	c.attacks = attacks.duplicate(true)
	c.features = features.duplicate()
	c.verbs = verbs.duplicate(true)
	c.pools = pools.duplicate(true)
	c.spell_ids = spell_ids.duplicate()
	c.econ = econ.duplicate(true)
	return c
