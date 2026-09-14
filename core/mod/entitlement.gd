# M2 — who owns what. The one place the game decides whether a paid pack's
# content is allowed to load.
#
#   Entitlement.owns(manifest)       # free packs: always. paid: only if bought.
#   Entitlement.grant("ember-crown") # after a purchase, or from a dev console
#   Entitlement.sync(["ember-crown"])# the storefront seam — see below
#
# The rule is deliberately blunt: a paid pack the player does not own is not
# "loaded, but with its content hidden". It is not loaded at all, so a locked
# DLC cannot leak a monster, an item name, or a line of its story through some
# other system that reads the catalog. The browser still LISTS it (that is how
# anybody learns it exists), from the manifest alone.
#
# The storefront seam. This file knows nothing about Steam, itch, or a web
# build's licence server, and should not: whatever does know calls sync() once
# at boot with the ids it says the player owns, and everything downstream keeps
# working. Until something does, the local file is the record — which is also
# exactly what a DRM-free itch build wants.
#
# user://entitlements.json  (or $SORCMERC_SAVE_DIR/entitlements.json, same
# override core/world_save.gd uses so concurrent runs don't share one file):
#
# {
#   "format": "sorcmerc-entitlements",
#   "version": 1,
#   "owned": ["vault-of-the-ember-crown"]
# }
extends RefCounted

const FORMAT := "sorcmerc-entitlements"
const VERSION := 1
const FILE := "entitlements.json"

static var _owned: Array[String] = []
static var _loaded := false

static func dir() -> String:
	var env := OS.get_environment("SORCMERC_SAVE_DIR")
	return env if env != "" else "user://"

static func path() -> String:
	return dir().path_join(FILE)

# Everything opens in a playtest build — the same switch core/progression.gd
# already uses to unlock species and classes, for the same reason: a playtest
# channel that cannot see half the content is not testing the game.
static func unlock_all() -> bool:
	return OS.has_feature("playtest") or OS.get_environment("SORCMERC_PLAYTEST") == "1" \
		or OS.get_environment("SORCMERC_UNLOCK_DLC") == "1"

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_owned = [] as Array[String]
	var txt := FileAccess.get_file_as_string(path())
	if txt.is_empty():
		return
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or d.get("format") != FORMAT:
		return
	for e in d.get("owned", []):
		_owned.append(String(e))

# Drop the cache; the next query re-reads the file. Tests point
# SORCMERC_SAVE_DIR somewhere of their own and call this.
static func reload() -> void:
	_loaded = false

static func owned() -> Array[String]:
	_load()
	return _owned.duplicate()

# `pack` is a core/mod/manifest.gd. A free pack is owned by everybody, which is
# what makes community content and official free content the same thing here.
static func owns(pack) -> bool:
	if pack == null or not pack.is_paid():
		return true
	if unlock_all():
		return true
	_load()
	return _owned.has(pack.id)

static func grant(pack_id: String) -> void:
	_load()
	if not _owned.has(pack_id):
		_owned.append(pack_id)
		_save()

static func revoke(pack_id: String) -> void:
	_load()
	if _owned.has(pack_id):
		_owned.erase(pack_id)
		_save()

# Replace the whole set from an authority outside the game (a storefront's
# "these are the DLCs this account owns"). Writing it down means the next
# launch still knows, offline.
static func sync(pack_ids: Array) -> void:
	_load()
	_owned = [] as Array[String]
	for e in pack_ids:
		_owned.append(String(e))
	_save()

static func _save() -> void:
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"format": FORMAT, "version": VERSION,
		"owned": _owned}, "  "))
	f.close()
