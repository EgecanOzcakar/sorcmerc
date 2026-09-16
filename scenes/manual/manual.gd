# The Field Manual overlay: a searchable index of core/manual.gd's pages on the
# left, the open page on the right. Same shape as the settings overlay —
# Manual.toggle(host) opens it over any screen (title, world, campaign, a
# fight) or closes the one that is up. Esc closes; typing goes to the search box.
extends Control

const Manual = preload("res://core/manual.gd")
const Icons = preload("res://core/ui_icons.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Ach = preload("res://core/achievements.gd")

var _search := LineEdit.new()
var _list := VBoxContainer.new()
var _title := Label.new()
var _body := RichTextLabel.new()
var _open := ""      # page id showing on the right

static func toggle(host: Control, page_id := ""):
	var open = host.get_node_or_null("ManualOverlay")
	if open != null:
		open.queue_free()
		return null
	var o = load("res://scenes/manual/manual.tscn").instantiate()
	o.name = "ManualOverlay"
	host.add_child(o)
	if page_id != "":
		o.show_page(page_id)
	return o

func _ready() -> void:
	Ach.unlock("read_manual")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Creator.dark_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP   # the screen underneath sleeps while we're up

	var dim := ColorRect.new()
	dim.color = Color(Icons.COL_BG.r, Icons.COL_BG.g, Icons.COL_BG.b, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 0, 20, 16))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48; panel.offset_top = 32; panel.offset_right = -48; panel.offset_bottom = -32
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var cap := Label.new()
	cap.text = "Field manual"
	cap.theme_type_variation = "Title"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.theme_type_variation = "Quiet"
	close.pressed.connect(queue_free)
	head.add_child(close)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	# left: search + index
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	_search.placeholder_text = "Search — prone, concentration, sneak attack…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_list())
	left.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	# right: the page
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	_title.theme_type_variation = "Head"
	right.add_child(_title)
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_color_override("default_color", Icons.COL_TEXT)
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.add_theme_stylebox_override("normal", Icons.box(Icons.COL_INK, Color(0, 0, 0, 0), 0, 16, 12))
	right.add_child(_body)

	_refresh_list()
	if _open == "":
		show_page("turn")
	_search.grab_focus()

func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var q := _search.text.strip_edges()
	var hits: Array = Manual.search(q)
	var section := ""
	for p in hits:
		if q == "" and p["section"] != section:
			section = p["section"]
			var s := Label.new()
			s.text = section
			s.theme_type_variation = "Caption"
			_list.add_child(s)
		var b := Button.new()
		b.text = p["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "Picked" if p["id"] == _open else "Quiet"
		b.pressed.connect(show_page.bind(String(p["id"])))
		_list.add_child(b)
		var snip := Manual.snippet(p, q)
		if snip != "":
			var l := Label.new()
			l.text = "  " + snip
			l.theme_type_variation = "Dim"
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(l)
	if hits.is_empty():
		var none := Label.new()
		none.text = "Nothing in the manual mentions that."
		none.theme_type_variation = "Dim"
		_list.add_child(none)
	elif q != "" and not hits.any(func(p): return p["id"] == _open):
		show_page(String(hits[0]["id"]))
	else:
		show_page(_open)   # re-render so the highlights follow the query

func show_page(id: String) -> void:
	var p := Manual.page(id)
	if p.is_empty():
		return
	_open = id
	_title.text = p["title"]
	var body: String = p["body"]
	# light up every match so a search lands the eye on the line that matters
	var q := _search.text.strip_edges()
	if q != "":
		for w in q.split(" ", false):
			body = _highlight(body, String(w))
	_body.text = body
	_body.scroll_to_line(0)
	for c in _list.get_children():
		if c is Button:
			c.theme_type_variation = "Picked" if c.text == p["title"] else "Quiet"

# Wrap case-insensitive matches of `w` that sit outside BBCode tags.
func _highlight(bb: String, w: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)(%s)(?![^\\[]*\\])" % _escape(w))
	return re.sub(bb, "[bgcolor=#3d3320][color=#f1e6cf]$1[/color][/bgcolor]", true)

static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\" else ch
	return out

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		queue_free()
		accept_event()
