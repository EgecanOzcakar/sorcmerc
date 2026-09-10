# The orchestrator: a build -> a ResolvedCharacter. Ordering matters only where noted.
# Ported from dnd-maintainer src/lib/resolver/index.ts resolveCharacter().
extends RefCounted

const Bundles = preload("res://core/rules/bundles.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Resolved = preload("res://core/rules/resolved.gd")
const PassAbilities = preload("res://core/rules/pass_abilities.gd")
const PassProfs = preload("res://core/rules/pass_profs.gd")
const PassDefense = preload("res://core/rules/pass_defense.gd")
const PassGear = preload("res://core/rules/pass_gear.gd")
const PassSpells = preload("res://core/rules/pass_spells.gd")
const PassPools = preload("res://core/rules/pass_pools.gd")
const PassPending = preload("res://core/rules/pass_pending.gd")

static func resolve(ch) -> Resolved:
	var r := Resolved.new()
	var catalog_mark: int = Catalog.warnings.size()

	var collected := Bundles.collect(ch)
	var b: Array = collected["bundles"]
	r.warnings.append_array(collected["warnings"])

	r.level = ch.level()
	r.proficiency_bonus = Bundles.proficiency_bonus(r.level)
	for l in ch.levels:
		r.class_levels[l["class_id"]] = int(r.class_levels.get(l["class_id"], 0)) + 1
	for tg in Bundles.of_type(b, "subclass"):
		var d = ch.choices.get(tg["grant"]["key"])
		if d != null and d.get("type") == "subclass":
			r.subclasses[tg["grant"]["classId"]] = d["subclassId"]

	# 1. abilities
	var ab := PassAbilities.resolve(ch.base_abilities, b, ch.choices)
	r.abilities = ab["abilities"]
	r.warnings.append_array(ab["warnings"])
	r.initiative = r.mod("dex")

	# 2. proficiencies, saves, skills
	var profs := PassProfs.proficiencies(b, ch.choices)
	r.proficiencies = {"armor": profs["armor"], "weapon": profs["weapon"],
		"tool": profs["tool"], "language": profs["language"]}
	var sv := PassProfs.saves(r.abilities, b, r.proficiency_bonus, ch.choices)
	r.saves = sv["saves"]
	r.save_prof = sv["save_prof"]
	var sk := PassProfs.skills(r.abilities, b, r.proficiency_bonus, ch.choices)
	r.skills = sk["skills"]
	r.skill_prof = sk["skill_prof"]
	r.passive_perception = 10 + int(r.skills.get("perception", 0))

	# 3/4. hp, speed
	var rolls: Array = []
	for l in ch.levels:
		rolls.append(int(l.get("hp_roll", -1)))
	r.max_hp = PassDefense.hp(b, rolls, r.mod("con"), r.level)
	r.speeds = PassDefense.speed(b)

	# 5. equipment (before AC and attacks)
	var eq := PassGear.equipment(ch, b)
	r.equipment = eq["items"]
	r.warnings.append_array(eq["warnings"])
	var armor_ac = PassGear.armor_ac(r.equipment, r.mod("dex"), r.proficiencies["armor"])

	# 6. ac
	var bardic := PassDefense.bardic_inspiration(b, Bundles.class_level(b, "bard"), r.mod("cha"))
	var acr := PassDefense.ac(b, r.abilities, armor_ac, int(bardic.get("die_size", 0)))
	r.ac = acr["ac"]
	r.ac_breakdown = acr["breakdown"]

	# 7. attacks
	for tg in Bundles.of_type(b, "fighting-style-choice"):
		var d = ch.choices.get(tg["grant"]["key"])
		if d != null and d.get("type") == "fighting-style-choice":
			for s in d["styles"]:
				if s in tg["grant"]["from"] and not s in r.fighting_styles:
					r.fighting_styles.append(s)
	r.weapon_masteries = PassGear.weapon_masteries(b, ch.choices, r.proficiencies["weapon"])
	r.attacks = PassGear.attacks(r.equipment, r.abilities, r.proficiency_bonus,
		r.proficiencies["weapon"], r.fighting_styles, Bundles.class_level(b, "monk"),
		r.weapon_masteries)

	# 8. spells
	var sp := PassSpells.resolve(b, r.abilities, r.proficiency_bonus, r.level)
	r.spellcasting = sp["spellcasting"]
	r.warnings.append_array(sp["warnings"])

	# 9. pools
	var pl := PassPools.resolve(b)
	r.pools = pl["pools"]
	r.warnings.append_array(pl["warnings"])

	# features and resistances
	for tg in Bundles.of_type(b, "feature"):
		var f: Dictionary = tg["grant"]["feature"]
		var entry := {"source": tg["source"], "save_dc": 0}
		if f.has("saveDC"):
			entry["save_dc"] = 8 + r.proficiency_bonus + r.mod(f["saveDC"]["dcAbility"])
		r.features[f["id"]] = entry
	for tg in Bundles.of_type(b, "resistance"):
		var dt: String = tg["grant"]["damageType"]
		if not dt in r.resistances:
			r.resistances.append(dt)

	# 10. pending
	var pd := PassPending.resolve(b, ch.choices, r.skill_prof, r.proficiencies["weapon"],
		collected["expanded_feats"])
	r.pending = pd["pending"]
	r.pending.append_array(profs["pending"])
	r.warnings.append_array(pd["warnings"])

	# non-proficient body armor: no casting, disadvantage on STR/DEX checks and all attacks
	if armor_ac != null and armor_ac["non_proficient_body"]:
		r.disadvantage_from_armor = true
		r.cannot_cast = true

	# catalog lookup misses made during this resolve
	for i in range(catalog_mark, Catalog.warnings.size()):
		r.warnings.append(Catalog.warnings[i])
	return r
