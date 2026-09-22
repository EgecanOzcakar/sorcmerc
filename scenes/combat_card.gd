# Issue #173 — who is that, on the left, and staying there.
#
# WHAT IT REPLACES. Board._stat_card: four lines in a box that floated beside
# the token and vanished the moment the mouse moved off it. You could read a
# foe's AC or you could reach for a button, never both, and it never showed an
# ability score or told a spell from a trait — every verb the creature had went
# into one comma-separated run.
#
# STICKY IS THE WHOLE POINT. A hover fills this card and then leaves it filled.
# Moving the mouse away does nothing; moving it over somebody ELSE swaps the
# card to them; the ✕ clears it. That is what makes it usable for the thing a
# player actually wants it for — reading a statblock while choosing the verb to
# answer it with — which a card that lives under the cursor cannot be.
#
# WHAT IT DELIBERATELY DOES NOT DO. Nothing here reads or writes the fight. It
# takes a Combatant and a Combat, asks them questions both already answer for
# the HUD, and builds Labels. No targeting, no selection, no turn — a card that
# could change the fight would need every guard main.gd's action bar has.
extends PanelContainer

const Icons = preload("res://core/ui_icons.gd")

signal closed

# The six, in the book's order rather than alphabetical: a player reading a
# statblock is reading down a column they already know the shape of.
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

var _who = null               # the Combatant this card is showing, or null
var _cb = null
var _rows := VBoxContainer.new()


func _init() -> void:
	add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 3, 10, 8))
	_rows.add_theme_constant_override("separation", 5)
	add_child(_rows)
	visible = false


func showing() -> String:
	return "" if _who == null else String(_who.id)


func clear() -> void:
	_who = null
	visible = false


# The one entry point. Idempotent on the same combatant so a mouse crossing
# three hexes of one big creature does not rebuild the card three times.
func show_who(c, cb) -> void:
	if c == null:
		return
	if _who != null and _who.id == c.id and visible:
		return
	_who = c
	_cb = cb
	visible = true
	_render()


func _render() -> void:
	for n in _rows.get_children():
		_rows.remove_child(n)
		n.queue_free()
	var c = _who
	var cb = _cb

	var head := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = String(c.cname)
	name_lbl.theme_type_variation = "Serif"
	name_lbl.add_theme_color_override("font_color",
		Icons.COL_GOLD if c.team == "party" else Icons.COL_FOE)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name_lbl)
	var x := Button.new()
	Icons.clicks(x)
	x.text = "✕"
	x.tooltip_text = "Close this card"
	x.pressed.connect(func():
		clear()
		closed.emit())
	head.add_child(x)
	_rows.add_child(head)

	_line("%s · %s" % [
		"Your company" if c.team == "party" else "Against you",
		cb.region_at(c.pos)], Icons.COL_MUTED)

	# Health first and as a bar, because it is the one number read at a glance.
	_bar(c.hp, c.max_hp, "%d / %d hp%s" % [maxi(0, c.hp), c.max_hp,
		"  +%d temp" % c.temp_hp if c.temp_hp > 0 else ""])
	_line("AC %d    Speed %d    Prof +%d" % [cb.effective_ac(c), c.speed, c.pb], Icons.COL_TEXT)

	# "stats -/+": the six, signed. For a hero the score is shown beside the
	# modifier because the sheet has one; a monster has no ability scores in this
	# catalog, only the save bonuses it rolls, so it gets those and says so.
	_cap("Saves" if c.sheet == null else "Abilities")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	for a in ABILITIES:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		if c.sheet != null:
			var score: int = int(c.sheet.abilities[a]["total"])
			lbl.text = "%s %2d %s" % [a.to_upper(), score, _signed(int(c.sheet.abilities[a]["mod"]))]
		else:
			lbl.text = "%s %s" % [a.to_upper(), _signed(int(c.saves.get(a, 0)))]
		lbl.add_theme_color_override("font_color", Icons.COL_BODY)
		grid.add_child(lbl)
	_rows.add_child(grid)

	var tags: Array = []
	for s in Icons.CONDITION_ORDER:
		if s != "down" and c.has(s):
			tags.append("%s %s" % [Icons.condition_glyph(s), s])
	if c.is_down():
		tags.append("%s down %d/%d" % [Icons.condition_glyph("down"), c.death_s, c.death_f])
	if cb.is_cover(c.pos):
		tags.append("in cover")
	if not tags.is_empty():
		_cap("Right now")
		_line(" · ".join(tags), Icons.COL_ACCENT)

	# What the damage types do to it — three lines that decide which spell to
	# reach for and were nowhere on the old card.
	for pair in [["Resists", c.resist], ["Immune to", c.immune], ["Vulnerable to", c.vulnerable]]:
		if not (pair[1] as Array).is_empty():
			_line("%s %s" % [pair[0], ", ".join(pair[1])], Icons.COL_MUTED)

	# Spells and traits kept apart, which is the other half of what #173 asked
	# for. A verb carrying a `spell` is something cast; everything else is
	# something the creature simply IS, and reading them as one list was how a
	# dragon's Frightful Presence ended up looking like a cantrip.
	var spells: Array = []
	var traits: Array = []
	for v in c.verbs:
		var label := String(v.get("label", ""))
		if label == "":
			continue
		var into: Array = spells if v.has("spell") else traits
		if not label in into:
			into.append(label)
	if not spells.is_empty():
		_cap("Spells")
		_line(", ".join(spells), Icons.COL_TEXT)
	if not traits.is_empty():
		_cap("Traits")
		_line(", ".join(traits), Icons.COL_TEXT)


func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


func _cap(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Caption"
	_rows.add_child(l)


func _line(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", col)
	_rows.add_child(l)


# The one drawn thing on the card. A number says how hurt something is; a bar
# says it without being read.
func _bar(have: int, whole: int, caption: String) -> void:
	var p := ProgressBar.new()
	p.max_value = maxi(1, whole)
	p.value = clampi(have, 0, whole)
	p.show_percentage = false
	p.custom_minimum_size.y = 14
	var fill := Icons.box(Icons.COL_FOE if _who.team == "foe" else Icons.COL_ACCENT,
		Color(0, 0, 0, 0), 2, 0, 0)
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", Icons.box(Icons.COL_INK, Icons.COL_EDGE, 2, 0, 0))
	_rows.add_child(p)
	_line(caption, Icons.COL_BODY)
