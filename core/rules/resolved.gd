# The materialized character sheet. A pure function of the build — never mutated
# in place. Dictionaries stop at the grant boundary; everything here has a name.
extends RefCounted

# identity / scale
var level: int
var class_levels: Dictionary = {}      # "rogue" -> 5
var subclasses: Dictionary = {}        # "rogue" -> "thief"
var proficiency_bonus: int

# abilities
var abilities: Dictionary = {}         # "str" -> {base, total, mod, bonuses}

# defense
var max_hp: int
var ac: int
var ac_breakdown: Array = []
var speeds: Dictionary = {}            # "walk" -> ft
var initiative: int
var resistances: Array[String] = []
var immunities: Array[String] = []

# checks
var saves: Dictionary = {}             # "str" -> int
var save_prof: Dictionary = {}
var skills: Dictionary = {}            # "stealth" -> int
var skill_prof: Dictionary = {}        # "stealth" -> "none"|"prof"|"expert"
var passive_perception: int = 10
var disadvantage_from_armor: bool = false
var cannot_cast: bool = false

# offense
var attacks: Array = []
var spellcasting: Dictionary = {}      # {} when the character casts nothing

# kit
var features: Dictionary = {}          # feature_id -> {source, save_dc}
var pools: Array = []                  # {id, max, regen, die_size, source}
var weapon_masteries: Dictionary = {}
var fighting_styles: Array[String] = []
var proficiencies: Dictionary = {"armor": [], "weapon": [], "tool": [], "language": []}
var equipment: Array = []

# build state
var pending: Array = []
# Every choice point this build has reached, decided or not — pending entries plus
# the ones already answered, each with a `decided` flag. Superset of `pending`,
# in the same shape, so the creator can reopen a made choice (T34).
var choice_points: Array = []
var warnings: Array[String] = []

func mod(a: String) -> int:
	return int(abilities[a]["mod"]) if abilities.has(a) else 0

func has_feature(id: String) -> bool:
	return features.has(id)

func pool_max(id: String) -> int:
	for p in pools:
		if p["id"] == id:
			return int(p["max"])
	return 0

func class_level(cid: String) -> int:
	return int(class_levels.get(cid, 0))
