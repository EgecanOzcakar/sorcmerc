# Grant type table + validator. Keys stay camelCase, verbatim as exported.
# TYPE_NIL in a row means "present, any type" (String-or-Dictionary / list-or-null fields).
# TYPE_INT accepts JSON numbers, which Godot always parses as float.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const SCHEMA := {
	"ability-bonus": {"req": {"ability": TYPE_STRING, "bonus": TYPE_INT}},
	"ability-check-bonus": {
		"req": {"abilities": TYPE_ARRAY, "value": TYPE_STRING, "featureId": TYPE_STRING},
		"opt": {"onlyWhenNotProficient": TYPE_BOOL}},
	"ability-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT, "bonus": TYPE_INT, "from": TYPE_NIL}},
	"ac-bonus": {"req": {"bonus": TYPE_INT}},
	"armor-class": {"req": {"calculation": TYPE_DICTIONARY}},
	"asi": {"req": {"key": TYPE_STRING, "points": TYPE_INT, "from": TYPE_NIL}},
	"bundle-choice": {"req": {"key": TYPE_STRING, "category": TYPE_STRING, "bundleIds": TYPE_ARRAY}},
	"damage-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT, "from": TYPE_ARRAY,
		"featureIdPrefix": TYPE_STRING}},
	"expertise-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT, "from": TYPE_NIL,
		"fromTools": TYPE_ARRAY}},
	"feat": {"req": {"featId": TYPE_STRING}},
	"feat-choice": {"req": {"key": TYPE_STRING, "category": TYPE_STRING, "from": TYPE_NIL}},
	"feature": {"req": {"feature": TYPE_DICTIONARY}},
	"feature-choice": {"req": {"key": TYPE_STRING, "options": TYPE_ARRAY}},
	"fighting-style-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT, "from": TYPE_ARRAY}},
	"hit-die": {"req": {"die": TYPE_INT}},
	"hp-bonus": {"req": {"perLevel": TYPE_INT}},
	"lineage-choice": {"req": {"key": TYPE_STRING, "speciesId": TYPE_STRING, "from": TYPE_ARRAY}},
	"proficiency": {"req": {"category": TYPE_STRING, "id": TYPE_STRING}},
	"proficiency-choice": {"req": {"category": TYPE_STRING, "key": TYPE_STRING, "count": TYPE_INT,
		"from": TYPE_NIL}},
	"resistance": {"req": {"damageType": TYPE_STRING}},
	"resource-pool": {"req": {"poolId": TYPE_STRING, "max": TYPE_DICTIONARY, "regen": TYPE_NIL},
		"opt": {"dieSizeSteps": TYPE_ARRAY}},
	"skill-expertise": {"req": {"skill": TYPE_STRING}},
	"speed": {"req": {"mode": TYPE_STRING, "value": TYPE_NIL}, "opt": {"condition": TYPE_STRING}},
	"spell": {"req": {"spellId": TYPE_STRING, "alwaysPrepared": TYPE_BOOL},
		"opt": {"minClassLevel": TYPE_INT, "ability": TYPE_STRING}},
	"spell-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT, "spellList": TYPE_STRING,
		"spellLevel": TYPE_INT}},
	"spellcasting": {"req": {"ability": TYPE_STRING, "source": TYPE_STRING}},
	"subclass": {"req": {"classId": TYPE_STRING, "key": TYPE_STRING}},
	"weapon-mastery-choice": {"req": {"key": TYPE_STRING, "count": TYPE_INT}},
}

# Files whose grant arrays validate_catalog() walks.
const GRANT_FILES := ["classes.json", "subclasses.json", "species.json", "backgrounds.json",
	"feats.json", "fighting-styles.json"]

static func _type_ok(v, hint: int) -> bool:
	match hint:
		TYPE_NIL: return true
		TYPE_INT: return v is float or v is int
		TYPE_STRING: return v is String
		TYPE_BOOL: return v is bool
		TYPE_ARRAY: return v is Array
		TYPE_DICTIONARY: return v is Dictionary
	return false

# "" when valid, else the reason.
static func validate(g) -> String:
	if not g is Dictionary:
		return "grant is not a Dictionary: " + str(g)
	var t = g.get("type")
	if not t is String:
		return "grant has no string \"type\": " + str(g)
	if not SCHEMA.has(t):
		return "unknown grant type \"%s\"" % t
	var row: Dictionary = SCHEMA[t]
	var req: Dictionary = row["req"]
	var opt: Dictionary = row.get("opt", {})
	for k in req:
		if not g.has(k):
			return "%s: missing required key \"%s\"" % [t, k]
		if not _type_ok(g[k], req[k]):
			return "%s: key \"%s\" has wrong type (%s)" % [t, k, type_string(typeof(g[k]))]
	for k in g:
		if k == "type" or req.has(k):
			continue
		if not opt.has(k):
			return "%s: unknown key \"%s\"" % [t, k]
		if not _type_ok(g[k], opt[k]):
			return "%s: key \"%s\" has wrong type (%s)" % [t, k, type_string(typeof(g[k]))]
	return ""

# Every grant in every grant-bearing data file. [] means the catalog is clean.
static func validate_catalog() -> Array[String]:
	var errs: Array[String] = []
	for f in GRANT_FILES:
		for g in catalog_grants(f):
			var e := validate(g)
			if e != "":
				errs.append("%s: %s" % [f, e])
	return errs

# Every grant in a file, including grants nested inside feature-choice options.
static func catalog_grants(file: String) -> Array:
	var out: Array = []
	_walk(Catalog.all(file), out)
	return out

static func _walk(v, out: Array) -> void:
	if v is Array:
		for x in v:
			_walk(x, out)
	elif v is Dictionary:
		if v.get("type") is String:
			out.append(v)
			for o in v.get("options", []):
				_walk(o.get("grants", []), out)
		else:
			for k in v:
				if k != "prerequisites":  # feats carry {type: ...} prereq rows that are not grants
					_walk(v[k], out)
