# M1/M2/M6 — the pack pipeline: a manifest is parsed and validated, the
# registry finds packs in both roots and decides which are live, a paid pack
# stays locked until it is owned, and a live pack's data really does land in
# core/rules/catalog.gd.
#   godot --headless --path . -s tests/test_mod_packs.gd
extends SceneTree

const Manifest = preload("res://core/mod/manifest.gd")
const Registry = preload("res://core/mod/registry.gd")
const Entitlement = preload("res://core/mod/entitlement.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Scaler = preload("res://core/scaler.gd")
const Effects = preload("res://core/rules/effects.gd")
const Potions = preload("res://core/potions.gd")

var _pass := 0
var _fail := 0
var _root := ""

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var tag := "%d-%d" % [OS.get_process_id(), randi()]
	_root = "user://test/mods-%s" % tag
	OS.set_environment("SORCMERC_MODS_DIR", _root)
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/save-%s" % tag)
	OS.set_environment("SORCMERC_PLAYTEST", "")     # the playtest build unlocks everything
	OS.set_environment("SORCMERC_UNLOCK_DLC", "")
	DirAccess.make_dir_recursive_absolute(_root)

	test_manifest()
	test_manifest_rejects()
	test_entitlement()
	test_registry()
	test_overlays()
	test_effect_overlays()
	test_effect_overlays_reject()
	test_shipped_content()
	print("test_mod_packs: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- helpers ---------------------------------------------------------------

func _listed(packs: Array, pack_id: String) -> bool:
	for p in packs:
		if p.id() == pack_id:
			return true
	return false

func _write(pack_id: String, files: Dictionary) -> String:
	var dir := _root.path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in files:
		var f := FileAccess.open(dir.path_join(String(name)), FileAccess.WRITE)
		var body = files[name]
		f.store_string(body if body is String else JSON.stringify(body))
		f.close()
	return dir

func _manifest(pack_id: String, extra := {}) -> Dictionary:
	var d := {"format": Manifest.FORMAT, "api": 1, "id": pack_id,
		"title": pack_id.capitalize(), "authors": ["A Tester"]}
	d.merge(extra, true)
	return d

func _min_world() -> Dictionary:
	return {"format": "sorcmerc-world", "version": 1,
		"settlements": [{"id": "hold", "position": [0, 0], "faction": "human", "kind": "town"}],
		"start": {"at": "hold", "offset": [20, 0]}}

# --- manifests -------------------------------------------------------------

func test_manifest() -> void:
	var m = Manifest.parse(_manifest("good", {"summary": "s", "kind": "campaign",
		"pack_version": "2.1", "priority": 5, "world": "world.json",
		"story": "story.json", "data": {"bestiary.json": "beasts.json"}}), "res://x")
	check(m.ok(), "a well-formed manifest parses clean: %s" % ", ".join(m.errors))
	check(m.id == "good" and m.kind == "campaign" and m.priority == 5, "fields land")
	check(m.has_world() and m.has_story(), "declared content is seen")
	check(m.data_files["bestiary.json"] == "beasts.json", "data overlay mapping")
	check(m.path_of("world.json") == "res://x/world.json", "paths resolve inside the pack")
	check(not m.is_paid(), "packs are free unless they say otherwise")
	check(not m.official, "nothing is official until a root says so")
	check("2.1" in m.describe() and "A Tester" in m.describe(), "describe() names version and author")

func test_manifest_rejects() -> void:
	var bad = Manifest.parse({"format": "nope", "id": "X X", "title": ""}, "res://x")
	check(not bad.ok(), "a bad manifest is not ok")
	check(bad.errors.size() >= 3, "it reports every problem, not the first")
	check(Manifest.parse(_manifest("p", {"api": Manifest.API + 1}), "").errors.size() == 1,
		"a pack from a newer API is refused with one clear reason")
	check(not Manifest.parse(_manifest("p", {"access": "paid"}), "").ok(),
		"a paid pack with no product_id cannot be sold, so it cannot ship")
	check(Manifest.parse(_manifest("p", {"access": "paid",
		"product_id": "sku.1"}), "").ok(), "...with one, it is fine")
	check(not Manifest.parse(_manifest("p", {"data": {"monster.json": "m.json"}}), "").ok(),
		"a data key that is not a game data file is a typo, and is caught")
	var missing = Manifest.parse(_manifest("p", {"world": "nope.json"}), _root)
	missing.check_files()
	check(not missing.ok(), "a declared file that is not there is an error")

# --- entitlement -----------------------------------------------------------

func test_entitlement() -> void:
	Entitlement.reload()
	var free = Manifest.parse(_manifest("f"), "")
	var paid = Manifest.parse(_manifest("p", {"access": "paid", "product_id": "sku"}), "")
	check(Entitlement.owns(free), "free content is owned by everybody")
	check(not Entitlement.owns(paid), "paid content is not")
	Entitlement.grant("p")
	check(Entitlement.owns(paid), "granting it makes it owned")
	Entitlement.reload()
	check(Entitlement.owns(paid), "...and it survives a reload — it was written down")
	Entitlement.revoke("p")
	check(not Entitlement.owns(paid), "revoke takes it back")
	Entitlement.sync(["p", "q"])
	check(Entitlement.owns(paid) and Entitlement.owned().size() == 2,
		"sync() replaces the set wholesale — the storefront is the authority")
	OS.set_environment("SORCMERC_UNLOCK_DLC", "1")
	Entitlement.sync([])
	check(Entitlement.owns(paid), "a playtest/unlocked build owns everything")
	OS.set_environment("SORCMERC_UNLOCK_DLC", "")
	Entitlement.reload()

# --- the registry ----------------------------------------------------------

func test_registry() -> void:
	_write("alpha", {"pack.json": _manifest("alpha", {"kind": "world",
		"world": "world.json"}), "world.json": _min_world()})
	_write("beta", {"pack.json": _manifest("beta", {"access": "paid",
		"product_id": "sku.beta", "world": "world.json"}), "world.json": _min_world()})
	_write("gamma", {"pack.json": _manifest("gamma", {"requires": ["nowhere"]})})
	_write("delta", {"pack.json": "{ not json"})
	_write("notapack", {"readme.txt": "just a folder"})

	var packs := Registry.scan(true)
	var ids: Array = []
	for p in packs:
		ids.append(p.id())
	check(ids.has("alpha") and ids.has("beta"), "both roots' packs are found")
	check(not ids.has("notapack"), "a directory with no pack.json is not a pack")
	check(Registry.find("alpha").live(), "a clean pack is live")
	check(Registry.find("beta").status == "locked", "an unowned paid pack is locked")
	check(Registry.find("gamma").status == "broken", "a missing requirement breaks a pack")
	check(Registry.find("delta").status == "broken", "unparsable json breaks a pack")
	check(not Registry.find("delta").errors.is_empty(), "...and says why")
	check(_listed(Registry.playable(), "alpha"), "a pack with a world is playable")
	check(not _listed(Registry.playable(), "beta"),
		"a locked pack is not playable, whatever it declares")

	var w = Registry.world_of(Registry.find("alpha"))
	check(w != null and w.settlements.size() == 1, "the registry builds a pack's world")
	check(String(w.origin.get("kind", "")) == "pack:alpha",
		"the map remembers which pack it came from")
	check(Registry.world_of(Registry.find("beta")) == null,
		"a locked pack's world is not built — locked means not read")

	Entitlement.grant("beta")
	Registry.scan(true)
	check(Registry.find("beta").live(), "buying it unlocks it on the next scan")

	Registry.set_enabled("alpha", false)
	check(Registry.find("alpha").status == "disabled", "the player can switch one off")
	Registry.set_enabled("alpha", true)
	check(Registry.find("alpha").live(), "...and back on")
	check(Registry.report().size() > 0, "there is a readable report")

# --- data overlays ----------------------------------------------------------

func test_overlays() -> void:
	var before: int = Catalog.all("bestiary.json").size()
	var ac_before: int = int(Catalog.monster("goblin").get("ac", 0))
	_write("ghouls", {"pack.json": _manifest("ghouls",
		{"data": {"bestiary.json": "beasts.json"}}),
		"beasts.json": [
			{"id": "ash-ghoul", "cname": "Ash Ghoul", "ac": 13, "max_hp": 22,
			 "init_mod": 2, "speed": 6, "atk_bonus": 4, "damage": "2d6+2",
			 "ranged": false, "atk_range": 1, "athletics": 3, "acro": 2,
			 "saves": {}, "features": [], "cr": 1, "xp": 200, "size": "Medium",
			 "type": "undead", "faction": "undead", "habitat": "any",
			 "attack_name": "Claws", "damage_type": "slashing"},
			{"id": "goblin", "ac": 99}]})
	Registry.scan(true)
	Registry.apply_data()
	check(Catalog.monster("ash-ghoul").get("cname") == "Ash Ghoul",
		"a pack's monster is in the catalog")
	check(Catalog.all("bestiary.json").size() == before + 1, "exactly one record was added")
	check(int(Catalog.monster("goblin").get("ac", 0)) == 99,
		"a pack may retune the game's own records, by id")
	var in_pool := false
	for e in Scaler._faction_pool("undead"):
		in_pool = in_pool or e["id"] == "ash-ghoul"
	check(in_pool,
		"...and the fight builder sees it, because the pools were dropped with the cache")

	Registry.set_enabled("ghouls", false)
	check(Catalog.monster("ash-ghoul").is_empty(), "switching the pack off takes it back out")
	check(int(Catalog.monster("goblin").get("ac", 0)) == ac_before, "...retunes included")
	Catalog.warnings.clear()

# --- effects overlays: what a pack's content DOES ---------------------------

# T33/T94 added data/effects/*.json, and until this the allowlist did not name
# them: a pack could add a spell and never be able to say what casting it does.
func test_effect_overlays() -> void:
	_write("emberwork", {"pack.json": _manifest("emberwork", {"data": {
			"spells.json": "spells.json",
			"effects/spells.json": "spell-mechanics.json",
			"magic-items.json": "items.json",
			"effects/potions.json": "potion-mechanics.json",
			"effects/features.json": "feature-mechanics.json"}}),
		"spells.json": [
			{"id": "ember-lance", "name": "Ember Lance", "level": 1,
			 "school": "evocation", "castingTime": "Action", "range": "60 feet",
			 "duration": "Instantaneous", "concentration": false, "ritual": false,
			 "classes": ["wizard"], "description": "A lance of cinders.",
			 "mechanics": null}],
		"spell-mechanics.json": {
			"_note": "an underscore key is an authoring comment, not a record",
			"ember-lance": {"cost": "action", "shape": "single", "range_ft": 60,
				"save": "dex", "half_on_save": true,
				"damage": [{"count": 2, "sides": 8, "type": "fire"}],
				"upcast": {"per_level": {"count": 1, "sides": 8}}}},
		"items.json": [
			{"id": "potion-of-embers", "name": "Potion of Embers", "rarity": "uncommon",
			 "type": "potion", "description": "Warm all the way down."}],
		"potion-mechanics.json": {
			"potion-of-embers": {"status": {"bonus_damage": 2}, "rounds": 10,
				"minutes": 30, "text": "+2 damage while it burns"}},
		"feature-mechanics.json": {
			"emberwork-cinderskin": {"kind": "self_buff", "cost": "bonus",
				"uses": 1, "status": {"resist": ["fire"]}, "duration": 10}}})
	Registry.scan(true)
	check(Registry.find("emberwork").live(),
		"a pack may declare effects/*.json: %s" % ", ".join(Registry.find("emberwork").errors))
	Registry.apply_data()
	var m := Effects.spell("ember-lance")
	check(not m.is_empty(), "a pack's spell is castable, because the pack said what it does")
	check(int(m.get("range_ft", 0)) == 60 and m.get("save", "") == "dex",
		"...with the mechanics it authored, not a guess off the prose")
	check(Potions.is_potion("potion-of-embers"), "a pack's potion is drinkable")
	check(not Effects.feature("emberwork-cinderskin").is_empty(), "a pack's feature has a mechanic")
	check(Effects.validate().is_empty(),
		"the merged catalog still validates: %s" % ", ".join(Effects.validate()))

	Registry.set_enabled("emberwork", false)
	Registry.apply_data()
	check(Effects.spell("ember-lance").is_empty(), "switching it off takes the mechanic back out")
	check(not Potions.is_potion("potion-of-embers"), "...the potion too")
	Catalog.warnings.clear()

# Every silent dead-end the vocabulary has, turned into a line in the browser.
func test_effect_overlays_reject() -> void:
	_write("badeffects", {"pack.json": _manifest("badeffects", {"data": {
			"effects/features.json": "f.json", "effects/spells.json": "s.json",
			"effects/potions.json": "p.json"}}),
		"f.json": {
			"bad-kind": {"kind": "explodes", "value": 1},
			"bad-reaction": {"kind": "reaction", "cost": "reaction", "trigger": "on_tuesday"}},
		"s.json": {
			"nowhere-spell": {"cost": "action", "damage": [{"count": 1, "sides": 6}]},
			"fireball": {"cost": "action", "damage": [{"dice": "8d6"}]}},
		"p.json": {"potions-of-healing": {"text": "nothing at all"}}})
	Registry.scan(true)
	var p = Registry.find("badeffects")
	check(p.status == "broken", "a pack whose effects cannot work does not load")
	var said := ", ".join(p.errors)
	check("explodes" in said, "an unknown feature kind is named")
	check("on_tuesday" in said, "a reaction hung off a trigger nothing fires is named")
	check("nowhere-spell" in said, "a mechanic for a spell that does not exist is named")
	check("count, sides" in said, "damage the verb builder cannot read is named")
	check("does nothing" in said, "a potion with no effect is named")
	Registry.set_enabled("badeffects", false)
	Catalog.warnings.clear()

# --- what ships in res://content -------------------------------------------

func test_shipped_content() -> void:
	OS.set_environment("SORCMERC_MODS_DIR", _root + "-empty")
	OS.set_environment("SORCMERC_UNLOCK_DLC", "1")   # see the paid one too
	Entitlement.reload()
	var packs := Registry.scan(true)
	check(not packs.is_empty(), "the game ships content packs")
	for p in packs:
		check(p.errors.is_empty(), "%s loads clean: %s" % [p.id(), ", ".join(p.errors)])
		check(p.manifest.official, "%s is marked official by its root" % p.id())
		if p.manifest.has_world():
			check(Registry.world_of(p) != null, "%s's map builds" % p.id())
	var paid := false
	var told := false
	for p in packs:
		paid = paid or p.manifest.is_paid()
		told = told or p.manifest.has_story()
	check(paid, "...including a paid one, so the DLC path is exercised by the game's own content")
	check(told, "...and a story")
	OS.set_environment("SORCMERC_UNLOCK_DLC", "")
	Registry.scan(true)
	Registry.apply_data()
