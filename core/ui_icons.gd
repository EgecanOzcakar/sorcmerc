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
const FS_BODY := 14       # default running text and button labels
const FS_SMALL := 13      # secondary rows, hints, journal
const FS_CAPTION := 12    # the »  S P A C E D  « panel captions

# --- class glyphs ----------------------------------------------------------
const CLASS_GLYPHS := {
	"barbarian": "⚒",   # crossed tools — the axe mark
	"bard": "♫",
	"cleric": "✝",
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

# Heroes carry a resolved sheet; monsters do not and get no class mark.
static func combatant_glyph(c) -> String:
	return class_glyph(primary_class(c.sheet)) if c.sheet != null else ""

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
}
# Fixed render order so a token's tag strip doesn't reshuffle between frames.
const CONDITION_ORDER := ["down", "unconscious", "paralyzed", "petrified", "stunned",
	"incapacitated", "restrained", "grappled", "prone", "frightened", "charmed",
	"poisoned", "blinded", "deafened", "exhaustion", "invisible", "hidden", "dodging", "helped"]

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
