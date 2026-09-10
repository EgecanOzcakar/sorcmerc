# F2 rules engine — one test per build step in the A0 spec §10.
#   godot --headless --path . -s tests/test_rules.gd
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Grants = preload("res://core/rules/grants.gd")
const Choice = preload("res://core/rules/choice.gd")

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
