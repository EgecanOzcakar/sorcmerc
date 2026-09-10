# Achievements model round-trip + the viewer standing up on its own.
#   godot --headless --path . -s tests/test_achievements.gd
extends SceneTree

const Ach = preload("res://core/achievements.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	_wipe()
	test_defs()
	test_unlock()
	test_round_trip()
	test_all()
	await test_viewer()
	_wipe()
	print("test_achievements: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()

func test_defs() -> void:
	check(Ach.DEFS.size() >= 10, "a real list of achievements")
	var ids := {}
	var ok := true
	for d in Ach.DEFS:
		if ids.has(d["id"]) or String(d["id"]).is_empty():
			ok = false
		ids[d["id"]] = true
		check(not String(d["title"]).is_empty(), "%s has a title" % d["id"])
		check(not String(d["desc"]).is_empty(), "%s has a description" % d["id"])
	check(ok, "every id is unique and non-empty")

func test_unlock() -> void:
	check(not Ach.is_unlocked("first_victory"), "starts locked")
	check(Ach.unlocked_at("first_victory") == "", "locked has no timestamp")
	check(Ach.unlock("first_victory"), "first unlock is new")
	var at := Ach.unlocked_at("first_victory")
	check(at != "", "unlocking stamps a time")
	check(not Ach.unlock("first_victory"), "second unlock reports not-new")
	check(Ach.unlocked_at("first_victory") == at, "timestamp does not move")
	check(not Ach.unlock("no_such_achievement"), "unknown id is a no-op")

func test_round_trip() -> void:
	Ach.unlock("level_5")
	var at := Ach.unlocked_at("level_5")
	var back = Ach.load_state()
	check(back.unlocked.has("first_victory"), "unlock survives a reload")
	check(back.unlocked.get("level_5") == at, "timestamp survives a reload")
	check(not back.unlocked.has("level_20"), "untouched ones stay locked")

	# Garbage in the file falls back to an empty, unlocked-nothing state.
	var f := FileAccess.open(Ach.PATH, FileAccess.WRITE)
	f.store_string('{"format":"nope","unlocked":{"level_20":"whenever"}}')
	f.close()
	check(Ach.load_state().unlocked.is_empty(), "unknown format falls back to defaults")
	# Unknown ids in a good file are dropped rather than shown.
	f = FileAccess.open(Ach.PATH, FileAccess.WRITE)
	f.store_string('{"format":"%s","unlocked":{"gone_from_the_list":"x","level_5":"%s"}}' % [Ach.FORMAT, at])
	f.close()
	var pruned = Ach.load_state()
	check(pruned.unlocked.size() == 1 and pruned.unlocked.has("level_5"), "retired ids are dropped on load")
	Ach._current = pruned

func test_all() -> void:
	var rows = Ach.all()
	check(rows.size() == Ach.DEFS.size(), "all() lists every achievement")
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = r
	check(by_id["level_5"]["unlocked"] and by_id["level_5"]["at"] != "", "all() shows unlocked state")
	check(not by_id["level_20"]["unlocked"] and by_id["level_20"]["at"] == "", "all() shows locked state")
	check(rows[0]["id"] == Ach.DEFS[0]["id"], "all() keeps display order")

func test_viewer() -> void:
	var v = load("res://scenes/achievements/achievements.tscn").instantiate()
	root.add_child(v)
	await process_frame
	check(v.get_child_count() > 0, "viewer builds its UI standalone")
	v.queue_free()
