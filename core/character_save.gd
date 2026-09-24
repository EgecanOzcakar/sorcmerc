# Character persistence. THE format T3 (profile) and T4 (party) load characters with.
#
# One JSON file per character at  user://characters/<slug>.json  — the slug is
# Character.id, and the file name is the identity: load_slug() hands back a
# character wearing the slug it was filed under, whatever the `id` inside says.
# A new character's slug is minted once by unique_slug() (the creator's
# _confirm), so saving a hero never lands on a hero the barracks already has —
# two people called Aria Vale are aria-vale and aria-vale-2. It is the *build*,
# not the sheet: reload it and call ch.sheet() to re-resolve. Nothing derived is
# stored, so a rules/data fix retroactively fixes every saved character.
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
#                                                        // optional "granted": true —
#                                                        // handed over, not earned
#   "choices": {"skill-choice:class:fighter:0": {"type":"skill-choice","skills":["perception","insight"]}},
#   "feats": ["alert"],               // feats taken outside a feat-choice grant
#   "equipped": ["longsword", "chain-mail", "shield"],   // unequipped gear is the party's,
#                                                        // not the character's (Party.stash)
#   "pools": {"second-wind": 1},      // campaign state: uses REMAINING
#   "slots_used": [2, 1],             // campaign state: spell slots SPENT, per level
#                                     // (absent = none spent; a long rest clears it;
#                                     // negative = a slot Font of Magic made, unspent)
#   "hp_current": -1,                 // -1 = full
#   "prepared": ["cure-wounds"],
#   "xp": 900,                        // banked XP (T10); Leveling gates level-up on it
#   "dead": false                     // died this run; revived by Party.resurrect
# }
#
# Unknown extra keys are ignored on load, so a later track may add its own without
# breaking older saves. Missing keys fall back to the Character defaults.
extends RefCounted

const Character = preload("res://core/character.gd")

const SaveDir = preload("res://core/save_dir.gd")
static var DIR: String = SaveDir.path("characters")
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

static func exists(slug: String) -> bool:
	return FileAccess.file_exists(path_for(slug))

# A slug no file is using yet — what a NEW character must be saved under.
#
# The name is not the identity. Two heroes called Aria Vale are two heroes, and
# slugify() is lossy besides (any two names made of the same letters and
# punctuation collapse to the same slug), so minting an id straight off the name
# meant the second Aria's file landed on top of the first's: the hero already in
# the barracks was overwritten with no warning, and the new one was then dropped
# by Party.add_member's duplicate-id guard without a word either. One character
# destroyed, one never created, nothing on screen about either.
#
# `preferred` is an id the character already carries (a preset's "vera", a
# character being re-saved); it is kept when it is still free, so re-saving is
# still an overwrite of the same file — only a genuinely new name gets a number.
static func unique_slug(name: String, preferred := "") -> String:
	var base: String = preferred if preferred != "" else slugify(name)
	if not exists(base):
		return base
	var n := 2
	while exists("%s-%d" % [base, n]):
		n += 1
	return "%s-%d" % [base, n]

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
		"offhand": ch.offhand,
		"pools": ch.pools.duplicate(),
		# Campaign state, exactly as `pools` is, and left out of here until
		# 2026-09-20: a caster who had spent two slots got them back from any
		# trip through this format. That is every autosave and every resume
		# (core/world_save.gd, core/campaign_save.gd) — and, since co-op sends
		# the party as these dictionaries, it is also what made the guest's
		# casters start each fight with a full spell list while the host's did
		# not. Two different boards from the same seed, which is a desync with
		# nothing to reconcile (issue #132).
		"slots_used": ch.slots_used.duplicate(),
		"hp_current": ch.hp_current,
		"buffs": ch.buffs.duplicate(true),
		"prepared": ch.prepared.duplicate(),
		"xp": ch.xp,
		"dead": ch.dead,
		"traits": ch.traits.duplicate(true),
		"traits_offered": ch.traits_offered,
		"trait_counts": ch.trait_counts.duplicate(),
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
		var lvl := {"class_id": String(l["class_id"]), "hp_roll": int(l.get("hp_roll", -1))}
		if bool(l.get("granted", false)):
			lvl["granted"] = true      # absent in a file written before this key existed:
		ch.levels.append(lvl)          # those levels read as earned, and stay earned
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
	ch.offhand = String(d.get("offhand", ""))
	for k in d.get("pools", {}):
		ch.pools[k] = int(d["pools"][k])
	# Missing in a file written before the key existed, which reads as "nothing
	# spent" — the behaviour those files already had.
	for n in d.get("slots_used", []):
		ch.slots_used.append(int(n))
	ch.hp_current = int(d.get("hp_current", -1))
	ch.buffs = d.get("buffs", {}).duplicate(true)
	ch.prepared.assign(d.get("prepared", []))
	ch.xp = int(d.get("xp", 0))
	ch.dead = bool(d.get("dead", false))
	# #176. Missing in a file written before traits: no traits, never asked —
	# which is exactly what makes the party page offer the pick once.
	for t in d.get("traits", []):
		if t is Dictionary and String(t.get("id", "")) != "":
			var tr := {"id": String(t["id"]), "why": String(t.get("why", ""))}
			# Step 3's earned keys, each only when present — JSON has no ints,
			# so the numbers are put back to the types core/traits.gd compares.
			for k in ["since", "until"]:
				if t.has(k):
					tr[k] = float(t[k])
			if t.has("dc"):
				tr["dc"] = int(t["dc"])
			if t.has("event"):
				tr["event"] = String(t["event"])
			if bool(t.get("told", false)):
				tr["told"] = true   # step 4: said at the fire once already
			if t.get("cure") is Dictionary:
				tr["cure"] = t["cure"].duplicate(true)
			ch.traits.append(tr)
	ch.traits_offered = bool(d.get("traits_offered", false))
	for k in d.get("trait_counts", {}):
		ch.trait_counts[String(k)] = int(d["trait_counts"][k])
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
	var ch = load_path(path_for(slug))
	# The file name IS the identity (see the header). A save whose `id` field
	# disagrees with it — hand-copied, renamed, written by an older build — would
	# otherwise come back wearing somebody else's id, and the second of the two
	# would be dropped silently the moment a Party loaded them both.
	if ch != null:
		ch.id = slug
	return ch

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

# --- #104: presets -----------------------------------------------------------
# A build kept to make again: the same file shape, in its own folder, keyed by
# the name. Loading one hands back a copy with no identity (id ""), so the
# creator mints a fresh character from it rather than resurrecting the original.
static var PRESET_DIR: String = SaveDir.path("presets")

static func save_preset(ch) -> String:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var d := to_dict(ch)
	d["id"] = slugify(ch.cname)
	d["hp_current"] = -1
	var path := "%s/%s.json" % [PRESET_DIR, d["id"]]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path)
		return ""
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return path

static func list_presets() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out

static func load_preset(slug: String):
	var ch = load_path("%s/%s.json" % [PRESET_DIR, slug])
	if ch != null:
		ch.id = ""
		ch.hp_current = -1
	return ch
