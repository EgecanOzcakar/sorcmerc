# Character persistence. THE format T3 (profile) and T4 (party) load characters with.
#
# One JSON file per character at  user://characters/<slug>.json  — the slug is
# Character.id, or a slugified name when id is empty. It is the *build*, not the
# sheet: reload it and call ch.sheet() to re-resolve. Nothing derived is stored,
# so a rules/data fix retroactively fixes every saved character.
#
# {
#   "format": "sorcmerc-character",   // literal, checked on load
#   "version": 1,                     // bump only on an incompatible change
#   "id": "vera",                     // == the slug == the file name
#   "name": "Vera Kord",
#   "species_id": "human",
#   "background_id": "soldier",
#   "base_abilities": {"str":14,"dex":12,"con":13,"int":10,"wis":12,"cha":10},
#   "levels": [{"class_id": "fighter", "hp_roll": -1}],   // ordered; -1 = average HP
#   "choices": {"skill-choice:class:fighter:0": {"type":"skill-choice","skills":["perception","insight"]}},
#   "feats": ["alert"],               // feats taken outside a feat-choice grant
#   "equipped": ["longsword", "chain-mail", "shield"],
#   "inventory": [{"item_id": "dagger", "quantity": 1}],
#   "pools": {"second-wind": 1},      // campaign state: uses REMAINING
#   "hp_current": -1,                 // -1 = full
#   "prepared": ["cure-wounds"]
# }
#
# Unknown extra keys are ignored on load, so a later track may add its own without
# breaking older saves. Missing keys fall back to the Character defaults.
extends RefCounted

const Character = preload("res://core/character.gd")

const DIR := "user://characters"
const FORMAT := "sorcmerc-character"
const VERSION := 1

static func slugify(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.strip_edges(true, true).lstrip("-").rstrip("-")
	return out if out != "" else "character"

static func path_for(slug: String) -> String:
	return "%s/%s.json" % [DIR, slug]

static func to_dict(ch) -> Dictionary:
	var slug: String = ch.id if ch.id != "" else slugify(ch.cname)
	return {
		"format": FORMAT, "version": VERSION,
		"id": slug, "name": ch.cname,
		"species_id": ch.species_id, "background_id": ch.background_id,
		"base_abilities": ch.base_abilities.duplicate(),
		"levels": ch.levels.duplicate(true),
		"choices": ch.choices.duplicate(true),
		"feats": ch.feats.duplicate(),
		"equipped": ch.equipped.duplicate(),
		"inventory": ch.inventory.duplicate(true),
		"pools": ch.pools.duplicate(),
		"hp_current": ch.hp_current,
		"prepared": ch.prepared.duplicate(),
	}

# null when the dictionary is not a character save.
static func from_dict(d: Dictionary):
	if d.get("format") != FORMAT:
		push_warning("not a character save: %s" % d.get("format"))
		return null
	var ch := Character.new()
	ch.id = String(d.get("id", ""))
	ch.cname = String(d.get("name", ""))
	ch.species_id = String(d.get("species_id", ""))
	ch.background_id = String(d.get("background_id", ""))
	for a in ch.base_abilities:
		if d.get("base_abilities", {}).has(a):
			ch.base_abilities[a] = int(d["base_abilities"][a])
	for l in d.get("levels", []):
		ch.levels.append({"class_id": String(l["class_id"]), "hp_roll": int(l.get("hp_roll", -1))})
	ch.choices = d.get("choices", {}).duplicate(true)
	# JSON has no ints: an ASI allocation comes back as floats. Restore them, so a
	# reloaded build compares equal to the one that was saved.
	for k in ch.choices:
		var alloc = ch.choices[k].get("allocation")
		if alloc is Dictionary:
			for a in alloc:
				alloc[a] = int(alloc[a])
	ch.feats.assign(d.get("feats", []))
	ch.equipped.assign(d.get("equipped", []))
	for i in d.get("inventory", []):
		ch.inventory.append({"item_id": String(i["item_id"]), "quantity": int(i.get("quantity", 1))})
	for k in d.get("pools", {}):
		ch.pools[k] = int(d["pools"][k])
	ch.hp_current = int(d.get("hp_current", -1))
	ch.prepared.assign(d.get("prepared", []))
	return ch

# Returns the path written, or "" on failure.
static func save(ch) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := to_dict(ch)
	var path := path_for(d["id"])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path)
		return ""
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return path

static func load_path(path: String):
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var d = JSON.parse_string(txt)
	return from_dict(d) if d is Dictionary else null

static func load_slug(slug: String):
	return load_path(path_for(slug))

# Every saved character, newest-first by modification time. T4's roster reads this.
static func list_slugs() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var files: Array = Array(dir.get_files())
	files.sort_custom(func(a, b):
		return FileAccess.get_modified_time(DIR + "/" + a) > FileAccess.get_modified_time(DIR + "/" + b))
	for f in files:
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	return out

static func load_all() -> Array:
	var out: Array = []
	for s in list_slugs():
		var ch = load_slug(s)
		if ch != null:
			out.append(ch)
	return out

static func delete(slug: String) -> bool:
	return DirAccess.remove_absolute(path_for(slug)) == OK
