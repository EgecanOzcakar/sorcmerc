# T17 — headless player for the whole game, from the entry scene: title → new run
# → make a character → begin → the campaign map → retire → run summary → hub.
# Presses real buttons on the real scenes; the fighting itself is drive_ui's and
# drive_campaign's job, so this walk retires instead of playing the road out.
#   godot --headless --path . -s tests/drive_game.gd
extends SceneTree

const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const CharacterSave = preload("res://core/character_save.gd")

const SLUG := "drive-gamesworth"

var main
var _presses := 0
var _fail := 0

func _init() -> void:
	OS.set_environment("SORCMERC_FAST", "1")
	CampaignSave.clear()                 # a saved run would change the title screen
	CharacterSave.delete(SLUG)           # and a leftover from an earlier walk
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
	press("New run")
	await process_frame

	# --- party setup ------------------------------------------------------
	var party_screen = find_node(main, "res://scenes/party/party.gd")
	if party_screen == null:
		fail("New run did not open the party screen")
		return _done()

	# An empty active party must not be able to start a run.
	var was: Array = Array(party_screen.party.active)
	party_screen.party.active.clear()
	press("Begin the run")
	await process_frame
	if find_node(main, "res://scenes/campaign/campaign.gd") != null:
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

	# --- into the run -----------------------------------------------------
	# The party screen is freed the moment the campaign replaces it, so hold on
	# to the assembled party itself, not the screen.
	var assembled = party_screen.party
	press("Begin the run")
	await process_frame
	await process_frame
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
	if not _text_on_screen("R E T I R E D"):
		fail("the summary does not name the end state")
	if not _text_on_screen("Carried home"):
		fail("the summary has no loot line")

	# --- back to the hub --------------------------------------------------
	press("Back to the hub")
	await process_frame
	if not buttons(main).any(func(b): return "New run" in b.text):
		fail("the summary did not return to the title screen")
	if not _text_on_screen("S O R C M E R C"):
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
	CharacterSave.delete(SLUG)
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
