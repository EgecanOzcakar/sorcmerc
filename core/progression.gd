# Meta-progression: which species / classes / subclasses this machine has opened.
# One small JSON file at  user://progression.json  — same convention as
# core/achievements.gd: a documented format, unknown keys ignored, unknown ids
# dropped on load.
#
# This is THIS MACHINE's profile, not a save: not per-character, not per-campaign.
# It survives party wipes, deleted characters and finished runs, and nothing here
# is ever locked back — lifetime XP only ever goes up.
#
# {
#   "format": "sorcmerc-progression",  // literal, checked on load
#   "version": 1,                      // bump only on an incompatible change
#   "lifetime_xp": 12500,              // every XP ever earned, all characters
#   "class_xp": {"cleric": 7300},      // XP earned while playing that class
#   "chosen": {                        // the 2 free subclass picks per unlocked
#     "rogue": ["thief", "soulknife"]  // class; the starting 5 are constants
#   }
# }
#
# Two currencies, two tiers:
#   * lifetime XP unlocks species and classes, automatically, the moment the
#     threshold is crossed — nothing is spent, so an unlock is permanent.
#   * unlocking a class grants 2 free subclass picks out of its 4:
#     unlock_class(id, [a, b]) records them. The other 2 cost class XP,
#     5,000 each, a per-class counter fed by playing that class.
#
# A class whose threshold is crossed is already unlocked; its 2 free picks stay
# pending until unlock_class() is called, and until then none of its subclasses
# read as unlocked.
#
# This model NEVER invalidates an existing character: it answers "may the creator
# offer this?", nothing more. Vera (fighter) and Pike (rogue) are perfectly legal
# characters whether or not their classes are open here.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")

const PATH := "user://progression.json"
const FORMAT := "sorcmerc-progression"
const VERSION := 1

const SUBCLASS_COST := 5000   # class XP, flat, for each of a class's other 2

# Open from day one, with every one of their lineages.
const STARTING_SPECIES := ["human", "orc", "elf", "dwarf"]

# Locked, cheapest first. The ordering is tunable — the spec fixed the five
# thresholds but not who gets which. Chosen by how far each strays from the
# ordinary mortal roster: gnome and tiefling are common enough sights, the big
# flashy lineages (dragonborn, goliath) come next, and the celestial-blooded
# aasimar is the rarest thing on the list, so it costs the most.
const SPECIES_COST := {
	"gnome": 3000,
	"tiefling": 6000,
	"dragonborn": 9000,
	"goliath": 12000,
	"aasimar": 15000,
}

# Open from day one, each with exactly 2 of its 4 subclasses pre-chosen.
const STARTING_CLASSES := {
	"cleric": ["lifedomain", "lightdomain"],
	"warlock": ["archfeypatron", "fiendpatron"],
	"wizard": ["abjurer", "evoker"],
	"barbarian": ["berserker", "zealot"],
	"ranger": ["gloomstalker", "hunter"],
}

# Locked, cheapest first, and every one of them above every species threshold.
# Ordering is tunable again: the two MVP-preset classes come first so a returning
# player re-opens familiar ground early, then the rest by how many moving parts
# they ask a new player to juggle, ending on the sorcerer's metamagic economy.
const CLASS_COST := {
	"rogue": 20000,
	"fighter": 30000,
	"bard": 40000,
	"monk": 50000,
	"druid": 60000,
	"paladin": 70000,
	"sorcerer": 80000,
}

var lifetime_xp := 0
var class_xp := {}   # class id -> int
var chosen := {}     # class id -> [2 subclass ids], unlocked classes only

static var _current = null

# The shared instance, loaded from disk on first use.
static func current():
	if _current == null:
		_current = load_state()
	return _current

static func load_state():
	var p = new()
	var txt := FileAccess.get_file_as_string(PATH)
	var d = JSON.parse_string(txt) if not txt.is_empty() else null
	if d is Dictionary and d.get("format") == FORMAT:
		p.lifetime_xp = maxi(0, int(d.get("lifetime_xp", 0)))
		var xp = d.get("class_xp", {})
		if xp is Dictionary:
			for id in xp:
				if CLASS_COST.has(id) or STARTING_CLASSES.has(id):
					p.class_xp[id] = maxi(0, int(xp[id]))
		var pick = d.get("chosen", {})
		if pick is Dictionary:
			for id in pick:
				if CLASS_COST.has(id) and _valid_picks(id, pick[id]):
					p.chosen[id] = Array(pick[id]).map(func(s): return String(s))
	return p

static func to_dict(p) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "lifetime_xp": p.lifetime_xp,
		"class_xp": p.class_xp, "chosen": p.chosen}

# Returns the path written, or "" on failure.
static func save_state(p = null) -> String:
	if p == null:
		p = current()
	_current = p
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % PATH)
		return ""
	f.store_string(JSON.stringify(to_dict(p), "  "))
	f.close()
	return PATH

# --- earning ---------------------------------------------------------------

# Every XP a character earns, anywhere, also lands here. Write-through; returns
# the new total.
static func add_lifetime_xp(n: int) -> int:
	if n > 0:
		current().lifetime_xp += n
		save_state()
	return current().lifetime_xp

# XP earned while playing a character of `class_id`, banked per class.
static func add_class_xp(class_id: String, n: int) -> int:
	if n > 0 and (CLASS_COST.has(class_id) or STARTING_CLASSES.has(class_id)):
		current().class_xp[class_id] = class_xp_of(class_id) + n
		save_state()
	return class_xp_of(class_id)

static func lifetime_xp_total() -> int:
	return current().lifetime_xp

static func class_xp_of(class_id: String) -> int:
	return int(current().class_xp.get(class_id, 0))

# --- species ---------------------------------------------------------------

# Lifetime XP needed; 0 for the day-one four and for anything unknown.
static func species_cost(id: String) -> int:
	return int(SPECIES_COST.get(id, 0))

# Export presets tag a "playtest" build via custom_features — everything opens
# for friends trying the game early, with the real lifetime/class-XP gates back
# in force the moment a release build (no such feature) is exported. Doesn't
# touch saved progress either way: it's a check here, not a write anywhere.
# SORCMERC_PLAYTEST=1 forces it the same way SORCMERC_FAST/_SEED do elsewhere —
# a real export can't be spun up from a headless test run to prove the branch.
static func _playtest_build() -> bool:
	return OS.has_feature("playtest") or OS.get_environment("SORCMERC_PLAYTEST") == "1"

static func is_species_unlocked(id: String) -> bool:
	if _playtest_build() or id in STARTING_SPECIES:
		return true
	return SPECIES_COST.has(id) and current().lifetime_xp >= species_cost(id)

# Unlocks are automatic at the threshold, so this only reports whether it took —
# there is nothing to spend and nothing to record.
static func unlock_species(id: String) -> bool:
	return is_species_unlocked(id)

# Species unlock all of their lineages together; there is no lineage currency.
static func is_lineage_unlocked(species_id: String, _lineage_id: String) -> bool:
	return is_species_unlocked(species_id)

# --- classes ---------------------------------------------------------------

static func class_cost(id: String) -> int:
	return int(CLASS_COST.get(id, 0))

static func is_class_unlocked(id: String) -> bool:
	if _playtest_build() or STARTING_CLASSES.has(id):
		return true
	return CLASS_COST.has(id) and current().lifetime_xp >= class_cost(id)

# The 2 free subclass picks that came with the unlock: the fixed pair for a
# starting class, the player's pair for one bought with lifetime XP, and [] while
# an unlocked class still owes its choice.
static func free_subclasses(class_id: String) -> Array:
	if STARTING_CLASSES.has(class_id):
		return STARTING_CLASSES[class_id]
	return current().chosen.get(class_id, [])

# True while an unlocked class has yet to name its 2 free subclasses. Never
# true in a playtest build -- forcing a pick-2 flow to get "everything open"
# would defeat the point.
static func awaits_picks(class_id: String) -> bool:
	if _playtest_build():
		return false
	return is_class_unlocked(class_id) and free_subclasses(class_id).is_empty()

# Records the 2 free picks that come with a lifetime-XP class unlock. Rejects a
# class that is not unlocked (or has already picked), anything other than exactly
# 2 distinct ids, and any id belonging to another class.
static func unlock_class(class_id: String, chosen_subclass_ids: Array) -> bool:
	if not awaits_picks(class_id) or not _valid_picks(class_id, chosen_subclass_ids):
		return false
	current().chosen[class_id] = Array(chosen_subclass_ids).map(func(s): return String(s))
	save_state()
	return true

static func _valid_picks(class_id: String, ids) -> bool:
	if not (ids is Array) or ids.size() != 2 or String(ids[0]) == String(ids[1]):
		return false
	var of := Catalog.subclasses_of(class_id)
	return String(ids[0]) in of and String(ids[1]) in of

# --- subclasses ------------------------------------------------------------

# The 2 a class did not get for free, in data order — these cost class XP.
static func paid_subclasses(class_id: String) -> Array:
	var free := free_subclasses(class_id)
	if free.is_empty():
		return []
	return Catalog.subclasses_of(class_id).filter(func(s): return not (s in free))

static func is_subclass_unlocked(id: String) -> bool:
	var src = Catalog.index("subclasses.json").get(id)
	if src == null:
		return false
	if _playtest_build():
		return true
	var class_id := String(src.get("classId", ""))
	if id in free_subclasses(class_id):
		return true
	var i := paid_subclasses(class_id).find(id)
	return i >= 0 and class_xp_of(class_id) >= (i + 1) * SUBCLASS_COST

# Class XP still owed before `id` opens; 0 once it has.
static func subclass_remaining(id: String) -> int:
	if is_subclass_unlocked(id):
		return 0
	var src = Catalog.index("subclasses.json").get(id)
	if src == null:
		return 0
	var class_id := String(src.get("classId", ""))
	var i := paid_subclasses(class_id).find(id)
	if i < 0:
		return SUBCLASS_COST   # class not unlocked / picks pending: full price
	return (i + 1) * SUBCLASS_COST - class_xp_of(class_id)

# --- viewer rows -----------------------------------------------------------

# Every species, day-one first then by rising cost, with its state — what the
# viewer draws. `remaining` is lifetime XP still to earn.
static func all_species() -> Array:
	var out := []
	for id in STARTING_SPECIES + SPECIES_COST.keys():
		var src = Catalog.index("species.json").get(id)
		out.append({"id": id, "name": String(src.get("name", id)) if src else id,
			"cost": species_cost(id), "unlocked": is_species_unlocked(id),
			"remaining": maxi(0, species_cost(id) - current().lifetime_xp),
			"lineages": src.get("lineages", []) if src else []})
	return out

# Every class in the same shape, each carrying its 4 subclasses' state.
static func all_classes() -> Array:
	var out := []
	for id in STARTING_CLASSES.keys() + CLASS_COST.keys():
		var subs := []
		for s in Catalog.subclasses_of(id):
			var src = Catalog.index("subclasses.json").get(s)
			subs.append({"id": s, "name": String(src.get("name", s)) if src else s,
				"unlocked": is_subclass_unlocked(s), "free": s in free_subclasses(id),
				"remaining": subclass_remaining(s)})
		var src = Catalog.index("classes.json").get(id)
		out.append({"id": id, "name": String(src.get("name", id)) if src else id,
			"cost": class_cost(id), "unlocked": is_class_unlocked(id),
			"remaining": maxi(0, class_cost(id) - current().lifetime_xp),
			"awaits_picks": awaits_picks(id), "class_xp": class_xp_of(id),
			"subclasses": subs})
	return out
