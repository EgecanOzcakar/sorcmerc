# Dev-only: the effect strip beside the action bar (core/active_effects.gd).
# A level-5 sorcerer with Innate Sorcery up, Quickened Spell armed, a Bless
# from the cleric and Poisoned on them: the chips, the ✦ on the Spells slot,
# then the Spells list with ✦ and ADV on the buttons they change. Then the
# fighter, Hidden and Helped: ADV on the attack button.
#
#   SORCMERC_SEED=7 xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . -s tests/shot_effects.gd   ->  shots_effects/*.png
extends SceneTree

const Kits = preload("res://tests/kits.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

func grab(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://shots_effects/%s.png" % name)
	print("saved shots_effects/%s.png  %dx%d" % [name, img.get_width(), img.get_height()])

func settle(main, n := 30) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_effects"))
	var pty = Party.new()
	var sorc_ch = Kits.hero("sorcerer", "draconicsorcery", 5)
	sorc_ch.id = "shot-sorcerer"
	sorc_ch.cname = "Maren Ashvale"
	pty.add_member(sorc_ch)
	for ch in Presets.party().slice(0, 2):
		pty.add_member(ch)
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = pty
	root.add_child(main)
	await settle(main, 90)
	if main._mode == "deploy":
		main._press_hotkey(-1)
		await settle(main, 90)
	var cb = main.cb
	var sorc = null
	var fighter = null
	for c in cb.combatants:
		if String(c.id) == "shot-sorcerer":
			sorc = c
		elif c.team == "party" and fighter == null:
			fighter = c
	var cleric = cb.combatants.filter(func(c): return c.team == "party" and c != sorc and c != fighter)[0]

	# 1. the sorcerer's turn, four things riding on them
	cb.turn_idx = cb.order.find(sorc)
	cb.begin_turn()
	for v in sorc.verbs:
		if String(v["id"]) == "sorcerer-innate-sorcery":
			print("innate -> ", cb.perform(sorc, v))
	sorc.econ["bonus"] = 1
	sorc.statuses["metamagic"] = {"option": "quickened", "sp": 2, "label": "Quickened Spell"}
	sorc.pools["sorcery-points"]["cur"] = int(sorc.pools["sorcery-points"]["cur"]) - 2
	sorc.statuses["spell:bless"] = {"bonus_to_hit": 2, "bonus_save": 2, "until_tick": cb._tick() + 9 * cb.TICK_STRIDE, "held_by": cleric}
	cb.apply_condition(sorc, "poisoned")
	main._mode = "idle"
	main._build_hero_menu(sorc)
	main._refresh()
	await settle(main, 60)
	await grab("1_strip")

	# 2. the Spells list: ✦ where Quickened rides, ADV where Innate Sorcery does
	main._open_list(sorc, "spells", 0)
	await settle(main, 30)
	await grab("2_spells")

	# 3. the fighter, Hidden and Helped: ADV on the attack
	for c in cb.combatants:
		c.statuses.erase("poisoned")
	cb.turn_idx = cb.order.find(fighter)
	cb.begin_turn()
	fighter.statuses["hidden"] = true
	fighter.statuses["helped"] = {"by": cleric}
	main._mode = "idle"
	main._build_hero_menu(fighter)
	main._refresh()
	await settle(main, 60)
	await grab("3_fighter")
	quit()
