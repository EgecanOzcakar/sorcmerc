# Character creator: basics -> class -> abilities -> skills/background -> equipment
# -> review. Every pick is written into the Character build state as a choice-key
# decision and the sheet is re-resolved live, so the review panel is never a
# separate model of the rules — it is core/rules/resolve.gd's output.
#
# Built programmatically (same pattern as scenes/main.gd); creator.tscn only points
# at this script. Run it directly:
#   godot --path . scenes/creator/creator.tscn
extends Control

const Character = preload("res://core/character.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const ChoicePick = preload("res://core/rules/choice_pick.gd")   # the choice model, see below
const Effects = preload("res://core/rules/effects.gd")
const Save = preload("res://core/character_save.gd")
const Ach = preload("res://core/achievements.gd")
const Presets = preload("res://core/presets.gd")
const Icons = preload("res://core/ui_icons.gd")
const Prog = preload("res://core/progression.gd")
const Leveling = preload("res://core/leveling.gd")
const Climb = preload("res://core/climb.gd")
const ManualOverlay = preload("res://scenes/manual/manual.gd")   # #103
const Traits = preload("res://core/traits.gd")   # #176

signal character_created(ch)

# --- palette (core/ui_icons.gd's) -----------------------------------------
const COL_BG := Icons.COL_BG
const COL_PANEL := Icons.COL_PANEL
const COL_GOLD := Icons.COL_GOLD
const COL_TEXT := Icons.COL_TEXT
const COL_DIM := Icons.COL_MUTED
const COL_WARN := Icons.COL_FOE

# The choice model's constants, which live in core/rules/choice_pick.gd now.
const ABILS := ChoicePick.ABILS
const ABIL_NAME := ChoicePick.ABIL_NAME
const STANDARD_ARRAY := ChoicePick.STANDARD_ARRAY
const PB_COST := ChoicePick.PB_COST
const PB_BUDGET := ChoicePick.PB_BUDGET
const STEPS := ["Basics", "Class", "Abilities", "Skills & Background", "Equipment", "Review"]

# =========================================================================
# Choice model — static and UI-free, in core/rules/choice_pick.gd since a core
# module (core/recruits.gd) needed it. These wrappers keep Creator.* reading the
# same for this screen, scenes/creator/levelup.gd and every test.
# =========================================================================

static func pick_count(p: Dictionary) -> int: return ChoicePick.pick_count(p)
static func allows_repeat(p: Dictionary) -> bool: return ChoicePick.allows_repeat(p)
static func max_per_option(p: Dictionary) -> int: return ChoicePick.max_per_option(p)
static func options_for(p: Dictionary, sheet = null, picks: Array = []) -> Array: return ChoicePick.options_for(p, sheet, picks)
static func label_for(p: Dictionary, id: String) -> String: return ChoicePick.label_for(p, id)
static func decision_for(p: Dictionary, picks: Array) -> Dictionary: return ChoicePick.decision_for(p, picks)
static func picks_from_decision(p: Dictionary, d) -> Array: return ChoicePick.picks_from_decision(p, d)

# #191: several grants can each ask for the same kind of pick. A human's skill
# and a class's skills, a species' language and a background's, a species
# cantrip and a class's. Two lists with the same options are one choice in all
# but bookkeeping, so they show as one list whose count is the sum; the picks
# are still stored under each grant's own key (toggle_group fills the first
# one with room). Lists that only overlap stay apart, and an option picked in
# one is greyed in the others (taken_elsewhere), since the same proficiency
# twice buys nothing.
const MERGEABLE := ["skill-choice", "language-choice", "tool-choice", "spell-choice"]

# The choice points as display groups, each where its first member stood.
static func choice_groups(points: Array, sheet = null) -> Array:
	var groups: Array = []
	var by_opts := {}
	for p in points:
		if not p["type"] in MERGEABLE:
			groups.append([p])
			continue
		var ids: Array = options_for(p, sheet).map(func(o): return String(o["id"]))
		ids.sort()
		var k := "%s|%s" % [p["type"], ",".join(ids)]
		if by_opts.has(k):
			by_opts[k].append(p)
		else:
			var g: Array = [p]
			by_opts[k] = g
			groups.append(g)
	return groups

# One click on a merged list: a picked option comes off whichever grant holds
# it; a new one goes to the first grant with room; with every grant full, the
# first gives up its oldest pick, the way a single list evicts.
static func toggle_group(g: Array, picks_by_key: Dictionary, id: String) -> Dictionary:
	var out := {}
	for p in g:
		out[p["key"]] = (picks_by_key.get(p["key"], []) as Array).duplicate()
	for p in g:
		if id in out[p["key"]]:
			out[p["key"]].erase(id)
			return out
	for p in g:
		if out[p["key"]].size() < pick_count(p):
			out[p["key"]].append(id)
			return out
	var first: String = g[0]["key"]
	if not out[first].is_empty():
		out[first].remove_at(0)
	out[first].append(id)
	return out

static func taken_elsewhere(p: Dictionary, group: Array, points: Array, choices: Dictionary, sheet) -> Dictionary:
	return ChoicePick.taken_elsewhere(p, group, points, choices, sheet)
static func unbuilt(p: Dictionary) -> Dictionary: return ChoicePick.unbuilt(p)
static func toggle(p: Dictionary, picks: Array, id: String) -> Array: return ChoicePick.toggle(p, picks, id)

# T22 gate: "" when the meta-progression has this option open, otherwise the short
# line its greyed-out button wears. Costs come from core/progression.gd, never from
# here. `kind` is "species" | "class" | "subclass".
#
# This only answers "may the creator offer this to a NEW character?" — an existing
# save keeps whatever it was built with (see progression.gd's header).
static func lock_note(kind: String, id: String) -> String:
	match kind:
		"species":
			if not Prog.is_species_unlocked(id):
				return _price("lifetime XP", Prog.species_cost(id) - Prog.lifetime_xp_total())
		"class":
			if not Prog.is_class_unlocked(id):
				return _price("lifetime XP", Prog.class_cost(id) - Prog.lifetime_xp_total())
		"subclass":
			if not Prog.is_subclass_unlocked(id):
				return _price("class XP", Prog.subclass_remaining(id))
	return ""

# #200: the same gate, asked of a whole build. A preset used to skip it, so on a
# fresh profile Vera handed over the Fighter and Pike the Rogue (and the Thief)
# that the class list beside them still showed as locked. The first lock the
# build runs into is the one it wears; "" when every part of it is open.
static func build_lock_note(c) -> String:
	var note := lock_note("species", c.species_id) if c.species_id != "" else ""
	if note != "":
		return note
	var seen: Array = []
	for l in c.levels:
		var cid := String(l["class_id"])
		if cid in seen:
			continue
		seen.append(cid)
		note = lock_note("class", cid)
		if note != "":
			return note
	for d in c.choices.values():
		if d is Dictionary and d.get("type", "") == "subclass" and String(d.get("subclassId", "")) != "":
			note = lock_note("subclass", String(d["subclassId"]))
			if note != "":
				return note
	return ""

static func _price(currency: String, remaining: int) -> String:
	return "locked — %d more %s" % [remaining, currency] if remaining > 0 else "locked"

static func spell_name(id: String) -> String: return ChoicePick.spell_name(id)
static func humanize(id: String) -> String: return ChoicePick.humanize(id)

static func point_buy_cost(abilities: Dictionary) -> int: return ChoicePick.point_buy_cost(abilities)
static func recommended_array(class_id: String) -> Dictionary: return ChoicePick.recommended_array(class_id)
static func proficient_weapons(sheet) -> Array: return ChoicePick.proficient_weapons(sheet)
static func proficient_armor(sheet) -> Array: return ChoicePick.proficient_armor(sheet)

const MAX_WEAPONS := 2

# =========================================================================
# UI
# =========================================================================

var ch
# The level the finished character joins at — the active party's highest, handed
# in by scenes/party/party.gd before the creator is shown. 1 (a fresh level-1
# hero) standalone, or while the party is still empty.
var start_level := 1
var _step := 0
var _abil_mode := "array"     # array | pointbuy
var _confirmed = null         # the Character handed back
var _free_picks: Array = []   # T22: the 2 subclasses a freshly unlocked class owes

var _title := Label.new()
var _steps := HBoxContainer.new()   # #82: the outline bar — every step, the current one lit, all clickable
var _body := VBoxContainer.new()
var _summary := VBoxContainer.new()   # #81: the live sheet — tiles on top, prose under
var _back := Button.new()
var _next := Button.new()
var _status := Label.new()
var _target: Container = null   # where _head/_note/_flow append: _body, or a split's right column

func _ready() -> void:
	# Class-scope Buttons, so they cannot be armed at their declaration the way
	# the ones built inside a function are.
	Icons.clicks(_back)
	Icons.clicks(_next)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	if ch == null:
		ch = new_character()

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 12
	root.offset_right = -14; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_title.theme_type_variation = "Title"
	var head := HBoxContainer.new()
	root.add_child(head)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	# #103: the rules the build is judged by, one press away — a class's dice,
	# a skill's use, what a background buys — same overlay the fight offers.
	var manual := Button.new()
	Icons.clicks(manual)
	manual.text = "Manual  [F2]"
	manual.theme_type_variation = "Quiet"
	manual.focus_mode = Control.FOCUS_NONE
	manual.pressed.connect(func(): ManualOverlay.toggle(self))
	head.add_child(manual)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	root.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	side.theme_type_variation = "Card"
	split.add_child(side)
	_summary.add_theme_constant_override("separation", 6)
	side.add_child(_summary)

	_status.add_theme_color_override("font_color", COL_WARN)
	root.add_child(_status)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	_back.text = "Back"
	_next.theme_type_variation = "Primary"
	_back.pressed.connect(func(): _goto(_step - 1))
	nav.add_child(_back)
	_steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps.alignment = BoxContainer.ALIGNMENT_CENTER
	_steps.add_theme_constant_override("separation", 4)
	nav.add_child(_steps)
	for i in STEPS.size():
		var b := Button.new()
		Icons.clicks(b)
		b.text = "%d. %s" % [i + 1, STEPS[i]]
		b.pressed.connect(_jump.bind(i))
		_steps.add_child(b)
	_next.pressed.connect(_on_next)
	nav.add_child(_next)

	_refresh()

static func new_character():
	var c = Character.new()
	c.cname = "New Merc"
	for i in ABILS.size():
		c.base_abilities[ABILS[i]] = STANDARD_ARRAY[i]
	return c

func _build_theme() -> void:
	theme = dark_theme()

# Static so other screens (scenes/creator/levelup.gd, campaign.gd) share one copy.
static func dark_theme() -> Theme:
	return Icons.dark_theme()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F2:
		ManualOverlay.toggle(self)   # #103
		accept_event()

# --- navigation -----------------------------------------------------------

func _goto(step: int) -> void:
	_step = clampi(step, 0, STEPS.size() - 1)
	_refresh()

func _on_next() -> void:
	if _step < STEPS.size() - 1:
		_jump(_step + 1)
	else:
		_confirm()

# #82: the outline bar. Back is always free; forward runs every gate on the
# way there, and stops on the first one that says no.
func _jump(step: int) -> void:
	for i in range(_step, step):
		var why := _blocker(i)
		if why != "":
			_goto(i)
			_status.text = why
			return
	_goto(step)

func _blocker(step := _step) -> String:
	match step:
		0: return "" if ch.species_id != "" else "Pick a species first."
		1: return "" if ch.levels.size() > 0 else "Pick a class first."
		3: return "" if ch.background_id != "" else "Pick a background first."
	return ""

func _confirm() -> void:
	# #176: a hero made here was offered the pick here. A preset or a build
	# loaded from before traits picks up its background's defaults rather than
	# walking out with none.
	Traits.fill_defaults(ch)
	ch.traits_offered = true
	var sheet = ch.sheet()
	if not sheet.pending.is_empty():
		_status.text = "%d choice(s) still unmade." % sheet.pending.size()
		return
	# A new hero is a new file, always. The name is not the identity — two Aria
	# Vales are two characters — so the slug is minted against what is already in
	# the barracks rather than straight off the name, which used to write the new
	# build over the hero who happened to slugify the same way (and then lose the
	# new one too, to Party.add_member's duplicate-id guard). Minted once: press
	# Confirm twice and the second press re-saves this file, it does not fork it.
	var wanted: String = ch.id if ch.id != "" else Save.slugify(ch.cname)
	if _confirmed == null:
		ch.id = Save.unique_slug(ch.cname, ch.id)
	var path := Save.save(ch)
	# Only the first Confirm mints a character; pressing it again re-saves the
	# same file, and re-counting that would make "make 10 characters" a matter
	# of clicking one button ten times.
	if _confirmed == null:
		Ach.bump("created")
	_confirmed = ch
	_status.text = "Saved to %s" % path
	if ch.id != wanted:
		_status.text += "   —   the barracks already has someone called %s; this one is filed beside them, not over them." % ch.cname
	character_created.emit(ch)

# --- render ---------------------------------------------------------------

func _refresh() -> void:
	_target = null
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	_title.text = "%d. %s" % [_step + 1, STEPS[_step]]
	for i in _steps.get_child_count():
		_steps.get_child(i).theme_type_variation = "Picked" if i == _step else "Quiet"
	_back.disabled = _step == 0
	_next.text = "Confirm and save" if _step == STEPS.size() - 1 else "Next"
	_status.text = ""

	match _step:
		0: _build_basics()
		1: _build_class()
		2: _build_abilities()
		3: _build_choices()
		4: _build_equipment()
		5: _build_review()
	_refresh_summary()

func _refresh_summary() -> void:
	_sheet_into(_summary, false)

func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Head"
	_into().add_child(l)

func _note(text: String, col: Color = COL_DIM) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "Dim"
	if col != COL_DIM:
		l.add_theme_color_override("font_color", col)
	_into().add_child(l)

func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	_into().add_child(f)
	return f

func _into() -> Container:
	return _target if _target != null else _body

# #80: a pick with a lock on it — species, class — is a column down the left,
# the ones this profile has opened first and each group alphabetical, with a
# rule between them; what the pick means goes on the right (_target, until the
# caller puts it back). `entries` are {label, extra, on, cb, note}: `note` is
# lock_note()'s price, "" for open.
func _pick_column(entries: Array) -> void:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	_body.add_child(split)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 4)
	split.add_child(col)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	split.add_child(right)
	_target = right
	var by_name := func(a, b): return String(a.get("sort", a["label"])).naturalnocasecmp_to(String(b.get("sort", b["label"]))) < 0
	var open: Array = entries.filter(func(e): return String(e["note"]) == "")
	var locked: Array = entries.filter(func(e): return String(e["note"]) != "")
	open.sort_custom(by_name)
	locked.sort_custom(by_name)
	for e in open + locked:
		if not locked.is_empty() and e == locked[0]:
			var cap := Label.new()
			cap.text = "Locked"
			cap.theme_type_variation = "Caption"
			col.add_child(cap)
		var b := _opt(col, e["label"], e["on"], e["cb"], e["extra"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_gate(b, e["note"])

func _opt(parent: Control, label: String, on: bool, cb: Callable, extra := "") -> Button:
	var b := Button.new()
	Icons.clicks(b)
	b.text = ("● " if on else "") + label + extra
	if on:
		b.theme_type_variation = "Picked"
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

# Grey out an option the meta-progression hasn't opened, with its price. No-op on
# an empty note, so callers can pass lock_note() straight through.
func _gate(b: Button, note: String) -> void:
	if note == "":
		return
	b.disabled = true
	b.text += "   " + note

# 1. basics ---------------------------------------------------------------

func _build_basics() -> void:
	_head("Name")
	var name_edit := LineEdit.new()
	name_edit.text = ch.cname
	name_edit.custom_minimum_size = Vector2(320, 0)
	name_edit.text_changed.connect(func(t):
		ch.cname = t
		_refresh_summary())
	_body.add_child(name_edit)

	_head("Species")
	var entries: Array = []
	for s in Catalog.all("species.json"):
		var sid: String = s["id"]
		entries.append({"label": s["name"], "extra": "  (%d ft)" % int(s["speed"]),
			"on": ch.species_id == sid, "cb": func(): _set_species(sid),
			# never take away what this character already is
			"note": lock_note("species", sid) if ch.species_id != sid else ""})
	_pick_column(entries)
	if ch.species_id != "":
		var src := Catalog.species_src(ch.species_id)
		_note("Size %s · speed %d ft · languages: %s" % [src["size"], int(src["speed"]),
			", ".join(src["languages"])])
	# lineage / sub-species, when the data has one
	for p in _choice_points_of(["lineage-choice"]):
		_choice_widget(p)
	_target = null

	_head("Load a preset")
	_note("Ready to march, temperament and origin already picked — take one of them instead of building your own. A fresh run starts them at level %d."
		% PRESET_START_LEVEL)
	var pf := _flow()
	for which in Presets.ROSTER:
		var id: String = which
		var pre = _preset(id)
		var b := _opt(pf, "%s (%s %d)" % [pre.cname, humanize(pre.class_id()), pre.level()], false,
			func(): _load_preset(id))
		b.tooltip_text = preset_blurb(pre)
		_gate(b, build_lock_note(pre))
	# #104: the player's own, saved from the Review step
	var mine: Array = Save.list_presets()
	if not mine.is_empty():
		_head("Your presets")
		var mf := _flow()
		for slug in mine:
			var pre = Save.load_preset(slug)
			if pre == null:
				continue
			_gate(_opt(mf, "%s (%s %d)" % [pre.cname, humanize(pre.class_id()), pre.level()], false,
				func(): _load_user_preset(slug)), build_lock_note(pre))

func _set_species(sid: String) -> void:
	if ch.species_id == sid:
		return
	_prune_choices(ch.species_id)
	ch.species_id = sid
	ch.dirty()
	_refresh()

# The level a ready-made hero starts a run at (the owner's call, 2026-09-24).
# The presets are level-3 builds with their subclass already chosen, and level
# 3 is the heartland's top (core/regions.gd): loaded as they are, they had
# outgrown home before the first fight. Cut to 2, the subclass decision rides
# along unused and answers the level-3 choice when it comes, so a new Vera is
# still a Champion, just not yet. A custom hero still starts at 1.
const PRESET_START_LEVEL := 2

# `levels` is 3 by default so the build-lock checks, and anything else asking
# "what is this preset", see the whole build. #200: through Presets.hero(), so a
# loaded preset walks in with its temperament and origin picked — never through
# vera()/party(), which stay bare for the balance sweeps (core/presets.gd).
static func _preset(which: String, levels := 3):
	return Presets.hero(which, levels)

# #200: the preset button's tooltip — who they are, in one line.
# "Orc Barbarian (Path of the Berserker), Farmer. Wrathful, Downs-rider."
static func preset_blurb(pre) -> String:
	var cid: String = pre.class_id()
	var sub := ""
	for d in pre.choices.values():
		if d is Dictionary and d.get("type", "") == "subclass":
			sub = String(Catalog.subclass_src(String(d.get("subclassId", ""))).get("name", ""))
	var who := "%s %s%s, %s." % [String(Catalog.species_src(pre.species_id).get("name", humanize(pre.species_id))),
		String(Catalog.class_src(cid).get("name", humanize(cid))), " (%s)" % sub if sub != "" else "",
		String(Catalog.background_src(pre.background_id).get("name", humanize(pre.background_id)))]
	var picks: Array = []
	for fam in Traits.FAMILIES:
		if Traits.of(pre, fam) != "":
			picks.append(Traits.name_of(Traits.of(pre, fam)))
	return who + (" %s." % ", ".join(picks) if not picks.is_empty() else "")

func _load_preset(which: String) -> void:
	var pre = _preset(which, clampi(start_level, PRESET_START_LEVEL, 3))
	if build_lock_note(pre) != "":
		return   # the button is greyed; this is the guard behind it
	ch = pre
	# A preset starts a run at PRESET_START_LEVEL and joins a higher-level party
	# at its level. Topped up rather than rebuilt — what they already are is a real
	# build with its choices made, and only the levels above it are missing.
	Leveling.grant_levels(ch, start_level)
	_goto(STEPS.size() - 1)

func _load_user_preset(slug: String) -> void:
	var pre = Save.load_preset(slug)
	if pre == null:
		_status.text = "That preset is gone."
		return
	var locked := build_lock_note(pre)
	if locked != "":
		_status.text = "%s is %s on this profile." % [pre.cname, locked]
		return
	ch = pre
	Leveling.grant_levels(ch, start_level)
	_goto(STEPS.size() - 1)

# 2. class ----------------------------------------------------------------

func _build_class() -> void:
	_head("Class")
	if start_level > 1:
		_note("Joins at level %d to match the party, with %d XP banked. Catch-up levels are granted, not earned: none of that XP counts toward the lifetime XP that unlocks species and classes."
			% [start_level, Leveling.xp_for_level(start_level)], COL_GOLD)
	var entries: Array = []
	for c in Catalog.all("classes.json"):
		var cid: String = c["id"]
		entries.append({"label": "%s  %s" % [Icons.class_glyph(cid), c["name"]], "sort": c["name"], "extra": "  d%d" % int(c["hitDie"]),
			"on": ch.class_id() == cid, "cb": func(): _set_class(cid),
			"note": lock_note("class", cid) if ch.class_id() != cid else ""})
	_pick_column(entries)
	_build_free_picks()
	if ch.class_id() != "":
		var src := Catalog.class_src(ch.class_id())
		var q: Dictionary = src["quickBuild"]
		_head(String(src["name"]))
		_note("Leans on %s.  Hit die d%d.  Saves %s." % [
			ABIL_NAME.get(src["primaryAbility"], "?"), int(src["hitDie"]),
			", ".join(src["savingThrows"]).to_upper()], COL_TEXT)
		_note("Quick build: highest %s, then %s; %s makes a good background." % [
			", ".join(q["highestAbility"]).to_upper(), String(q["secondaryAbility"]).to_upper(),
			humanize(q["suggestedBackground"])])
		_note("Armor: %s.  Weapons: %s." % [
			", ".join(src["armorProficiencies"].map(humanize)) if src["armorProficiencies"] else "none",
			", ".join(src["weaponProficiencies"].map(humanize)) if src["weaponProficiencies"] else "none"])
		_class_climb()
	_target = null

# The whole class, 1 to 20, beside the list you are choosing from. Until now a
# class here was three lines of prose and a hit die — enough to tell a d12 from
# a d6 and nothing whatever about where the twenty levels go, which is the
# question somebody choosing one is actually asking. This is the same widget the
# level-up page carries, and deliberately so: one model, one set of rules about
# what may be read, and two screens that cannot drift apart.
#
# Opened at the level this character actually stands on, which is 0 for a fresh
# build and start_level for one joining a party mid-campaign — so a level-6
# recruit sees six rungs already taken, the same as they will after the fight.
#
# Veiling still applies, because it is computed in core/climb.gd rather than by
# each screen for itself: every rung's level, name and marks stay legible all
# the way to 20, and what a feature DOES is read out only for the level being
# taken. That is the right amount for choosing on. The question at this step is
# where a class GOES — that Extra Attack waits at 5, that the fork is at 3, that
# the rogue's back half is dense and the barbarian's is not — not what each
# thing will do on the day you get it.
func _class_climb() -> void:
	var cid: String = ch.class_id()
	if cid == "":
		return
	var taken := String(ch.sheet().subclasses.get(cid, ""))
	# In the middle column, under the prose, where _pick_column leaves _target —
	# so the page reads left to right as one sentence: which classes there are,
	# what this one is, where it goes.
	#
	# It spent a little while across the whole page instead, because at this
	# column's width a rung's chips wrap and every rung from the second down was
	# drawn over the one below it. That was never this screen's bug to route
	# around: a rung is a Button with its content anchored inside, so it was
	# 46px tall whatever was in it, and climb_view's _fit_rungs fixes it for
	# both screens. tests/test_climb_layout.gd holds it down at 520px, which is
	# narrower than this column has ever been.
	var view = load("res://scenes/creator/climb_view.tscn").instantiate()
	view.custom_minimum_size.y = 560
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_into().add_child(view)
	view.show_track(Climb.build(cid, taken, ch.level()), Climb.paths_for(cid), taken, cid)

# T22: buying a class with lifetime XP comes with 2 of its 4 subclasses, free and
# permanent. Until they are named none of the class's subclasses read as unlocked,
# so the choice lives right here, next to the class that owes it.
func _build_free_picks() -> void:
	var cid: String = ch.class_id()
	if cid == "" or not Prog.awaits_picks(cid):
		return
	_head("Free subclasses — pick 2")
	_note("%s came with 2 of its 4 subclasses. The other 2 cost %d class XP each, earned by playing it."
		% [humanize(cid), Prog.SUBCLASS_COST])
	var f := _flow()
	for s in Catalog.subclasses_of(cid):
		_opt(f, String(Catalog.subclass_src(s).get("name", humanize(s))), s in _free_picks,
			func(): _toggle_free_pick(s))
	var confirm := _opt(_flow(), "Confirm these 2 (permanent)", false, func():
		if Prog.unlock_class(cid, _free_picks):
			_free_picks.clear()
		_refresh())
	confirm.disabled = _free_picks.size() != 2

func _toggle_free_pick(sid: String) -> void:
	if sid in _free_picks:
		_free_picks.erase(sid)
	elif _free_picks.size() < 2:
		_free_picks.append(sid)
	_refresh()

func _set_class(cid: String) -> void:
	if ch.class_id() == cid:
		return
	_prune_choices(ch.class_id())
	ch.equipped.clear()
	_relevel(cid)
	_refresh()

# Builds the class out to start_level. Every level's grants arrive as pending
# choices (subclass at 3, ASI/feat at 4, more spells...), so the Skills &
# Background and Review steps ask for them exactly the way level 1's are asked
# for, and Confirm stays blocked until they are all made. The banked XP is the
# level's own cost and no more — a gift, never lifetime XP (see leveling.gd's
# grant_levels).
func _relevel(cid := "") -> void:
	var class_id: String = cid if cid != "" else ch.class_id()
	if class_id == "":
		return
	ch.levels.clear()
	ch.xp = 0
	Leveling.grant_levels(ch, start_level, class_id)

# Injected before the creator is shown (scenes/party/party.gd). Also safe later:
# the build is re-leveled in place and the screen redrawn.
func set_start_level(n: int) -> void:
	start_level = clampi(n, 1, Leveling.MAX_LEVEL)
	if ch == null or ch.class_id() == "":
		return
	_relevel()
	if is_inside_tree():
		_refresh()

# 3. abilities ------------------------------------------------------------

func _build_abilities() -> void:
	_head("Ability scores")
	var mf := _flow()
	_opt(mf, "Standard array", _abil_mode == "array", func(): _set_abil_mode("array"))
	_opt(mf, "Point buy (27)", _abil_mode == "pointbuy", func(): _set_abil_mode("pointbuy"))
	if ch.class_id() != "":
		_opt(mf, "Use quick-build recommendation", false, func(): _apply_quick_build())

	if _abil_mode == "array":
		_note("Assign 15/14/13/12/10/8. Picking a value swaps it with whoever holds it.")
	else:
		var spent := point_buy_cost(ch.base_abilities)
		_note("Spent %d of %d points. Scores 8–15 before species/background bonuses." % [spent, PB_BUDGET],
			COL_WARN if spent > PB_BUDGET else COL_DIM)

	var rec := recommended_array(ch.class_id()) if ch.class_id() != "" else {}
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for a in ABILS:
		var l := Label.new()
		var hint := ""
		if rec.has(a) and int(rec[a]) >= 14:
			hint = "  (recommended %d)" % int(rec[a])
		l.text = ABIL_NAME[a] + hint
		l.custom_minimum_size = Vector2(190, 0)
		grid.add_child(l)
		if _abil_mode == "array":
			var ob := OptionButton.new()
			for i in STANDARD_ARRAY.size():
				ob.add_item(str(STANDARD_ARRAY[i]), STANDARD_ARRAY[i])
				if STANDARD_ARRAY[i] == int(ch.base_abilities[a]):
					ob.select(i)
			ob.item_selected.connect(func(i): _assign_array(a, STANDARD_ARRAY[i]))
			grid.add_child(ob)
		else:
			var row := HBoxContainer.new()
			_opt(row, "−", false, func(): _bump(a, -1))
			var v := Label.new()
			v.text = "  %d  " % int(ch.base_abilities[a])
			row.add_child(v)
			_opt(row, "+", false, func(): _bump(a, 1))
			grid.add_child(row)
		var tot := Label.new()
		var sheet = ch.sheet()
		var t: int = int(sheet.abilities[a]["total"]) if sheet.abilities.has(a) else int(ch.base_abilities[a])
		tot.text = "→ %d (%+d)" % [t, (t - 10) / 2 if t >= 10 else int(floor((t - 10) / 2.0))]
		tot.add_theme_color_override("font_color", COL_DIM)
		grid.add_child(tot)
	_note("The → column is the score after bonuses. The background's +2/+1 is picked on the next step and lands there too.")

# Used to silently no-op outside Standard Array mode (the button looked
# broken — nothing happened, no message). It also only ever set ability
# scores, not the "recommended build" 5e's own quick-build actually means
# (array + suggested background) — both fixed: switch to array mode as
# part of the action, and apply the class's suggestedBackground too.
func _apply_quick_build() -> void:
	if ch.class_id() == "":
		return
	_abil_mode = "array"
	ch.base_abilities = recommended_array(ch.class_id())
	var bg := String(Catalog.class_src(ch.class_id()).get("quickBuild", {}).get("suggestedBackground", ""))
	if bg != "" and ch.background_id != bg:
		_prune_choices(ch.background_id)
		var prev: String = ch.background_id
		ch.background_id = bg
		Traits.fill_defaults(ch, prev)   # #176: the background's temperament and origin, until the player picks
	ch.dirty()
	_refresh()

func _set_abil_mode(m: String) -> void:
	_abil_mode = m
	if m == "array":
		ch.base_abilities = recommended_array(ch.class_id()) if ch.class_id() != "" else \
			{"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}
	else:
		for a in ABILS:
			ch.base_abilities[a] = 8
	ch.dirty()
	_refresh()

func _assign_array(ability: String, value: int) -> void:
	for a in ABILS:
		if int(ch.base_abilities[a]) == value and a != ability:
			ch.base_abilities[a] = ch.base_abilities[ability]
			break
	ch.base_abilities[ability] = value
	ch.dirty()
	_refresh()

func _bump(ability: String, d: int) -> void:
	var v := int(ch.base_abilities[ability]) + d
	if v < 8 or v > 15:
		return
	var probe: Dictionary = ch.base_abilities.duplicate()
	probe[ability] = v
	if point_buy_cost(probe) > PB_BUDGET:
		return
	ch.base_abilities = probe
	ch.dirty()
	_refresh()

# 4. skills & background --------------------------------------------------

func _build_choices() -> void:
	_head("Background")
	var f := _flow()
	for b in Catalog.all("backgrounds.json"):
		var bid: String = b["id"]
		_opt(f, b["name"], ch.background_id == bid, func(): _set_background(bid))
	if ch.background_id != "":
		var src := Catalog.background_src(ch.background_id)
		_note("Skills: %s.  Tools: %s.  Origin feat: %s." % [
			", ".join(src["skillProficiencies"].map(humanize)),
			", ".join(src["toolProficiencies"].map(humanize)) if src["toolProficiencies"] else "none",
			humanize(src["originFeat"]) if src["originFeat"] != null else "none"])
		_build_traits()

	_head("Choices")
	var pts := _choice_points_of([])
	if pts.is_empty():
		_note("Nothing to choose.")
	elif ch.sheet().pending.is_empty():
		_note("Nothing left to choose — the ones below are made and can be changed.")
	_choice_widgets(pts)

# #176: personality traits — one temperament and one origin, the background's
# pre-selected and the player's to change. What each does is spelled out under
# the row, the effects this build applies in fights marked apart from the ones
# still to come (core/traits.gd's effect_lines), so nobody picks a line of text
# believing it is a bonus.
func _build_traits() -> void:
	for fam in Traits.FAMILIES:
		_head("Temperament" if fam == "temperament" else "Origin")
		var f := _flow()
		var cur := Traits.of(ch, fam)
		for id in Traits.of_family(fam):
			var tid: String = id
			var b := _opt(f, Traits.name_of(tid), cur == tid, func(): _set_trait(fam, tid))
			b.tooltip_text = String(Traits.row(tid).get("text", ""))
		if cur != "":
			var lines: Array = Traits.effect_lines(cur).map(func(l): return String(l["text"]) + ("" if l["live"] else "  (not yet in play)"))
			_note("%s — %s\n%s" % [Traits.name_of(cur), Traits.row(cur).get("text", ""), "\n".join(lines.map(func(t): return "·  " + t))])

func _set_trait(family: String, id: String) -> void:
	if Traits.of(ch, family) == id:
		return
	Traits.set_family(ch, family, id)
	_refresh()

func _set_background(bid: String) -> void:
	if ch.background_id == bid:
		return
	_prune_choices(ch.background_id)
	var prev: String = ch.background_id
	ch.background_id = bid
	Traits.fill_defaults(ch, prev)   # #176: follows the background only where the player has not picked
	ch.dirty()
	_refresh()

# 5. equipment ------------------------------------------------------------

func _build_equipment() -> void:
	var sheet = ch.sheet()
	_head("Weapons  (pick up to %d)" % MAX_WEAPONS)
	_note("What they carry into the first fight. Packs, tools and trinkets are not on the shelf.")
	var wf := _flow()
	for wid in proficient_weapons(sheet):
		var w := Catalog.weapon(wid)
		_item_opt(wf, wid, w, "weapon", wid in ch.equipped, func(): _toggle_weapon(wid))

	_head("Armor")
	var af := _flow()
	_opt(af, "None", not _has_body_armor(), func(): _set_armor(""))
	for aid in proficient_armor(sheet):
		if aid == "shield":
			continue
		var a := Catalog.armor(aid)
		_item_opt(af, aid, a, "armor", aid in ch.equipped, func(): _set_armor(aid))
	if "shield" in proficient_armor(sheet):
		_item_opt(_flow(), "shield", Catalog.armor("shield"), "armor", "shield" in ch.equipped,
			func(): _toggle_equip("shield"))
	_note("Equipped: %s" % (", ".join(ch.equipped) if ch.equipped else "nothing"))

# T9a: gear is picked off its picture, like the inventory — the numbers are
# the hover text, the name the caption, "Picked" the same highlight _opt uses.
func _item_opt(parent: Control, iid: String, def: Dictionary, kind: String, on: bool, cb: Callable) -> Button:
	var b := Icons.item_tile(iid, Icons.item_tooltip(iid, def, kind), String(def.get("name", iid)))
	if on:
		b.theme_type_variation = "Picked"
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _has_body_armor() -> bool:
	for e in ch.equipped:
		if e != "shield" and Catalog.index("armor.json").has(e):
			return true
	return false

func _toggle_weapon(wid: String) -> void:
	if wid in ch.equipped:
		ch.equipped.erase(wid)
	else:
		var worn: Array = []
		for e in ch.equipped:
			if Catalog.index("weapons.json").has(e):
				worn.append(e)
		if worn.size() >= MAX_WEAPONS:
			ch.equipped.erase(worn[0])
		ch.equipped.append(wid)
	ch.dirty()
	_refresh()

func _set_armor(aid: String) -> void:
	for e in ch.equipped.duplicate():
		if e != "shield" and Catalog.index("armor.json").has(e):
			ch.equipped.erase(e)
	if aid != "":
		ch.equipped.append(aid)
	ch.dirty()
	_refresh()

func _toggle_equip(id: String) -> void:
	if id in ch.equipped:
		ch.equipped.erase(id)
	else:
		ch.equipped.append(id)
	ch.dirty()
	_refresh()

# 6. review ---------------------------------------------------------------

func _build_review() -> void:
	var sheet = ch.sheet()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_body.add_child(box)
	_sheet_into(box, true)
	# #104: keep the build to make again later, whoever this one becomes
	var keep := _opt(_flow(), "Save as preset", false, func():
		var path := Save.save_preset(ch)
		_status.text = ("Kept as a preset: %s — it is on the Basics page from now on." % ch.cname) if path != "" \
			else "Could not write the preset.")
	keep.tooltip_text = "Keeps this build under its name. Start a new character from it on the Basics page."
	if not sheet.choice_points.is_empty():
		_head("Unmade choices" if not sheet.pending.is_empty() else "Choices")
		_choice_widgets(_choice_points_of([]))

# --- choice widgets -------------------------------------------------------

# Every choice point the build has reached, optionally filtered to a set of types,
# in the resolver's own order — a choice keeps its place on the page whether or
# not it is made yet, so picking one never shuffles the rest under the cursor.
func _choice_points_of(types: Array) -> Array:
	return ch.sheet().choice_points.filter(func(p): return types.is_empty() or p["type"] in types)

# The points, grouped (#191): a merged group is one widget, the rest one each.
func _choice_widgets(points: Array) -> void:
	var sheet = ch.sheet()
	for g in choice_groups(points, sheet):
		_choice_widget(g[0], g, points)

func _choice_widget(p: Dictionary, group: Array = [], points: Array = []) -> void:
	if group.is_empty():
		group = [p]
	var sheet = ch.sheet()
	var picks: Array = []
	var n := 0
	var froms: Array = []
	for q in group:
		picks.append_array(picks_from_decision(q, ch.choices.get(q["key"])))
		var qn := pick_count(q)
		if q["type"] == "spell-choice":   # a pool shorter than the grant asks for all of it
			qn = mini(qn, Effects.pick_pool(q["spellList"], int(q["spellLevel"])).size())
		n += qn
		froms.append("%s %s" % [q["source"]["origin"], humanize(q["source"]["id"])])
	var decided: bool = group.all(func(q): return q.get("decided", false))
	_head("%s%s — pick %d  (%d chosen)" % ["✓ " if decided else "",
		humanize(p["type"]).replace(" choice", ""), n, picks.size()])
	_note("from %s%s" % [" + ".join(froms),
		"  ·  already chosen, click to change" if decided else ""])
	var f := _flow()
	var opts := options_for(p, sheet, picks)
	if opts.is_empty():
		_note("No options available.", COL_WARN)
	var taken: Dictionary = taken_elsewhere(p, group, points, ch.choices, sheet) if p["type"] in MERGEABLE else {}
	# Never grey a list into one it cannot finish: when too few options are
	# left, the ones already known come back (a picked-elsewhere one stays out).
	var free := opts.filter(func(o): return not taken.has(o["id"]) and not o["id"] in picks).size()
	if free < n - picks.size():
		for id in taken.keys():
			if taken[id] == "already known":
				taken.erase(id)
	# What the board does not play yet is greyed whatever the count says: there
	# is always a built option left to finish the list with (core/metamagic.gd).
	var unplayed := unbuilt(p)
	for o in opts:
		var id := String(o["id"])
		var count := picks.count(id)
		var extra := ""
		if allows_repeat(p) and count > 0:
			extra = "  +%d" % count
		var b := _opt(f, _decorate(p, id, String(o["label"])), count > 0,
			(func(): _pick_group(group, id)) if group.size() > 1 else (func(): _pick(p, id)), extra)
		if p["type"] == "spell-choice":
			b.tooltip_text = "%s spell" % humanize(Icons.spell_school(id))
		if count == 0 and taken.has(id):
			b.disabled = true
			b.tooltip_text = String(taken[id]).capitalize()
		elif count == 0 and unplayed.has(id):
			b.disabled = true
			b.tooltip_text = String(unplayed[id])

func _pick_group(group: Array, id: String) -> void:
	var by_key := {}
	for q in group:
		by_key[q["key"]] = picks_from_decision(q, ch.choices.get(q["key"]))
	var out := toggle_group(group, by_key, id)
	for q in group:
		ch.decide(q["key"], decision_for(q, out[q["key"]]))
	_refresh()

# A pick's icon, where the option has one: spells wear their school's mark.
func _decorate(p: Dictionary, id: String, label: String) -> String:
	if p["type"] == "spell-choice":
		return "%s  %s" % [Icons.school_glyph(Icons.spell_school(id)), label]
	if p["type"] == "subclass":
		return "%s  %s" % [Icons.class_glyph(ch.class_id()), label]
	return label

func _pick(p: Dictionary, id: String) -> void:
	var picks := picks_from_decision(p, ch.choices.get(p["key"]))
	ch.decide(p["key"], decision_for(p, toggle(p, picks, id)))
	_refresh()

# --- the live sheet -------------------------------------------------------

# #81: the sheet, laid out like one. A name block, the five numbers a fight
# reads first as a row of tiles, the six abilities as tiles with modifier and
# save under each, then the captioned prose (_sheet_bbcode). Built into
# `parent` fresh each time; the side panel and the Review page share it.
func _sheet_into(parent: Container, full: bool) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()
	var sheet = ch.sheet()
	var cls := humanize(ch.class_id()) if ch.class_id() != "" else "—"
	var sub := ""
	if sheet.subclasses.has(ch.class_id()):
		sub = " (%s)" % humanize(sheet.subclasses[ch.class_id()])
	var name := Label.new()
	name.text = ch.cname
	name.theme_type_variation = "Head"
	name.add_theme_color_override("font_color", COL_GOLD)
	parent.add_child(name)
	var line := Label.new()
	line.text = "%s  ·  %s %s%s  ·  level %d" % [
		humanize(ch.species_id) if ch.species_id != "" else "—",
		Icons.class_glyph(ch.class_id()), cls, sub, max(1, sheet.level)]
	line.theme_type_variation = "Dim"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(line)
	parent.add_child(_rule())
	var stats := GridContainer.new()
	stats.columns = 5
	parent.add_child(stats)
	for st in [["AC", str(sheet.ac)], ["HP", str(sheet.max_hp)],
			["Speed", "%d ft" % int(sheet.speeds.get("walk", 30))],
			["Prof.", "+%d" % sheet.proficiency_bonus], ["Init.", "%+d" % sheet.initiative]]:
		stats.add_child(_tile(st[0], [[st[1], Icons.COL_HEAD, 22]]))
	parent.add_child(_rule())
	var abils := GridContainer.new()
	abils.columns = 6
	parent.add_child(abils)
	for a in ABILS:
		var t := int(sheet.abilities[a]["total"]) if sheet.abilities.has(a) else 10
		var prof: bool = sheet.save_prof.get(a, false)
		abils.add_child(_tile(ABIL_NAME[a], [
			[str(t), Icons.COL_HEAD, 20], ["%+d" % sheet.mod(a), COL_TEXT, Icons.FS_BODY],
			[("● " if prof else "") + "%+d" % int(sheet.saves.get(a, 0)), COL_GOLD if prof else COL_DIM, Icons.FS_SMALL]]))
	var key := Label.new()
	key.text = "score · modifier · save (● proficient)"
	key.theme_type_variation = "Dim"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(key)
	parent.add_child(_rule())
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_color_override("default_color", COL_TEXT)
	r.text = _sheet_bbcode(full)
	parent.add_child(r)

# One tile of the sheet: a gilt caption over one or more values, each
# [text, colour, font size], centred.
static func _tile(caption: String, rows: Array) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	var c := Label.new()
	c.text = caption.to_upper()
	c.theme_type_variation = "Caption"
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	for row in rows:
		var l := Label.new()
		l.text = String(row[0])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", row[1])
		l.add_theme_font_size_override("font_size", int(row[2]))
		v.add_child(l)
	return v

static func _rule() -> Control:
	var h := ColorRect.new()
	h.color = Icons.COL_GOLD_EDGE
	h.custom_minimum_size = Vector2(0, 1)
	return h

# The prose half of the sheet: skills, attacks, spells, features — and on the
# Review page, everything.
func _sheet_bbcode(full: bool) -> String:
	var sheet = ch.sheet()
	var s := ""
	var sk: Array = []
	for k in sheet.skill_prof:
		if sheet.skill_prof[k] != "none":
			sk.append("%s [color=#f1e6cf]%+d[/color]%s" % [Catalog.skills().get(k, {}).get("name", k),
				int(sheet.skills[k]), " [color=#c9a45a]E[/color]" if sheet.skill_prof[k] == "expert" else ""])
	s += _cap("Skills") + "  " + (", ".join(sk) if sk else "[color=#8a7f6e]none[/color]") + "\n"
	s += _cap("Passive Perception") + "  [color=#f1e6cf]%d[/color]\n[hr color=#7a6234]\n" % sheet.passive_perception
	s += _cap("Attacks") + "\n"
	if sheet.attacks.is_empty():
		s += "[color=#8a7f6e]  none[/color]\n"
	for atk in sheet.attacks:
		s += "  %s  [color=#f1e6cf]%+d[/color]  [color=#b9ae9b]%s %s[/color]\n" % [
			atk["name"], int(atk["to_hit"]), atk["notation"], atk["damage_type"]]
	if not sheet.spellcasting.is_empty():
		var sc: Dictionary = sheet.spellcasting
		var slots: Array = []
		for i in sc.get("slots", []).size():
			if int(sc["slots"][i]) > 0:
				slots.append("L%d×%d" % [i + 1, int(sc["slots"][i])])
		s += "[hr color=#7a6234]\n" + _cap("Spellcasting") + "  %s  ·  DC [color=#f1e6cf]%d[/color]  ·  attack [color=#f1e6cf]%+d[/color]\n" % [
			String(sc["ability"]).to_upper(), int(sc["save_dc"]), int(sc["attack_bonus"])]
		s += "  slots: %s\n" % (", ".join(slots) if slots else "[color=#8a7f6e]none[/color]")
		if full:
			var known: Array = []
			for k in sc.get("cantrips", []):
				known.append(Icons.spell_bb(k, spell_name(k)))
			for k in sc.get("known", []):
				known.append(Icons.spell_bb(k["id"], spell_name(k["id"])))
			for k in sc.get("always_prepared", []):
				known.append(Icons.spell_bb(k, spell_name(k)))
			if known:
				s += "  spells: %s\n" % ", ".join(known)
	if full:
		s += "[hr color=#7a6234]\n" + _cap("Features") + "\n"
		for fid in sheet.features:
			s += "  · %s [color=#8a8478]%s[/color]\n" % [Effects.verb_label(fid), Effects.feature_source(fid)]
		if not sheet.pools.is_empty():
			s += "[hr color=#7a6234]\n" + _cap("Resources") + "\n"
			for p in sheet.pools:
				s += "  · %s ×%d\n" % [humanize(p["id"]), int(p["max"])]
		if not sheet.equipment.is_empty():
			s += "[hr color=#7a6234]\n" + _cap("Equipment") + "  %s\n" % ", ".join(ch.equipped)
	if not sheet.pending.is_empty():
		s += "[hr color=#7a6234]\n[color=#d15750][b]%d choice%s left[/b][/color]\n" % [sheet.pending.size(), "" if sheet.pending.size() == 1 else "s"]
		var kinds := {}   # the same kind twice is one line with a count, not two lines
		var order: Array = []
		for p in sheet.pending:
			var k := humanize(p["type"])
			if not kinds.has(k):
				order.append(k)
			kinds[k] = int(kinds.get(k, 0)) + 1
		for k in order:
			s += "[color=#d15750]  · %s%s[/color]\n" % [k, ("  ×%d" % kinds[k]) if kinds[k] > 1 else ""]
	if not sheet.warnings.is_empty() and full:
		s += "[hr color=#7a6234]\n[color=#c9a45a]warnings:[/color]\n"
		for w in sheet.warnings:
			s += "  %s\n" % w
	return s

# A section caption on the sheet: small, gilt, the way Icons' "Caption" type reads.
static func _cap(text: String) -> String:
	return "[font_size=13][color=#c9a45a]%s[/color][/font_size]" % text.to_upper()

# A class/species/background swap leaves that source's decisions behind; drop them
# so the old pick can't silently satisfy a same-keyed grant on the new one.
func _prune_choices(origin_id: String) -> void:
	if origin_id == "":
		return
	for k in ch.choices.keys():
		if k.split(":").size() == 4 and k.split(":")[2] == origin_id:
			ch.choices.erase(k)
	ch.dirty()
