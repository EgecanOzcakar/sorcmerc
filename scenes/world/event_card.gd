# D3 — the road event card: the one thing that gets to stop a 1x-8x fast-forward.
#
# core/travel.gd rolls the road, resolves the event against the standing orders
# already set on the party screen, and hands the world screen an event dict that
# is *already applied*. This card is the receipt. It reports what happened, names
# the check and names the roll behind it, and says whose standing order put that
# character on the job — because that credit is the whole feedback loop: the
# player set an order hours ago and this is the only place they ever see it pay.
#
#   const EventCard = preload("res://scenes/world/event_card.gd")
#   _event_card = EventCard.new()
#   add_child(_event_card)
#   _event_card.acknowledged.connect(_on_event_ack)   # () -> resume clock, free me
#   _event_card.show_event(Travel.check(party, world))
#
# What this does NOT own, deliberately:
#  - the clock. It never pauses or resumes anything; the world screen pauses
#    before showing it and resumes on `acknowledged`. This card has no idea a
#    clock exists.
#  - the outcome. Nothing here rolls, spends, heals or reveals — travel.gd did
#    all of it before the dict was built. Reading this card cannot change the
#    game state by one point.
#  - asking anything. This phase's events resolve themselves (travel.gd's rule
#    2). ponytail: D4's events stop and ask, which means an "options" key on the
#    dict and a second signal here; the single `acknowledged` is the shape that
#    grows into it, not something that has to be torn out.
#  - freeing itself. It emits and stops; the caller decides whether to free or
#    keep it for the next event.
extends Control

const Catalog = preload("res://core/rules/catalog.gd")
const Icons = preload("res://core/ui_icons.gd")

# The only thing the world screen has to listen for. Emitted exactly once per
# show_event(), whichever of the three ways out the player takes.
signal acknowledged()

# The map is paused behind this, not replaced — the player wants to see where
# they were when the road interrupted them. Dark enough that the card's own
# panel is clearly on top of it, not part of it.
const SCRIM := 0.78

const MARGIN := 20.0          # gutter to the window edge; survives a ~400px width
const PAD := 20.0             # panel inner padding
const PANEL_MAX_W := 560.0    # past this the body text runs too wide to scan
const PANEL_MIN_W := 240.0    # below this nothing is readable anyway; clip instead
const BAR_W := 5.0            # the kind stripe down the panel's left edge
# The gilt border every panel in this project wears is COL_GOLD at roughly half
# strength; this is that, in whichever colour the event's kind is.
const BORDER_ALPHA := 0.5

# travel.gd's longest text (D3.1's carter, plus the settlement name it appends)
# measures three lines at PANEL_MAX_W, four at ~400px and seven at PANEL_MIN_W.
# The cap exists only so a future event with a paragraph in it cannot grow the
# card off the screen — which means it has to sit ABOVE the longest thing the
# table can actually say, because _wrap() drops what does not fit rather than
# scrolling it. Six was under the carter at the narrow end; eight clears it.
const BODY_LINES := 8
const TITLE_LINES := 2
const LINE_GAP := 5.0         # between wrapped lines of the same block
const BLOCK_GAP := 12.0       # between blocks
const TIGHT_GAP := 5.0        # roll line to the standing-order note under it

const CHIP_H := 22.0
const CHIP_PAD := 9.0         # chip text inset
const CHIP_GAP := 7.0
const CHIP_RADIUS := 0        # draw_rect has no corner radius; chips are plain boxes

const BTN_H := 32.0
const BTN_MIN_W := 150.0      # "Back to the road" is a target, not a word in a box

# Esc for the player who is reading, Enter for the player at 8x who wants it gone
# before they have finished reading it. Keypad Enter because a numpad Enter that
# does nothing reads as a hang.
const DISMISS_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]
const DISMISS_TEXT := "Back to the road   (Enter)"

# The glance-level tell, before a word is read. `kind` is the event's category
# (travel.gd's "good"/"bad"), NOT whether the roll passed — a bad event that was
# caught in time is still a bad thing that happened, and the stripe says so while
# the verdict on the roll line says it went well. Both glyphs are already on the
# icon sheet (ui_icons.gd), so neither can come out as tofu.
# D6 adds "border": not something the road gave or took, but the country under
# it changing. Its own caption because "the road takes" would be a lie — nothing
# has happened yet, which is the entire point of showing it before it does.
const KIND_GLYPH := {"good": "✦", "bad": "↯", "border": "⚑"}
const KIND_CAPTION := {"good": "T H E   R O A D   G I V E S", "bad": "T H E   R O A D   T A K E S",
	"border": "T H E   C O U N T R Y   C H A N G E S"}
const UNKNOWN_CAPTION := "O N   T H E   R O A D"
const UNKNOWN_GLYPH := "·"

# Fallbacks for a dict with nothing in it. The card must render *something*
# rather than an empty gilt box, because a blank card over a paused map reads as
# a crash and the player's only move is to quit.
const NO_TITLE := "Something on the road"
const NO_TEXT := "The party keeps walking."

const MINUTES_PER_HOUR := 60.0

var _e: Dictionary = {}
var _btn: Button = null
var _dismissed := true        # nothing to dismiss until show_event() says so

# Everything drawn, in absolute coordinates, produced by _layout() and replayed
# by _draw(). One producer means the panel and the button placed on top of it
# cannot drift apart — the same contract site_screen.gd's _rows()/_xs() keeps.
var _ops: Array = []
var _panel := Rect2()
var _art: Texture2D = null   # the event's picture, its outcome's frame when it has one
var _art_rect := Rect2()
const ART_H := 320.0         # the picture's height on the card (#83: the whole 1:1 picture, so square-ish)
const ART_MIN_H := 110.0     # below this it is a strip, not a picture: leave it out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	# STOP (the Control default, set explicitly because it is load-bearing here):
	# the card is modal, so a click meant for the dismiss button must never also
	# land on the map underneath and send the party somewhere.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_button()
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


# The whole public surface, besides `acknowledged`. `e` is travel.gd's already
# resolved event dict; every key in it is optional as far as this card is
# concerned, including all of them.
func show_event(e: Dictionary) -> void:
	_e = e.duplicate() if e != null else {}
	_art = Icons.scene_art(("" if _s("id").begins_with("camp-") else "event-") + _s("id"),
		_e.get("ok") if _e.has("ok") else null) if _e.has("id") else null
	_dismissed = false
	visible = true
	_ensure_button()
	_layout()
	queue_redraw()


# --- what the dict says -----------------------------------------------------
# Every reader below is total: a missing key is a default, never an error. The
# dict comes from travel.gd, but this card is also the thing that has to survive
# a save file from a version where the key was called something else.

# A key read as text, whatever is actually sitting in it. str() rather than
# String(): String() has no constructor from an int or from null, so a dict with
# a wrong-typed key would take the whole card down instead of rendering a
# stand-in — which is the one thing a modal over a paused map must never do.
func _s(key: String, fallback := "") -> String:
	var v: Variant = _e.get(key, null)
	if v == null:
		return fallback
	var out: String = str(v)
	return fallback if out == "" else out


# Same contract for the numbers: anything that is not actually a number reads as
# zero rather than throwing. int("many") is 0 already; float({}) is an error.
func _num(key: String) -> float:
	var v: Variant = _e.get(key, null)
	if v is int or v is float or v is bool:
		return float(v)
	return 0.0


func _kind() -> String:
	var k := _s("kind")
	return k if KIND_GLYPH.has(k) else ""


# Gold is the payoff colour everywhere else in this project; red is the cost
# colour. A kind this card does not know reads muted rather than guessing.
func _kind_color() -> Color:
	match _kind():
		"good": return Icons.COL_GOLD
		"bad": return Icons.COL_FOE
		"border": return Icons.COL_ACCENT
	return Icons.COL_MUTED


func _has_roll() -> bool:
	return _e.has("nat") and _e.has("dc")


# A boolean key. A string is never a flag — bool("false") is true, and reporting
# a pass because the key held the word "false" is the worst possible lie here.
func _flag(key: String) -> bool:
	var v: Variant = _e.get(key, null)
	return v != null and not (v is String) and bool(v)


# "Vera Kord · Survival 14+5 vs DC 13" — the house rule, name the check and name
# the roll. Signed bonus rather than world.gd's "%d+%d": a forced march is a -2
# (travel.gd's PACE), and "14+-2" is not a roll anybody can read.
func _roll_text() -> String:
	return "%s %d%s vs DC %d" % [_skill_label(), int(_num("nat")),
		"%+d" % int(_num("bonus")), int(_num("dc"))]


# The catalog's own name for the skill, falling back to the id dressed up.
# capitalize() alone is right for every single-word skill and wrong for the one
# that is two: "animalhandling" is an id, "Animal Handling" is what the sheet
# calls it, and the road rolls it (travel.gd's carter). Catalog.skills() is a
# cached parse, so this is a dictionary lookup per draw.
func _skill_label() -> String:
	var id := _s("skill", "check")
	var entry: Variant = Catalog.skills().get(id, null)
	if entry is Dictionary:
		var named := String(entry.get("name", ""))
		if named != "":
			return named
	return id.capitalize()


func _cname() -> String:
	return _s("cname")


# --- layout -----------------------------------------------------------------

func _ensure_button() -> void:
	if _btn != null and is_instance_valid(_btn):
		return
	_btn = Button.new()
	_btn.text = DISMISS_TEXT
	# No focus: with the button focusable, Enter would fire it *and* reach
	# _input() below, and "emits exactly once" would depend on which won.
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.pressed.connect(_dismiss)
	add_child(_btn)


# `art_h` < 0 asks for the full banner; the pass below hands back a smaller
# one (or 0) when the card would run off the window with it.
func _layout(art_h := -1.0) -> void:
	_ops.clear()
	var pw := minf(PANEL_MAX_W, maxf(PANEL_MIN_W, size.x - MARGIN * 2.0))
	var tx := BAR_W + PAD                                   # text inset, panel-relative
	var avail := maxf(40.0, pw - tx - PAD)
	var rel: Array = []                                     # ops relative to the panel origin
	var y := PAD

	var kind_col := _kind_color()
	var kind := _kind()

	# Caption and glyph share a baseline: the mark is the size of the title under
	# it, so the eye lands on the stripe, the mark and the caption as one block.
	var glyph: String = KIND_GLYPH.get(kind, UNKNOWN_GLYPH)
	var cap: String = KIND_CAPTION.get(kind, UNKNOWN_CAPTION)
	var gw := _w(glyph, Icons.FS_HEAD) + 8.0
	rel.append(_op(Vector2(tx, y + Icons.FS_CAPTION), glyph, Icons.FS_HEAD, kind_col, avail))
	rel.append(_op(Vector2(tx + gw, y + Icons.FS_CAPTION), cap, Icons.FS_CAPTION, kind_col, avail - gw))
	y += Icons.FS_CAPTION + 10.0

	_art_rect = Rect2()
	if art_h < 0.0:
		art_h = ART_H
	if _art != null and art_h >= ART_MIN_H:
		_art_rect = Rect2(tx, y, avail, art_h)   # panel-relative; moved with the ops below
		y += art_h + BLOCK_GAP

	var title := _s("title", NO_TITLE)
	for tline in _wrap(title, Icons.FS_TITLE, avail, TITLE_LINES):
		y += Icons.FS_TITLE
		rel.append(_op(Vector2(tx, y), tline, Icons.FS_TITLE, Icons.COL_HEAD, avail))
		y += LINE_GAP
	y += BLOCK_GAP - LINE_GAP

	var text := _s("text", NO_TEXT)
	for bline in _wrap(text, Icons.FS_BODY, avail, BODY_LINES):
		y += Icons.FS_BODY
		rel.append(_op(Vector2(tx, y), bline, Icons.FS_BODY, Icons.COL_BODY, avail))
		y += LINE_GAP
	y += BLOCK_GAP - LINE_GAP

	if _has_roll():
		# Who rolled is the loudest part of the line, then the roll, then the
		# verdict. The verdict is coloured by `ok` (did it go well) while the
		# stripe is coloured by `kind` (was this good news or bad news) — two
		# different questions, and a bad event caught in time answers them
		# differently.
		var ok := _flag("ok")
		var x := tx
		var who := _cname()
		if who != "":
			rel.append(_op(Vector2(x, y + Icons.FS_BODY), who, Icons.FS_BODY, Icons.COL_HEAD, avail))
			x += _w(who, Icons.FS_BODY)
			rel.append(_op(Vector2(x, y + Icons.FS_BODY), "  ·  ", Icons.FS_BODY, Icons.COL_EDGE, avail))
			x += _w("  ·  ", Icons.FS_BODY)
		var roll := _roll_text()
		rel.append(_op(Vector2(x, y + Icons.FS_BODY), roll, Icons.FS_BODY, Icons.COL_TEXT, avail))
		x += _w(roll, Icons.FS_BODY)
		var verdict := "   ✓ made it" if ok else "   ✗ missed"
		# ponytail: at ~400px a long name plus a long skill pushes the verdict
		# off the panel's right edge. It is the least load-bearing part of the
		# line (the stripe and the chips already carry the outcome), so it is
		# dropped rather than wrapped, which would split one roll over two lines.
		if x + _w(verdict, Icons.FS_BODY) <= tx + avail:
			rel.append(_op(Vector2(x, y + Icons.FS_BODY), verdict, Icons.FS_BODY,
				Icons.COL_PARTY if ok else Icons.COL_FOE, avail))
		y += Icons.FS_BODY + TIGHT_GAP

		# The feedback loop, in one line: this is the only place a standing order
		# ever reports back. Both halves are worth saying — "your order" teaches
		# that the setting did something, "nobody was named" is the nudge to go
		# and set one.
		if _e.has("named") and who != "":
			var note := ""
			var note_col := Icons.COL_MUTED
			if _flag("named"):
				note = "Your standing orders put %s on this." % who
				note_col = Icons.COL_ACCENT
			else:
				note = "No standing order for this — %s was simply best at it." % who
			for nline in _wrap(note, Icons.FS_SMALL, avail, 2):
				y += Icons.FS_SMALL
				rel.append(_op(Vector2(tx, y), nline, Icons.FS_SMALL, note_col, avail))
				y += LINE_GAP
			y -= LINE_GAP
		y += BLOCK_GAP

	var chips := _chips()
	if not chips.is_empty():
		var x := tx
		y += CHIP_H
		for chip in chips:
			var cw := minf(avail, _w(String(chip["text"]), Icons.FS_SMALL) + CHIP_PAD * 2.0)
			if x > tx and x + cw > tx + avail:
				x = tx
				y += CHIP_H + CHIP_GAP
			var r := Rect2(x, y - CHIP_H, cw, CHIP_H)
			rel.append({"rect": r, "col": chip["col"]})
			rel.append(_op(Vector2(x + CHIP_PAD, y - (CHIP_H - Icons.FS_SMALL) * 0.5 - 2.0),
				String(chip["text"]), Icons.FS_SMALL, chip["col"], cw - CHIP_PAD * 2.0))
			x += cw + CHIP_GAP
		y += BLOCK_GAP

	y += BTN_H + PAD

	# Centred, and clamped off the top so a tall card on a short window loses its
	# bottom (which is the button, still reachable by Enter) rather than its title.
	var ph := y
	var over := ph - (size.y - MARGIN * 2.0)   # the banner yields to the words (see approach_card.gd)
	if over > 0.0 and _art_rect.size.y > 0.0:
		var less := _art_rect.size.y - over
		_layout(less if less >= ART_MIN_H else 0.0)
		return
	var px := (size.x - pw) * 0.5
	var py := maxf(MARGIN, (size.y - ph) * 0.5)
	_panel = Rect2(px, py, pw, ph)
	_art_rect.position += _panel.position
	for op in rel:
		var moved: Dictionary = op.duplicate()
		if moved.has("pos"):
			moved["pos"] = Vector2(moved["pos"]) + _panel.position
		else:
			moved["rect"] = Rect2(Rect2(moved["rect"]).position + _panel.position,
				Rect2(moved["rect"]).size)
		_ops.append(moved)

	if _btn != null and is_instance_valid(_btn):
		var bw := maxf(BTN_MIN_W, minf(pw - PAD * 2.0, _btn.get_combined_minimum_size().x))
		_btn.size = Vector2(bw, BTN_H)
		_btn.position = Vector2(px + (pw - bw) * 0.5, py + ph - PAD - BTN_H)


func _op(pos: Vector2, text: String, fs: int, col: Color, max_w: float) -> Dictionary:
	return {"pos": pos, "text": text, "fs": fs, "col": col, "max_w": max_w}


# What the event cost or paid, one chip each, only when the key is there. These
# are the numbers a player scanning at 8x actually needs; the prose above says
# what happened, the chips say what it is worth.
func _chips() -> Array:
	var out: Array = []
	# Signed rather than always "+": D3.1 put costs on the purse too (a ford that
	# takes a pack, a toll post that is paid), and "+-40 gold" is not a number
	# anybody can read. Colour carries the sign as well, so the direction is
	# legible before the digits are.
	var gold := int(_num("gold"))
	if gold != 0:
		out.append({"text": "%+d gold" % gold,
			"col": Icons.COL_GOLD if gold > 0 else Icons.COL_FOE})
	var hurt := int(_num("hurt"))
	if hurt > 0:
		out.append({"text": "-%d hp across the party" % hurt, "col": Icons.COL_FOE})
	var healed := int(_num("healed"))
	if healed > 0:
		out.append({"text": "+%d hp across the party" % healed, "col": Icons.COL_PARTY})
	var m := _num("minutes")
	# Under a minute is not a consequence, it is rounding.
	if absf(m) >= 1.0:
		out.append({"text": "%s %s" % [_span(absf(m)), "lost on the road" if m > 0.0 else "saved"],
			"col": Icons.COL_FOE if m > 0.0 else Icons.COL_PARTY})
	var item := _s("item_name")
	if item != "":
		out.append({"text": "%s — in the stash" % item, "col": Icons.COL_GOLD})
	var lair := _s("lair")
	if lair != "":
		out.append({"text": "%s — on the map now" % lair, "col": Icons.COL_ACCENT})
	# Goodwill has no number on this card on purpose: the score it moves is a
	# faction's (core/faction_opinion.gd) and it is read in their markets and
	# their quest boards, not here. Naming who heard about it is the part the
	# player can act on.
	var thanks := _s("thanks")
	if thanks != "":
		out.append({"text": "%s hears of it" % thanks, "col": Icons.COL_ACCENT})
	return out


# World-minutes as the player reads the clock: "4h", "1h 30m", "45m".
func _span(minutes: float) -> String:
	var total := int(round(minutes))
	var h := int(total / int(MINUTES_PER_HOUR))
	var m := total % int(MINUTES_PER_HOUR)
	if h <= 0:
		return "%dm" % m
	return "%dh" % h if m == 0 else "%dh %dm" % [h, m]


# --- the way out ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or _dismissed:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if not k.keycode in DISMISS_KEYS:
		return
	# _input(), not _unhandled_key_input(): world.gd owns the latter for the visit
	# screens, and Esc there backs a page out. _input runs before any of that, so
	# accept_event() here means the key is spent on the card and cannot also
	# close a town behind it.
	if is_inside_tree():
		accept_event()
	_dismiss()


# Idempotent on purpose: the button, Esc and Enter are three doors into the same
# room, and the world screen frees this card on the signal — a second emit would
# be a resume on a clock that is already running.
func _dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	acknowledged.emit()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Icons.COL_BG, SCRIM))
	draw_rect(_panel, Icons.COL_PANEL)
	# The stripe is the whole glance-level read: full height, kind-coloured, and
	# the only saturated shape on the card.
	draw_rect(Rect2(_panel.position, Vector2(BAR_W, _panel.size.y)), _kind_color())
	# The frame joins the glance read rather than fighting it: the project's gilt
	# border is COL_GOLD at half strength, and a kind-tinted one is the same idea
	# one step further, so a bad card is not a red stripe inside a gold box.
	draw_rect(_panel, Color(_kind_color(), BORDER_ALPHA), false, 1.0)
	if _art != null and _art_rect.size.x > 0.0:
		# #83: the whole picture, fitted inside the slot and centred — it used
		# to be cropped to a banner, which lost most of a 1:1 scene.
		var dst := Icons.fit_rect(_art.get_size(), _art_rect)
		draw_texture_rect(_art, dst, false)
		draw_rect(dst, Color(_kind_color(), 0.55), false, 1.0)
	for op in _ops:
		var o: Dictionary = op
		if o.has("rect"):
			var col: Color = o["col"]
			draw_rect(Rect2(o["rect"]), Icons.COL_INK)
			draw_rect(Rect2(o["rect"]), Color(col, 0.55), false, 1.0)
			continue
		_text(Vector2(o["pos"]), String(o["text"]), int(o["fs"]), o["col"], float(o["max_w"]))


# --- text helpers -----------------------------------------------------------
# The same three helpers site_screen.gd has, duplicated for the same reason
# world.gd duplicates main.gd's projection math: they are methods of a Control
# that draws on itself, and factoring them out means editing files this phase
# does not own. ponytail: a shared core/ui_text.gd is the upgrade path.

func _text(at: Vector2, s: String, fs: int, col: Color, max_w := -1.0) -> void:
	if s == "":
		return
	draw_string(Icons.sans(), at, s, HORIZONTAL_ALIGNMENT_LEFT,
		max_w if max_w > 0.0 else -1.0, fs, col)


func _w(s: String, fs: int) -> float:
	return Icons.sans().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _wrap(text: String, fs: int, max_w: float, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var probe: String = word if line == "" else line + " " + word
		if _w(probe, fs) <= max_w or line == "":
			line = probe
			continue
		out.append(line)
		line = word
		if out.size() >= max_lines:
			return out
	if line != "" and out.size() < max_lines:
		out.append(line)
	return out
