# The Field Manual is generated off the data files; these keep it honest.
#   godot --headless --path . -s tests/test_manual.gd
extends SceneTree

const Manual = preload("res://core/manual.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Adapter = preload("res://core/adapter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var pages: Array = Manual.pages()
	var ids: Array = pages.map(func(p): return p["id"])
	# every class in the data has a page, with its blurb and its features
	for c in Catalog.all("classes.json"):
		var id := "class-" + String(c["id"])
		check(id in ids, "%s has a page" % id)
		var p := Manual.page(id)
		check(Manual.CLASS_BLURB.has(c["id"]), "%s has a blurb" % c["id"])
		check(p["body"].contains("Features by level") and p["body"].contains("1 — "), "%s lists level-1 features" % id)
	# every condition in the data is on the conditions page
	var cond_body: String = Manual.page("conditions")["body"]
	for id in Catalog.all("effects/conditions.json").keys():
		if not String(id).begins_with("_"):
			check(cond_body.contains("[b]%s[/b]" % String(id).capitalize()), "condition %s is documented" % id)
	# every mastery in the weapon data is documented
	var mast_body: String = Manual.page("mastery")["body"]
	for w in Catalog.all("weapons.json"):
		if w.get("mastery") != null:
			check(mast_body.contains("[b]%s[/b]" % String(w["mastery"]).capitalize()), "mastery %s is documented" % w["mastery"])
	# the numbers on the range page are the engine's, not last month's
	var range_body: String = Manual.page("range")["body"]
	check(range_body.contains("%d ft to a hex" % Adapter.FT_PER_HEX), "range page quotes FT_PER_HEX")
	check(range_body.contains("capped at %d hexes" % Adapter.RANGE_CAP), "range page quotes RANGE_CAP")
	# search: every word, case-insensitive, tags count, nonsense finds nothing
	check(Manual.search("PRONE").any(func(p): return p["id"] == "conditions"), "search is case-insensitive")
	check(Manual.search("sneak attack").any(func(p): return p["id"] == "class-rogue"), "multi-word search hits the rogue")
	check(Manual.search("oa").any(func(p): return p["id"] == "moving"), "tags are searchable (oa)")
	check(Manual.search("").size() == pages.size(), "empty search is every page")
	check(Manual.search("xyzzy plugh").is_empty(), "nonsense finds nothing")
	var snip := Manual.snippet(Manual.page("dying"), "natural 20")
	check(snip.to_lower().contains("natural 20"), "snippet contains the match (%s)" % snip)
	for p in pages:
		check(p["body"].length() > 200, "%s has a real body" % p["id"])
		check(not p["tags"].is_empty(), "%s has tags" % p["id"])
	print("test_manual: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
