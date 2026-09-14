# M7/M8 — the two screens the content pipeline added: the browser that lists
# every pack, and the card a story beat is shown on. Both are asserted on the
# nodes they actually build (labels and buttons), not on how they look.
#   godot --headless --path . -s tests/test_mod_screens.gd
extends SceneTree

const Registry = preload("res://core/mod/registry.gd")
const Entitlement = preload("res://core/mod/entitlement.gd")
const StoryCard = preload("res://scenes/world/story_card.gd")
const StoryRuntime = preload("res://core/mod/story_runtime.gd")
const Story = preload("res://core/mod/story.gd")
const WorldPack = preload("res://core/mod/world_pack.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")

const MODS_SCENE := "res://scenes/mods/mods.tscn"

var _pass := 0
var _fail := 0
var _played = null
var _choice := "-"

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_MODS_DIR", "user://nonexistent-mods")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/screens-%d" % OS.get_process_id())
	OS.set_environment("SORCMERC_UNLOCK_DLC", "")
	Entitlement.reload()
	Registry.scan(true)
	await process_frame
	await test_browser()
	await test_story_card()
	print("test_mod_screens: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func labels(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is Label:
			out += c.text + " | "
		if c is Button:
			out += c.text + " | "
		out += labels(c)
	return out

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

func test_browser() -> void:
	var screen = load(MODS_SCENE).instantiate()
	screen.on_play = func(pack): _played = pack
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280, 720)
	await process_frame
	var text := labels(screen)
	check("The Ashen Road" in text, "the browser lists the shipped campaign")
	check("Vault of the Ember Crown" in text, "...and the paid one, which is how anybody hears of it")
	check("Example — The Long Vale" in text, "...and the example map")
	check("DLC — not owned" in text, "an unowned pack says so")
	check("sorcmerc.dlc.ember-crown" in text, "...and names the thing to buy")
	check(Registry.user_root() in text, "the footer says where mods go")

	check(press(screen, "Play"), "a playable pack has a Play button")
	check(_played != null and _played.playable(),
		"pressing it hands that pack back to the caller, ready to start")
	# The locked one must not be startable at all — not greyed, not there.
	_played = null
	var play_labels := 0
	for b in buttons(screen):
		if "Play" in b.text or "Start the story" in b.text:
			play_labels += 1
	check(play_labels == 2, "only the two live packs offer a way in")

	check(press(screen, "Turn off"), "a live pack can be switched off")
	await process_frame
	check(not Registry.is_enabled("ashen-road") or not Registry.is_enabled("example-world"),
		"...and the registry remembers it")
	# Put it back: this is the real registry, and the next test run reads the
	# same file.
	Registry.set_enabled("ashen-road", true)
	Registry.set_enabled("example-world", true)
	screen.queue_free()
	await process_frame

func _run():
	var story = Story.parse({"format": "sorcmerc-story", "title": "T",
		"cast": [{"id": "a", "name": "Ann", "role": "Reeve"}],
		"chapters": [{"id": "one", "beats": [
			{"id": "open", "kind": "scene", "speaker": "a", "title": "A meeting",
			 "lines": ["The first line.", "The second line."],
			 "choices": [{"id": "yes", "text": "Agree."}, {"id": "no", "text": "Refuse."}]},
			{"id": "quiet", "kind": "scene", "lines": ["Nobody is here."]}]}]})
	return StoryRuntime.new(story, {}, "t")

func _world():
	return WorldPack.build({"format": "sorcmerc-world",
		"settlements": [{"id": "hold", "position": [0, 0], "faction": "human"}]}, "t")

func test_story_card() -> void:
	var run = _run()
	var w = _world()
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	var card = StoryCard.new()
	root.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	card.size = Vector2(1280, 720)
	card.chosen.connect(func(id): _choice = id)
	var beat: Dictionary = run.story.beat("open")
	card.show_beat(run, beat, ["+100 gp"], w, p)
	await process_frame
	await process_frame
	var text := labels(card)
	check("Ann — Reeve" in text, "the card names the speaker and their part")
	check("A meeting" in text, "...and the beat's title")
	check("The first line." in text and "The second line." in text, "every line is drawn")
	check("+100 gp" in text, "what the beat did is on the receipt")
	check("Agree." in text and "Refuse." in text, "both choices are offered")
	check(press(card, "Agree."), "a choice can be pressed")
	check(_choice == "yes", "...and it reports which")
	_choice = "-"
	card.show_beat(run, beat, [], w, p)
	await process_frame
	await process_frame
	check(press(card, "Agree."), "the card can be reused for the next beat")
	check(_choice == "yes", "...and emits again, once")

	# A scene with no choices gets one way out, and Esc is also a way out —
	# the runtime's contract is that nothing blocks.
	_choice = "-"
	card.show_beat(run, run.story.beat("quiet"), [], w, p)
	await process_frame
	await process_frame
	check(press(card, "Continue"), "a scene with no choices still has a button")
	check(_choice == "", "...and dismissing reports no choice")
	card.queue_free()
	await process_frame
