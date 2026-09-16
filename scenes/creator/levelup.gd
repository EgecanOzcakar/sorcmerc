# Level-up screen: preview what +1 grants, confirm, then answer whatever the
# resolver now lists as pending. The choice widgets are creator.gd's five static
# functions (pick_count / options_for / toggle / decision_for / picks_from_decision)
# — this scene only lays them out.
#
# Opened as a full-screen overlay by scenes/profile/profile.gd's "Level up".
# Injected, like the profile: set_character(ch), then listen for `finished`.
extends Control

const Creator = preload("res://scenes/creator/creator.gd")
const Leveling = preload("res://core/leveling.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Save = preload("res://core/character_save.gd")
const Icons = preload("res://core/ui_icons.gd")
const Loc = preload("res://core/loc.gd")

# leveled = the build actually gained a level (a cancel before Confirm leaves it false).
signal finished(leveled: bool)

const COL_BG := Creator.COL_BG
const COL_PANEL := Creator.COL_PANEL
const COL_GOLD := Creator.COL_GOLD
const COL_TEXT := Creator.COL_TEXT
const COL_DIM := Creator.COL_DIM
const COL_WARN := Creator.COL_WARN

var _ch
var _committed := false
var _before                                  # the sheet as it was before the level
var _body: VBoxContainer
var _title := Label.new()
var _status := Label.new()
var _confirm := Button.new()
var _cancel := Button.new()
var _chrome := false

func set_character(ch) -> void:
	_ch = ch
	_before = ch.sheet()
	_committed = false
	if not _chrome:
		_chrome = true
		set_anchors_preset(Control.PRESET_FULL_RECT)
		theme = Creator.dark_theme()
		var bg := ColorRect.new()
		bg.color = COL_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		_build_chrome()
	_render()

func character():
	return _ch

func _build_chrome() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 12
	root.offset_right = -14; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_title.theme_type_variation = "Title"
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_status.add_theme_color_override("font_color", COL_WARN)
	root.add_child(_status)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	_cancel.text = "Cancel"
	_cancel.pressed.connect(_on_cancel)
	Icons.clicks(_cancel)
	nav.add_child(_cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_confirm.theme_type_variation = "Primary"
	_confirm.pressed.connect(_on_confirm)
	Icons.clicks(_confirm)
	nav.add_child(_confirm)

# --- actions ---------------------------------------------------------------

# Public so tests drive the flow without pressing buttons.
func commit() -> void:
	if _committed:
		return
	# ponytail: HP is the average (leveling.AVERAGE / hp_roll -1), the spec's
	# roguelite default. Rolling is one Dice.roll away — pass it as the third arg
	# to Leveling.add_level when a mode wants the swing.
	Leveling.add_level(_ch)
	_committed = true
	_render()

func _on_confirm() -> void:
	if not _committed:
		commit()
		return
	if not Leveling.can_finalize(_ch):
		_status.text = Loc.tf("creator.unmade", "%d choice(s) still unmade.",
			[Leveling.pending(_ch).size()])
		return
	if _ch.id != "":
		Save.save(_ch)
	finished.emit(true)

func _on_cancel() -> void:
	# Before Confirm nothing has changed; after it, the level stands and any choice
	# left unmade simply stays pending (the build is re-resolvable at any time).
	finished.emit(_committed)

func _pick(p: Dictionary, id: String) -> void:
	var picks := Creator.picks_from_decision(p, _ch.choices.get(p["key"]))
	Leveling.decide(_ch, p["key"], Creator.decision_for(p, Creator.toggle(p, picks, id)))
	_render()

# --- render ----------------------------------------------------------------

func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	var cls: String = _ch.class_id()
	if _committed:
		_title.text = Loc.tf("levelup.title_done", "%s — level %d", [_ch.cname, _ch.level()])
		_confirm.text = Loc.t("common.done", "Done")
		_cancel.text = Loc.t("common.close", "Close")
		_gains_panel(Leveling.gains(_before, _ch.sheet()))
		_choices()
	else:
		_title.text = Loc.t("levelup.title", "%s — %s %d → %d") % [_ch.cname,
			String(Catalog.class_src(cls).get("name", Creator.humanize(cls))),
			_ch.level(), _ch.level() + 1]
		_confirm.text = Loc.tf("levelup.confirm", "Confirm level %d", [_ch.level() + 1])
		_cancel.text = Loc.t("common.cancel", "Cancel")
		_gains_panel(Leveling.preview(_ch))
	_status.text = ""

func _gains_panel(g: Dictionary) -> void:
	var die := int(Catalog.class_src(_ch.class_id())["hitDie"]) if _ch.class_id() != "" else 0
	_head(Loc.tf("levelup.level", "Level %d", [int(g["level"])]))
	_note(Loc.t("levelup.hp", "Hit points  +%d  (average of d%d + CON)")
		% [int(g["hp"]), die], COL_TEXT)
	if int(g["proficiency_bonus"]) > 0:
		_note(Loc.tf("levelup.pb", "Proficiency bonus  +%d",
			[int(g["proficiency_bonus"])]), COL_TEXT)
	if String(g["subclass"]) != "":
		_note(Loc.tf("levelup.subclass", "Subclass  %s",
			[String(Catalog.subclass_src(String(g["subclass"])).get("name",
				Creator.humanize(g["subclass"])))]), COL_TEXT)
	for f in g["features"]:
		_note(Loc.tf("levelup.feature", "New feature  %s", [Creator.humanize(f)]), COL_TEXT)
	for st in g["styles"]:
		_note(Loc.tf("levelup.style", "Fighting style  %s", [Creator.humanize(st)]), COL_TEXT)
	for p in g["pools"]:
		_note("%s  %d → %d" % [Creator.humanize(p["id"]), int(p["from"]), int(p["to"])], COL_TEXT)
	for s in g["slots"]:
		_note(Loc.t("levelup.slots", "Level %d spell slots  %d → %d")
			% [int(s["level"]), int(s["from"]), int(s["to"])], COL_TEXT)
	if not _committed and int(g["choices"]) > 0:
		_note(Loc.tf("levelup.choices", "%d choice(s) to make.", [int(g["choices"])]))

func _choices() -> void:
	var sheet = _ch.sheet()
	if Leveling.pending(_ch).is_empty():
		_head(Loc.t("levelup.nothing_left", "Nothing left to choose"))
	# In the resolver's order, made or not: a choice keeps its place on the page
	# (made ones stay on screen and editable, T34) rather than dropping to the
	# bottom the moment it resolves.
	for p in sheet.choice_points:
		var picks := Creator.picks_from_decision(p, _ch.choices.get(p["key"]))
		var n := Creator.pick_count(p)
		var src: Dictionary = p["source"]
		_head("%s%s" % ["✓ " if p.get("decided", false) else "",
			Loc.tf("creator.pick_head", "%s — pick %d  (%d chosen)",
				[Creator.choice_label(String(p["type"])), n, picks.size()])])
		_note("%s%s" % [Loc.tf("creator.pick_from", "from %s %s",
			[Loc.term("origin", String(src["origin"]), String(src["origin"])),
			Creator.humanize(src["id"])]),
			Loc.t("creator.already_chosen", "  ·  already chosen, click to change")
				if p.get("decided", false) else ""])
		var f := HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 6)
		f.add_theme_constant_override("v_separation", 6)
		_body.add_child(f)
		var opts := Creator.options_for(p, sheet)
		if opts.is_empty():
			_note(Loc.t("creator.no_options", "No options available."), COL_WARN)
		for o in opts:
			var count := picks.count(o["id"])
			var b := Button.new()
			Icons.clicks(b)
			b.text = ("● " if count > 0 else "") + o["label"]
			if Creator.allows_repeat(p) and count > 0:
				b.text += "  +%d" % count
			if count > 0:
				b.theme_type_variation = "Picked"
			b.pressed.connect(_pick.bind(p, o["id"]))
			f.add_child(b)

func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Head"
	_body.add_child(l)

func _note(text: String, col: Color = COL_DIM) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	_body.add_child(l)
