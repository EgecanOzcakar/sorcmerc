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
const Effects = preload("res://core/rules/effects.gd")
const Save = preload("res://core/character_save.gd")
const Ach = preload("res://core/achievements.gd")
const Presets = preload("res://core/presets.gd")
const Icons = preload("res://core/ui_icons.gd")
const Prog = preload("res://core/progression.gd")
const Leveling = preload("res://core/leveling.gd")

signal character_created(ch)

# --- palette (core/ui_icons.gd's) -----------------------------------------
const COL_BG := Icons.COL_BG
const COL_PANEL := Icons.COL_PANEL
const COL_GOLD := Icons.COL_GOLD
const COL_TEXT := Icons.COL_TEXT
const COL_DIM := Icons.COL_MUTED
const COL_WARN := Icons.COL_FOE

const ABILS := ["str", "dex", "con", "int", "wis", "cha"]
const ABIL_NAME := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}
const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
const PB_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}   # 2024 point buy
const PB_BUDGET := 27
const STEPS := ["Basics", "Class", "Abilities", "Skills & Background", "Equipment", "Review"]

# ponytail: the export has no languages.json (SCHEMA gap) — the PHB standard list,
# hardcoded. Delete this the day F1 exports one.
const LANGUAGES := ["common", "common-sign", "draconic", "dwarvish", "elvish", "giant",
	"gnomish", "goblin", "halfling", "orc", "abyssal", "celestial", "infernal",
	"deep-speech", "primordial", "sylvan", "undercommon", "thieves-cant"]

# =========================================================================
# Choice model — static, UI-free, so tests/test_creator.gd drives the same code.
# A pending entry from the resolver becomes: N picks from a list of options,
# and a list of picks becomes a decision Dictionary for Character.decide().
# =========================================================================

static func pick_count(p: Dictionary) -> int:
	match p["type"]:
		"asi": return int(p["points"])
		"subclass", "lineage-choice", "feature-choice", "feat-choice": return 1
		_: return int(p.get("count", 1))

# asi is the only category where the same option may be picked twice (+2 to one).
static func allows_repeat(p: Dictionary) -> bool:
	return p["type"] == "asi"

static func max_per_option(p: Dictionary) -> int:
	return 2 if p["type"] == "asi" else 1

# [{id, label}] — `sheet` narrows the pools that depend on the current build
# (expertise: only skills you are proficient in).
static func options_for(p: Dictionary, sheet = null) -> Array:
	var ids: Array = []
	match p["type"]:
		"skill-choice":
			ids = p["from"] if p["from"] != null else Catalog.skills().keys()
		"saving-throw-choice", "asi", "ability-choice":
			ids = p["from"] if p.get("from") != null else ABILS
		"language-choice":
			ids = p["from"] if p["from"] != null else LANGUAGES
		"tool-choice":
			ids = p["from"] if p["from"] != null else _all_tools()
		"expertise-choice":
			if p["from"] != null:
				ids = p["from"].duplicate()
			elif sheet != null:
				for s in sheet.skill_prof:
					if sheet.skill_prof[s] == "prof":
						ids.append(s)
			else:
				ids = Catalog.skills().keys()
			ids.append_array(p.get("fromTools", []))
		"fighting-style-choice", "weapon-mastery-choice", "damage-choice", "subclass", "lineage-choice":
			for i in p["from"]:
				if not i in p.get("already_chosen", []):
					ids.append(i)
		"spell-choice":
			ids = Effects.pick_pool(p["spellList"], int(p["spellLevel"]))
		"feature-choice":
			for o in p["options"]:
				ids.append(o["optionId"])
		"feat-choice":
			if p["from"] != null:
				ids = p["from"]
			else:
				for f in Catalog.all("feats.json"):
					if f["category"] == p["category"]:
						ids.append(f["id"])
	var out: Array = []
	for i in ids:
		out.append({"id": i, "label": label_for(p, i)})
	return out

static func label_for(p: Dictionary, id: String) -> String:
	match p["type"]:
		"asi", "ability-choice", "saving-throw-choice":
			return ABIL_NAME.get(id, humanize(id))
		"skill-choice":
			return String(Catalog.skills().get(id, {}).get("name", humanize(id)))
		"expertise-choice":
			return String(Catalog.skills().get(id, {}).get("name", humanize(id)))
		"spell-choice":
			return String(Catalog.spell(id).get("name", humanize(id)))
		"feat-choice":
			return String(Catalog.feat_src(id).get("name", humanize(id)))
		"subclass":
			return String(Catalog.subclass_src(id).get("name", humanize(id)))
		"weapon-mastery-choice":
			return String(Catalog.weapon(id).get("name", humanize(id)))
	return humanize(id)

# picks -> the decision Character.decide() stores. Payload keys are the source's
# (spec §2.1); never rename them.
static func decision_for(p: Dictionary, picks: Array) -> Dictionary:
	var t: String = p["type"]
	match t:
		"skill-choice": return {"type": t, "skills": picks.duplicate()}
		"saving-throw-choice": return {"type": t, "savingThrows": picks.duplicate()}
		"tool-choice": return {"type": t, "tools": picks.duplicate()}
		"language-choice": return {"type": t, "languages": picks.duplicate()}
		"ability-choice": return {"type": t, "abilities": picks.duplicate()}
		"fighting-style-choice": return {"type": t, "styles": picks.duplicate()}
		"weapon-mastery-choice": return {"type": t, "weaponIds": picks.duplicate()}
		"damage-choice": return {"type": t, "damageTypes": picks.duplicate()}
		"spell-choice": return {"type": t, "spellIds": picks.duplicate()}
		"subclass": return {"type": t, "subclassId": picks[0] if picks else ""}
		"lineage-choice": return {"type": t, "lineageId": picks[0] if picks else ""}
		"feature-choice": return {"type": t, "optionId": picks[0] if picks else ""}
		"feat-choice": return {"type": t, "featId": picks[0] if picks else ""}
		"expertise-choice":
			var sk: Array = []
			var tl: Array = []
			for i in picks:
				if Catalog.skills().has(i):
					sk.append(i)
				else:
					tl.append(i)
			return {"type": t, "skills": sk, "tools": tl}
		"asi":
			var alloc := {}
			for a in picks:
				alloc[a] = int(alloc.get(a, 0)) + 1
			return {"type": t, "allocation": alloc}
	return {"type": t}

# The inverse: a stored decision -> the pick list the UI toggles.
static func picks_from_decision(p: Dictionary, d) -> Array:
	if d == null or d.get("type") != p["type"]:
		return []
	match p["type"]:
		"skill-choice": return d["skills"].duplicate()
		"saving-throw-choice": return d["savingThrows"].duplicate()
		"tool-choice": return d["tools"].duplicate()
		"language-choice": return d["languages"].duplicate()
		"ability-choice": return d["abilities"].duplicate()
		"fighting-style-choice": return d["styles"].duplicate()
		"weapon-mastery-choice": return d["weaponIds"].duplicate()
		"damage-choice": return d["damageTypes"].duplicate()
		"spell-choice": return d["spellIds"].duplicate()
		"subclass": return [d["subclassId"]]
		"lineage-choice": return [d["lineageId"]]
		"feature-choice": return [d["optionId"]]
		"feat-choice": return [d["featId"]]
		"expertise-choice": return d["skills"] + d["tools"]
		"asi":
			var out: Array = []
			for a in d["allocation"]:
				for _i in int(d["allocation"][a]):
					out.append(a)
			return out
	return []

# Toggle one option: adds it, or removes it when already at its per-option cap.
# Over-picking evicts the oldest, so there is never an invalid state to report.
static func toggle(p: Dictionary, picks: Array, id: String) -> Array:
	var out := picks.duplicate()
	var n := out.count(id)
	if n >= max_per_option(p):
		while out.has(id):
			out.erase(id)
		return out
	out.append(id)
	while out.size() > pick_count(p):
		out.remove_at(0)
	return out

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

static func _price(currency: String, remaining: int) -> String:
	return "locked — %d more %s" % [remaining, currency] if remaining > 0 else "locked"

static func humanize(id: String) -> String:
	return id.replace("-", " ").replace("_", " ").capitalize()

static func _all_tools() -> Array:
	var out: Array = []
	for f in ["backgrounds.json", "classes.json"]:
		for r in Catalog.all(f):
			for t in r.get("toolProficiencies", []):
				if not t in out:
					out.append(t)
	return out

# --- abilities ------------------------------------------------------------

static func point_buy_cost(abilities: Dictionary) -> int:
	var c := 0
	for a in ABILS:
		c += int(PB_COST.get(int(abilities[a]), 99))
	return c

# Quick-build order from the class catalog: highest ability gets the 15.
static func recommended_array(class_id: String) -> Dictionary:
	var q: Dictionary = Catalog.class_src(class_id).get("quickBuild", {}) if class_id != "" else {}
	var order: Array = []
	for a in q.get("highestAbility", []):
		order.append(a)
	if q.has("secondaryAbility") and not q["secondaryAbility"] in order:
		order.append(q["secondaryAbility"])
	for a in ABILS:
		if not a in order:
			order.append(a)
	var out := {}
	for i in order.size():
		out[order[i]] = STANDARD_ARRAY[i]
	return out

# --- equipment ------------------------------------------------------------

static func proficient_weapons(sheet) -> Array:
	var profs: Array = sheet.proficiencies["weapon"]
	var out: Array = []
	for wid in Catalog.index("weapons.json"):
		var w: Dictionary = Catalog.index("weapons.json")[wid]
		if w["weaponProficiencyId"] in profs or w["category"] in profs:
			out.append(wid)
	return out

static func proficient_armor(sheet) -> Array:
	var profs: Array = sheet.proficiencies["armor"]
	var out: Array = []
	for aid in Catalog.index("armor.json"):
		var a: Dictionary = Catalog.index("armor.json")[aid]
		var cat: String = a["category"]
		if cat in profs or (cat == "shield" and "shields" in profs):
			out.append(aid)
	return out

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
var _summary := RichTextLabel.new()
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
	root.add_child(_title)

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
	_summary.bbcode_enabled = true
	_summary.scroll_following = false
	_summary.add_theme_color_override("default_color", COL_TEXT)
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
	c.cname = "New Hero"
	for i in ABILS.size():
		c.base_abilities[ABILS[i]] = STANDARD_ARRAY[i]
	return c

func _build_theme() -> void:
	theme = dark_theme()

# Static so other screens (scenes/creator/levelup.gd, campaign.gd) share one copy.
static func dark_theme() -> Theme:
	return Icons.dark_theme()

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
	_summary.text = _sheet_bbcode(false)

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
		if e == locked.front():
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
	_note("Vera, Pike and Ilsa as real 5.5e builds — hand one back instead of building.")
	var pf := _flow()
	for pre in [["Vera Kord (Fighter 3)", "vera"], ["Pike Sallow (Rogue 3)", "pike"],
			["Ilsa Vane (Cleric 3)", "ilsa"]]:
		_opt(pf, pre[0], false, func(): _load_preset(pre[1]))

func _set_species(sid: String) -> void:
	if ch.species_id == sid:
		return
	_prune_choices(ch.species_id)
	ch.species_id = sid
	ch.dirty()
	_refresh()

func _load_preset(which: String) -> void:
	match which:
		"vera": ch = Presets.vera()
		"pike": ch = Presets.pike()
		"ilsa": ch = Presets.ilsa()
	# The presets are level-3 builds; a preset joins a higher-level party at its
	# level too. Topped up rather than rebuilt — what they already are is a real
	# build with its choices made, and only the levels above it are missing.
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
		_note("Primary ability: %s · Hit die: d%d · Saves: %s" % [
			ABIL_NAME.get(src["primaryAbility"], "?"), int(src["hitDie"]),
			", ".join(src["savingThrows"]).to_upper()])
		_note("Quick build: highest %s, then %s; suggested background %s." % [
			", ".join(q["highestAbility"]).to_upper(), String(q["secondaryAbility"]).to_upper(),
			humanize(q["suggestedBackground"])])
		_note("Armor: %s · Weapons: %s" % [
			", ".join(src["armorProficiencies"]) if src["armorProficiencies"] else "none",
			", ".join(src["weaponProficiencies"]) if src["weaponProficiencies"] else "none"])
	_target = null

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
	_note("Species and background bonuses (the → column) are applied by the resolver; the background's points are chosen on the next step.")

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
		ch.background_id = bg
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
		_note("Skills: %s · Tools: %s · Origin feat: %s" % [
			", ".join(src["skillProficiencies"]),
			", ".join(src["toolProficiencies"]) if src["toolProficiencies"] else "none",
			humanize(src["originFeat"]) if src["originFeat"] != null else "none"])

	_head("Choices")
	var pts := _choice_points_of([])
	if pts.is_empty():
		_note("Nothing to choose.")
	elif ch.sheet().pending.is_empty():
		_note("Nothing left to choose — the ones below are made and can be changed.")
	for p in pts:
		_choice_widget(p)

func _set_background(bid: String) -> void:
	if ch.background_id == bid:
		return
	_prune_choices(ch.background_id)
	ch.background_id = bid
	ch.dirty()
	_refresh()

# 5. equipment ------------------------------------------------------------

func _build_equipment() -> void:
	var sheet = ch.sheet()
	_head("Weapons  (pick up to %d)" % MAX_WEAPONS)
	_note("Only weapons and armor are modeled — no PHB equipment packs in the export yet.")
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
	_head(ch.cname)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_color_override("default_color", COL_TEXT)
	r.text = _sheet_bbcode(true)
	_body.add_child(r)
	if not sheet.choice_points.is_empty():
		_head("Unmade choices" if not sheet.pending.is_empty() else "Choices")
		for p in _choice_points_of([]):
			_choice_widget(p)

# --- choice widgets -------------------------------------------------------

# Every choice point the build has reached, optionally filtered to a set of types,
# in the resolver's own order — a choice keeps its place on the page whether or
# not it is made yet, so picking one never shuffles the rest under the cursor.
func _choice_points_of(types: Array) -> Array:
	return ch.sheet().choice_points.filter(func(p): return types.is_empty() or p["type"] in types)

func _choice_widget(p: Dictionary) -> void:
	var sheet = ch.sheet()
	var picks := picks_from_decision(p, ch.choices.get(p["key"]))
	var n := pick_count(p)
	var src: Dictionary = p["source"]
	if p["type"] == "spell-choice":   # a pool shorter than the grant asks for all of it
		n = mini(n, Effects.pick_pool(p["spellList"], int(p["spellLevel"])).size())
	_head("%s%s — pick %d  (%d chosen)" % ["✓ " if p.get("decided", false) else "",
		humanize(p["type"]).replace(" choice", ""), n, picks.size()])
	_note("from %s %s%s" % [src["origin"], humanize(src["id"]),
		"  ·  already chosen, click to change" if p.get("decided", false) else ""])
	var f := _flow()
	var opts := options_for(p, sheet)
	if opts.is_empty():
		_note("No options available.", COL_WARN)
	for o in opts:
		var count := picks.count(o["id"])
		var extra := ""
		if allows_repeat(p) and count > 0:
			extra = "  +%d" % count
		var b := _opt(f, _decorate(p, String(o["id"]), String(o["label"])), count > 0,
			func(): _pick(p, o["id"]), extra)
		if p["type"] == "spell-choice":
			b.tooltip_text = "%s spell" % humanize(Icons.spell_school(String(o["id"])))

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

func _sheet_bbcode(full: bool) -> String:
	var sheet = ch.sheet()
	var cls := humanize(ch.class_id()) if ch.class_id() != "" else "—"
	var sub := ""
	if sheet.subclasses.has(ch.class_id()):
		sub = " (%s)" % humanize(sheet.subclasses[ch.class_id()])
	var s := "[b][color=#c9a45a]%s[/color][/b]\n%s %s %s%s %d\n\n" % [ch.cname,
		humanize(ch.species_id) if ch.species_id != "" else "—",
		Icons.class_glyph(ch.class_id()), cls, sub, max(1, sheet.level)]
	s += "[b]AC[/b] %d   [b]HP[/b] %d   [b]Speed[/b] %d ft   [b]PB[/b] +%d   [b]Init[/b] %+d\n\n" % [
		sheet.ac, sheet.max_hp, int(sheet.speeds.get("walk", 30)), sheet.proficiency_bonus, sheet.initiative]
	var ab: Array = []
	for a in ABILS:
		var t := int(sheet.abilities[a]["total"]) if sheet.abilities.has(a) else 10
		ab.append("%s %d (%+d)" % [ABIL_NAME[a], t, sheet.mod(a)])
	s += "  ".join(ab) + "\n\n"
	var sv: Array = []
	for a in ABILS:
		sv.append("%s %+d%s" % [ABIL_NAME[a], int(sheet.saves.get(a, 0)),
			"*" if sheet.save_prof.get(a, false) else ""])
	s += "[b]Saves[/b] " + "  ".join(sv) + "\n"
	var sk: Array = []
	for k in sheet.skill_prof:
		if sheet.skill_prof[k] != "none":
			sk.append("%s %+d%s" % [Catalog.skills().get(k, {}).get("name", k),
				int(sheet.skills[k]), "E" if sheet.skill_prof[k] == "expert" else ""])
	s += "[b]Skills[/b] " + (", ".join(sk) if sk else "none") + "\n"
	s += "[b]Passive Perception[/b] %d\n\n" % sheet.passive_perception
	s += "[b]Attacks[/b]\n"
	if sheet.attacks.is_empty():
		s += "  none\n"
	for atk in sheet.attacks:
		s += "  %s %+d, %s %s\n" % [atk["name"], int(atk["to_hit"]), atk["notation"], atk["damage_type"]]
	if not sheet.spellcasting.is_empty():
		var sc: Dictionary = sheet.spellcasting
		var slots: Array = []
		for i in sc.get("slots", []).size():
			if int(sc["slots"][i]) > 0:
				slots.append("L%d×%d" % [i + 1, int(sc["slots"][i])])
		s += "\n[b]Spellcasting[/b] %s  DC %d  atk %+d\n  slots: %s\n" % [
			String(sc["ability"]).to_upper(), int(sc["save_dc"]), int(sc["attack_bonus"]),
			", ".join(slots) if slots else "none"]
		if full:
			var known: Array = []
			for k in sc.get("cantrips", []):
				known.append(Icons.spell_bb(k, humanize(k)))
			for k in sc.get("known", []):
				known.append(Icons.spell_bb(k["id"], humanize(k["id"])))
			for k in sc.get("always_prepared", []):
				known.append(Icons.spell_bb(k, humanize(k)))
			if known:
				s += "  spells: %s\n" % ", ".join(known)
	if full:
		s += "\n[b]Features[/b]\n"
		for fid in sheet.features:
			s += "  · %s\n" % humanize(fid)
		if not sheet.pools.is_empty():
			s += "\n[b]Resources[/b]\n"
			for p in sheet.pools:
				s += "  · %s ×%d\n" % [humanize(p["id"]), int(p["max"])]
		if not sheet.equipment.is_empty():
			s += "\n[b]Equipment[/b] %s\n" % ", ".join(ch.equipped)
	if not sheet.pending.is_empty():
		s += "\n[color=#d15750][b]%d choice(s) left[/b][/color]\n" % sheet.pending.size()
		for p in sheet.pending:
			s += "[color=#d15750]  · %s[/color]\n" % humanize(p["type"])
	if not sheet.warnings.is_empty() and full:
		s += "\n[color=#c9a45a]warnings:[/color]\n"
		for w in sheet.warnings:
			s += "  %s\n" % w
	return s

# A class/species/background swap leaves that source's decisions behind; drop them
# so the old pick can't silently satisfy a same-keyed grant on the new one.
func _prune_choices(origin_id: String) -> void:
	if origin_id == "":
		return
	for k in ch.choices.keys():
		if k.split(":").size() == 4 and k.split(":")[2] == origin_id:
			ch.choices.erase(k)
	ch.dirty()
