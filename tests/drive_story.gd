# M7 — the story, in the real scene: a content pack's map and story are handed
# to scenes/world/world.tscn exactly as scenes/game/game.gd hands them over,
# the world screen polls the runtime as it runs, the beat card appears and is
# answered, the quest lands in the ordinary log, and the whole thing resumes
# from the autosave with the story where it was.
#   godot --headless --path . -s tests/drive_story.gd
extends SceneTree

const Registry = preload("res://core/mod/registry.gd")
const StoryRuntime = preload("res://core/mod/story_runtime.gd")
const WorldSave = preload("res://core/world_save.gd")
const Quest = preload("res://core/quest.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

var screen
var _fail := 0
var _pass := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_MODS_DIR", "user://nonexistent-mods")
	OS.set_environment("SORCMERC_FAST", "1")
	_run()

func step(n: int, dt := 0.1) -> void:
	for i in n:
		if screen != null and is_instance_valid(screen):
			screen._process(dt)
		await process_frame

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text and not b.disabled:
			b.pressed.emit()
			return true
	return false

func _party():
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _run() -> void:
	var pack = Registry.find("ashen-road")
	if pack == null or not pack.live():
		printerr("  FAIL: the shipped campaign is not loadable")
		quit(1)
		return
	var run = StoryRuntime.new(Registry.story_of(pack), {}, pack.id())
	screen = load("res://scenes/world/world.tscn").instantiate()
	screen.party = _party()
	screen.world = Registry.world_of(pack)
	screen.story = run
	root.add_child(screen)
	await process_frame
	screen.size = Vector2(1280, 800)
	await step(3)

	check(screen.world.settlements.size() == 4, "the pack's map is the map being played")
	check(screen._story_btn != null and screen._story_btn.visible,
		"the HUD offers the journal, because this run has a story")

	# The opening note has no lines and no choices: it must not stop the map.
	check(run.fired.has("arrival"), "the opening beat fired on its own")
	check(screen.story_card != null, "...and put its first card on screen")
	check(screen.world.clock.is_paused(), "a beat pauses the map under it")

	# The road-in note comes first; wave it away like a player would, and the
	# reeve is the next thing the chapter has to say.
	check(press(screen.story_card, "Continue"), "a note card is dismissed with one button")
	await step(3)
	check(screen.story_card != null and run.fired.has("the-reeve"),
		"the next beat comes up on its own")
	var card_text := ""
	for b in buttons(screen.story_card):
		card_text += b.text + " | "
	check("Name the price" in card_text, "the card offers the reeve's choices")

	check(press(screen.story_card, "Name the price"), "take the work")
	await step(3)
	check(run.flags.has("hired"), "the choice was applied")

	# Everything the flag unlocked now fires, one card at a time, as the map
	# runs: Oss at the gate, then the warren job itself.
	for i in 12:
		if screen.story_card != null:
			if not press(screen.story_card, "Continue"):
				press(screen.story_card, "Tell us")
		await step(2)
	check(not Quest.get_quest(screen.party, "ashen-warren").is_empty(),
		"the story's quest is in the ordinary quest log")
	var warren = null
	for l in screen.world.lairs:
		if l.id == "ash-warren":
			warren = l
	check(warren != null and warren.discovered, "the beat put the warren on the map")

	# The journal overlay reads off the same runtime.
	if screen.story_card != null:
		screen._on_story_choice("", {})
	screen._toggle_story()
	await process_frame
	check(screen._story_panel != null, "the journal opens")
	var journal := ""
	for c in _labels(screen._story_panel):
		journal += c + " | "
	check("Smoke on the Marches" in journal or "Hired" in journal,
		"...and shows what has happened so far")
	screen._close_story()
	await process_frame

	# The autosave carries the story, and a resume puts it back mid-telling.
	screen._autosave()
	var saved = WorldSave.load_latest()
	check(saved != null and not saved["story"].is_empty(), "the autosave carries the story")
	check(String(saved["story"]["pack"]) == "ashen-road", "...and which pack it belongs to")
	var resumed = StoryRuntime.new(Registry.story_of(pack), saved["story"], "ashen-road")
	check(resumed.flags.has("hired") and resumed.fired.has("the-reeve"),
		"a resumed run knows what has already happened")
	check(resumed.chapter == run.chapter, "...and which chapter it is in")

	print("drive_story: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		out.append_array(_labels(c))
	return out
