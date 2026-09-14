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
# The established dark, warm-gold fantasy set. Screens alias these into their own
# COL_* constants so their local names keep working.
const COL_BG := Color("14161c")          # screen background
const COL_PANEL := Color("1b1f29")       # card / panel fill
const COL_INK := Color("0c0e15")         # deep inset fill (log box, profile panels)
const COL_EDGE := Color("39404f")        # quiet border
const COL_GOLD := Color("c8a75a")        # captions, accents
const COL_GOLD_EDGE := Color("6f5a30")   # gilt panel border
const COL_HEAD := Color("f0e6cf")        # headline text
const COL_TEXT := Color("e9e9df")        # body text
const COL_BODY := Color("c2c5cf")        # secondary body text
const COL_MUTED := Color("8f95a3")       # captions/hints, disabled prose
const COL_ACCENT := Color("8fb7d8")      # informational highlight
const COL_PARTY := Color("5fbf6a")
const COL_FOE := Color("d15750")

# --- type scale ------------------------------------------------------------
# One size per UI role, shared by all five screens.
const FS_TITLE := 22      # the screen's one headline
const FS_HEAD := 17       # section / card title
const FS_BODY := 15       # default running text and button labels
const FS_SMALL := 13      # secondary rows, hints, journal
const FS_CAPTION := 12    # the »  S P A C E D  « panel captions

# The one button/label theme every screen wears. `compact` is the inline-control
# variant (the profile's ± / equip buttons sit inside text rows).
static func dark_theme(compact := false) -> Theme:
	var th := Theme.new()
	var pad := 3 if compact else 6
	var mk := func(bg: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(6)
		s.content_margin_left = 10; s.content_margin_right = 10
		s.content_margin_top = pad; s.content_margin_bottom = pad
		return s
	th.set_stylebox("normal", "Button", mk.call(Color("2b3040")))
	th.set_stylebox("hover", "Button", mk.call(Color("3a4152")))
	th.set_stylebox("pressed", "Button", mk.call(Color("4a5570")))
	th.set_stylebox("disabled", "Button", mk.call(Color("22252e")))
	th.set_color("font_color", "Button", Color("e6e8ee"))
	th.set_color("font_hover_color", "Button", Color("ffffff"))
	th.set_color("font_color", "Label", COL_TEXT)
	th.set_font_size("font_size", "Button", FS_BODY)
	th.set_font_size("font_size", "Label", FS_BODY)
	th.set_stylebox("normal", "LineEdit", mk.call(Color("22252e")))
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
	"necromancy": Color("79a86b"), "transmutation": Color("c8a75a"),
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
# straight however the buttons were laid out. assets/icons/ holds a drawn 32x32
# SVG per verb kind and per spell school instead — tools/gen_action_icons.py
# emits them, keyed by exactly the names in VERB_GLYPHS and SCHOOL_GLYPHS, so a
# new verb needs a recipe there and nothing here.
#
# The art is white on transparent and gets its colour on the button, which is
# what lets one file serve both the gold verb marks and the eight school
# colours (see spell_bb — a spell has always been tinted by school).
#
# A miss is not an error. Icons that haven't been imported yet, an export that
# left them out, a content pack's verb kind with no art of its own: _icon()
# returns null and the caller keeps the glyph. Every call site pairs the two.
const ICON_ROOT := "res://assets/icons"
const ICON_PX := 22          # drawn size on the bar at zoom 1 (_apply_ui_scale scales it)
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

# Hang `tex` on `b` in `col`, sized for the bar. Button reads its icon colour
# from one theme entry per state rather than a single property, so setting only
# icon_normal_color leaves the mark stark white the moment the pointer touches
# it — hence the loop. Returns the button so it chains, like clicks().
static func icon_button(b: Button, tex: Texture2D, col: Color, px := ICON_PX) -> Button:
	if tex == null:
		return b
	b.icon = tex
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", px)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color"]:
		b.add_theme_color_override(state, col)
	b.add_theme_color_override("icon_disabled_color", Color(col, 0.4))
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
