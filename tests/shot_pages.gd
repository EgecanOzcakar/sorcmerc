# Dev-only: every screen with text on it, one PNG each, into shots_tmp/ — the
# walk behind the 2026-09-19 reading pass, kept so the next one starts from
# the same 33 pages. Needs a display (it renders); not part of run_tests.sh.
#   godot --path . --resolution 1400x860 -s tests/shot_pages.gd
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Campaign = preload("res://core/campaign.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Leveling = preload("res://core/leveling.gd")
const Travel = preload("res://core/travel.gd")
const RNG = preload("res://core/rng.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")
const ManualOverlay = preload("res://scenes/manual/manual.gd")
const AchievementsOverlay = preload("res://scenes/achievements/achievements.gd")
const BugReportOverlay = preload("res://scenes/bugreport/bug_report.gd")

var game
var _n := 0

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-%d" % randi())
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()
	await shot("title")
	game.show_content()
	await shot("mods")
	game.show_party_setup()
	await shot("party_setup")

	# The creator, step by step.
	var cre = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(cre)
	await settle()
	var ch = Creator.new_character()
	ch.cname = "Wren Ashby"
	ch.species_id = "elf"
	ch.add_level("wizard", -1)
	ch.background_id = "sage"
	cre.ch = ch
	cre._abil_mode = "array"
	ch.dirty()
	for step in 6:
		cre._goto(step)
		await shot("creator_%d" % step)
	cre.queue_free()

	# Profile and level-up.
	var ilsa = Presets.ilsa()
	var prof = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(prof)
	prof.set_character(ilsa)
	await shot("profile")
	ilsa.xp = Leveling.xp_for_level(4)
	prof.level_up()
	await shot("levelup_preview")
	for c in prof.get_children():
		if c.has_method("commit"):
			c.commit()
	await shot("levelup_choices")
	prof.queue_free()

	# The open world and everything drawn over it.
	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	await shot("world")
	w._toggle_menu()
	await shot("world_menu")
	w._toggle_menu()
	w._toggle_quests()
	await shot("world_quests")
	w._toggle_quests()
	w._toggle_inventory()
	await shot("world_inventory")
	w._toggle_inventory()
	w._open_party()
	await shot("party_screen")
	if w._party_overlay != null:
		w._close_party()
	w._open_visit(w.world.settlements[0])
	await shot("visit_hub")
	w._goto_page("market")
	await shot("visit_market")
	w._goto_page("inn")
	await shot("visit_inn")
	w._goto_page("board")
	await shot("visit_board")
	w._close_visit()
	var foe = w.world.parties[1]
	w._open_approach(foe)
	await shot("approach_card")
	w._on_approach_chosen("parley")
	await shot("event_card_outcome")
	if w._event_card != null:
		w._event_card.queue_free()
		w._event_card = null
	var e := {}
	var r = RNG.new(7)
	for i in 40:
		e = Travel.check(w.party, w.world, r)
		if not e.is_empty():
			break
	if not e.is_empty():
		w._event_card = load("res://scenes/world/event_card.gd").new()
		w.add_child(w._event_card)
		w._event_card.show_event(e)
		await shot("event_card_road")
		w._event_card.queue_free()
		w._event_card = null
	w._show_spoils({"outcome": "Victory", "xp": 120, "gold": 45,
		"loot": ["potion-of-healing", "potion-of-healing"], "rounds": 6})
	await shot("spoils")
	if w._spoils_panel != null:
		w._close_spoils()
	w._build_levelup_panel([w.party.roster[0]])
	await shot("levelup_panel")
	w._close_levelup()
	game.show_title()

	# The fight.
	var fight = load("res://scenes/main.tscn").instantiate()
	root.add_child(fight)
	await settle(2.0)
	await shot("combat")
	fight.queue_free()

	# The linear run and its summary.
	var pty = Party.new()
	for c in Presets.party():
		pty.add_member(c)
	var run = Campaign.new(pty, 11)
	game._show_campaign(run)
	await shot("campaign")
	game.campaign = null
	run.state = "won"
	game.show_summary(run)
	await shot("summary")
	game.show_title()

	# The overlays.
	SettingsOverlay.toggle(game)
	await shot("settings")
	SettingsOverlay.toggle(game)
	ManualOverlay.toggle(game)
	await shot("manual")
	ManualOverlay.toggle(game)
	AchievementsOverlay.open(game)
	await shot("achievements")
	for c in game.get_children():
		if c.get_script() == AchievementsOverlay:
			c.queue_free()
	BugReportOverlay.toggle(game, {"Screen": "title"})
	await shot("bug_report")
	quit()

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	_n += 1
	root.get_viewport().get_texture().get_image().save_png("res://shots_tmp/page_%02d_%s.png" % [_n, name])
	print("saved page_%02d_%s.png" % [_n, name])
