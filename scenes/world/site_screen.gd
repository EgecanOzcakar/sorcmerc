# D1 — the descent diagram: a core/site.gd drawn as the shaft the party is
# standing in. Deliberately not a menu panel. What this screen exists to make
# the player feel is "I am three rooms deep, the fork in front of me is the only
# way on, and the thing at the bottom has been in sight since I walked in" —
# so the depth already travelled stays on screen above you (greyed), the rooms
# you cannot see yet stay on screen below you, and the boss is drawn from the
# first frame. The party's hit points sit under all of it, because the only
# decision this screen supports is "press on, or get out with what we have".
#
#   var s = SiteScreen.new()
#   s.site = site                 # core/site.gd
#   s.party = party               # core/party.gd
#   add_child(s)
#   s.room_chosen.connect(...)    # (index: int) — the player picked options()[index]
#   s.withdrew.connect(...)       # () — walk out, between rooms; call site.withdraw()
#   s.advanced.connect(...)       # () — done with a non-combat room; call site.leave()
#   s.done.connect(...)           # () — a terminal state was acknowledged; close me
#   s.refresh()                   # after anything changes the model underneath
#
# What this does NOT own, deliberately:
#  - the model. It never calls enter() / leave() / withdraw() / finish_combat():
#    it emits, and the world screen drives. The two exceptions are take() and
#    short_rest(), which ARE the whole content of a non-combat room and have no
#    consequence anywhere outside the site.
#  - the fight. state == "combat" means the world screen has taken over and is
#    running scenes/main.tscn; this screen hides itself (visible = false) and
#    keeps no buttons alive, so nothing of it can draw over or steal clicks from
#    the combat scene. It comes back on the next refresh() into another state.
#  - what a clear or a wipe costs. Terminal states are named, one button hands
#    control back, and the world screen decides the consequences.
#  - saving, gold splitting, XP. Same reason: this is a view.
extends Control

const Icons = preload("res://core/ui_icons.gd")

signal room_chosen(index: int)
signal withdrew()
signal advanced()
signal done()

# The world map stays faintly visible behind the shaft rather than being
# replaced: a site is somewhere you are standing ON the map, not another program.
const BG_FADE := 0.94

const MARGIN := 24.0          # side gutter; also the top/bottom breathing room
const HEADER_H := 56.0        # the "room 2 of 4" line plus the one-line status under it
const FOOTER_H := 92.0        # the party's condition (up to two lines) plus the button row

# Row spacing. ROW_MIN is "two nodes still read as two places"; ROW_MAX stops a
# three-room warren from drawing as three dots lost in a tall window.
const ROW_MIN := 58.0
const ROW_MAX := 104.0

const NODE_R := 9.0           # half-height of a room diamond
const NODE_ASPECT := 0.9      # very slightly wide, the same squashed diamond the map draws
const BOSS_SCALE := 1.8       # the last room is bigger because it is the reason you came
const LINE_W := 1.5           # matches world.gd's ring/polyline weight
const FAN_GAP := 8.0          # clearance between a brace and the nodes it joins

const LABEL_GAP := 8.0        # node to the block of text under it
const BTN_H := 30.0
const FOOTER_BTN_MIN_W := 110.0   # so a lone "Withdraw" is a target, not a word with a box on it
# The live row carries a block (a button and its kind word, or a room title and
# two wrapped lines of description) where every other row carries one line.
const FORK_LABEL_H := 56.0
# ...so the row below it is pushed this much further down, or the fan-in brace
# would be drawn straight through that block.
const FORK_EXTRA := FORK_LABEL_H + 14.0

# At or under this share of max hp a name in the party line goes gold — the
# "one more room?" threshold, not a death's door warning (that is 0 hp, and red).
const HURT_SHARE := 0.4
const SEPARATOR := "     "

const COL_GAP := 12.0
const COL_MAX_W := 230.0      # a fork column never needs to be wider than its longest title
# Under this column width the default body size clips titles badly, so the fork
# buttons drop a step on the type scale instead.
# ponytail: three columns on a ~400px phone still clip the longest room names
# ("The caved-in side passage"). The honest fix is stacking the fork vertically
# at that width, which costs the fork its shape — left for when a phone build is
# actually a target.
const NARROW_COL := 190.0

# The log line core/site.gd writes on entering a room. Read back to remember
# which room was taken at each depth, because the model records the path only
# here — the rooms array keeps every option, not the one chosen.
# ponytail: if that format changes this quietly loses the names above you and
# nothing else; it can never be wrong, only blank.
const ENTERED_MARK := "→ "

# What a room is, in the two words that go under its name on the fork.
const KIND_WORDS := {"combat": "a fight", "treasure": "a cache", "rest": "an hour"}
const BOSS_WORD := "the last room"
# The map draws a lair as "☠" (world.gd's _draw_lair); the bottom of the shaft is
# that same lair seen from the inside, so it wears the same mark.
const BOSS_GLYPH := "☠"

# Terminal states: the headline, the line under it, and the one button out.
const OUTCOMES := {
	"cleared": {
		"head": "Cleared out.",
		"sub": "Nothing left down there worth the walk back.",
		"btn": "Back to the map"},
	"withdrawn": {
		"head": "You back out.",
		"sub": "It is still down there, and it knows the way you came in.",
		"btn": "Back to the map"},
	"wiped": {
		"head": "The party goes down in the dark.",
		"sub": "What that costs is settled above ground.",
		"btn": "Drag them out"},
}

var site                      # core/site.gd, or null
var party                     # core/party.gd, or null

var _buttons: Array = []      # every button this screen currently owns
var _forks: Array = []        # the subset sitting on the live row, in options() order
var _path := {}               # depth -> the title of the room actually taken there
var _base_depth := -1         # the depth this screen first saw, to index the log by


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()
		queue_redraw()


# The world screen calls this after every change it makes to the model.
func refresh() -> void:
	_remember_path()
	_rebuild()
	_place()
	queue_redraw()


func _state() -> String:
	return String(site.state) if site != null else ""


func _depth() -> int:
	return int(site.depth) if site != null else 0


func _total() -> int:
	return maxi(1, int(site.depth_total())) if site != null else 1


# --- what the player can press --------------------------------------------

func _rebuild() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			# Removed, not just queued: a queue_free()d button is still a child
			# for the rest of the frame, and both this screen's own layout and
			# the tests walk the child list.
			remove_child(b)
			b.queue_free()
	_buttons.clear()
	_forks.clear()
	var st := _state()
	visible = st != "combat"
	if site == null or st == "combat":
		return
	match st:
		"picking":
			var opts: Array = site.options()
			for i in opts.size():
				var r: Dictionary = opts[i]
				var b := _button("%s  %s" % [_glyph(r), String(r.get("title", "A way on"))])
				b.pressed.connect(_pick.bind(i))
				b.mouse_entered.connect(queue_redraw)   # the picture follows the hovered fork
				b.mouse_exited.connect(queue_redraw)
				# Only the fork clips: its width is the diagram's, not the
				# label's. A footer button that clips reports no width of its
				# own to _place() and comes out reading "Withdra".
				b.clip_text = true
				b.tooltip_text = String(r.get("desc", ""))
				_forks.append(b)
			# Withdrawing is only legal between rooms, and this is the only
			# state that is between rooms — so it exists here and nowhere else.
			var out := _button("Withdraw")
			out.pressed.connect(func(): withdrew.emit())
		"visiting":
			var room: Dictionary = site.room
			match String(room.get("kind", "")):
				"treasure":
					var taken: bool = bool(room.get("taken", false))
					var t := _button("Taken" if taken else "Take")
					t.disabled = taken
					t.pressed.connect(_take)
				"rest":
					var rested: bool = bool(room.get("rested", false))
					var h := _button("An hour gone" if rested else "Rest an hour")
					h.disabled = rested
					h.pressed.connect(_rest)
			var on := _button("Go on ▾")
			on.pressed.connect(func(): advanced.emit())
		_:
			var spec: Dictionary = OUTCOMES.get(st, {"btn": "Back to the map"})
			var fin := _button(String(spec.get("btn", "Back to the map")))
			fin.pressed.connect(func(): done.emit())


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	add_child(b)
	_buttons.append(b)
	return b


# The one rule of this screen: a fork is reported, never taken.
func _pick(i: int) -> void:
	room_chosen.emit(i)


func _take() -> void:
	if site != null:
		site.take()
	refresh()


func _rest() -> void:
	if site != null:
		site.short_rest()
	refresh()


# --- geometry --------------------------------------------------------------
# _rows() and _xs() are the whole layout: everything drawn and every button
# placed reads its position from them, so the diagram and the controls on top of
# it cannot drift apart.

func _rows() -> PackedFloat32Array:
	var total := _total()
	var live := _labelled_row()
	# A row is a node's centre, so each end of the shaft has to keep back its own
	# half-height — the boss diamond's especially, or it sits in the party line.
	var top := MARGIN + HEADER_H + NODE_R
	var bot := maxf(top + ROW_MIN, size.y - FOOTER_H - NODE_R * BOSS_SCALE)
	var row_h := clampf((bot - top) / float(total), ROW_MIN, ROW_MAX)
	var extra := FORK_EXTRA if live >= 0 else 0.0
	var extent := row_h * float(total - 1) + extra
	# ponytail: below roughly 600px of height a six-room site cannot fit even at
	# ROW_MIN and the bottom of the shaft runs under the footer. The fix is
	# scrolling or a compressed "3 more rooms" stand-in for the middle, and
	# neither is worth building before a window that small is a real target.
	var y0 := top + maxf(0.0, (bot - top - extent) * 0.5)
	var out := PackedFloat32Array()
	for d in total:
		out.append(y0 + row_h * float(d) + (extra if live >= 0 and d > live else 0.0))
	return out


# The depth whose row carries a block of text rather than one line: the fork you
# are choosing from, or the room you are standing in. -1 once the site is over.
func _labelled_row() -> int:
	if site == null or _state() not in ["picking", "visiting"]:
		return -1
	return mini(_depth(), _total() - 1)


func _xs(d: int) -> PackedFloat32Array:
	var cx := size.x * 0.5
	var n := 1
	if d == _depth() and _state() == "picking" and site != null:
		n = maxi(1, site.options().size())
	if n <= 1:
		return PackedFloat32Array([cx])
	var w := _col_w(n)
	var span := w * float(n) + COL_GAP * float(n - 1)
	var out := PackedFloat32Array()
	for i in n:
		out.append(cx - span * 0.5 + w * 0.5 + float(i) * (w + COL_GAP))
	return out


func _col_w(n: int) -> float:
	var avail := maxf(80.0, size.x - MARGIN * 2.0 - COL_GAP * float(n - 1))
	return minf(COL_MAX_W, avail / float(n))


func _place() -> void:
	if site == null or not visible:
		return
	var rows := _rows()
	var d := _labelled_row()
	if _state() == "picking" and d >= 0 and not _forks.is_empty():
		var xs := _xs(d)
		var w := _col_w(_forks.size())
		if w < NARROW_COL:
			for b in _forks:
				b.add_theme_font_size_override("font_size", Icons.FS_SMALL)
		for i in _forks.size():
			var b: Button = _forks[i]
			b.size = Vector2(w, BTN_H)
			b.position = Vector2(xs[mini(i, xs.size() - 1)] - w * 0.5, rows[d] + NODE_R + LABEL_GAP)
	# Everything that is not a fork sits in one centred row along the bottom,
	# where the player's eye already is after reading the party's hit points.
	var footer: Array = _buttons.filter(func(b): return not _forks.has(b))
	if footer.is_empty():
		return
	# Its own minimum, not a guess: "Withdraw" clipped to "Withdra" at a flat width.
	var widths: Array = footer.map(func(b): return maxf(FOOTER_BTN_MIN_W, b.get_combined_minimum_size().x))
	var total_w := 0.0
	for w2 in widths:
		total_w += float(w2) + COL_GAP
	total_w -= COL_GAP
	var x := size.x * 0.5 - total_w * 0.5
	for i in footer.size():
		var b: Button = footer[i]
		b.size = Vector2(float(widths[i]), maxf(BTN_H, b.get_combined_minimum_size().y))
		b.position = Vector2(x, size.y - MARGIN - BTN_H)
		x += float(widths[i]) + COL_GAP


# --- the path already walked ----------------------------------------------

# core/site.gd keeps every option it ever offered but not which one was taken;
# the only record is the log. Read it back so the rooms above you have names
# instead of all reading "cleared".
func _remember_path() -> void:
	if site == null:
		return
	if _base_depth < 0:
		_base_depth = _depth()
	var i := 0
	for entry in site.log:
		var line := String(entry)
		if line.begins_with(ENTERED_MARK):
			_path[_base_depth + i] = line.substr(ENTERED_MARK.length())
			i += 1


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Icons.COL_BG, BG_FADE))
	if site == null:
		_text(Vector2(MARGIN, MARGIN + Icons.FS_TITLE), "Nothing down here.",
			Icons.FS_TITLE, Icons.COL_MUTED)
		return
	_draw_header()
	_draw_shaft()
	_draw_room_art()
	_draw_party()


func _draw_header() -> void:
	var st := _state()
	var head := ""
	var sub := ""
	if OUTCOMES.has(st):
		head = String(OUTCOMES[st].get("head", ""))
		sub = String(OUTCOMES[st].get("sub", ""))
	else:
		head = String(site.progress_line()) if site.lair != null else "Down in the dark"
		# The site's own last line is the only feedback a taken cache or a
		# spent hour has; when there isn't one yet, say the rule of the place.
		sub = String(site.log[-1]) if not site.log.is_empty() \
			else "No long rest down here. What you spend stays spent."
	var cx := size.x * 0.5
	_text(Vector2(cx, MARGIN + Icons.FS_TITLE), head, Icons.FS_TITLE,
		Icons.COL_FOE if st == "wiped" else Icons.COL_HEAD, true)
	_text(Vector2(cx, MARGIN + Icons.FS_TITLE + Icons.FS_SMALL + 8.0), sub,
		Icons.FS_SMALL, Icons.COL_MUTED, true)


func _draw_shaft() -> void:
	var rows := _rows()
	var total := _total()
	var here := _depth()
	for d in total:
		if d > 0:
			_draw_link(d, rows)
	for d in total:
		var xs := _xs(d)
		var boss := d == total - 1
		for i in xs.size():
			var at := Vector2(xs[i], rows[d])
			if d < here:
				_draw_node(at, boss, Icons.COL_EDGE, Icons.COL_MUTED, true)
			elif d == here and _state() in ["picking", "visiting"]:
				_draw_node(at, boss, Icons.COL_GOLD_EDGE, Icons.COL_GOLD, false)
			elif d == here and _state() == "wiped":
				_draw_node(at, boss, Icons.COL_FOE.darkened(0.4), Icons.COL_FOE, true)
			elif boss:
				_draw_node(at, true, Icons.COL_FOE.darkened(0.55), Icons.COL_FOE, true)
			else:
				_draw_node(at, false, Icons.COL_BG, Icons.COL_EDGE, false)
		_draw_row_label(d, rows[d], xs)


# The spine, and the brace where it splits or rejoins. One shape does both: drop
# out of every node above, run along a midline, then drop into every node below
# — with one parent and three children that is the sketch's ┌─┴─┐, with one of
# each it is a plain vertical line.
func _draw_link(d: int, rows: PackedFloat32Array) -> void:
	var up := _xs(d - 1)
	var down := _xs(d)
	var y_up: float = rows[d - 1] + NODE_R
	var y_down: float = rows[d] - NODE_R
	var mid := (y_up + y_down) * 0.5
	if d - 1 == _labelled_row():
		# Leave the live row's block of text alone: the line picks up again
		# below it rather than being drawn through a button.
		y_up = minf(rows[d - 1] + NODE_R + FORK_LABEL_H, y_down - FAN_GAP)
		mid = minf(y_up + FAN_GAP, y_down - FAN_GAP)
	# Lit into the fork you are facing, quiet behind you, quieter still below.
	var col: Color = Icons.COL_EDGE
	if d == _depth() and _state() == "picking":
		col = Icons.COL_GOLD_EDGE
	elif d > _depth():
		col = Icons.COL_EDGE.darkened(0.25)
	for x in up:
		draw_polyline(PackedVector2Array([Vector2(x, y_up), Vector2(x, mid)]), col, LINE_W, true)
	for x in down:
		draw_polyline(PackedVector2Array([Vector2(x, mid), Vector2(x, y_down)]), col, LINE_W, true)
	var lo: float = minf(up[0], down[0])
	var hi: float = maxf(up[up.size() - 1], down[down.size() - 1])
	if hi - lo > 0.5:
		draw_polyline(PackedVector2Array([Vector2(lo, mid), Vector2(hi, mid)]), col, LINE_W, true)


func _draw_node(at: Vector2, boss: bool, fill: Color, edge: Color, filled: bool) -> void:
	var r := NODE_R * (BOSS_SCALE if boss else 1.0)
	var pts := PackedVector2Array([
		at + Vector2(0.0, -r), at + Vector2(r * NODE_ASPECT, 0.0),
		at + Vector2(0.0, r), at + Vector2(-r * NODE_ASPECT, 0.0)])
	if filled:
		draw_colored_polygon(pts, fill)
	var ring := PackedVector2Array(pts)
	ring.append(pts[0])
	draw_polyline(ring, edge, LINE_W, true)
	if boss:
		# 0.9 of the half-height, or the skull fills the diamond corner to corner.
		var fs := int(r * 0.9)
		_text(at + Vector2(0.0, fs * 0.4), BOSS_GLYPH, fs, Icons.COL_HEAD, true)


# One line beside a node for every row but the live one, which gets a block.
func _draw_row_label(d: int, y: float, xs: PackedFloat32Array) -> void:
	var total := _total()
	var here := _depth()
	var boss := d == total - 1
	var right := xs[xs.size() - 1] + NODE_R * (BOSS_SCALE if boss else 1.0) + LABEL_GAP + 2.0
	if d == here and _state() in ["picking", "visiting"]:
		_draw_live_row(d, y, xs)
		return
	if boss and d >= here:
		# The reason you came, legible from the first frame.
		var title: String = String(site.rooms[total - 1][0].get("title", "The master of the place"))
		_label_right(right, y, title.to_upper(), Icons.FS_HEAD, Icons.COL_FOE)
		return
	if d < here or _state() == "cleared":
		_label_right(right, y, String(_path.get(d, "cleared")), Icons.FS_SMALL, Icons.COL_MUTED)
		return
	if d == here and _state() == "withdrawn":
		_label_right(right, y, "you turned back here", Icons.FS_SMALL, Icons.COL_MUTED)
		return
	if d == here and _state() == "wiped":
		_label_right(right, y, String(site.room.get("title", "here")), Icons.FS_SMALL, Icons.COL_FOE)
		return
	_label_right(right, y, "?", Icons.FS_SMALL, Icons.COL_EDGE)



# A label beside a node, made to fit the width that is actually left: the boss's
# name is the longest string on the screen and a phone-width window has nowhere
# near room for it at head size. One step down the type scale first, then wrap,
# because a shortened name is worse than a smaller one.
func _label_right(x: float, y: float, text: String, fs: int, col: Color) -> void:
	var avail := maxf(40.0, size.x - MARGIN - x)
	var use := fs
	if _w(text, use) > avail and use > Icons.FS_SMALL:
		use = Icons.FS_SMALL
	var lines := _wrap(text, use, avail, 2)
	var step := float(use) + 3.0
	var y0 := y + 5.0 - float(lines.size() - 1) * step * 0.5
	for i in lines.size():
		_text(Vector2(x, y0 + float(i) * step), lines[i], use, col)

# The row you are standing on. Picking: a kind word under each fork button (the
# button itself carries the name, so it is never drawn twice). Visiting: the
# room's name and what it looks like, because that is all a non-combat room is.
func _draw_live_row(d: int, y: float, xs: PackedFloat32Array) -> void:
	if _state() == "picking":
		var opts: Array = site.options()
		for i in mini(xs.size(), opts.size()):
			var r: Dictionary = opts[i]
			_text(Vector2(xs[i], y + NODE_R + LABEL_GAP + BTN_H + Icons.FS_SMALL + 2.0),
				_kind_word(r), Icons.FS_SMALL, Icons.COL_MUTED, true)
		return
	var room: Dictionary = site.room
	var cx: float = xs[0]
	_text(Vector2(cx, y + NODE_R + LABEL_GAP + Icons.FS_HEAD),
		String(room.get("title", "Somewhere in the dark")), Icons.FS_HEAD, Icons.COL_HEAD, true)
	var wrap_w := minf(COL_MAX_W * 2.0, size.x - MARGIN * 2.0)
	var lines := _wrap(String(room.get("desc", "")), Icons.FS_SMALL, wrap_w, 2)
	for i in lines.size():
		_text(Vector2(cx, y + NODE_R + LABEL_GAP + Icons.FS_HEAD + float(i + 1) * (Icons.FS_SMALL + 3.0)),
			lines[i], Icons.FS_SMALL, Icons.COL_BODY, true)


# The room, pictured, on the shaft's empty right flank: while picking, the
# fork under the mouse (the first, until one is); while visiting, the room
# itself, with its found/empty frame once a cache is taken. Nothing when the
# window is too narrow to hold the shaft and a picture side by side.
const ART_PX := 240.0
func _room_art():
	var st := _state()
	var room: Dictionary = {}
	if st == "picking":
		var opts: Array = site.options()
		room = opts[0] if not opts.is_empty() else {}
		for i in mini(_forks.size(), opts.size()):
			if is_instance_valid(_forks[i]) and _forks[i].is_hovered():
				room = opts[i]
	elif st == "visiting":
		room = site.room
	if room.is_empty():
		return null
	var ok = null
	if String(room.get("kind", "")) == "treasure" and bool(room.get("taken", false)):
		ok = int(room.get("gold", 1)) > 0 or not room.get("loot", []).is_empty()
	return Icons.scene_art("room-" + String(room.get("id", "")), ok) if String(room.get("id", "")) != "" else null

func _draw_room_art() -> void:
	var art = _room_art()
	if art == null or size.x < COL_MAX_W * 2.0 + ART_PX + MARGIN * 4.0:
		return
	var r := Rect2(Vector2(size.x - MARGIN - ART_PX, (size.y - ART_PX) * 0.45), Vector2(ART_PX, ART_PX))
	draw_texture_rect(art, r, false)
	draw_rect(r, Color(Icons.COL_GOLD, 0.5), false, 1.0)

func _kind_word(room: Dictionary) -> String:
	if _is_boss(room):
		return BOSS_WORD
	return String(KIND_WORDS.get(String(room.get("kind", "")), "a way on"))


func _glyph(room: Dictionary) -> String:
	return BOSS_GLYPH if _is_boss(room) else Icons.node_glyph(String(room.get("kind", "")))


func _is_boss(room: Dictionary) -> bool:
	return room.has("lead") or bool(room.get("boss", false)) \
		or int(room.get("depth", -1)) == _total() - 1


# The party's condition, which is the whole input to "press on or get out".
# Each member is its own segment so a hurt one can be red on its own.
func _draw_party() -> void:
	if party == null:
		return
	var segs: Array = []
	for id in party.active:
		var s: Dictionary = party.summary(String(id))
		if s.is_empty():
			continue
		var hp := int(s.get("hp", 0))
		var maxhp := maxi(1, int(s.get("max_hp", 1)))
		var col: Color = Icons.COL_PARTY
		if hp <= 0:
			col = Icons.COL_FOE
		elif float(hp) / float(maxhp) <= HURT_SHARE:
			col = Icons.COL_GOLD
		segs.append({"text": "%s %d/%d" % [String(s.get("name", "?")), hp, maxhp], "col": col})
	if segs.is_empty():
		return
	# Greedy wrap into at most two lines: four names and their hit points fit one
	# line at 1280 and want two at phone widths.
	var max_w := size.x - MARGIN * 2.0
	var lines: Array = [[]]
	var w_used := 0.0
	for seg in segs:
		var w := _w(String(seg["text"]) + SEPARATOR, Icons.FS_SMALL)
		if w_used + w > max_w and not lines[-1].is_empty():
			lines.append([])
			w_used = 0.0
		lines[-1].append(seg)
		w_used += w
	var y := size.y - FOOTER_H + Icons.FS_SMALL + 6.0
	for line in lines:
		var total_w := 0.0
		for seg in line:
			total_w += _w(String(seg["text"]), Icons.FS_SMALL) + _w(SEPARATOR, Icons.FS_SMALL)
		total_w -= _w(SEPARATOR, Icons.FS_SMALL)
		var x := size.x * 0.5 - total_w * 0.5
		for i in line.size():
			var seg: Dictionary = line[i]
			var text := String(seg["text"])
			_text(Vector2(x, y), text, Icons.FS_SMALL, seg["col"])
			x += _w(text, Icons.FS_SMALL)
			if i < line.size() - 1:
				_text(Vector2(x, y), SEPARATOR, Icons.FS_SMALL, Icons.COL_EDGE)
				x += _w(SEPARATOR, Icons.FS_SMALL)
		y += Icons.FS_SMALL + 4.0



# --- text helpers ----------------------------------------------------------

func _text(at: Vector2, s: String, fs: int, col: Color, center := false) -> void:
	if s == "":
		return
	var x := at.x - (_w(s, fs) * 0.5 if center else 0.0)
	draw_string(Icons.sans(), Vector2(x, at.y), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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
