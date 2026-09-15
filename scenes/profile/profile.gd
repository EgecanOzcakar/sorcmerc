# Character profile: the sheet for one Character, rendered from resolve.gd's output.
# Dependency-injected — call set_character(ch) with a core/character.gd build.
# Nothing here derives a stat; every number comes off ch.sheet(). Editing (equip,
# damage, spend) mutates the build and re-renders, so the sheet re-resolves.
extends Control

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Presets = preload("res://core/presets.gd")
const Leveling = preload("res://core/leveling.gd")
const Ach = preload("res://core/achievements.gd")

const ABIL := ["str", "dex", "con", "int", "wis", "cha"]
const ABIL_NAME := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}

const COL_BG := Icons.COL_BG
const COL_PANEL := Icons.COL_INK
const COL_EDGE := Icons.COL_GOLD_EDGE
const COL_GOLD := Icons.COL_GOLD
const COL_TEXT := Icons.COL_HEAD
const COL_DIM := Icons.COL_BODY
const COL_ACCENT := Icons.COL_ACCENT

const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")

var _ch                                 # core/character.gd
var _party                              # core/party.gd — the shared stash (T10)
var _fields: Dictionary = {}            # key -> Label, for tests
var _body: HBoxContainer
var _chrome := false

func _ready() -> void:
	if _ch == null:
		set_character(Presets.vera())   # standalone demo fixture

# Works before the node enters the tree, so callers (and tests) can inject and read
# back in one go.
func set_character(ch) -> void:
	_ch = ch
	if not _chrome:
		_chrome = true
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_build_theme()
		var bg := ColorRect.new()
		bg.color = COL_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	_render()

func character():
	return _ch

# The party whose stash this screen equips from. Injected by the party/campaign
# screens; standalone it falls back to a one-character demo party.
func set_party(p) -> void:
	_party = p
	if _chrome:
		_render()

func party():
	if _party == null:
		_party = Party.new()
		_party.add_member(_ch)
	return _party

# The rendered text of a field, for tests: field("ac"), field("skill_stealth"), ...
func field(key: String) -> String:
	return _fields[key].text if _fields.has(key) else ""

func _build_theme() -> void:
	theme = Icons.dark_theme(true)   # compact: the +/- and equip buttons sit inside text rows

# --- rendering ---------------------------------------------------------------

func _render() -> void:
	_fields.clear()
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
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	var s = _ch.sheet()
	var c1 := _column()
	_abilities(c1, s)
	_defense(c1, s)
	_saves(c1, s)
	var c2 := _column()
	_skills(c2, s)
	var c3 := _column()
	_resources(c3, s)
	_features(c3, s)
	var c4 := _column()
	_attacks(c4, s)
	_inventory(c4, s)

func _header() -> Control:
	var s = _ch.sheet()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var name_col := VBoxContainer.new()
	var nm := Label.new()
	nm.text = _ch.cname
	nm.theme_type_variation = "Title"
	name_col.add_child(nm)
	var sub := Label.new()
	sub.text = "%s, %s" % [_title(_ch.species_id), _title(_ch.background_id)]
	sub.theme_type_variation = "Dim"
	name_col.add_child(sub)
	box.add_child(name_col)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var lv := Label.new()
	lv.text = _class_line(s)
	lv.theme_type_variation = "Head"
	lv.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(lv)
	_fields["classes"] = lv

	var need := Leveling.xp_to_next(_ch)
	var xp := Label.new()
	xp.text = "%d XP" % int(_ch.xp) if need == 0 else "%d XP, need %d more" % [int(_ch.xp), need]
	xp.theme_type_variation = "Dim"
	box.add_child(xp)
	_fields["xp"] = xp

	var b := Button.new()
	Icons.clicks(b)
	b.text = "Level up"
	b.theme_type_variation = "Primary"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = need > 0
	b.pressed.connect(_level_up)
	box.add_child(b)
	_fields["level_up_btn"] = b
	return box

func _class_line(s) -> String:
	var parts: Array = []
	for cid in s.class_levels:
		var sub: String = s.subclasses.get(cid, "")
		var label: String = _title(cid) if sub == "" else "%s (%s)" % [_title(cid), _title(sub)]
		parts.append("%s %s %d" % [Icons.class_glyph(cid), label, s.class_levels[cid]])
	return " / ".join(parts) if not parts.is_empty() else "Level 0"

const LEVELUP_SCENE := "res://scenes/creator/levelup.tscn"

# T2's level-up, as a full-screen overlay over the sheet (the party screen opens
# the profile the same way). It mutates the same build, so closing just re-renders.
func _level_up() -> void:
	if not ResourceLoader.exists(LEVELUP_SCENE):
		return
	var overlay = load(LEVELUP_SCENE).instantiate()
	add_child(overlay)
	overlay.set_character(_ch)
	overlay.finished.connect(func(_leveled):
		overlay.queue_free()
		_ch.dirty()
		_render())

# --- panels ------------------------------------------------------------------

func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(280, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(v)
	return v

func _panel(col: VBoxContainer, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	col.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var cap := Label.new()
	cap.text = title
	cap.theme_type_variation = "Caption"
	v.add_child(cap)
	return v

func _row(box: VBoxContainer, left: String, right: String, key := "", tint := COL_TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.add_theme_color_override("font_color", COL_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_color_override("font_color", tint)
	h.add_child(r)
	box.add_child(h)
	if key != "":
		_fields[key] = r
	return h

func _btn(h: HBoxContainer, text: String, fn: Callable) -> void:
	var b := Button.new()
	Icons.clicks(b)
	b.text = text
	b.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
	b.pressed.connect(fn)
	h.add_child(b)

static func _sign(n: int) -> String:
	return "%+d" % n

static func _title(id: String) -> String:
	return Effects.humanize(id)

# --- stat sections -----------------------------------------------------------

func _abilities(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Abilities")
	for a in ABIL:
		var d: Dictionary = s.abilities.get(a, {"total": 10, "mod": 0})
		_row(v, ABIL_NAME[a], "%d (%s)" % [int(d["total"]), _sign(int(d["mod"]))], "abil_" + a)

func _defense(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Defense")
	_row(v, "Armor Class", str(s.ac), "ac")
	var hp := _row(v, "Hit Points", "%d/%d" % [_hp_current(s), s.max_hp], "hp")
	for delta in [-5, -1, 1, 5]:
		_btn(hp, _sign(delta), _apply_hp.bind(delta))
	_btn(hp, "full", _apply_hp.bind(9999))
	for k in s.speeds:
		_row(v, _title(k) + " speed", "%d ft" % int(s.speeds[k]), "speed_" + k)
	_row(v, "Initiative", _sign(s.initiative), "initiative")
	_row(v, "Proficiency", _sign(s.proficiency_bonus), "pb")
	_row(v, "Passive Perception", str(s.passive_perception), "passive_perception")
	if s.disadvantage_from_armor:
		_row(v, "Armor", "non-proficient: disadvantage", "", Icons.COL_FOE)
	if not s.resistances.is_empty():
		_row(v, "Resistances", ", ".join(s.resistances), "resistances", COL_ACCENT)

func _saves(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Saving Throws")
	for a in ABIL:
		var mark := "●" if s.save_prof.get(a, false) else "○"
		_row(v, "%s %s" % [mark, ABIL_NAME[a]], _sign(int(s.saves.get(a, 0))), "save_" + a)

func _skills(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Skills")
	var defs := Catalog.skills()
	var ids: Array = defs.keys()
	ids.sort()
	for id in ids:
		var prof: String = s.skill_prof.get(id, "none")
		var mark := "◆" if prof == "expert" else ("●" if prof == "prof" else "○")
		var ab: String = defs[id]["ability"]
		_row(v, "%s %s (%s)" % [mark, defs[id]["name"], ABIL_NAME[ab]],
			_sign(int(s.skills.get(id, 0))), "skill_" + id)

func _attacks(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Attacks")
	if s.attacks.is_empty():
		_row(v, "—", "nothing wielded")
	for a in s.attacks:
		var reach := "%d/%d ft" % [int(a["normal_ft"]), int(a["long_ft"])] if a["range"] == "ranged" else "melee"
		_row(v, "%s  (%s)" % [a["name"], reach],
			"%s  %s %s" % [_sign(int(a["to_hit"])), a["notation"], a["damage_type"]],
			"attack_" + str(a["id"]))
	if not s.spellcasting.is_empty():
		var sc: Dictionary = s.spellcasting
		_row(v, "Spell save DC", str(int(sc["save_dc"])), "spell_dc", COL_ACCENT)
		_row(v, "Spell attack", _sign(int(sc["attack_bonus"])), "spell_attack", COL_ACCENT)

# --- resources ---------------------------------------------------------------

func _resources(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Resources")
	var any := false
	var sc: Dictionary = s.spellcasting
	if not sc.is_empty():
		var pact: Dictionary = sc.get("pact", {})
		if not pact.is_empty():
			any = true
			_pool_row(v, "pact", "Pact slots (lv %d)" % int(pact["slotLevel"]), int(pact["count"]))
		for i in int(sc.get("slots", []).size()):
			var mx := int(sc["slots"][i])
			if mx > 0:
				any = true
				_pool_row(v, "slot:%d" % (i + 1), "Level %d slots" % (i + 1), mx)
	for p in s.pools:
		any = true
		var label: String = _title(p["id"])
		if int(p["die_size"]) > 0:
			label += " (d%d)" % int(p["die_size"])
		_pool_row(v, p["id"], label, int(p["max"]))
	if not any:
		_row(v, "—", "no tracked resources")
	else:
		var h := HBoxContainer.new()
		v.add_child(h)
		_btn(h, "Long rest (restore all)", _restore_all)

func _pool_row(v: VBoxContainer, id: String, label: String, mx: int) -> void:
	var h := _row(v, label, "%d/%d" % [_pool_current(id, mx), mx], "pool_" + id)
	_btn(h, "−", _spend.bind(id, mx, -1))
	_btn(h, "+", _spend.bind(id, mx, 1))

func _pool_current(id: String, mx: int) -> int:
	return clampi(int(_ch.pools.get(id, mx)), 0, mx)

func _spend(id: String, mx: int, delta: int) -> void:
	_ch.pools[id] = clampi(_pool_current(id, mx) + delta, 0, mx)
	_render()

func _restore_all() -> void:
	_ch.pools.clear()
	_ch.hp_current = -1
	_render()

func _hp_current(s) -> int:
	return s.max_hp if _ch.hp_current < 0 else clampi(_ch.hp_current, 0, s.max_hp)

func _apply_hp(delta: int) -> void:
	var s = _ch.sheet()
	_ch.hp_current = clampi(_hp_current(s) + delta, 0, s.max_hp)
	_render()

# --- features ----------------------------------------------------------------

func _features(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Features")
	var ids: Array = s.features.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = s.features[id]
		var right := ""
		if int(entry.get("save_dc", 0)) > 0:
			right = "DC %d" % int(entry["save_dc"])
		elif not Effects.feature(id).is_empty():
			right = "combat"
		# ponytail: humanize() is F2's stated fallback — swap for real prose when F1
		# re-exports feature descriptions (SCHEMA gap #4).
		_row(v, Effects.humanize(id), right, "feature_" + id, COL_DIM)
	for st in s.fighting_styles:
		_row(v, _title(st), "style", "style_" + st, COL_DIM)
	if ids.is_empty() and s.fighting_styles.is_empty():
		_row(v, "—", "no features")

# --- inventory ---------------------------------------------------------------

# Worn/wielded (off the sheet), then the party's shared stash. Equipping moves an
# item out of the stash onto this character; unequipping puts it back.
func _inventory(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Equipped")
	if s.equipment.is_empty():
		_row(v, "—", "nothing worn")
	var worn := _grid(v)
	for it in s.equipment:
		_item_tile(worn, String(it["item_id"]), it["def"], String(it["kind"]), int(it["quantity"]), true)

	var stash := _panel(col, "Party stash")
	if party().stash.is_empty():
		_row(stash, "—", "empty")
	var bag := _grid(stash)
	for e in party().stash:
		var iid := String(e["item_id"])
		var kd: Array = Icons.item_def(iid)
		var kind: String = kd[0] if not kd[1].is_empty() else "unknown"
		_item_tile(bag, iid, kd[1], kind, int(e["quantity"]), false, Party.is_identified(e))

func _grid(v: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	v.add_child(g)
	return g

# T9a: the item IS its picture. Everything the row used to say is the hover
# text; the click is the one action the row offered (Equip/Unequip, or Read
# identify scroll), and a Light weapon in hand takes the off-hand on right-click.
# T13: an unidentified item shows as a mystery — rarity only, no name, no Equip.
# Reading a Scroll of Identification here works any time; the DC 15 Arcana check
# is the rest node's business (it is made "during a short rest").
func _item_tile(g: GridContainer, iid: String, def: Dictionary, kind: String, qty: int,
		equipped: bool, identified := true) -> void:
	var tip: String
	var caption := "×%d" % qty if qty > 1 else ""
	if not identified:
		tip = "Unidentified item (%s)" % str(def.get("rarity", "unknown"))
		var can_read: bool = party().stash_count(Party.IDENTIFY_SCROLL, true) > 0
		tip += "\n\nClick: read an identify scroll" if can_read else "\n\nNeeds a Scroll of Identification"
		var m := Icons.item_tile(iid, tip, caption)
		m.text = "?" if m.icon != null else m.text
		m.disabled = not can_read
		_fields["item_" + iid] = m
		if can_read:
			m.pressed.connect(func():
				party().use_identification_scroll(iid)
				_render())
		g.add_child(m)
		return
	tip = Icons.item_tooltip(iid, def, kind)
	if kind == "unknown":
		_fields["item_" + iid] = Icons.item_tile(iid, tip, caption)
		g.add_child(_fields["item_" + iid])
		return
	var offhand: bool = equipped and kind == "weapon" and _ch.is_light(iid)
	if equipped:
		caption = "Off-hand" if _ch.offhand == iid else "Equipped"
	tip += "\n\nClick: %s" % ("unequip" if equipped else "equip")
	if offhand:
		tip += "\nRight-click: %s" % ("main hand" if _ch.offhand == iid else "off-hand")
	var b := Icons.item_tile(iid, tip, caption)
	b.pressed.connect(toggle_equip.bind(iid))
	if offhand:
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				toggle_offhand(iid))
	g.add_child(b)
	_fields["item_" + iid] = b
	_fields["equip_btn_" + iid] = b
	if offhand:
		_fields["offhand_btn_" + iid] = b

# Public for the same reason toggle_equip is: tests drive it without a button.
func toggle_offhand(item_id: String) -> void:
	if _ch.offhand == item_id:
		_ch.unequip_offhand()
	else:
		_ch.equip_offhand(item_id)
	_render()

# Public so tests can drive it without a button press. Moves one unit between the
# character's `equipped` and the party's shared stash. Refuses to equip an item that
# is still unidentified — the guard lives here so every caller is covered.
func toggle_equip(item_id: String) -> void:
	if item_id in _ch.equipped:
		_ch.equipped.erase(item_id)
		if _ch.offhand == item_id:
			_ch.unequip_offhand()
		party().stash_add(item_id)
	elif party().stash_count(item_id, true) > 0 and party().stash_remove(item_id):
		_ch.equipped.append(item_id)
		if Icons.rarity_of(item_id) == "legendary":
			Ach.unlock("equip_legendary")
	else:
		return
	_ch.dirty()
	_render()
