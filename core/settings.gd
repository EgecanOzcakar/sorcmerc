# Player settings. One small JSON file at  user://settings.json  — same convention
# as core/character_save.gd: a documented format, unknown keys ignored, missing
# keys fall back to the defaults below.
#
# {
#   "format": "sorcmerc-settings",  // literal, checked on load
#   "version": 1,                   // bump only on an incompatible change
#   "anim_speed_multiplier": 0.55,  // 1.0 normal, <1 slower and weightier, >1 faster
#   "default_difficulty": "normal", // "easy" | "normal" | "hard"
#   "sfx_volume": 80,               // 0-100, the "SFX" audio bus (T27)
#   "music_volume": 80,             // 0-100, the "Music" audio bus (T27)
#   "reaction_prompts": true,       // stop and ask before a reaction spends a slot
#   "achievement_popups": true      // slide a card in when something is earned
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

# The pace the combat screen plays at: a multiplier on every tween and every
# pause between beats (scenes/main.gd's _anim). It used to be floored at 1.0,
# so the only thing this setting could do was make the fight go FASTER — there
# was no way to ask for the swing to land with any weight behind it. Below 1.0
# is the other half of the dial.
const ANIM_MIN := 0.4     # half speed and then some: every blow reads
const ANIM_MAX := 3.0     # as quick as a player can ask for without SORCMERC_FAST
# What the pace picker in scenes/settings/settings.gd offers, slowest first.
# FAST is the old "Reduced animations" toggle, kept as the last entry.
const ANIM_PACES := [
	{"id": "weighty", "label": "Weighty", "speed": 0.55,
		"note": "Blows land. Movement covers ground. The default pace."},
	{"id": "measured", "label": "Measured", "speed": 0.75,
		"note": "A little more room around every action."},
	{"id": "normal", "label": "Normal", "speed": 1.0, "note": "Quick swings, short pauses. Reads at a glance."},
	{"id": "brisk", "label": "Brisk", "speed": 1.6, "note": "Less waiting between turns."},
	{"id": "instant", "label": "Instant", "speed": FAST,
		"note": "No animation at all — the log is the fight."},
]

const DEFAULT_VOLUME := 80.0   # both audio sliders, 0-100

# Weighty by default: the slowest pace is the one a fight reads best at, and
# a player who wants it brisker will find the dial sooner than one who wants
# the swing they never saw.
const ANIM_DEFAULT := 0.55
var anim_speed_multiplier := ANIM_DEFAULT
var default_difficulty := "normal"
var sfx_volume := DEFAULT_VOLUME
var music_volume := DEFAULT_VOLUME
# Stop the fight and ask before one of your reactions spends a spell slot
# (Counterspell, Hellish Rebuke). The free ones — an opportunity attack,
# Uncanny Dodge — never ask: taking them is the right answer every time, and a
# question with one sensible answer is a key press, not a decision.
var reaction_prompts := true
# The top-right card an earned achievement slides in on
# (scenes/achievements/toast.gd). Off still earns and still records it — the
# viewer is the record — it just stops the game talking over itself mid-fight.
var achievement_popups := true
# How big the combat screen's chrome is — the bar, the initiative strip, the
# key chips, the header — as a multiplier. It used to ride the map zoom, so
# zooming in on a fight grew the buttons with it; the map's zoom is the map's
# now (#152), and this is the only thing that sizes the chrome.
const UI_SCALE_MIN := 0.7
const UI_SCALE_MAX := 1.4
var ui_scale := 1.0

# Which pace a stored multiplier reads as: the nearest one, so a hand-edited
# settings.json still selects something rather than nothing.
static func pace_for(speed: float) -> Dictionary:
	var best: Dictionary = ANIM_PACES[0]
	for p in ANIM_PACES:
		if absf(float(p["speed"]) - speed) < absf(float(best["speed"]) - speed):
			best = p
	return best

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
		# Clamped, not floored: below ANIM_MIN is a slideshow and above
		# ANIM_MAX is what FAST is for, but anything between is the player's
		# call. FAST itself passes through — it is a real stored value now
		# (the "Instant" pace), not just an env-var stand-in.
		var want := float(d.get("anim_speed_multiplier", ANIM_DEFAULT))
		s.anim_speed_multiplier = want if want >= FAST else clampf(want, ANIM_MIN, ANIM_MAX)
		var diff := String(d.get("default_difficulty", "normal"))
		s.default_difficulty = diff if diff in DIFFICULTIES else "normal"
		s.sfx_volume = clampf(float(d.get("sfx_volume", DEFAULT_VOLUME)), 0.0, 100.0)
		s.music_volume = clampf(float(d.get("music_volume", DEFAULT_VOLUME)), 0.0, 100.0)
		s.reaction_prompts = bool(d.get("reaction_prompts", true))
		s.achievement_popups = bool(d.get("achievement_popups", true))
		s.ui_scale = clampf(float(d.get("ui_scale", 1.0)), UI_SCALE_MIN, UI_SCALE_MAX)
	return s

static func to_dict(s) -> Dictionary:
	return {"format": FORMAT, "version": VERSION,
		"anim_speed_multiplier": s.anim_speed_multiplier,
		"default_difficulty": s.default_difficulty,
		"sfx_volume": s.sfx_volume,
		"music_volume": s.music_volume,
		"reaction_prompts": s.reaction_prompts,
		"achievement_popups": s.achievement_popups,
		"ui_scale": s.ui_scale}

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

# Animation speed the game should actually run at. SORCMERC_FAST wins outright
# when it is set — the headless suite relies on that, and a test run must never
# be slowed down by whatever settings.json happens to be on the machine. With
# the env var unset the setting is simply obeyed, in both directions; the old
# maxf() against 1.0 is what made "slower" unreachable.
static func anim() -> float:
	if OS.get_environment("SORCMERC_FAST") != "":
		return FAST
	return current().anim_speed_multiplier

# Whether the combat screen installs a reaction decider at all. SORCMERC_FAST
# wins outright, for the same reason anim() lets it: a headless run has nobody
# to answer the question, and a prompt nobody answers is a hang, not a pause.
static func chrome_scale() -> float:
	return current().ui_scale

static func reaction_prompts_on() -> bool:
	if OS.get_environment("SORCMERC_FAST") != "":
		return false
	return current().reaction_prompts
