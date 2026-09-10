# Local achievements. One small JSON file at  user://achievements.json  — same
# convention as core/settings.gd: a documented format, unknown keys ignored,
# unknown ids dropped on load.
#
# This is THIS MACHINE's profile, not a save: it is not per-character and not
# per-campaign, and it deliberately survives party wipes, deleted characters and
# finished runs. Nothing here is ever locked back.
#
# {
#   "format": "sorcmerc-achievements",   // literal, checked on load
#   "version": 1,                        // bump only on an incompatible change
#   "unlocked": {                        // id -> ISO-8601 UTC unlock timestamp
#     "first_victory": "2026-09-10T14:02:11"
#   }
# }
#
# Gameplay only ever calls  Achievements.unlock("id")  — idempotent, write-through,
# returns true the first time only, so a caller can pop a toast on true.
extends RefCounted

const PATH := "user://achievements.json"
const FORMAT := "sorcmerc-achievements"
const VERSION := 1

# The whole list, in display order. Real, checkable milestones only.
const DEFS := [
	{"id": "first_victory", "title": "First Blood",
		"desc": "Win your first combat."},
	{"id": "death_save", "title": "Not Today",
		"desc": "Have a character go down and survive their death saves."},
	{"id": "identify_item", "title": "Arcane Appraiser",
		"desc": "Successfully identify a magic item."},
	{"id": "loot_very_rare", "title": "Treasure Hunter",
		"desc": "Loot an item of very rare quality or better."},
	{"id": "equip_legendary", "title": "Wielding Legend",
		"desc": "Equip a legendary item."},
	{"id": "level_5", "title": "Seasoned",
		"desc": "Bring a character to level 5."},
	{"id": "level_20", "title": "Living Legend",
		"desc": "Bring a character to level 20, the highest there is."},
	{"id": "spell_5th", "title": "High Magic",
		"desc": "Have a character learn a spell of 5th level or higher."},
	{"id": "resurrect_ally", "title": "Back From the Dead",
		"desc": "Resurrect a fallen ally, by spell or by scroll."},
	{"id": "hard_flawless", "title": "Untouchable",
		"desc": "Win a fight on hard difficulty with nobody downed."},
	{"id": "big_spender", "title": "Big Spender",
		"desc": "Spend 1,000 gold or more at merchants in a single run."},
	{"id": "campaign_clear", "title": "The Long Road",
		"desc": "Finish a campaign: reach the boss and beat it."},
	{"id": "retire_run", "title": "Quit While Ahead",
		"desc": "Retire a run voluntarily instead of pushing your luck."},
]

var unlocked := {}   # id -> ISO timestamp

static var _current = null

# The shared instance, loaded from disk on first use.
static func current():
	if _current == null:
		_current = load_state()
	return _current

static func load_state():
	var a = new()
	var txt := FileAccess.get_file_as_string(PATH)
	var d = JSON.parse_string(txt) if not txt.is_empty() else null
	if d is Dictionary and d.get("format") == FORMAT:
		var got = d.get("unlocked", {})
		if got is Dictionary:
			for def in DEFS:
				var at := String(got.get(def["id"], ""))
				if not at.is_empty():
					a.unlocked[def["id"]] = at
	return a

static func to_dict(a) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "unlocked": a.unlocked}

# Returns the path written, or "" on failure.
static func save_state(a = null) -> String:
	if a == null:
		a = current()
	_current = a
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % PATH)
		return ""
	f.store_string(JSON.stringify(to_dict(a), "  "))
	f.close()
	return PATH

# True only the first time: already-unlocked (or unknown) ids are a no-op, so a
# caller may fire this every frame it likes and still pop one toast.
static func unlock(id: String) -> bool:
	if find(id).is_empty() or is_unlocked(id):
		return false
	current().unlocked[id] = Time.get_datetime_string_from_system(true)
	save_state()
	return true

static func is_unlocked(id: String) -> bool:
	return current().unlocked.has(id)

# ISO timestamp, or "" when locked.
static func unlocked_at(id: String) -> String:
	return String(current().unlocked.get(id, ""))

static func find(id: String) -> Dictionary:
	for def in DEFS:
		if def["id"] == id:
			return def
	return {}

# Every achievement with its state, in display order — what the viewer draws.
static func all() -> Array:
	var out := []
	for def in DEFS:
		out.append({"id": def["id"], "title": def["title"], "desc": def["desc"],
			"unlocked": is_unlocked(def["id"]), "at": unlocked_at(def["id"])})
	return out
