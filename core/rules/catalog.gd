# Lazy, cached access to data/*.json. All static — no autoload, no instances.
# Unknown ids return {} and append to `warnings`, which resolve.gd drains.
extends RefCounted

const DIR := "res://data/"

static var warnings: Array[String] = []

static var _files := {}      # filename -> parsed Variant (null when absent/bad)
static var _indexes := {}    # filename -> {id: record}
static var _spell_lists := {}  # class_id -> {level: [spell_id]}

static func all(file: String) -> Variant:
	if not _files.has(file):
		var txt := FileAccess.get_file_as_string(DIR + file)
		if txt.is_empty():
			warnings.append("missing data file: " + file)
			_files[file] = null
		else:
			_files[file] = JSON.parse_string(txt)
			if _files[file] == null:
				warnings.append("unparsable data file: " + file)
	return _files[file]

static func index(file: String) -> Dictionary:
	if not _indexes.has(file):
		var d := {}
		var a = all(file)
		if a is Array:
			for r in a:
				d[r["id"]] = r
		elif a is Dictionary:
			d = a
		_indexes[file] = d
	return _indexes[file]

static func _one(file: String, id: String) -> Dictionary:
	var r = index(file).get(id)
	if r == null:
		warnings.append("unknown id \"%s\" in %s" % [id, file])
		return {}
	return r

static func class_src(id: String) -> Dictionary: return _one("classes.json", id)
static func subclass_src(id: String) -> Dictionary: return _one("subclasses.json", id)
static func species_src(id: String) -> Dictionary: return _one("species.json", id)
static func background_src(id: String) -> Dictionary: return _one("backgrounds.json", id)
static func feat_src(id: String) -> Dictionary: return _one("feats.json", id)
static func fighting_style_src(id: String) -> Dictionary: return _one("fighting-styles.json", id)
static func weapon(id: String) -> Dictionary: return _one("weapons.json", id)
static func armor(id: String) -> Dictionary: return _one("armor.json", id)
static func spell(id: String) -> Dictionary: return _one("spells.json", id)
static func condition(id: String) -> Dictionary: return _one("conditions.json", id)
static func monster(id: String) -> Dictionary: return _one("monsters.json", id)
static func skills() -> Dictionary: return index("skills.json")

static func subclasses_of(class_id: String) -> Array:
	var out: Array = []
	for s in all("subclasses.json"):
		if s["classId"] == class_id:
			out.append(s["id"])
	return out

# Native class spell lists only — subclass expanded lists arrive as `spell` grants
# (SCHEMA gap #7) and must not be folded in here.
static func spell_list(class_id: String, level: int) -> Array:
	if _spell_lists.is_empty():
		for s in all("spells.json"):
			for c in s.get("classes", []):
				var by_level: Dictionary = _spell_lists.get_or_add(c, {})
				by_level.get_or_add(int(s["level"]), []).append(s["id"])
	return _spell_lists.get(class_id, {}).get(level, [])

# JSON numbers arrive as floats; slot tables are the one place ints are compared.
static func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v in a:
		out.append(int(v))
	return out

# Class table only; the third-caster fallback lives in pass_spells.
static func spell_slots(class_id: String, class_level: int) -> Array[int]:
	var c := class_src(class_id)
	var table: Array = c.get("spellSlots", [])
	if class_level < 1 or class_level > table.size():
		return [] as Array[int]
	return _ints(table[class_level - 1])

static func pact_magic(class_id: String, class_level: int) -> Dictionary:
	var c := class_src(class_id)
	var table = c.get("pactMagic")
	if table == null or class_level < 1 or class_level > table.size():
		return {}
	return table[class_level - 1]

static func third_caster_slots(class_level: int) -> Array[int]:
	var table = all("third-caster-slots.json")
	if table == null or class_level < 1 or class_level > table.size():
		return [] as Array[int]
	return _ints(table[class_level - 1])
