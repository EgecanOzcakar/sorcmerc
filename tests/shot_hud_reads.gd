# Dev-only: the combat HUD reads of #241 and #238, for the PR's screenshots.
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . -s tests/shot_hud_reads.gd
#
# Settles the demo fight on a hero turn, then puts a few effects on the board
# so the character card has something to list — Bless and its concentration on
# the acting hero, Prone and Bane on the nearest foe — and saves two frames:
#   hud_card_foe.png    the card on a foe (#238: a foe's conditions and spells)
#   hud_card_hero.png   the card on the hero, whose bar shows their weapon (#241)
#   hud_swapped.png     the same bar after Tab: the two weapons change places
# The preset heroes each carry one weapon, so the acting one is handed a light
# crossbow for the picture — enough for the Swap slot to have something to show.
# Crop and shrink them into docs/shots/ by hand; nothing here is a test.
extends SceneTree

const Adapter = preload("res://core/adapter.gd")

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	var guard = 0
	while main.cb and not main.cb.is_over() and main.cb.round_num < 2 and guard < 40:
		await process_frame
		guard += 1
	for i in 20:
		await process_frame
	await create_timer(0.8).timeout
	var cb = main.cb
	var hero = cb.current()
	var foe = null
	for c in cb.team_of("foe"):
		if c.conscious() and (foe == null or c.id < foe.id):
			foe = c
	hero.statuses["spell:bless"] = {"bonus_to_hit": 2, "bonus_save": 2,
		"until_tick": cb._tick() + 10 * cb.TICK_STRIDE, "held_by": hero}
	hero.statuses["concentrating"] = {"spell": "bless", "until_round": cb.round_num + 9}
	if foe != null:
		foe.statuses["prone"] = true
		foe.statuses["spell:bane"] = {"bonus_to_hit": -2, "bonus_save": -2,
			"until_tick": cb._tick() + 3 * cb.TICK_STRIDE, "held_by": hero}
		main._card.show_who(foe, cb)
	var xbow: Dictionary = hero.attacks[0].duplicate(true)
	xbow.merge({"id": "light-crossbow", "name": "Light Crossbow", "range": "ranged",
		"dice_count": 1, "dice_sides": 8, "notation": "1d8+%d" % int(xbow["dmg_bonus"]),
		"damage_type": "piercing", "normal_ft": 80, "long_ft": 320, "properties": ["ammunition", "loading", "two-handed"],
		"mastery": ""}, true)
	hero.attacks.append(xbow)
	main._build_hero_menu(hero)
	main._refresh()
	await _save("hud_card_foe.png")
	main._card.show_who(hero, cb)
	main._refresh()
	await _save("hud_card_hero.png")
	Adapter.set_main_attack(hero, "light-crossbow")
	main._build_hero_menu(hero)
	main._refresh()
	await _save("hud_swapped.png")
	quit()

func _save(name: String) -> void:
	for i in 6:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://" + name)
	print("saved %s  %dx%d" % [name, img.get_width(), img.get_height()])
