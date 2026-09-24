# The hover card on an action-bar badge: what a spell or a swing is, in two
# voices, with the dice it rolls drawn beside the numbers.
#
# WHAT IT REPLACES. The engine's own tooltip — one run of plain text as wide as
# the screen let it be. Scorching Ray's SRD paragraph came out as a single
# 1080 px line across the whole board, then the numbers under it on another,
# and nothing told the story half from the rules half, or a fire spell from a
# cold one without reading the word.
#
# WHAT IT IS NOW. A card of fixed width (CARD_W, scaled with the bar), so a long
# description wraps into a column instead of a banner:
#
#   Burning Hands                          <- serif, in the school's colour
#   Level 1 evocation · Action · 15 ft     <- sans caption
#   [◢ Cone]                               <- the shape, as a tag
#   As you hold your hands with thumbs...  <- the lore: slanted serif
#   ─────────
#   Each creature in a 15-foot cone must...<- the rules: sans, terms tinted
#   (d20)  DC 13 DEX save, half on a success
#   (d6)(d6)(d6)  3d6 fire                  <- the dice, drawn (die_icon.gd)
#   level 1 slot                            <- the foot: what it costs
#
# THE TAG says how many it touches, which is the first thing a player needs
# from a spell and the one thing the old text never said up front: Single
# target, Cone, AoE (a sphere, a line, a ring around you), or Self.
#
# THE TWO VOICES. An SRD description opens with a sentence or two of picture
# ("a thin sheet of flames shoots forth...") and then turns into rules ("Each
# creature in a 15-foot cone must make..."). split_prose() cuts it where the
# first rules sentence starts — a sentence is rules if it names a die, a save,
# an attack roll, damage, hit points, a condition or a distance — and everything from there on
# is set in the sans face with the rest of the numbers. A description that is
# rules from its first word (Cure Wounds) simply has no lore half. The martial
# verbs have no SRD prose at all, so they carry a line of their own
# (scenes/main.gd KIND_LORE) over the rules blurb they always had.
#
# COLOUR is core/ui_icons.gd's DAMAGE_COLORS / CONDITION_COLORS, the same table
# the combat log and the combat card read: fire is one orange everywhere.
#
#   const SkillCard = preload("res://scenes/skill_card.gd")
#   var b := SkillCard.HoverButton.new()
#   b.tooltip_text = "Burning Hands\n..."        # still set: tests read it
#   b.card = SkillCard.from_verb(h, v, lore, rules, name)
#   # or leave b.card empty: the card is built from tooltip_text (first line
#   # the title, the rest the body), for the bar's own slots and controls.
#
# What it does NOT own: which verbs exist or what they do (core/combat.gd,
# core/rules/effects.gd), the plain tooltip string (main.gd _verb_tooltip,
# which tests and the drive robots still read), or when a card opens (the
# engine's tooltip timer — this only builds what it shows).
extends RefCounted

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const DieIcon = preload("res://scenes/die_icon.gd")

# Wide enough for a spell's rules sentence to wrap into three or four lines,
# narrow enough to sit over the bar without covering the board's middle.
const CARD_W := 340.0
const DIE_PX := 26.0          # a still die in a roll row
const MAX_DICE := 6           # past this a row shows six and the notation says the rest
const PROSE_CAP := 520        # characters of SRD prose before it is cut at a sentence

# The four shapes, each with a mark and a colour of its own so the tag reads
# before its word does.
const SHAPE_TAGS := {
	"single": ["◉", "Single target", Color("c9a45a")],
	"cone": ["◢", "Cone", Color("f08a3c")],
	"aoe": ["✹", "AoE", Color("e0643c")],
	"self": ["◈", "Self", Color("6fa89a")],
}

# A button whose tooltip is the card. `card` empty = build it from the text.
class HoverButton extends Button:
	const SkillCard = preload("res://scenes/skill_card.gd")
	var card := {}
	func _make_custom_tooltip(for_text: String) -> Object:
		return SkillCard.build(card if not card.is_empty() else SkillCard.from_text(for_text))

# --- the card's contents ----------------------------------------------------
#
# A card is a Dictionary, every key optional:
#   title, title_color, subtitle         the head
#   tags: [[glyph, text, Color]]         the shape tag (and anything else tag-shaped)
#   lore                                 plain text, the slanted serif
#   rules                                plain text, sans, damage/condition words tinted
#   rolls: [{sides, count, color, bb}]   a die row each: `count` dice of `sides`, then `bb`
#   facts: [bb]                          sans lines under the rolls
#   foot                                 bb, the muted cost line
#   alert: [text, Color]                 "Not available right now." / "Press again to confirm."

static func from_text(text: String) -> Dictionary:
	var lines := text.split("\n")
	var body: Array = []
	for i in range(1, lines.size()):
		body.append(lines[i])
	return {"title": lines[0] if lines.size() > 0 else "", "rules": "\n".join(body).strip_edges()}

# Which of the four tags a verb wears, and the size that goes with it.
static func shape_of(v: Dictionary) -> Array:
	var size_ft := int(v.get("size_ft", 0))
	match String(v.get("targeting", "self")):
		"enemy", "ally", "object":
			return ["single", ""]
		"direction":
			return ["cone", "%d ft" % size_ft if size_ft > 0 else ""]
		"line":
			return ["aoe", "%d ft line" % size_ft if size_ft > 0 else "line"]
		"self_area":
			return ["aoe", "%d ft around you" % size_ft if size_ft > 0 else "around you"]
		"allies":
			return ["aoe", "your side"]
		"hex", "corner", "area":
			if v.get("teleport", false):
				return ["self", "teleport"]
			return ["aoe", "%d ft radius" % size_ft if size_ft > 0 else ""]
	return ["self", ""]

# Lore first, rules after: see the header. Returns [lore, rules].
static var _re_sentence := RegEx.create_from_string("(?<=[.!?])\\s+(?=[A-Z])")
static var _re_rules := RegEx.create_from_string(
	"(?i)\\b(\\d*d\\d+|saving throw|save|damage|hit points?|attack roll|spell attack|advantage|disadvantage"
	+ "|condition|armor class|temporary|speed|\\d+[- ]f(?:oo|ee)t|using a higher-level|cantrip upgrade)\\b")

static func split_prose(text: String) -> Array:
	var sentences := _re_sentence.sub(text.strip_edges(), "\n", true).split("\n")
	var lore: Array = []
	var i := 0
	while i < sentences.size() and _re_rules.search(sentences[i]) == null:
		lore.append(sentences[i])
		i += 1
	var rules: Array = []
	for j in range(i, sentences.size()):
		rules.append(sentences[j])
	return [_cap(" ".join(lore)), _cap(" ".join(rules))]

static func _cap(s: String) -> String:
	if s.length() <= PROSE_CAP:
		return s
	var cut := s.left(PROSE_CAP).rfind(". ")
	return (s.left(cut + 1) if cut > PROSE_CAP * 0.5 else s.left(PROSE_CAP)) + " …"

# "1d6+3" -> [1, 6, 3]; [] if it is not dice.
static var _re_notation := RegEx.create_from_string("(\\d+)d(\\d+)\\s*(?:([+-])\\s*(\\d+))?")

static func parse_dice(s: String) -> Array:
	var m := _re_notation.search(s)
	if m == null:
		return []
	var bonus := int(m.get_string(4)) if m.get_string(4) != "" else 0
	return [int(m.get_string(1)), int(m.get_string(2)), -bonus if m.get_string(3) == "-" else bonus]

static func _notation(n: int, sides: int, bonus: int) -> String:
	return "%dd%d%s" % [n, sides, ("+%d" % bonus) if bonus > 0 else (("%d" % bonus) if bonus < 0 else "")]

static func _d20(bb: String) -> Dictionary:
	return {"sides": 20, "count": 1, "color": Icons.COL_HEAD, "bb": bb}

# Everything the card says about one verb. `lore` / `rules` are the prose the
# caller already chose (a spell's SRD text, else main.gd's KIND_LORE and
# KIND_BLURB); the numbers come off the verb itself, the same ones
# _verb_tooltip prints, so the card and the plain tooltip cannot disagree.
static func from_verb(h, v: Dictionary, lore: String, rules: String, title: String) -> Dictionary:
	var sid := String(v.get("spell", ""))
	var card := {"title": title, "lore": lore, "rules": rules, "rolls": [], "facts": []}
	var kind := String(v["kind"])
	var cost := String(v.get("cost", "action"))
	var head: Array = []
	if sid != "":
		var school := Icons.spell_school(sid)
		card["title_color"] = Icons.school_color(school)
		var base := int(Catalog.spell(sid).get("level", v.get("slot_level", 0)))
		head.append(("%s cantrip" % school.capitalize()) if base == 0
			else "Level %d %s" % [int(v.get("slot_level", base)), school])
	head.append({"action": "Action", "bonus": "Bonus action", "free": "Free", "reaction": "Reaction"}.get(cost, cost.capitalize()))
	var rng := _range_text(h, v)
	if rng != "":
		head.append(rng)
	if v.get("concentration", false):
		head.append("concentration")
	card["subtitle"] = " · ".join(head)

	var shape := shape_of(v)
	var t: Array = (SHAPE_TAGS[shape[0]] as Array).duplicate()
	if shape[1] != "":
		t[1] = "%s · %s" % [t[1], shape[1]]
	card["tags"] = [t]

	var rolls: Array = card["rolls"]
	var facts: Array = card["facts"]
	match kind:
		"attack":
			var a: Dictionary = h.attacks[0] if not h.attacks.is_empty() else {}
			rolls.append(_d20("[b]%+d[/b] to hit with %s" % [int(h.atk_bonus), a.get("name", "an unarmed strike")]))
			var d := parse_dice(String(h.damage))
			var dt := String(a.get("damage_type", ""))
			if not d.is_empty():
				rolls.append(_dmg(d[0], d[1], d[2], dt))
		"offhand_attack":
			rolls.append(_d20("[b]%+d[/b] to hit" % int(v.get("to_hit", 0))))
			var d := parse_dice(String(v.get("damage", "")))
			if not d.is_empty():
				rolls.append(_dmg(d[0], d[1], d[2], String(v.get("damage_type", ""))))
	if v.has("attack_bonus"):
		var rays := int(v.get("rays", 1))
		rolls.append(_d20("[b]%+d[/b] spell attack%s" % [int(v["attack_bonus"]),
			(", once for each of %d rays" % rays) if rays > 1 else ""]))
	elif int(v.get("rays", 1)) > 1:
		facts.append("%d rays, each rolled to hit" % int(v["rays"]))
	if String(v.get("save", "")) != "":
		rolls.append({"sides": 20, "count": 1, "color": Icons.COL_MUTED,
			"bb": "Target rolls a [b]DC %d %s[/b] save%s" % [int(v.get("save_dc", 0)), String(v["save"]).to_upper(),
			", half damage on a success" if v.get("half_on_save", false) else ""]})
	if v.has("dice_count") and v.has("dice_sides"):
		var bonus := int(v.get("dice_bonus", v.get("bonus_damage", 0)))
		if kind in ["heal_self", "heal_ally"]:
			rolls.append(_heal(int(v["dice_count"]), int(v["dice_sides"]), bonus, "HP back"))
		else:
			rolls.append(_dmg(int(v["dice_count"]), int(v["dice_sides"]), bonus, String(v.get("damage_type", ""))))
	if v.has("heal_count"):
		rolls.append(_heal(int(v["heal_count"]), int(v.get("heal_sides", 8)), int(v.get("heal_bonus", 0)), "HP back"))
	if v.has("temp_count") and int(v["temp_count"]) > 0:
		rolls.append(_heal(int(v["temp_count"]), int(v.get("temp_sides", 4)), int(v.get("temp_bonus", 0)), "temporary HP"))

	if kind == "dash":
		facts.append("+%d hexes of movement this turn" % int(h.speed))
	if kind == "grant_action":
		facts.append("+%d action this turn" % int(v.get("amount", 1)))
	if kind == "drink" and String(v.get("text", "")) != "":
		facts.append(Icons.tint_terms(String(v["text"])))
	elif String(v.get("text", "")) != "" and sid == "":
		facts.append(Icons.tint_terms(String(v["text"])))
	if int(v.get("targets", 1)) > 1:
		facts.append("Up to %d targets within 30 ft of each other" % int(v["targets"]))
	if not v.get("conditions", []).is_empty():
		var cs: Array = (v["conditions"] as Array).map(func(c): return Icons.condition_bb(String(c)))
		var until := String({"round": "until its next turn", "concentration": "while you concentrate"}.get(
			String(v.get("duration", "")), ""))
		facts.append("Inflicts %s%s" % [", ".join(cs), (" " + until) if until != "" else ""])
	if int(v.get("bonus_damage", 0)) > 0 and not v.has("dice_count"):
		facts.append("+%d damage on your hits" % int(v["bonus_damage"]))
	if int(v.get("extra_attacks", 0)) > 0:
		var n := int(v["extra_attacks"])
		facts.append("+%d attack%s" % [n, "" if n == 1 else "s"])
	if v.has("amount") and not v.has("dice_count") and kind != "grant_action":
		facts.append("Amount: %d" % int(v["amount"]))
	if not v.get("resist", []).is_empty():
		var rs: Array = (v["resist"] as Array).map(func(d): return Icons.damage_bb(String(d)))
		facts.append("Resist %s" % ", ".join(rs))

	var foot: Array = []
	if int(v.get("slot_level", 0)) > 0:
		foot.append("uses a level %d slot" % int(v["slot_level"]))
	if v.has("pool"):
		foot.append("%d of %d uses left" % [h.pool_left(v["pool"]), int(h.pools[v["pool"]]["max"])])
	card["foot"] = " · ".join(foot)
	return card

static func _range_text(h, v: Dictionary) -> String:
	var tg := String(v.get("targeting", "self"))
	if tg in ["self", "self_area", "allies", "direction"]:   # a cone starts at your hand; its size is on the tag
		return ""
	if v.has("range_ft"):
		var ft := int(v["range_ft"])
		return "touch" if ft <= 5 else "%d ft" % ft
	if String(v["kind"]) == "attack":
		var r := int(h.atk_range)
		return "reach %d hex%s" % [r, "" if r == 1 else "es"]
	if v.has("range"):
		var r := int(v["range"])
		return "reach %d hex%s" % [r, "" if r == 1 else "es"]
	return ""

static func _dmg(n: int, sides: int, bonus: int, dtype: String) -> Dictionary:
	var col := Icons.damage_color(dtype) if dtype != "" else Icons.COL_HEAD
	var word := Icons.damage_bb(dtype.to_lower(), dtype.to_lower()) if dtype != "" else "damage"
	return {"sides": sides, "count": n, "color": col,
		"bb": "[b]%s[/b] %s%s" % [_notation(n, sides, bonus), word, " damage" if dtype != "" else ""]}

static func _heal(n: int, sides: int, bonus: int, what: String) -> Dictionary:
	var col: Color = Icons.DAMAGE_COLORS["healing"]
	return {"sides": sides, "count": n, "color": col,
		"bb": "[b]%s[/b] [color=%s]%s[/color]" % [_notation(n, sides, bonus), col.to_html(false), what]}

# --- the card, built ----------------------------------------------------------

static func build(card: Dictionary) -> Control:
	var u := Settings.chrome_scale()
	var w := CARD_W * u
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 4, int(14 * u), int(10 * u)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(5 * u))
	panel.add_child(col)

	if card.has("alert"):
		var al: Array = card["alert"]
		col.add_child(_label(String(al[0]), Icons.sans(700), int(Icons.FS_SMALL * u), al[1], w))
	# What a buff or condition does to this button (core/active_effects.gd), in
	# the colour of the mark on the badge's corner: [[why, colour], ...].
	for fx in card.get("effects", []):
		col.add_child(_label(String(fx[0]), Icons.sans(600), int(Icons.FS_SMALL * u), fx[1], w))

	var title := _label(String(card.get("title", "")), Icons.serif(700), int((Icons.FS_HEAD - 1) * u),
		card.get("title_color", Icons.COL_HEAD), w)
	col.add_child(title)
	if String(card.get("subtitle", "")) != "":
		var sub := _label(String(card["subtitle"]), Icons.sans(500), int(Icons.FS_CAPTION * u), Icons.COL_MUTED, w)
		sub.add_theme_constant_override("line_spacing", 0)
		col.add_child(sub)

	var tags: Array = card.get("tags", [])
	if not tags.is_empty():
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", int(6 * u))
		for t in tags:
			row.add_child(_tag(String(t[0]), String(t[1]), t[2], u))
		col.add_child(row)

	var lore := String(card.get("lore", ""))
	if lore != "":
		var l := _label(lore, Icons.serif_italic(), int((Icons.FS_BODY - 1) * u), Icons.COL_BODY, w)
		# Alegreya's own line height is a book's, and at card size it double-spaced
		# three lines of lore into a column taller than the rules under it.
		l.add_theme_constant_override("line_spacing", int(-5 * u))
		col.add_child(l)

	var rules := String(card.get("rules", ""))
	var rolls: Array = card.get("rolls", [])
	var facts: Array = card.get("facts", [])
	if rules != "" or not rolls.is_empty() or not facts.is_empty():
		if lore != "":
			col.add_child(_rule(u))
		if rules != "":
			col.add_child(_rich(Icons.tint_terms(rules), int(Icons.FS_SMALL * u), Icons.COL_TEXT, w))
		for r in rolls:
			col.add_child(_roll_row(r, u, w))
		for f in facts:
			col.add_child(_rich("•  " + String(f), int(Icons.FS_SMALL * u), Icons.COL_TEXT, w))

	if String(card.get("foot", "")) != "":
		col.add_child(_rich(String(card["foot"]), int(Icons.FS_CAPTION * u), Icons.COL_MUTED, w))
	return panel

static func _label(text: String, font: Font, fs: int, c: Color, w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l

static func _rich(bb: String, fs: int, c: Color, w: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(w, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", Icons.sans(400))
	r.add_theme_font_override("bold_font", Icons.sans(700))
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.add_theme_color_override("default_color", c)
	r.text = bb
	return r

# A shape tag: the mark and the word, on a dark chip edged in the tag's colour.
static func _tag(glyph: String, text: String, c: Color, u: float) -> Control:
	var chip := PanelContainer.new()
	var box := Icons.box(Color(c, 0.14), Color(c, 0.7), 3, int(7 * u), int(1 * u))
	chip.add_theme_stylebox_override("panel", box)
	var l := Label.new()
	l.text = "%s  %s" % [glyph, text]
	l.add_theme_font_override("font", Icons.sans(700))
	l.add_theme_font_size_override("font_size", int(Icons.FS_CAPTION * u))
	l.add_theme_color_override("font_color", c.lightened(0.15))
	chip.add_child(l)
	return chip

# The hairline between the two voices.
static func _rule(u: float) -> Control:
	var r := ColorRect.new()
	r.color = Color(Icons.COL_GOLD_EDGE, 0.8)
	r.custom_minimum_size = Vector2(0, maxf(1.0, u))
	return r

# One roll: its dice, drawn, then what they add up to.
static func _roll_row(r: Dictionary, u: float, w: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(3 * u))
	var n := int(r.get("count", 1))
	var shown := mini(n, MAX_DICE)
	var px := DIE_PX * u
	var dice_w := 0.0
	for i in shown:
		var d := DieIcon.new()
		d.sides = int(r.get("sides", 20))
		d.color = r.get("color", Icons.COL_HEAD)
		d.custom_minimum_size = Vector2(px, px)
		d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(d)
		dice_w += px + 3 * u
	if n > shown:
		var more := Label.new()
		more.text = "+%d" % (n - shown)
		more.add_theme_font_size_override("font_size", int(Icons.FS_CAPTION * u))
		more.add_theme_color_override("font_color", Icons.COL_MUTED)
		row.add_child(more)
		dice_w += more.get_minimum_size().x + 3 * u
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4 * u, 0)
	row.add_child(gap)
	var text := _rich(String(r.get("bb", "")), int(Icons.FS_SMALL * u), Icons.COL_TEXT, maxf(80.0 * u, w - dice_w - 7 * u))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	return row
