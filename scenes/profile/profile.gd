# Character profile: the sheet for one Character, rendered from resolve.gd's output.
# Dependency-injected — call set_character(ch) with a core/character.gd build.
# Nothing here derives a stat; every number comes off ch.sheet(). Equipping
# mutates the build and re-renders, so the sheet re-resolves.
#
# HP, pools and slots are shown, never edited. The design audit
# (docs/audit-game-design.md §1.1) found the sheet was a free long rest
# anywhere: HP ±1/±5/full buttons, a − and + on every pool, and a "Long rest
# (restore all)" button, reachable from the map's party page in open country —
# a sorcerer could refill sorcery points here and turn them into slots in the
# next fight. They are gone; a rest is taken where the world charges for one.
# The slot rows are Adapter.slot_table() (§4.1), the same reading the party
# page and the combat pips show: what is left against the sheet's maximum.
extends Control

const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Presets = preload("res://core/presets.gd")
const Leveling = preload("res://core/leveling.gd")
const Ach = preload("res://core/achievements.gd")
const Potions = preload("res://core/potions.gd")
const RoadSpells = preload("res://core/road_spells.gd")
const Adapter = preload("res://core/adapter.gd")   # audit 4.1: the one reading of slots
const Traits = preload("res://core/traits.gd")

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

# Issue #118: whoever opens this screen as an overlay names the way out, and it
# is drawn as the last thing in the header row rather than floated over the
# screen. scenes/party/party.gd already does this for its own exit and says why
# (a Button anchored to the top-right corner covers whatever the screen under
# it put in that corner) — here the thing it covered was the Level up button,
# which is the one control on this page a player is looking for.
signal exit_requested
var exit_label := ""

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
	theme = Icons.dark_theme(true)   # compact: the equip and cast buttons sit inside text rows

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
	_traits(c2)
	var c3 := _column()
	_resources(c3, s)
	_road(c3)
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
	b.pressed.connect(level_up)
	box.add_child(b)
	_fields["level_up_btn"] = b

	if exit_label != "":
		var out := Button.new()
		Icons.clicks(out)
		out.text = exit_label
		out.theme_type_variation = "Quiet"
		out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		out.pressed.connect(func(): exit_requested.emit())
		box.add_child(out)
		_fields["exit_btn"] = out
	return box

func _class_line(s) -> String:
	var parts: Array = []
	for cid in s.class_levels:
		var sub: String = s.subclasses.get(cid, "")
		var subname: String = String(Catalog.subclass_src(sub).get("name", _title(sub))) if sub != "" else ""
		var label: String = _title(cid) if sub == "" else "%s (%s)" % [_title(cid), subname]
		parts.append("%s %s %d" % [Icons.class_glyph(cid), label, s.class_levels[cid]])
	return " / ".join(parts) if not parts.is_empty() else "Level 0"

const LEVELUP_SCENE := "res://scenes/creator/levelup.tscn"

# T2's level-up, as a full-screen overlay over the sheet (the party screen opens
# the profile the same way). It mutates the same build, so closing just re-renders.
#
# Public since #118: the party screen's own per-character "Level up" opens this
# sheet and this overlay in one press, rather than growing a second copy of the
# same two screens.
func level_up() -> void:
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
	_row(v, "Hit Points", "%d/%d" % [_hp_current(s), s.max_hp], "hp")
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
			"attack_" + str(a["id"]), Icons.damage_color(String(a["damage_type"])))   # fire is one orange game-wide
	if not s.spellcasting.is_empty():
		var sc: Dictionary = s.spellcasting
		_row(v, "Spell save DC", str(int(sc["save_dc"])), "spell_dc", COL_ACCENT)
		_row(v, "Spell attack", _sign(int(sc["attack_bonus"])), "spell_attack", COL_ACCENT)

# --- resources ---------------------------------------------------------------

# Read-only (audit 1.1). Slots are Adapter.slot_table(): left against the
# sheet's maximum, a spent level still a row, the warlock's Pact Magic named
# as such. A level Font of Magic has pushed past its maximum reads "4/3",
# which is what it is until the long rest. Keys: slot_<level>, slot_pact.
func _resources(col: VBoxContainer, s) -> void:
	var v := _panel(col, "Resources")
	var any := false
	for row in Adapter.slot_table(_ch):
		any = true
		var lv := int(row["level"])
		var pact: bool = row["pact"]
		var left := int(row["left"])
		_row(v, "Pact slots (lv %d)" % lv if pact else "Level %d slots" % lv,
			"%d/%d" % [left, int(row["max"])], "slot_pact" if pact else "slot_%d" % lv,
			COL_TEXT if left > 0 else COL_DIM)
	# Arcane Recovery is not a pool on the sheet (it is spent by the rest
	# itself, core/adapter.gd), so it gets its own line: ready or used.
	var ar_max: int = Adapter.arcane_recovery_max(_ch)
	if ar_max > 0:
		any = true
		var ready: bool = Adapter.arcane_recovery_left(_ch) > 0
		_row(v, "Arcane Recovery", "ready, up to %d slot levels" % ar_max if ready else "used until a long rest",
			"arcane_recovery", COL_TEXT if ready else COL_DIM)
	for p in s.pools:
		any = true
		var label: String = _title(p["id"])
		if int(p["die_size"]) > 0:
			label += " (d%d)" % int(p["die_size"])
		var mx := int(p["max"])
		_row(v, label, "%d/%d" % [clampi(int(_ch.pools.get(p["id"], mx)), 0, mx), mx], "pool_" + String(p["id"]))
	if not any:
		_row(v, "—", "no tracked resources")

func _hp_current(s) -> int:
	return s.max_hp if _ch.hp_current < 0 else clampi(_ch.hp_current, 0, s.max_hp)

# --- features ----------------------------------------------------------------

# Utility spells with a road door (core/road_spells.gd): cast here, for a slot.
var last_cast := ""   # the line the last road cast produced; the panel shows it

func _road(col: VBoxContainer) -> void:
	var known: Array = RoadSpells.known(party(), _ch)
	if known.is_empty():
		return
	var v := _panel(col, "On the road")
	if last_cast != "":
		var note := Label.new()
		note.text = last_cast
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", COL_DIM)
		v.add_child(note)
		_fields["road_note"] = note
	for r in known:
		var sid := String(r["id"])
		var h := _row(v, Catalog.spell(sid).get("name", sid), "L%d" % int(r["level"]), "road_" + sid, COL_DIM)
		h.tooltip_text = RoadSpells.text(sid)
		var b := Button.new()
		b.text = "Cast"
		b.disabled = not bool(r["castable"])
		b.tooltip_text = RoadSpells.text(sid) if r["castable"] else "No slot of level %d left" % int(r["level"])
		b.pressed.connect(cast_road.bind(sid))
		h.add_child(b)
		_fields["road_btn_" + sid] = b

func cast_road(sid: String) -> void:
	last_cast = RoadSpells.cast(party(), _ch, sid, party().world_now)
	_render()

# #176: who they are. Each trait's name and family, its line, and what it does —
# the effects this build applies in the verdigris every live number on this
# page wears, the ones still to come muted and marked so, never mistaken for a
# bonus the hero has.
func _traits(col: VBoxContainer) -> void:
	var v := _panel(col, "Personality traits")
	var ids: Array = Traits.ids(_ch)
	if ids.is_empty():
		_row(v, "—", "none yet")
		return
	for id in ids:
		_row(v, Traits.name_of(id), String(Traits.row(id).get("family", "")), "trait_" + id, COL_GOLD)
		var t := Label.new()
		t.text = String(Traits.row(id).get("text", ""))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(220, 0)
		t.theme_type_variation = "Dim"
		v.add_child(t)
		for line in Traits.effect_lines(id):
			var e := Label.new()
			e.text = "·  " + String(line["text"]) + ("" if line["live"] else "   (not yet in play)")
			e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			e.custom_minimum_size = Vector2(220, 0)
			e.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
			e.add_theme_color_override("font_color", COL_ACCENT if line["live"] else Icons.COL_MUTED)
			v.add_child(e)
		# #176 step 3: a scar or a wound says what mends it, and a lapsing one
		# how long it has left.
		var mend := Traits.mend_text(_ch, id, float(party().world_now))
		if mend != "":
			var m := Label.new()
			m.text = "Mends: " + mend
			m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			m.custom_minimum_size = Vector2(220, 0)
			m.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
			m.add_theme_color_override("font_color", Icons.COL_MUTED)
			v.add_child(m)

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
		# "Channel Divinity" with "Cleric" for the source, not "Cleric Channel
		# Divinity": the name is what you look for, where it came from is the
		# footnote.
		_row(v, Effects.verb_label(id), Effects.feature_source(id) + ("  ·  " + right if right != "" else ""), "feature_" + id, COL_DIM)
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
	if not equipped and Potions.is_potion(iid):
		# A potion is drunk, not worn: heal now, or a buff the next fight inherits.
		tip += "\n%s\n\nClick: drink" % Potions.text(iid)
		var d := Icons.item_tile(iid, tip, caption)
		d.pressed.connect(drink.bind(iid))
		g.add_child(d)
		_fields["item_" + iid] = d
		_fields["drink_btn_" + iid] = d
		return
	if kind == "unknown":
		_fields["item_" + iid] = Icons.item_tile(iid, tip, caption)
		g.add_child(_fields["item_" + iid])
		return
	var offhand: bool = equipped and kind == "weapon" and _ch.is_light(iid)
	if equipped:   # the tile is in the Equipped panel already; say which item it is
		caption = String(def.get("name", Effects.humanize(iid))) + (" (off-hand)" if _ch.offhand == iid else "")
	tip += "\n\nClick: %s" % ("unequip" if equipped else "equip")
	if offhand:
		tip += "\nRight-click: %s" % ("main hand" if _ch.offhand == iid else "off-hand")
	var b := Icons.item_tile(iid, tip, caption, Icons.ITEM_ART_PX, Icons.party_compare(kind, party(), def))
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

# The road door of core/potions.gd; the combat door is combat.gd's drink verb.
func drink(item_id: String) -> void:
	Potions.drink_on_road(party(), _ch, item_id, party().world_now)   # seeded in core: Potions.road_seed
	_render()

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
