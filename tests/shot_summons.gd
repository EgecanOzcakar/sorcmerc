# Dev-only: the two tokens T-summon puts on the board, and the bar that calls
# them. Two frames — the Beast Master's turn with Primal Companion on the bar,
# then the board once the beast and the Trickery cleric's double are standing,
# so the turn strip shows them holding initiative counts of their own.
#
#   SORCMERC_SEED=7 xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . -s tests/shot_summons.gd   ->  shots_summons/*.png
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Leveling = preload("res://core/leveling.gd")
const Party = preload("res://core/party.gd")

func autopick(p: Dictionary, sheet, prefer := "") -> Array:
	var opts := Creator.options_for(p, sheet)
	if opts.is_empty():
		return []
	for o in opts:
		if o["id"] == prefer:
			return [prefer]
	var picks: Array = []
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3:
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

func build(cid: String, sid: String, lvl: int, nm: String):
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
		var picks := autopick(p, sheet, sid if p["type"] == "subclass" else "")
		if picks.is_empty():
			break
		ch.decide(p["key"], Creator.decision_for(p, picks))
	return ch

func grab(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://shots_summons/%s.png" % name)
	print("saved shots_summons/%s.png  %dx%d" % [name, img.get_width(), img.get_height()])

func find(cb, cid: String):
	for c in cb.combatants:
		if c.sheet != null and String(c.id) == "shot-%s" % cid:
			return c
	return null

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots_summons"))
	var pty = Party.new()
	pty.add_member(build("ranger", "beastmaster", 8, "Sena Thornwake"))
	pty.add_member(build("cleric", "trickerydomain", 8, "Ilsa Vane"))
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
	var ranger = find(cb, "ranger")
	var cleric = find(cb, "cleric")
	if ranger == null or cleric == null:
		print("the two heroes did not make it onto the board")
		quit(1)
		return

	# 1. The bar, on the ranger's turn, before anything is pressed.
	cb.turn_idx = cb.order.find(ranger)
	cb.begin_turn()
	main._mode = "idle"
	main._build_hero_menu(ranger)
	main._refresh()
	for i in 4:
		await process_frame
	print("bar: ", cb.available(ranger).map(func(v): return String(v["id"])))
	await grab("1_bar")

	# 2. Both tokens up, both holding a count of their own.
	for pair in [[ranger, "beastmaster-primal-companion"], [cleric, "trickerydomain-invoke-duplicity"]]:
		var who = pair[0]
		cb.begin_turn_for(who)
		for v in who.verbs:
			if String(v["id"]) == String(pair[1]):
				print(who.cname, " -> ", cb.perform(who, v))
	cb.turn_idx = cb.order.find(ranger)
	main._mode = "idle"
	main._build_hero_menu(ranger)
	main._refresh()
	for i in 240:          # long enough for the achievement toast to clear the turn strip
		await process_frame
	var names: Array = []
	for c in cb.order:
		names.append("%s(%d)" % [c.short_name(), c.init_roll])
	print("order: ", ", ".join(names))
	await grab("2_board")
	quit()
