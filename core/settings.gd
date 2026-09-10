# Player settings. One small JSON file at  user://settings.json  — same convention
# as core/character_save.gd: a documented format, unknown keys ignored, missing
# keys fall back to the defaults below.
#
# {
#   "format": "sorcmerc-settings",  // literal, checked on load
#   "version": 1,                   // bump only on an incompatible change
#   "anim_speed_multiplier": 1.0,   // 1.0 normal, higher = faster tweens/pauses
#   "default_difficulty": "normal"  // "easy" | "normal" | "hard"
# }
#
# Read it with Settings.current() — loaded once, cached; save() writes the cache
# back. anim() folds in the SORCMERC_FAST env var, which stays authoritative for
# headless test runs.
extends RefCounted

const PATH := "user://settings.json"
const FORMAT := "sorcmerc-settings"
const VERSION := 1
const DIFFICULTIES := ["easy", "normal", "hard"]
const FAST := 999.0   # what SORCMERC_FAST has always meant: no waiting

var anim_speed_multiplier := 1.0
var default_difficulty := "normal"

static var _current = null

# The shared instance, loaded from disk on first use.
static func current():
	if _current == null:
		_current = load_settings()
	return _current

static func load_settings():
	var s = new()
	var txt := FileAccess.get_file_as_string(PATH)
	var d = JSON.parse_string(txt) if not txt.is_empty() else null
	if d is Dictionary and d.get("format") == FORMAT:
		s.anim_speed_multiplier = maxf(1.0, float(d.get("anim_speed_multiplier", 1.0)))
		var diff := String(d.get("default_difficulty", "normal"))
		s.default_difficulty = diff if diff in DIFFICULTIES else "normal"
	return s

static func to_dict(s) -> Dictionary:
	return {"format": FORMAT, "version": VERSION,
		"anim_speed_multiplier": s.anim_speed_multiplier,
		"default_difficulty": s.default_difficulty}

# Returns the path written, or "" on failure.
static func save_settings(s = null) -> String:
	if s == null:
		s = current()
	_current = s
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % PATH)
		return ""
	f.store_string(JSON.stringify(to_dict(s), "  "))
	f.close()
	return PATH

# Animation speed the game should actually run at: the setting, or SORCMERC_FAST
# when the env var is set (tests rely on it, and it may only ever speed things up).
static func anim() -> float:
	var env := FAST if OS.get_environment("SORCMERC_FAST") != "" else 1.0
	return maxf(env, current().anim_speed_multiplier)
