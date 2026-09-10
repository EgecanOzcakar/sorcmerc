# The settings overlay: animation speed, default difficulty, clear autosave.
# Programmatic UI on the shared dark theme. Every control writes straight through
# to core/settings.gd and saves; `changed` fires so a live screen can re-read.
#
# Reached with  Settings.toggle(host, on_change)  — instantiates it as a child of
# `host`, or closes the one that is already open.
#
# Run standalone:  godot --path . scenes/settings/settings.tscn
extends Control

const Settings = preload("res://core/settings.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Sound = preload("res://core/audio.gd")
const CAMPAIGN_SAVE := "res://core/campaign_save.gd"

const COL_BG := Color("14161c")
const COL_CARD := Color("1b1f29")
const COL_EDGE := Color("39404f")
const COL_GOLD := Color("c8a75a")
const COL_DIM := Color("8f95a3")

signal changed

var _s
var _note := Label.new()

# Open the overlay under `host`, or close it if it is already open. Returns the
# overlay when it opened one, null when it closed it.
static func toggle(host: Control, on_change := Callable()):
	var open = host.get_node_or_null("SettingsOverlay")
	if open != null:
		open.queue_free()
		return null
	var o = load("res://scenes/settings/settings.tscn").instantiate()
	o.name = "SettingsOverlay"
	host.add_child(o)
	if on_change.is_valid():
		o.changed.connect(on_change)
	return o

func _ready() -> void:
	_s = Settings.current()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Creator.dark_theme()
	# Eat clicks/keys so the screen underneath does not react while we are open.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = COL_CARD
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.border_color = COL_EDGE
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 0)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = "»   S E T T I N G S   «"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(cap)

	var fast := CheckButton.new()
	fast.text = "Reduced animations (fast)"
	fast.button_pressed = _s.anim_speed_multiplier > 1.0
	fast.toggled.connect(func(on: bool):
		_s.anim_speed_multiplier = Settings.FAST if on else 1.0
		_apply())
	col.add_child(fast)

	col.add_child(_volume_row("Sound effects", _s.sfx_volume, func(v: float):
		_s.sfx_volume = v
		Sound.set_sfx_volume(v)
		_apply()))
	col.add_child(_volume_row("Music", _s.music_volume, func(v: float):
		_s.music_volume = v
		Sound.set_music_volume(v)
		_apply()))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "New campaign difficulty"
	lbl.add_theme_color_override("font_color", COL_DIM)
	row.add_child(lbl)
	var pick := OptionButton.new()
	for d in Settings.DIFFICULTIES:
		pick.add_item(d.capitalize())
	pick.selected = Settings.DIFFICULTIES.find(_s.default_difficulty)
	pick.item_selected.connect(func(i: int):
		_s.default_difficulty = Settings.DIFFICULTIES[i]
		_apply())
	row.add_child(pick)
	col.add_child(row)

	var wipe := Button.new()
	wipe.text = "Clear autosave"
	wipe.pressed.connect(_clear_autosave)
	col.add_child(wipe)

	_note.add_theme_color_override("font_color", COL_DIM)
	_note.add_theme_font_size_override("font_size", 12)
	col.add_child(_note)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	col.add_child(close)

# T27: one 0-100 audio slider. `on_value` gets the new value (already stepped),
# and is responsible for writing it through to settings + the bus.
func _volume_row(label: String, value: float, on_value: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_color_override("font_color", COL_DIM)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = value
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var pct := Label.new()
	pct.text = "%d%%" % int(value)
	pct.custom_minimum_size = Vector2(44, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	slider.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(v)
		on_value.call(v))
	return row

func _apply() -> void:
	Settings.save_settings(_s)
	changed.emit()

# T10 owns core/campaign_save.gd and may not have landed it yet, so this stays a
# no-op with a note rather than a crash when the script (or its delete) is absent.
func _clear_autosave() -> void:
	var script = load(CAMPAIGN_SAVE) if ResourceLoader.exists(CAMPAIGN_SAVE) else null
	var names := []
	if script != null:
		for m in script.get_script_method_list():
			names.append(m["name"])
	var fn: String = "delete" if "delete" in names else ("clear" if "clear" in names else "")
	if fn == "":
		_note.text = "No autosave system yet — nothing to clear."
		return
	_note.text = "Autosave cleared." if script.call(fn) else "No autosave to clear."

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		queue_free()
