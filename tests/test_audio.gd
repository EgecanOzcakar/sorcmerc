# T27 — the audio assets and the WAV reader that turns them into streams.
# Playback itself is unobservable headlessly; what can rot is the asset set (an id
# referenced with no file behind it) and the hand-rolled RIFF parse in core/audio.gd.
#
#   godot --headless --path . -s tests/test_audio.gd
extends SceneTree

const Audio = preload("res://core/audio.gd")
const Encounter = preload("res://core/encounter.gd")
const Combat = preload("res://core/combat.gd")

# Every id anything in the game asks for by name.
const SFX_IDS := ["hit", "crit", "kill", "cast", "heal", "level_up", "victory",
	"defeat", "click", "buy", "identify", "quest", "pickup", "rest"]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	var a = Audio.new()
	for id in SFX_IDS:
		var s = a._stream(Audio.SFX_DIR + id + ".wav", false)
		check(s != null and s.data.size() > 1000, "sfx %s parses" % id)
		if s != null:
			check(s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "sfx %s is one-shot" % id)
	for theme in Encounter.THEMES + ["settlement", "title", "tension"]:
		var s = a._stream(Audio.MUSIC_DIR + theme + ".wav", true)
		check(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "bed %s loops" % theme)
		if s != null:
			check(s.loop_end == s.data.size() / 2, "bed %s loops over its whole length" % theme)
	check(a._stream("res://assets/audio/sfx/nope.wav", false) == null, "missing file -> null")
	# Every trigger combat.gd maps to a sting must name a real asset.
	for trigger in Combat.BARK_SFX:
		var id: String = Combat.BARK_SFX[trigger]
		check(id == "" or id in SFX_IDS, "bark trigger %s maps to a real sfx" % trigger)
	# The statics are safe with no autoload running — this is what every headless
	# test run does when combat.gd fires a bark.
	Audio.play_sfx("hit")
	Audio.set_environment("frozen-cave")
	Audio.set_combat(true)
	Audio.set_sfx_volume(80.0)
	check(true, "static API no-ops without the autoload")
	a.free()
	print("test_audio: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
