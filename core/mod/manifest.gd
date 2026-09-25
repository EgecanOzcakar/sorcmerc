# M1 — a content pack's front page: `pack.json`, parsed and validated.
#
# A pack is a directory with a pack.json in it and, next to it, whatever it
# declares: a world, a story, JSON that overlays the game's own data/*.json.
# Nothing else. In particular a pack may NOT ship GDScript — see the "data
# only" note below — so this file is the whole of what the game will ever
# execute on a stranger's behalf: it reads a dictionary and copies fields out
# of it.
#
#   var m = Manifest.parse(JSON.parse_string(txt), "user://mods/ashen-road")
#   if not m.ok(): printerr(m.errors)     # every problem at once, not the first
#
# The shape (every key optional except `format`/`id`/`title`):
#
# {
#   "format": "sorcmerc-pack",   // literal; anything else is not a pack
#   "api": 1,                    // the modding API this pack was written against
#   "id": "ashen-road",          // slug, unique across every root; the save file
#                                //   remembers it, so renaming one orphans saves
#   "title": "The Ashen Road",
#   "summary": "One paragraph for the browser.",
#   "authors": ["The sorcmerc team"],
#   "pack_version": "1.0.0",     // the PACK's version, free-form; not `api`
#   "kind": "campaign",          // "world" | "campaign" | "data" — a label for the
#                                //   browser. What a pack DOES is decided by the
#                                //   files it declares, never by this.
#   "access": "free",            // "free" | "paid" — see core/mod/entitlement.gd
#   "product_id": "sorcmerc.dlc.ashen-road",   // storefront SKU, paid packs only
#   "priority": 0,               // data-overlay order; higher lands later, so it wins
#   "requires": ["some-other-pack"],           // ids that must be present and enabled
#   "world": "world.json",       // core/mod/world_pack.gd
#   "story": "story.json",       // core/mod/story.gd
#   "callings": "callings.json", // core/callings.gd: {background: template}, merged over the built-in
#   "data": {"bestiary.json": "beasts.json"}   // catalog file <- this pack's file
# }
#
# Data only, deliberately. Community content is downloaded from strangers and
# run on a player's machine; a pack that could ship code would be a way to run
# that code. Every pack is therefore JSON interpreted by the modules under
# core/mod/, which is also why the same pipeline can carry an official DLC and
# a mod from a forum without two trust levels: there is only one, and it is
# "this is data".
extends RefCounted

const FORMAT := "sorcmerc-pack"

# The modding API level this build speaks. A pack declaring a HIGHER one is
# rejected with a readable reason rather than half-loaded — it was written
# against a game that knows things this one does not. A lower one is fine and
# always will be: that is the promise this number exists to make.
const API := 1

const ACCESS := ["free", "paid"]
const KINDS := ["world", "campaign", "data"]

# Which of the game's own data files a pack may overlay (core/rules/catalog.gd
# reads exactly these names). An allowlist rather than "any filename" so a
# typo — "monster.json" — is an error the browser shows, not an overlay that
# silently does nothing for the rest of the pack's life.
const DATA_FILES := ["classes.json", "subclasses.json", "species.json",
	"backgrounds.json", "feats.json", "fighting-styles.json", "weapons.json",
	"armor.json", "magic-items.json", "spells.json", "conditions.json",
	"monsters.json", "bestiary.json", "skills.json",
	# T33/T94 — data/effects/*.json: what a spell, a potion, a feature or a
	# condition DOES, as against the catalog entry that says it exists. The
	# catalog has layered these the whole time (Catalog.all() takes any of its
	# own filenames), but the allowlist did not name them, so a pack could add
	# a spell nobody could cast and a potion nobody could drink — the silent
	# dead-end this allowlist exists to prevent, on the one axis it missed.
	"effects/spells.json", "effects/potions.json", "effects/features.json",
	"effects/conditions.json",
	# The inns' hirelings (core/recruits.gd): what they are called, by species,
	# and what they carry, by class — so a pack's new species is not a common
	# room full of "default" names, and its new class does not sign on unarmed.
	"recruit-names.json", "recruit-kits.json",
	# 2026-09-25: what a worn magic item does on the sheet (core/rules/
	# pass_items.gd). Added, not renamed: every API-1 pack still loads.
	"effects/items.json"]

# The subset of DATA_FILES that is an object keyed by id rather than a list of
# records, and whose values core/rules/effects.gd (or, for items,
# core/rules/pass_items.gd) interprets. Listed apart because registry.gd
# validates them against that vocabulary at scan time.
const EFFECT_FILES := ["effects/spells.json", "effects/potions.json",
	"effects/features.json", "effects/conditions.json", "effects/items.json"]

const SLUG := "^[a-z0-9][a-z0-9_-]*$"

var id := ""
var title := ""
var summary := ""
var authors: Array[String] = []
var pack_version := "1.0.0"
var kind := "data"
var access := "free"
var product_id := ""
var priority := 0
var requires: Array[String] = []
var api := 1

var world_file := ""          # "" when this pack ships no map
var story_file := ""          # "" when it tells no story
var callings_file := ""       # "" when it adds no callings
var data_files := {}          # catalog filename -> this pack's filename

# Where the pack.json was found, without the filename: every path above is
# resolved against it and nowhere else, so a pack cannot reach out of its
# own directory.
var dir := ""

# Set by core/mod/registry.gd from the root it was discovered in, never by the
# pack itself — a mod claiming to be official would otherwise be one line of
# JSON away from it.
var official := false

var errors: Array[String] = []

func ok() -> bool:
	return errors.is_empty()

func path_of(file: String) -> String:
	return dir.path_join(file)

func is_paid() -> bool:
	return access == "paid"

func has_world() -> bool:
	return world_file != ""

func has_story() -> bool:
	return story_file != ""

func has_callings() -> bool:
	return callings_file != ""

# One line for the browser and for a validation report.
func describe() -> String:
	var by := "  —  " + ", ".join(authors) if not authors.is_empty() else ""
	return "%s  v%s%s" % [title if title != "" else id, pack_version, by]

static func _strings(v, into: Array[String]) -> void:
	if v is Array:
		for e in v:
			into.append(String(e))

# Never fails, never throws: a broken pack.json comes back as a Manifest with
# `errors` on it. The browser can then show the pack AND why it will not load,
# which is the only way an author finds out what they typed wrong.
# (no class_name anywhere in this project: `new()` is the script itself, same
# shape core/settings.gd's load_settings() uses.)
static func parse(src, dir_v: String):
	var m = new()
	m.dir = dir_v
	if not (src is Dictionary):
		m.errors.append("pack.json is not a JSON object")
		return m
	var d: Dictionary = src
	if String(d.get("format", "")) != FORMAT:
		m.errors.append("format must be \"%s\"" % FORMAT)
	m.api = int(d.get("api", 1))
	if m.api > API:
		m.errors.append("needs modding API %d; this build speaks %d" % [m.api, API])

	m.id = String(d.get("id", ""))
	if m.id.is_empty():
		m.errors.append("missing id")
	elif not RegEx.create_from_string(SLUG).search(m.id):
		m.errors.append("id \"%s\" must be lowercase letters, digits, - and _" % m.id)

	m.title = String(d.get("title", ""))
	if m.title.is_empty():
		m.errors.append("missing title")
	m.summary = String(d.get("summary", ""))
	_strings(d.get("authors", []), m.authors)
	m.pack_version = String(d.get("pack_version", "1.0.0"))

	m.kind = String(d.get("kind", "data"))
	if not KINDS.has(m.kind):
		m.errors.append("kind \"%s\" is not one of %s" % [m.kind, ", ".join(KINDS)])

	m.access = String(d.get("access", "free"))
	if not ACCESS.has(m.access):
		m.errors.append("access \"%s\" is not one of %s" % [m.access, ", ".join(ACCESS)])
	m.product_id = String(d.get("product_id", ""))
	# A paid pack with no SKU cannot be bought, so it can never be unlocked by
	# anything but the playtest switch — which is a pack that ships broken.
	if m.is_paid() and m.product_id.is_empty():
		m.errors.append("a paid pack needs a product_id")

	m.priority = int(d.get("priority", 0))
	_strings(d.get("requires", []), m.requires)

	m.world_file = String(d.get("world", ""))
	m.story_file = String(d.get("story", ""))
	m.callings_file = String(d.get("callings", ""))
	var data = d.get("data", {})
	if data is Dictionary:
		for key in data:
			var target := String(key)
			if not DATA_FILES.has(target):
				m.errors.append("data key \"%s\" is not a game data file" % target)
				continue
			m.data_files[target] = String(data[key])
	elif data != null:
		m.errors.append("data must be an object of {game file: pack file}")
	return m

# The other half of validation: the files it claims exist. Split out because
# parse() is pure (a test can hand it a dictionary) while this one touches
# disk — and because the registry wants both, in that order.
func check_files() -> void:
	for f in _declared_files():
		if not FileAccess.file_exists(path_of(f)):
			errors.append("declared file is missing: %s" % f)

func _declared_files() -> Array[String]:
	var out: Array[String] = []
	if has_world():
		out.append(world_file)
	if has_story():
		out.append(story_file)
	if has_callings():
		out.append(callings_file)
	for target in data_files:
		out.append(String(data_files[target]))
	return out
