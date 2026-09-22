# The climb, drawn: twenty rungs down the left, what the selected one gives on
# the right. One widget, two screens — the level-up page opens it at the rung
# it is about to take, and the creator's class step opens it at zero so a class
# is chosen by reading where it goes rather than by its one-line blurb.
#
# It draws core/climb.gd's list and nothing else: no rules, no decisions. The
# level-up page keeps its own Confirm and its own choice widgets and puts them
# beside this; picking a rung here only changes what the right-hand panel says.
#
# Veiling is the climb's call, not this file's. A veiled rung keeps its name,
# its marks and its level — you can see Extra Attack waiting at 5 from level 1
# — but the panel will not read out what it does until you are one level away.
# That is the whole difference between a plan and a spoiler.
#
# Built programmatically, like every other screen here; climb_view.tscn only
# points at this script.
extends Control

const Climb = preload("res://core/climb.gd")
const Effects = preload("res://core/rules/effects.gd")
const Icons = preload("res://core/ui_icons.gd")

signal rung_selected(level: int)

# A mark per grant kind, for the kinds with no badge of their own yet. Features
# get real art through Icons.skill_icon(); these are the punctuation around it.
const MARKS := {
	"feature": "✦", "fork": "⚑", "asi": "◈", "pick": "◇", "pool": "◉", "num": "➤",
}
const BADGE_PX := 34

var _entries: Array = []
var _sel := 1
var _paths: Dictionary = {}     # subclass id -> name, for the fork's branches
var _taken_path := ""

var _rungs := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_stretch_ratio = 1.7
	row.add_child(scroll)
	_rungs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rungs.add_theme_constant_override("separation", 2)
	scroll.add_child(_rungs)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 0, 16, 14))
	panel.custom_minimum_size.x = 300
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(panel)
	_detail.add_theme_constant_override("separation", 6)
	panel.add_child(_detail)


# The one public call. `paths` names the branches at the fork and `taken_path`
# is the one this build walked, so the fork can light it.
func show_track(entries: Array, paths: Array = [], taken_path := "") -> void:
	_build()
	_entries = entries
	_paths = {}
	for p in paths:
		_paths[String(p["id"])] = String(p["name"])
	_taken_path = taken_path
	# Open on the rung the reader is about to take — the one piece of the track
	# they came here for — or on the first if the climb has not started.
	_sel = 1
	for e in entries:
		if e["next"]:
			_sel = int(e["level"])
	_render()


func selected() -> int:
	return _sel


func _render() -> void:
	for c in _rungs.get_children():
		_rungs.remove_child(c)
		c.queue_free()
	for e in _entries:
		_rungs.add_child(_rung(e))
	_render_detail()


func _rung(e: Dictionary) -> Control:
	var n := int(e["level"])
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size.y = 46
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func():
		_sel = n
		_render_detail()
		_mark_selected()
		rung_selected.emit(n))
	b.set_meta("level", n)
	if n == _sel:
		b.add_theme_stylebox_override("normal",
			Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 3, 8, 6))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	b.add_child(row)

	row.add_child(_badge(e))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	var name := Label.new()
	name.text = Climb.headline(e)
	name.add_theme_color_override("font_color", _ink(e))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 9)
	chips.add_theme_constant_override("v_separation", 1)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chips)
	for c in _chips(e):
		chips.add_child(c)
	return b


# The level number, and the state of the climb in one glance: filled behind
# you, gilt on the rung you are about to take, hollow above it.
func _badge(e: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Icons.COL_INK
	var fg := Icons.COL_MUTED
	if e["next"]:
		bg = Icons.COL_GOLD
		fg = Icons.COL_INK
	elif e["taken"]:
		bg = Icons.COL_ROW
		fg = Icons.COL_BODY
	p.add_theme_stylebox_override("panel",
		Icons.box(bg, Icons.COL_GOLD_EDGE if e["taken"] or e["next"] else Icons.COL_EDGE, 2, 0, 0))
	var l := Label.new()
	l.text = str(int(e["level"]))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _chips(e: Dictionary) -> Array:
	var out: Array = []
	if not e["fork"].is_empty():
		for p in e["fork"]:
			var pid := String(p["id"])
			var mine: bool = pid == _taken_path
			out.append(_chip("%s %s" % ["◆" if mine else "◇", p["name"]], mine, false))
		return out
	# The headline already names one grant; repeating it as the first chip made
	# every rung read "Expertise / ◇ Expertise".
	var named := Climb.headline(e)
	var skipped := false
	# Three bundle-choice grants all read "Starting kit"; a rogue's level 1 said
	# it three times in a row. Same label twice is one chip with a count.
	var seen: Dictionary = {}
	var order: Array = []
	for g in e["grants"]:
		if g["kind"] == "fork":
			continue
		if not skipped and String(g["label"]) == named:
			skipped = true
			continue
		var key := "%s %s" % [MARKS.get(g["kind"], "◇"), g["label"]]
		if not seen.has(key):
			order.append(key)
		seen[key] = int(seen.get(key, 0)) + 1
	for key in order:
		var n: int = seen[key]
		out.append(_chip(key if n == 1 else "%s ×%d" % [key, n],
			bool(e["taken"]), bool(e["veiled"])))
	if not e["slots"].is_empty():
		out.append(_chip("slots %s" % _slot_text(e["slots"]), bool(e["taken"]), bool(e["veiled"])))
	return out


func _chip(text: String, have: bool, veiled: bool) -> Control:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Small"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color",
		Icons.COL_GOLD if have else (Icons.COL_MUTED if veiled else Icons.COL_BODY))
	return l


func _ink(e: Dictionary) -> Color:
	if e["next"]:
		return Icons.COL_HEAD
	if e["taken"]:
		return Icons.COL_GOLD
	if e["veiled"]:
		return Icons.COL_MUTED
	return Icons.COL_BODY


func _mark_selected() -> void:
	for c in _rungs.get_children():
		if c is Button:
			if int(c.get_meta("level", 0)) == _sel:
				c.add_theme_stylebox_override("normal",
					Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 3, 8, 6))
			else:
				c.remove_theme_stylebox_override("normal")


func _entry(level: int) -> Dictionary:
	for e in _entries:
		if int(e["level"]) == level:
			return e
	return {}


func _render_detail() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var e := _entry(_sel)
	if e.is_empty():
		return

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var art := _feature_art(e)
	if art != null:
		head.add_child(art)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var t := Label.new()
	t.text = Climb.headline(e)
	t.theme_type_variation = "Head"
	t.add_theme_color_override("font_color", Icons.COL_HEAD)
	titles.add_child(t)
	var cap := Label.new()
	cap.theme_type_variation = "Caption"
	cap.text = "LEVEL %d" % int(e["level"])
	if e["next"]:
		cap.text += "  ·  NEXT"
	elif e["veiled"]:
		cap.text += "  ·  NOT YET"
	titles.add_child(cap)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size.y = 90
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = _veiled_text(e) if e["veiled"] else _open_text(e)
	_detail.add_child(body)


# A veiled rung still lists what it gives — the shape of the level is the
# planning information. What it withholds is the reading of each line.
func _veiled_text(e: Dictionary) -> String:
	var s := "[color=#8a7f6e][i]What this does is read when you get there.[/i][/color]\n\n"
	for g in e["grants"]:
		s += "  %s [color=#b9ae9b]%s[/color]\n" % [MARKS.get(g["kind"], "◇"), g["label"]]
	if not e["fork"].is_empty():
		s += "\n[color=#6fa89a]%d paths open here.[/color]\n" % e["fork"].size()
	return s


func _open_text(e: Dictionary) -> String:
	var s := ""
	for g in e["grants"]:
		s += "  %s [color=#dcd3c2]%s[/color]  [color=#8a7f6e]%s[/color]\n" % [
			MARKS.get(g["kind"], "◇"), g["label"], g["source"]]
	if not e["fork"].is_empty():
		s += "\n[color=#c9a45a]The paths:[/color]\n"
		for p in e["fork"]:
			var mine: bool = String(p["id"]) == _taken_path
			s += "  %s [color=%s]%s[/color]\n" % [
				"◆" if mine else "◇", "#c9a45a" if mine else "#8a7f6e", p["name"]]
	if not e["slots"].is_empty():
		s += "\n[color=#6fa89a]spell slots — %s[/color]\n" % _slot_text(e["slots"])
	var mech := _mechanics(e)
	if mech != "":
		s += "\n[color=#c9a45a]WHAT IT DOES[/color]\n" + mech
	elif e["grants"].is_empty() and e["slots"].is_empty() and e["fork"].is_empty():
		s += "[color=#8a7f6e][i]Hit points, and nothing else. Some levels are like that.[/i][/color]\n"
	return s


# Straight out of data/effects/features.json — the same dictionary the board
# reads. 307 of 340 features have no entry, so most rungs say nothing here and
# that is honest: the sheet lists the feature, the fight does not read it yet.
func _mechanics(e: Dictionary) -> String:
	var s := ""
	for g in e["grants"]:
		if g["kind"] != "feature":
			continue
		var m: Dictionary = Effects.feature(String(g["id"]))
		if m.is_empty():
			continue
		var bits: Array = []
		if m.has("cost"):
			var cost := String(m["cost"])
			bits.append("as a reaction" if cost == "reaction" else "%s action" % cost)
		if m.has("pool"):
			bits.append("draws on %s" % Effects.humanize(String(m["pool"])))
		if m.has("duration"):
			bits.append("lasts %s" % m["duration"])
		if m.has("resist"):
			bits.append("resists %s" % ", ".join(m["resist"]))
		if bits.is_empty():
			continue
		s += "  [color=#dcd3c2]%s[/color] — [color=#b9ae9b]%s[/color]\n" % [
			g["label"], ", ".join(bits)]
	return s


func _feature_art(e: Dictionary) -> Control:
	for g in e["grants"]:
		if g["kind"] != "feature":
			continue
		var tex: Texture2D = Icons.skill_icon({"id": String(g["id"])})
		if tex == null:
			continue
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(46, 46)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return r
	return null


static func _slot_text(slots: Array) -> String:
	var out: Array = []
	for i in slots.size():
		if int(slots[i]) > 0:
			out.append("%d×%d" % [int(slots[i]), i + 1])
	return "  ".join(out)
