# #157: the after-action page — the fight's verdict, played rather than printed.
#
# WHAT THIS REPLACES. Issue #30 gave a won fight a page so the haul was not
# paid in silence; what that page was, was a receipt. A gilt box appeared with
# every line of it already on screen: heading, painting, "+400 XP, +50 gold",
# what came off the bodies, who did not get up, and a button. Nothing moved,
# nothing arrived, and the biggest moment in a run read exactly like the
# merchant's stock list.
#
# WHAT IT IS NOW. The same rows, in the same order, dealt out over about a
# second and a half: the verdict slams in and settles, the painting comes up
# under it, each line arrives on its own beat out of a bright flash, and the
# numbers count to what was won. The way on appears last, when the page has
# finished saying what it has to say.
#
# THREE THINGS THIS IS CAREFUL ABOUT, all of which a later editor can break:
#
#  1. **Every label carries its FINAL text from the first frame.** The stagger
#     is opacity and colour, never text that has not arrived — so a screen
#     reader, a test asking "does this page say +400 XP", and a player who
#     clicked through all read the same page. The one exception is the tally
#     rows, and see 2.
#  2. **A tally row is its own final text with the digits wound back**, and it
#     lands on that exact string. `_wound(text, k)` scales every run of digits
#     by k, so "+400 XP,  +50 gold" counts up to itself and cannot drift off
#     by a rounding error at the end: at k >= 1 the original string is
#     returned untouched, not recomputed.
#  3. **Settings.anim() zeroes it.** At Instant, and under SORCMERC_FAST —
#     which is every headless run and the whole test suite — the page is fully
#     open on the frame it is built, button and all. An after-action page that
#     had to be waited out would turn every UI robot into a timing test.
#
# The whole thing is skippable: a click or a key anywhere on it finishes the
# sequence at once. That is deliberately NOT a button — the page has exactly
# one of those, and it is the way on.
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")

# The beats, in seconds at pace 1.0. The whole sequence is BANNER + one ROW_GAP
# per row + TAIL, which is ~1.4 s for a typical four-row victory — long enough
# to feel dealt, short enough that nobody reaches for the button first.
const BANNER := 0.42        # the verdict's slam and settle
const ART_AT := 0.16        # the painting starts under it
const ART_FOR := 0.34
const ROWS_AT := 0.46       # the first line lands here
const ROW_GAP := 0.13       # ...and each one after it
const ROW_FOR := 0.26       # how long one line takes to arrive
const TALLY_FOR := 0.55     # how long a counting row counts for
const TAIL := 0.20          # tip and button, after the last line
# A line arrives by fading up out of a bright flash rather than by sliding:
# these rows are children of a VBoxContainer, and a container owns its
# children's positions — an animated `position` survives only until something
# queues a sort, which an autowrapping label inside a scroll does whenever the
# panel settles. Opacity and colour are the caller's to keep. The flash is what
# is left of the motion, and it is enough to make a line read as dealt.
const FLASH := Color(1.0, 0.97, 0.88)

var _t := 0.0
var _done := false
var _banner: Label = null
var _rule: ColorRect = null   # the gilt line that opens under the verdict
var _art: TextureRect = null
var _rows: Array = []       # [{node, at, text, tally}]
var _tail: Array = []       # nodes that come up once the rows have landed
var _end := 0.0             # when the whole sequence is over
var _regex: RegEx = null

# Digits scaled by k. At k >= 1 the ORIGINAL string comes back — a counter that
# recomputes its own destination is a counter that can land on 399.
func _wound(text: String, k: float) -> String:
	if k >= 1.0:
		return text
	if _regex == null:
		_regex = RegEx.new()
		_regex.compile("\\d+")
	var out := ""
	var at := 0
	for m in _regex.search_all(text):
		out += text.substr(at, m.get_start() - at)
		out += str(int(floor(float(m.get_string().to_int()) * maxf(k, 0.0))))
		at = m.get_end()
	return out + text.substr(at)

# `rows` are [text, colour], [text, colour, "tally"] — a tally row counts its
# numbers up instead of simply arriving — or a Control the caller built (the
# party strip, the fallen, the haul as tiles), dealt on its own beat like a
# line. `art` and `tip` may be null/"".
func build(heading: String, rows: Array, art: Texture2D, tip: String, on_close: Callable) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(Icons.COL_BG.r, Icons.COL_BG.g, Icons.COL_BG.b, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "Gilt"
	panel.custom_minimum_size = Vector2(440, 0)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# The verdict, at the size the moment deserves. The combat screen's own wash
	# says V I C T O R Y in gilt at 54 px and this page used to answer it with a
	# section heading; it is the same word about the same fight and it should
	# not shrink on the way out. Spelled plainly rather than letterspaced — the
	# spacing belongs to the wash's painted text, and a label is read by more
	# than eyes.
	_banner = Label.new()
	_banner.text = heading
	_banner.theme_type_variation = "Head"
	_banner.add_theme_font_size_override("font_size", Icons.FS_TITLE + 6)
	_banner.add_theme_color_override("font_color",
		Icons.COL_GOLD if heading == "Victory" else Icons.COL_FOE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_banner)

	# ...and a rule under it that opens out from the middle as the word settles.
	# One node and one animated number, and it is what makes the slam land on
	# something rather than simply stop.
	_rule = ColorRect.new()
	_rule.color = Icons.COL_GOLD_EDGE if heading == "Victory" else Icons.COL_FOE
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(_rule)

	# #151: the verdict pictured — the run summary's own two paintings — so the
	# page after a fight reads like the card before it, and not a receipt.
	if art != null:
		_art = TextureRect.new()
		_art.texture = art
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art.custom_minimum_size = Vector2(420, 180)
		box.add_child(_art)

	var scroll := ScrollContainer.new()
	var tall := 0.0   # a text line is a line; a built row says how tall it is
	for row in rows:
		tall += row.custom_minimum_size.y + 6.0 if row is Control else 26.0
	scroll.custom_minimum_size = Vector2(420, clampf(tall, 52.0, 420.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)

	var at := ROWS_AT
	for row in rows:
		if row is Control:
			list.add_child(row)
			_rows.append({"node": row, "at": at, "text": "", "tally": false})
			at += ROW_GAP
			continue
		var l := Label.new()
		l.text = String(row[0])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", row[1])
		list.add_child(l)
		_rows.append({"node": l, "at": at, "text": l.text,
			"tally": row.size() > 2 and String(row[2]) == "tally"})
		at += ROW_GAP

	if tip != "":
		var t := Label.new()   # #151: one line of advice, the way the approach card carries one
		t.text = tip
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.theme_type_variation = "Dim"
		box.add_child(t)
		_tail.append(t)

	var go := Button.new()
	go.text = "Back to the map  [Esc]"
	go.pressed.connect(on_close)
	box.add_child(go)
	_tail.append(go)

	_end = at + ROW_FOR + TAIL
	gui_input.connect(_skipped)
	_apply()
	# Instant, and every headless run: the page is already open, button and all.
	if Settings.anim() >= Settings.FAST:
		finish()
	else:
		_focus_the_way_on()

# Everything at its end state, and no more ticking. Also what the click does.
func finish() -> void:
	if _done:
		return
	_done = true
	_t = _end
	_apply()
	_focus_the_way_on()

# Esc is the map's own binding for "close this page", so the button wants the
# focus the moment it is pressable. Guarded on the tree because a caller is
# free to build the page before parenting it, and a Control outside the tree
# has no viewport to take focus in.
func _focus_the_way_on() -> void:
	for n in _tail:
		if n is Button and n.is_inside_tree():
			n.grab_focus()

func _skipped(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
		finish()

func _process(dt: float) -> void:
	if _done:
		return
	_t += dt * maxf(Settings.anim(), 0.01)
	if _t >= _end:
		finish()
		return
	_apply()

# 0 before `at`, 1 after `at + over`, eased out in between.
func _k(at: float, over: float) -> float:
	return ease(clampf((_t - at) / maxf(over, 0.001), 0.0, 1.0), 0.4)

func _apply() -> void:
	# The verdict: in on the first frame at full opacity but oversized, settling
	# to its own size. Fading a headline in reads as a slow page; punching it
	# down reads as a verdict.
	var k := _k(0.0, BANNER)
	_banner.modulate.a = clampf(k * 3.0, 0.0, 1.0)
	_banner.pivot_offset = _banner.size * 0.5    # scale about the word, not off the panel's edge
	_banner.scale = Vector2.ONE * (1.0 + 0.55 * (1.0 - k))
	_rule.custom_minimum_size.x = 360.0 * _k(BANNER * 0.45, BANNER)
	_rule.modulate.a = k
	if _art != null:
		_art.modulate.a = _k(ART_AT, ART_FOR)
	for r in _rows:
		var kr := _k(float(r["at"]), ROW_FOR)
		var node: Control = r["node"]
		# Colour AND opacity in one write: modulate multiplies the theme colour
		# the row was given, so a line lands hot and cools into its own ink.
		node.modulate = Color(FLASH.lerp(Color.WHITE, kr), kr)
		if r["tally"]:
			node.text = _wound(String(r["text"]), _k(float(r["at"]), TALLY_FOR))
	var kt := _k(_end - TAIL, TAIL)
	for n in _tail:
		n.modulate.a = kt
		if n is Button:
			n.disabled = kt < 1.0
