# Lazy, cached access to data/*.json. All static — no autoload, no instances.
# Unknown ids return {} and append to `warnings`, which resolve.gd drains.
extends RefCounted

const DIR := "res://data/"

static var warnings: Array[String] = []

static var _files := {}      # filename -> parsed Variant (null when absent/bad)
static var _indexes := {}    # filename -> {id: record}
static var _spell_lists := {}  # class_id -> {level: [spell_id]}

# M6 — content packs layering their own records over data/*.json. Each entry is
# {"id": pack id, "files": {data filename: parsed records}}, in the order they
# should apply: a later pack's record with an id an earlier one already used
# replaces it, so `priority` in a pack.json is what decides who wins a fight
# over "goblin". core/mod/registry.gd owns this list and is the only thing that
# should write it.
#
# Overlays are deliberately NOT a separate lookup path: they are folded into
# the same parsed arrays everything already reads, so a pack's monster is a
# monster to every system in the game — the scaler's faction pools, the
# bestiary screen, the encounter builder — with no per-caller awareness.
static var _overlays: Array = []

static func set_overlays(list: Array) -> void:
	_overlays = list
	reset()

static func overlays() -> Array:
	return _overlays

# Drop every cache. Needed when the overlay set changes (enabling a pack
# mid-session) and useful to a test that wants the base game back.
static func reset() -> void:
	_files.clear()
	_indexes.clear()
	_spell_lists.clear()

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
		_files[file] = _layered(file, _files[file])
	return _files[file]

# The base file with every pack's records for it folded in. An Array file
# (monsters, spells, items — anything with `id` records) merges by id and
# appends what is new, keeping the base order so nothing that walks the list
# in file order shifts under a pack. A Dictionary file (skills.json) merges by
# key. A pack may therefore both ADD content and RETUNE the game's own, which
# is the difference between a mod loader and a second data directory.
static func _layered(file: String, base):
	if _overlays.is_empty():
		return base
	var merged = base
	for pack in _overlays:
		var records = pack.get("files", {}).get(file)
		if records == null:
			continue
		if merged == null:
			merged = [] if records is Array else {}
		if merged is Dictionary and records is Dictionary:
			merged = merged.duplicate()
			merged.merge(records, true)
		elif merged is Array and records is Array:
			merged = _merge_records(merged, records)
		else:
			warnings.append("pack \"%s\" overlays %s with the wrong shape"
				% [pack.get("id", "?"), file])
	return merged

static func _merge_records(base: Array, extra: Array) -> Array:
	var at := {}
	for i in base.size():
		if base[i] is Dictionary and base[i].has("id"):
			at[base[i]["id"]] = i
	var out := base.duplicate()
	for r in extra:
		if not (r is Dictionary) or not r.has("id"):
			continue
		if at.has(r["id"]):
			out[at[r["id"]]] = r
		else:
			at[r["id"]] = out.size()
			out.append(r)
	return out

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
static func magic_item(id: String) -> Dictionary: return _one("magic-items.json", id)
static func spell(id: String) -> Dictionary: return _one("spells.json", id)
static func condition(id: String) -> Dictionary: return _one("conditions.json", id)
static func monster(id: String) -> Dictionary:
	var r = index("monsters.json").get(id)
	return r if r != null else _one("bestiary.json", id)
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
