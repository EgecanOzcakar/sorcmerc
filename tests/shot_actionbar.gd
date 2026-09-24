# Dev-only: the action bar with a hover card up, for a PR screenshot. Opens
# Ilsa Vane's [2] Spells list (the demo party's cleric — see
# tests/test_action_bar.gd for why her) and moves the real mouse onto one badge,
# so what is captured is the engine's own tooltip popup, not a card placed by
# hand. Needs a display (xvfb-run is fine); headless draws nothing.
#
#   godot --path . -s tests/shot_actionbar.gd                 # -> actionbar_screen.png
#   SHOT_SLOT=1 SHOT_PICK=0 godot --path . -s tests/shot_actionbar.gd
#
# SHOT_SLOT is the main-bar slot to open first (1 = Spells; -1 opens nothing),
# SHOT_PICK the button to hover on whatever bar is then showing. SHOT_STATUS=1
# also puts a few conditions on the foes and a few damage lines in the log, to
# show the damage-type / condition colours (core/ui_icons.gd) on the board,
# in the log and on the combat card.
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var ilsa = null
	for c in main.cb.combatants:
		if c.cname == "Ilsa Vane":
			ilsa = c
	if OS.get_environment("SHOT_STATUS") != "":
		var foes: Array = main.cb.combatants.filter(func(c): return c.team != "party")
		var conds := [["prone", "poisoned"], ["frightened"], ["restrained", "stunned"]]
		for i in mini(foes.size(), conds.size()):
			for cond in conds[i]:
				main.cb.apply_condition(foes[i], cond)
		foes[0].resist = ["cold", "poison"]
		main.cb.log.append("Ilsa Vane casts Burning Hands: %s takes 9 fire damage." % foes[0].cname)
		main.cb.log.append("%s is frightened and restrained." % foes[1].cname)
		main.cb.log.append("Vera Kord hits %s for 7 slashing damage; it is knocked prone." % foes[2].cname)
		main.cb.log.append("%s resists the cold, takes 3 cold damage, and is poisoned." % foes[0].cname)
		main._flush_log()
		main._card.show_who(foes[0], main.cb)
	main._build_hero_menu(ilsa)
	await process_frame
	var slot := int(OS.get_environment("SHOT_SLOT")) if OS.get_environment("SHOT_SLOT") != "" else 1
	if slot >= 0:
		main._buttons.get_child(slot).pressed.emit()
		await process_frame
	await process_frame
	var pick := int(OS.get_environment("SHOT_PICK")) if OS.get_environment("SHOT_PICK") != "" else 2
	var b: Control = main._buttons.get_child(pick)
	var at: Vector2 = b.get_global_rect().get_center()
	# Two motions: the engine arms a tooltip on travel, not on arrival.
	for p in [at - Vector2(3, 3), at]:
		var ev := InputEventMouseMotion.new()
		ev.position = p
		ev.global_position = p
		root.push_input(ev)
		await process_frame
	await create_timer(1.2).timeout
	for i in 4:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://actionbar_screen.png")
	print("saved actionbar_screen.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
