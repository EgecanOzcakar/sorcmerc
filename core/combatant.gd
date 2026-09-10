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

# kit
var sneak_attack: String = ""       # e.g. "2d6"
var nimble_escape: bool = false
var surprise_attack: String = ""    # e.g. "2d6"
var second_wind: String = ""        # e.g. "1d10+3"
var action_surge: bool = false
var cunning_action: bool = false
var spells: Array = []              # "burning_hands" | "healing_word" | "sacred_flame"
var attacks: Array = []             # from the sheet; [0] backs atk_bonus/damage
var features: Dictionary = {}       # feature_id -> true
var verbs: Array = []               # resolved combat verbs (F3)
var pools: Dictionary = {}          # pool_id -> {cur, max, regen}
var spell_ids: Array[String] = []   # castable-now spells
var slots: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var econ: Dictionary = {}           # per-turn action economy (F3)
var sheet = null                    # ResolvedCharacter; null for monsters

# Read-only-ish aliases so combat.gd keeps compiling until F3 deletes the call sites.
var dex_save: int:
	get: return int(saves.get("dex", 0))
	set(v): saves["dex"] = v
var slots1: int:
	get: return slots[0]
	set(v): slots[0] = v
var slots2: int:
	get: return slots[1]
	set(v): slots[1] = v

# runtime
var statuses: Dictionary = {}       # "prone" | "dodging" | "hidden" | "down" | "stable" | "dead" | "reacted"
var death_s: int = 0
var death_f: int = 0
var used_second_wind: bool = false
var used_action_surge: bool = false
var has_acted: bool = false
var init_roll: int = 0

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
		"atk_bonus","damage","ranged","atk_range","crit_range","save_dc","dex_save","athletics",
		"acro","stealth","passive_perception","sneak_attack","nimble_escape",
		"surprise_attack","second_wind","action_surge","cunning_action","sheet",
	]:
		c.set(prop, get(prop))
	c.spells = spells.duplicate()
	c.saves = saves.duplicate()
	c.slots = slots.duplicate()
	c.attacks = attacks.duplicate(true)
	c.features = features.duplicate()
	c.verbs = verbs.duplicate(true)
	c.pools = pools.duplicate(true)
	c.spell_ids = spell_ids.duplicate()
	c.econ = econ.duplicate(true)
	return c
