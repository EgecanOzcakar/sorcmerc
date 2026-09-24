# Dev-only: the picture for #176's step 0 — a hero's own resistance on the
# combat card, which it never was before the Combatant carried it. Needs a
# display (it renders 3D); not part of run_tests.sh.
#
#   godot --path . --resolution 1400x900 -s tests/shot_hero_resist.gd
#     -> hero_resist.png   the demo fight, Vera made a dwarf, her card filled
extends SceneTree

const Settings = preload("res://core/settings.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")


func _init() -> void:
	Settings.current().reaction_prompts = false   # nobody here to answer one
	var party := Party.new()
	for ch in Presets.party():
		if ch.id == "vera":
			ch.species_id = "dwarf"   # poison resistance, off the species' own grant
			ch.dirty()
		party.add_member(ch)
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = party
	root.add_child(main)
	for _i in 30:
		await process_frame

	# Past deployment, onto a hero's turn (shot_board_props.gd's loop).
	var guard := 0
	while guard < 900:
		await process_frame
		guard += 1
		if main.cb == null or main.cb.is_over() or main._busy:
			continue
		if main._mode == "deploy":
			for b in main._buttons.get_children():
				if b is Button and not b.disabled and "Begin" in b.text:
					b.pressed.emit()
					break
			continue
		var cur = main.cb.current()
		if main._mode == "idle" and cur != null and cur.team == "party" and cur.conscious():
			break

	# Fill the card off a real hover, the path a player walks.
	for c in main.cb.combatants:
		if c.id == "vera":
			main.board_hex_hovered(c.pos)
			break
	main._cam_follow = false
	main._board._auto_fit = true
	main._pan = Vector2.ZERO
	for _i in 30:
		await process_frame
	await create_timer(0.4).timeout
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://hero_resist.png")
	print("wrote hero_resist.png")
	quit()
