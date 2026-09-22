# #158: the seam between the models on disk and the bestiary they stand for.
#
#   godot --headless --path . -s tests/test_figure_models.gd
#
# scenes/figures3d.gd decides what draws a combatant from three tables and a
# naming convention: HERO_MODELS by class id, a file at assets/beasts/<bestiary
# id>.glb, then FOE_MODELS by faction, then the vector disc/glyph tier. Every
# one of those is a STRING matched against something else — a class id out of
# data/classes.json, a bestiary id, a faction — and nothing has ever checked
# that the two sides still agree. A class renamed, a monster id respelled or a
# .glb dropped from a batch all fail the same silent way: that figure quietly
# stops being 3D and nobody notices until a screenshot.
#
# So: every path named exists, every key names something real, every file on
# disk answers to a bestiary id, and the coverage numbers have a floor under
# them. The floor is a regression guard, not a target — raise it when a batch
# lands, never lower it to make a red run green.
#
# It also PRINTS the coverage, by faction, with the uncovered factions named.
# A faction with no model at all is a fight drawn entirely in vector discs
# (core/scaler.gd draws a roster from one faction), which makes that list the
# answer to "what should the next batch of models be".
extends SceneTree

const Catalog = preload("res://core/rules/catalog.gd")
const Figures3D = preload("res://scenes/figures3d.gd")

# What is on disk today. Raise these when a batch of models lands.
const MIN_BY_ID := 109        # assets/beasts/<bestiary id>.glb files (2026-09-22 batch: +34)
const MIN_FACTIONS := 7       # factions FOE_MODELS answers for outright

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var bestiary: Array = Catalog.all("bestiary.json")
	test_paths_exist()
	test_every_class_has_a_figure()
	test_factions_are_real(bestiary)
	test_files_answer_to_a_bestiary_id(bestiary)
	report(bestiary)
	print("test_figure_models: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_paths_exist() -> void:
	for cid in Figures3D.HERO_MODELS:
		var path: String = String(Figures3D.HERO_MODELS[cid])
		check(ResourceLoader.exists(path), "hero figure for %s is on disk (%s)" % [cid, path])
	for fac in Figures3D.FOE_MODELS:
		var path: String = String(Figures3D.FOE_MODELS[fac])
		check(ResourceLoader.exists(path), "foe figure for %s is on disk (%s)" % [fac, path])

# A twelfth class shipping with no figure is the case this catches: the build
# runs, the fight plays, and that hero is a disc on a board of models.
func test_every_class_has_a_figure() -> void:
	for c in Catalog.all("classes.json"):
		var cid := String(c.get("id", ""))
		check(Figures3D.HERO_MODELS.has(cid), "class %s has a figure" % cid)

func test_factions_are_real(bestiary: Array) -> void:
	var live := {}
	for m in bestiary:
		live[String(m.get("faction", ""))] = true
	for fac in Figures3D.FOE_MODELS:
		check(live.has(String(fac)),
			"FOE_MODELS key %s is a faction the bestiary actually has" % fac)

# The convention is the whole of the by-id lookup: tools/import_beasts.py names
# its output after the bestiary id, and figures3d.gd asks for that file. A file
# whose name is not an id is a model nothing will ever draw.
func test_files_answer_to_a_bestiary_id(bestiary: Array) -> void:
	var ids := {}
	for m in bestiary:
		ids[String(m.get("id", ""))] = true
	var dir := DirAccess.open(Figures3D.BEAST_DIR.get_base_dir())
	check(dir != null, "the model directory is there")
	if dir == null:
		return
	var found := 0
	for f in dir.get_files():
		# .import is Godot's sidecar; the editor also writes .glb.import beside
		# each one, and an extracted albedo .jpg sits there too.
		if not f.ends_with(".glb"):
			continue
		found += 1
		check(ids.has(f.get_basename()),
			"%s is named for a bestiary id (nothing draws it otherwise)" % f)
	check(found >= MIN_BY_ID, "at least %d monsters have a model of their own (found %d)" % [MIN_BY_ID, found])

# Not an assertion, a readout — but the floor under it is an assertion, because
# a faction quietly losing its last model is exactly the regression this file
# exists to catch.
func report(bestiary: Array) -> void:
	var by_faction := {}
	for m in bestiary:
		var fac := String(m.get("faction", ""))
		if not by_faction.has(fac):
			by_faction[fac] = {"all": 0, "own": 0}
		by_faction[fac]["all"] += 1
		if ResourceLoader.exists(Figures3D.BEAST_DIR % String(m.get("id", ""))):
			by_faction[fac]["own"] += 1
	var covered := 0
	var bare: Array = []
	var lines: Array = []
	for fac in by_faction:
		var n: Dictionary = by_faction[fac]
		var stands_in: bool = Figures3D.FOE_MODELS.has(fac)
		if stands_in:
			covered += 1
		if not stands_in and int(n["own"]) == 0:
			bare.append("%s (%d)" % [fac, int(n["all"])])
		lines.append("    %-14s %3d in the bestiary, %3d with a model of their own%s"
			% [fac, int(n["all"]), int(n["own"]), ", faction rig" if stands_in else ""])
	lines.sort()
	print("  figure coverage:")
	for l in lines:
		print(l)
	bare.sort()
	print("  no figure at all (a fight drawn entirely in discs): %s" % ", ".join(bare))
	check(covered >= MIN_FACTIONS,
		"at least %d factions have a rig of their own (found %d)" % [MIN_FACTIONS, covered])
