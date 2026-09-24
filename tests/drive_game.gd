# T17/O8 — headless player for the whole game, from the entry scene: title → new
# run → make the founder (a new run makes one; the rest are hired at an inn) →
# begin → the open world (normal play), then the same
# walk again with SORCMERC_LINEAR_CAMPAIGN set, which is the only way to the old
# linear route: campaign map → retire → run summary → hub → resume.
# Presses real buttons on the real scenes; the fighting itself is drive_ui's and
# drive_campaign's job, so this walk retires instead of playing the road out.
#   godot --headless --path . -s tests/drive_game.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const WorldSave = preload("res://core/world_save.gd")
const CharacterSave = preload("res://core/character_save.gd")

const SLUG := "drive-gamesworth"
const SLUG2 := "drive-secondrun"    # the second run's founder
const Recruits = preload("res://core/recruits.gd")

var main
var _presses := 0
var _fail := 0

func _init() -> void:
	# O17: this process's own autosave slots, so a concurrent godot run cannot
	# clobber them. randi() as well as the pid: under a sandboxed (flatpak)
	# godot every process sees pid 3, so the pid alone is not unique.
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")   # normal play, whatever the shell said
	CampaignSave.clear()                 # a saved run would change the title screen
	WorldSave.clear()                    # ...and so would a saved open world
	CharacterSave.delete(SLUG)           # and a leftover from an earlier walk
	CharacterSave.delete(SLUG2)
	main = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(main)
	_run()

func fail(msg: String) -> void:
	_fail += 1
	printerr("  FAIL: ", msg)

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion() and not c.disabled:
			out.append(c)
		out.append_array(buttons(c))
	return out

func press(label: String, under: Node = null) -> bool:
	for b in buttons(under if under else main):
		if label in b.text:
			_presses += 1
			b.pressed.emit()
			return true
	fail("no button labelled '%s'" % label)
	return false

# The first node of `type` anywhere under the hub.
func find_node(node: Node, script_path: String):
	if node.get_script() != null and node.get_script().resource_path == script_path:
		return node
	for c in node.get_children():
		var hit = find_node(c, script_path)
		if hit != null:
			return hit
	return null

func _run() -> void:
	await process_frame
	await process_frame

	# --- title ------------------------------------------------------------
	if not buttons(main).any(func(b): return "New run" in b.text):
		fail("the title screen has no New run")
	# O8: with the flag unset, nothing on the title screen leads to the linear run —
	# not even a leftover autosave (Resume is a linear-run door).
	var throwaway := Party.new()
	for ch in Party.demo_roster():
		throwaway.add_member(ch)
	CampaignSave.save(Campaign.new(throwaway, 3))
	main.show_title()
	await process_frame
	if buttons(main).any(func(b): return "Resume the last run" in b.text):
		fail("the title offers Resume (the linear run) with SORCMERC_LINEAR_CAMPAIGN unset")
	CampaignSave.clear()
	main.show_title()
	await process_frame
	press("New run")
	await process_frame

	# --- party setup ------------------------------------------------------
	var party_screen = find_node(main, "res://scenes/party/party.gd")
	if party_screen == null:
		fail("New run did not open the party screen")
		return _done()

	# An empty active party must not be able to start a run.
	# T-worlds replaced the single "Begin the run" button with three
	# ("Begin — Small/Large/Procedural World"); which one is pressed doesn't
	# matter for anything checked in this file (linear-vs-open-world routing
	# is decided by SORCMERC_LINEAR_CAMPAIGN, not by which map size button),
	# so "Small World" stands in for all three everywhere below.
	var was: Array = Array(party_screen.party.active)
	party_screen.party.active.clear()
	press("Begin, small world")
	await process_frame
	if find_node(main, "res://scenes/world/world.gd") != null:
		fail("started a run with an empty active party")
	party_screen.party.active.assign(was)

	# The creator, opened from the party screen. Building a character is
	# drive_creator's job — this only checks the handoff back into the roster,
	# so it hands the creator a finished build and confirms it.
	var before: int = party_screen.party.roster.size()
	press("Create new")
	await process_frame
	var creator = find_node(main, "res://scenes/creator/creator.gd")
	if creator == null:
		fail("the party screen never opened the creator")
		return _done()
	creator.ch = Party.demo_roster()[0]
	creator.ch.id = ""
	creator.ch.cname = "Drive Gamesworth"
	creator._goto(5)                       # review
	creator._next.pressed.emit()
	_presses += 1
	await process_frame
	if party_screen.party.roster.size() != before + 1:
		fail("the created character never reached the roster")
	if CharacterSave.load_slug(SLUG) == null:
		fail("the created character never saved")
	# A new run is a founding (core/recruits.gd): one hero made, and then the
	# door shuts — everyone after is hired at an inn.
	if not Recruits.hire_only(party_screen.party):
		fail("a new run did not start under the hiring rule")
	if party_screen.party.roster.size() != 1:
		fail("a new run's roster is not just the founder (%d)" % party_screen.party.roster.size())
	if buttons(main).any(func(b): return "Create new" in b.text):
		fail("Create new is still open after the founder was made")

	# --- into the open world (O8: the default) ----------------------------
	# The party screen is freed the moment the map replaces it, so hold on to the
	# assembled party itself, not the screen.
	var assembled = party_screen.party
	press("Begin, small world")
	await process_frame
	await process_frame
	var world_screen = find_node(main, "res://scenes/world/world.gd")
	if world_screen == null:
		fail("Begin the run did not reach the open world")
		return _done()
	if find_node(main, "res://scenes/campaign/campaign.gd") != null:
		fail("normal play reached the linear campaign")
	if world_screen.party != assembled:
		fail("the open world is not running the party we assembled")
	if world_screen.party.get_member(SLUG) == null:
		fail("the open world got a demo roster, not the player's own characters")
	if world_screen.world == null or world_screen.world.player() == null:
		fail("the open world has no map/player party")

	# --- O13: leave the map, and the front door offers it back -------------
	var where := Vector2(321, -77)
	world_screen.world.player().position = where
	world_screen.world.set_goal(world_screen.world.player(), where)   # stand still,
	                                                                 # the map runs live
	world_screen.party.add_gold(55)
	var purse: int = world_screen.party.gold
	world_screen._leave_world()
	await process_frame
	await process_frame
	if not buttons(main).any(func(b): return "Resume the open world" in b.text):
		fail("leaving the open world did not put its Resume on the title screen")
	press("Resume the open world")
	await process_frame
	await process_frame
	var resumed_world = find_node(main, "res://scenes/world/world.gd")
	if resumed_world == null:
		fail("Resume the open world did not reopen the map")
	else:
		if not resumed_world.world.player().position.is_equal_approx(where):
			fail("Resume the open world lost the player's position")
		if resumed_world.party.get_member(SLUG) == null:
			fail("Resume the open world lost the player's own characters")
		if resumed_world.party.gold != purse:
			fail("Resume the open world lost the purse (%d, want %d)"
				% [resumed_world.party.gold, purse])
		if resumed_world.world.settlements.is_empty():
			fail("the resumed map has no settlements")
		# ...and back out of it: a live map left mounted keeps ticking under the rest
		# of this walk (parties march, a hunt can open a whole combat scene), which
		# is nobody's idea of a controlled test.
		resumed_world._leave_world()
		await process_frame
		await process_frame

	# --- O13x: a second run gets its own slot, not the first run's file -----
	press("New run")
	await process_frame
	party_screen = find_node(main, "res://scenes/party/party.gd")
	if party_screen == null:
		fail("New run did not open the party screen for the second playthrough")
	else:
		# The first run's founder is in the barracks and stays there: a new run
		# founds its own company, and Begin waits until it has.
		if party_screen.party.get_member(SLUG) != null or not party_screen.party.roster.is_empty():
			fail("the barracks walked into a new run's roster")
		press("Begin, small world")
		await process_frame
		if find_node(main, "res://scenes/world/world.gd") != null:
			fail("a new run began with no founder")
		press("Create new")
		await process_frame
		var second_creator = find_node(main, "res://scenes/creator/creator.gd")
		if second_creator == null:
			fail("the second run's party screen never opened the creator")
			return _done()
		second_creator.ch = Party.demo_roster()[0]
		second_creator.ch.id = ""
		second_creator.ch.cname = "Drive Secondrun"
		second_creator._goto(5)
		second_creator._next.pressed.emit()
		_presses += 1
		await process_frame
		press("Begin, small world")   # the button's own words — see line 104
		await process_frame
		await process_frame
		var second_world = find_node(main, "res://scenes/world/world.gd")
		if second_world == null:
			fail("the second New run did not reach the open world")
		else:
			var where2 := Vector2(-90, 15)
			second_world.world.player().position = where2
			second_world.world.set_goal(second_world.world.player(), where2)
			second_world._leave_world()
			await process_frame
			await process_frame
			var resume_buttons := buttons(main).filter(
				func(b): return "Resume the open world" in b.text)
			if resume_buttons.size() != 2:
				fail("expected 2 open-world slots on the title screen, found %d"
					% resume_buttons.size())
			else:
				# Newest (this second run) sorts first.
				resume_buttons[0].pressed.emit(); _presses += 1
				await process_frame
				await process_frame
				var w2 = find_node(main, "res://scenes/world/world.gd")
				if w2 == null or not w2.world.player().position.is_equal_approx(where2):
					fail("the newest slot's button did not resume the newest slot")
				else:
					w2._leave_world()
					await process_frame
					await process_frame
				resume_buttons = buttons(main).filter(
					func(b): return "Resume the open world" in b.text)
				if resume_buttons.size() == 2:
					resume_buttons[1].pressed.emit(); _presses += 1
					await process_frame
					await process_frame
					var w1 = find_node(main, "res://scenes/world/world.gd")
					if w1 == null or not w1.world.player().position.is_equal_approx(where):
						fail("the older slot's button did not resume the older slot,"
							+ " a fresh run must not have overwritten it")
					else:
						w1._leave_world()
						await process_frame
						await process_frame

	# --- the same walk with the debug flag on: the linear route ------------
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "1")
	main.show_title()
	await process_frame
	press("New run")
	await process_frame
	party_screen = find_node(main, "res://scenes/party/party.gd")
	if party_screen == null:
		fail("New run did not open the party screen the second time")
		return _done()
	assembled = party_screen.party
	press("Begin, small world")
	await process_frame
	await process_frame
	if find_node(main, "res://scenes/world/world.gd") != null:
		fail("SORCMERC_LINEAR_CAMPAIGN still opened the open world")
	var campaign = find_node(main, "res://scenes/campaign/campaign.gd")
	if campaign == null:
		fail("Begin the run did not reach the campaign map")
		return _done()
	if campaign.party != assembled:
		fail("the campaign is not running the party we assembled")
	if campaign.run.state != "picking":
		fail("the run did not start between nodes")

	# --- retire (only offered while picking) ------------------------------
	press("Retire…", campaign)
	press("Yes — end the run now", campaign)
	if campaign.run.state != "retired":
		fail("retiring from the map did not retire the run")
	await process_frame
	await process_frame

	# --- the summary ------------------------------------------------------
	if main.campaign != null:
		fail("the hub did not take the run back off the campaign screen")
	if find_node(main, "res://scenes/campaign/campaign.gd") != null:
		fail("the campaign screen is still up after the run ended")
	if CampaignSave.has_save():
		fail("a finished run left its autosave behind")
	if not _text_on_screen("Retired"):
		fail("the summary does not name the end state")
	if not _text_on_screen("Carried home"):
		fail("the summary has no loot line")

	# --- back to the hub --------------------------------------------------
	press("Back to the hub")
	await process_frame
	if not buttons(main).any(func(b): return "New run" in b.text):
		fail("the summary did not return to the title screen")
	if not _text_on_screen("Sorcmerc"):
		fail("the title is not back up")

	# --- resume: a half-walked run is offered at the front door ------------
	# Saved standing on a fight: the harder half of resuming — the map has to put
	# the combat screen back up rather than sit on "Fighting…".
	var saved := Campaign.new(assembled, 11)
	for i in saved.options().size():
		if saved.options()[i]["kind"] == "combat":
			saved.enter(i)
			break
	CampaignSave.save(saved)
	main.show_title()
	await process_frame
	press("Resume the last run")
	await process_frame
	await process_frame
	var resumed = find_node(main, "res://scenes/campaign/campaign.gd")
	if resumed == null:
		fail("Resume did not open the campaign map")
	elif resumed.run.stage != saved.stage or resumed.run.node.get("id", "") != saved.node.get("id", ""):
		fail("Resume did not restore the saved run's position")
	elif resumed._combat == null:
		fail("resuming mid-fight did not put the combat screen back up")

	CampaignSave.clear()
	WorldSave.clear()
	CharacterSave.delete(SLUG)
	CharacterSave.delete(SLUG2)
	_done()

func _text_on_screen(needle: String, node: Node = null) -> bool:
	var n: Node = node if node else main
	if (n is Label or n is RichTextLabel or n is Button) and needle in n.text:
		return true
	for c in n.get_children():
		if _text_on_screen(needle, c):
			return true
	return false

func _done() -> void:
	print("drive_game: %d presses — %s" % [_presses,
		"OK" if _fail == 0 else "*** %d FAILED ***" % _fail])
	quit(1 if _fail > 0 else 0)
