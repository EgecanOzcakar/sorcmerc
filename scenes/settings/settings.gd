# The settings overlay: language, animation speed, default difficulty, clear
# autosave.
# Programmatic UI on the shared dark theme. Every control writes straight through
# to core/settings.gd and saves; `changed` fires so a live screen can re-read.
#
# Reached with  Settings.toggle(host, on_change)  — instantiates it as a child of
# `host`, or closes the one that is already open.
#
# Run standalone:  godot --path . scenes/settings/settings.tscn
extends Control

const Settings = preload("res://core/settings.gd")
const Icons = preload("res://core/ui_icons.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Sound = preload("res://core/audio.gd")
const Loc = preload("res://core/loc.gd")
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

	# A CenterContainer rather than PRESET_CENTER: that preset moves the anchors
	# to the middle and leaves the offsets alone, so the panel hangs DOWN AND
	# RIGHT from the centre by its own size rather than sitting on it — which
	# the pace picker's extra row made plain. Same fix the quest log and the
	# settlement counter got.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Icons.box(COL_CARD, Icons.COL_GOLD_EDGE, 0, 24, 20))
	panel.custom_minimum_size = Vector2(380, 0)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var cap := Label.new()
	cap.text = Loc.t("settings.title", "Settings")
	cap.theme_type_variation = "Title"
	col.add_child(cap)

	# Language, first — it is the one control that rewrites every other label on
	# this panel, and the list itself is deliberately NOT translated: a player
	# who has landed in the wrong language has to be able to read their way out.
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	var lang_lbl := Label.new()
	lang_lbl.text = Loc.t("settings.language", "Language")
	lang_lbl.theme_type_variation = "Dim"
	lang_row.add_child(lang_lbl)
	var lang := OptionButton.new()
	lang.name = "LanguagePicker"
	for l in Loc.LANGS:
		lang.add_item(String(l["label"]))
		lang.set_item_metadata(lang.item_count - 1, String(l["id"]))
		if l["id"] == _s.language:
			lang.select(lang.item_count - 1)
	lang.item_selected.connect(func(i: int):
		_s.language = String(lang.get_item_metadata(i))
		Loc.set_lang(_s.language)
		_apply()
		# Every label already on screen was built in the old language, this one
		# included. Rebuilding the overlay is cheaper and more honest than
		# chasing each Label — and `changed` has already told the screen
		# underneath to re-read itself.
		_reopen())
	lang_row.add_child(lang)
	col.add_child(lang_row)

	# Combat pace. This was a "Reduced animations (fast)" checkbox, which is to
	# say the dial only turned one way: the fight could be made quicker and
	# never weightier. Both halves are here now, slowest first, and the note
	# under it says what the chosen one actually does.
	var pace_row := HBoxContainer.new()
	pace_row.add_theme_constant_override("separation", 8)
	var pace_lbl := Label.new()
	pace_lbl.text = Loc.t("settings.combat_pace", "Combat pace")
	pace_lbl.theme_type_variation = "Dim"
	pace_row.add_child(pace_lbl)
	var pace := OptionButton.new()
	pace.name = "PacePicker"
	for p in Settings.ANIM_PACES:
		pace.add_item(Loc.t("pace.%s" % p["id"], String(p["label"])))
		pace.set_item_metadata(pace.item_count - 1, float(p["speed"]))
		pace.set_item_tooltip(pace.item_count - 1, Loc.t("pace.%s.note" % p["id"], String(p["note"])))
	var pace_note := Label.new()
	pace_note.name = "PaceNote"
	pace_note.theme_type_variation = "Dim"
	pace_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var select_pace := func(speed: float) -> void:
		var chosen: Dictionary = Settings.pace_for(speed)
		for i in pace.item_count:
			if is_equal_approx(float(pace.get_item_metadata(i)), float(chosen["speed"])):
				pace.select(i)
				break
		pace_note.text = Loc.t("pace.%s.note" % chosen["id"], String(chosen["note"]))
	select_pace.call(_s.anim_speed_multiplier)
	pace.item_selected.connect(func(i: int):
		_s.anim_speed_multiplier = float(pace.get_item_metadata(i))
		select_pace.call(_s.anim_speed_multiplier)
		_apply())
	pace_row.add_child(pace)
	col.add_child(pace_row)
	col.add_child(pace_note)

	col.add_child(_volume_row(Loc.t("settings.sfx", "Sound effects"), _s.sfx_volume, func(v: float):
		_s.sfx_volume = v
		Sound.set_sfx_volume(v)
		_apply()))
	col.add_child(_volume_row(Loc.t("settings.music", "Music"), _s.music_volume, func(v: float):
		_s.music_volume = v
		Sound.set_music_volume(v)
		_apply()))

	# A reaction that spends a slot is a real decision, so the fight can stop and
	# let you make it. The free ones never ask either way — see core/settings.gd.
	var react := CheckButton.new()
	react.name = "ReactionPrompts"
	react.text = Loc.t("settings.reaction_prompts", "Ask before a reaction spends a slot")
	react.tooltip_text = Loc.t("settings.reaction_prompts.note",
		"Counterspell and Hellish Rebuke stop the fight and ask.\n" \
		+ "Opportunity attacks and Uncanny Dodge always fire by themselves.")
	react.button_pressed = _s.reaction_prompts
	react.toggled.connect(func(on: bool):
		_s.reaction_prompts = on
		_apply())
	col.add_child(react)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = Loc.t("settings.difficulty", "New campaign difficulty")
	lbl.theme_type_variation = "Dim"
	row.add_child(lbl)
	var pick := OptionButton.new()
	for d in Settings.DIFFICULTIES:
		pick.add_item(Loc.term("difficulty", d, d.capitalize()))
	pick.selected = Settings.DIFFICULTIES.find(_s.default_difficulty)
	pick.item_selected.connect(func(i: int):
		_s.default_difficulty = Settings.DIFFICULTIES[i]
		_apply())
	row.add_child(pick)
	col.add_child(row)

	var wipe := Button.new()
	wipe.text = Loc.t("settings.clear_autosave", "Clear autosave")
	wipe.pressed.connect(_clear_autosave)
	col.add_child(wipe)

	_note.theme_type_variation = "Dim"
	col.add_child(_note)

	var close := Button.new()
	close.text = Loc.t("common.close", "Close")
	close.theme_type_variation = "Primary"
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

# Close and reopen this overlay in place, keeping whoever was listening to
# `changed` attached. Only the language picker needs it.
func _reopen() -> void:
	var host := get_parent()
	var listeners := changed.get_connections()
	# Out of the tree NOW, not at the end of the frame: a queue_free()d child
	# still sitting there keeps its name, and Godot would rename the
	# replacement ("SettingsOverlay2") — which is what toggle() and every test
	# look the overlay up by. Same reason scenes/party/party.gd's _clear()
	# removes before it frees.
	host.remove_child(self)
	queue_free()
	var o = load("res://scenes/settings/settings.tscn").instantiate()
	o.name = "SettingsOverlay"
	host.add_child(o)
	for c in listeners:
		o.changed.connect(c["callable"])

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
		_note.text = Loc.t("settings.autosave_absent", "No autosave system yet — nothing to clear.")
		return
	_note.text = Loc.t("settings.autosave_cleared", "Autosave cleared.") if script.call(fn) \
		else Loc.t("settings.autosave_none", "No autosave to clear.")

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		accept_event()
		queue_free()
