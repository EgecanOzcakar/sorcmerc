# Dev-only: the combat board with its two loud readouts up at once — the roll
# reveal's headline and a damage number over three bodies hit for three
# different fractions of what they had, so one frame shows the whole size ramp.
#
#   SORCMERC_SEED=5 xvfb-run -a godot --path . -s tests/shot_damage.gd
#       -> damage_numbers.png (pin the seed or the board is a different fight)
#
# Not headless and not under SORCMERC_FAST: both switch off the cosmetic layer
# this exists to photograph, and at the Instant pace the numbers never animate.
extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 90:
		await process_frame
	var foes: Array = []
	for c in main.cb.combatants:
		if c.team != "party" and not c.is_dead():
			foes.append(c)
	if foes.is_empty():
		print("no foes on the board — nothing to photograph")
		quit(1)
		return
	# A scratch, a solid hit and a near-kill. The number's size is the share of
	# the body it took, so these should read small, middling and large.
	var bites := [0.10, 0.40, 0.90]
	for i in mini(foes.size(), bites.size()):
		var c = foes[i]
		c.hp = maxi(1, c.max_hp - int(round(c.max_hp * float(bites[i]))))
	# ...and the headline over the one that nearly died.
	var lead = foes[mini(2, foes.size() - 1)]
	var res := {"hit": true, "crit": true, "damage": lead.max_hp - lead.hp,
		"dice": [20, 6, 5], "nat": 20, "bonus": 5, "total": 25, "ac": 14}
	main._board.show_reveal(lead.id, res, main._reveal_head(res))
	# Two frames: one for tick() to see the new hp and spawn, one to lift the
	# numbers clear. A capture under xvfb renders this scene at ~7fps, so the
	# 1.1s life is gone by frame 8 — there is no wide window to aim at.
	for i in 2:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://damage_numbers.png")
	print("saved damage_numbers.png  %dx%d" % [img.get_width(), img.get_height()])
	quit()
