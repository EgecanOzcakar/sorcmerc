# Headless: the shared GLB cache. What it has to be true of is cheap to state
# and impossible to observe from the layers themselves — "was this file read
# twice" has no visible effect on a figure, only on the frame it appeared in —
# so this asserts it on the cache's own counters.
#   godot --headless --path . -s tests/test_model_cache.gd
extends SceneTree

const ModelCache = preload("res://scenes/model_cache.gd")
const Figures3D = preload("res://scenes/figures3d.gd")
const Party3D = preload("res://scenes/world/party3d.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)


func _init() -> void:
	var hero: String = Figures3D.HERO_MODELS["wizard"]
	var foe: String = Figures3D.FOE_MODELS["goblinoid"]
	var missing := "res://assets/figures/no_such_thing_idle.glb"

	# --- the plain contract ---------------------------------------------
	ModelCache.reset()
	check(ModelCache.get_scene("") == null, "the empty path is nothing, not an error")
	check(ModelCache.get_scene(missing) == null, "a path with no file is null (the caller's fallback tier)")
	check(not ModelCache.exists(missing), "...and exists() says so")
	var first := ModelCache.get_scene(hero)
	check(first != null, "a real model loads")
	check(first is PackedScene, "...as a PackedScene")
	var inst: Node = first.instantiate()
	check(inst != null, "...that instantiates")
	inst.free()

	# --- the whole point: one file, one read -----------------------------
	var before: Dictionary = ModelCache.stats()
	var second := ModelCache.get_scene(hero)
	check(second == first, "the same path hands back the very same resource")
	var after: Dictionary = ModelCache.stats()
	check(after["hits"] == before["hits"] + 1, "the second ask is a cache hit")
	check(after["blocking"] == before["blocking"] and after["waited"] == before["waited"],
		"...and reads nothing from disk")
	# A missing path is answered from the negative cache too — asked once,
	# answered forever, which is what stops a per-combatant beast lookup from
	# stat-ing the filesystem on every roster.
	check(ModelCache.get_scene(missing) == null, "a missing path stays missing")

	# The cross-layer half of it: the map layer and the combat layer are
	# separate objects reading the same file, and the second one must not pay.
	check(Party3D.HeroModels == Figures3D.HERO_MODELS,
		"the overworld and the board really do name the same hero files")

	# --- prefetch --------------------------------------------------------
	ModelCache.reset()
	var started: int = ModelCache.prefetch([hero, foe, missing, "", hero])
	check(started == 2, "prefetch starts one request per real, distinct, uncached path (got %d)" % started)
	check(ModelCache.prefetch([hero, foe]) == 0, "...and does not ask twice for one in flight")
	var pre := ModelCache.get_scene(hero)
	check(pre != null, "a prefetched model arrives")
	check(ModelCache.stats()["waited"] == 1, "...collected from the background request, not re-read")
	check(ModelCache.stats()["blocking"] == 0, "...so nothing was read on the calling thread")
	check(ModelCache.get_scene(foe) != null, "the other prefetched model arrives too")
	check(ModelCache.stats()["waited"] == 2, "...the same way")
	check(ModelCache.stats()["requested"] == 2, "two requests, for the two files worth requesting")

	# collect() drains what a caller never came back for, so a prefetch that
	# is abandoned (a roster that changed) cannot sit in flight forever.
	ModelCache.reset()
	ModelCache.prefetch([hero])
	for i in 60:
		ModelCache.collect()
		if ModelCache.ready(hero):
			break
		await process_frame
	check(ModelCache.ready(hero), "collect() takes in a finished request with no caller waiting")

	# --- the ceiling -----------------------------------------------------
	# Every hero class plus every troop model is more paths than one screen
	# wants at once and fewer than the cap, so nothing evicts; the cap itself
	# is asserted on the count, since loading 41 GLBs to prove it would read
	# most of assets/.
	ModelCache.reset()
	var hot := 0
	for cid in Figures3D.HERO_MODELS:
		if ModelCache.exists(Figures3D.HERO_MODELS[cid]):
			hot += 1
	for race in Party3D.MODELS:
		for role in Party3D.MODELS[race]:
			if ModelCache.exists(Party3D.MODELS[race][role]):
				hot += 1
	check(hot <= ModelCache.MAX_KEPT,
		"the cap clears a whole screen's hot set (%d models, cap %d)" % [hot, ModelCache.MAX_KEPT])

	# --- reset -----------------------------------------------------------
	ModelCache.get_scene(hero)
	ModelCache.reset()
	check(not ModelCache.ready(hero), "reset() drops what was cached")
	check(ModelCache.stats()["hits"] == 0 and ModelCache.stats()["requested"] == 0,
		"...and the counters with it")
	check(ModelCache.get_scene(hero) != null, "...and the cache still works afterwards")
	ModelCache.reset()

	print("test_model_cache: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
