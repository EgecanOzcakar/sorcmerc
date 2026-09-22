# Headless: the bust cache (#165) answers null without a renderer and never
# throws, keys as path@px, and the model lookup it shares with the board
# resolves a hero sheet, a modeled beast, a faction rig, and nothing.
#   godot --headless --path . -s tests/test_portraits.gd
extends SceneTree

const Portraits = preload("res://scenes/portraits.gd")
const Figures3D = preload("res://scenes/figures3d.gd")
const Catalog = preload("res://core/rules/catalog.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

class FakeSheet:
	var class_levels := {"rogue": 2, "wizard": 5}

func _init() -> void:
	check(Portraits.bust(Figures3D.HERO_MODELS["wizard"]) == null, "headless: bust() is null")
	check(Portraits.bust("") == null, "empty path: bust() is null")
	Portraits.warm(Figures3D.HERO_MODELS.values(), 28)
	check(Portraits._cache.is_empty(), "headless: warm() starts no renders")
	check(Portraits.key("res://a.glb", 48) == "res://a.glb@48", "cache key is path@px")

	check(Figures3D.model_path_for(FakeSheet.new(), "") == Figures3D.HERO_MODELS["wizard"],
		"hero: the class carrying the most levels")
	var beast := ""
	for id in Catalog.index("bestiary.json").keys():
		if ResourceLoader.exists(Figures3D.BEAST_DIR % id):
			beast = id; break
	check(beast != "" and Figures3D.model_path_for(null, beast) == Figures3D.BEAST_DIR % beast,
		"bestiary id with a model: BEAST_DIR (%s)" % beast)
	var faction_only := ""
	for id in Catalog.index("bestiary.json").keys():
		var f := String(Catalog.monster(id).get("faction", ""))
		if Figures3D.FOE_MODELS.has(f) and not ResourceLoader.exists(Figures3D.BEAST_DIR % id):
			faction_only = id; break
	check(faction_only != "" and Figures3D.model_path_for(null, faction_only)
		== Figures3D.FOE_MODELS[Catalog.monster(faction_only)["faction"]],
		"faction without its own file: FOE_MODELS (%s)" % faction_only)
	check(Figures3D.model_path_for(null, "") == "", "no sheet, no id: empty")

	print("%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
