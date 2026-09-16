# D4 — the approach card: the first thing in this game that stops and *asks*.
#
# A hostile band closing on the party used to drop them straight into a fight —
# the encounter happened TO them. core/approach.gd broke that open into four
# ways of meeting it; this card is where the player picks one. It is the sibling
# of scenes/world/event_card.gd and wears the same clothes on purpose (same
# scrim, same gilt panel, same spaced caption), with one difference that decides
# every other decision in this file: the event card REPORTS, this one ASKS.
#
#   const ApproachCard = preload("res://scenes/world/approach_card.gd")
#   _approach_card = ApproachCard.new()
#   add_child(_approach_card)
#   _approach_card.chosen.connect(_on_approach_chosen)     # (way: String)
#   _approach_card.show_approach(Approach.options(party, foe), "Goblins (3)")
#
# Because it asks, it has to price what it is asking about: every option draws
# who would roll, what they would roll, their bonus and the DC, BEFORE the press.
# A choice you cannot price is not a choice — it is a coin flip with extra steps,
# and approach.gd builds the options dict specifically so this card can show it.
#
# What this does NOT own, deliberately:
#  - the rules. It never calls Approach.resolve(), never rolls, never spends.
#    It hands back a `way` string and the world screen does all of it. Nothing
#    the player does on this card changes the game state by one point.
#  - the clock. It does not know one exists; world.gd pauses before showing this
#    and resumes after `chosen`, exactly as it does for the event card.
#  - which options exist. approach.gd decides that (the mindless do not parley,
#    and an option nobody can roll is never offered). This card renders
#    the array it is given, in the order it is given, however long it is.
#  - freeing itself, or being cancellable. There is no "back": the band is
#    already on them, so every way out of this card is one of the choices.
extends Control

const Icons = preload("res://core/ui_icons.gd")

# The only thing the world screen listens for. Emitted exactly once per
# show_approach(), whichever of the several doors the player goes through.
signal chosen(way: String)

# --- the panel, borrowed wholesale from event_card so the two read as one
# family of card rather than two unrelated overlays. ------------------------
const SCRIM := 0.78           # the map is paused behind this, not replaced
const MARGIN := 20.0          # gutter to the window edge; survives a ~400px width
const PAD := 20.0             # panel inner padding
const PANEL_MAX_W := 560.0    # past this the option rows run too wide to scan
const PANEL_MIN_W := 240.0    # below this nothing is readable anyway; clip instead
const BAR_W := 5.0            # the kind stripe down the panel's left edge
const BORDER_ALPHA := 0.5     # the project's gilt border is COL_GOLD at half

const TITLE_LINES := 2        # a foe label is "Goblins (3)", never a paragraph
# The hint carries the key binding, so it is the one block that must never be
# the thing that clips at a narrow width.
const HINT_LINES := 3
const NOTE_LINES := 2
const LINE_GAP := 5.0         # between wrapped lines of the same block
const BLOCK_GAP := 12.0       # between blocks
# The hint sits tight under the title rather than a block away: it is a caption
# on the title, not a paragraph of its own.
const HINT_GAP := 2.0

# --- the option rows -------------------------------------------------------
# A row is drawn by _draw(), not by its Button: the Button is the hit target and
# nothing else (every one of its styleboxes is overridden empty). That is the
# only way to get a two-line row with a right-aligned roll line out of a control
# whose text is one centred string — and it is the same "this Control draws
# itself" shape the event card and site_screen.gd already use.
const ROW_GAP := 8.0
const ROW_PAD := 9.0          # row inner padding, top and bottom
const ROW_BAR_W := 3.0        # per-row stripe: the glance-level read of the way
const ROW_TEXT_X := 12.0      # text gutter inside a row, clear of its stripe
const ROW_END_PAD := 10.0     # right-hand inset, so the roll line is not flush
const ROW_HOVER_TINT := 0.16  # the way's colour washed over the row under the cursor
const ROW_FILL_LINE := 0.32   # its resting border
const ROW_HOVER_LINE := 0.95  # ...and the one under the cursor
const INLINE_GAP := 16.0      # least space between a label and a roll line sharing a baseline

const CHIP_W := 20.0          # the number-key chip; square-ish at FS_SMALL
const CHIP_GAP := 8.0
const GLYPH_GAP := 7.0

# 1..9 only: a tenth option would need a key nobody would guess, and approach.gd
# offers at most four. Keypad too, because a numpad 2 that does nothing reads as
# a hang to the player who is already holding the numpad.
const NUM_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const KP_NUM_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5,
	KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
# Swallowed, not obeyed. Esc backs a page out everywhere else in world.gd, and
# this card is modal over a band that is already closing: there is no page to
# back out to. Eating the key here means Esc cannot reach through the card and
# close a settlement screen the player left open behind it.
const SWALLOW_KEYS := [KEY_ESCAPE]

# The glance-level read, before a word: they are hostile and they are close, so
# the card's own stripe is the cost colour, same as a bad road event.
const GLYPH := "⚔"
const CAPTION := "T H E Y   H A V E   S E E N   Y O U"

# One colour and one mark per way. Both sets are palette/icon-sheet entries, so
# neither can come out as an invented colour or as tofu. The colours say what
# the way spends: blue is information (no fight at all), gold is gold (the toll),
# green is the party's own edge (the first round), red is blood.
const WAY_GLYPH := {"avoid": "☁", "parley": "⚖", "ambush": "➶", "engage": "⚔"}
const UNKNOWN_GLYPH := "·"

# The standing-order mark. ★ is already on the icon sheet (NODE_GLYPHS.boss), so
# it renders; it is gold because being credited for an order you set hours ago is
# a payoff, and the hint line explains it the one time it can appear.
const NAMED_MARK := "★"
const NAMED_HINT := "  ★ is the character your standing orders put on the job."

# What a way buys and what it costs, one line each. Both glyphs are already on
# the icon sheet (CONDITION_GLYPHS' "helped" and "down"), so neither can come out
# as tofu — which a ✓/✗ pair, the obvious choice, could.
#
# This pair is the whole answer to the thing that was wrong with this card: a row
# that showed only what a way BUYS made every way that rolls read as better than
# the one that cannot fail, and engage — the safe option — looked like the option
# with nothing on it. The cost of a gamble belongs next to its prize.
const WIN_GLYPH := "✚"
const LOSE_GLYPH := "✗"
const STAKE_LINES := 2        # each half of a gamble, wrapped

const NO_ROLL_TEXT := "no roll"   # engage is the certain one; say so, do not just omit
const NO_FOE := "A band on the road"
const NO_LABEL := "Meet them"

# What the card shows when it is handed nothing at all. An empty options array
# should be impossible (approach.gd always offers engage), but a card with no
# buttons over a paused world is a soft-lock, and a soft-lock is worse than a
# wrong-looking card. One button, the way that always exists and never rolls.
const FALLBACK_OPTION := {"id": "engage", "label": NO_LABEL, "dc": 0,
	"note": "There is no getting round it. Straight at them."}
# For the same reason, a row whose `id` is missing emits this rather than "":
# never hand the world screen a way its rules cannot resolve.
const FALLBACK_WAY := "engage"

var _opts: Array = []
var _foe := ""
var _btns: Array[Button] = []
var _chosen := true           # nothing to choose until show_approach() says so

# Everything drawn, in absolute coordinates, produced by _layout() and replayed
# by _draw(). One producer means the rows and the buttons sitting on top of them
# cannot drift apart — the same contract event_card.gd keeps with its _ops.
var _ops: Array = []
var _rows: Array = []         # {rect, col} per option, drawn under _ops
var _panel := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	# STOP (the Control default, set explicitly because it is load-bearing): the
	# card is modal, so a click aimed at an option must never also land on the map
	# underneath and send the party walking somewhere.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


# The whole public surface, besides `chosen`. `options` is what
# Approach.options() returned — every key in every entry is optional as far as
# this card is concerned, including all of them. `foe_label` is the caller's
# one-line name for who is closing ("Goblins (3)"); this card does not know how
# to build one and never guesses.
const ART_H := 200.0
const ART_MIN_H := 110.0
var _art_rect := Rect2()
var _art: Texture2D = null    # the band on the road: one picture, fixed for the card's life

# Which picture that is. The card used to show the HOVERED way's art, so the
# banner flipped between four paintings while the player read four rows, and
# then the outcome card behind it made a fifth — a pop-up that showed a handful
# of pictures for one decision (#55). One picture while the question is open and
# one once it is answered is the whole shape: this is the question's, and the
# way's own art (its pass/fail frame) belongs to the answer, on the event card
# world.gd opens next. Both of these are a band coming up the road, which is
# what the player is actually looking at, and neither presumes a choice.
const SCENE_ART := "approach-engage"          # a hostile band, closing
const FRIENDLY_SCENE_ART := "approach-greet"  # a civil one, hailing
# The friendly card is the two no-roll ways (core/approach.gd's FRIENDLY_ORDER);
# nothing else on the dict says which kind of meeting this is.
const FRIENDLY_WAYS := ["greet", "pass"]

func _s_of(i: int, key: String) -> String:
	return str(_opt(i).get(key, ""))

func _friendly() -> bool:
	for n in _opts.size():
		if not _s_of(n, "id") in FRIENDLY_WAYS:
			return false
	return not _opts.is_empty()

func show_approach(options: Array, foe_label: String) -> void:
	_opts = []
	if options != null:
		for o in options:
			_opts.append(o)
	if _opts.is_empty():
		_opts.append(FALLBACK_OPTION)
	_foe = foe_label if foe_label != "" else NO_FOE
	_chosen = false
	_art = Icons.event_art(FRIENDLY_SCENE_ART if _friendly() else SCENE_ART, null)
	visible = true
	_build_buttons()
	_layout()
	queue_redraw()


# --- what an option says ----------------------------------------------------
# Every reader below is total: a missing key is a default, a wrong-typed key is
# a default, and nothing in here can throw. This card is the last thing between
# approach.gd and a modal over a paused map, and a modal that errors mid-draw
# leaves the player with no move but to quit.

func _opt(i: int) -> Dictionary:
	if i < 0 or i >= _opts.size():
		return {}
	var v: Variant = _opts[i]
	return v if v is Dictionary else {}


# A key read as text, whatever is actually sitting in it. str() rather than
# String(): String() has no constructor from an int or from null, so one
# wrong-typed key would take the whole card down instead of rendering a stand-in.
func _os(o: Dictionary, key: String, fallback := "") -> String:
	var v: Variant = o.get(key, null)
	if v == null:
		return fallback
	var out: String = str(v)
	return fallback if out == "" else out


# Same contract for the numbers: anything that is not a number reads as zero
# rather than throwing. int("many") is 0 already; int({}) is an error.
func _on(o: Dictionary, key: String) -> int:
	var v: Variant = o.get(key, null)
	if v is int or v is float or v is bool:
		return int(v)
	return 0


# A boolean key. A string is never a flag — bool("false") is true, and crediting
# a standing order that was not set is exactly the lie this mark must not tell.
func _oflag(o: Dictionary, key: String) -> bool:
	var v: Variant = o.get(key, null)
	return v != null and not (v is String) and bool(v)


func _way(o: Dictionary) -> String:
	var id := _os(o, "id")
	# Any non-empty id is forwarded as-is, including one this card has never
	# heard of: a fifth way added to approach.gd should work here without this
	# file being touched. Only an absent id falls back.
	return id if id != "" else FALLBACK_WAY


func _way_color(o: Dictionary) -> Color:
	match _os(o, "id"):
		"avoid": return Icons.COL_ACCENT
		"parley": return Icons.COL_GOLD
		"ambush": return Icons.COL_PARTY
		"engage": return Icons.COL_FOE
	return Icons.COL_MUTED


func _way_glyph(o: Dictionary) -> String:
	return String(WAY_GLYPH.get(_os(o, "id"), UNKNOWN_GLYPH))


func _has_check(o: Dictionary) -> bool:
	return _os(o, "skill") != "" or _on(o, "dc") > 0


# "Vera Kord · Stealth +7 vs DC 13" — the house rule, name the check and name the
# roll, except that nothing has been rolled yet, so what is named is the price.
# The bonus is signed because a forced march is a -2 (travel.gd's PACE) and
# approach.gd has already folded it in; "Stealth 7" when the real number is 5
# would be the one number on this card that must never be wrong.
func _roll_line(o: Dictionary) -> String:
	if not _has_check(o):
		return ""
	var parts: Array[String] = []
	var skill := _os(o, "skill")
	if skill != "":
		parts.append("%s %+d" % [skill.capitalize(), _on(o, "bonus")])
	var dc := _on(o, "dc")
	if dc > 0:
		parts.append("vs DC %d" % dc)
	# The face the die has to show. A bonus and a DC are two numbers a player has
	# to subtract under time pressure to know whether this is a good bet; the
	# subtraction is the whole decision, so the card does it.
	var needs := _on(o, "needs")
	if needs > 0 and dc > 0:
		parts.append("· needs %s" % ("%d+" % needs if needs <= 20 else "out of reach"))
	elif o.has("needs") and dc > 0:
		parts.append("· cannot fail")
	var check := " ".join(parts)
	var who := _os(o, "cname")
	if who == "":
		return check
	return "%s · %s" % [who, check] if check != "" else who


func _named(o: Dictionary) -> bool:
	return _oflag(o, "named")


func _any_named() -> bool:
	for i in _opts.size():
		if _named(_opt(i)):
			return true
	return false


# --- layout -----------------------------------------------------------------

# Rebuilt from scratch on every show_approach() rather than reused: each button
# carries its own index into _opts, and a card reshown with three options where
# it had four would otherwise leave a fourth button bound to a row that is gone.
func _build_buttons() -> void:
	for b in _btns:
		if is_instance_valid(b):
			# remove_child before queue_free: queue_free is deferred, and a button
			# that is still a child for one more frame is still clickable.
			remove_child(b)
			b.queue_free()
	_btns.clear()
	for i in _opts.size():
		var b := Button.new()
		b.name = "approach_%d_%s" % [i, _way(_opt(i))]
		# No text: the row under it is drawn by _draw(), and a Button's own label
		# is one centred string that would sit on top of all of it.
		b.text = ""
		b.tooltip_text = _tooltip(i)
		# No focus: with the button focusable, a number key would fire it *and*
		# reach _input() below, and "emits exactly once" would come down to which
		# of the two won the race.
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.pressed.connect(_choose.bind(i))
		# The hover wash is drawn by _draw(), so the cursor crossing a row has to
		# ask for a frame; nothing else in this card is animated.
		b.mouse_entered.connect(queue_redraw)
		b.mouse_exited.connect(queue_redraw)
		add_child(b)
		_btns.append(b)


# The whole row as one string, for the player who hovers and waits — and the one
# place the note and the roll line are guaranteed to appear together even when
# the panel is too narrow to have drawn both.
func _tooltip(i: int) -> String:
	var o := _opt(i)
	var out := _os(o, "label", NO_LABEL)
	var roll := _roll_line(o)
	if roll != "":
		out += "\n" + roll
	var note := _os(o, "note")
	if note != "":
		out += "\n" + note
	for pair in [[WIN_GLYPH, "win"], [LOSE_GLYPH, "lose"]]:
		var text := _os(o, String(pair[1]))
		if text != "":
			out += "\n%s %s" % [String(pair[0]), text]
	return out


# `art_h` < 0 asks for the full banner; the pass below hands back a smaller
# one (or 0) when the card would run off the window with it.
func _layout(art_h := -1.0) -> void:
	_ops.clear()
	_rows.clear()
	var pw := minf(PANEL_MAX_W, maxf(PANEL_MIN_W, size.x - MARGIN * 2.0))
	var tx := BAR_W + PAD                                   # text inset, panel-relative
	var avail := maxf(40.0, pw - tx - PAD)
	var rel: Array = []                                     # ops relative to the panel origin
	var rel_rows: Array = []
	var y := PAD

	# Caption and glyph share a baseline, the mark sized to the title under it,
	# so the stripe, the mark and the caption land on the eye as one block.
	var gw := _w(GLYPH, Icons.FS_HEAD) + 8.0
	rel.append(_op(Vector2(tx, y + Icons.FS_CAPTION), GLYPH, Icons.FS_HEAD, Icons.COL_FOE, avail))
	rel.append(_op(Vector2(tx + gw, y + Icons.FS_CAPTION), CAPTION, Icons.FS_CAPTION,
		Icons.COL_FOE, avail - gw))
	y += Icons.FS_CAPTION + 10.0

	# The meeting itself, pictured: the same banner slot the event card uses for
	# the outcome that follows, and the same size — one picture here, one there.
	# Sized to the window: a quarter of its height up to ART_H, and none at all
	# when a short window needs every pixel for the four ways themselves.
	_art_rect = Rect2()
	if art_h < 0.0:
		art_h = ART_H
	if _art != null and art_h >= ART_MIN_H:
		_art_rect = Rect2(tx, y, avail, art_h)
		y += art_h + BLOCK_GAP

	# Who it is. The caller owns this string; the card only puts it in the one
	# place a title goes.
	for tline in _wrap(_foe, Icons.FS_TITLE, avail, TITLE_LINES):
		y += Icons.FS_TITLE
		rel.append(_op(Vector2(tx, y), tline, Icons.FS_TITLE, Icons.COL_HEAD, avail))
		y += LINE_GAP
	y += HINT_GAP

	# Say what is bound, in the header, once. A player at 8x who has just been
	# stopped will not go looking for the keys.
	var hint := "Choose how to meet them — click a row, or press 1-%d." % _opts.size()
	if _any_named():
		hint += NAMED_HINT
	for hline in _wrap(hint, Icons.FS_SMALL, avail, HINT_LINES):
		y += Icons.FS_SMALL
		rel.append(_op(Vector2(tx, y), hline, Icons.FS_SMALL, Icons.COL_MUTED, avail))
		y += LINE_GAP
	y += BLOCK_GAP - LINE_GAP

	for i in _opts.size():
		y += _row(rel, rel_rows, i, tx, avail, y)
		y += ROW_GAP
	y += PAD - ROW_GAP

	# Centred, and clamped off the top so a tall card on a short window loses its
	# bottom rows rather than its title — the rows it loses are still reachable by
	# their number keys, which is why the header says what they are.
	var ph := y
	# The banner yields to the words: over the window with it, lay out again
	# with exactly the overflow taken off the picture, or none if that leaves a strip.
	var over := ph - (size.y - MARGIN * 2.0)
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
	for r in rel_rows:
		var row: Dictionary = r.duplicate()
		row["rect"] = Rect2(Rect2(row["rect"]).position + _panel.position, Rect2(row["rect"]).size)
		_rows.append(row)

	for i in _btns.size():
		if i < _rows.size() and is_instance_valid(_btns[i]):
			var rect := Rect2(_rows[i]["rect"])
			_btns[i].position = rect.position
			_btns[i].size = rect.size


# One option row. Appends its ops and its rect, and returns its height so the
# caller does not have to know what is in it. Everything inside is built at x=0
# for the row's own left edge and shifted onto `tx` in one place at the bottom,
# so a row's internals never have to carry the panel's gutter around with them.
func _row(rel: Array, rel_rows: Array, i: int, tx: float, avail: float, top: float) -> float:
	var sub: Array = []
	var o := _opt(i)
	var col := _way_color(o)
	var label := _os(o, "label", NO_LABEL)
	var roll := _roll_line(o)
	var note := _os(o, "note")
	var named := _named(o)
	var right := avail - ROW_END_PAD

	# The number chip, the way's mark, then the label. The chip is the key hint
	# in the only place it is useful: on the thing the key presses.
	var chip := str(i + 1) if i < NUM_KEYS.size() else ""
	var head_x := ROW_TEXT_X
	if chip != "":
		head_x += CHIP_W + CHIP_GAP
	var glyph := _way_glyph(o)
	var glyph_x := head_x
	head_x += _w(glyph, Icons.FS_HEAD) + GLYPH_GAP

	var mark := (" " + NAMED_MARK) if named else ""
	var roll_w := _w(roll, Icons.FS_SMALL) + _w(mark, Icons.FS_SMALL)
	# The roll line rides the label's baseline when there is room for it there,
	# and drops to its own line when there is not. At 1280 that is one tight row
	# per way; at ~400px it is two lines rather than a DC pushed off the edge,
	# and the DC is the entire reason this card exists.
	var inline := roll != "" and head_x + _w(label, Icons.FS_HEAD) + INLINE_GAP + roll_w <= right

	var y := top + ROW_PAD + Icons.FS_HEAD
	if chip != "":
		var chip_r := Rect2(ROW_TEXT_X, y - Icons.FS_HEAD + 1.0, CHIP_W, Icons.FS_HEAD)
		sub.append({"rect": chip_r, "col": col})
		sub.append(_op(Vector2(ROW_TEXT_X + (CHIP_W - _w(chip, Icons.FS_SMALL)) * 0.5, y - 2.0),
			chip, Icons.FS_SMALL, col, CHIP_W))
	sub.append(_op(Vector2(glyph_x, y), glyph, Icons.FS_HEAD, col, avail))
	sub.append(_op(Vector2(head_x, y), label, Icons.FS_HEAD, Icons.COL_HEAD, right - head_x))

	if inline:
		_roll_ops(sub, Vector2(right - roll_w, y), roll, mark, right)
	elif roll != "":
		y += LINE_GAP + Icons.FS_SMALL
		_roll_ops(sub, Vector2(ROW_TEXT_X, y), roll, mark, right)
	elif not _has_check(o):
		# engage. "no roll" is not the absence of a line, it is the sell: this is
		# the one way that cannot go wrong, and the player is choosing it against
		# three that can.
		sub.append(_op(Vector2(right - _w(NO_ROLL_TEXT, Icons.FS_SMALL), y),
			NO_ROLL_TEXT, Icons.FS_SMALL, Icons.COL_MUTED, avail))

	# The sell, under everything, muted — but only for a way that did not say what
	# it wins and loses. Those two lines say the same thing in harder words, and
	# printing both made every row carry its own paraphrase. The note is still on
	# the tooltip, where a player who wants the prose can hover for it.
	if _os(o, "win") == "" and _os(o, "lose") == "":
		for nline in _wrap(note, Icons.FS_SMALL, right - ROW_TEXT_X, NOTE_LINES):
			y += LINE_GAP + Icons.FS_SMALL
			sub.append(_op(Vector2(ROW_TEXT_X, y), nline, Icons.FS_SMALL, Icons.COL_MUTED,
				right - ROW_TEXT_X))

	# Both halves of the gamble, in the order a gambler weighs them: what it pays
	# and then what it costs. A way with no `lose` (engage) draws one line, and
	# that absence IS its argument — it is the only row on the card with nothing
	# under the red mark.
	y = _stake(sub, y, WIN_GLYPH, _os(o, "win"), Icons.COL_PARTY, right)
	y = _stake(sub, y, LOSE_GLYPH, _os(o, "lose"), Icons.COL_FOE, right)

	var h := (y - top) + ROW_PAD
	rel_rows.append({"rect": Rect2(tx, top, avail, h), "col": col})
	for op in sub:
		var moved: Dictionary = op
		if moved.has("rect"):
			moved["rect"] = Rect2(Rect2(moved["rect"]).position + Vector2(tx, 0.0),
				Rect2(moved["rect"]).size)
		else:
			moved["pos"] = Vector2(moved["pos"]) + Vector2(tx, 0.0)
		rel.append(moved)
	return h


# One stake line: a mark and the outcome it stands for, hanging under the note.
# Returns the new y whether or not it drew anything, so a way with no downside
# simply takes up no room saying so.
func _stake(sub: Array, y: float, glyph: String, text: String, col: Color, right: float) -> float:
	if text == "":
		return y
	var gx := ROW_TEXT_X
	var tx2 := gx + _w(glyph, Icons.FS_SMALL) + GLYPH_GAP
	var first := true
	for line in _wrap(text, Icons.FS_SMALL, right - tx2, STAKE_LINES):
		y += LINE_GAP + Icons.FS_SMALL
		if first:
			sub.append(_op(Vector2(gx, y), glyph, Icons.FS_SMALL, col, right - gx))
			first = false
		sub.append(_op(Vector2(tx2, y), line, Icons.FS_SMALL, col, right - tx2))
	return y


# The roll line and, when the player's own standing order put this character on
# the job, the gold mark that says so. Two ops rather than one string, because
# the mark is the payoff and it earns its own colour.
func _roll_ops(sub: Array, at: Vector2, roll: String, mark: String, right: float) -> void:
	sub.append(_op(at, roll, Icons.FS_SMALL, Icons.COL_ACCENT, right - at.x))
	if mark != "":
		sub.append(_op(Vector2(at.x + _w(roll, Icons.FS_SMALL), at.y), mark, Icons.FS_SMALL,
			Icons.COL_GOLD, right))


func _op(pos: Vector2, text: String, fs: int, col: Color, max_w: float) -> Dictionary:
	return {"pos": pos, "text": text, "fs": fs, "col": col, "max_w": max_w}


# --- the ways out -----------------------------------------------------------
# All of them are choices. There is no cancel: the band is already closing, and
# a card that could be dismissed would mean the world screen had to invent a
# decision for the player, which is the exact thing D4 set out to stop doing.

func _input(event: InputEvent) -> void:
	if not visible or _chosen:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode in SWALLOW_KEYS:
		if is_inside_tree():
			accept_event()
		return
	var i := NUM_KEYS.find(k.keycode)
	if i < 0:
		i = KP_NUM_KEYS.find(k.keycode)
	if i < 0 or i >= _opts.size():
		return
	# _input(), not _unhandled_key_input(): world.gd owns the latter for the visit
	# screens and the speed controls, where 1/2/4/8 set the clock speed. _input
	# runs first, so accept_event() here means the key is spent on this card and
	# cannot also wind the clock the card is holding still.
	if is_inside_tree():
		accept_event()
	_choose(i)


# Idempotent on purpose: four rows, nine keys and a mouse are a lot of doors into
# one room, and the world screen resolves the approach on this signal — a second
# emit would be a second Approach.resolve() on a band that has already been met.
func _choose(i: int) -> void:
	if _chosen:
		return
	_chosen = true
	chosen.emit(_way(_opt(i)))


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Icons.COL_BG, SCRIM))
	draw_rect(_panel, Icons.COL_PANEL)
	draw_rect(Rect2(_panel.position, Vector2(BAR_W, _panel.size.y)), Icons.COL_FOE)
	draw_rect(_panel, Color(Icons.COL_GOLD, BORDER_ALPHA), false, 1.0)
	if _art != null and _art_rect.size.x > 0.0:
		var ts := _art.get_size()
		var src := Rect2(Vector2.ZERO, ts)
		var slot_aspect := _art_rect.size.x / _art_rect.size.y
		if ts.x / ts.y < slot_aspect:
			src.size.y = ts.x / slot_aspect
			src.position.y = (ts.y - src.size.y) * 0.4
		else:
			src.size.x = ts.y * slot_aspect
			src.position.x = (ts.x - src.size.x) / 2.0
		draw_texture_rect_region(_art, _art_rect, src)
		draw_rect(_art_rect, Color(Icons.COL_FOE, 0.55), false, 1.0)

	for n in _rows.size():
		var row: Dictionary = _rows[n]
		var rect := Rect2(row["rect"])
		var col: Color = row["col"]
		var hot: bool = n < _btns.size() and is_instance_valid(_btns[n]) and _btns[n].is_hovered()
		draw_rect(rect, Icons.COL_INK)
		if hot:
			draw_rect(rect, Color(col, ROW_HOVER_TINT))
		draw_rect(rect, Color(col, ROW_HOVER_LINE if hot else ROW_FILL_LINE), false, 1.0)
		# The way's stripe, the row's own glance-level tell, echoing the panel's.
		draw_rect(Rect2(rect.position, Vector2(ROW_BAR_W, rect.size.y)), col)

	for op in _ops:
		var o: Dictionary = op
		if o.has("rect"):
			var col: Color = o["col"]
			draw_rect(Rect2(o["rect"]), Icons.COL_BG)
			draw_rect(Rect2(o["rect"]), Color(col, 0.55), false, 1.0)
			continue
		_text(Vector2(o["pos"]), String(o["text"]), int(o["fs"]), o["col"], float(o["max_w"]))


# --- text helpers -----------------------------------------------------------
# The same three helpers event_card.gd and site_screen.gd have, duplicated for
# the same reason: they are methods of a Control that draws on itself, and
# factoring them out means editing files this phase does not own.
# ponytail: a shared core/ui_text.gd is still the upgrade path for all three.

func _text(at: Vector2, s: String, fs: int, col: Color, max_w := -1.0) -> void:
	if s == "":
		return
	draw_string(Icons.sans(), at, s, HORIZONTAL_ALIGNMENT_LEFT,
		max_w if max_w > 0.0 else -1.0, fs, col)


func _w(s: String, fs: int) -> float:
	if s == "":
		return 0.0
	return Icons.sans().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _wrap(text: String, fs: int, max_w: float, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	if text == "":
		return out
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
