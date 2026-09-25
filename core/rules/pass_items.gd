# Magic items that do something on the sheet: a +1 sword swings truer, a cloak
# of protection turns blows, gauntlets of ogre power are Strength 19.
#
# Until 2026-09-25 nothing did. pass_gear.gd built the sheet from weapons.json
# and armor.json alone, so a magic item put on at the profile sat in `equipped`
# as an inert "unknown" row — carried, sold, and worth nothing in a fight — and
# core/adapter.gd's header said as much: nothing in the game hands out magic
# gear. With loot selling at a fifth of list (Campaign.SELL_RATE) the other
# half of that pass is that a magic item is worth WEARING (the design audit
# §5.1c). This is the first tranche: the items loot and the smith's back room
# hand out most, whose whole mechanic is a flat number the sheet already has a
# place for. data/effects/items.json says what each one does; this file puts
# it on the sheet.
#
#   var worn := PassItems.worn(ch)            # {items: [{id, fx}], warnings}
#   PassItems.apply_abilities(r, worn)        # after pass_abilities: set_ability
#   PassItems.apply_saves(r, worn)            # after pass_profs: saves, checks
#   PassItems.ac_bonuses(worn, armor_ac)      # into pass_defense.ac's bonuses
#   PassItems.apply_attacks(r, worn, offhand) # after pass_gear.attacks
#   PassItems.apply_spells(r, worn)           # after pass_spells: spell_attack
#   PassItems.apply_resist(r, worn)           # resistances
#
# Everything lands on the Resolved sheet, not on the Combatant, and that is the
# point: core/adapter.gd copies ac, saves, attacks, resistances and the spell
# attack bonus off the sheet, so the fight sees an item with no code of its own,
# the profile shows it, and core/rules/power.gd PRICES it — the budget reads
# the combatant the adapter built from this sheet, so a company in +2 armor is
# sent a bigger fight and paid more for it. power.gd reads AC, attacks, HP (a
# Constitution item's) and resistances; it does not price saving throws or
# ability checks, so a cloak's +1 to saves and a luckstone are the unpriced
# part of this tranche.
#
# RAW limits, kept: one of each item counts (two cloaks are one cloak), only
# the best weapon, armor and shield enchantment counts (a +1 and a +2 sword is
# a +2 sword), and at most ATTUNE_MAX items that need attunement count, in the
# order they were put on. The rest are worn and inert, and the sheet says so
# (a warning, and worn_note for the profile).
#
# ponytail: a weapon or armor enchantment rides whatever the hero wields or
# wears, rather than being one particular +1 longsword. The export files every
# +N weapon as one "any simple or martial" entry, so the item a goblin drops
# has no base; giving it one means picking a weapon at drop time and a stash
# row per (base, bonus). Revisit if players want to find a +1 longbow in
# particular.
#
# What this does NOT own: which items drop or sell (core/loot.gd, the back
# room in core/settlement_visit.gd), equipping (the profile moves ids between
# the stash and `equipped`), or anything the export's prose describes that has
# no number here — see data/effects/items.json's note for the vocabulary and
# the build log (docs/plan/2026-09-25-coin-and-xp.md) for what is still open.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const FILE := "effects/items.json"
const ATTUNE_MAX := 3            # RAW: three attuned items at a time
# The slot vocabulary, and the keys an entry may carry. registry.gd validates a
# pack's overlay against both, so a typo is an error rather than a dead item.
const SLOTS := ["weapon", "armor", "shield", "worn"]
const KEYS := ["slot", "attack", "damage", "weapons", "ac", "unarmored", "saves", "checks",
	"set_ability", "spell_attack", "resist", "text"]
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

# The mechanics for one magic-item id, {} when it has none.
static func entry(id: String) -> Dictionary:
	var d = Catalog.all(FILE)
	if not (d is Dictionary):
		return {}
	var e = d.get(id, {})
	return e if e is Dictionary else {}

static func is_magic_item(id: String) -> bool:
	return Catalog.index("magic-items.json").has(id)

# A magic shield is a shield in every rule that asks (pass_gear.armor_ac, the
# monk's and barbarian's no-shield defences, Unarmed Fighting's die).
static func is_shield(id: String) -> bool:
	return String(entry(id).get("slot", "")) == "shield"

static func needs_attunement(id: String) -> bool:
	return bool(Catalog.magic_item(id).get("attunement", false))

# The items on this hero that count, after RAW's limits, in `equipped` order.
# {items: [{id, fx}], inert: [{id, why}], warnings: [String]}
static func worn(ch) -> Dictionary:
	var items: Array = []
	var inert: Array = []
	var warns: Array = []
	var seen := {}
	var attuned := 0
	var best_slot := {}   # slot -> index into items, for weapon/armor/shield
	for raw in ch.equipped:
		var id := String(raw)
		if seen.has(id) or not is_magic_item(id):
			continue
		seen[id] = true
		var fx := entry(id)
		if fx.is_empty():
			continue
		if needs_attunement(id):
			if attuned >= ATTUNE_MAX:
				inert.append({"id": id, "why": "attunement"})
				warns.append("%s needs attunement and %d items already hold it — worn, and inert"
					% [id, ATTUNE_MAX])
				continue
			attuned += 1
		var slot := String(fx.get("slot", "worn"))
		if slot != "worn":
			if best_slot.has(slot):
				var i: int = best_slot[slot]
				if _power(fx) > _power(items[i]["fx"]):
					inert.append({"id": items[i]["id"], "why": "outclassed"})
					items[i] = {"id": id, "fx": fx}
				else:
					inert.append({"id": id, "why": "outclassed"})
				continue
			best_slot[slot] = items.size()
		items.append({"id": id, "fx": fx})
	return {"items": items, "inert": inert, "warnings": warns}

static func _power(fx: Dictionary) -> int:
	return int(fx.get("attack", 0)) + int(fx.get("damage", 0)) + int(fx.get("ac", 0))

# Why an equipped item does nothing, for the profile: "" when it counts.
static func worn_note(ch, id: String) -> String:
	if not is_magic_item(id):
		return ""
	if entry(id).is_empty():
		return "Does nothing in a fight yet."
	for x in worn(ch)["inert"]:
		if String(x["id"]) == id:
			return ("Inert: %d attuned items already." % ATTUNE_MAX) if x["why"] == "attunement" \
				else "Inert: a better one of its kind is worn."
	return ""

# --- the passes, in resolve.gd's order ------------------------------------

# Gauntlets of ogre power: the score becomes 19 unless it is already higher.
static func apply_abilities(r, w: Dictionary) -> void:
	for it in w["items"]:
		var set_to = it["fx"].get("set_ability", {})
		if not (set_to is Dictionary):
			continue
		for a in set_to:
			var k := String(a)
			if not r.abilities.has(k):
				continue
			var ab: Dictionary = r.abilities[k]
			var v: int = int(set_to[a])
			if v > int(ab["total"]):
				ab["total"] = v
				ab["mod"] = floori((v - 10) / 2.0)
				ab["bonuses"].append({"value": 0, "set": v, "source": {"origin": "item", "id": it["id"]}})

static func apply_saves(r, w: Dictionary) -> void:
	for it in w["items"]:
		var n: int = int(it["fx"].get("saves", 0))
		if n != 0:
			for k in r.saves:
				r.saves[k] = int(r.saves[k]) + n
		var c: int = int(it["fx"].get("checks", 0))
		if c != 0:
			for k in r.skills:
				r.skills[k] = int(r.skills[k]) + c
			r.initiative += c   # 2024: Initiative is a Dexterity check

# AC bonus entries in pass_defense.ac's own shape, {bonus, source}. `armor_ac`
# is pass_gear.armor_ac's answer (null when nothing is worn), which is what the
# armor and shield slots and `unarmored` are conditioned on.
static func ac_bonuses(w: Dictionary, armor_ac) -> Array:
	var body: bool = armor_ac != null and armor_ac["totalBase"] != null
	var shield: bool = armor_ac != null and int(armor_ac["shieldBonus"]) > 0
	var out: Array = []
	for it in w["items"]:
		var fx: Dictionary = it["fx"]
		var n: int = int(fx.get("ac", 0))
		if n == 0:
			continue
		match String(fx.get("slot", "worn")):
			"armor":
				if not body:
					continue
			"shield":
				if not shield:
					continue   # held, but not proficient: the shield is not doing its job
		if bool(fx.get("unarmored", false)) and (body or shield):
			continue
		out.append({"bonus": n, "source": {"origin": "item", "id": it["id"]}})
	return out

# Every weapon attack but the off-hand one and the unarmed strike takes the
# weapon slot's bonus; a `weapons` list narrows a worn item to those weapons
# (bracers of archery). The notation is rebuilt off the new numbers.
static func apply_attacks(r, w: Dictionary, offhand: String) -> void:
	for it in w["items"]:
		var fx: Dictionary = it["fx"]
		var hit: int = int(fx.get("attack", 0))
		var dmg: int = int(fx.get("damage", 0))
		if hit == 0 and dmg == 0:
			continue
		var only: Array = fx.get("weapons", [])
		for a in r.attacks:
			var aid := String(a["id"])
			var base := aid.trim_suffix("-thrown")
			if aid == "unarmed-strike" or (offhand != "" and base == offhand):
				continue
			if not only.is_empty() and not base in only:
				continue
			a["to_hit"] = int(a["to_hit"]) + hit
			a["dmg_bonus"] = int(a["dmg_bonus"]) + dmg
			a["notation"] = _notation(int(a["dice_count"]), int(a["dice_sides"]), int(a["dmg_bonus"]))
			var ver := String(a.get("versatile_notation", ""))
			if ver != "":
				var dice := ver.split("+")[0].split("-")[0]
				var d := dice.split("d")
				if d.size() == 2:
					a["versatile_notation"] = _notation(int(d[0]), int(d[1]), int(a["dmg_bonus"]))
			var from: Array = a.get("items", [])
			from.append(it["id"])
			a["items"] = from

static func apply_spells(r, w: Dictionary) -> void:
	if r.spellcasting.is_empty():
		return
	for it in w["items"]:
		var n: int = int(it["fx"].get("spell_attack", 0))
		if n != 0:
			r.spellcasting["attack_bonus"] = int(r.spellcasting.get("attack_bonus", 0)) + n

static func apply_resist(r, w: Dictionary) -> void:
	for it in w["items"]:
		for t in it["fx"].get("resist", []):
			if not String(t) in r.resistances:
				r.resistances.append(String(t))

static func _notation(count: int, sides: int, bonus: int) -> String:
	var s := "%dd%d" % [count, sides]
	return s if bonus == 0 else "%s%+d" % [s, bonus]
