# Where everything that persists goes. One answer for the world/campaign
# autosaves, the character files, achievements and progression, so a test can
# never write over a real save.
#
#   $SORCMERC_SAVE_DIR set        -> that directory (the O17 convention: the
#                                    drivers set one per process)
#   a `godot -s tests/...` run    -> user://test/auto-<pid>-<rand>, without being asked —
#                                    test_world_defeat used to finish a fight and
#                                    autosave over the player's world.json, and
#                                    test_creator saved Vera over the player's Vera
#   otherwise                     -> user://
extends RefCounted

static var _root := ""

static func root() -> String:
	if _root == "":
		var env := OS.get_environment("SORCMERC_SAVE_DIR")
		if env != "":
			_root = env.trim_suffix("/")
		elif _under_test():
			_root = "user://test/auto-%d-%d" % [OS.get_process_id(), randi()]   # flatpak pids are tiny and reused
		else:
			_root = "user:/"   # so root() + "/x" is user://x
	return _root

static func _under_test() -> bool:
	for a in OS.get_cmdline_args():
		if String(a).begins_with("tests/") or String(a).contains("/tests/"):
			return true
	return false

static func path(rel: String) -> String:
	return root() + "/" + rel
