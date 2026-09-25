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
const Portraits = preload("res://scenes/portraits.gd")
const Figures3D = preload("res://scenes/figures3d.gd")
const Traits = preload("res://core/traits.gd")
const Active = preload("res://core/active_effects.gd")   # #238

signal closed

# The six, in the book's order rather than alphabetical: a player reading a
# statblock is reading down a column they already know the shape of.
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]

# The portrait column: the WHOLE figure, not the bust the turn strip and the
# party page use. A bust answers "who is that" and this card already answers
# that in gilt at the top; what a full figure adds is what the thing actually
# looks like — how big it is, what it is carrying, whether it is armoured —
# which is most of what you want to know about something you have never fought
# before, and none of which a head shows.
#
# Taller than wide because a standing rig is roughly 1:2.6. A model the art does
# not cover renders nothing and the column simply is not built, which is the
# same fall-through scenes/figures3d.gd draws the board by.
const FIGURE_PX := Vector2i(92, 158)

var _who = null               # the Combatant this card is showing, or null
var _cb = null
var _sig := ""                # #238: what the card was last drawn from (see refresh)
var _rows := VBoxContainer.new()
# Where _line/_cap/_bar append: the column beside the portrait while the
# headline numbers are being written, then _rows again for everything that
# wants the card's whole width. The same shape scenes/creator/creator.gd's
# _target has, and for the same reason — one set of row helpers, two columns.
var _target: Container = null


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
	_sig = _signature()
	_render()


# #238: the card is sticky, so it outlives the moment it was drawn — the Bless
# landed, the goblin went prone, the hero dropped, and a card that only
# redrew on a NEW hover still showed the creature as it was. The screen calls
# this on every _refresh; it redraws only when something the card shows has
# changed, so a turn that touched nobody on it costs one string compare.
func refresh() -> void:
	if _who == null or not visible:
		return
	var sig := _signature()
	if sig == _sig:
		return
	_sig = sig
	_render()


# Everything the card reads off the fight that can change mid-fight: health,
# AC, the effects and their clocks, the death saves, cover.
func _signature() -> String:
	var c = _who
	var cb = _cb
	var chips: Array = Active.of(cb, c).map(func(x): return [x["id"], x["label"], x["clock"]])
	return var_to_str([c.hp, c.temp_hp, c.max_hp, cb.effective_ac(c), c.speed, chips,
		c.is_down(), c.is_dead(), c.death_s, c.death_f, cb.is_cover(c.pos)])


func _render() -> void:
	_target = null
	for n in _rows.get_children():
		_rows.remove_child(n)
		n.queue_free()
	var c = _who
	var cb = _cb

	# Figure on the left, the headline numbers beside it, and everything that
	# wants the full width underneath. The six-ability grid and the spell and
	# trait lists do not fit in what is left of a 260-380px column next to a
	# portrait, so they stay below it rather than being squeezed in beside.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_rows.add_child(top)
	var fig := _figure(c)
	if fig != null:
		top.add_child(fig)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 5)
	top.add_child(side)
	_target = side

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
	_into().add_child(head)

	_line("%s · %s" % [
		"Your company" if c.team == "party" else "Against you",
		cb.region_at(c.pos)], Icons.COL_MUTED)

	# Health first and as a bar, because it is the one number read at a glance.
	_bar(c.hp, c.max_hp, "%d / %d hp%s" % [maxi(0, c.hp), c.max_hp,
		"  +%d temp" % c.temp_hp if c.temp_hp > 0 else ""])
	_line("AC %d    Speed %d" % [cb.effective_ac(c), c.speed], Icons.COL_TEXT)
	_line("Proficiency +%d" % c.pb, Icons.COL_MUTED)
	# Back to the full width for everything that needs it.
	_target = null
	_now_row(c, cb)

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
	_into().add_child(grid)

	# What the damage types do to it — three lines that decide which spell to
	# reach for and were nowhere on the old card. Each type in its colour, so
	# "Resists fire" is the orange of the Fire Bolt badge's card.
	for pair in [["Resists", c.resist], ["Immune to", c.immune], ["Vulnerable to", c.vulnerable]]:
		if not (pair[1] as Array).is_empty():
			var kinds: Array = (pair[1] as Array).map(func(d): return Icons.damage_bb(String(d)))
			_rich_line("%s %s" % [pair[0], ", ".join(kinds)], Icons.COL_MUTED)

	# Spells and traits kept apart, which is the other half of what #173 asked
	# for. A verb carrying a `spell` is something cast; everything else is
	# something the creature simply IS, and reading them as one list was how a
	# dragon's Frightful Presence ended up looking like a cantrip.
	_verbs_row(c, true, "Spells")
	_verbs_row(c, false, "Traits")
	_personality_row(c, cb)


# The figure, or null when the art does not cover this class or faction — which
# is common enough that it is the expected case rather than an error. Rendered
# through scenes/portraits.gd, so it shares the cache, the lighting and the
# headless fall-through with every other face on screen.
func _figure(c) -> Control:
	var tex: Texture2D = Portraits.figure(Figures3D._model_path(c), FIGURE_PX)
	if tex == null:
		return null
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Icons.box(Icons.COL_INK, Icons.COL_EDGE, 2, 0, 0))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = FIGURE_PX
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(r)
	return frame


# #238: what is riding on it right now — conditions, buffs, held spells, with
# how long each has left. The words, tones and clocks are the effect strip's
# (core/active_effects.gd), the same chips the action bar shows for the hero
# whose turn it is, so "Bless 9 rounds" here and on the strip cannot disagree;
# this is the only place a FOE's buffs, or a hero's off their turn, are read.
# Straight under the health bar: a status is the thing that changed since you
# last looked, and the ability grid never does.
#
# Down, stable and dead are not chips (Active.HIDDEN: that is the health
# readout's job), so the death saves get a chip of their own here, and cover —
# a property of the hex, not a status — rides along at the end.
func _now_row(c, cb) -> void:
	var chips: Array = Active.of(cb, c)
	if c.is_down() and not c.is_dead():
		chips.push_front({"id": "down", "tone": Active.HINDRANCE, "clock": "",
			"label": "Stable" if c.is_stable() else "Down, saves %d/%d" % [c.death_s, c.death_f],
			"detail": "Unconscious at 0 HP. Healing brings them back up." if c.is_stable() \
				else "Death saves, %d succeeded and %d failed: three successes and they stabilise, three failures and they die." % [c.death_s, c.death_f]})
	if cb.is_cover(c.pos):
		chips.append({"id": "cover", "tone": Active.EDGE, "clock": "", "label": "In cover",
			"detail": "Half cover: +2 AC (already in the AC above) and +2 to DEX saves."})
	if chips.is_empty():
		return
	_cap("Right now")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 4)
	_into().add_child(flow)
	var Main = load("res://scenes/main.gd")
	for x in chips:
		flow.add_child(_effect_chip(x, Main))


# One effect as a chip: a condition in the colour it wears on the token's strip
# and in the log (Icons.CONDITION_COLORS) with its glyph, anything else in the
# strip's tone colour (main.gd's _tone_color). The clock in small muted type
# after the name, the description on hover — scenes/main.gd's _effect_chip,
# sized for the card.
func _effect_chip(x: Dictionary, Main) -> Control:
	var id := String(x["id"])
	var col: Color = Icons.condition_color(id) if Icons.CONDITION_COLORS.has(id) \
		else Main._tone_color(String(x["tone"]))
	var box := PanelContainer.new()
	var sb := Icons.box(Color(col, 0.12), col.darkened(0.15), 3, 6, 2)
	sb.border_width_left = 3
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var clock := String(x.get("clock", ""))
	box.tooltip_text = "%s%s\n%s" % [x["label"], (" — " + clock) if clock != "" else "",
		String(x.get("detail", ""))]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var l := Label.new()
	l.text = ("%s %s" % [Icons.condition_glyph(id), x["label"]]) if Icons.CONDITION_GLYPHS.has(id) \
		else String(x["label"])
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", col.lightened(0.25))
	row.add_child(l)
	if clock != "":
		var k := Label.new()
		k.text = clock
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
		k.add_theme_color_override("font_color", Icons.COL_MUTED)
		row.add_child(k)
	return box


# One chip per spell or trait, each explaining itself on hover.
#
# It was a comma-joined run of names, which tells a reader that a Bugbear has
# Surprise Attack and nothing whatever about what Surprise Attack does. The
# explanation already existed — it is the same text the action bar puts under
# a verb's badge — so this reuses main.gd's own _verb_tooltip rather than
# writing a second account of the same rules that could drift from it.
#
# load() rather than preload(), for the reason core/ladder.gd's header gives
# for the same trick: scenes/main.gd preloads THIS file, so a preload back the
# other way is a cycle. Resolved at call time, it is not.
#
# Chips rather than a run of text because a reader has to be able to SEE that
# there is something to hover: an underline-free label in a paragraph looks
# like prose, and prose does not have tooltips.
func _verbs_row(c, want_spell: bool, caption: String) -> void:
	var seen := {}
	var items: Array = []
	for v in c.verbs:
		var label := String(v.get("label", ""))
		if label == "" or seen.has(label) or v.has("spell") != want_spell:
			continue
		seen[label] = true
		items.append(v)
	if items.is_empty():
		return
	_cap(caption)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 4)
	_into().add_child(flow)
	var Main = load("res://scenes/main.gd")
	for v in items:
		flow.add_child(_verb_chip(c, v, Main))


# #176: the hero's personality traits — lit in gold where this board makes them
# count (core/traits.gd's fight-start stamp), muted where it does not. The
# card's "Traits" row above is the creature's non-spell verbs; this one is who
# the hero is, and the heading says which.
func _personality_row(c, cb) -> void:
	if c.traits.is_empty():
		return
	_cap("Personality traits")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 4)
	_into().add_child(flow)
	var live: Array = Traits.live_here(c, cb) if cb != null else []
	for id in c.traits:
		var here: bool = id in live
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Icons.box(Icons.COL_ROW,
			Icons.COL_GOLD if here else Icons.COL_EDGE, 3, 7, 3))
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		var lines: Array = Traits.effect_lines(id).map(func(l): return String(l["text"]) + ("" if l["live"] else "  (not yet in play)"))
		box.tooltip_text = "%s%s\n%s" % [Traits.name_of(id), "  — counts here" if here else "",
			"\n".join(lines)]
		var l := Label.new()
		l.text = Traits.name_of(id)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		l.add_theme_color_override("font_color", Icons.COL_GOLD if here else Icons.COL_BODY)
		box.add_child(l)
		flow.add_child(box)


func _verb_chip(c, v: Dictionary, Main) -> Control:
	var label := String(v["label"])
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Icons.box(Icons.COL_ROW, Icons.COL_EDGE, 3, 7, 3))
	# The tooltip is the point, so the chip has to take the mouse — a Label
	# alone ignores it and would never show one.
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var what := String(Main._verb_tooltip(c, v))
	box.tooltip_text = label if what == "" else "%s\n%s" % [label, what]
	var l := Label.new()
	l.text = label
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", Icons.COL_TEXT)
	box.add_child(l)
	return box


func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


func _into() -> Container:
	return _target if _target != null else _rows


func _cap(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Caption"
	_into().add_child(l)


func _line(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", col)
	_into().add_child(l)

# _line, for a line with coloured words in it (bbcode): conditions, damage types.
func _rich_line(bb: String, col: Color) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	r.add_theme_color_override("default_color", col)
	r.text = bb
	_into().add_child(r)


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
	_into().add_child(p)
	_line(caption, Icons.COL_BODY)
