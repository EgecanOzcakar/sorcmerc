# The one place the UI's visual vocabulary lives: glyphs (class / spell school /
# condition), the rarity colour ramp, the shared palette and the type scale.
# Every screen imports this rather than hardcoding a mark or a font size.
#
# Glyph rule: monochrome symbol codepoints only (U+2000–U+2BFF). Emoji render in
# their own colours and fight the drawn shape language — and several of the ones
# this project reached for first (👁, 🛡, 🗡) are plain tofu in the default font.
# tests/shot_icons.gd renders the whole sheet to a PNG; look there before adding one.
extends RefCounted

const Catalog = preload("res://core/rules/catalog.gd")
const Sound = preload("res://core/audio.gd")


# --- the click -------------------------------------------------------------
#
# assets/audio/sfx/click.wav shipped with the T27 audio pass and, until this,
# nothing in the game played it: every screen builds its own buttons and none of
# them made a sound. This is the one place that changes.
#
# It ATTACHES to a button you already built rather than building one for you.
# A constructor-style factory was the obvious shape and the wrong one — the 23
# button sites across the menu screens set tooltip_text, disabled, toggle_mode,
# custom text and half a dozen different callback signatures between them, so a
# factory would have had to grow a parameter for each and every call site would
# have been rewritten around it. This way a site gains one wrapper and keeps its
# own setup verbatim:
#
#   row.add_child(Icons.clicks(b))      # or Icons.clicks(b) on its own line
#
# Returns the button so it chains into an add_child(). Safe headless and safe
# before the Audio autoload exists: play_sfx is a no-op static until then.
#
# Deliberately NOT applied to OptionButton — `pressed` on a dropdown fires when
# the list opens, not when a choice is made, so it would click on the wrong half
# of the interaction. Those want an item_selected sound, which is a different
# cue and not one this project has.
static func clicks(b: BaseButton) -> BaseButton:
	b.pressed.connect(func(): Sound.play_sfx("click"))
	return b

# --- palette ---------------------------------------------------------------
# The company ledger by lamplight: a warm near-black ground (oiled leather, not
# blue-grey), gilt for the one thing on a screen that matters, verdigris where
# the old build used a cool blue for "information". Screens alias these into
# their own COL_* constants so their local names keep working.
const COL_BG := Color("17130f")          # screen background
const COL_PANEL := Color("221c16")       # card / panel fill
const COL_ROW := Color("1d1813")         # the alternate ledger row
const COL_INK := Color("0f0c09")         # deep inset fill (log box, profile panels)
const COL_EDGE := Color("4a3d2c")        # quiet border — tarnished brass
const COL_GOLD := Color("c9a45a")        # captions, accents, the primary button
const COL_GOLD_EDGE := Color("7a6234")   # gilt panel border
const COL_HEAD := Color("f1e6cf")        # headline text
const COL_TEXT := Color("dcd3c2")        # body text
const COL_BODY := Color("b9ae9b")        # secondary body text
const COL_MUTED := Color("8a7f6e")       # captions/hints, disabled prose
const COL_ACCENT := Color("6fa89a")      # informational highlight — verdigris
const COL_PARTY := Color("7fbf6a")
const COL_FOE := Color("d35a4a")

# --- type ------------------------------------------------------------------
# Two faces from one hand (Huerta Tipográfica, OFL): Alegreya carries every
# title, name and sentence; Alegreya Sans carries controls, stats and the log.
# DejaVu stays as the glyph fallback — the class / school marks are symbol
# codepoints neither Alegreya face draws.
const FS_TITLE := 32      # the screen's one headline
const FS_HEAD := 21       # section / card title
const FS_BODY := 16       # default running text and button labels
const FS_SMALL := 14      # secondary rows, hints, journal
const FS_CAPTION := 14    # panel captions — sentence case, gilt, no tracking

static var _fonts := {}

static func _font(kind: String) -> Font:
	if _fonts.is_empty():
		var fallback: Font = load("res://assets/fonts/DejaVuSans.ttf")
		var serif_file: FontFile = load("res://assets/fonts/Alegreya-Variable.ttf")
		serif_file.fallbacks = [fallback]
		for w in [400, 500, 700]:
			var v := FontVariation.new()
			v.base_font = serif_file
			v.variation_opentype = {"wght": w}
			_fonts["serif%d" % w] = v
		for w in [["", 400], ["-Medium", 500], ["-Bold", 700]]:
			var f: FontFile = load("res://assets/fonts/AlegreyaSans%s.ttf" % ("-Regular" if w[0] == "" else w[0]))
			f.fallbacks = [fallback]
			_fonts["sans%d" % w[1]] = f
	return _fonts[kind]

static func serif(weight := 400) -> Font:
	return _font("serif%d" % weight)

static func sans(weight := 400) -> Font:
	return _font("sans%d" % weight)

# A flat leather block with a darker bottom edge — the button, the field, the
# row. Radius 3 on anything you press, 0 on anything you read.
static func box(bg: Color, edge := Color(0, 0, 0, 0), radius := 3, pad_x := 12, pad_y := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x; s.content_margin_right = pad_x
	s.content_margin_top = pad_y; s.content_margin_bottom = pad_y
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(1)
	return s

static func _pressable(bg: Color, pad_y: int) -> StyleBoxFlat:
	var s := box(bg, Color(0, 0, 0, 0), 3, 12, pad_y)
	s.border_color = bg.darkened(0.45)
	s.border_width_bottom = 2
	return s

# The one theme every screen wears, applied once at the front door
# (scenes/game/game.gd) and inherited by everything under it. Type variations
# are the vocabulary a screen speaks — `l.theme_type_variation = "Title"` —
# instead of a font-size and a colour override on every label:
#
#   Label:   Title  Head  Caption  Dim  Stat  Gilt  Serif
#   Button:  Primary  Quiet  Key
#   Panel:   Card  Inset  Row  RowAlt  Gilt
#
# `compact` is the inline-control variant (the profile's ± / equip buttons sit
# inside text rows).
static func dark_theme(compact := false) -> Theme:
	var th := Theme.new()
	var pad := 3 if compact else 6
	th.default_font = sans()
	th.default_font_size = FS_BODY

	# buttons
	th.set_stylebox("normal", "Button", _pressable(Color("2e261d"), pad))
	th.set_stylebox("hover", "Button", _pressable(Color("3b3125"), pad))
	th.set_stylebox("pressed", "Button", _pressable(Color("4a3d2c"), pad))
	th.set_stylebox("disabled", "Button", _pressable(Color("1e1913"), pad))
	th.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), COL_GOLD, 3, 12, pad))
	th.set_color("font_color", "Button", COL_TEXT)
	th.set_color("font_hover_color", "Button", COL_HEAD)
	th.set_color("font_pressed_color", "Button", COL_HEAD)
	th.set_color("font_disabled_color", "Button", COL_MUTED)
	th.set_font("font", "Button", sans(500))
	th.set_font_size("font_size", "Button", FS_BODY)
	# the one gilt button a screen gets
	th.set_type_variation("Primary", "Button")
	th.set_stylebox("normal", "Primary", _pressable(COL_GOLD, pad))
	th.set_stylebox("hover", "Primary", _pressable(Color("dbb86a"), pad))
	th.set_stylebox("pressed", "Primary", _pressable(Color("b08d47"), pad))
	th.set_stylebox("disabled", "Primary", _pressable(Color("5a4a2c"), pad))
	th.set_color("font_color", "Primary", COL_INK)
	th.set_color("font_hover_color", "Primary", COL_INK)
	th.set_color("font_pressed_color", "Primary", COL_INK)
	th.set_font("font", "Primary", sans(700))
	# the chosen one of a set of options: the block with a gilt rim
	th.set_type_variation("Picked", "Button")
	for st in ["normal", "hover", "pressed"]:
		var pk := _pressable(Color("3b3125"), pad)
		pk.border_color = COL_GOLD
		pk.set_border_width_all(1)
		pk.border_width_bottom = 2
		th.set_stylebox(st, "Picked", pk)
	th.set_stylebox("disabled", "Picked", _pressable(Color("1e1913"), pad))
	th.set_color("font_color", "Picked", COL_GOLD)
	th.set_color("font_hover_color", "Picked", COL_HEAD)
	th.set_font("font", "Picked", sans(700))
	# a button that reads as a link: no block, gilt text
	th.set_type_variation("Quiet", "Button")
	for st in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(st, "Quiet", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, pad))
	th.set_color("font_color", "Quiet", COL_GOLD)
	th.set_color("font_hover_color", "Quiet", COL_HEAD)
	# a key cap: the combat bar's [1]…[9]
	th.set_type_variation("Key", "Button")
	th.set_stylebox("normal", "Key", _pressable(Color("2e261d"), pad))
	th.set_stylebox("hover", "Key", _pressable(Color("3b3125"), pad))
	th.set_stylebox("pressed", "Key", _pressable(COL_GOLD_EDGE, pad))
	th.set_font("font", "Key", sans(500))

	for t in ["OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		th.set_stylebox("normal", t, _pressable(Color("2e261d"), pad))
		th.set_stylebox("hover", t, _pressable(Color("3b3125"), pad))
		th.set_stylebox("pressed", t, _pressable(Color("4a3d2c"), pad))
		th.set_stylebox("disabled", t, _pressable(Color("1e1913"), pad))
		th.set_stylebox("focus", t, box(Color(0, 0, 0, 0), COL_GOLD, 3, 12, pad))
		th.set_color("font_color", t, COL_TEXT)
		th.set_color("font_hover_color", t, COL_HEAD)
	th.set_stylebox("normal", "LineEdit", box(COL_INK, COL_EDGE, 3, 10, pad))
	th.set_stylebox("focus", "LineEdit", box(COL_INK, COL_GOLD, 3, 10, pad))
	th.set_color("font_color", "LineEdit", COL_HEAD)
	th.set_color("caret_color", "LineEdit", COL_GOLD)
	th.set_stylebox("panel", "PopupMenu", box(COL_PANEL, COL_EDGE, 3, 6, 6))
	th.set_stylebox("hover", "PopupMenu", box(Color("3b3125"), Color(0, 0, 0, 0), 2, 8, 4))
	th.set_color("font_color", "PopupMenu", COL_TEXT)
	th.set_color("font_hover_color", "PopupMenu", COL_HEAD)
	th.set_stylebox("panel", "TooltipPanel", box(COL_INK, COL_GOLD_EDGE, 3, 10, 8))
	th.set_color("font_color", "TooltipLabel", COL_TEXT)

	# labels
	th.set_color("font_color", "Label", COL_TEXT)
	th.set_font_size("font_size", "Label", FS_BODY)
	th.set_type_variation("Title", "Label")
	th.set_font("font", "Title", serif(500))
	th.set_font_size("font_size", "Title", FS_TITLE)
	th.set_color("font_color", "Title", COL_HEAD)
	th.set_type_variation("Head", "Label")
	th.set_font("font", "Head", serif(500))
	th.set_font_size("font_size", "Head", FS_HEAD)
	th.set_color("font_color", "Head", COL_HEAD)
	th.set_type_variation("Serif", "Label")   # a name or a sentence at body size
	th.set_font("font", "Serif", serif())
	th.set_font_size("font_size", "Serif", FS_BODY + 1)
	th.set_type_variation("Caption", "Label")
	th.set_font("font", "Caption", sans(700))
	th.set_font_size("font_size", "Caption", FS_CAPTION)
	th.set_color("font_color", "Caption", COL_GOLD)
	th.set_type_variation("Gilt", "Label")
	th.set_color("font_color", "Gilt", COL_GOLD)
	th.set_type_variation("Dim", "Label")
	th.set_font_size("font_size", "Dim", FS_SMALL)
	th.set_color("font_color", "Dim", COL_MUTED)
	th.set_type_variation("Stat", "Label")
	th.set_font("font", "Stat", sans(500))
	th.set_color("font_color", "Stat", COL_HEAD)
	th.set_color("default_color", "RichTextLabel", COL_TEXT)
	th.set_font("normal_font", "RichTextLabel", sans())
	th.set_font("bold_font", "RichTextLabel", sans(700))
	th.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)

	# panels
	th.set_stylebox("panel", "PanelContainer", box(COL_PANEL, Color(0, 0, 0, 0), 0, 14, 10))
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", box(COL_PANEL, COL_EDGE, 0, 14, 10))
	th.set_type_variation("Inset", "PanelContainer")
	th.set_stylebox("panel", "Inset", box(COL_INK, COL_EDGE, 0, 12, 10))
	th.set_type_variation("Gilt", "PanelContainer")
	th.set_stylebox("panel", "Gilt", box(COL_PANEL, COL_GOLD_EDGE, 0, 14, 10))
	th.set_type_variation("Row", "PanelContainer")
	th.set_stylebox("panel", "Row", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 6))
	th.set_type_variation("RowAlt", "PanelContainer")
	th.set_stylebox("panel", "RowAlt", box(COL_ROW, Color(0, 0, 0, 0), 0, 10, 6))
	# the picked row: a gilt bar down its left edge, nothing else
	th.set_type_variation("RowPicked", "PanelContainer")
	var picked := box(COL_ROW, Color(0, 0, 0, 0), 0, 10, 6)
	picked.border_color = COL_GOLD
	picked.border_width_left = 3
	th.set_stylebox("panel", "RowPicked", picked)

	th.set_stylebox("panel", "ScrollContainer", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	th.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	th.set_stylebox("grabber", "VScrollBar", box(COL_EDGE, Color(0, 0, 0, 0), 2, 0, 0))
	th.set_stylebox("grabber_highlight", "VScrollBar", box(COL_GOLD_EDGE, Color(0, 0, 0, 0), 2, 0, 0))
	th.set_stylebox("grabber_pressed", "VScrollBar", box(COL_GOLD, Color(0, 0, 0, 0), 2, 0, 0))
	th.set_stylebox("panel", "Tree", box(COL_INK, COL_EDGE, 0, 6, 6))
	th.set_stylebox("normal", "TextEdit", box(COL_INK, COL_EDGE, 0, 10, 8))
	th.set_color("font_color", "TextEdit", COL_TEXT)
	th.set_stylebox("background", "ProgressBar", box(COL_INK, Color(0, 0, 0, 0), 0, 0, 0))
	th.set_stylebox("fill", "ProgressBar", box(COL_GOLD, Color(0, 0, 0, 0), 0, 0, 0))
	th.set_stylebox("separator", "HSeparator", box(COL_EDGE, Color(0, 0, 0, 0), 0, 0, 0))
	th.set_constant("separation", "HSeparator", 1)
	return th

# --- class glyphs ----------------------------------------------------------
const CLASS_GLYPHS := {
	"barbarian": "⚒",   # crossed tools — the axe mark
	"bard": "♫",
	"cleric": "☩",   # a cross of crosses — reads apart from the rogue's dagger
	"druid": "☘",
	"fighter": "⚔",
	"monk": "✺",        # ki burst
	"paladin": "✠",
	"ranger": "➶",
	"rogue": "†",       # a dagger, literally
	"sorcerer": "✦",    # innate spark
	"warlock": "❂",     # the patron's eldritch star
	"wizard": "☰",      # a page of runes
}

static func class_glyph(class_id: String) -> String:
	return String(CLASS_GLYPHS.get(class_id, ""))

# The class a multiclassed sheet reads as: the one with the most levels.
static func primary_class(sheet) -> String:
	if sheet == null:
		return ""
	var best := ""
	var top := 0
	for cid in sheet.class_levels:
		if int(sheet.class_levels[cid]) > top:
			top = int(sheet.class_levels[cid])
			best = cid
	return best

# Monsters carry no sheet and so no class mark — they read by creature type instead.
# ponytail: nine types mapped, the rest fall back to melee/ranged marks.
const FOE_GLYPHS := {
	"undead": "☠", "dragon": "➳", "beast": "❦", "fiend": "✖", "plant": "☘",
	"ooze": "◕", "construct": "⚙", "celestial": "✧", "aberration": "◍",
}

# Heroes get their class mark, monsters their creature-type mark.
static func combatant_glyph(c) -> String:
	if c.sheet != null:
		return class_glyph(primary_class(c.sheet))
	var mtype := String(Catalog.monster(c.src_id).get("type", ""))
	return String(FOE_GLYPHS.get(mtype, "➶" if c.ranged else "⚔"))

# --- campaign map nodes ----------------------------------------------------
const NODE_GLYPHS := {"combat": "⚔", "treasure": "◆", "merchant": "⚖", "rest": "♨",
	"boss": "★"}

static func node_glyph(kind: String) -> String:
	return String(NODE_GLYPHS.get(kind, "·"))

# --- spell schools ---------------------------------------------------------
const SCHOOL_GLYPHS := {
	"abjuration": "⬡", "conjuration": "⊕", "divination": "◎", "enchantment": "❥",
	"evocation": "✹", "illusion": "◇", "necromancy": "☠", "transmutation": "⟳",
}
const SCHOOL_COLORS := {
	"abjuration": Color("6f9bd8"), "conjuration": Color("d98f4a"),
	"divination": Color("8fd0d8"), "enchantment": Color("d47fc0"),
	"evocation": Color("e0643c"), "illusion": Color("9d8fd8"),
	"necromancy": Color("79a86b"), "transmutation": Color("c9a45a"),
}

static func school_glyph(school: String) -> String:
	return String(SCHOOL_GLYPHS.get(school, "·"))

static func school_color(school: String) -> Color:
	return SCHOOL_COLORS.get(school, COL_MUTED)

static func spell_school(spell_id: String) -> String:
	return String(Catalog.spell(spell_id).get("school", ""))

# --- action-bar verb glyphs -------------------------------------------------
# One mark per verb `kind` (scenes/main.gd's BASIC + combat.gd's OFFERABLE) —
# the action bar's icon-forward T-actionbar redesign. "spell" isn't listed:
# a spell button uses school_glyph(spell_school(...)) instead, since a school
# mark is more informative than one generic wand icon for every spell.
const VERB_GLYPHS := {
	"attack": "⚔", "offhand_attack": "⚔",
	"shove": "⇉", "smash": "⚒", "help": "✚",
	"dodge": "◈", "dash": "➤", "disengage": "↩", "hide": "☁",
	"heal_self": "☤", "heal_ally": "☤",
	"self_buff": "⬆", "ally_buff": "⬆",
	"grant_action": "⏩", "attack_modifier": "◎", "save_effect": "⚡",
}

static func verb_glyph(kind: String) -> String:
	return String(VERB_GLYPHS.get(kind, "·"))

# --- action-bar icons ------------------------------------------------------
# The glyphs above are the fallback now, not the mark. A codepoint is whatever
# the shipped font decided it looks like: DejaVu draws ⚔, ⚒ and ⇉ at three
# different weights and on two different baselines, so a row of them never sat
# straight however the buttons were laid out. assets/icons/ holds drawn 64x64
# SVG badges instead — gilt frame, dark medallion, a lit silhouette on it —
# emitted by tools/gen_action_icons.py in three layers:
#
#   skills/    one per skill the bar can name: every combat-castable spell,
#              every feature that becomes a button, each Shove variant. This is
#              the layer the bar actually wants, because since T-skillicons the
#              badge IS the button — the name and the numbers live in the
#              tooltip — and two spells that share a mark are two buttons a
#              player cannot tell apart.
#   schools/   the eight spell schools, for a spell with no badge of its own.
#   actions/   one per verb kind (VERB_GLYPHS), plus the bar's own controls.
#
# Keyed by exactly the ids the game uses, so a new spell needs a recipe there
# and nothing here.
#
# The colour is in the file, not on the button. A school badge already stands on
# its own SCHOOL_COLORS disc (the same colour spell_bb tints the spell's name
# with), the martial verbs share steel and gold, and healing is COL_PARTY green
# — so the bar draws them untouched. Button's icon_*_color defaults are white,
# which multiplies to a no-op; nothing here overrides them.
#
# A miss is not an error. Icons that haven't been imported yet, an export that
# left them out, a content pack's verb kind with no art of its own: _icon()
# returns null and the caller keeps the glyph. Every call site pairs the two.
const ICON_ROOT := "res://assets/icons"
# The badge IS the button now — the name, the prose and the numbers moved into
# the hover popup — so it gets the room a 126 px label used to take.
const ICON_PX := 40          # drawn size on the bar at zoom 1 (_apply_ui_scale scales it)
# The bar's own controls live alongside the verbs — same row, same weight.
const BAR_ICONS := ["end_turn", "back", "swap", "generic"]

static var _icon_cache := {}

static func _icon(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	# exists() first: load()ing a path that isn't there is an engine error, and
	# a headless test run that never imported the assets would print 28 of them.
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	_icon_cache[path] = tex
	return tex

# The face behind a settlement counter: assets/generated/<faction>-<service>.png,
# null if nobody has drawn that one yet (callers add nothing rather than a blank).
static func portrait(faction: String, service: String) -> Texture2D:
	return _icon("res://assets/generated/%s-%s.png" % [faction, service])

# A road event's picture (assets/generated/event-<id>[-pass|-fail].png,
# tools: ~/localgen/gen_sorcmerc_events.py): the outcome's own frame when it
# has one, the plain scene otherwise, null for an event with no art.
static func event_art(event_id: String, ok) -> Texture2D:
	if ok != null:
		var tex := _icon("res://assets/generated/event-%s-%s.png" % [event_id, "pass" if ok else "fail"])
		if tex != null:
			return tex
	return _icon("res://assets/generated/event-%s.png" % event_id)

static func portrait_rect(faction: String, service: String, px := 160) -> TextureRect:
	var tex := portrait(faction, service)
	if tex == null:
		return null
	var pic := TextureRect.new()
	pic.texture = tex
	pic.custom_minimum_size = Vector2(px, px)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return pic

# The badge for one thing the bar is offering, most specific first: the skill's
# own art if it has any (assets/icons/skills — every combat-castable spell, every
# feature that becomes a button, each Shove variant), then the spell's school,
# then the verb kind, then the generic spark. `v` is a verb straight out of
# cb.available().
#
# Ids arrive with two decorations that are not part of the identity: a granted
# verb is "<feature>:<basic>" (combat.gd's grant_verb, e.g. Flurry of Blows
# granting an attack) and an upcast spell is "<spell>@<level>". Both are cut
# back to the thing that has art.
static func skill_icon(v: Dictionary) -> Texture2D:
	var sid := String(v.get("spell", ""))
	var id := String(v.get("id", "")).get_slice(":", 1) if String(v.get("id", "")).contains(":") \
		else String(v.get("id", ""))
	id = id.get_slice("@", 0)
	var tex: Texture2D = null
	if sid != "":
		tex = _icon("%s/skills/%s.svg" % [ICON_ROOT, sid])
		if tex == null:
			tex = _icon("%s/schools/%s.svg" % [ICON_ROOT, spell_school(sid)])
	else:
		tex = _icon("%s/skills/%s.svg" % [ICON_ROOT, id])
	if tex == null:
		tex = verb_icon(String(v.get("kind", "")))
	return tex

# One per verb `kind`, plus BAR_ICONS. A kind with no art of its own — a
# content pack's, or one added before its icon was drawn — gets the generic
# spark; null means the build has no icons at all, and the glyph takes over.
static func verb_icon(kind: String) -> Texture2D:
	var tex := _icon("%s/actions/%s.svg" % [ICON_ROOT, kind])
	return tex if tex != null else _icon("%s/actions/generic.svg" % ICON_ROOT)

# One per SCHOOL_GLYPHS key — a spell button is marked by its school, which
# says more about it than one generic wand for all 300 of them would. Same
# generic fallback for a spell whose entry names no school.
static func school_icon(school: String) -> Texture2D:
	var tex := _icon("%s/schools/%s.svg" % [ICON_ROOT, school])
	return tex if tex != null else _icon("%s/actions/generic.svg" % ICON_ROOT)

# Hang `tex` on `b`, sized for the bar. No tint: these are finished art, and a
# theme colour would multiply the whole badge — frame, disc and all — down to
# one hue. The one override is the disabled state, where the default theme
# leaves a badge as bright as a live one. Returns the button so it chains,
# like clicks().
static func icon_button(b: Button, tex: Texture2D, px := ICON_PX) -> Button:
	if tex == null:
		return b
	b.icon = tex
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", px)
	b.add_theme_constant_override("h_separation", 4)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	# dark_theme() pads a button by 10 for text; a badge button has no text and
	# that padding is the difference between a 40 px mark and a 32 px one, so
	# these get their own boxes — same colours, four pixels of inset.
	for state in [["normal", "2b3040"], ["hover", "3a4152"], ["pressed", "4a5570"],
			["disabled", "22252e"]]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(state[1])
		box.set_corner_radius_all(6)
		box.set_content_margin_all(4)
		b.add_theme_stylebox_override(state[0], box)
	return b

# "⟳ Fire Bolt" as bbcode, school-tinted mark, plain name.
static func spell_bb(spell_id: String, text: String) -> String:
	var sc := spell_school(spell_id)
	return "[color=%s]%s[/color] %s" % [school_color(sc).to_html(false), school_glyph(sc), text]

# --- conditions ------------------------------------------------------------
# The 15 official 2024 conditions, plus the engine's own runtime flags.
const CONDITION_GLYPHS := {
	"blinded": "◍",        # sight blacked out
	"charmed": "♥",
	"deafened": "⌇",       # a muffled wave
	"exhaustion": "⇓",     # everything sinks a step
	"frightened": "↯",
	"grappled": "⊗",       # held fast
	"incapacitated": "⌀",  # no actions at all
	"invisible": "○",      # outline only
	"paralyzed": "❄",      # frozen stiff
	"petrified": "⬢",      # a block of stone
	"poisoned": "☠",
	"prone": "↓",
	"restrained": "⏣",     # caught in a net
	"stunned": "✷",        # seeing stars
	"unconscious": "☾",    # out cold
	# runtime-only flags the combat screen shows on tokens
	"hidden": "☁",
	"dodging": "◈",
	"helped": "✚",
	"down": "✗",
	"reckless": "⚔",      # Reckless Attack — no glyph meant no feedback the button did anything
	"sapped": "↯̸",        # weapon mastery Sap
	"slowed": "⇣",        # weapon mastery Slow
}
# Fixed render order so a token's tag strip doesn't reshuffle between frames.
const CONDITION_ORDER := ["down", "unconscious", "paralyzed", "petrified", "stunned",
	"incapacitated", "restrained", "grappled", "prone", "frightened", "charmed",
	"poisoned", "blinded", "deafened", "exhaustion", "invisible", "hidden", "dodging", "helped",
	"reckless", "sapped", "slowed"]

static func condition_glyph(id: String) -> String:
	return String(CONDITION_GLYPHS.get(id, "•"))

# Every glyph a combatant's current statuses earn it, in CONDITION_ORDER.
static func status_glyphs(c) -> String:
	var out := ""
	for id in CONDITION_ORDER:
		if id == "down":
			continue          # the board draws down with its death-save count
		if c.has(id):
			out += condition_glyph(id)
	return out

# --- rarity ----------------------------------------------------------------
# The conventional CRPG ramp: grey → green → blue → purple → gold, artifact red.
const RARITY_COLORS := {
	"common": Color("b9bcc6"),
	"uncommon": Color("5fbf6a"),
	"rare": Color("5aa0e6"),
	"very-rare": Color("a97fe0"),
	"legendary": Color("e2a33c"),
	"artifact": Color("d15750"),
}

static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, COL_MUTED)

# Mundane gear isn't in magic-items.json and reads as common.
static func rarity_of(item_id: String) -> String:
	return String(Catalog.magic_item(item_id).get("rarity", "common"))

static func item_color(item_id: String) -> Color:
	return rarity_color(rarity_of(item_id))

# `text` stays whatever the caller wants to show (a real name, or T13's mystery
# line) — the ramp only colours it, so an unidentified item still reads as one.
static func item_bb(item_id: String, text: String) -> String:
	return "[color=%s]%s[/color]" % [item_color(item_id).to_html(false), text]

# --- item art (T9a) ---------------------------------------------------------
# One render per item id under assets/art/items (tools/import_item_art.py off
# the ComfyUI batch). null when nobody has drawn it: the tile then shows the
# name, so a content pack's item is still a tile, just a plain one.
const ITEM_ART_PX := 64

static func item_art(item_id: String) -> Texture2D:
	return _icon("res://assets/art/items/%s.png" % item_id)

# Everything the old row said, as the hover text of a tile: name, the numbers
# that matter for its kind, then the prose. `def` is the catalog entry (weapon,
# armor or magic-item), `kind` which of the three it came from.
static func item_tooltip(item_id: String, def: Dictionary, kind: String) -> String:
	var lines: Array = [str(def.get("name", item_id.capitalize()))]
	match kind:
		"weapon":
			var dice := str(def.get("damageDice", ""))
			if str(def.get("versatileDice", "None")) != "None":
				dice += " (%s two-handed)" % def["versatileDice"]
			lines.append("%s %s, %s" % [dice, def.get("damageType", ""), def.get("category", "")])
			var props := str(def.get("properties", "[]")).replace("[", "").replace("]", "").replace("'", "")
			if str(def.get("range", "melee")) == "ranged" or props.contains("thrown"):
				lines.append("Range %s/%s ft" % [def.get("normalRange", "?"), def.get("longRange", "?")])
			if props != "":
				lines.append(props.capitalize())
		"armor":
			var ac := "AC %s" % def.get("baseAc", "?")
			var dex := str(def.get("maxDexBonus", "None"))
			if str(def.get("category", "")) == "light":
				ac += " + Dex"
			elif dex != "None":
				ac += " + Dex (max %s)" % dex
			lines.append("%s, %s" % [ac, def.get("category", "")])
			if str(def.get("stealthDisadvantage", "False")) == "True":
				lines.append("Disadvantage on Stealth")
			if int(def.get("strengthRequirement", 0)) > 0:
				lines.append("Needs Str %s" % def["strengthRequirement"])
		_:
			lines.append(str(def.get("rarity", "")).capitalize()
				+ (", attunement" if str(def.get("attunement", "False")) == "True" else ""))
			var desc := str(def.get("description", "")).strip_edges()
			if desc != "":
				lines.append("")
				lines.append(desc.left(600) + ("…" if desc.length() > 600 else ""))
	var cost := str(def.get("costGp", ""))
	if cost != "" and cost != "None":
		lines.append("%s gp" % cost)
	return "\n".join(lines)

# A square art tile with the hover text; the caller wires `pressed`. `caption`
# is the button's own text under the art (a price, "×3", "Equipped"); without
# art the name stands in for it. The rarity ramp colours the caption.
# The hover card an ItemTile shows in place of the engine's plain tooltip: the
# name in its rarity colour, the numbers, the prose wrapped, the click hint
# dim at the foot. Built from the same tooltip string (first line the name,
# "Click:"/"Right-click:" lines the hint, everything else the body), so a
# test can still read tooltip_text and nothing has two sources of truth.
class ItemTile extends Button:
	const Icons = preload("res://core/ui_icons.gd")
	var rarity_color := Icons.COL_TEXT
	func _make_custom_tooltip(for_text: String) -> Object:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 4, 12, 8))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var lines: PackedStringArray = for_text.split("\n")
		var head := Label.new()
		head.text = lines[0]
		head.add_theme_font_size_override("font_size", Icons.FS_BODY + 4)
		head.add_theme_color_override("font_color", rarity_color)
		v.add_child(head)
		var body: Array = []
		var hint: Array = []
		for i in range(1, lines.size()):
			var l := String(lines[i])
			if l.begins_with("Click:") or l.begins_with("Right-click:"):
				hint.append(l)
			else:
				body.append(l)
		while not body.is_empty() and String(body[-1]).strip_edges() == "":
			body.pop_back()
		if not body.is_empty():
			var txt := Label.new()
			txt.text = "\n".join(body)
			txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			txt.custom_minimum_size = Vector2(320, 0)
			txt.add_theme_color_override("font_color", Icons.COL_TEXT)
			v.add_child(txt)
		if not hint.is_empty():
			var h := Label.new()
			h.text = "\n".join(hint)
			h.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
			h.add_theme_color_override("font_color", Icons.COL_MUTED)
			v.add_child(h)
		return card

static func item_tile(item_id: String, tooltip: String, caption := "", px := ITEM_ART_PX) -> Button:
	var b := ItemTile.new()
	b.rarity_color = item_color(item_id)
	clicks(b)
	b.tooltip_text = tooltip
	b.add_theme_color_override("font_color", item_color(item_id))
	b.add_theme_font_size_override("font_size", FS_CAPTION)
	var tex := item_art(item_id)
	if tex == null:
		b.text = tooltip.get_slice("\n", 0) + ("" if caption == "" else "\n" + caption)
		b.custom_minimum_size = Vector2(px + 12, px + 12)
		return b
	b.icon = tex
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = caption
	b.custom_minimum_size = Vector2(px + 12, px + (30 if caption != "" else 12))
	return b

# Kind + catalog entry for any item id, in the order the rest of the UI
# resolves them (an armor "shield" beats the magic-item "shield").
static func item_def(item_id: String) -> Array:
	var def := Catalog.weapon(item_id)
	if not def.is_empty():
		return ["weapon", def]
	def = Catalog.armor(item_id)
	if not def.is_empty():
		return ["armor", def]
	return ["magic", Catalog.magic_item(item_id)]

# The item's picture as bbcode for a RichTextLabel (the combat log's loot
# line); "" when it has no art, so the name stands alone as before.
static func item_img_bb(item_id: String, px := 28) -> String:
	var path := "res://assets/art/items/%s.png" % item_id
	return "[img=%dx%d]%s[/img] " % [px, px, path] if item_art(item_id) != null else ""
