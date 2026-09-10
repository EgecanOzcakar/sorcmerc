# F2 rules engine — one test per build step in the A0 spec §10.
#   godot --headless --path . -s tests/test_rules.gd
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Grants = preload("res://core/rules/grants.gd")
const Choice = preload("res://core/rules/choice.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const Character = preload("res://core/character.gd")
const PassAbilities = preload("res://core/rules/pass_abilities.gd")
const PassProfs = preload("res://core/rules/pass_profs.gd")
const PassDefense = preload("res://core/rules/pass_defense.gd")
const PassPools = preload("res://core/rules/pass_pools.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_catalog_loads()
	test_catalog_grants_validate()
	test_schema_covers_catalog()
	test_choice_keys()
	test_bundles_order()
	test_bundles_subclass_is_retroactive()
	test_bundles_min_class_level_gate()
	test_no_nested_expansion()
	test_abilities()
	test_profs()
	test_expertise_and_half_proficiency()
	test_hp()
	test_ac()
	test_speed()
	test_pools()

	print("test_rules: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- step 1: catalog.gd + grants.gd --------------------------------------

func test_catalog_loads() -> void:
	var counts := {
		"classes.json": 12, "subclasses.json": 48, "species.json": 10,
		"backgrounds.json": 16, "feats.json": 74, "fighting-styles.json": 10,
		"spells.json": 146, "weapons.json": 39, "armor.json": 13,
		"magic-items.json": 262, "conditions.json": 15, "skills.json": 18,
	}
	for f in counts:
		var a = Catalog.all(f)
		check(a != null, "%s loads" % f)
		var n: int = a.size() if a != null else -1
		check(n == counts[f], "%s has %d records (got %d)" % [f, counts[f], n])

	check(Catalog.class_src("fighter")["hitDie"] == 10, "fighter hit die 10")
	check(Catalog.weapon("longsword")["damageDice"] == "1d8", "longsword 1d8")
	check(Catalog.armor("chain-mail")["baseAc"] == 16, "chain mail base AC 16")
	check(Catalog.skills()["stealth"]["ability"] == "dex", "stealth is DEX")
	check(Catalog.subclasses_of("fighter").size() == 4, "fighter has 4 subclasses")
	check("fireball" in Catalog.spell_list("wizard", 3), "fireball on the wizard 3rd list")
	check(not "fireball" in Catalog.spell_list("cleric", 3), "fireball not on the cleric list")
	check(Catalog.spell_slots("wizard", 1) == [2], "wizard 1 has 2 first-level slots")
	check(Catalog.spell_slots("fighter", 5).is_empty(), "fighter has no class slot table")
	check(Catalog.third_caster_slots(3) == [2], "third caster 3 has 2 first-level slots")
	check(int(Catalog.pact_magic("warlock", 3)["slotLevel"]) == 2, "warlock 3 casts at slot level 2")

	# unknown ids warn instead of throwing
	var before := Catalog.warnings.size()
	check(Catalog.class_src("bardbarian").is_empty(), "unknown class id -> {}")
	check(Catalog.warnings.size() == before + 1, "unknown id appends a warning")

func test_catalog_grants_validate() -> void:
	var errs := Grants.validate_catalog()
	for e in errs:
		printerr("    ", e)
	check(errs.is_empty(), "validate_catalog() is clean (%d errors)" % errs.size())

func test_schema_covers_catalog() -> void:
	var seen := {}
	for f in Grants.GRANT_FILES:
		for g in Grants.catalog_grants(f):
			seen[g["type"]] = true
	for t in Grants.SCHEMA:
		check(seen.has(t), "SCHEMA type \"%s\" appears in the catalog" % t)
	for t in seen:
		check(Grants.SCHEMA.has(t), "catalog type \"%s\" is in SCHEMA" % t)

# --- step 2: choice.gd ---------------------------------------------------

func test_choice_keys() -> void:
	var k := Choice.make("skill-choice", "class", "fighter", 0)
	check(k == "skill-choice:class:fighter:0", "make() renders the four segments")
	check(Choice.parse(k) == {"category": "skill-choice", "origin": "class", "id": "fighter", "index": 0},
		"parse() round-trips make()")
	check(Choice.parse("skill-choice:class:fighter").is_empty(), "3 segments rejected")
	check(Choice.parse("nope:class:fighter:0").is_empty(), "bad category rejected")
	check(Choice.parse("asi:elf:fighter:0").is_empty(), "bad origin rejected")
	check(Choice.parse("asi:class:fighter:x").is_empty(), "non-numeric index rejected")
	check(Choice.companion("asi:class:fighter:0", "feat-choice") == "feat-choice:class:fighter:0",
		"companion() swaps only the category")

	# every key the export actually emits must parse
	var bad: Array[String] = []
	var n := 0
	for f in Grants.GRANT_FILES:
		for g in Grants.catalog_grants(f):
			if not g.has("key"):
				continue
			n += 1
			if Choice.parse(g["key"]).is_empty():
				bad.append("%s: %s" % [f, g["key"]])
	for b in bad:
		printerr("    ", b)
	check(n > 200, "the catalog carries choice keys (%d)" % n)
	check(bad.is_empty(), "every exported choice key parses (%d bad)" % bad.size())

# --- step 3: bundles.gd --------------------------------------------------

func _fighter(n: int) -> Character:
	var ch := Character.new()
	ch.id = "test"; ch.cname = "Test"
	ch.species_id = "human"
	ch.background_id = "soldier"
	for i in n:
		ch.add_level("fighter", -1)
	return ch

func test_bundles_order() -> void:
	var r := Bundles.collect(_fighter(1))
	var b: Array = r["bundles"]
	var tags: Array = []
	for x in b:
		tags.append("%s/%s" % [x["source"]["origin"], x["source"]["id"]])
	check(tags == ["species/human", "class/fighter", "background/soldier", "feat/savage-attacker"],
		"fighter 1 bundles in source order (got %s)" % str(tags))
	check(r["expanded_feats"].has("savage-attacker"), "the background origin feat expanded")
	check(r["warnings"].is_empty(), "an undecided fighter 1 collects without warnings")
	check(Bundles.class_level(b, "fighter") == 1, "class_level counts class bundles")

	var f5 := _fighter(5)
	var b5: Array = Bundles.collect(f5)["bundles"]
	check(Bundles.class_level(b5, "fighter") == 5, "fighter 5 has 5 class bundles")
	check(Bundles.of_type(b5, "hit-die").size() == 1, "hit-die granted once, at level 1")

func test_bundles_subclass_is_retroactive() -> void:
	var ch := _fighter(7)
	var before := Bundles.of_type(Bundles.collect(ch)["bundles"], "feature").size()
	ch.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "champion"})
	var b: Array = Bundles.collect(ch)["bundles"]
	var ids: Array = []
	for tg in Bundles.of_type(b, "feature"):
		ids.append(tg["grant"]["feature"]["id"])
	check(ids.size() > before, "deciding the subclass adds features")
	check("champion-improved-critical" in ids, "the level-3 subclass feature is spliced in retroactively")
	check("champion-remarkable-athlete" in ids, "the level-7 subclass feature is present at fighter 7")

	# ...and not above the class level
	var ch3 := _fighter(3)
	ch3.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "champion"})
	var ids3: Array = []
	for tg in Bundles.of_type(Bundles.collect(ch3)["bundles"], "feature"):
		ids3.append(tg["grant"]["feature"]["id"])
	check("champion-improved-critical" in ids3, "fighter 3 has the level-3 subclass feature")
	check(not "champion-remarkable-athlete" in ids3, "fighter 3 does not get the level-7 one")

func test_bundles_min_class_level_gate() -> void:
	var gated := 0
	for f in Grants.GRANT_FILES:
		for g in Grants.catalog_grants(f):
			if g.has("minClassLevel"):
				gated += 1
	check(gated > 0, "the catalog uses minClassLevel (%d grants)" % gated)

	# a druid 3 Circle of the Land must not see the level-5 circle spells
	var ch := Character.new()
	ch.species_id = "human"; ch.background_id = "soldier"
	for i in 3:
		ch.add_level("druid", -1)
	ch.decide("subclass:class:druid:0", {"type": "subclass", "subclassId": "circleland"})
	ch.decide("feature-choice:subclass:circleland:0", {"type": "feature-choice", "optionId": "arid"})
	var lo := Bundles.of_type(Bundles.collect(ch)["bundles"], "spell").size()
	for i in 4:
		ch.add_level("druid", -1)
	var hi := Bundles.of_type(Bundles.collect(ch)["bundles"], "spell").size()
	check(hi > lo, "druid 7 unlocks more circle spells than druid 3 (%d vs %d)" % [hi, lo])

# The single-pass feature-choice expansion (bundles.gd step 12) is only safe while
# no option's own grants nest a feat / lineage-choice / feature-choice.
func test_no_nested_expansion() -> void:
	var offenders: Array[String] = []
	for f in Grants.GRANT_FILES:
		for g in Grants.catalog_grants(f):
			if g["type"] != "feature-choice":
				continue
			for o in g["options"]:
				for sub in o.get("grants", []):
					if sub["type"] in ["feat", "lineage-choice", "feature-choice"]:
						offenders.append("%s -> %s nests %s" % [g["key"], o["optionId"], sub["type"]])
	for x in offenders:
		printerr("    ", x)
	check(offenders.is_empty(), "no feature-choice option nests an expanding grant (%d)" % offenders.size())

# --- step 4: pass_abilities + pass_profs ---------------------------------

func _resolved_abilities(ch: Character) -> Dictionary:
	return PassAbilities.resolve(ch.base_abilities, Bundles.collect(ch)["bundles"], ch.choices)

func test_abilities() -> void:
	var ch := _fighter(1)
	ch.base_abilities = {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}
	var a: Dictionary = _resolved_abilities(ch)["abilities"]
	check(int(a["str"]["total"]) == 15 and int(a["str"]["mod"]) == 2, "str 15 -> +2")
	check(int(a["wis"]["mod"]) == 0, "wis 10 -> +0")
	check(int(a["cha"]["mod"]) == -1, "cha 8 -> -1")
	check(int(a["con"]["mod"]) == 1, "con 13 -> +1")

	# the soldier background's 3-point ASI
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	a = _resolved_abilities(ch)["abilities"]
	check(int(a["str"]["total"]) == 17 and int(a["str"]["mod"]) == 3, "background ASI +2 str -> 17 (+3)")
	check(int(a["con"]["total"]) == 14, "background ASI +1 con -> 14")

	# over-allocation is skipped with a warning
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 3, "con": 3}})
	var r := _resolved_abilities(ch)
	check(int(r["abilities"]["str"]["total"]) == 15, "over-allocated ASI is skipped")
	check(r["warnings"].size() == 1, "over-allocated ASI warns")

	# out-of-pool allocation is skipped (soldier's pool is str/dex/con)
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"int": 3}})
	r = _resolved_abilities(ch)
	check(int(r["abilities"]["int"]["total"]) == 12, "out-of-pool ASI is skipped")
	check(r["warnings"].size() == 1, "out-of-pool ASI warns")

	# cap 20
	ch.base_abilities["str"] = 19
	ch.decide("asi:background:soldier:0", {"type": "asi", "allocation": {"str": 2, "con": 1}})
	a = _resolved_abilities(ch)["abilities"]
	check(int(a["str"]["total"]) == 20 and int(a["str"]["mod"]) == 5, "ability total caps at 20")

func test_profs() -> void:
	var ch := _fighter(1)
	ch.base_abilities = {"str": 16, "dex": 14, "con": 14, "int": 10, "wis": 12, "cha": 8}
	ch.decide("skill-choice:class:fighter:0", {"type": "skill-choice", "skills": ["athletics", "perception"]})
	var b: Array = Bundles.collect(ch)["bundles"]
	var a: Dictionary = PassAbilities.resolve(ch.base_abilities, b, ch.choices)["abilities"]
	var pb := Bundles.proficiency_bonus(1)
	check(pb == 2, "PB at level 1 is 2")

	var s := PassProfs.saves(a, b, pb, ch.choices)
	check(s["save_prof"]["str"] and s["save_prof"]["con"], "fighter is proficient in STR and CON saves")
	check(not s["save_prof"]["dex"], "fighter is not proficient in DEX saves")
	check(int(s["saves"]["str"]) == 5, "STR save = +3 mod + 2 PB")
	check(int(s["saves"]["dex"]) == 2, "DEX save = +2 mod, no PB")

	var sk := PassProfs.skills(a, b, pb, ch.choices)
	check(sk["skill_prof"]["athletics"] == "prof", "chosen skill is proficient")
	check(int(sk["skills"]["athletics"]) == 5, "athletics = +3 STR + 2 PB")
	check(sk["skill_prof"]["intimidation"] == "prof", "background skill is proficient")
	check(sk["skill_prof"]["arcana"] == "none", "an ungranted skill is not proficient")
	check(int(sk["skills"]["arcana"]) == 0, "arcana = +0 INT")

	var p := PassProfs.proficiencies(b, ch.choices)
	check("heavy" in p["armor"] and "shields" in p["armor"], "fighter armor proficiencies")
	check("martial" in p["weapon"], "fighter weapon proficiencies")
	check("common" in p["language"], "human speaks common")
	var pending_types: Array = []
	for x in p["pending"]:
		pending_types.append(x["type"])
	check("language-choice" in pending_types, "undecided language choices are pending")

func test_expertise_and_half_proficiency() -> void:
	# Rogue 1: expertise doubles PB on the two chosen skills.
	var ch := Character.new()
	ch.species_id = "human"; ch.background_id = "soldier"
	ch.base_abilities = {"str": 10, "dex": 17, "con": 12, "int": 12, "wis": 12, "cha": 10}
	ch.add_level("rogue", -1)
	ch.decide("skill-choice:class:rogue:0", {"type": "skill-choice", "skills": ["stealth", "acrobatics", "perception", "deception"]})
	ch.decide("expertise-choice:class:rogue:0", {"type": "expertise-choice", "skills": ["stealth"], "tools": []})
	var b: Array = Bundles.collect(ch)["bundles"]
	var a: Dictionary = PassAbilities.resolve(ch.base_abilities, b, ch.choices)["abilities"]
	var sk := PassProfs.skills(a, b, 2, ch.choices)
	check(sk["skill_prof"]["stealth"] == "expert", "expertise recorded")
	check(int(sk["skills"]["stealth"]) == 7, "stealth = +3 DEX + 2 PB + 2 expertise")
	check(int(sk["skills"]["acrobatics"]) == 5, "acrobatics = +3 DEX + 2 PB (no expertise)")

	# Champion 7's Remarkable Athlete: half PB (rounded up) on STR/DEX/CON checks,
	# only where not already proficient.
	var f := _fighter(7)
	f.base_abilities = {"str": 16, "dex": 10, "con": 14, "int": 10, "wis": 10, "cha": 10}
	f.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "champion"})
	f.decide("skill-choice:class:fighter:0", {"type": "skill-choice", "skills": ["athletics", "perception"]})
	var fb: Array = Bundles.collect(f)["bundles"]
	var fa: Dictionary = PassAbilities.resolve(f.base_abilities, fb, f.choices)["abilities"]
	var fsk := PassProfs.skills(fa, fb, 3, f.choices)
	check(int(fsk["skills"]["acrobatics"]) == 2, "Remarkable Athlete adds ceil(3/2)=2 to a non-proficient DEX skill")
	check(int(fsk["skills"]["athletics"]) == 6, "no half-PB where already proficient (+3 STR +3 PB)")
	check(int(fsk["skills"]["arcana"]) == 0, "Remarkable Athlete does not touch INT skills")

# --- step 5: pass_defense + pass_pools -----------------------------------

func _build(cid: String, n: int, abil: Dictionary, decisions := {}) -> Character:
	var ch := Character.new()
	ch.species_id = "human"; ch.background_id = "soldier"
	ch.base_abilities = abil
	for i in n:
		ch.add_level(cid, -1)
	for k in decisions:
		ch.decide(k, decisions[k])
	return ch

func test_hp() -> void:
	var abil := {"str": 16, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 10}  # CON +2
	var f1 := _build("fighter", 1, abil)
	var b1: Array = Bundles.collect(f1)["bundles"]
	check(PassDefense.hp(b1, [-1], 2, 1) == 12, "fighter 1: d10 max + 2 CON = 12")

	var f5 := _build("fighter", 5, abil)
	var b5: Array = Bundles.collect(f5)["bundles"]
	# average: 10+2 then 4x(6+2) = 44
	check(PassDefense.hp(b5, [-1, -1, -1, -1, -1], 2, 5) == 44, "fighter 5 on averages = 44")
	check(PassDefense.hp(b5, [-1, 10, 10, 10, 10], 2, 5) == 60, "fighter 5 with max rolls = 60")

	var w20 := _build("wizard", 20, abil)
	var b20: Array = Bundles.collect(w20)["bundles"]
	var rolls: Array = []
	for i in 20:
		rolls.append(-1)
	# d6: 6+2 then 19x(4+2) = 122
	check(PassDefense.hp(b20, rolls, 2, 20) == 122, "wizard 20 on averages = 122")

	# Dwarf hp-bonus is +1 per level
	var d := _build("fighter", 5, abil)
	d.species_id = "dwarf"
	var db: Array = Bundles.collect(d)["bundles"]
	check(PassDefense.hp(db, [-1, -1, -1, -1, -1], 2, 5) == 49, "dwarf fighter 5 = 44 + 5 hp-bonus")

func test_ac() -> void:
	# Barbarian unarmored: 10 + DEX + CON
	var abil := {"str": 16, "dex": 14, "con": 16, "int": 10, "wis": 14, "cha": 10}
	var bb := _build("barbarian", 1, abil)
	var b: Array = Bundles.collect(bb)["bundles"]
	var a: Dictionary = PassAbilities.resolve(abil, b, bb.choices)["abilities"]
	check(int(PassDefense.ac(b, a, null)["ac"]) == 15, "barbarian unarmored AC = 10 + 2 DEX + 3 CON")

	# Monk unarmored: 10 + DEX + WIS
	var mk := _build("monk", 1, abil)
	var mb: Array = Bundles.collect(mk)["bundles"]
	var ma: Dictionary = PassAbilities.resolve(abil, mb, mk.choices)["abilities"]
	check(int(PassDefense.ac(mb, ma, null)["ac"]) == 14, "monk unarmored AC = 10 + 2 DEX + 2 WIS")

	# Armored: chain mail (16, no DEX) + shield
	var f := _build("fighter", 1, abil)
	var fb: Array = Bundles.collect(f)["bundles"]
	var fa: Dictionary = PassAbilities.resolve(abil, fb, f.choices)["abilities"]
	check(int(PassDefense.ac(fb, fa, {"totalBase": 16, "shieldBonus": 2})["ac"]) == 18,
		"chain mail + shield = 18")
	check(int(PassDefense.ac(fb, fa, null)["ac"]) == 12, "unequipped armored calc falls back to 10 + DEX")

func test_speed() -> void:
	var h := _build("fighter", 1, {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10})
	check(int(PassDefense.speed(Bundles.collect(h)["bundles"])["walk"]) == 30, "human walk 30 ft")

	# Elf lineage grants a climb/swim walk-equivalent in some species; assert the
	# second pass at least never invents a mode with no walk speed.
	var s := PassDefense.speed([{"source": {"origin": "species", "id": "x"},
		"grants": [{"type": "speed", "mode": "climb", "value": "walk-equivalent"}]}])
	check(s.is_empty(), "walk-equivalent with no walk speed is dropped")
	var s2 := PassDefense.speed([{"source": {"origin": "species", "id": "x"},
		"grants": [{"type": "speed", "mode": "walk", "value": 30},
			{"type": "speed", "mode": "climb", "value": "walk-equivalent"}]}])
	check(int(s2["climb"]) == 30, "walk-equivalent resolves to the walk speed")

func test_pools() -> void:
	var abil := {"str": 16, "dex": 14, "con": 14, "int": 10, "wis": 14, "cha": 14}
	# Rage: 2/3/4/5/6 at barbarian 1/3/6/12/17
	for pair in [[1, 2], [2, 2], [3, 3], [5, 3], [6, 4], [11, 4], [12, 5], [16, 5], [17, 6], [20, 6]]:
		var ch := _build("barbarian", pair[0], abil)
		var pools: Array = PassPools.resolve(Bundles.collect(ch)["bundles"])["pools"]
		var mx := -1
		for p in pools:
			if p["id"] == "rage":
				mx = int(p["max"])
		check(mx == pair[1], "barbarian %d rages = %d (got %d)" % [pair[0], pair[1], mx])

	# class-level pools
	var monk := _build("monk", 7, abil)
	var mp: Array = PassPools.resolve(Bundles.collect(monk)["bundles"])["pools"]
	var focus := -1
	for p in mp:
		if p["id"] == "focus-points":
			focus = int(p["max"])
	check(focus == 7, "monk 7 has 7 focus points")

	var sorc := _build("sorcerer", 5, abil)
	var sp: Array = PassPools.resolve(Bundles.collect(sorc)["bundles"])["pools"]
	var sorcery := -1
	for p in sp:
		if p["id"] == "sorcery-points":
			sorcery = int(p["max"])
	check(sorcery == 5, "sorcerer 5 has 5 sorcery points")

	# proficiency-bonus pool
	var pal := _build("paladin", 9, abil)
	var pp: Array = PassPools.resolve(Bundles.collect(pal)["bundles"])["pools"]
	var cd := -1
	for p in pp:
		if p["id"] == "channel-divinity":
			cd = int(p["max"])
	check(cd == 4, "paladin 9 Channel Divinity = PB 4")

	# dieSizeSteps, on a level-steps pool
	var ek := _build("fighter", 5, abil)
	ek.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "psiwarrior"})
	var ep: Array = PassPools.resolve(Bundles.collect(ek)["bundles"])["pools"]
	var psi := {}
	for p in ep:
		if p["id"] == "psionic-energy":
			psi = p
	check(int(psi.get("max", -1)) == 6, "psi warrior 5 has 6 psionic energy dice")
	check(int(psi.get("die_size", -1)) == 8, "psi warrior 5 psionic die is d8")
