# T27 — the one place that makes noise. Registered as the `Audio` autoload, because
# core/*.gd is pure logic the headless test suite exercises and cannot own scene-tree
# nodes. Callers use the STATIC API off a preload:
#
#   const Sound = preload("res://core/audio.gd")
#   Sound.play_sfx("hit")                  one-shot, ids = assets/audio/sfx/*.wav
#   Sound.play_bark("hero1")               T31 voice stinger, assets/audio/barks/*.wav
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
# Assets are the WAVs tools/gen_audio.py writes. They are read with FileAccess and
# turned into AudioStreamWAV by hand rather than load()ed, so no editor import
# round-trip (.import files) is needed to run from source.
#
# Sample rate and channel count come out of each file's `fmt ` chunk rather than
# being assumed, so a stereo bed and a mono one-shot at a different rate can sit
# in the same directory and both play at the right speed. gen_audio.py's --rate
# therefore needs no change here.
# ponytail: swap to plain load() if these ever become real, editor-imported audio.
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const BARK_DIR := "res://assets/audio/barks/"
const MUSIC_DIR := "res://assets/audio/music/"
const FALLBACK_MIX_RATE := 22050   # only if a file's fmt chunk is unreadable
const FADE := 1.0            # seconds, bed crossfade and tension fade
const BED_DB := -12.0        # the bed sits under everything
const TENSION_DB := -9.0
const QUIET_DB := -60.0      # "off" without stopping the loop
const VOICES := 8            # concurrent one-shots; oldest gets reused

static var _i = null         # the autoload, once it exists

var _streams := {}           # path -> AudioStreamWAV (or null when missing)
var _voices: Array = []
var _next_voice := 0
var _beds: Array = []        # two players, ping-ponged for the crossfade
var _bed := 0
var _tension: AudioStreamPlayer = null
var _theme := ""

# --- static API (safe with no autoload: every call is a no-op) --------------

static func play_sfx(id: String) -> void:
	if _i != null:
		_i._play_one_shot(SFX_DIR + id + ".wav")

# T31: the gibberish stinger paired with a text bark. Same voices/bus as the SFX.
static func play_bark(id: String) -> void:
	if _i != null:
		_i._play_one_shot(BARK_DIR + id + ".wav")

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
	_i = self

func _play_one_shot(path: String) -> void:
	var stream = _stream(path, false)
	if stream == null:
		return
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.play()

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

# Read one of our own WAVs (16-bit PCM, mono or stereo) into an AudioStreamWAV,
# cached. Rate and channel count come from the file's `fmt ` chunk.
# Returns null if the file is missing or unreadable.
func _stream(path: String, looped: bool):
	if _streams.has(path):
		return _streams[path]
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		push_warning("audio: cannot read %s" % path)
		_streams[path] = null
		return null
	var at := 12   # past "RIFF" + size + "WAVE"
	var data := PackedByteArray()
	var channels := 1
	var rate := FALLBACK_MIX_RATE
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		if id == "fmt " and at + 16 <= bytes.size():
			channels = maxi(1, bytes.decode_u16(at + 10))
			rate = maxi(1, bytes.decode_u32(at + 12))
		elif id == "data":
			data = bytes.slice(at + 8, mini(at + 8 + size, bytes.size()))
			break
		at += 8 + size + (size & 1)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = channels >= 2
	s.data = data
	if looped:
		# loop_end is in FRAMES, so a stereo file is data.size() / 4, not / 2.
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size() / (2 * channels)
	_streams[path] = s
	return s
