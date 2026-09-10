# Spellcasting: DC, attack, slots, known/prepared.
# Ported from dnd-maintainer src/lib/resolver/spellcasting.ts, plus the local
# third-caster table (SCHEMA gap #5).
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const PREPARED_CASTERS := ["cleric", "druid", "wizard", "paladin", "ranger"]

# {} when the character casts nothing. {spellcasting: Dictionary, warnings: [String]}
static func resolve(bundles: Array, abilities: Dictionary, pb: int, level: int) -> Dictionary:
	var warns: Array[String] = []
	var casting := Bundles.of_type(bundles, "spellcasting")
	var spells := Bundles.of_type(bundles, "spell")
	var choices := Bundles.of_type(bundles, "spell-choice")
	if casting.is_empty() and spells.is_empty() and choices.is_empty():
		return {"spellcasting": {}, "warnings": warns}

	var ability := ""
	var save_dc := 0
	var attack_bonus := 0
	var class_id := ""
	var third_caster := false
	var ability_mod := 0
	if not casting.is_empty():
		var primary: Dictionary = casting[0]
		for tg in casting:
			if tg["grant"]["source"] == "class":
				primary = tg
				break
		ability = primary["grant"]["ability"]
		ability_mod = int(abilities[ability]["mod"])
		save_dc = 8 + pb + ability_mod
		attack_bonus = pb + ability_mod
		var src: Dictionary = primary["source"]
		if src["origin"] == "class":
			class_id = src["id"]
		elif src["origin"] == "subclass":
			class_id = src["classId"]
			third_caster = Catalog.spell_slots(class_id, 1).is_empty() \
				and Catalog.spell_slots(class_id, 20).is_empty()

	var cantrips: Array = []
	var known: Array = []
	var always: Array = []
	var overrides := {}
	for tg in spells:
		var g: Dictionary = tg["grant"]
		if g.has("ability") and g["ability"] != ability:
			overrides[g["spellId"]] = g["ability"]
		var def := Catalog.spell(g["spellId"])
		if def.is_empty():
			warns.append("spell grant references uncatalogued spell \"%s\"" % g["spellId"])
		if g["alwaysPrepared"]:
			always.append(g["spellId"])
		elif def.is_empty():
			known.append({"id": g["spellId"], "level": 0})
		elif int(def["level"]) == 0:
			cantrips.append(g["spellId"])
		else:
			known.append({"id": g["spellId"], "level": int(def["level"])})

	var cantrips_known := 0
	var spells_known := {}
	for tg in choices:
		var g: Dictionary = tg["grant"]
		var lvl := int(g["spellLevel"])
		if lvl == 0:
			cantrips_known += int(g["count"])
		else:
			spells_known[lvl] = int(spells_known.get(lvl, 0)) + int(g["count"])

	var class_level: int = Bundles.class_level(bundles, class_id) if class_id != "" else 0
	var is_warlock: bool = class_id == "warlock"
	var pact := Catalog.pact_magic(class_id, level) if is_warlock else {}
	var slots: Array[int] = [] as Array[int]
	if not is_warlock and class_id != "":
		slots = Catalog.third_caster_slots(class_level) if third_caster else Catalog.spell_slots(class_id, level)
	while slots.size() < 9:
		slots.append(0)

	var prepared_count := 0
	if class_id in PREPARED_CASTERS:
		prepared_count = maxi(1, class_level + ability_mod)

	return {"spellcasting": {
		"ability": ability, "save_dc": save_dc, "attack_bonus": attack_bonus,
		"class_id": class_id, "slots": slots, "pact": pact,
		"cantrips": cantrips, "cantrips_known": cantrips_known,
		"known": known, "spells_known": spells_known,
		"always_prepared": always, "prepared_count": prepared_count,
		"ability_overrides": overrides,
	}, "warnings": warns}
