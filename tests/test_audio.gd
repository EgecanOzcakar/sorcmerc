# T27 — the audio assets and the WAV reader that turns them into streams.
# Playback itself is unobservable headlessly; what can rot is the asset set (an id
# referenced with no file behind it) and the hand-rolled RIFF parse in core/audio.gd.
#
#   godot --headless --path . -s tests/test_audio.gd
extends SceneTree

const Audio = preload("res://core/audio.gd")
const Encounter = preload("res://core/encounter.gd")
const Combat = preload("res://core/combat.gd")
const WeaponSfx = preload("res://core/weapon_sfx.gd")

# Every id anything in the game asks for by name. T9z: plus every id
# core/weapon_sfx.gd can hand out — those lists are the contract, so a class
# added there without a WAV behind it fails here, not silently in a fight.
const BASE_SFX_IDS := ["hit", "crit", "kill", "cast", "heal", "level_up", "victory",
	"defeat", "click", "buy", "identify", "quest", "pickup", "rest",
	# The moments that used to fire silently: a save either way, a barrel going
	# up, a status landing, exhaustion, and the world between fights. `down` is
	# here rather than aliased to `kill` now that a hero dropping and a foe dying
	# are two different sounds. The two miss ids come in off WeaponSfx.MISS_IDS
	# below, the same way the weapon and school ids do.
	"save_made", "save_failed", "down", "burst", "condition", "collapse",
	"travel", "settlement", "shop", "quest_complete"]

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
	var sfx_ids: Array = BASE_SFX_IDS + WeaponSfx.ATTACK_IDS + WeaponSfx.SPELL_IDS + WeaponSfx.MISS_IDS
	for id in sfx_ids:
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
	# The same sting twice in one frame is one event heard twice. An area spell
	# resolves a save and a condition PER TARGET, so this is what stops a fireball
	# catching five bodies from stacking five copies of one sample.
	var hit_path: String = Audio.SFX_DIR + "hit.wav"
	var miss_path: String = Audio.SFX_DIR + "miss.wav"
	check(a._should_play(hit_path, 1000), "the first start plays")
	check(not a._should_play(hit_path, 1000), "the same sting on the same frame is dropped")
	check(not a._should_play(hit_path, 1000 + Audio.RETRIGGER_MS - 1), "still inside the window")
	check(a._should_play(hit_path, 1000 + Audio.RETRIGGER_MS), "past the window it plays again")
	# Per sound, not global: a miss and a hit landing together are two events.
	check(a._should_play(miss_path, 1000 + Audio.RETRIGGER_MS), "a different sting is unaffected")
	# The very first play of a sound must not be swallowed by the zero-clock case.
	check(a._should_play(Audio.SFX_DIR + "burst.wav", 0), "a start at tick 0 still plays")
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
		check(id == "" or id in sfx_ids, "bark trigger %s maps to a real sfx" % trigger)
	# The statics are safe with no autoload running — this is what every headless
	# test run does when combat.gd fires a bark.
	Audio.play_sfx("hit")
	Audio.play_bark("hero1")
	Audio.set_environment("frozen-cave")
	Audio.set_combat(true)
	Audio.set_sfx_volume(80.0)
	check(true, "static API no-ops without the autoload")
	a.free()

	# --- T9z: the weapon/school classifier -----------------------------------
	# Heroes carry the weapon on attacks[0]; monsters carry only a damage type.
	# Real builds (Presets) and a real bestiary spawn, not hand-made dicts, so
	# a change to how adapter.gd shapes an attack entry shows up here.
	var Adapter = load("res://core/adapter.gd")
	var Presets = load("res://core/presets.gd")
	var vera = Adapter.to_combatant(Presets.vera(), "party", Vector2i.ZERO)   # longsword
	check(WeaponSfx.for_attack(vera) == "hit_sword", "a longsword hit is hit_sword (got %s)" % WeaponSfx.for_attack(vera))
	var pike = Adapter.to_combatant(Presets.pike(), "party", Vector2i.ZERO)   # shortbow
	check(WeaponSfx.for_attack(pike) == "hit_bow", "a shortbow hit is hit_bow (got %s)" % WeaponSfx.for_attack(pike))
	var ilsa = Adapter.to_combatant(Presets.ilsa(), "party", Vector2i.ZERO)   # mace
	check(WeaponSfx.for_attack(ilsa) == "hit_blunt", "a mace hit is hit_blunt (got %s)" % WeaponSfx.for_attack(ilsa))
	# Swapping Vera's main hand to a handaxe (an axe, slashing) must chop, not ring.
	if Adapter.set_main_attack(vera, "handaxe"):
		check(WeaponSfx.for_attack(vera) == "hit_axe", "a handaxe hit is hit_axe")
	# A monster: bestiary damage type survives Adapter.from_monster's copy
	# (the two fields are declared on Combatant for exactly this).
	var Catalog = load("res://core/rules/catalog.gd")
	var goblin = Adapter.from_monster(Catalog.monster("goblin"), "foe", Vector2i.ZERO)
	check(goblin.damage_type != "", "a spawned monster keeps its bestiary damage_type")
	var g_sfx: String = WeaponSfx.for_attack(goblin)
	check(g_sfx in WeaponSfx.ATTACK_IDS or g_sfx == "hit", "a monster hit resolves to a real class")
	var bite = Adapter.from_monster({"id": "x", "cname": "x", "max_hp": 5, "damage_type": "piercing",
		"ranged": false}, "foe", Vector2i.ZERO)
	check(WeaponSfx.for_attack(bite) == "hit_bite", "a piercing natural attack is hit_bite")
	check(WeaponSfx.for_attack(null) == "hit", "no attacker at all -> the generic hit")
	# Misses split melee/ranged only, off the same attacks[0] the hits read.
	check(WeaponSfx.for_miss(vera) == "miss", "a melee miss is the whoosh")
	check(WeaponSfx.for_miss(pike) == "miss_ranged", "a shortbow miss whistles past")
	check(WeaponSfx.for_miss(goblin) in WeaponSfx.MISS_IDS, "a monster miss resolves to a real id")
	check(WeaponSfx.for_miss(null) == "miss", "no attacker at all -> the generic miss")
	# Schools, off real spells.
	check(WeaponSfx.for_spell("fireball") == "cast_evocation", "fireball is evocation")
	check(WeaponSfx.for_spell("cure-wounds") == "cast_abjuration", "cure-wounds is abjuration")
	check(WeaponSfx.for_spell("not-a-spell") == "cast", "an unknown spell -> the generic cast")
	check(WeaponSfx.for_spell("") == "cast", "no spell id -> the generic cast")

	print("test_audio: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
