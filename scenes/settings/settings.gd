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
const Difficulty = preload("res://core/difficulty.gd")
const Icons = preload("res://core/ui_icons.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Sound = preload("res://core/audio.gd")
const CAMPAIGN_SAVE := "res://core/campaign_save.gd"

const COL_BG := Icons.COL_BG
const COL_CARD := Icons.COL_PANEL
const COL_EDGE := Icons.COL_EDGE
const COL_GOLD := Icons.COL_GOLD
const COL_DIM := Icons.COL_MUTED

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
	panel.add_theme_stylebox_override("panel", Icons.box(COL_CARD, Icons.COL_GOLD_EDGE, 0, 24, 20))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH   # grow around the centre, not down-right
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH     # from it (T9c made the list tall)
	panel.custom_minimum_size = Vector2(380, 0)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = "Settings"
	cap.theme_type_variation = "Title"
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
	lbl.theme_type_variation = "Dim"
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

	# T9c: the BG3-shaped overlay — a preset picker and the knobs behind it.
	# Touching a knob flips the picker to Custom; picking a preset sets them all.
	var dcap := Label.new()
	dcap.text = "Encounter rules"
	dcap.theme_type_variation = "Caption"
	col.add_child(dcap)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	var plbl := Label.new()
	plbl.text = "Preset"
	plbl.theme_type_variation = "Dim"
	prow.add_child(plbl)
	_preset = OptionButton.new()
	for name in Difficulty.PRESETS.keys() + ["custom"]:
		_preset.add_item(String(name).capitalize())
	_preset.item_selected.connect(func(i: int):
		var names: Array = Difficulty.PRESETS.keys() + ["custom"]
		if names[i] != "custom":
			_s.difficulty = Difficulty.PRESETS[names[i]].duplicate()
			_apply()
			_rebuild())
	prow.add_child(_preset)
	col.add_child(prow)
	col.add_child(_knob("Enemy hit points", "foe_hp", 0.05, "×%.2f"))
	col.add_child(_knob("Enemy to-hit and spell DC", "foe_hit", 1, "%+d"))
	col.add_child(_knob("Enemy damage per hit", "foe_dmg", 1, "%+d"))
	var crits := CheckButton.new()
	crits.text = "Enemies can score critical hits"
	crits.button_pressed = bool(_s.difficulty.get("foe_crits", true))
	crits.toggled.connect(func(on: bool):
		_s.difficulty["foe_crits"] = on
		_touched())
	col.add_child(crits)
	col.add_child(_knob("Inn and camp-kit cost", "camp_cost", 0.25, "×%.2f"))
	col.add_child(_knob("Market prices", "trade_price", 0.25, "×%.2f"))
	_sync_preset()

	var wipe := Button.new()
	wipe.text = "Clear autosave"
	wipe.pressed.connect(_clear_autosave)
	col.add_child(wipe)

	_note.theme_type_variation = "Dim"
	col.add_child(_note)

	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = "Primary"
	close.pressed.connect(queue_free)
	col.add_child(close)

# T9c helpers ----------------------------------------------------------------
var _preset: OptionButton = null

func _sync_preset() -> void:
	var names: Array = Difficulty.PRESETS.keys() + ["custom"]
	_preset.selected = names.find(Difficulty.preset_of(_s.difficulty))

func _touched() -> void:
	_s.difficulty = Difficulty.clamped(_s.difficulty)
	_sync_preset()
	_apply()

func _rebuild() -> void:
	# the knobs read _s.difficulty when built, so a preset change redraws the screen
	var parent := get_parent()
	var fresh = load("res://scenes/settings/settings.tscn").instantiate()
	parent.add_child(fresh)
	queue_free()

func _knob(label: String, key: String, step: float, fmt: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label
	lbl.theme_type_variation = "Dim"
	lbl.custom_minimum_size = Vector2(220, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = float(Difficulty.RANGE[key][0])
	slider.max_value = float(Difficulty.RANGE[key][1])
	slider.step = step
	slider.value = float(_s.difficulty.get(key, Difficulty.PRESETS["balanced"][key]))
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size = Vector2(56, 0)
	val.text = fmt % (int(slider.value) if step >= 1 else slider.value)
	row.add_child(val)
	slider.value_changed.connect(func(v: float):
		_s.difficulty[key] = int(v) if step >= 1 else v
		val.text = fmt % (int(v) if step >= 1 else v)
		_touched())
	return row

# T27: one 0-100 audio slider. `on_value` gets the new value (already stepped),
# and is responsible for writing it through to settings + the bus.
func _volume_row(label: String, value: float, on_value: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.theme_type_variation = "Dim"
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
