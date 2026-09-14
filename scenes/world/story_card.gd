# M7 — the card a story beat is shown on: who is speaking, what they say, what
# it did to you, and the choice if there is one.
#
#   const StoryCard = preload("res://scenes/world/story_card.gd")
#   _story_card = StoryCard.new()
#   add_child(_story_card)
#   _story_card.chosen.connect(_on_story_choice)      # (choice_id: String) -> void
#   _story_card.show_beat(run, beat, lines, world, party)
#
# Built out of ordinary Controls rather than drawn by hand like D3's event card
# and D4's approach card. Those two are drawn because they are laid out to the
# pixel around numbers the player is comparing; this is a paragraph and some
# buttons, and a VBox does that better than 400 lines of draw_string would.
#
# What it does NOT own, same split as the other two cards: the clock (the world
# screen pauses before showing it and resumes on `chosen`), the outcome (the
# runtime already applied the beat — this is the receipt), and freeing itself.
extends Control

const Icons = preload("res://core/ui_icons.gd")

# Emitted exactly once per show_beat(): the id of the choice taken, or "" when
# the player closed the card without taking one (a scene with no choices always
# emits "").
signal chosen(choice_id: String)

const SCRIM := 0.78
const PANEL_W := 560.0
const MARGIN := 20.0
const DISMISS_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]

var _emitted := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Icons.dark_theme()

func show_beat(run, beat: Dictionary, lines: Array, world, party) -> void:
	for c in get_children():
		c.queue_free()
	_emitted = false

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, SCRIM)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Icons.COL_PANEL
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.border_color = Icons.COL_GOLD_EDGE
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var speaker := String(beat.get("speaker", ""))
	var head := Label.new()
	head.text = run.story.speaker_label(speaker) if speaker != "" \
		else String(beat.get("title", run.story.title))
	head.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	head.add_theme_color_override("font_color", Icons.COL_GOLD)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)

	# With a speaker up top the beat's own title becomes the subtitle; without
	# one it was already the headline and must not be printed twice.
	var title := String(beat.get("title", ""))
	if speaker != "" and title != "":
		col.add_child(_dim(title, Icons.COL_MUTED))

	for line in beat.get("lines", []):
		var l := Label.new()
		l.text = String(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
		l.add_theme_color_override("font_color", Icons.COL_TEXT)
		col.add_child(l)

	# What firing the beat actually did: the quest it handed over, the gold, the
	# lair it put on the map. Muted, under a rule, because it is the receipt and
	# not the scene.
	if not lines.is_empty():
		col.add_child(HSeparator.new())
		for line in lines:
			col.add_child(_dim(String(line), Icons.COL_ACCENT))

	var options: Array = run.choices_for(beat, world, party)
	if options.is_empty():
		var go := Button.new()
		go.text = "Continue   (Enter)"
		Icons.clicks(go)
		go.pressed.connect(_emit.bind(""))
		col.add_child(go)
	else:
		for c in options:
			var b := Button.new()
			b.text = String(c.get("text", "..."))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			Icons.clicks(b)
			b.pressed.connect(_emit.bind(String(c.get("id", ""))))
			col.add_child(b)

	# Centred after the layout has a size to centre against.
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.position = (size - panel.size) * 0.5
		panel.position.x = maxf(MARGIN, panel.position.x)
		panel.position.y = maxf(MARGIN, panel.position.y)

func _dim(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", color)
	return l

func _emit(choice_id: String) -> void:
	if _emitted:
		return
	_emitted = true
	chosen.emit(choice_id)

# Esc/Enter dismiss the card. A card WITH choices is dismissible too: the
# runtime's contract is that nothing blocks, so walking away from an offer is
# simply not taking it.
func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode in DISMISS_KEYS:
		accept_event()
		_emit("")
