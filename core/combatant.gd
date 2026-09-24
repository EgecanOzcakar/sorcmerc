# Plain data + runtime state for one creature. No engine/node dependency.
extends RefCounted

var id: String
var src_id: String   # monsters.json id this was spawned from ("" for heroes)
var cname: String
var short := ""   # what the initiative bar shows; "" = the first word of cname

func short_name() -> String:
	return short if short != "" else cname.split(" ")[0]
var team: String  # "party" | "foe"

var ac: int
var max_hp: int
var hp: int
var temp_hp: int = 0       # a buffer in front of hp; never healed, never stacks (RAW)
var init_mod: int = 0
var speed: int = 4          # move points (hexes) per turn
var pos: Vector2i = Vector2i.ZERO
var size: String = "Medium"  # bestiary.json's; Push spares Huge and bigger

# attack
var atk_bonus: int = 0
var damage: String = "1d4"
var ranged: bool = false
# T9z: bestiary.json carries these on the monster itself (no attacks[] entry,
# just "bite"/"claw" + a damage type). Declared here so Adapter.from_monster's
# generic `c.set(k, v)` copy actually keeps them — Object.set() on a property a
# script doesn't declare is a silent no-op, which is why they were dropped
# before. core/weapon_sfx.gd reads them to pick a natural-attack sound.
var damage_type: String = ""
var attack_name: String = ""

# T94 — defences data/bestiary.json has carried on all 316 entries since F1b and
# the engine threw away: `Adapter.from_monster` copies every key with a generic
# `c.set(k, v)`, and Object.set() on a property no script declares is a silent
# no-op (the same trap the damage_type/attack_name comment above records). So
# every fire immunity, every undead poison immunity and every charm immunity in
# the catalog resolved to "takes it in full" until these four lines existed.
# Damage type ids, lowercase, normalised by Adapter._damage_types(); `cond_immune`
# holds conditions.json ids, which combat.apply_condition checks.
var resist: Array = []
var immune: Array = []
var vulnerable: Array = []
var cond_immune: Array = []
var atk_range: int = 1     # hexes; melee = 1, shortbow set in encounter.gd
var reach: int = 1         # melee reach in hexes: 1 (5 ft), 2 for a reach weapon (10 ft)
var crit_range: int = 20  # Vera crits on 19
var init_adv := false      # advantage on the initiative roll (Assassinate, Dread Ambusher)
# Unarmed Strike's DC (2024 Shove / Grapple): 8 + STR mod + PB. Heroes read
# both off the sheet; a monster's PB comes off its CR (adapter.from_monster).
var str_mod: int = 0
var pb: int = 2

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
var darkvision := false             # #85: sees an unlit hex as lit (core/combat.gd lit()/can_see())
var verbs: Array = []               # fully numeric combat verbs, built by adapter.gd
var pools: Dictionary = {}          # pool_id -> {cur, max, regen}
var spell_ids: Array[String] = []   # castable-now spells
var slots: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var sheet = null                    # ResolvedCharacter; null for monsters
var caster := false                 # a statblock fielded with real slots (core/enemy_casters.gd)
var traits: Array = []              # #176: personality trait ids (core/traits.gd); [] for monsters

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

# "helped" is not here: Help's advantage lasts until the start of the HELPER's
# next turn (RAW), so combat.begin_turn_for(helper) is what clears it.
const TURN_STATUSES := ["dodging", "disengaged", "reckless"]

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
		"id","src_id","cname","team","ac","max_hp","hp","init_mod","speed","pos","size",
		"atk_bonus","damage","ranged","atk_range","reach","crit_range","save_dc","athletics",
		"acro","stealth","passive_perception","sheet","darkvision","temp_hp","init_adv","str_mod","pb",
		"caster",
	]:
		c.set(prop, get(prop))
	c.saves = saves.duplicate()
	c.resist = resist.duplicate()
	c.immune = immune.duplicate()
	c.vulnerable = vulnerable.duplicate()
	c.cond_immune = cond_immune.duplicate()
	c.slots = slots.duplicate()
	c.traits = traits.duplicate()
	c.attacks = attacks.duplicate(true)
	c.features = features.duplicate()
	c.verbs = verbs.duplicate(true)
	c.pools = pools.duplicate(true)
	c.spell_ids = spell_ids.duplicate()
	c.econ = econ.duplicate(true)
	return c
