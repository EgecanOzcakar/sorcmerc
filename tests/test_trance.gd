# T9x: shorter-rest characters (core/trance.gd) — keyed off any feature id in
# TRANCE_FEATURES (data/species.json's "elf-trance", or a subclass/homebrew
# feature reusing the same id), not the race name. Mutates a resolved sheet's
# `features` dict directly to simulate "this build resolved with Trance"
# rather than driving the full species/creator pipeline — that pipeline is
# its own well-covered concern (test_creator.gd); this only tests what
# core/trance.gd does once a character has the feature.
#   godot --headless --path . -s tests/test_trance.gd
extends SceneTree

const Trance = preload("res://core/trance.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const World = preload("res://core/world.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _party(trance: bool) -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	if trance:
		p.roster[0].sheet().features[Trance.TRANCE_FEATURES[0]] = {}
	return p

func _init() -> void:
	check(not Trance.has_trance(_party(false)), "a plain party has no Trance")
	check(Trance.has_trance(_party(true)), "a party with the feature reads as having Trance")

	# --- apply_rest_bonus: no-op without the feature ---
	var w := World.new()
	w.add_settlement(World.Settlement.new("home", Vector2.ZERO, "human", "town"))
	var plain := _party(false)
	check(Trance.apply_rest_bonus(plain, w, Vector2.ZERO).is_empty(), "no Trance -> no bonus at all")

	# --- with Trance: short-rest top-up, wider scouting, a free identify try ---
	var elf := _party(true)
	var ch = elf.party_characters()[0]
	ch.hp_current = 1
	elf.stash_add("longsword", 1, false)   # an "unidentified" stack to try identifying
	var w2 := World.new()
	var bonus: Dictionary = Trance.apply_rest_bonus(elf, w2, Vector2.ZERO, RNG.new(1))
	check(not bonus.is_empty(), "Trance -> a real bonus dict comes back")
	check(ch.hp_current > 1, "the short-rest top-up actually heals")
	check(w2.is_explored(Vector2(w2.EXPLORE_RADIUS * Trance.SCOUT_MULT, 0)),
		"scouting reaches past the normal EXPLORE_RADIUS in at least one direction")
	check(bonus["identify"].has("ok"), "an unidentified item in the stash gets a real identify attempt")

	var no_mystery := _party(true)
	check(Trance.apply_rest_bonus(no_mystery, World.new(), Vector2.ZERO)["identify"].is_empty(),
		"nothing to identify -> the identify slot is empty, not a crash")

	print("test_trance: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
