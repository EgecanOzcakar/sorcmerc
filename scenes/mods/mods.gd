# M8 — the front door of the whole content pipeline: every pack the game found,
# what state it is in, and the button that starts one.
#
# It lists three kinds of thing without treating them as three kinds of thing:
# a campaign the team shipped free, a paid DLC, and a map somebody downloaded.
# They are the same row because they are the same format — the only differences
# on screen are a status chip and, for a locked one, a line saying where it
# comes from instead of a Play button.
#
#   var screen = load("res://scenes/mods/mods.tscn").instantiate()
#   screen.on_play = func(pack): ...     # the chosen pack; the caller starts it
#   screen.on_back = show_title
#
# Standalone, for looking at what a pack author just wrote:
#   godot --path . scenes/mods/mods.tscn
extends Control

const Registry = preload("res://core/mod/registry.gd")
const Entitlement = preload("res://core/mod/entitlement.gd")
const Icons = preload("res://core/ui_icons.gd")

# Both optional: with neither set the screen is a read-only browser, which is
# exactly what running it standalone should be.
var on_play: Callable = Callable()
var on_back: Callable = Callable()

var _list: VBoxContainer
var _note: Label

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
	panel.offset_left = 40; panel.offset_right = -40
	panel.offset_top = 30; panel.offset_bottom = -30
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = "Campaigns and mods"
	cap.theme_type_variation = "Title"
	col.add_child(cap)

	_note = Label.new()
	_note.theme_type_variation = "Dim"
	col.add_child(_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	var rescan := Button.new()
	rescan.text = "↻  Rescan"
	Icons.clicks(rescan)
	rescan.pressed.connect(_rescan)
	buttons.add_child(rescan)
	var back := Button.new()
	back.text = "←  Back"
	Icons.clicks(back)
	back.pressed.connect(_back)
	buttons.add_child(back)

	refresh()

# Re-read both roots from disk: an author edits a JSON file, presses this, and
# sees what they broke without restarting the game. That loop is most of what
# makes a data-only modding API pleasant to write against.
func _rescan() -> void:
	Registry.scan(true)
	Registry.apply_data()
	refresh()

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var packs := Registry.scan()
	_note.text = "%d installed  ·  mods go in  %s" % [packs.size(), Registry.user_root()]
	if packs.is_empty():
		var none := Label.new()
		none.text = "Nothing installed. Drop a pack directory in %s." % Registry.user_root()
		none.add_theme_color_override("font_color", Icons.COL_MUTED)
		_list.add_child(none)
	for p in packs:
		_list.add_child(_row(p))

func _row(pack) -> Control:
	var m = pack.manifest
	var card := PanelContainer.new()
	var box := Icons.box(Icons.COL_INK, Color(0, 0, 0, 0), 0, 12, 8)
	box.border_color = _edge(pack)
	box.border_width_left = 3
	card.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var mark := Label.new()
	mark.text = _glyph(pack)
	mark.add_theme_color_override("font_color", _edge(pack))
	head.add_child(mark)

	var title := Label.new()
	title.text = pack.title()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = "Head"
	title.add_theme_color_override("font_color",
		Icons.COL_HEAD if pack.live() else Icons.COL_MUTED)
	head.add_child(title)

	var chip := Label.new()
	chip.text = pack.label()
	chip.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	chip.add_theme_color_override("font_color", _edge(pack))
	head.add_child(chip)

	col.add_child(_dim("%s, %s%s" % [m.kind, m.describe(),
		", official" if m.official else ""], Icons.COL_MUTED))
	if m.summary != "":
		col.add_child(_dim(m.summary, Icons.COL_BODY))

	# Everything wrong with it, in full. An author's only feedback loop is this
	# list, so a truncated error is a bug report nobody can act on.
	for e in pack.errors:
		col.add_child(_dim("✗  " + String(e), Icons.COL_FOE))
	for w in pack.warnings:
		col.add_child(_dim("!  " + String(w), Icons.COL_ACCENT))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	if pack.playable() and on_play.is_valid():
		var play := Button.new()
		play.text = "Play" if m.has_world() else "Start the story"
		play.theme_type_variation = "Primary"
		Icons.clicks(play)
		play.pressed.connect(func(): on_play.call(pack))
		row.add_child(play)

	if pack.status == "locked":
		# No purchase button: the game is not the storefront. It reads what the
		# player owns (core/mod/entitlement.gd) and says so.
		var sold := _dim("Sold separately, as %s" % m.product_id, Icons.COL_GOLD)
		sold.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # an HBox gives a wrapping label no width otherwise
		row.add_child(sold)
	elif pack.status != "broken":
		var toggle := Button.new()
		toggle.text = "Turn off" if Registry.is_enabled(m.id) else "Turn on"
		Icons.clicks(toggle)
		toggle.pressed.connect(func():
			Registry.set_enabled(m.id, not Registry.is_enabled(m.id))
			refresh())
		row.add_child(toggle)
	return card

func _glyph(pack) -> String:
	match pack.status:
		"locked": return "🔒"
		"broken": return "✗"
		"disabled": return "○"
		_: return "◆" if pack.manifest.is_paid() else "✦"

func _edge(pack) -> Color:
	match pack.status:
		"locked": return Icons.COL_GOLD
		"broken": return Icons.COL_FOE
		"disabled": return Icons.COL_EDGE
		_: return Icons.COL_GOLD_EDGE

func _dim(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "Dim"
	if color != Icons.COL_MUTED:
		l.add_theme_color_override("font_color", color)
	return l

func _back() -> void:
	if on_back.is_valid():
		on_back.call()
	elif get_parent() == get_tree().root:
		get_tree().quit()
	else:
		queue_free()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		_back()
