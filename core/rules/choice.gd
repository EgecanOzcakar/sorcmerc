# Choice keys: "category:origin:id:index". F1 emits them; never regenerate one
# except to find a companion key (the ASI <-> feat-choice either-or pair).
# Parse failure warns and returns {}; it is never fatal.
extends RefCounted

const CATEGORIES := ["skill-choice", "tool-choice", "language-choice", "saving-throw-choice",
	"ability-choice", "expertise-choice", "asi", "subclass", "fighting-style-choice",
	"weapon-mastery-choice", "damage-choice", "bundle-choice", "lineage-choice",
	"feat-choice", "feature-choice", "spell-choice"]

const ORIGINS := ["species", "background", "class", "subclass", "feat"]

static var warnings: Array[String] = []

static func make(category: String, origin: String, id: String, index: int) -> String:
	return "%s:%s:%s:%d" % [category, origin, id, index]

# {} on failure.
static func parse(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 4:
		warnings.append("malformed choice key \"%s\": expected 4 segments" % key)
		return {}
	if not parts[0] in CATEGORIES:
		warnings.append("invalid choice key category \"%s\" in \"%s\"" % [parts[0], key])
		return {}
	if not parts[1] in ORIGINS:
		warnings.append("invalid choice key origin \"%s\" in \"%s\"" % [parts[1], key])
		return {}
	if not parts[3].is_valid_int() or int(parts[3]) < 0:
		warnings.append("invalid choice key index \"%s\" in \"%s\"" % [parts[3], key])
		return {}
	return {"category": parts[0], "origin": parts[1], "id": parts[2], "index": int(parts[3])}

# The other half of an either-or pair, e.g. asi <-> feat-choice at the same slot.
static func companion(key: String, category: String) -> String:
	var p := parse(key)
	if p.is_empty():
		return ""
	return make(category, p["origin"], p["id"], p["index"])
