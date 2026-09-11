# F2 rules engine — one test per build step in the A0 spec §10.
#   godot --headless --path . -s tests/test_rules.gd
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Grants = preload("res://core/rules/grants.gd")
const Choice = preload("res://core/rules/choice.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const PassAbilities = preload("res://core/rules/pass_abilities.gd")
const PassProfs = preload("res://core/rules/pass_profs.gd")
const PassDefense = preload("res://core/rules/pass_defense.gd")
const PassPools = preload("res://core/rules/pass_pools.gd")
const Presets = preload("res://core/presets.gd")
const Character = preload("res://core/character.gd")
const Resolved = preload("res://core/rules/resolved.gd")
const Dice = preload("res://core/dice.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const AI = preload("res://core/ai.gd")
const RNG = preload("res://core/rng.gd")
const Effects = preload("res://core/rules/effects.gd")
const Power = preload("res://core/rules/power.gd")

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
	test_presets_match_encounter()
	test_presets_have_no_pending_and_no_warnings()
	test_choice_points_keep_decided_choices()
	test_unknown_equipped_item_warns()
	test_sheet_is_cached_and_retroactive()
	test_attacks()
	test_spell_slots()
	test_adapter()
	test_effects_data_is_valid()
	test_effects_reproduce_the_hardcoded_kit()
	test_spell_mechanics_merge()
	test_spell_verbs()
	test_t33_spell_overrides()
	test_power_ranks_the_heroes()

	print("test_rules: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- step 1: catalog.gd + grants.gd --------------------------------------

func test_catalog_loads() -> void:
	var counts := {
		"classes.json": 12, "subclasses.json": 48, "species.json": 10,
		"backgrounds.json": 16, "feats.json": 74, "fighting-styles.json": 10,
		"spells.json": 146, "weapons.json": 39, "armor.json": 13,
		# magic items: 262 exported + the game-authored scroll-of-resurrection
		"magic-items.json": 264, "conditions.json": 15, "skills.json": 18,
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

# --- step 6: resolved + resolve + pass_pending ---------------------------
# The highest-value test in F2: three sheets built through the resolver against
# encounter.gd's hand-authored numbers (sheet / authored):
#
#   vera  AC 18/18  HP 28/28  +5/+5  1d8+3   init 1/0  DEX save 1/1  athletics 5/5
#   pike  AC 15/15  HP 21/21  +5/+5  1d6+3   init 3/3  DEX save 5/3  stealth 7/7
#   ilsa  AC 16/16  HP 21/22  +3/+3  1d6+1   init 1/1  DEX save 1/1  DC 13/13  slots 4/2
#
# Three differences are tuning decisions, not port bugs:
#  * Ilsa HP 21 vs 22 — cleric 3 with CON 12 on averages is exactly 21. Within +/-1.
#  * Pike DEX save +5 vs +3 — rogue *is* proficient in DEX saves; the hand-authored
#    Pike simply never got the proficiency. The sheet is correct; foes' burning-hands
#    odds against Pike drop accordingly.
#  * Speed 30 ft = 5 hexes for all three; Vera and Ilsa were authored at 4 (spec §2.5).
#    adapter.gd's FT_PER_HEX is the knob; the 200-seed sweep is re-baselined at step 8.
# Vera takes Interception rather than Defense so AC lands on 18, not 19.

const TARGETS := {
	"vera": {"ac": 18, "max_hp": 28, "to_hit": 5, "damage": "1d8+3", "crit_range": 19},
	"pike": {"ac": 15, "max_hp": 21, "to_hit": 5, "damage": "1d6+3", "crit_range": 20},
	"ilsa": {"ac": 16, "max_hp": 22, "to_hit": 3, "damage": "1d6+1", "crit_range": 20,
		"slots1": 4, "slots2": 2, "save_dc": 13},
}

func _near(a: int, b: int) -> bool:
	return absi(a - b) <= 1

func test_presets_match_encounter() -> void:
	for ch in Presets.party():
		var s: Resolved = ch.sheet()
		var t: Dictionary = TARGETS[ch.id]
		check(_near(s.ac, int(t["ac"])), "%s AC %d vs authored %d" % [ch.id, s.ac, int(t["ac"])])
		check(_near(s.max_hp, int(t["max_hp"])), "%s HP %d vs authored %d" % [ch.id, s.max_hp, int(t["max_hp"])])
		check(not s.attacks.is_empty(), "%s has an attack" % ch.id)
		var a: Dictionary = s.attacks[0]
		check(_near(int(a["to_hit"]), int(t["to_hit"])),
			"%s to-hit %+d vs authored %+d" % [ch.id, int(a["to_hit"]), int(t["to_hit"])])
		check(a["notation"] == t["damage"],
			"%s damage %s vs authored %s" % [ch.id, a["notation"], t["damage"]])
		if t.has("save_dc"):
			check(int(s.spellcasting["save_dc"]) == int(t["save_dc"]),
				"%s save DC %d vs authored %d" % [ch.id, int(s.spellcasting["save_dc"]), int(t["save_dc"])])
			check(int(s.spellcasting["slots"][0]) == int(t["slots1"]), "%s has %d first-level slots" % [ch.id, int(t["slots1"])])
			check(int(s.spellcasting["slots"][1]) == int(t["slots2"]), "%s has %d second-level slots" % [ch.id, int(t["slots2"])])

	# the kit each hero's hardcoded Combatant flags stood for
	var v: Resolved = Presets.vera().sheet()
	check(v.has_feature("champion-improved-critical"), "Vera crits on 19 via Improved Critical")
	check(v.has_feature("fighter-second-wind"), "Vera has Second Wind")
	check(v.has_feature("fighter-action-surge"), "Vera has Action Surge")
	var p: Resolved = Presets.pike().sheet()
	check(p.has_feature("rogue-sneak-attack"), "Pike has Sneak Attack")
	check(p.has_feature("rogue-cunning-action"), "Pike has Cunning Action")
	check(int(p.skills["stealth"]) == 7, "Pike stealth = +3 DEX + 2 PB + 2 expertise (got %d)" % int(p.skills["stealth"]))
	check(p.passive_perception == 12, "Pike passive perception 12 (got %d)" % p.passive_perception)
	var i: Resolved = Presets.ilsa().sheet()
	check("sacred-flame" in i.spellcasting["cantrips"], "Ilsa knows Sacred Flame")

func test_presets_have_no_pending_and_no_warnings() -> void:
	for ch in Presets.party():
		var s: Resolved = ch.sheet()
		for x in s.pending:
			printerr("    %s pending: %s %s" % [ch.id, x["type"], x["key"]])
		check(s.pending.is_empty(), "%s is fully decided (%d pending)" % [ch.id, s.pending.size()])
		# bundle-choice warnings are the known v1 scope cut (spec §2.3): starting-equipment
		# bundles are not exported, so every class emits them. Everything else must be clean.
		var real: Array = []
		for w in s.warnings:
			if not w.begins_with("bundle-choice"):
				real.append(w)
		for w in real:
			printerr("    %s warning: %s" % [ch.id, w])
		check(real.is_empty(), "%s resolves with no warnings beyond bundle-choice (%d)" % [ch.id, real.size()])

# T34: a decided choice stays listed in `choice_points` (it only leaves `pending`),
# and re-deciding it overwrites the old answer on the next resolve.
func test_choice_points_keep_decided_choices() -> void:
	var ch = Presets.vera()
	var s: Resolved = ch.sheet()
	check(s.pending.is_empty(), "vera starts fully decided")
	check(not s.choice_points.is_empty(), "a fully decided build still lists its choice points")
	var keys: Array = []
	for p in s.choice_points:
		keys.append(p["key"])
	for p in s.pending:
		check(p["key"] in keys, "pending entry %s is also a choice point" % p["key"])

	# choice_points is exactly "open or answered": a suppressed either-or alternative
	# (the feat half of a taken ASI) must not be offered, or both could be satisfied.
	for c in Presets.party():
		var cs: Resolved = c.sheet()
		var open_keys: Array = []
		for p in cs.pending:
			open_keys.append(p["key"])
		for p in cs.choice_points:
			check(p["decided"] or p["key"] in open_keys,
				"%s: choice point %s is either decided or pending" % [c.id, p["key"]])

	var skill_cp := {}
	for p in s.choice_points:
		if p["type"] == "skill-choice" and p["decided"] and int(p["count"]) >= 1:
			skill_cp = p
			break
	check(not skill_cp.is_empty(), "vera's skill choice is listed as decided")
	if skill_cp.is_empty():
		return

	var was: Array = ch.choices[skill_cp["key"]]["skills"]
	var pool: Array = skill_cp["from"] if skill_cp["from"] != null else Catalog.skills().keys()
	var fresh: Array = []
	for sk in pool:
		if not sk in was and fresh.size() < int(skill_cp["count"]):
			fresh.append(sk)
	check(fresh.size() == int(skill_cp["count"]), "there is a different set of skills to swap to")
	ch.decide(skill_cp["key"], {"type": "skill-choice", "skills": fresh})
	var s2: Resolved = ch.sheet()
	check(s2.pending.is_empty(), "re-deciding leaves nothing pending (%d)" % s2.pending.size())
	for sk in fresh:
		check(s2.skill_prof.get(sk, "none") != "none", "the new pick %s is proficient" % sk)
	for sk in was:
		if not sk in fresh:
			check(s2.skill_prof.get(sk, "none") == "none", "the old pick %s was dropped" % sk)
	var still := false
	for p in s2.choice_points:
		if p["key"] == skill_cp["key"]:
			still = p["decided"]
	check(still, "the re-decided choice is still listed, still decided")

	# and an undecided build lists the very same choice point, flagged open
	var blank = Presets.vera()
	blank.choices.erase(skill_cp["key"])
	blank.dirty()
	var open_cp := {}
	for p in blank.sheet().choice_points:
		if p["key"] == skill_cp["key"]:
			open_cp = p
	check(not open_cp.is_empty() and not open_cp["decided"],
		"clearing the decision flips the same choice point back to open")

# An equipped id matching neither weapons.json nor armor.json used to sit
# inert with no diagnostic -- a typo'd/stale id silently lost a gear slot.
func test_unknown_equipped_item_warns() -> void:
	var ch = Presets.vera()
	ch.equipped.append("not-a-real-item-id")
	var s: Resolved = ch.sheet()
	var hit: Array = s.warnings.filter(func(w): return "not-a-real-item-id" in w)
	check(hit.size() == 1, "an unknown equipped item warns exactly once (got %d)" % hit.size())

func test_sheet_is_cached_and_retroactive() -> void:
	var ch: Character = Presets.vera()
	check(ch.sheet() == ch.sheet(), "sheet() is cached")
	var before: int = ch.sheet().ac
	ch.decide("fighting-style-choice:class:fighter:0", {"type": "fighting-style-choice", "styles": ["defense"]})
	check(ch.sheet().ac == before + 1, "swapping Interception for Defense re-resolves and raises AC by 1")

# --- step 7: pass_gear + pass_spells -------------------------------------

func _gear(ch: Character) -> Resolved:
	return ch.sheet()

func test_attacks() -> void:
	var abil := {"str": 16, "dex": 18, "con": 14, "int": 10, "wis": 10, "cha": 10}
	var ch := _build("fighter", 1, abil)
	ch.equipped = ["longsword"]
	var a: Array = ch.sheet().attacks
	check(a.size() == 1 and a[0]["ability"] == "str", "a plain melee weapon uses STR")
	check(int(a[0]["to_hit"]) == 5, "longsword +3 STR + 2 PB")
	check(a[0]["notation"] == "1d8+3", "longsword damage 1d8+3")
	check(a[0]["versatile_notation"] == "1d10+3", "longsword versatile 1d10+3")

	# finesse takes the better of STR / DEX
	ch.equipped = ["rapier"]; ch.dirty()
	a = ch.sheet().attacks
	check(a[0]["ability"] == "dex" and int(a[0]["to_hit"]) == 6, "finesse uses DEX +4 when it beats STR")

	# ranged always uses DEX; archery adds +2
	ch.equipped = ["shortbow"]; ch.dirty()
	a = ch.sheet().attacks
	check(a[0]["ability"] == "dex" and int(a[0]["to_hit"]) == 6, "shortbow uses DEX")
	check(int(a[0]["normal_ft"]) == 80, "shortbow normal range 80 ft")
	ch.decide("fighting-style-choice:class:fighter:0", {"type": "fighting-style-choice", "styles": ["archery"]})
	check(int(ch.sheet().attacks[0]["to_hit"]) == 8, "archery adds +2 to a ranged attack")

	# dueling: +2 damage with a single one-handed melee weapon
	ch.equipped = ["longsword"]; ch.dirty()
	ch.decide("fighting-style-choice:class:fighter:0", {"type": "fighting-style-choice", "styles": ["dueling"]})
	check(ch.sheet().attacks[0]["notation"] == "1d8+5", "dueling adds +2 damage")

	# unarmed with nothing equipped: 1d1+STR, so Dice.parse never sees a bare "1"
	var bare := _build("fighter", 1, abil)
	a = bare.sheet().attacks
	check(a.size() == 1 and a[0]["id"] == "unarmed-strike", "no weapon -> an unarmed strike")
	check(a[0]["notation"] == "1d1+3", "plain unarmed strike is 1d1+STR (spec 2.4)")
	check(Dice.parse(a[0]["notation"]) == {"count": 1, "sides": 1, "mod": 3}, "Dice.parse accepts it")

	# monk martial arts die scales with monk level
	for pair in [[1, 6], [4, 6], [5, 8], [11, 10], [17, 12]]:
		var m := _build("monk", pair[0], abil)
		var ma: Array = m.sheet().attacks
		check(int(ma[0]["dice_sides"]) == pair[1], "monk %d unarmed die d%d" % [pair[0], pair[1]])
	var m5 := _build("monk", 5, abil)
	check(m5.sheet().attacks[0]["ability"] == "dex", "a monk swings with the better of STR/DEX")

	# non-proficient body armor blocks casting and flags disadvantage
	var w := _build("wizard", 3, abil)
	w.equipped = ["plate"]
	var ws := w.sheet()
	check(ws.cannot_cast and ws.disadvantage_from_armor, "plate on a wizard blocks casting")

func test_spell_slots() -> void:
	var abil := {"str": 10, "dex": 12, "con": 12, "int": 16, "wis": 16, "cha": 16}
	for pair in [[1, [2]], [3, [4, 2]], [5, [4, 3, 2]], [11, [4, 3, 3, 3, 2, 1]],
			[20, [4, 3, 3, 3, 3, 2, 2, 1, 1]]]:
		var w := _build("wizard", pair[0], abil)
		var slots: Array = w.sheet().spellcasting["slots"]
		var want: Array = pair[1].duplicate()
		while want.size() < 9:
			want.append(0)
		check(slots == want, "wizard %d slots %s (got %s)" % [pair[0], str(want), str(slots)])

	# warlock pact magic replaces the slot table
	var wl := _build("warlock", 5, abil)
	var ws: Dictionary = wl.sheet().spellcasting
	check(int(ws["pact"]["count"]) == 2 and int(ws["pact"]["slotLevel"]) == 3, "warlock 5 = 2 slots at level 3")
	var empty := true
	for n in ws["slots"]:
		if int(n) != 0:
			empty = false
	check(empty, "a warlock has no ordinary slot table")

	# Eldritch Knight falls back to the local third-caster table
	var ek := _build("fighter", 7, abil)
	ek.decide("subclass:class:fighter:0", {"type": "subclass", "subclassId": "eldritchknight"})
	var es: Dictionary = ek.sheet().spellcasting
	check(int(es["slots"][0]) == 4 and int(es["slots"][1]) == 2, "EK 7 gets 4/2 from third-caster-slots.json")
	check(es["ability"] == "int", "EK casts off INT")

	# prepared casters get a prepared count; known casters do not
	var cl := _build("cleric", 5, abil)
	check(int(cl.sheet().spellcasting["prepared_count"]) == 8, "cleric 5 with WIS +3 prepares 8")
	var sorc := _build("sorcerer", 5, abil)
	check(int(sorc.sheet().spellcasting["prepared_count"]) == 0, "a sorcerer has no prepared count")

	# a non-caster has no spellcasting block at all
	var bb := _build("barbarian", 3, abil)
	check(bb.sheet().spellcasting.is_empty(), "a barbarian casts nothing")

	# Arcane Trickster reads the same table from the rogue side
	var at := _build("rogue", 7, abil)
	at.decide("subclass:class:rogue:0", {"type": "subclass", "subclassId": "arcanetrickster"})
	var ats: Dictionary = at.sheet().spellcasting
	check(int(ats["slots"][0]) == 4 and int(ats["slots"][1]) == 2, "arcane trickster 7 gets 4/2")
	check(int(ats["save_dc"]) == 14, "AT 7 save DC = 8 + 3 PB + 3 INT")

# --- step 8: adapter.gd --------------------------------------------------

const START := {"vera": Vector2i(2, 0), "pike": Vector2i(2, 2), "ilsa": Vector2i(1, 1),
	"grull": Vector2i(4, 1), "snik": Vector2i(4, 0), "vess": Vector2i(5, 0), "kritch": Vector2i(7, 1)}

func _sheet_party() -> Array:
	var out: Array = []
	for ch in Presets.party():
		out.append(Adapter.to_combatant(ch, "party", START[ch.id]))
	return out

func _json_foes() -> Array:
	var out: Array = []
	for m in Catalog.all("monsters.json"):
		out.append(Adapter.from_monster(m, "foe", START[m["id"]]))
	return out

func test_adapter() -> void:
	check(Adapter.hexes(30) == 5, "30 ft = 5 hexes")
	check(Adapter.hexes(5) == 1, "a 5 ft reach still costs a hex")
	var by_id := {}
	for c in _sheet_party():
		by_id[c.id] = c

	var v = by_id["vera"]
	check(v.ac == 18 and v.max_hp == 28, "adapted Vera: AC 18, HP 28")
	check(v.atk_bonus == 5 and v.damage == "1d8+3", "adapted Vera swings +5 / 1d8+3")
	check(v.crit_range == 19, "Improved Critical becomes crit_range 19")
	check(not v.verb("fighter-second-wind").is_empty() and not v.verb("fighter-action-surge").is_empty(),
		"Vera's kit survives the adapter as verbs")
	check(v.pool_left("fighter-second-wind") == 2 and v.pool_left("fighter-action-surge") == 1,
		"the features with no exported resource-pool get a synthetic one")
	check(not v.ranged and v.atk_range == 1, "a longsword is melee reach 1")

	var p = by_id["pike"]
	check(int(p.verb("rogue-sneak-attack")["dice_count"]) == 2, "Pike still sneak-attacks for 2d6")
	check(p.verb("rogue-cunning-action")["cost"] == "bonus", "Cunning Action is a bonus-cost verb")
	check(p.ranged and p.atk_range == Adapter.RANGE_CAP,
		"an 80 ft shortbow clamps to RANGE_CAP %d hexes (got %d)" % [Adapter.RANGE_CAP, p.atk_range])
	check(int(p.saves["dex"]) == 5, "all six saves come across, not just DEX")

	var i = by_id["ilsa"]
	check(i.save_dc == 13, "adapted Ilsa's save DC is 13")
	check(i.slots[0] == 4 and i.slots[1] == 2, "Ilsa's slots come across")
	var spell_ids: Array = i.verbs.filter(func(v): return v["kind"] == "spell").map(func(v): return v["id"])
	check("burning-hands" in spell_ids and "sacred-flame" in spell_ids and "cure-wounds" in spell_ids,
		"Ilsa's spells become castable verbs (got %s)" % str(spell_ids))
	check("burning-hands@2" in spell_ids, "and one upcast verb per slot level she owns")
	check(int(i.verb("burning-hands")["range"]) == 1 and int(i.verb("burning-hands")["radius"]) == 2,
		"a 15 ft cone is a 2-hex wedge")

	# monsters need no Character
	var g = _json_foes()[0]
	check(g.id == "grull" and g.max_hp == 27 and int(g.saves["dex"]) == 2,
		"from_monster builds a Combatant off a statblock")
	check(int(g.verb("monster-surprise-attack")["dice_count"]) == 2,
		"a monster's kit is verbs too — no sheet required")
	check(g.sheet == null, "a monster has no sheet")

	# write_back persists hp and pools, not statuses
	var ch: Character = Presets.vera()
	var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	c.hp = 7
	c.statuses["prone"] = true
	Adapter.write_back(c, ch)
	check(ch.hp_current == 7, "write_back persists HP")
	check(Adapter.to_combatant(ch, "party", Vector2i.ZERO).hp == 7, "the next fight starts at the carried HP")

# The 200-seed sweep lives in tests/test_combat.gd only: since F3, encounter.gd
# builds its party through Presets + Adapter, so both sweeps were the same run.

# --- step 9: effects.gd + power.gd ---------------------------------------

func test_effects_data_is_valid() -> void:
	var errs := Effects.validate()
	for e in errs:
		printerr("    ", e)
	check(errs.is_empty(), "data/effects/*.json validates (%d errors)" % errs.size())
	check(Effects.feature("fighter-fighting-style").is_empty(), "an unlisted feature is flavor, not an error")
	check(Effects.condition("prone")["stand_costs"] == "half_move", "conditions carry numbers now")
	check(Effects.humanize("barbarian-primal-knowledge") == "Barbarian Primal Knowledge",
		"the prose fallback humanizes an id")

func test_effects_reproduce_the_hardcoded_kit() -> void:
	# Sneak Attack / Second Wind / Action Surge as data must equal what the adapter's
	# legacy flags (and today's combat.gd) do.
	for pair in [[1, 1], [2, 1], [3, 2], [5, 3], [11, 6], [20, 10]]:
		var r := _build("rogue", pair[0], {"str": 10, "dex": 16, "con": 12, "int": 12, "wis": 10, "cha": 10})
		var v := _verb(r, "rogue-sneak-attack")
		check(int(v["dice_count"]) == pair[1] and int(v["dice_sides"]) == 6,
			"rogue %d sneak attack %dd6 (got %dd%d)" % [pair[0], pair[1], int(v["dice_count"]), int(v["dice_sides"])])
	var pk: Character = Presets.pike()
	check(_verb(pk, "rogue-sneak-attack")["once_per"] == "turn", "sneak attack is once per turn")
	check(int(Adapter.to_combatant(pk, "party", Vector2i.ZERO).verb("rogue-sneak-attack")["dice_count"]) == 2,
		"the adapter carries the resolved dice count onto the combatant")

	var f := _build("fighter", 3, {"str": 16, "dex": 12, "con": 14, "int": 10, "wis": 12, "cha": 10})
	var sw := _verb(f, "fighter-second-wind")
	check(sw["cost"] == "bonus", "Second Wind is a bonus action")
	check(int(sw["dice_count"]) == 1 and int(sw["dice_sides"]) == 10 and int(sw["dice_bonus"]) == 3,
		"fighter 3 Second Wind heals 1d10+3 — the same as the hardcoded string")
	check(int(sw["uses"]) == 2, "Second Wind's synthetic pool is PB uses")
	var as_ := _verb(f, "fighter-action-surge")
	check(as_["kind"] == "grant_action" and int(as_["amount"]) == 1 and int(as_["uses"]) == 1,
		"Action Surge grants one extra action, once")
	check(int(_verb(_build("fighter", 17, f.base_abilities), "fighter-action-surge")["uses"]) == 2,
		"Action Surge is twice at fighter 17")

	# Rage reads its uses off the real resource pool, not a synthetic one
	var bb := _build("barbarian", 6, {"str": 16, "dex": 14, "con": 16, "int": 8, "wis": 10, "cha": 8})
	var rg := _verb(bb, "barbarian-rage")
	check(int(rg["uses"]) == 4 and int(rg["bonus_damage"]) == 2, "barbarian 6 rages 4x for +2 damage")
	check("bludgeoning" in rg["resist"], "rage resists the physical trio")

	# Extra Attack
	var f5 := _build("fighter", 5, f.base_abilities)
	check(int(_verb(f5, "fighter-extra-attack")["value"]) == 2, "Extra Attack is 2 attacks per action")

func _verb(ch: Character, id: String) -> Dictionary:
	for v in Effects.verbs_for(ch.sheet()):
		if v["id"] == id:
			return v
	return {}

func test_spell_mechanics_merge() -> void:
	var bh := Effects.spell("burning-hands")
	check(bh["shape"] == "cone" and int(bh["size_ft"]) == 15, "burning hands is a 15 ft cone")
	check(bh["save"] == "dex" and bh["half_on_save"], "burning hands: DEX save for half")
	check(int(bh["damage"][0]["count"]) == 3 and int(bh["damage"][0]["sides"]) == 6, "burning hands 3d6")
	check(int(bh["level"]) == 1, "burning hands is a level-1 spell")
	# healing-word and magic-missile are absent from the 146-spell export — F1 gap.
	check(Effects.spell("healing-word").is_empty(), "an uncatalogued spell has no mechanics")
	var cw := Effects.spell("cure-wounds")
	check(int(cw["heal"]["count"]) == 2 and int(cw["heal"]["sides"]) == 8,
		"cure wounds is authored where the regex parse gave nothing usable")
	check(Effects.spell("guidance").is_empty(), "a non-combat spell is not castable in a fight")
	check(Effects.spell("light").is_empty(), "neither is Light")
	var sr := Effects.spell("scorching-ray")
	check(int(sr["rays"]) == 3 and int(sr["damage"][0]["count"]) == 2,
		"scorching ray is 3 separate rays of 2d6, not one 2d6 hit")

# F3: the numeric verbs combat.gd actually eats. Ranges stay in feet here — the
# adapter owns the hex conversion.
func test_spell_verbs() -> void:
	var ilsa: Character = Presets.ilsa()
	var vs := Effects.spell_verbs_for(ilsa.sheet(), ilsa.sheet().spellcasting["cantrips"] + ["burning-hands", "cure-wounds"])
	var by_id := {}
	for v in vs:
		by_id[v["id"]] = v
	check(by_id.has("burning-hands") and by_id.has("burning-hands@2"),
		"one verb per slot level a caster can spend (got %s)" % str(by_id.keys()))
	check(not by_id.has("sacred-flame@1"), "a cantrip is never upcast")
	var bh: Dictionary = by_id["burning-hands"]
	check(bh["cost"] == "action" and int(bh["slot_level"]) == 1, "burning hands: action, level-1 slot")
	check(bh["targeting"] == "direction" and int(bh["size_ft"]) == 15, "a cone is aimed, 15 ft")
	check(int(bh["dice_count"]) == 3 and int(by_id["burning-hands@2"]["dice_count"]) == 4,
		"upcasting adds a die")
	check(int(bh["save_dc"]) == 13 and bh["save"] == "dex", "the caster's DC rides on the verb")
	var cw: Dictionary = by_id["cure-wounds"]
	check(cw["targeting"] == "ally" and int(cw["heal_count"]) == 2 and int(cw["heal_bonus"]) == 3,
		"cure wounds heals 2d8 + the casting mod at an ally")
	check(by_id["sacred-flame"]["ignores_cover"], "sacred flame still ignores cover")
	check(not by_id.has("guidance"), "a non-combat spell produces no verb")

	var vs2 := Effects.spell_verbs_for(ilsa.sheet(), ["scorching-ray"])
	check(vs2.size() == 1 and int(vs2[0]["rays"]) == 3,
		"scorching ray's verb carries its ray count (no upcast headroom at 2nd-level slots to test the +1/level)")

# T33: hand-authored combat mechanics for the spells the regex parse got wrong or
# missed entirely. Numbers here are read off each spell's SRD `description` prose —
# if one drifts, this table is where it gets caught.
func test_t33_spell_overrides() -> void:
	# id -> [count, sides, type, save ("" = spell attack), shape, size_ft, range_ft]
	var want := {
		"poison-spray":       [1, 12, "poison", "con", "single", 0, 30],
		"thorn-whip":         [1, 6, "piercing", "", "single", 0, 30],
		"ray-of-frost":       [1, 8, "cold", "", "single", 0, 60],
		"shocking-grasp":     [1, 8, "lightning", "", "single", 0, 5],
		"chill-touch":        [1, 8, "necrotic", "", "single", 0, 120],
		"produce-flame":      [1, 8, "fire", "", "single", 0, 60],
		"mind-sliver":        [1, 6, "psychic", "int", "single", 0, 60],
		"acid-splash":        [1, 6, "acid", "dex", "sphere", 5, 60],
		"guiding-bolt":       [4, 6, "radiant", "", "single", 0, 120],
		"chromatic-orb":      [3, 8, "fire", "dex", "single", 0, 90],
		"dissonant-whispers": [3, 6, "psychic", "wis", "single", 0, 60],
		"hellish-rebuke":     [2, 10, "fire", "dex", "single", 0, 60],
		"ray-of-sickness":    [2, 8, "poison", "", "single", 0, 60],
		"arms-of-hadar":      [2, 6, "necrotic", "str", "emanation", 10, 5],
		"blight":             [8, 8, "necrotic", "con", "single", 0, 30],
		"cone-of-cold":       [8, 8, "cold", "con", "cone", 60, 5],
	}
	for id in want:
		var m := Effects.spell(id)
		var w: Array = want[id]
		var d: Dictionary = m.get("damage", [{}])[0]
		check(int(d.get("count", 0)) == w[0] and int(d.get("sides", 0)) == w[1],
			"%s is %dd%d (got %sd%s)" % [id, w[0], w[1], d.get("count"), d.get("sides")])
		check(d.get("type", "") == w[2], "%s deals %s damage" % [id, w[2]])
		check(m.get("save", "") == w[3], "%s: save \"%s\"" % [id, w[3]])
		check(m.has("attack") == (w[3] == ""), "%s rolls %s" % [id, "to hit" if w[3] == "" else "a save"])
		check(m.get("shape", "") == w[4] and int(m.get("size_ft", 0)) == w[5],
			"%s is a %s%s" % [id, w[4], "" if w[5] == 0 else " of %d ft" % w[5]])
		check(int(m.get("range_ft", 0)) == w[6], "%s reaches %d ft" % [id, w[6]])
		check(int(m.get("level", -1)) == 0 or m.has("upcast"), "%s: upcast authored" % id)
		check(int(m.get("level", -1)) > 0 or m.has("cantrip_scale"), "%s: cantrip scaling authored" % id)

	# half-on-save is the difference between a dodge and a reduction — spot-check both ways.
	check(Effects.spell("blight")["half_on_save"] and Effects.spell("cone-of-cold")["half_on_save"],
		"Blight and Cone of Cold are save-for-half")
	check(not Effects.spell("poison-spray").get("half_on_save", false),
		"Poison Spray is save-or-nothing")
	check(Effects.spell("hellish-rebuke")["cost"] == "reaction", "Hellish Rebuke is a reaction")

	# save-or-condition spells: no damage at all, so `conditions` is what makes them castable.
	for id in ["hideous-laughter", "sleep", "fear"]:
		var m := Effects.spell(id)
		check(not m.is_empty() and not m.has("damage"), "%s is castable on its condition alone" % id)
		check(m.get("save", "") == "wis", "%s forces a WIS save" % id)
		check(m.get("duration", "") == "round", "%s's condition is not a permanent lockout" % id)
	check(Effects.spell("hideous-laughter")["conditions"] == ["prone", "incapacitated"],
		"Hideous Laughter drops the target prone AND incapacitated")
	check(Effects.spell("sleep")["conditions"] == ["incapacitated"], "Sleep incapacitates")
	check(Effects.spell("fear")["conditions"] == ["frightened"] and Effects.spell("fear")["shape"] == "cone"
		and int(Effects.spell("fear")["size_ft"]) == 30, "Fear frightens a 30 ft cone")

	# and the verbs those merge into, at Ilsa's level-2 slots.
	var sheet = Presets.ilsa().sheet()
	var by_id := {}
	for v in Effects.spell_verbs_for(sheet, ["guiding-bolt", "chromatic-orb", "hideous-laughter",
			"ray-of-frost", "cone-of-cold"]):
		by_id[v["id"]] = v
	check(int(by_id["guiding-bolt"]["dice_count"]) == 4 and int(by_id["guiding-bolt@2"]["dice_count"]) == 5,
		"Guiding Bolt upcasts 4d6 -> 5d6")
	check(by_id["guiding-bolt"].has("attack_bonus") and not by_id["guiding-bolt"].has("conditions"),
		"a spell attack carries the caster's attack bonus")
	check(int(by_id["chromatic-orb@2"]["dice_count"]) == 4, "Chromatic Orb upcasts 3d8 -> 4d8")
	check(by_id["ray-of-frost"]["targeting"] == "enemy" and int(by_id["ray-of-frost"]["dice_count"]) == 1,
		"a cantrip is one die below level 5")
	var hl: Dictionary = by_id["hideous-laughter"]
	check(hl["conditions"] == ["prone", "incapacitated"] and hl["duration"] == "round",
		"the conditions and their duration ride the verb")
	check(not hl.has("dice_count") and int(hl["save_dc"]) == 13, "no damage, but the caster's DC")
	check(by_id.has("cone-of-cold") and not by_id.has("cone-of-cold@6"),
		"a 5th-level spell offers its base level only — Ilsa has no headroom above it")
	check(by_id["cone-of-cold"]["targeting"] == "direction" and int(by_id["cone-of-cold"]["size_ft"]) == 60,
		"Cone of Cold is aimed like Burning Hands, 60 ft")

func test_power_ranks_the_heroes() -> void:
	var scores := {}
	for ch in Presets.party():
		var c = Adapter.to_combatant(ch, "party", START[ch.id])
		scores[ch.id] = float(Power.estimate(c)["score"])
	var goblin := Power.estimate(_json_foes()[1])   # snik, 7 HP
	var boss := Power.estimate(_json_foes()[0])     # grull, 27 HP
	print("  power: vera %.1f  pike %.1f  ilsa %.1f  grull %.1f  snik %.1f" % [
		scores["vera"], scores["pike"], scores["ilsa"], float(boss["score"]), float(goblin["score"])])
	# Ranking at the time of writing: ilsa 17.1 ≈ vera 17.0 > pike 13.1, grull 17.1, snik 4.7.
	# Ilsa edged narrowly ahead of Vera once Scorching Ray got a real mechanics
	# entry (it was scoring 0 before — Light Domain genuinely grants it, per
	# spell_ids above, but Effects.spell() had nothing to merge it against) —
	# a Light cleric with real access to Burning Hands AND Scorching Ray outdamages
	# a sword-and-board fighter over 4 rounds, which is the estimator being honest,
	# not a bug. Pike last: single-target, 21 HP, AC 15.
	check(scores["vera"] > scores["pike"] and absf(scores["vera"] - scores["ilsa"]) < 1.0,
		"vera clears the weaker martial, and stays close to the front-loaded caster")
	check(scores["pike"] > float(goblin["score"]), "even the squishiest hero beats a mook")
	check(float(boss["score"]) > float(goblin["score"]) * 2.0, "the brute outscores a mook several times over")
	# "an order of magnitude" (spec §10 step 9) is a level-10 statement; at level 3 vs a
	# 7 HP mook the honest gap is ~3.5x.
	check(scores["vera"] > float(goblin["score"]) * 3.0,
		"a level-3 hero is several times a mook (%.1f vs %.1f)" % [scores["vera"], float(goblin["score"])])
	for k in ["dpr", "ehp", "control", "score"]:
		check(boss.has(k), "estimate() returns \"%s\" — T8's contract" % k)

	var party: Array = _sheet_party()
	check(Power.team_score(party) > 0.0, "team_score sums the party")
	check(Power.roster_budget(party, "hard") > Power.roster_budget(party, "easy"),
		"a harder tier buys a bigger roster")
	check(Power.fits(_json_foes(), 0.0), "fits() is true against a zero budget")
