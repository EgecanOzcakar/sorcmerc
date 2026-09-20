# One process-wide cache, and one background loader, for the big GLBs.
#
# THE PROBLEM THIS SOLVES. assets/figures, assets/troops, assets/beasts and
# assets/lairs are ~220 MB of Meshy exports — a hero rig is ~3 MB, goblin_std
# is 23 MB — and every one of them used to be read by a bare `load()` on the
# main thread, from two private dictionaries that knew nothing about each
# other (scenes/figures3d.gd and scenes/world/props3d.gd). Two consequences,
# both visible:
#
#   1. A reset() paid for its models one at a time, in series, on the frame
#      that asked for them. Opening the overworld reads a settlement GLB per
#      (faction, kind) and a troop GLB per band; starting a fight reads one
#      per class and faction on the roster. Godot's loader is a thread pool —
#      asking it for all of them FIRST and collecting them after is the same
#      bytes off the same disk with the waiting overlapped, which is what
#      prefetch() below is for.
#
#   2. The same file was read twice and kept twice. The player's figure on
#      the map (scenes/world/party3d.gd) and the same hero in the fight
#      (scenes/figures3d.gd) are the same wizard_idle.glb, and a beast band
#      marching and that beast on the board are the same wolf.glb — but the
#      caches were per-layer, so entering a fight re-read from disk what the
#      map already had in memory. One cache, shared by every layer, means the
#      second reader is free.
#
# WHAT A CALLER GETS. get_scene() has exactly the contract the two private
# dictionaries had: the PackedScene, or null when there is no such file —
# which is never an error, it is how a class or faction the art has not
# covered yet falls through to the vector/pawn tier. It never returns a
# half-loaded scene and never makes a caller poll: a path that was prefetched
# and is still in flight is waited for, so "prefetch, then build" is always at
# least as fast as building straight away, and usually much faster.
#
# Deliberately NOT an autoload: static state on a RefCounted, the same shape
# core/rules/catalog.gd uses, so a test can preload it and reset() it without
# a SceneTree.
extends RefCounted

# How many models stay warm. The per-layer dictionaries this replaces died
# with their screen; a shared one outlives every screen, so it needs a ceiling
# or a long session accumulates all 220 MB of assets/. The number has to clear
# the whole hot set of a screen, not an average: an overworld can want twelve
# settlement models (4 factions x 3 kinds) and twelve troop models (4 races x
# 3 roles) at once, and the fight it launches adds a class figure per hero and
# one per foe faction on top — so a cap that fits the average would evict
# inside a single reset() and re-read what it just dropped. 40 clears that and
# still bounds the cache at roughly 120 MB of GLB. Eviction itself is cheap:
# an instantiated figure does not need the PackedScene it came from to stay
# alive, so dropping one only costs a re-read if it is wanted again.
const MAX_KEPT := 40

static var _scenes := {}       # path -> PackedScene (never null; see _missing)
static var _missing := {}      # path -> true, for a path with no file: asked once, answered forever
static var _pending := {}      # path -> true while a background request is in flight
static var _order: Array[String] = []   # paths in _scenes, least recently used first
static var _counts := {"hits": 0, "waited": 0, "blocking": 0, "requested": 0, "evicted": 0}


# Ask the loader for everything this caller is about to build, before it
# builds any of it. Returns how many new background requests were started —
# the rest were already cached, already in flight, or have no file.
#
# The contract is "prefetch what you are about to ask for": a request nobody
# collects with get_scene() stays in flight, holding its bytes, until
# collect() or reset() drains it. Every caller in the tree prefetches at the
# top of a reset() and consumes the whole list a few lines later.
static func prefetch(paths: Array) -> int:
	var started := 0
	for p in paths:
		var path := String(p)
		if path == "" or _scenes.has(path) or _missing.has(path) or _pending.has(path):
			continue
		if not exists(path):
			continue
		# Sub-threads left off: a GLB's textures would load in parallel with
		# it, and this project's own measurements never needed it. The win
		# here is across FILES, and that comes from the pool being asked for
		# several at once, which this does.
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = true
			_counts["requested"] += 1
			started += 1
	return started


# The scene at `path`, or null when there is no file there (an uncovered
# class, faction or beast — the caller's fallback tier, not an error).
static func get_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _scenes.has(path):
		_touch(path)
		_counts["hits"] += 1
		return _scenes[path] as PackedScene
	if _missing.has(path):
		return null
	var res: Resource
	if _pending.erase(path):
		# Already in flight from a prefetch(): this returns at once if it has
		# finished and waits out only what is left, which is the whole point
		# of having asked early.
		_counts["waited"] += 1
		res = ResourceLoader.load_threaded_get(path)
	else:
		if not exists(path):
			return null
		_counts["blocking"] += 1
		res = ResourceLoader.load(path)
	return _store(path, res)


# Is it already in memory, right now, with nothing to wait for? For a caller
# that wants to show something else rather than stall; nothing in the tree
# needs it yet, but it is the question a streaming caller would ask.
static func ready(path: String) -> bool:
	return path != "" and _scenes.has(path)


# ResourceLoader.exists(), remembered. The layers call this per combatant and
# per band to decide which tier draws them (figures3d.gd's beast lookup asks
# for every roster it builds), and a negative answer can never change while
# the game is running.
static func exists(path: String) -> bool:
	if path == "":
		return false
	if _scenes.has(path):
		return true
	if _missing.has(path):
		return false
	if ResourceLoader.exists(path):
		return true
	_missing[path] = true
	return false


# Take in whatever background requests have already finished, without waiting
# for any that have not. Only reset() needs it — a caller that prefetches what
# it then asks for leaves nothing behind.
static func collect() -> void:
	for path in _pending.keys():
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_pending.erase(path)
			_store(path, ResourceLoader.load_threaded_get(path))


# Drop everything, in-flight requests included. For a test that wants a cold
# cache, and for anything that invalidates paths wholesale (a content pack
# changing which files exist) — the same job core/rules/catalog.gd's reset()
# does for data/*.json.
static func reset() -> void:
	for path in _pending.keys():
		ResourceLoader.load_threaded_get(path)   # drained, not leaked: this request had an owner
	_pending.clear()
	_scenes.clear()
	_missing.clear()
	_order.clear()
	_counts = {"hits": 0, "waited": 0, "blocking": 0, "requested": 0, "evicted": 0}


# hits/waited/blocking/requested/evicted — what a test asserts on, since "was
# this read from disk twice" has no other observable.
static func stats() -> Dictionary:
	return _counts.duplicate()


static func _store(path: String, res: Resource) -> PackedScene:
	var scene := res as PackedScene
	if scene == null:
		# No file, or a load that failed: either way this path has nothing to
		# give, and asking again next frame would only fail again.
		_missing[path] = true
		return null
	_scenes[path] = scene
	_touch(path)
	while _order.size() > MAX_KEPT:
		var old: String = _order.pop_front()
		_scenes.erase(old)
		_counts["evicted"] += 1
	return scene


static func _touch(path: String) -> void:
	_order.erase(path)
	_order.append(path)
