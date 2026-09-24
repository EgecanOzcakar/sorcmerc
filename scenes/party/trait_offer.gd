# #176 — the one-time offer to a hero from before personality traits existed.
# A save written before them loads every hero with no traits and
# `traits_offered` false (core/character_save.gd); the first time the party page
# opens with such a hero on it, this asks who they are — the same two picks the
# creator makes, the hero's background's pre-selected — once. "Keep these"
# writes them; "Leave them as they are" writes nothing; either way the hero is
# never asked again (spec §8: an offer, not a gate).
#
#   const TraitOffer = preload("res://scenes/party/trait_offer.gd")
#   var o := TraitOffer.new()
#   add_child(o)
#   o.done.connect(func(kept): ...)   # after it has written the hero; free it
#   o.offer(ch)
#
# Owns the picking and the writing to the one character. Does not own which
# hero is asked, or when (scenes/party/party.gd), or what a trait does
# (core/traits.gd).
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Traits = preload("res://core/traits.gd")

signal done(kept: bool)

const SCRIM := 0.8
const PANEL_W := 620.0

var _ch = null
var _pick := {}            # family -> id, what "Keep these" would write
var _box: VBoxContainer
var _emitted := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Icons.dark_theme()


func offer(ch) -> void:
	_ch = ch
	_emitted = false
	for fam in Traits.FAMILIES:
		_pick[fam] = Traits.default_for(String(ch.background_id), fam)
	_build()


# What "Keep these" would write, for tests and robots.
func picks() -> Dictionary:
	return _pick.duplicate()


func choose(family: String, id: String) -> void:
	if String(Traits.row(id).get("family", "")) != family:
		return
	_pick[family] = id
	_build()


func keep() -> void:
	if _emitted:
		return
	for fam in _pick:
		if String(_pick[fam]) != "":
			Traits.set_family(_ch, fam, String(_pick[fam]))
	_ch.traits_offered = true
	_emitted = true
	done.emit(true)


func leave() -> void:
	if _emitted:
		return
	_ch.traits_offered = true
	_emitted = true
	done.emit(false)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, SCRIM)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)

	var cap := Label.new()
	cap.text = "Personality traits"
	cap.theme_type_variation = "Caption"
	_box.add_child(cap)
	var head := Label.new()
	head.text = "Who is %s?" % String(_ch.cname)
	head.theme_type_variation = "Title"
	_box.add_child(head)
	_box.add_child(_para("Mercs have personality traits now: a temperament and where they come from. %s was on the road before there were any. Their background suggests the two below — keep them, change them, or leave %s as they are. You are only asked once." % [_ch.cname, _ch.cname], Icons.COL_BODY))

	for fam in Traits.FAMILIES:
		var h := Label.new()
		h.text = "Temperament" if fam == "temperament" else "Origin"
		h.theme_type_variation = "Head"
		_box.add_child(h)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		_box.add_child(flow)
		for id in Traits.of_family(fam):
			var tid: String = id
			var b := Button.new()
			Icons.clicks(b)
			var on: bool = String(_pick.get(fam, "")) == tid
			b.text = ("● " if on else "") + Traits.name_of(tid)
			if on:
				b.theme_type_variation = "Picked"
			b.tooltip_text = String(Traits.row(tid).get("text", ""))
			b.pressed.connect(func(): choose(fam, tid))
			flow.add_child(b)
		var cur := String(_pick.get(fam, ""))
		if cur != "":
			var lines: Array = Traits.effect_lines(cur).map(func(l): return "·  " + String(l["text"]) + ("" if l["live"] else "  (not yet in play)"))
			_box.add_child(_para("%s — %s\n%s" % [Traits.name_of(cur), Traits.row(cur).get("text", ""), "\n".join(lines)], Icons.COL_MUTED))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	var keep_b := Button.new()
	Icons.clicks(keep_b)
	keep_b.text = "Keep these"
	keep_b.theme_type_variation = "Primary"
	keep_b.pressed.connect(keep)
	row.add_child(keep_b)
	var leave_b := Button.new()
	Icons.clicks(leave_b)
	leave_b.text = "Leave them as they are"
	leave_b.theme_type_variation = "Quiet"
	leave_b.pressed.connect(leave)
	row.add_child(leave_b)


func _para(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 36.0, 0)
	l.add_theme_color_override("font_color", col)
	return l


# Esc is "leave them as they are" — the offer is not a gate.
func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		leave()
