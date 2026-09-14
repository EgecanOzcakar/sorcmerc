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
	# D6: the overworld feeds a band id straight to set_environment(), so every
	# band core/regions.gd declares needs a bed of that exact name. Derived from
	# BANDS rather than listed, or a fifth country would ship silent.
	var Regions = load("res://core/regions.gd")
	var region_beds: Array = []
	for b in Regions.BANDS:
		region_beds.append(String(b["id"]))
	for theme in Encounter.THEMES + ["settlement", "title", "tension"] + region_beds:
		var s = a._stream(Audio.MUSIC_DIR + theme + ".wav", true)
		check(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "bed %s loops" % theme)
		if s != null:
			# loop_end is in frames, so the divisor tracks the channel count.
			var frames: int = s.data.size() / (4 if s.stereo else 2)
			check(s.loop_end == frames, "bed %s loops over its whole length" % theme)
			check(s.mix_rate >= 22050, "bed %s kept its sample rate" % theme)
	check(a._stream("res://assets/audio/sfx/nope.wav", false) == null, "missing file -> null")
	# T31: every voice barks.gd can name has all its variants on disk.
	var Barks = load("res://core/barks.gd")
	var voices := ["hero", "gruff"]
	for f in Barks.VOICE:
		if not String(Barks.VOICE[f]) in voices:
			voices.append(String(Barks.VOICE[f]))
	check(Barks.voice("party", "") == "hero" and Barks.voice("foe", "nope") == "gruff",
		"voice() falls back sanely")
	for v in voices:
		for n in range(1, Barks.VARIANTS + 1):
			var s = a._stream(Audio.BARK_DIR + "%s%d.wav" % [v, n], false)
			check(s != null and s.data.size() > 1000, "bark %s%d parses" % [v, n])
	# Every trigger combat.gd maps to a sting must name a real asset.
	for trigger in Combat.BARK_SFX:
		var id: String = Combat.BARK_SFX[trigger]
		check(id == "" or id in SFX_IDS, "bark trigger %s maps to a real sfx" % trigger)
	# The statics are safe with no autoload running — this is what every headless
	# test run does when combat.gd fires a bark.
	Audio.play_sfx("hit")
	Audio.play_bark("hero1")
	Audio.set_environment("frozen-cave")
	Audio.set_combat(true)
	Audio.set_sfx_volume(80.0)
	check(true, "static API no-ops without the autoload")
	a.free()
	print("test_audio: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
