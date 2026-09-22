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
const Effects = preload("res://core/rules/effects.gd")
const Save = preload("res://core/character_save.gd")
const Icons = preload("res://core/ui_icons.gd")
const Climb = preload("res://core/climb.gd")

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
# Co-op: a guest levels their own hero on a mirrored copy; every step made
# here is also handed to `on_step`, and the host makes the same steps on the
# real one (scenes/world/world.gd). `persist` is off there — the copy is not
# the guest's to write into their barracks.
var on_step: Callable = Callable()
var persist := true
var _before                                  # the sheet as it was before the level
# Issue #120: the choice keys that were already answered when this screen
# opened — the picks of every level before this one. They are drawn, with what
# was chosen still marked, but they are not up for reconsideration here: a
# level-up is where THIS level's choices get made, not where the feat taken at
# 4 or the background skills taken at 1 get traded in. LIVE_TYPES is the
# exception the reporter asked for and 5e grants anyway.
var _locked: Dictionary = {}
# A prepared caster's list is meant to move — RAW lets one known spell be
# swapped on level-up, and this game's casters do their real picking on the
# prepare page. So a spell choice stays editable however old it is.
const LIVE_TYPES := ["spell-choice"]
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
	_locked = {}
	for p in _before.choice_points:
		if p.get("decided", false) and not p["type"] in LIVE_TYPES:
			_locked[p["key"]] = true
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
	if on_step.is_valid():
		on_step.call({"op": "add_level"})
	_committed = true
	_render()

func _on_confirm() -> void:
	if not _committed:
		commit()
		return
	if not Leveling.can_finalize(_ch):
		_status.text = "%d choice(s) still unmade." % Leveling.pending(_ch).size()
		return
	if _ch.id != "" and persist:
		Save.save(_ch)
	finished.emit(true)

func _on_cancel() -> void:
	# Before Confirm nothing has changed; after it, the level stands and any choice
	# left unmade simply stays pending (the build is re-resolvable at any time).
	finished.emit(_committed)

func _pick(p: Dictionary, id: String) -> void:
	if _locked.has(p["key"]):   # #120: an earlier level's pick, here to be read
		return
	var picks := Creator.picks_from_decision(p, _ch.choices.get(p["key"]))
	var decision: Dictionary = Creator.decision_for(p, Creator.toggle(p, picks, id))
	Leveling.decide(_ch, p["key"], decision)
	if on_step.is_valid():
		on_step.call({"op": "decide", "key": p["key"], "decision": decision})
	_render()

# --- render ----------------------------------------------------------------

func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	var cls: String = _ch.class_id()
	if _committed:
		_title.text = "%s — level %d" % [_ch.cname, _ch.level()]
		_confirm.text = "Done"
		_cancel.text = "Close"
		_gains_panel(Leveling.gains(_before, _ch.sheet()))
		_climb_panel()
		_choices()
	else:
		_title.text = "%s — %s %d → %d" % [_ch.cname, Creator.humanize(cls),
			_ch.level(), _ch.level() + 1]
		_confirm.text = "Confirm level %d" % (_ch.level() + 1)
		_cancel.text = "Cancel"
		_gains_panel(Leveling.preview(_ch))
		_climb_panel()
	# Before the level is taken the card is the whole page, so it sits in the
	# middle of it; after, the choices follow it down from the top.
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status.text = ""

# What the level gives, one gain per line with the number set large: this is
# the good news, and it used to be four dim lines in a corner.
func _gains_panel(g: Dictionary) -> void:
	var die := int(Catalog.class_src(_ch.class_id())["hitDie"]) if _ch.class_id() != "" else 0
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _committed else Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size.x = 520
	_body.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var cap := Label.new()
	cap.text = "Level %d brings" % int(g["level"])
	cap.theme_type_variation = "Caption"
	box.add_child(cap)
	_gain(box, "+%d" % int(g["hp"]), "hit points  (average of d%d + CON)" % die)
	if int(g["proficiency_bonus"]) > 0:
		_gain(box, "+%d" % int(g["proficiency_bonus"]), "proficiency bonus")
	if String(g["subclass"]) != "":
		_gain(box, Creator.humanize(g["subclass"]), "subclass")
	for f in g["features"]:
		_gain(box, Effects.verb_label(f), "new feature")
	for st in g["styles"]:
		_gain(box, Creator.humanize(st), "fighting style")
	for p in g["pools"]:
		_gain(box, "%d → %d" % [int(p["from"]), int(p["to"])], Creator.humanize(p["id"]))
	for s in g["slots"]:
		_gain(box, "%d → %d" % [int(s["from"]), int(s["to"])], "level %d spell slots" % int(s["level"]))
	if not _committed and int(g["choices"]) > 0:
		_gain(box, str(int(g["choices"])), "choice%s to make, once you confirm" % ("" if int(g["choices"]) == 1 else "s"))

# The whole climb under the card (core/climb.gd). The card says what this level
# brings; this says where the level sits — what is behind, what is one rung up,
# and what is still veiled. Before Confirm the build is still on the old level,
# so the rung about to be taken is the one marked "next", which is exactly the
# one the card is describing.
func _climb_panel() -> void:
	var cid: String = _ch.class_id()
	if cid == "":
		return
	var taken := String(_ch.sheet().subclasses.get(cid, ""))
	var view = load("res://scenes/creator/climb_view.tscn").instantiate()
	view.custom_minimum_size.y = 430
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(view)
	view.show_track(Climb.build(cid, taken, _ch.level()), Climb.paths_for(cid), taken)


# One gain: the figure in the serif, the words after it in the dim body.
func _gain(box: VBoxContainer, figure: String, words: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var f := Label.new()
	f.text = figure
	f.theme_type_variation = "Head"
	f.custom_minimum_size.x = 120
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(f)
	var w := Label.new()
	w.text = words
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w.add_theme_color_override("font_color", COL_TEXT)
	h.add_child(w)
	box.add_child(h)

func _choices() -> void:
	var sheet = _ch.sheet()
	if Leveling.pending(_ch).is_empty():
		_head("Nothing left to choose")
	# This level's choices first, in the resolver's order (a made one keeps its
	# place and stays editable, T34). What earlier levels spent comes after,
	# under its own caption and dimmed: it is here to be read, not to be
	# waded through on the way to the one row that is actually open.
	var mine: Array = sheet.choice_points.filter(func(p): return not _locked.has(p["key"]))
	var earlier: Array = sheet.choice_points.filter(func(p): return _locked.has(p["key"]))
	for p in mine:
		_choice_row(p, sheet, false)
	if not earlier.is_empty():
		var cap := Label.new()
		cap.text = "Chosen at earlier levels"
		cap.theme_type_variation = "Caption"
		_body.add_child(cap)
		for p in earlier:
			_choice_row(p, sheet, true)

func _choice_row(p: Dictionary, sheet, locked: bool) -> void:
	var picks := Creator.picks_from_decision(p, _ch.choices.get(p["key"]))
	var n := Creator.pick_count(p)
	var src: Dictionary = p["source"]
	var kind := Creator.humanize(p["type"])
	if locked:
		var l := Label.new()   # one dim line: what, from where, and what was taken
		# "WIS +2, CHA +1", not "Wis, Wis, Cha": a repeated pick is a count.
		var counts := {}
		for id in picks:
			counts[id] = int(counts.get(id, 0)) + 1
		var taken: Array = []
		for id in counts:
			var nm: String = String(id).to_upper() if String(id).length() == 3 else Creator.humanize(id)
			var times: int = counts[id]
			taken.append(nm + (" +%d" % times if String(p["type"]).begins_with("asi") else ("  ×%d" % times if times > 1 else "")))
		l.text = "%s, from %s %s  —  %s" % [kind, src["origin"], Creator.humanize(src["id"]),
			", ".join(taken) if not taken.is_empty() else "nothing"]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", COL_DIM)
		l.set_meta("choice_key", p["key"])
		_body.add_child(l)
		return
	var done: bool = p.get("decided", false)
	_head("%s%s — pick %d" % ["✓ " if done else "", kind, n] + ("" if done else "  (%d of %d)" % [picks.size(), n]))
	_note("from %s %s%s" % [src["origin"], Creator.humanize(src["id"]),
		"  ·  chosen — click to change" if done else ""])
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	_body.add_child(f)
	var opts := Creator.options_for(p, sheet, picks)
	if opts.is_empty():
		_note("No options available.", COL_WARN)
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
		b.set_meta("choice_key", p["key"])   # which choice this answers, for tests
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
