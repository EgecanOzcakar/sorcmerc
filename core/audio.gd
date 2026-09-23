# T27 — the one place that makes noise. Registered as the `Audio` autoload, because
# core/*.gd is pure logic the headless test suite exercises and cannot own scene-tree
# nodes. Callers use the STATIC API off a preload:
#
#   const Sound = preload("res://core/audio.gd")
#   Sound.play_sfx("hit")                  one-shot, ids = assets/audio/sfx/*.wav
#   Sound.play_bark("hero1")               T31 voice stinger, assets/audio/barks/*.wav
#   Sound.play_sting("music_discovery")    a short musical phrase over the bed,
#                                          assets/audio/sfx/music_*.wav on the Music bus
#   Sound.set_environment("frozen-cave")   crossfade the ambient bed (theme ids =
#                                          Encounter.THEMES, plus settlement/title)
#   Sound.set_combat(true)                 fade the shared tension layer in over it
#   Sound.set_sfx_volume(80) / set_music_volume(80)    0-100, straight to the bus
#
# Static, not `Audio.play_sfx(...)` on the autoload global, because a script run as
# the main loop (`godot -s tests/test_*.gd`, every test and every drive_*.gd) never
# instantiates autoloads — the global identifier does not exist there and referring
# to it fails compilation of the whole dependency chain. The statics no-op until the
# autoload registers itself in _ready, which is exactly the headless behaviour we want.
#
# Assets are WAVs read straight off disk with AudioStreamWAV.load_from_file()
# rather than load()ed, so no editor import round-trip (.import files) is needed
# to run from source. That reader takes 8/16-bit PCM and 32-bit float, mono or
# stereo, at any rate (it reads the `fmt ` chunk), and hands back 16-bit PCM.
# It refuses WAVE_FORMAT_EXTENSIBLE, which is what ffmpeg writes for 24-bit:
# export 32-bit float or 16-bit instead.
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const BARK_DIR := "res://assets/audio/barks/"
const MUSIC_DIR := "res://assets/audio/music/"
const FADE := 1.0            # seconds, bed crossfade and tension fade
const BED_DB := -12.0        # the bed sits under everything
const TENSION_DB := -9.0
const STING_DB := -6.0       # a phrase over the bed: above it, under the sfx
const QUIET_DB := -60.0      # "off" without stopping the loop
const VOICES := 8            # concurrent one-shots; oldest gets reused
# The same sting starting twice within this window is one event heard twice, not
# two events, so the second is dropped. An area spell resolves a save PER TARGET
# and a condition PER TARGET in a single frame, so a fireball catching five
# bodies would otherwise stack five copies of one sample: phasey, five times as
# loud, and it drowns the cast it is supposed to be answering. Generous enough to
# catch a whole frame's worth of that (~3 frames at 60 fps) and far shorter than
# the gap between two things a player would ever read as separate — a second
# attack is turns or animation away, never 50 ms.
const RETRIGGER_MS := 50

static var _i = null         # the autoload, once it exists

var _streams := {}           # path -> AudioStreamWAV (or null when missing)
var _voices: Array = []
var _next_voice := 0
var _last_start := {}        # path -> Time.get_ticks_msec() of its last start
var _beds: Array = []        # two players, ping-ponged for the crossfade
var _bed := 0
var _tension: AudioStreamPlayer = null
var _sting: AudioStreamPlayer = null
var _theme := ""

# --- static API (safe with no autoload: every call is a no-op) --------------

# A sting with extra takes beside it (hit_sword.wav, hit_sword_2.wav, _3 ...)
# plays one of them at random, and every play drifts a few percent in pitch:
# the same file on every swing is what makes even a good recording wear thin.
const PITCH_DRIFT := 0.06
static func play_sfx(id: String) -> void:
	if _i != null:
		_i._play_one_shot(_i._take_of(SFX_DIR, id), randf_range(1.0 - PITCH_DRIFT, 1.0 + PITCH_DRIFT))

# T31: the gibberish stinger paired with a text bark. Same voices/bus as the SFX.
static func play_bark(id: String) -> void:
	if _i != null:
		_i._play_one_shot(BARK_DIR + id + ".wav")

# A musical sting — a landmark answered, a raid landing — from the same
# directory as the sfx but NOT through play_sfx: it rides the Music bus (the
# music slider is what should govern a phrase of music), takes no pitch drift
# (a few percent is right for a sword and puts a phrase out of key with the
# bed), and has one player of its own, because two phrases at once is noise
# and the newer one is the event that just happened.
static func play_sting(id: String) -> void:
	if _i != null:
		_i._play_sting(SFX_DIR + id + ".wav")

static func set_environment(theme: String) -> void:
	if _i != null:
		_i._set_environment(theme)

static func set_combat(active: bool) -> void:
	if _i != null:
		_i._set_combat(active)

static func set_sfx_volume(v: float) -> void:
	_set_bus("SFX", v)

static func set_music_volume(v: float) -> void:
	_set_bus("Music", v)

# --- the autoload ----------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	var s = load("res://core/settings.gd").current()
	set_sfx_volume(s.sfx_volume)
	set_music_volume(s.music_volume)
	if DisplayServer.get_name() == "headless":
		return               # no players, nothing to play, nothing to hang on
	for i in VOICES:
		_voices.append(_player("SFX", 0.0))
	for i in 2:
		_beds.append(_player("Music", QUIET_DB))
	_tension = _player("Music", QUIET_DB)
	_sting = _player("Music", STING_DB)
	_i = self

func _play_one_shot(path: String, pitch := 1.0) -> void:
	var stream = _stream(path, false)
	if stream == null:
		return
	if not _should_play(_take_key(path), Time.get_ticks_msec()):
		return
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.play()

func _play_sting(path: String) -> void:
	var stream = _stream(path, false)
	if stream == null:
		return
	_sting.stream = stream
	_sting.play()

# The takes of `id` on disk, counted once: id.wav, id_2.wav, id_3.wav ... until
# one is missing. Picks one at random; the plain file when there is only one.
var _takes: Dictionary = {}   # dir+id -> count
func _take_of(dir: String, id: String) -> String:
	var key := dir + id
	if not _takes.has(key):
		var n := 1
		while FileAccess.file_exists("%s%s_%d.wav" % [dir, id, n + 1]):
			n += 1
		_takes[key] = n
	var n: int = _takes[key]
	if n <= 1:
		return dir + id + ".wav"
	var k := randi_range(1, n)
	return dir + id + ".wav" if k == 1 else "%s%s_%d.wav" % [dir, id, k]

# Retrigger limiting is per sting, not per take: two takes of hit_sword in
# the same frame is still the same sound twice.
static func _take_key(path: String) -> String:
	var base := path.get_basename()
	var i := base.rfind("_")
	if i > 0 and base.substr(i + 1).is_valid_int():
		return base.substr(0, i) + ".wav"
	return path

# The RETRIGGER_MS rule, and the only place that records a start. Split out of
# _play_one_shot so tests/test_audio.gd can exercise it with synthetic timestamps:
# headless never builds a voice pool (_ready returns before it does), so the
# caller above cannot run at all under the test suite.
func _should_play(path: String, now: int) -> bool:
	if now - int(_last_start.get(path, -RETRIGGER_MS - 1)) < RETRIGGER_MS:
		return false
	_last_start[path] = now
	return true

# Crossfade to `theme`'s ambient bed. An unknown theme is ignored (the current bed
# keeps playing) rather than cutting to silence.
func _set_environment(theme: String) -> void:
	if theme == _theme:
		return
	var stream = _stream(MUSIC_DIR + theme + ".wav", true)
	if stream == null:
		return
	_theme = theme
	var old: AudioStreamPlayer = _beds[_bed]
	_bed = 1 - _bed
	var cur: AudioStreamPlayer = _beds[_bed]
	cur.stream = stream
	cur.volume_db = QUIET_DB
	cur.play()
	_fade(cur, BED_DB)
	_fade(old, QUIET_DB)

func _set_combat(active: bool) -> void:
	if active and not _tension.playing:
		var stream = _stream(MUSIC_DIR + "tension.wav", true)
		if stream == null:
			return
		_tension.stream = stream
		_tension.volume_db = QUIET_DB
		_tension.play()
	_fade(_tension, TENSION_DB if active else QUIET_DB)

# --- plumbing --------------------------------------------------------------

func _player(bus: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = db
	add_child(p)
	return p

func _fade(p: AudioStreamPlayer, db: float) -> void:
	var t := create_tween()
	t.tween_property(p, "volume_db", db, FADE)
	if db <= QUIET_DB:
		t.tween_callback(p.stop)

static func _ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, bus)
	AudioServer.set_bus_send(AudioServer.get_bus_count() - 1, "Master")

# 0 = muted, 100 = unity. linear_to_db keeps the slider's low end usable.
static func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, v <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(v, 1.0, 100.0) / 100.0))

# Read a WAV into an AudioStreamWAV, cached. Returns null if the file is missing
# or unreadable. Whatever the file's depth, the stream comes back 16-bit PCM
# (the engine's own conversion, no compression with default options).
func _stream(path: String, looped: bool):
	if _streams.has(path):
		return _streams[path]
	var s = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	if s == null:
		push_warning("audio: cannot read %s" % path)
	elif looped:
		# loop_end is in FRAMES, so a stereo file is data.size() / 4, not / 2.
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / (4 if s.stereo else 2)
	_streams[path] = s
	return s
