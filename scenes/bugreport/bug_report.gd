# The bug reporter, as the player meets it: a title, a description, and a look
# at exactly what is going to be attached before anything leaves the machine.
#
# Reached with  BugReportOverlay.toggle(host, context)  — the same overlay shape as
# scenes/settings/settings.gd, instantiated as a child of whatever screen is up,
# or closed if it is already open. `context` is that screen saying where it is
# and what it was doing; see core/bug_report.gd's body().
#
# Pressing the gilt button opens GitHub's own new-issue form with all of this
# already in it, and the player submits there under their own account — the
# game never holds a token. core/bug_report.gd says why at length.
#
# Run standalone:  godot --path . scenes/bugreport/bug_report.tscn
extends Control

const Report = preload("res://core/bug_report.gd")
const Icons = preload("res://core/ui_icons.gd")

const COL_BG := Icons.COL_BG
const COL_CARD := Icons.COL_PANEL
const PANEL_W := 560
# The standing hint under the boxes, which clears itself once there is a
# summary — it is advice, not the outcome of a press, so it must not sit there
# under a finished report saying the report is not ready.
const HINT_NEED_TITLE := "A one-line summary is all that is required."

# What the screen told us about itself, as an ordered String -> String map.
var context: Dictionary = {}

var _title_edit: LineEdit
var _desc_edit: TextEdit
var _note: Label
var _send: Button
var _last: Dictionary = {}     # the most recent submit(), for "copy" afterwards

# Open the overlay under `host`, or close it if it is already open. Returns the
# overlay when it opened one, null when it closed it — same contract as
# SettingsOverlay.toggle, so a screen can bind either to a button the same way.
static func toggle(host: Control, screen_context := {}):
	var open = host.get_node_or_null("BugReportOverlay")
	if open != null:
		open.queue_free()
		return null
	var o = load("res://scenes/bugreport/bug_report.tscn").instantiate()
	o.name = "BugReportOverlay"
	o.context = screen_context.duplicate(true)
	host.add_child(o)
	return o

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	# Eat clicks and keys: the screen underneath must not act on a keystroke
	# meant for the description box. (In combat those are the hotkeys 1-9.)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# A CenterContainer rather than PRESET_CENTER: the panel is tall enough that
	# anchoring it by its top-left corner hangs it off the bottom of the screen,
	# and it grows again whenever the attachment fold is opened.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Icons.box(COL_CARD, Icons.COL_GOLD_EDGE, 0, 24, 20))
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = "Report a bug"
	cap.theme_type_variation = "Title"
	col.add_child(cap)

	var blurb := Label.new()
	blurb.text = "This opens GitHub with the report already written. You submit it there, under your own account, so we can reply to you."
	blurb.theme_type_variation = "Dim"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = PANEL_W
	col.add_child(blurb)
	col.add_child(_gap(4))

	col.add_child(_label("Summary"))
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "One line — what went wrong"
	_title_edit.max_length = Report.TITLE_MAX
	_title_edit.text_changed.connect(func(_t: String): _refresh_send())
	# Enter in a one-line field means "that's the title, get on with it".
	_title_edit.text_submitted.connect(func(_t: String):
		if _can_send():
			_desc_edit.grab_focus())
	col.add_child(_title_edit)

	col.add_child(_label("What happened"))
	_desc_edit = TextEdit.new()
	_desc_edit.placeholder_text = "What you were doing, what you expected, what happened instead."
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.custom_minimum_size = Vector2(PANEL_W, 108)
	col.add_child(_desc_edit)

	# Nothing is attached behind the player's back: this is the exact text,
	# folded away because it is long and on the page because it is theirs.
	var attached := _attached_preview()
	col.add_child(attached)
	col.add_child(_gap(4))

	_note = Label.new()
	_note.theme_type_variation = "Dim"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = PANEL_W
	col.add_child(_note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_send = Button.new()
	_send.text = "Open GitHub with this report"
	_send.theme_type_variation = "Primary"
	_send.pressed.connect(_submit)
	Icons.clicks(_send)
	row.add_child(_send)
	var copy := Button.new()
	copy.text = "Copy instead"
	copy.pressed.connect(_copy)
	Icons.clicks(copy)
	row.add_child(copy)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = "Quiet"
	close.pressed.connect(queue_free)
	Icons.clicks(close)
	row.add_child(close)
	col.add_child(row)

	_refresh_send()
	_title_edit.grab_focus()

# --- the attachment, shown ------------------------------------------------

# A fold, shut by default: the diagnostics are four lines of build info and up
# to two dozen breadcrumbs, which is more than a panel wants open but exactly
# what someone suspicious of "we collect some information" wants to read.
func _attached_preview() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var head := Button.new()
	head.theme_type_variation = "Quiet"
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.toggle_mode = true
	head.text = "▸  Also attached: %s" % _attached_summary()
	wrap.add_child(head)

	var detail := RichTextLabel.new()
	detail.bbcode_enabled = false
	detail.visible = false
	detail.selection_enabled = true
	detail.fit_content = false
	detail.custom_minimum_size = Vector2(PANEL_W, 136)
	detail.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	detail.add_theme_color_override("default_color", Icons.COL_MUTED)
	detail.text = _attachment_text()
	wrap.add_child(detail)

	# Re-read on every open: the world clock keeps running under the overlay, so
	# the trail can have grown since it was built. A preview of what WAS going to
	# be attached is worse than no preview.
	head.toggled.connect(func(on: bool):
		if on:
			detail.text = _attachment_text()
		detail.visible = on
		head.text = "%s  Also attached: %s" % ["▾" if on else "▸", _attached_summary()])
	return wrap

func _attached_summary() -> String:
	return "your build, this screen" + (
		", recent activity" if not Report.trail().is_empty() else "")

# The attachment on its own — everything body() would add except the player's
# own words, which are right there in the box above.
func _attachment_text() -> String:
	var lines: Array[String] = []
	for k in context:
		var v := String(context[k]).strip_edges()
		if not v.is_empty():
			lines.append("%s: %s" % [String(k), v])
	if not lines.is_empty():
		lines.append("")
	lines.append_array(Report.build_lines())
	var crumbs := Report.trail()
	if not crumbs.is_empty():
		lines.append("")
		lines.append_array(crumbs)
	return "\n".join(lines)

# --- sending --------------------------------------------------------------

func _can_send() -> bool:
	return not _title_edit.text.strip_edges().is_empty()

func _refresh_send() -> void:
	_send.disabled = not _can_send()
	if _send.disabled:
		_note.text = HINT_NEED_TITLE
	elif _note.text == HINT_NEED_TITLE:
		_note.text = ""

func _submit() -> void:
	if not _can_send():
		return
	_last = Report.submit(_title_edit.text, _desc_edit.text, context)
	if _last.get("opened", false):
		_note.text = "GitHub is open in your browser — press Submit there to file it."
	else:
		# The browser refused (a blocked popup on the web export, or no handler
		# for https). The report exists regardless; say where, and offer it.
		_note.text = "Could not open a browser. Press “Copy instead” and paste it at github.com/%s/issues/new." % Report.REPO
	var path := String(_last.get("path", ""))
	if not path.is_empty():
		_note.text += "\nA copy is saved at %s" % ProjectSettings.globalize_path(path)

func _copy() -> void:
	if not _can_send():
		_note.text = "Write a one-line summary first — it becomes the issue title."
		return
	# Rebuilt every press rather than reusing the last one: the player may have
	# kept typing since, and a copy of the report they no longer mean is worse
	# than no copy at all.
	_last = Report.submit(_title_edit.text, _desc_edit.text, context, false)
	DisplayServer.clipboard_set("%s\n\n%s" % [_last["title"], _last["body"]])
	_note.text = "Copied. Paste it at github.com/%s/issues/new" % Report.REPO
	var path := String(_last.get("path", ""))
	if not path.is_empty():
		_note.text += "\nA copy is saved at %s" % ProjectSettings.globalize_path(path)

# --- small builders -------------------------------------------------------

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Caption"
	return l

func _gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		queue_free()
