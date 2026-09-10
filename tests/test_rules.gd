# F2 rules engine — one test per build step in the A0 spec §10.
#   godot --headless --path . -s tests/test_rules.gd
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Grants = preload("res://core/rules/grants.gd")
const Choice = preload("res://core/rules/choice.gd")
const Bundles = preload("res://core/rules/bundles.gd")
const Character = preload("res://core/character.gd")

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
