# T-party3d: RoamingParty.troops/highest_troop(), and Party3D's model pick
# off them — the player keeps their gold-ringed pawn, a race-troop band
# (human/dwarf/elf/orc) with a roster gets the role figure, a monster-faction
# band with no race counterpart (goblinoid, undead, ...) falls back to
# figures3d.gd's single FOE_MODELS figure for that faction, and only a band
# with neither (no troops, no faction coverage) falls through to the flat
# PawnTex icon.
#   godot --headless --path . -s tests/test_party3d.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	const World = preload("res://core/world.gd")
	var p := World.RoamingParty.new("test", Vector2.ZERO, "human")
	check(p.highest_troop().is_empty(), "no troops, no highest troop")
	p.troops = [{"role": "heavy", "level": 2}, {"role": "light", "level": 5}, {"role": "spellcaster", "level": 3}]
	check(String(p.highest_troop().get("role", "")) == "light", "highest_troop picks the max level, not the first")
	p.troops = [{"role": "heavy", "level": 4}, {"role": "light", "level": 4}]
	check(String(p.highest_troop().get("role", "")) in ["heavy", "light"], "a tie still returns one of them, not empty")

	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	check(main._party3d != null, "Party3D is wired into the live scene")

	var patrol = null
	var player = null
	var goblins = null
	for party in main.world.parties:
		if party.id == "patrol": patrol = party
		if party.is_player: player = party
		if party.id == "goblins": goblins = party
	check(patrol != null and main._party3d.has_model(patrol),
		"patrol (human, heavy troop we generated) gets a figure")
	check(player != null and not main._party3d.has_model(player),
		"the player never gets a Party3D figure — they keep the pawn")
	check(goblins != null and main._party3d.has_model(goblins),
		"goblinoid has no race counterpart, but gets the FOE_MODELS figure combat uses")

	print("test_party3d: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
