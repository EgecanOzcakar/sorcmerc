# #232 — the card a road event asks on: what the company has walked into, and
# two or three things to do about it, each saying what it would take (who would
# roll it and at what, the spell that would answer it, the coin it costs).
#
#   const RoadChoiceCard = preload("res://scenes/world/road_choice_card.gd")
#   _choice_card = RoadChoiceCard.new()
#   add_child(_choice_card)
#   _choice_card.chosen.connect(_on_road_choice)        # (choice_id: String) -> void
#   _choice_card.show_event(e, RoadEvents.options(e, party, world))
#
# The question only. The answer is resolved by core/road_events.gd and reported
# on D3's own event card (scenes/world/event_card.gd), die and all — so the
# roll the player chose is shown exactly the way every roll on the road always
# has been. Built from ordinary Controls like the story card: it is a paragraph
# and some buttons, not a sheet of numbers laid out to the pixel.
#
# What it does NOT own, same split as every card on the map: the clock (the
# world screen stops it before this is shown and keeps it stopped through the
# answer's card), the outcome, and freeing itself. It cannot be dismissed
# without choosing: the road asked, and every event offers a way to decline
# ("leave it", "walk on") as one of its choices, so walking away is a choice
# the card names rather than a key that skips it.
extends Control

const Icons = preload("res://core/ui_icons.gd")

signal chosen(choice_id: String)
# D3's card's own signal, kept with one meaning here: "whatever the first offered
# choice is" — on a built-in event, "as the orders have it". It is what lets
# this card stand in the world screen's one road-card slot (`_event_card`), so
# every gate that waits on a road card waits on this one too, and a robot (or
# Enter) that waves the road's card away gets the standing orders, which is
# what waving it away always meant.
signal acknowledged()

const SCRIM := 0.78
const PANEL_W := 560.0
const MARGIN := 20.0
const ART_H := 180.0

var _emitted := false
var _e: Dictionary = {}            # the event asked, for whoever holds the card
var _buttons: Array[Button] = []   # for the robots: the real buttons, in order

func _ready() -> void:
	# Anchors AND offsets: the anchors alone leave a card added mid-frame at
	# size zero, which laid the panel out in the corner with no scrim behind it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Icons.dark_theme()

func show_event(e: Dictionary, options: Array) -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_emitted = false
	_e = e.duplicate()

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, SCRIM)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	var room: float = get_viewport_rect().size.x - MARGIN * 2.0
	panel.custom_minimum_size = Vector2(minf(PANEL_W, room) if room > 0.0 else PANEL_W, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	# The event's own picture when there is one (the same art D3's card shows).
	var art = Icons.scene_art("event-" + String(e.get("id", "")), null)
	if art != null:
		var pic := TextureRect.new()
		pic.texture = art
		pic.custom_minimum_size = Vector2(0, ART_H)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		col.add_child(pic)

	var head := Label.new()
	head.text = String(e.get("title", ""))
	head.theme_type_variation = "Head"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)
	var body := Label.new()
	body.text = String(e.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
	body.theme_type_variation = "Serif"
	col.add_child(body)
	col.add_child(HSeparator.new())

	for o in options:
		var b := Button.new()
		var hint := String(o.get("why", "")) if bool(o.get("disabled", false)) else String(o.get("hint", ""))
		b.text = String(o.get("label", "...")) + (("\n" + hint) if hint != "" else "")
		b.name = "choice_%s" % String(o.get("id", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = bool(o.get("disabled", false))
		Icons.clicks(b)
		b.pressed.connect(_emit.bind(String(o.get("id", ""))))
		col.add_child(b)
		_buttons.append(b)

	await get_tree().process_frame
	if is_instance_valid(panel):
		var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
		panel.position = (area - panel.size) * 0.5
		panel.position.x = maxf(MARGIN, panel.position.x)
		panel.position.y = maxf(MARGIN, panel.position.y)

# The choice buttons, in the order the event lists them.
func buttons() -> Array[Button]:
	return _buttons

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		accept_event()
		if not _emitted:
			_emitted = true
			acknowledged.emit()

func _emit(choice_id: String) -> void:
	if _emitted:
		return
	_emitted = true
	chosen.emit(choice_id)
