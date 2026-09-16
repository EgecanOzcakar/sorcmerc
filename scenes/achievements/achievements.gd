# The achievements viewer: every defined achievement, in sections, locked ones
# greyed, unlocked ones stamped with the day they were earned. Read-only — it
# only ever reads core/achievements.gd, which is this machine's local profile.
#
# Three things a row can be:
#   earned      — gilt bar, a filled star, the day it happened
#   in progress — a threshold achievement with a bar under it (31 / 100 kills)
#   hidden      — a ??? title and no description until it is earned, for the
#                 ones that would read as a to-do list ("go and lose a fight")
#
# Open it with  Achievements.open(host)  or run it alone:
#   godot --path . scenes/achievements/achievements.tscn
extends Control

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
	# The only achievement this screen earns, and it earns it before it counts
	# the rows — so the tally you are looking at already includes it.
	Ach.unlock("taking_stock")
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
	cap.text = "Achievements"
	cap.theme_type_variation = "Title"
	col.add_child(cap)

	var tally := Label.new()
	tally.text = "%d of %d earned" % [won, rows.size()]
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
	# One section per group, in GROUPS order, each headed with its own tally.
	# A group nothing is defined in draws nothing rather than an empty heading.
	for g in Ach.GROUPS:
		var mine: Array = rows.filter(func(r): return r["group"] == g["id"])
		if mine.is_empty():
			continue
		list.add_child(_heading(String(g["label"]), mine))
		for r in mine:
			list.add_child(_row(r))

	var close := Button.new()
	Icons.clicks(close)
	close.text = "Close"
	close.pressed.connect(_close)
	col.add_child(close)

# "Blood and Steel   4 / 12" — the section rule.
func _heading(label: String, rows: Array) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = label
	title.theme_type_variation = "Caption"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	head.add_child(title)

	var won := rows.filter(func(r): return r["unlocked"]).size()
	var tally := Label.new()
	tally.text = "%d / %d" % [won, rows.size()]
	tally.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	tally.add_theme_color_override("font_color", Icons.COL_MUTED)
	head.add_child(tally)
	return head

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

	# The badge (assets/generated/achievement-<id>.png), dimmed while locked;
	# the star stands in for one that has no art.
	var badge := Icons.scene_art("achievement-" + String(r.get("id", "")), null)
	if badge != null:
		var pic := TextureRect.new()
		pic.texture = badge
		pic.custom_minimum_size = Vector2(56, 56)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not r["unlocked"]:
			pic.modulate = Color(0.45, 0.45, 0.45, 0.8)
		head.add_child(pic)
	var mark := Label.new()
	mark.text = "★" if r["unlocked"] else "☆"
	mark.add_theme_color_override("font_color", Icons.COL_GOLD if r["unlocked"] else Icons.COL_EDGE)
	head.add_child(mark)

	# A hidden one keeps its own counsel until it is earned. Locked and hidden
	# is the only combination that draws the placeholder — an earned one always
	# says what it was.
	var secret: bool = r["hidden"] and not r["unlocked"]

	var title := Label.new()
	title.text = "???" if secret else r["title"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = "Head"
	if not r["unlocked"]:
		title.add_theme_color_override("font_color", Icons.COL_MUTED)
	head.add_child(title)

	var when := Label.new()
	when.text = String(r["at"]).split("T")[0] if r["unlocked"] else "Locked"
	when.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	when.add_theme_color_override("font_color", Icons.COL_ACCENT if r["unlocked"] else Icons.COL_EDGE)
	head.add_child(when)

	var desc := Label.new()
	desc.text = "Earn it and find out." if secret else r["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	desc.add_theme_color_override("font_color", Icons.COL_BODY if r["unlocked"] else Icons.COL_MUTED)
	col.add_child(desc)
	# How far along a threshold one is. Only while it is locked and not a
	# secret: "31 of 100" under something already earned is noise, and under a
	# hidden one it is half the answer.
	if int(r["goal"]) > 0 and not r["unlocked"] and not secret:
		col.add_child(_progress(int(r["have"]), int(r["goal"])))
	return card

func _progress(have: int, goal: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = have
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(160, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", Icons.box(Icons.COL_BG, Color(0, 0, 0, 0), 3, 0, 0))
	bar.add_theme_stylebox_override("fill", Icons.box(Icons.COL_GOLD_EDGE, Color(0, 0, 0, 0), 3, 0, 0))
	row.add_child(bar)

	var n := Label.new()
	n.text = "%d / %d" % [have, goal]
	n.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	n.add_theme_color_override("font_color", Icons.COL_MUTED)
	row.add_child(n)
	return row

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
