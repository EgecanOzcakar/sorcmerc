# The achievements viewer: every defined achievement, locked ones greyed, unlocked
# ones stamped with the day they were earned. Read-only — it only ever reads
# core/achievements.gd, which is this machine's local profile.
#
# Nothing hooks it up yet; open it with  Achievements.open(host)  or run it alone:
#   godot --path . scenes/achievements/achievements.tscn
extends Control

const Loc = preload("res://core/loc.gd")
const Ach = preload("res://core/achievements.gd")
const Icons = preload("res://core/ui_icons.gd")

# Open the viewer under `host`, or close it if it is already open.
static func open(host: Control):
	var already = host.get_node_or_null("AchievementsPanel")
	if already != null:
		already.queue_free()
		return null
	var o = load("res://scenes/achievements/achievements.tscn").instantiate()
	o.name = "AchievementsPanel"
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
	panel.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 0, 24, 20))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("margin_left", 0)
	panel.offset_left = 40; panel.offset_right = -40
	panel.offset_top = 30; panel.offset_bottom = -30
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var rows = Ach.all()
	var won := 0
	for r in rows:
		if r["unlocked"]:
			won += 1

	var cap := Label.new()
	cap.text = Loc.t("achievements.title", "Achievements")
	cap.theme_type_variation = "Title"
	col.add_child(cap)

	var tally := Label.new()
	tally.text = Loc.t("achievements.tally", "%d of %d earned") % [won, rows.size()]
	tally.theme_type_variation = "Dim"
	col.add_child(tally)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for r in rows:
		list.add_child(_row(r))

	var close := Button.new()
	Icons.clicks(close)
	close.text = Loc.t("common.close", "Close")
	close.pressed.connect(_close)
	col.add_child(close)

func _row(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	# A ledger row: the earned ones carry a gilt bar down the left edge, the
	# rest sit plain. No box per entry.
	var box := Icons.box(Icons.COL_INK, Color(0, 0, 0, 0), 0, 12, 8)
	box.border_color = Icons.COL_GOLD if r["unlocked"] else Icons.COL_EDGE
	box.border_width_left = 3
	card.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var mark := Label.new()
	mark.text = "★" if r["unlocked"] else "☆"
	mark.add_theme_color_override("font_color", Icons.COL_GOLD if r["unlocked"] else Icons.COL_EDGE)
	head.add_child(mark)

	var title := Label.new()
	title.text = r["title"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = "Head"
	if not r["unlocked"]:
		title.add_theme_color_override("font_color", Icons.COL_MUTED)
	head.add_child(title)

	var when := Label.new()
	when.text = String(r["at"]).split("T")[0] if r["unlocked"] \
		else Loc.t("achievements.locked", "Locked")
	when.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	when.add_theme_color_override("font_color", Icons.COL_ACCENT if r["unlocked"] else Icons.COL_EDGE)
	head.add_child(when)

	var desc := Label.new()
	desc.text = r["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	desc.add_theme_color_override("font_color", Icons.COL_BODY if r["unlocked"] else Icons.COL_MUTED)
	col.add_child(desc)
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
