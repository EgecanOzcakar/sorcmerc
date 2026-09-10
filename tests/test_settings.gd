# Settings model round-trip + the overlay standing up on its own.
#   godot --headless --path . -s tests/test_settings.gd
extends SceneTree

const Settings = preload("res://core/settings.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_defaults()
	test_round_trip()
	test_anim()
	await test_overlay()
	print("test_settings: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func test_defaults() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	var s = Settings.load_settings()
	check(s.anim_speed_multiplier == 1.0, "default anim speed is normal")
	check(s.default_difficulty == "normal", "default difficulty is normal")

func test_round_trip() -> void:
	var s = Settings.load_settings()
	s.anim_speed_multiplier = Settings.FAST
	s.default_difficulty = "hard"
	check(Settings.save_settings(s) != "", "saved")
	var back = Settings.load_settings()
	check(back.anim_speed_multiplier == Settings.FAST, "anim speed survives the round trip")
	check(back.default_difficulty == "hard", "difficulty survives the round trip")
	check(Settings.current().default_difficulty == "hard", "save updates the cached instance")

	# Garbage in the file falls back to sane defaults instead of exploding.
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string('{"format":"nope","default_difficulty":"impossible"}')
	f.close()
	var junk = Settings.load_settings()
	check(junk.default_difficulty == "normal", "unknown format falls back to defaults")

func test_anim() -> void:
	var s = Settings.load_settings()
	s.anim_speed_multiplier = 1.0
	Settings.save_settings(s)
	# SORCMERC_FAST stays authoritative for headless runs; the test suite sets it.
	var fast_env := OS.get_environment("SORCMERC_FAST") != ""
	check(Settings.anim() == (Settings.FAST if fast_env else 1.0), "anim() honours SORCMERC_FAST")
	s.anim_speed_multiplier = Settings.FAST
	Settings.save_settings(s)
	check(Settings.anim() == Settings.FAST, "the setting speeds things up on its own")
	s.anim_speed_multiplier = 1.0
	Settings.save_settings(s)

func test_overlay() -> void:
	var host := Control.new()
	root.add_child(host)
	var o = load("res://scenes/settings/settings.gd").toggle(host)
	check(o != null, "overlay opens with no game underneath it")
	await process_frame
	check(host.get_node_or_null("SettingsOverlay") != null, "overlay is a child of the host")
	check(load("res://scenes/settings/settings.gd").toggle(host) == null, "second toggle closes it")
	await process_frame
	check(host.get_node_or_null("SettingsOverlay") == null, "overlay is gone")
	host.queue_free()
