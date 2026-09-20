# Every .gd in the project parses. Not a test of behaviour — a test that the
# code is loadable at all, which no other test can be: a test only compiles the
# scripts it happens to preload, so a parse error in a file nothing imports (or
# in a screen no test drives) survives a green suite and is found by running the
# game.
#
#   godot --headless --path . -s tests/check_scripts.gd
#
# One process, one load() per file: loading a script parses and compiles it
# (and everything it preloads) without running anything. The signal is
# `can_instantiate()`, NOT a null return — a script that fails to parse still
# comes back as a GDScript object, it just cannot be instantiated, so checking
# for null quietly passes everything. (Nothing in this project is @abstract or
# @tool, which are the two things that would be legitimately uninstantiable.)
#
# Run it FIRST: it is seconds, and a file that does not parse makes every
# failure after it a mystery.
#
# Assets have to be imported before this means anything: scripts that preload a
# texture cannot compile without .godot/imported/, so a fresh checkout needs
# `godot --headless --path . --import` first (tools/run_tests.sh does it).
extends SceneTree

const ROOTS := ["res://core", "res://scenes", "res://tests"]
# This file is the one script that must not be loaded by the check: loading it
# re-enters nothing, but listing it in its own report is noise.
const SKIP := ["res://tests/check_scripts.gd"]

var _checked := 0
var _bad: Array[String] = []

func _init() -> void:
	for root in ROOTS:
		_walk(root)
	for path in _bad:
		printerr("  BROKEN: ", path)
	print("check_scripts: %d scripts, %d broken" % [_checked, _bad.size()])
	quit(1 if not _bad.is_empty() else 0)

func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(path)
		elif name.ends_with(".gd") and not SKIP.has(path):
			_check(path)
		name = d.get_next()
	d.list_dir_end()

func _check(path: String) -> void:
	_checked += 1
	# CACHE_MODE_IGNORE so this is a real parse every time rather than whatever
	# an earlier preload in this same process already put in the cache.
	var script = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if script == null or not script.can_instantiate():
		_bad.append(path)
