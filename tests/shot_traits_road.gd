# Dev-only: the pictures for #176 step 4 — personality traits off the fight
# board, on the real world screen: a road event's roll line naming the roller's
# trait, the fire saying what a trait earned did to somebody, and the party
# page's Relations naming the traits behind a pull. Needs a display (the world
# renders 3D); not part of run_tests.sh.
#
#   SORCMERC_FAST=1 godot --path . --resolution 1400x900 -s tests/shot_traits_road.gd
#     -> docs/shots/traits-road-card.png       "(Downs-rider +1)" on the roll line
#     -> docs/shots/traits-road-fire.png       the burn, said at the next fire
#     -> docs/shots/traits-road-relations.png  "...: Brave and Craven"
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Travel = preload("res://core/travel.gd")
const RNG = preload("res://core/rng.gd")

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shot-%d" % OS.get_process_id())
	var s = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(s)
	for _i in 30:
		await process_frame
	var chars: Array = s.party.party_characters()
	for ch in chars:
		ch.traits_offered = true
	Traits.set_family(chars[0], "origin", "downs-rider")
	Traits.set_family(chars[0], "temperament", "brave")
	Traits.set_family(chars[1], "temperament", "craven")

	# A real road event, rolled by the Downs-rider: the first seed whose roller
	# is them.
	s._process(0.016)
	var e := {}
	for seed_v in range(1, 600):
		e = Travel.check(s.party, s.world, RNG.new(seed_v))
		if e.has("trait_term"):
			break
	s._card(e, func(): pass)
	for _i in 12:
		await process_frame
	await _save("docs/shots/traits-road-card.png")
	s._event_card.queue_free()
	s._event_card = null

	# The fire: Pike came back from a burn, and nobody has said anything yet.
	Traits.grant(chars[1], "burn-shy", "Went down in the fire — Hell Hound", s.world.clock.elapsed)
	for night in 8:
		if not s._fireside(RNG.new(10 + night), func(): pass):
			continue
		var said := String(s._event_card._e.get("text", "")) if s._event_card != null else ""
		if "sits well back" in said:
			for _i in 12:
				await process_frame
			await _save("docs/shots/traits-road-fire.png")
			break
		if s._event_card != null:
			s._event_card.queue_free()
			s._event_card = null
	if s._event_card != null:
		s._event_card.queue_free()
		s._event_card = null

	# The party page: Brave and Craven, and what it has done to them.
	s._open_party()
	for _i in 12:
		await process_frame
	await _save("docs/shots/traits-road-relations.png")
	quit()

func _save(path: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://" + path)
	print("wrote ", path)
