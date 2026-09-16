# Localization (core/loc.gd): the language setting, the string tables under
# data/loc/, and the record overlay that translates data/*.json in place.
#
# The invariant that matters most is the LAST one: English must come out of
# every lookup byte-for-byte unchanged, because "en" is the source language and
# every call site passes its own English text as the fallback. A localization
# layer that changes the English game is a regression, not a feature.
#
#   godot --headless --path . -s tests/test_loc.gd
extends SceneTree

const Loc = preload("res://core/loc.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Settings = preload("res://core/settings.gd")
const Creator = preload("res://scenes/creator/creator.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_english_is_the_identity()
	test_language_switch_translates_records()
	test_every_feature_id_has_a_turkish_name()
	test_every_ui_key_a_screen_asks_for_is_translated()
	test_tables_are_well_formed()
	test_unknown_keys_fall_back_to_english()
	test_switching_back_restores_english()
	await test_the_picker_switches_the_screen_under_it()
	Loc.set_lang("en")
	print("test_loc: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- the source language ---------------------------------------------------

func test_english_is_the_identity() -> void:
	Loc.set_lang("en")
	check(Loc.lang() == "en", "default language is English")
	check(Loc.t("nothing.at.all", "Fallback") == "Fallback", "t() returns the fallback")
	check(Loc.term("ability", "str", "Strength") == "Strength", "term() returns the fallback")
	check(Loc.name_of("fighter-second-wind") == "", "name_of() is empty in the source language")
	check(Catalog.class_src("barbarian")["name"] == "Barbarian", "class names are untouched")
	check(Catalog.spell("fireball")["name"] == "Fireball", "spell names are untouched")
	check(Effects.humanize("fighter-second-wind") == "Fighter Second Wind",
		"humanize() still knocks the hyphens out")
	check(Effects.verb_label("fighter-second-wind") == "Second Wind",
		"verb_label() still drops the class prefix")

# --- the record overlay ----------------------------------------------------

func test_language_switch_translates_records() -> void:
	Loc.set_lang("tr")
	check(Loc.lang() == "tr", "set_lang switched")
	# An Array file, matched on `id`...
	check(Catalog.class_src("barbarian")["name"] == "Barbar", "classes.json is translated")
	check(Catalog.spell("fireball")["name"] == "Ateş Topu", "spells.json is translated")
	check(Catalog.weapon("longsword")["name"] == "Uzun Kılıç", "weapons.json is translated")
	check(Catalog.subclass_src("berserker")["name"] == "Berserker Yolu",
		"subclasses.json is translated")
	# ...and a Dictionary file, matched on the key.
	check(Catalog.skills()["stealth"]["name"] == "Gizlilik", "skills.json is translated")
	check(Catalog.condition("prone")["name"] == "Yerde", "conditions.json is translated")
	# Only the fields the translation carries are replaced.
	check(int(Catalog.class_src("barbarian")["hitDie"]) == 12, "untranslated fields survive")
	check(Catalog.condition("prone")["description"].contains("emekle"),
		"a condition's prose is translated too")
	# Features and the keyword glossary.
	check(Effects.humanize("fighter-second-wind") == "İkinci Nefes", "feature names are translated")
	check(Loc.term("ability", "str", "Strength") == "Güç", "the glossary answers")
	check(Loc.term("damage", "fire", "fire") == "ateş", "damage types are translated")
	check(Catalog.monster("goblin")["cname"] == "Goblin", "bestiary names are translated")
	check(Catalog.monster("giant-spider")["cname"] == "Dev Örümcek",
		"...including the composed ones")
	check(Catalog.magic_item("bag-of-holding")["name"] == "Taşıma Torbası",
		"magic-items.json is translated")

func test_every_feature_id_has_a_turkish_name() -> void:
	Loc.set_lang("tr")
	var missing: Array[String] = []
	for id in _feature_ids():
		if Loc.name_of(id) == "":
			missing.append(id)
	check(missing.is_empty(), "untranslated feature ids: " + ", ".join(missing.slice(0, 12)))

# Every id the data grants as a feature, gathered the way the resolver sees them:
# a `feature` grant's nested id, or a bestiary/monster entry's `features` list.
func _feature_ids() -> Array:
	var ids := {}
	for f in ["classes.json", "subclasses.json", "species.json", "backgrounds.json",
			"feats.json", "fighting-styles.json", "bestiary.json", "monsters.json"]:
		_collect(Catalog.all(f), ids)
	return ids.keys()

func _collect(node, ids: Dictionary) -> void:
	if node is Dictionary:
		for k in node:
			var v = node[k]
			if k == "feature" and v is Dictionary and v.has("id"):
				ids[String(v["id"])] = true
			elif k == "features" and v is Array:
				for x in v:
					if x is String:
						ids[x] = true
			_collect(v, ids)
	elif node is Array:
		for x in node:
			_collect(x, ids)

# --- the UI table ----------------------------------------------------------

# Every key a screen actually asks Loc.t()/tf() for, scraped out of the scripts
# themselves. A key added to a screen and forgotten in the table fails here
# rather than showing up as an English sentence in a Turkish menu.
func test_every_ui_key_a_screen_asks_for_is_translated() -> void:
	var table: Dictionary = _json("res://data/loc/tr/ui.json")
	var missing: Array[String] = []
	for key in _keys_in_scripts():
		if not table.has(key):
			missing.append(key)
	check(missing.is_empty(), "UI keys with no Turkish: " + ", ".join(missing.slice(0, 12)))

const SCRIPT_DIRS := ["res://scenes", "res://core"]

func _keys_in_scripts() -> Array:
	var re := RegEx.create_from_string('Loc\\.t(?:f|mpl)?\\(\\s*"([a-z0-9_.]+)"\\s*,')
	var out := {}
	for dir in SCRIPT_DIRS:
		for path in _gd_files(dir):
			for m in re.search_all(FileAccess.get_file_as_string(path)):
				out[m.get_string(1)] = true
	return out.keys()

func _gd_files(dir: String) -> Array:
	var out: Array = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			out.append(dir + "/" + name)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + sub))
	return out

# --- shape -----------------------------------------------------------------

func test_tables_are_well_formed() -> void:
	for name in ["ui", "terms", "features", "names"]:
		var d = _json("res://data/loc/tr/%s.json" % name)
		check(d is Dictionary and not d.is_empty(), "%s.json parses and is not empty" % name)
	# A record table is id -> {field: text}; nothing else is meaningful.
	for name in ["classes", "spells", "conditions", "skills", "subclasses",
			"fighting-styles", "weapons", "armor", "species", "backgrounds", "feats",
			"magic-items", "bestiary"]:
		var d = _json("res://data/loc/tr/records/%s.json" % name)
		var ok: bool = d is Dictionary and not d.is_empty()
		if ok:
			for id in d:
				if not (d[id] is Dictionary) or d[id].is_empty():
					ok = false
					break
		check(ok, "records/%s.json is id -> fields" % name)
	# Format placeholders must survive translation: a "%d" that became "%s" is a
	# crash at the call site, not a typo.
	var ui: Dictionary = _json("res://data/loc/tr/ui.json")
	var en := _english_fallbacks()
	var wrong: Array[String] = []
	for key in ui:
		if en.has(key) and _specs(String(en[key])) != _specs(String(ui[key])):
			wrong.append(key)
	check(wrong.is_empty(), "format placeholders changed: " + ", ".join(wrong.slice(0, 12)))

# The English text each call site passes, so the check above has something to
# compare the translation's placeholders against.
func _english_fallbacks() -> Dictionary:
	var re := RegEx.create_from_string('Loc\\.t(?:f|mpl)?\\(\\s*"([a-z0-9_.]+)"\\s*,\\s*\\n?\\s*"((?:[^"\\\\]|\\\\.)*)"')
	var out := {}
	for dir in SCRIPT_DIRS:
		for path in _gd_files(dir):
			for m in re.search_all(FileAccess.get_file_as_string(path)):
				if not out.has(m.get_string(1)):
					out[m.get_string(1)] = m.get_string(2)
	return out

# The printf specs in a string, in order. "%%" is a literal percent, not a slot.
func _specs(s: String) -> Array:
	var re := RegEx.create_from_string("%[-+ #0]*[0-9.*]*[a-zA-Z%]")
	var out: Array = []
	for m in re.search_all(s):
		if m.get_string() != "%%":
			out.append(m.get_string())
	return out

func test_unknown_keys_fall_back_to_english() -> void:
	Loc.set_lang("tr")
	check(Loc.t("no.such.key", "Untranslated") == "Untranslated",
		"a missing UI key reads as its English")
	check(Loc.term("no_such_group", "x", "English") == "English",
		"a missing glossary group reads as its English")
	check(Loc.name_of("no-such-feature") == "", "a missing feature name is empty")
	check(Effects.humanize("no-such-feature") == "No Such Feature",
		"...so humanize() still has something to say")
	check(Creator.humanize("no-such-thing") == "No Such Thing",
		"and so does the creator's own")

func test_switching_back_restores_english() -> void:
	Loc.set_lang("tr")
	check(Catalog.class_src("barbarian")["name"] == "Barbar", "Turkish is in force")
	Loc.set_lang("en")
	check(Catalog.class_src("barbarian")["name"] == "Barbarian", "English came back")
	check(Catalog.condition("prone")["name"] == "Prone", "...for the dictionary files too")
	check(Effects.humanize("fighter-second-wind") == "Fighter Second Wind",
		"...and for feature names")
	# The setting round-trips: a language is stored and validated on the way in.
	var s = Settings.load_settings()
	check(s.language == "en" or Loc.supported(s.language), "the stored language is a real one")
	check(Settings.to_dict(s).has("language"), "settings.json carries the language")

# The one interactive path: picking a language rebuilds the overlay, because
# every label already on it was built in the old language — the picker's own
# row included.
func test_the_picker_switches_the_screen_under_it() -> void:
	Loc.set_lang("en")
	# This is the one test that writes user://settings.json, and every later
	# test in the suite reads it. Snapshot it here, put it back at the end.
	var before: Dictionary = Settings.to_dict(Settings.current())
	var host := Control.new()
	root.add_child(host)
	var o = load("res://scenes/settings/settings.gd").toggle(host)
	await process_frame
	var pick: OptionButton = o.find_child("LanguagePicker", true, false)
	check(pick != null, "the overlay has a language picker")
	if pick != null:
		check(pick.item_count == Loc.LANGS.size(), "it offers every shipped language")
		var tr_index := -1
		for i in pick.item_count:
			if String(pick.get_item_metadata(i)) == "tr":
				tr_index = i
				# The list itself is never translated: a player in the wrong
				# language has to be able to read their way out.
				check(pick.get_item_text(i) == "Türkçe", "the label is the language's own name")
		pick.item_selected.emit(tr_index)
		await process_frame
		await process_frame
		check(Loc.lang() == "tr", "picking switched the language")
		check(Settings.current().language == "tr", "...and it was written through to settings")
		var reopened = host.get_node_or_null("SettingsOverlay")
		check(reopened != null, "the overlay rebuilt itself")
		if reopened != null:
			check(_has_text(reopened, Loc.t("settings.title", "Settings")),
				"...in the new language")
	host.queue_free()
	Loc.set_lang(String(before.get("language", "en")))
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(before, "  "))
		f.close()
	Settings.drop_cache()
	check(Settings.current().language == before.get("language", "en"),
		"the suite's settings.json is back the way it was")

func _has_text(node: Node, want: String) -> bool:
	if node is Label and (node as Label).text == want:
		return true
	for c in node.get_children():
		if _has_text(c, want):
			return true
	return false

func _json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))
