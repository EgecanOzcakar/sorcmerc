# Dev-only: the three screens the hiring pool adds or changes (core/recruits.gd)
# — the founding screen of a new run, the inn's "Looking for work" list, and the
# settle-in page a hireling is finished on. Needs a display (it renders); not
# part of run_tests.sh.
#
#   xvfb-run -a -s "-screen 0 1600x900x24" \
#       godot --path . --resolution 1400x860 -s tests/shot_hiring.gd   ->  shots_hiring/*.png
extends SceneTree

const Recruits = preload("res://core/recruits.gd")
const Leveling = preload("res://core/leveling.gd")

var game

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/shots-hiring-%d" % randi())
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
	DirAccess.make_dir_recursive_absolute("res://shots_hiring")
	game = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	await settle()

	# 1. The founding: a new run, nobody on the roster, one hero to make.
	game.show_party_setup()
	await shot("founding")

	# 2. The inn at Riverhold, a day in, with a founder and the founding purse.
	game.show_world(null)
	await settle(1.5)
	var w = game._screen
	var party = w.party
	party.roster.clear()
	party.active.clear()
	var founder = load("res://core/presets.gd").vera(1)
	founder.id = "founder"
	party.add_member(founder)
	Recruits.found(party)
	party.gold = Recruits.FOUNDING_PURSE
	w.world.clock.elapsed = 600.0
	var s = w.world.settlements[0]
	w._open_visit(s)
	w._goto_page("inn")
	await shot("inn_looking_for_work")

	# 3. Settling one in: the first recruit with a choice left to make.
	var offers: Array = Recruits.offers(s, w.world, party)
	var pick: Dictionary = offers[0]
	for o in offers:
		if not Leveling.can_finalize(Recruits.build(o)):
			pick = o
			break
	w._open_settle_in(s, pick)
	await shot("settle_in")
	quit(0)

func settle(secs := 0.6) -> void:
	await create_timer(secs).timeout

func shot(name: String) -> void:
	await settle()
	RenderingServer.force_draw()
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://shots_hiring/%s.png" % name)
	print("saved shots_hiring/%s.png" % name)
