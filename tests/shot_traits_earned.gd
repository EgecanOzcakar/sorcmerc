# Dev-only: the pictures for #176 step 3 — a fight's earned personality traits
# on the real world screen: the after-action page's gilt lines, then the moment
# each one opens once the page is read. Needs a display (the world renders 3D);
# not part of run_tests.sh.
#
#   SORCMERC_FAST=1 godot --path . --resolution 1400x900 -s tests/shot_traits_earned.gd
#     -> docs/shots/traits-earned-spoils.png   the page: who came out of it as what
#     -> docs/shots/traits-earned-bane.png     the moment: the tenth goblin, a bane (counted, first)
#     -> docs/shots/traits-earned-scar.png     the moment: downed by fire, the save failed
#     -> docs/shots/traits-earned-profile.png  the profile: the scar and what mends it
extends SceneTree

const Traits = preload("res://core/traits.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shot-%d" % OS.get_process_id())
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 30:
		await process_frame
	var chars: Array = s.party.party_characters()
	var burned = chars[0]
	var slayer = chars[1]
	slayer.trait_counts["kill:goblinoid"] = 9
	# A minute at which the fire scars the first hero (the roll is seeded off
	# the hero, the event and the minute — found, not forced).
	var result := {}
	for i in 400:
		var probe = Traits.after_fight([_copy(burned)], _fire(burned.id, slayer.id), {"now": float(i)})
		if probe["moments"].any(func(m): return m["kind"] == "scar"):
			s.world.clock.elapsed = float(i)
			result = _fire(burned.id, slayer.id)
			break
	s._earn_from_fight(result, "easy", "road")
	s._show_spoils(result)
	for _i in 90:   # the page deals its rows out
		await process_frame
	await _save("docs/shots/traits-earned-spoils.png")
	s._close_spoils()
	s._process(0.016)
	for _i in 10:
		await process_frame
	await _save("docs/shots/traits-earned-bane.png")
	s._moment._skip_or_advance()
	for _i in 10:
		await process_frame
	await _save("docs/shots/traits-earned-scar.png")
	while s._moment != null:
		s._moment._skip_or_advance()
		await process_frame
	var page = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(page)
	page.set_party(s.party)
	page.set_character(burned)
	for _i in 10:
		await process_frame
	await _save("docs/shots/traits-earned-profile.png")
	quit()

func _fire(burned_id: String, slayer_id: String) -> Dictionary:
	return {"outcome": "Victory", "xp": 240, "gold": 30, "loot": [], "deaths": [], "kills": ["goblin", "hell-hound"],
		"downed": [burned_id], "rounds": 4, "objective": {},
		"credit": {burned_id: {"kills": [], "downed_by": [{"dtype": "fire", "by": "hell-hound", "team": "foe"}], "revived_by": []},
			slayer_id: {"kills": ["goblin"], "downed_by": [], "revived_by": []}}}

func _copy(ch):
	var CharacterSave = load("res://core/character_save.gd")
	return CharacterSave.from_dict(CharacterSave.to_dict(ch))

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
