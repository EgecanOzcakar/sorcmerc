# The persistable build. Everything else about a character is derived from this
# by core/rules/resolve.gd and cached in `_sheet`.
extends RefCounted

var id: String
var cname: String
var species_id: String
var background_id: String
var base_abilities: Dictionary = {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
var levels: Array[Dictionary] = []      # [{class_id, hp_roll}] ordered; hp_roll -1 = average
var choices: Dictionary = {}            # choice_key -> decision
var feats: Array[String] = []
var equipped: Array[String] = []        # weapon/armor ids worn or wielded
                                        # everything unequipped lives in Party.stash
var offhand: String = ""                # id of the light weapon wielded off-hand;
                                        # also present in `equipped` (T24)
var pools: Dictionary = {}              # pool_id -> current uses
var slots_used: Array[int] = []         # spell slots spent, per level; cleared by a long rest
var hp_current: int = -1                # -1 = full
var buffs: Dictionary = {}              # potion id -> {until (world-minute), status?/condition?/road?} — core/potions.gd
var prepared: Array[String] = []
var xp: int = 0                         # banked per character; gates Leveling.can_level_up
var dead: bool = false                  # died in a fight; benched until revived

const Resolve = preload("res://core/rules/resolve.gd")
const Resolved = preload("res://core/rules/resolved.gd")
const Catalog = preload("res://core/rules/catalog.gd")

var _sheet = null
var _dirty := true

# Cached. Nothing else may call Resolve.resolve() — a level-20 resolve is a few ms
# and must never land in _process or a UI redraw (spec §11).
func sheet() -> Resolved:
	if _dirty or _sheet == null:
		_sheet = Resolve.resolve(self)
		_dirty = false
	return _sheet

func level() -> int:
	return levels.size()

func class_level(cid: String) -> int:
	var n := 0
	for l in levels:
		if l["class_id"] == cid:
			n += 1
	return n

func class_id() -> String:
	return levels[0]["class_id"] if not levels.is_empty() else ""

func decide(key: String, decision: Dictionary) -> void:
	choices[key] = decision
	_dirty = true

func add_level(cid: String, hp_roll: int = -1) -> void:
	levels.append({"class_id": cid, "hp_roll": hp_roll})
	_dirty = true

func dirty() -> void:
	_dirty = true

# Two-weapon fighting (T24): only a Light weapon may be wielded off-hand. Equips it
# too if it isn't already worn, so both hands resolve into `sheet().attacks`.
# ponytail: no Dual Wielder feat — that's the one thing that lifts the Light gate.
func is_light(item_id: String) -> bool:
	return "light" in Catalog.weapon(item_id).get("properties", [])

func equip_offhand(item_id: String) -> bool:
	if not is_light(item_id):
		return false
	if not item_id in equipped:
		equipped.append(item_id)
	offhand = item_id
	_dirty = true
	return true

func unequip_offhand() -> void:
	offhand = ""
	_dirty = true
