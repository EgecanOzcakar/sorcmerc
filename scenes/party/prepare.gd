# Prepare spells — the daily-prep screen the prepared casters never had.
#
# core/rules/pass_spells.gd has computed `prepared_count` since F2 and nothing
# read it, because no screen existed to spend it: a cleric or druid got their
# cantrips, their subclass's always-prepared list, and nothing else. A level-8
# Circle of the Moon druid stood there with 4/3/3/2 spell slots and only
# cantrips to spend them on (docs/expansion-plan.md, T-classes). This is where
# that list gets filled in.
#
# WHO gets this page: the five in PassSpells.PREPARED_CASTERS. A sorcerer, bard
# or warlock KNOWS their spells rather than preparing them — their list is
# settled at level-up and there is nothing to decide here — and the two third
# casters (Eldritch Knight, Arcane Trickster) prepare nothing either.
#
# WHAT may be prepared: the class's own list, at the levels this character has
# slots for. RAW for a cleric, druid, paladin and ranger, who prepare from the
# whole class list. A wizard prepares from their spellbook instead, and the
# spellbook is `spellcasting.known` — every one of which adapter.gd already
# makes castable, so a wizard's book is shown here as already prepared and
# costs nothing against the limit.
#
# WHAT DOESN'T COUNT: cantrips (never prepared) and the always-prepared list a
# subclass grants (a Light domain cleric's Burning Hands is theirs whatever
# they choose today). Both are shown, so the page reads as the whole kit rather
# than as the part of it that happens to be editable.
#
# Run standalone:  godot --path . scenes/party/prepare.tscn
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const PassSpells = preload("res://core/rules/pass_spells.gd")
const Presets = preload("res://core/presets.gd")
const Sound = preload("res://core/audio.gd")

const COL_BG := Icons.COL_BG
const COL_GOLD := Icons.COL_GOLD
const COL_TEXT := Icons.COL_HEAD
const COL_DIM := Icons.COL_BODY
const COL_ACCENT := Icons.COL_ACCENT
const COL_WARN := Icons.COL_MUTED

var _ch                                   # core/character.gd
var _fields: Dictionary = {}              # key -> Label, for tests
var _rows: Dictionary = {}                # spell id -> Button, for tests
var _body: VBoxContainer
var _chrome := false

func _ready() -> void:
	if _ch == null:
		set_character(Presets.ilsa(8))    # standalone: a cleric has a list to show

# Same contract as scenes/profile/profile.gd: works before the node is in the
# tree, so a caller (and a test) can inject and read back in one go.
func set_character(ch) -> void:
	_ch = ch
	if not _chrome:
		_chrome = true
		set_anchors_preset(Control.PRESET_FULL_RECT)
		theme = Icons.dark_theme(true)
		var bg := ColorRect.new()
		bg.color = COL_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	_render()

func character():
	return _ch

# --- the model, static and UI-free so tests can drive it directly ---------

# Does this character prepare spells at all?
static func prepares(ch) -> bool:
	var sc: Dictionary = ch.sheet().spellcasting
	return String(sc.get("class_id", "")) in PassSpells.PREPARED_CASTERS

# How many the character may hold, and how many they are holding. The count is
# `prepared_count` from the resolver — level + the casting ability's modifier —
# and only the spells this screen actually chose are counted against it.
static func limit(ch) -> int:
	return int(ch.sheet().spellcasting.get("prepared_count", 0))

static func chosen(ch) -> Array:
	var out: Array = []
	for sid in ch.prepared:
		if sid in pool(ch):
			out.append(sid)
	return out

# Everything castable without spending a pick: the cantrips, the subclass's
# always-prepared list, and (for a wizard) the spellbook. adapter.gd already
# makes every one of these castable, so charging a pick for them would be
# charging for something the character has either way.
static func free_list(ch) -> Array:
	var sc: Dictionary = ch.sheet().spellcasting
	var out: Array = []
	for sid in sc.get("cantrips", []):
		if not sid in out:
			out.append(String(sid))
	for sid in sc.get("always_prepared", []):
		if not sid in out:
			out.append(String(sid))
	for k in sc.get("known", []):
		if not String(k["id"]) in out:
			out.append(String(k["id"]))
	return out

# The one prepared caster who does not prepare from the class list. A wizard
# prepares from their spellbook and nowhere else, and the spellbook here is
# `spellcasting.known` — the spell-choice picks made at level-up. Every one of
# those is already castable (adapter.gd), and the book is smaller than the
# limit at every level the game reaches, so a wizard's preparation is settled
# the moment the book is: there is nothing on this page for them to decide, and
# the page says so rather than offering the whole wizard list as if RAW allowed
# it.
const SPELLBOOK_CASTERS := ["wizard"]

# What may be picked: the class list at the levels this character has slots
# for, minus whatever is already free. Effects.pick_pool is the same filter the
# creator's spell picks use — a spell that does nothing on the board and has no
# door off it is a preparation spent on nothing.
static func pool(ch) -> Array:
	var sc: Dictionary = ch.sheet().spellcasting
	var cid: String = String(sc.get("class_id", ""))
	if not cid in PassSpells.PREPARED_CASTERS or cid in SPELLBOOK_CASTERS:
		return []
	var free := free_list(ch)
	var out: Array = []
	for lvl in top_slot(ch):
		for sid in Effects.pick_pool(cid, lvl + 1):
			if not sid in free and not sid in out:
				out.append(String(sid))
	return out

# The highest slot level the character can actually cast at. Preparing a 4th
# level spell with no 4th level slot is a pick that can never be spent.
static func top_slot(ch) -> int:
	var slots: Array = ch.sheet().spellcasting.get("slots", [])
	var top := 0
	for i in slots.size():
		if int(slots[i]) > 0:
			top = i + 1
	return top

# Toggle one spell. Refuses a pick that would take the character over the limit
# and refuses anything outside the pool; returns whether the list changed, so a
# caller can say why nothing happened.
static func toggle(ch, sid: String) -> bool:
	if sid in ch.prepared:
		ch.prepared.erase(sid)
		ch.dirty()
		return true
	if not sid in pool(ch) or chosen(ch).size() >= limit(ch):
		return false
	ch.prepared.append(sid)
	ch.dirty()
	return true

static func clear(ch) -> void:
	for sid in chosen(ch):
		ch.prepared.erase(sid)
	ch.dirty()

# --- rendering -----------------------------------------------------------

func field(key: String) -> String:
	return _fields[key].text if _fields.has(key) else ""

func row(sid: String) -> Button:
	return _rows.get(sid)

func _render() -> void:
	_fields.clear()
	_rows.clear()
	for c in get_children():
		if not c is ColorRect:
			c.queue_free()
			remove_child(c)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 12
	root.offset_right = -14; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	if not prepares(_ch):
		_note(_body, "%s does not prepare spells." % _ch.cname)
		_note(_body, "A bard, sorcerer or warlock knows their spells outright — the list is "
			+ "settled at level-up, and there is nothing to decide here.")
		return
	_free_panel()
	_pool_panel()

func _header() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var s = _ch.sheet()
	var sc: Dictionary = s.spellcasting

	var title := Label.new()
	title.text = "Prepare spells — %s" % _ch.cname
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(title)

	if prepares(_ch):
		var n: int = chosen(_ch).size()
		var count := Label.new()
		count.text = "%d / %d prepared" % [n, limit(_ch)]
		count.add_theme_color_override("font_color", COL_GOLD if n < limit(_ch) else COL_ACCENT)
		box.add_child(count)
		_fields["count"] = count

		var dc := Label.new()
		dc.text = "save DC %d" % int(sc.get("save_dc", 0))
		dc.add_theme_color_override("font_color", COL_DIM)
		box.add_child(dc)
		_fields["dc"] = dc

		var slots := Label.new()
		slots.text = _slot_line(sc)
		slots.add_theme_color_override("font_color", COL_DIM)
		box.add_child(slots)
		_fields["slots"] = slots

		var clear_btn := Button.new()
		Icons.clicks(clear_btn)
		clear_btn.text = "Clear"
		clear_btn.tooltip_text = "Unprepare everything chosen here"
		clear_btn.disabled = chosen(_ch).is_empty()
		clear_btn.pressed.connect(func():
			Sound.play_sfx("click")
			clear(_ch)
			_render())
		box.add_child(clear_btn)
	return box

func _slot_line(sc: Dictionary) -> String:
	var parts: Array = []
	for i in int(sc.get("slots", []).size()):
		var n := int(sc["slots"][i])
		if n > 0:
			parts.append("L%d x%d" % [i + 1, n])
	return "slots: " + (", ".join(parts) if not parts.is_empty() else "none")

# The part of the kit that is not up for debate today.
func _free_panel() -> void:
	var free := free_list(_ch)
	if free.is_empty():
		return
	var v := _panel("Always yours  (does not count against the limit)")
	for sid in free:
		var def := Catalog.spell(sid)
		var lvl := int(def.get("level", 0))
		_line(v, "%s" % def.get("name", sid),
			"cantrip" if lvl == 0 else "level %d" % lvl, "free_" + sid, COL_DIM, sid)

# Issue #122: the same badge the action bar puts on the button that casts this
# spell (assets/icons/skills, falling back to the school disc) — so a spell is
# recognised here by the mark it will wear in the fight, rather than read as a
# name and met again as a picture. Null for a build with no icons imported, and
# the row is a row of text again, exactly as it was.
const BADGE_PX := 28

func _badge(sid: String) -> TextureRect:
	var tex := Icons.skill_icon({"spell": sid})
	if tex == null:
		return null
	var pic := TextureRect.new()
	pic.texture = tex
	pic.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.tooltip_text = String(Catalog.spell(sid).get("name", sid))
	return pic

func _pool_panel() -> void:
	var picks := pool(_ch)
	if picks.is_empty():
		if String(_ch.sheet().spellcasting.get("class_id", "")) in SPELLBOOK_CASTERS:
			_note(_body, "A wizard prepares from their spellbook, and the book above is "
				+ "already prepared in full — it holds fewer spells than %s can carry. "
				% _ch.cname
				+ "The way to change this list is to add to the book at level-up.")
		else:
			_note(_body, "Nothing left to prepare: every spell this character can cast is "
				+ "already theirs.")
		return
	var full: bool = chosen(_ch).size() >= limit(_ch)
	# Grouped by spell level, because that is how a caster shops: what a 2nd
	# level slot can buy is the question, not what is alphabetically next.
	var by_level: Dictionary = {}
	for sid in picks:
		by_level.get_or_add(int(Catalog.spell(sid).get("level", 1)), []).append(sid)
	var levels: Array = by_level.keys()
	levels.sort()
	for lvl in levels:
		var v := _panel("Level %d" % lvl)
		for sid in by_level[lvl]:
			_pick_row(v, sid, full)

func _pick_row(box: VBoxContainer, sid: String, full: bool) -> void:
	var def := Catalog.spell(sid)
	var on: bool = sid in _ch.prepared
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var pic := _badge(sid)
	if pic != null:
		h.add_child(pic)
	var name := Label.new()
	name.text = String(def.get("name", sid))
	name.add_theme_color_override("font_color", COL_TEXT if on else COL_DIM)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)

	var note := Label.new()
	note.text = _summary(sid)
	note.add_theme_color_override("font_color", COL_DIM)
	h.add_child(note)

	var b := Button.new()
	Icons.clicks(b)
	b.text = "Prepared" if on else "Prepare"
	b.toggle_mode = true
	b.button_pressed = on
	# A full list still lets you take one back off it — otherwise the only way
	# out of a wrong pick is Clear, which throws the other eleven away too.
	b.disabled = full and not on
	if b.disabled:
		b.tooltip_text = "%s can only hold %d prepared spells" % [_ch.cname, limit(_ch)]
	b.pressed.connect(func():
		Sound.play_sfx("click")
		toggle(_ch, sid)
		_render())
	h.add_child(b)
	box.add_child(h)
	_rows[sid] = b

# One line of what the spell actually does, off the same mechanics the action
# bar reads — so the choice is made against the engine's behaviour rather than
# against the SRD prose, which for several of these says more than the engine
# does.
func _summary(sid: String) -> String:
	var m := Effects.spell(sid)
	if m.is_empty():
		return "utility"
	var bits: Array = []
	if m.has("damage"):
		var d: Dictionary = m["damage"][0]
		bits.append("%dd%d %s" % [int(d.get("count", 1)), int(d.get("sides", 6)), d.get("type", "")])
	if m.has("heal"):
		bits.append("heals")
	if m.has("conditions"):
		bits.append(", ".join(m["conditions"]))
	if m.has("buff"):
		bits.append("buff")
	if m.has("summon"):
		# {"id": "dire-wolf"} — the bestiary id, not a name. Both monsters.json
		# and bestiary.json spell the name `cname`; reading "name" meant this
		# line had always printed the raw id.
		var mid := String(m["summon"].get("id", "")) if m["summon"] is Dictionary else String(m["summon"])
		bits.append("summons %s" % Catalog.monster(mid).get("cname", mid))
	if m.get("teleport", false):
		bits.append("teleport")
	if m.get("concentration", false):
		bits.append("conc.")
	return "  ".join(bits) if not bits.is_empty() else "utility"

func _panel(title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	_body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var cap := Label.new()
	cap.text = title
	cap.theme_type_variation = "Caption"
	v.add_child(cap)
	return v

func _line(box: VBoxContainer, left: String, right: String, key := "", tint := COL_TEXT,
		badge_spell := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if badge_spell != "":
		var pic := _badge(badge_spell)
		if pic != null:
			h.add_child(pic)
	var l := Label.new()
	l.text = left
	l.add_theme_color_override("font_color", tint)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_color_override("font_color", COL_DIM)
	h.add_child(r)
	box.add_child(h)
	if key != "":
		_fields[key] = r

func _note(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", COL_DIM)
	box.add_child(l)
