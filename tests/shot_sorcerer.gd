# Dev-only: the sorcerer's two features on the bar. Two frames — the Bonus
# actions list ([3]) on a level-5 sorcerer's turn, with Innate Sorcery and the
# Font of Magic buttons in it; then the same list after Innate Sorcery and one
# slot made from points, so the actor line's pips show the extra slot. Then
# Metamagic: the Bonus list with the sorcerer's two options (Quickened and
# Twinned, picked on purpose), and the Spells list with Quickened armed, where
# every action spell now costs a Bonus Action.
#
#   SORCMERC_SEED=7 xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . -s tests/shot_sorcerer.gd   ->  shots_sorcerer/*.png
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Leveling = preload("res://core/leveling.gd")
const Party = preload("res://core/party.gd")

const WANT := ["quickened-spell", "twinned-spell"]

func autopick(p: Dictionary, sheet) -> Array:
	var opts := Creator.options_for(p, sheet)
	var picks: Array = []
	for o in opts:
		if String(o["id"]) in WANT and picks.size() < Creator.pick_count(p):
			picks = Creator.toggle(p, picks, o["id"])
	if not picks.is_empty():
		return picks
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3 and not opts.is_empty():
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

func build(cid: String, lvl: int, nm: String):
	var ch = Creator.new_character()
	ch.id = "shot-%s" % cid
	ch.cname = nm
	ch.species_id = "human"
	ch.background_id = String(Catalog.class_src(cid).get("quickBuild", {}).get("suggestedBackground", "soldier"))
	ch.base_abilities = Creator.recommended_array(cid)
	Leveling.grant_levels(ch, lvl, cid)
	for _step in 120:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			break
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet)
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	return ch

func grab(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://shots_sorcerer/%s.png" % name)
	print("saved shots_sorcerer/%s.png  %dx%d" % [name, img.get_width(), img.get_height()])

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_sorcerer"))
	var pty = Party.new()
	pty.add_member(build("sorcerer", 5, "Maren Ashvale"))
	pty.add_member(build("fighter", 5, "Vera Holt"))
	var main = load("res://scenes/main.tscn").instantiate()
	main.party = pty
	root.add_child(main)
	for i in 90:
		await process_frame
	if main._mode == "deploy":
		main._press_hotkey(-1)
		for i in 90:
			await process_frame
	var cb = main.cb
	var sorc = null
	for c in cb.combatants:
		if String(c.id) == "shot-sorcerer":
			sorc = c
	if sorc == null:
		print("the sorcerer did not make it onto the board")
		quit(1)
		return

	# 1. [3] Bonus actions, before anything is pressed: Innate Sorcery and the
	# points-for-a-slot buttons live, the slot-for-points ones greyed (the
	# pool is already full, so a burned slot would lose its points).
	cb.turn_idx = cb.order.find(sorc)
	cb.begin_turn()
	main._mode = "idle"
	main._build_hero_menu(sorc)
	main._refresh()
	for i in 4:
		await process_frame
	main._press_hotkey(2)
	for i in 6:
		await process_frame
	print("bar: ", cb.available(sorc).map(func(v): return String(v["id"])))
	await grab("1_bonus")

	# 2. Innate Sorcery up and a 1st-level slot made next turn: the pips on the
	# actor line carry the fifth 1st-level slot.
	for v in sorc.verbs:
		if String(v["id"]) == "sorcerer-innate-sorcery":
			print("innate -> ", cb.perform(sorc, v))
	sorc.econ["bonus"] = 1
	for v in sorc.verbs:
		if String(v["id"]) == "sorcerer-font-of-magic@slot1":
			print("font -> ", cb.perform(sorc, v))
	sorc.econ["bonus"] = 1
	main._mode = "idle"
	main._build_hero_menu(sorc)
	main._refresh()
	for i in 4:
		await process_frame
	main._press_hotkey(2)
	for i in 240:
		await process_frame
	await grab("2_after")

	# 3. Metamagic: its options sit in the Bonus list with the Font buttons
	# (they cost no action of their own). Every page of it, so the two
	# options are on one of them whatever the list's length.
	main._build_hero_menu(sorc)
	main._refresh()
	var bonus: Array = main._slot_list(main._menu_entries(sorc)["opts"], "bonus")
	print("bonus list: ", bonus.map(func(o): return o[0]))
	var at: int = -1
	for i in bonus.size():
		if String(bonus[i][0]).contains("Quickened"):
			at = i
	var per: int = main.LIST_PAGE if bonus.size() <= main.LIST_PAGE else main.LIST_PAGE - 1
	main._open_list(sorc, "bonus", maxi(0, at) / per)
	for i in 30:
		await process_frame
	await grab("3_metamagic")

	# 4. Quickened armed: the Spells list, where Fireball and the rest now
	# read [bonus].
	for v in sorc.verbs:
		if String(v["id"]) == "metamagic-quickened-spell":
			print("quicken -> ", cb.perform(sorc, v))
	# ...and cast: Fire Bolt goes off as a Bonus Action, the log says so, and
	# the action is still there for a second spell (a cantrip, by RAW).
	var foe = cb.combatants.filter(func(c): return c.team == "foe" and not c.is_dead())[0]
	for v in cb.available(sorc):
		if String(v.get("spell", "")) == "fire-bolt":
			print("fire bolt -> ", cb.perform(sorc, v, foe))
			break
	print("econ ", sorc.econ)
	main._flush_log()
	main._build_hero_menu(sorc)
	main._refresh()
	for i in 240:
		await process_frame
	await grab("4_quickened")
	quit()
