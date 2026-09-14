# The progression viewer: lifetime XP, which species and classes are open, and
# every subclass with what it still costs. Read-only — it only ever reads
# core/progression.gd, which is this machine's local profile.
#
# Nothing hooks it up yet; open it with  Progression.open(host)  or run it alone:
#   godot --path . scenes/progression/progression.tscn
extends Control

const Prog = preload("res://core/progression.gd")
const Icons = preload("res://core/ui_icons.gd")

# Open the viewer under `host`, or close it if it is already open.
static func open(host: Control):
	var already = host.get_node_or_null("ProgressionPanel")
	if already != null:
		already.queue_free()
		return null
	var o = load("res://scenes/progression/progression.tscn").instantiate()
	o.name = "ProgressionPanel"
	host.add_child(o)
	return o

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Icons.COL_PANEL
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.border_color = Icons.COL_GOLD_EDGE
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40; panel.offset_right = -40
	panel.offset_top = 30; panel.offset_bottom = -30
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = "»   P R O G R E S S I O N   «"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", Icons.COL_GOLD)
	cap.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
	col.add_child(cap)

	var tally := Label.new()
	tally.text = "%d lifetime XP" % Prog.lifetime_xp_total()
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally.add_theme_color_override("font_color", Icons.COL_MUTED)
	tally.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	col.add_child(tally)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_heading("Species"))
	for s in Prog.all_species():
		var lines := []
		for lin in s["lineages"]:
			lines.append(String(lin.get("name", lin.get("id", ""))))
		list.add_child(_card("", s["name"], s["unlocked"],
			"" if s["unlocked"] else "unlocks at %d lifetime XP (%d to go)" % [s["cost"], s["remaining"]],
			"Lineages: " + ", ".join(lines) if not lines.is_empty() else "", []))

	list.add_child(_heading("Classes"))
	for c in Prog.all_classes():
		var note := ""
		if not c["unlocked"]:
			note = "unlocks at %d lifetime XP (%d to go)" % [c["cost"], c["remaining"]]
		elif c["awaits_picks"]:
			note = "choose 2 subclasses"
		else:
			note = "%d class XP" % c["class_xp"]
		list.add_child(_card(Icons.class_glyph(c["id"]), c["name"], c["unlocked"],
			note, "", c["subclasses"]))

	var close := Button.new()
	Icons.clicks(close)
	close.text = "Close"
	close.pressed.connect(_close)
	col.add_child(close)

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Icons.FS_TITLE)
	l.add_theme_color_override("font_color", Icons.COL_GOLD)
	return l

func _card(glyph: String, title: String, unlocked: bool, note: String, sub: String,
		subclasses: Array) -> Control:
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Icons.COL_INK
	box.set_corner_radius_all(6)
	box.set_border_width_all(1)
	box.border_color = Icons.COL_GOLD_EDGE if unlocked else Icons.COL_EDGE
	box.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var mark := Label.new()
	mark.text = glyph if not glyph.is_empty() else ("★" if unlocked else "☆")
	mark.add_theme_color_override("font_color", Icons.COL_GOLD if unlocked else Icons.COL_EDGE)
	head.add_child(mark)

	var name_l := Label.new()
	name_l.text = title
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	name_l.add_theme_color_override("font_color", Icons.COL_HEAD if unlocked else Icons.COL_MUTED)
	head.add_child(name_l)

	var state := Label.new()
	state.text = note if not note.is_empty() else "Unlocked"
	state.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	state.add_theme_color_override("font_color", Icons.COL_ACCENT if unlocked else Icons.COL_EDGE)
	head.add_child(state)

	if not sub.is_empty():
		var desc := Label.new()
		desc.text = sub
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		desc.add_theme_color_override("font_color", Icons.COL_BODY if unlocked else Icons.COL_MUTED)
		col.add_child(desc)

	for s in subclasses:
		var row := Label.new()
		var tail := "free" if s["free"] else "%d class XP to go" % s["remaining"]
		row.text = "    %s %s — %s" % ["★" if s["unlocked"] else "☆", s["name"], tail]
		row.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		row.add_theme_color_override("font_color",
			Icons.COL_BODY if s["unlocked"] else Icons.COL_MUTED)
		col.add_child(row)
	return card

# Standalone (no host to return to) it just quits; nested, it closes itself.
func _close() -> void:
	if get_parent() == get_tree().root:
		get_tree().quit()
	else:
		queue_free()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		_close()
