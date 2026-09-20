# Equipment resolution + attacks. Ported from dnd-maintainer src/lib/resolver/equipment.ts.
# v1 scope: weapons.json + armor.json only. The export ships no gear/packs/bundles
# (SCHEMA gaps #1, #2, #6), so bundle-choice resolves to a warning and unknown item
# ids become inert rows. Only `ch.equipped` is a character's — everything else the
# party is carrying lives in Party.stash (T10), which the sheet knows nothing about.
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")
const Catalog = preload("res://core/rules/catalog.gd")

# {items: Array, warnings: Array[String]}
# item = {item_id, def, kind: "weapon"|"armor"|"unknown", quantity, equipped, source}
static func equipment(ch, bundles: Array) -> Dictionary:
	var warns: Array[String] = []
	var items: Array = []
	var qty := {}
	var order: Array = []
	for iid in ch.equipped:
		if not qty.has(iid):
			order.append(iid)
			qty[iid] = 1

	for iid in order:
		var def: Dictionary = Catalog.index("weapons.json").get(iid, {})
		var kind := "weapon"
		if def.is_empty():
			def = Catalog.index("armor.json").get(iid, {})
			kind = "armor"
		if def.is_empty():
			kind = "unknown"
			warns.append("equipped item \"%s\" matches neither weapons.json nor armor.json — "
				% iid + "it will sit inert (no attack/AC contribution)")
		items.append({"item_id": iid, "def": def, "kind": kind, "quantity": qty[iid],
			"equipped": iid in ch.equipped, "source": {"origin": "item", "id": iid}})

	for tg in Bundles.of_type(bundles, "bundle-choice"):
		warns.append("bundle-choice \"%s\" cannot resolve — starting-equipment bundles are not exported (SCHEMA gap #2)" % tg["grant"]["key"])

	return {"items": items, "warnings": warns}

# null when nothing relevant is worn.
# {totalBase, shieldBonus, non_proficient_body, non_proficient_shield}
static func armor_ac(items: Array, dex_mod: int, armor_profs: Array):
	var body := {}
	var shield := {}
	for it in items:
		if not it["equipped"] or it["kind"] != "armor":
			continue
		if it["def"]["category"] == "shield":
			if shield.is_empty():
				shield = it["def"]
		elif body.is_empty():
			body = it["def"]

	var shield_ok := _armor_prof("shield", armor_profs)
	var shield_bonus: int = int(shield["baseAc"]) if not shield.is_empty() and shield_ok else 0
	var np_shield: bool = not shield.is_empty() and not shield_ok
	if body.is_empty() and shield_bonus == 0:
		return null
	if body.is_empty():
		return {"totalBase": null, "shieldBonus": shield_bonus,
			"non_proficient_body": false, "non_proficient_shield": np_shield}

	var cap = body["maxDexBonus"]
	var dex: int = dex_mod if cap == null else clampi(dex_mod, 0, int(cap))
	return {"totalBase": int(body["baseAc"]) + dex, "shieldBonus": shield_bonus,
		"non_proficient_body": not _armor_prof(body["category"], armor_profs),
		"non_proficient_shield": np_shield}

# Can this sheet use the item without the non-proficiency penalties? `profs`
# is r.proficiencies["weapon"] or ["armor"] to match `kind`.
static func proficient(kind: String, def: Dictionary, profs: Array) -> bool:
	if kind == "weapon":
		return str(def.get("weaponProficiencyId", "")) in profs or str(def.get("category", "")) in profs
	return _armor_prof(str(def.get("category", "")), profs)

static func _armor_prof(category: String, profs: Array) -> bool:
	match category:
		"light": return "light" in profs
		"medium": return "medium" in profs or "medium-nonmetal" in profs
		"heavy": return "heavy" in profs
		"shield": return "shields" in profs or "shields-nonmetal" in profs
	return false

# [{id, name, ability, to_hit, dice_count, dice_sides, dmg_bonus, notation, damage_type,
#   properties, range, normal_ft, long_ft, versatile_notation, mastery}]
static func attacks(items: Array, abilities: Dictionary, pb: int, weapon_profs: Array,
		styles: Array, monk_level: int, masteries: Dictionary = {}) -> Array:
	var equipped: Array = []
	for it in items:
		if it["equipped"] and it["kind"] == "weapon":
			equipped.append(it)

	var archery: bool = "archery" in styles
	var dueling: bool = "dueling" in styles
	var out: Array = []

	for it in equipped:
		var w: Dictionary = it["def"]
		var ability := "str"
		if "finesse" in w["properties"]:
			ability = "str" if int(abilities["str"]["mod"]) >= int(abilities["dex"]["mod"]) else "dex"
		elif w["range"] == "ranged":
			ability = "dex"
		var mod: int = int(abilities[ability]["mod"])
		var proficient: bool = w["weaponProficiencyId"] in weapon_profs or w["category"] in weapon_profs

		var to_hit: int = mod + (pb if proficient else 0)
		if archery and w["range"] == "ranged":
			to_hit += 2
		var dmg: int = mod
		var one_handed_melee: bool = w["range"] == "melee" and not "two-handed" in w["properties"]
		if dueling and one_handed_melee and equipped.size() == 1:
			dmg += 2

		var d := _dice(w["damageDice"])
		out.append({
			"id": w["id"], "name": w["name"], "ability": ability, "to_hit": to_hit,
			"dice_count": d[0], "dice_sides": d[1], "dmg_bonus": dmg,
			"notation": notation(d[0], d[1], dmg),
			"damage_type": w["damageType"], "properties": w["properties"], "range": w["range"],
			"normal_ft": int(w["normalRange"]) if w["normalRange"] != null else 0,
			"long_ft": int(w["longRange"]) if w["longRange"] != null else 0,
			"versatile_notation": _versatile(w, dmg),
			"mastery": masteries.get(w["id"], ""),
		})
		# Thrown: the same weapon as a ranged attack (same ability, no Archery bonus),
		# so a javelin or dagger shows up in the wield toggle as a real ranged option.
		if "thrown" in w["properties"] and w["range"] == "melee" and w["normalRange"] != null:
			var thrown: Dictionary = out[-1].duplicate(true)
			thrown["id"] = w["id"] + "-thrown"
			thrown["name"] = w["name"] + " (thrown)"
			thrown["range"] = "ranged"
			thrown["versatile_notation"] = ""
			out.append(thrown)

	var unarmed_fighting: bool = "unarmed-fighting" in styles
	if equipped.is_empty() or monk_level > 0 or unarmed_fighting:
		var ability := "str"
		if monk_level > 0 and int(abilities["dex"]["mod"]) > int(abilities["str"]["mod"]):
			ability = "dex"
		var mod: int = int(abilities[ability]["mod"])
		var sides := 1
		if monk_level >= 17: sides = 12
		elif monk_level >= 11: sides = 10
		elif monk_level >= 5: sides = 8
		elif monk_level > 0: sides = 6
		elif unarmed_fighting:
			var has_shield := false
			for it in items:
				if it["equipped"] and it["kind"] == "armor" and it["def"]["category"] == "shield":
					has_shield = true
			sides = 8 if equipped.is_empty() and not has_shield else 6
		out.append({
			"id": "unarmed-strike", "name": "Unarmed Strike", "ability": ability,
			"to_hit": mod + pb, "dice_count": 1, "dice_sides": sides, "dmg_bonus": mod,
			"notation": notation(1, sides, mod),
			"damage_type": "bludgeoning", "properties": [], "range": "melee",
			"normal_ft": 0, "long_ft": 0, "versatile_notation": "", "mastery": "",
		})
	return out

# Attacks carry ints; notation is formatted from them so Dice.parse never sees a
# bare "1" (spec §2.4) — a plain unarmed strike becomes "1d1+N".
static func notation(count: int, sides: int, bonus: int) -> String:
	var s := "%dd%d" % [count, sides]
	return s if bonus == 0 else "%s%+d" % [s, bonus]

static func _dice(spec: String) -> Array:
	var parts := spec.split("d")
	if parts.size() != 2:
		return [int(spec) if spec.is_valid_int() else 1, 1]
	return [int(parts[0]) if parts[0] != "" else 1, int(parts[1])]

static func _versatile(w: Dictionary, dmg: int) -> String:
	if w["versatileDice"] == null:
		return ""
	var d := _dice(w["versatileDice"])
	return notation(d[0], d[1], dmg)

# weapon_id -> mastery_id for decided weapon-mastery-choices. v1 resolves *which*
# masteries are known; the effects (cleave / graze / vex) are F3's.
static func weapon_masteries(bundles: Array, choices: Dictionary, weapon_profs: Array) -> Dictionary:
	var eligible := {}
	for wid in Catalog.index("weapons.json"):
		var w: Dictionary = Catalog.index("weapons.json")[wid]
		if w["mastery"] == null:
			continue
		if w["weaponProficiencyId"] in weapon_profs or w["category"] in weapon_profs:
			eligible[wid] = w["mastery"]

	var out := {}
	for tg in Bundles.of_type(bundles, "weapon-mastery-choice"):
		var g: Dictionary = tg["grant"]
		var d = choices.get(g["key"])
		if d == null or d.get("type") != "weapon-mastery-choice":
			continue
		for wid in d["weaponIds"]:
			if eligible.has(wid) and not out.has(wid):
				out[wid] = eligible[wid]
	return out
