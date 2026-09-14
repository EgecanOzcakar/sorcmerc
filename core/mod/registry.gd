# M6 — the shelf every pack sits on: find them, decide which are allowed to
# load, and hand the rest of the game one list.
#
#   Registry.scan()                 # Array of packs, official first, then by priority
#   Registry.playable()             # the ones with a world or a story to start
#   Registry.find("ashen-road")
#   Registry.apply_data()           # push every live pack's data overlays into the catalog
#   Registry.world_of(pack)         # a built World, or null (pack.errors says why)
#   Registry.story_of(pack)         # a core/mod/story.gd, or null
#
# Two roots, one pipeline:
#
#   res://content/    ships with the game — official free content and paid DLC.
#                     Marked `official`, and that flag comes from the ROOT, not
#                     from anything a pack can write about itself.
#   user://mods/      what the player installed. Same format, same loader, same
#                     validator. ($SORCMERC_MODS_DIR overrides it, the same way
#                     SORCMERC_SAVE_DIR overrides the save directory, so a test
#                     — or a second concurrent run — gets its own.)
#
# The same pipeline for both is the point of the design: shipping a paid story
# pack is writing a pack and setting `"access": "paid"`. There is no DLC code
# path for the team and a mod code path for everyone else, so official content
# is exercised by the same loader the community's is — which is the only way
# the community's half stays working.
#
# A pack's `status`:
#   "ok"        loaded; its data is live and its world/story can be started
#   "locked"    a paid pack this player does not own (core/mod/entitlement.gd).
#               Listed — that is how anybody learns it exists — but nothing of
#               its content is read.
#   "disabled"  turned off by the player
#   "broken"    failed validation; `errors` says how, and the browser shows it
extends RefCounted

const Manifest = preload("res://core/mod/manifest.gd")
const Entitlement = preload("res://core/mod/entitlement.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")
const Story = preload("res://core/mod/story.gd")
const Catalog = preload("res://core/rules/catalog.gd")

const OFFICIAL_ROOT := "res://content"
const USER_ROOT := "user://mods"
const MANIFEST := "pack.json"
const STATE_FILE := "mods.json"
const STATE_FORMAT := "sorcmerc-mods"
const STATE_VERSION := 1

# One discovered pack. Thin on purpose: the manifest is the pack, this adds
# only what discovery and validation learned about it.
class Pack extends RefCounted:
	var manifest                      # core/mod/manifest.gd
	var status := "ok"
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var _world = null                 # parsed world.json, cached
	var _story = null                 # core/mod/story.gd, cached

	func id() -> String: return manifest.id
	func title() -> String: return manifest.title if manifest.title != "" else manifest.id
	func live() -> bool: return status == "ok"
	func playable() -> bool: return live() and (manifest.has_world() or manifest.has_story())

	# The one-line status the browser shows next to the title.
	func label() -> String:
		match status:
			"locked": return "DLC — not owned"
			"disabled": return "off"
			"broken": return "%d problem(s)" % errors.size()
			_: return "free" if not manifest.is_paid() else "owned"

static var _packs: Array = []
static var _scanned := false
static var _disabled: Array[String] = []
static var _state_loaded := false

static func user_root() -> String:
	var env := OS.get_environment("SORCMERC_MODS_DIR")
	return env if env != "" else USER_ROOT

static func roots() -> Array[String]:
	return [OFFICIAL_ROOT, user_root()] as Array[String]

# --- the enabled/disabled list -------------------------------------------
#
# A DISABLED list rather than an enabled one, so a pack the player just
# installed — or a DLC they just bought — is on without anybody having to go
# and switch it on.

static func _state_path() -> String:
	var env := OS.get_environment("SORCMERC_SAVE_DIR")
	return (env if env != "" else "user://").path_join(STATE_FILE)

static func _load_state() -> void:
	if _state_loaded:
		return
	_state_loaded = true
	_disabled = [] as Array[String]
	var txt := FileAccess.get_file_as_string(_state_path())
	if txt.is_empty():
		return
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or d.get("format") != STATE_FORMAT:
		return
	for e in d.get("disabled", []):
		_disabled.append(String(e))

static func _save_state() -> void:
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"format": STATE_FORMAT, "version": STATE_VERSION,
		"disabled": _disabled}, "  "))
	f.close()

static func is_enabled(pack_id: String) -> bool:
	_load_state()
	return not _disabled.has(pack_id)

static func set_enabled(pack_id: String, on: bool) -> void:
	_load_state()
	if on:
		_disabled.erase(pack_id)
	elif not _disabled.has(pack_id):
		_disabled.append(pack_id)
	_save_state()
	scan(true)
	apply_data()

# --- discovery ------------------------------------------------------------

static func scan(force := false) -> Array:
	if _scanned and not force:
		return _packs
	_scanned = true
	_load_state()
	Entitlement.reload()
	_packs = []
	var seen := {}
	for root in roots():
		var official := root == OFFICIAL_ROOT
		for dir_name in _subdirs(root):
			var dir := root.path_join(dir_name)
			var pack = _read(dir, official)
			if pack == null:
				continue
			# First root wins a duplicate id, and the official root is first:
			# a mod cannot shadow a DLC by claiming its id, which would
			# otherwise be a way to make the game load the wrong content
			# under a name a save file trusts.
			if seen.has(pack.id()):
				pack.status = "broken"
				pack.errors.append("another pack already uses the id \"%s\"" % pack.id())
			else:
				seen[pack.id()] = pack
			_packs.append(pack)
	# Requirements resolve against everything found, so order does not matter.
	for pack in _packs:
		for need in pack.manifest.requires:
			var other = seen.get(need)
			if other == null:
				pack.status = "broken"
				pack.errors.append("needs pack \"%s\", which is not installed" % need)
			elif not other.live():
				pack.status = "broken"
				pack.errors.append("needs pack \"%s\", which is not loaded" % need)
	_packs.sort_custom(func(a, b):
		if a.manifest.official != b.manifest.official:
			return a.manifest.official           # official content layers first
		if a.manifest.priority != b.manifest.priority:
			return a.manifest.priority < b.manifest.priority
		return a.id() < b.id())
	return _packs

static func _subdirs(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

# A directory with no pack.json is not a broken pack, it is not a pack — the
# distinction matters because assets/ subdirectories and a stray unzip both
# look like directories to the scanner.
static func _read(dir: String, official: bool):
	var path := dir.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return null
	var err: Array = []
	var m = Manifest.parse(_json(path, err), dir)
	m.official = official
	if m.id.is_empty():
		m.id = dir.get_file()        # so a broken pack still has something to be listed as
	m.check_files()
	var pack := Pack.new()
	pack.manifest = m
	pack.errors.append_array(err)
	pack.errors.append_array(m.errors)
	if not m.ok():
		pack.status = "broken"
	elif not is_enabled(m.id):
		pack.status = "disabled"
	elif not Entitlement.owns(m):
		pack.status = "locked"
	else:
		_validate_content(pack)
	return pack

# Everything a pack declares is parsed and checked at scan time, not at play
# time: an author finds out their story is broken from the browser, and a
# player never gets three chapters into one that cannot finish.
static func _validate_content(pack) -> void:
	var m = pack.manifest
	var world_ids := {}
	if m.has_world():
		var src = _json(m.path_of(m.world_file), pack.errors)
		var report: Dictionary = WorldPack.validate(src)
		pack.errors.append_array(report["errors"])
		pack.warnings.append_array(report["warnings"])
		if report["errors"].is_empty():
			pack._world = src
			world_ids = _world_ids(src)
	if m.has_story():
		var src = _json(m.path_of(m.story_file), pack.errors)
		var story = Story.parse(src)
		story.check(world_ids, _own_item_ids(m))
		pack.errors.append_array(story.errors)
		pack.warnings.append_array(story.warnings)
		if story.ok():
			pack._story = story
	for target in m.data_files:
		var src = _json(m.path_of(String(m.data_files[target])), pack.errors)
		if src == null:
			pass                     # _json already said what was wrong with it
		elif not (src is Array or src is Dictionary):
			pack.errors.append("%s must be a list or an object" % m.data_files[target])
	if not pack.errors.is_empty():
		pack.status = "broken"

# The item ids this pack adds through its own data overlays. They are not in
# the catalog yet at scan time (apply_data runs after), so the story validator
# is handed them separately rather than warning about every reward a pack
# invents for itself.
static func _own_item_ids(m) -> Dictionary:
	var out := {}
	for file in ["magic-items.json", "weapons.json", "armor.json"]:
		if not m.data_files.has(file):
			continue
		var src = _json(m.path_of(String(m.data_files[file])))
		if src is Array:
			for r in src:
				if r is Dictionary and r.has("id"):
					out[String(r["id"])] = true
	return out

static func _world_ids(src) -> Dictionary:
	var out := {}
	if not (src is Dictionary):
		return out
	for group in [["settlements", "settlement"], ["lairs", "lair"], ["parties", "party"]]:
		for e in src.get(group[0], []):
			if e is Dictionary and e.has("id"):
				out[String(e["id"])] = group[1]
	return out

# Parsed JSON, or null with a readable reason appended to `err`.
# JSON.parse_string() pushes an engine error and hands back a bare null, which
# tells an author nothing and spams a test run; the instance API keeps the
# message and the line number, which is exactly what a pack author needs.
static func _json(path: String, err: Array = []):
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		err.append("%s is missing or empty" % path.get_file())
		return null
	var j := JSON.new()
	if j.parse(txt) != OK:
		err.append("%s: %s (line %d)" % [path.get_file(), j.get_error_message(),
			j.get_error_line()])
		return null
	return j.data

# --- what the rest of the game asks for -----------------------------------

static func find(pack_id: String):
	for p in scan():
		if p.id() == pack_id:
			return p
	return null

static func live() -> Array:
	return scan().filter(func(p): return p.live())

static func playable() -> Array:
	return scan().filter(func(p): return p.playable())

# Push every live pack's data overlays into core/rules/catalog.gd, in scan
# order. Call once after scan() and again whenever the set changes; it is
# cheap (the files are read once here, and the catalog re-reads its own
# base data lazily afterwards).
static func apply_data() -> void:
	var layers: Array = []
	for pack in live():
		var m = pack.manifest
		if m.data_files.is_empty():
			continue
		var files := {}
		for target in m.data_files:
			var src = _json(m.path_of(String(m.data_files[target])))
			if src != null:
				files[String(target)] = src
		if not files.is_empty():
			layers.append({"id": m.id, "files": files})
	Catalog.set_overlays(layers)
	# Pools built from the old bestiary are now wrong: a pack's monsters have to
	# be able to show up in a roster, and a pack that retuned one has to have
	# retuned it everywhere.
	load("res://core/scaler.gd").forget_pools()

# The pack's map, built. Returns null when the pack has no world or its world
# did not validate — scan() has already recorded why in pack.errors.
static func world_of(pack, seed_v := 0):
	if pack == null or pack._world == null:
		return null
	return WorldPack.build(pack._world, pack.id(), seed_v)

static func story_of(pack):
	return pack._story if pack != null else null

# One report for a test, a console, or the browser's "why is this red".
static func report() -> Array[String]:
	var out: Array[String] = []
	for p in scan():
		out.append("%s  [%s]  %s" % [p.id(), p.status, p.manifest.describe()])
		for e in p.errors:
			out.append("    error: " + e)
		for w in p.warnings:
			out.append("    warning: " + w)
	return out
