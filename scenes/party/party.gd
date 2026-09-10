# Party manager screen — roster on the left, the active <=4 on the right,
# shared gold + stash below. Built programmatically, same palette as the
# combat screen. All state lives in core/party.gd; this only draws it.
#
# Run standalone:  godot --path . scenes/party/party.tscn
extends Control

const Party = preload("res://core/party.gd")

# Palette lifted from scenes/main.gd — kept local so the party screen doesn't
# preload the whole combat script for four colours.
const COL_BG := Color("14161c")
const COL_CARD := Color("1b1f29")
const COL_CARD_SEL := Color("2b3040")
const COL_EDGE := Color("39404f")
const COL_GOLD := Color("c8a75a")
const COL_DIM := Color("8f95a3")
const COL_PARTY := Color("5fbf6a")

var party: Party                          # injected by T5, or a demo roster
var _selected := ""                       # roster id armed for a slot click

var _roster_col := VBoxContainer.new()
var _slot_col := VBoxContainer.new()
var _hint := Label.new()
var _purse := Label.new()
var _stash := RichTextLabel.new()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	if party == null:
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
		party.add_gold(275)
		party.stash_add("potion-of-healing", 3)
		party.stash_add("rope-hempen")

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16; root.offset_top = 12
	root.offset_right = -16; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := Label.new()
	header.text = "»   T H E   P A R T Y   «"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(header)

	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", COL_DIM)
	root.add_child(_hint)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	cols.add_child(_column("R O S T E R", _roster_col, 1.4))
	cols.add_child(_column("A C T I V E   P A R T Y   (max %d)" % Party.MAX_ACTIVE, _slot_col, 1.0))

	root.add_child(_footer())
	_refresh()

# A titled, scrolling column.
func _column(title: String, body: VBoxContainer, stretch: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = stretch
	var cap := Label.new()
	cap.text = title
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", COL_GOLD)
	wrap.add_child(cap)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	wrap.add_child(scroll)
	return wrap

func _footer() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	_purse.add_theme_color_override("font_color", COL_GOLD)
	_purse.add_theme_font_size_override("font_size", 16)
	row.add_child(_purse)

	_stash.bbcode_enabled = true
	_stash.fit_content = true
	_stash.scroll_active = false
	_stash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash.add_theme_font_size_override("normal_font_size", 14)
	row.add_child(_stash)

	var create := Button.new()
	create.text = "+  Create new"
	create.pressed.connect(_on_create_new)
	row.add_child(create)
	return panel

# --- rendering ------------------------------------------------------------

func _refresh() -> void:
	for c in _roster_col.get_children():
		c.queue_free()
	for c in _slot_col.get_children():
		c.queue_free()

	for ch in party.roster:
		_roster_col.add_child(_card(party.summary(ch.id)))

	for i in Party.MAX_ACTIVE:
		if i < party.active.size():
			_slot_col.add_child(_slot(i, party.summary(party.active[i])))
		else:
			_slot_col.add_child(_slot(i, {}))

	_purse.text = "%d gp" % party.gold
	if party.stash.is_empty():
		_stash.text = "[color=#8f95a3]stash empty[/color]"
	else:
		var parts := []
		for e in party.stash:
			parts.append("%s ×%d" % [String(e["item_id"]).capitalize(), int(e["quantity"])])
		_stash.text = "[color=#c9ccd6]Stash:[/color] [color=#8f95a3]%s[/color]" % ", ".join(parts)

	if _selected == "":
		_hint.text = "Click a roster member to pick them up, then click a party slot to place or swap them."
	else:
		_hint.text = "%s selected — click a party slot to place them, or click them again to cancel." \
			% party.summary(_selected).get("name", "?")

# One roster row: summary + select/bench/profile.
func _card(sm: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var picked: bool = sm["id"] == _selected
	panel.add_theme_stylebox_override("panel",
		_box(COL_CARD_SEL if picked else COL_CARD, COL_GOLD if picked else COL_EDGE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var pick := Button.new()
	pick.text = "▣" if picked else "▢"
	pick.tooltip_text = "Select for a party slot"
	pick.pressed.connect(func(): _select(sm["id"]))
	row.add_child(pick)

	row.add_child(_summary_label(sm))

	var bench := Button.new()
	bench.text = "Bench" if sm["active"] else "To party"
	bench.disabled = not sm["active"] and party.active.size() >= Party.MAX_ACTIVE
	bench.pressed.connect(func():
		if sm["active"]: party.bench(sm["id"])
		else: party.activate(sm["id"])
		_selected = ""
		_refresh())
	row.add_child(bench)

	var prof := Button.new()
	prof.text = "View"
	prof.tooltip_text = "Open the character profile"
	prof.pressed.connect(func(): _on_view_profile(sm["id"]))
	row.add_child(prof)
	return panel

# One of the four marching-order slots. Clicking it places/swaps the selection.
func _slot(index: int, sm: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal",
		_box(COL_CARD, COL_PARTY if not sm.is_empty() else COL_EDGE))
	if sm.is_empty():
		b.text = "%d.  — empty —" % (index + 1)
		b.add_theme_color_override("font_color", COL_DIM)
	else:
		b.text = "%d.  %s   —   %s %d   ·   AC %d   ·   HP %d/%d" % [index + 1, sm["name"],
			sm["class_name"], sm["level"], sm["ac"], sm["hp"], sm["max_hp"]]
	b.pressed.connect(func(): _on_slot(index))
	return b

func _summary_label(sm: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	var name_l := Label.new()
	name_l.text = sm["name"]
	name_l.add_theme_font_size_override("font_size", 16)
	if sm["active"]:
		name_l.add_theme_color_override("font_color", COL_PARTY)
	col.add_child(name_l)
	var stats := Label.new()
	stats.text = "%s %d   ·   AC %d   ·   HP %d/%d" % [sm["class_name"], sm["level"],
		sm["ac"], sm["hp"], sm["max_hp"]]
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", COL_DIM)
	col.add_child(stats)
	return col

# --- interaction ----------------------------------------------------------

func _select(id: String) -> void:
	_selected = "" if _selected == id else id
	_refresh()

func _on_slot(index: int) -> void:
	if _selected == "":
		return
	if index < party.active.size():
		if party.is_active(_selected):
			# both in the party: reorder by exchanging slots
			var i := party.active.find(_selected)
			var other: String = party.active[index]
			party.active[index] = _selected
			party.active[i] = other
		else:
			party.swap(party.active[index], _selected)
	else:
		party.activate(_selected)
	_selected = ""
	_refresh()

func _on_create_new() -> void:
	# TODO(T1): change_scene_to_file("res://scenes/creator/creator.tscn") and add
	# the resulting Character via party.add_member(). The creator scene does not
	# exist yet.
	_hint.text = "Character creator (T1) not wired up yet."

func _on_view_profile(id: String) -> void:
	# TODO(T3): change_scene_to_file("res://scenes/profile/profile.tscn") with the
	# selected character. That scene does not exist yet — checked 2026-09-10.
	_hint.text = "Profile screen (T3) not wired up yet — %s." % party.summary(id).get("name", id)

# --- theme (mirrors scenes/main.gd's) -------------------------------------

func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = edge
	s.set_content_margin_all(10)
	return s

func _build_theme() -> void:
	var th := Theme.new()
	var mk := func(bg: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(6)
		s.content_margin_left = 10; s.content_margin_right = 10
		s.content_margin_top = 6; s.content_margin_bottom = 6
		return s
	th.set_stylebox("normal", "Button", mk.call(Color("2b3040")))
	th.set_stylebox("hover", "Button", mk.call(Color("3a4152")))
	th.set_stylebox("pressed", "Button", mk.call(Color("4a5570")))
	th.set_stylebox("disabled", "Button", mk.call(Color("22252e")))
	th.set_color("font_color", "Button", Color("e6e8ee"))
	th.set_color("font_hover_color", "Button", Color("ffffff"))
	theme = th
