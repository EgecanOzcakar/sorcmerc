# The party page's Relations, drawn rather than listed: the marching party's
# faces in a ring, and one line between every pair saying at a glance how they
# get on. It replaces six "Vera Kord and Pike Sallow — rivals (-44)" lines,
# which read fine one at a time and told you nothing as a whole — who is the
# odd one out, which two would cover for each other — until you had read all
# six and drawn the picture yourself. This draws it.
#
# How a pair reads, strongest cue first:
#   colour   the band (core/party_opinion.gd's band()): red rivals, frost-blue
#            cold, grey neutral, green warm, gold bonded, rose lovers;
#   shape    a lightning zigzag for rivals, a broken line for cold, a faint
#            dotted one for neutral, a solid one warm and up, a double one for
#            lovers — so it still reads to someone who does not see the colour;
#   weight   how far the score is from nothing, |score| / 100;
#   badge    the band's mark on the line (⚡ ❄ ☀ ∞ ♥; neutral gets none), with a
#            gilt spark on it when a trait is part of the pull (#176 step 4).
#
# The words are one hover away, not gone: over a line the tooltip is that
# pair's describe() — band, score and the traits behind it — and over a face it
# is every line that person is on. Hovering also lifts what is under the mouse
# and dims the rest, which is how you ask "what does everyone think of Pike".
#
# The bench sits in too (the design audit, docs/audit-game-design.md §2.4b):
# since 2026-09-25 a benched merc shares the fire at an inn or the lodge, so
# what they think of the marching four is live and belongs on the picture.
# They sit in a column down the right edge, smaller, their lines faint until a
# face or a line is hovered — four faces and six lines is the picture; the
# bench is the context beside it. A column rather than a row under the ring,
# because the card already shares its height with the marching list above it
# and the width is the one thing it has to spare. A merc who has sat out long enough to be restless
# (core/bench.gd) wears an amber ring and a mark, and their face's tooltip says
# how many days and what it means.
#
# What it does not own: any rule about opinion (all of it is PartyOpinion's —
# this reads band/score/describe and Traits.opinion_terms, and writes nothing),
# the bench's clock (core/bench.gd), or the choice of who is drawn (the party's
# active list, in marching order, then the living bench in roster order).
# Faces are scenes/portraits.gd's busts; headless and for a class the art does
# not cover, the class glyph stands in, the way the rest of the page falls back.
extends Control

const PartyOpinion = preload("res://core/party_opinion.gd")
const Bench = preload("res://core/bench.gd")
const Traits = preload("res://core/traits.gd")
const Icons = preload("res://core/ui_icons.gd")
const Portraits = preload("res://scenes/portraits.gd")
const HeroModels = preload("res://scenes/figures3d.gd").HERO_MODELS

const BANDS := ["rivals", "cold", "neutral", "warm", "bonded", "lovers"]
const BAND_COLOR := {
	"rivals": Color("d35a4a"),    # Icons.COL_FOE
	"cold": Color("7d9fc4"),
	"neutral": Color("8a7f6e"),   # Icons.COL_MUTED
	"warm": Color("7fbf6a"),      # Icons.COL_PARTY
	"bonded": Color("e0b860"),
	"lovers": Color("e57fa4"),
}
const BAND_MARK := {"rivals": "⚡", "cold": "❄", "warm": "☀", "bonded": "∞", "lovers": "♥"}

const FACE_R := 30.0          # a face's circle
const FACE_PX := 56           # the bust rendered into it
const BADGE_R := 14.0
const MARK_FS := 18
const LEGEND_H := 22.0
const HIT := 9.0              # how near a line the mouse must be to be "on" it
const DIAG_T := 0.3           # where a crossing diagonal wears its badge, so two never meet in the middle
const BENCH_R := 20.0         # a benched face's circle: the context, not the picture
const BENCH_COL_W := 66.0     # one column of the bench, down the right edge
const BENCH_SLOT_H := 58.0    # one benched face and the first name under it
const BENCH_CAP_H := 18.0     # the column's "Bench" caption, over it
const BENCH_FADE := 0.28      # a bench line's alpha while nothing is hovered
const COL_RESTLESS := Color("e0923c")
const BASE_MIN := Vector2(360, 230)

var _party = null
var _ids: Array = []          # the marching party, in order
var _bench: Array = []        # the living bench, in roster order
var _hover_face := -1
var _hover_edge := -1         # an index into edges()


func _init() -> void:
	name = "RelationsWeb"
	custom_minimum_size = BASE_MIN   # it takes the marching column's width; this is the floor
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(party) -> void:
	_party = party
	_ids = Array(party.active).map(func(i): return String(i))
	_bench = party.bench_list().filter(func(ch): return not ch.dead).map(func(ch): return String(ch.id))
	_hover_face = -1
	_hover_edge = -1
	queue_redraw()


# Everybody drawn: the marching party, then the bench.
func ids() -> Array:
	return _ids + _bench

func is_benched(i: int) -> bool:
	return i >= _ids.size()

# One entry per pair among everybody drawn, in PartyOpinion.pairs()'s order —
# the marching pairs first, exactly as before the bench sat in: who, the band,
# the score, the traits behind the pull, and whether a benched merc is on it.
# What the lines are drawn from, and what a test reads.
func edges() -> Array:
	var out: Array = []
	if _party == null:
		return out
	for pr in PartyOpinion.pairs(ids()):
		var a := String(pr[0])
		var b := String(pr[1])
		var ca = _party.get_member(a)
		var cb = _party.get_member(b)
		out.append({
			"a": a, "b": b,
			"band": PartyOpinion.band(_party, a, b),
			"score": PartyOpinion.score(_party, a, b),
			"why": Traits.opinion_terms(ca, cb)["why"] if ca != null and cb != null else [],
			"bench": a in _bench or b in _bench,
		})
	return out


# --- where things are ---------------------------------------------------------

func _field() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x - _bench_strip().size.x, size.y - LEGEND_H))

# How many faces a bench column holds, and how many columns the bench needs —
# three a column in the card's usual height, a second column past that.
func _bench_rows() -> int:
	return maxi(1, int((size.y - LEGEND_H - BENCH_CAP_H) / BENCH_SLOT_H))

func _bench_cols() -> int:
	return 0 if _bench.is_empty() else ceili(float(_bench.size()) / _bench_rows())

func _bench_strip() -> Rect2:
	var w := BENCH_COL_W * _bench_cols()
	return Rect2(Vector2(size.x - w, 0), Vector2(w, size.y - LEGEND_H))

func _radius(i: int) -> float:
	return BENCH_R if is_benched(i) else FACE_R

# The faces in a ring, clockwise from top-left, in marching order: two side by
# side, three a triangle, four the corners of a box (whose two diagonals are
# the only lines that cross, hence DIAG_T).
func face_positions() -> Array:
	var f := _field()
	var w := f.size.x
	var h := f.size.y
	var rel: Array
	match _ids.size():
		0, 1:
			rel = [Vector2(0.5, 0.5)]
		2:
			rel = [Vector2(0.22, 0.45), Vector2(0.78, 0.45)]
		3:
			rel = [Vector2(0.5, 0.25), Vector2(0.8, 0.77), Vector2(0.2, 0.77)]
		_:
			rel = [Vector2(0.14, 0.25), Vector2(0.86, 0.25), Vector2(0.86, 0.77), Vector2(0.14, 0.77)]
	var out: Array = []
	for i in mini(_ids.size(), rel.size()):
		out.append(f.position + Vector2(rel[i].x * w, rel[i].y * h))
	# The bench: down the column under its caption, a slot a face, the first
	# name under each; a second column when the first is full.
	var strip := _bench_strip()
	var rows := _bench_rows()
	for k in _bench.size():
		out.append(Vector2(strip.position.x + BENCH_COL_W * (k / rows + 0.5),
			BENCH_CAP_H + BENCH_SLOT_H * (k % rows) + BENCH_R + 4.0))
	return out

func _index(id: String) -> int:
	return ids().find(id)

func _is_diagonal(e: Dictionary) -> bool:
	var i := _index(e["a"])
	var j := _index(e["b"])
	return _ids.size() == 4 and i < 4 and j < 4 and absi(i - j) == 2

# The line between two faces, trimmed to their rims.
func _segment(e: Dictionary, pos: Array) -> Array:
	var i := _index(e["a"])
	var j := _index(e["b"])
	var p: Vector2 = pos[i]
	var q: Vector2 = pos[j]
	var d := (q - p).normalized()
	return [p + d * (_radius(i) + 4.0), q - d * (_radius(j) + 4.0)]

func _badge_at(e: Dictionary, seg: Array) -> Vector2:
	var t := DIAG_T if _is_diagonal(e) else 0.5
	return (seg[0] as Vector2).lerp(seg[1], t)


# --- hover and the words behind the picture -----------------------------------

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_set_hover(ev.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_face = -1
		_hover_edge = -1
		queue_redraw()

func _set_hover(at: Vector2) -> void:
	var f := face_at(at)
	var e := -1 if f >= 0 else edge_at(at)
	if f != _hover_face or e != _hover_edge:
		_hover_face = f
		_hover_edge = e
		queue_redraw()

func face_at(at: Vector2) -> int:
	var pos := face_positions()
	for i in pos.size():
		if at.distance_to(pos[i]) <= _radius(i) + 2.0:
			return i
	return -1

func edge_at(at: Vector2) -> int:
	var pos := face_positions()
	var es := edges()
	var best := -1
	var best_d := HIT
	for i in es.size():
		var seg := _segment(es[i], pos)
		var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]))
		d = minf(d, at.distance_to(_badge_at(es[i], seg)) - BADGE_R + HIT)   # the badge counts as the line
		if d < best_d:
			best_d = d
			best = i
	return best

# Over a line: that pair's describe(). Over a face: every line they are on —
# and for a benched face, first, how long they have sat out, and whether they
# are restless (core/bench.gd), in the words the warning card used.
func tooltip_at(at: Vector2) -> String:
	if _party == null:
		return ""
	var f := face_at(at)
	if f >= 0:
		var mine: Array = []
		var who: String = ids()[f]
		if is_benched(f):
			mine.append(bench_note(who))
		for e in edges():
			if e["a"] == who or e["b"] == who:
				mine.append(PartyOpinion.describe(_party, e["a"], e["b"]))
		return "\n".join(mine)
	var i := edge_at(at)
	if i < 0:
		return ""
	var e: Dictionary = edges()[i]
	return PartyOpinion.describe(_party, e["a"], e["b"])

func _get_tooltip(at: Vector2) -> String:
	return tooltip_at(at)

# "On the bench 12 days. Restless: march them soon, or they may leave the company."
func bench_note(id: String) -> String:
	var ch = _party.get_member(id)
	var d := Bench.days(_party, id, _party.world_now)
	var line := "%s: on the bench %d day%s." % [ch.cname if ch != null else id, d, "" if d == 1 else "s"]
	if Bench.restless(_party, id):
		line += " Restless: march them soon, or they may leave the company."
	return line


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _party == null or ids().size() < 2:
		return
	var pos := face_positions()
	var es := edges()
	var lit := {}      # which edges and faces the hover lifts; empty means all
	if _hover_face >= 0:
		lit[_hover_face] = true
		for i in es.size():
			if _index(es[i]["a"]) == _hover_face or _index(es[i]["b"]) == _hover_face:
				lit["e%d" % i] = true
	elif _hover_edge >= 0:
		lit["e%d" % _hover_edge] = true
		lit[_index(es[_hover_edge]["a"])] = true
		lit[_index(es[_hover_edge]["b"])] = true
	# A bench line is faint until something on it is hovered, and wears no
	# badge till then: the marching four's six lines stay the picture.
	for i in es.size():
		var faint: bool = es[i]["bench"] and not lit.has("e%d" % i)
		_draw_edge(es[i], pos, lit.is_empty() or lit.has("e%d" % i), i == _hover_edge, faint)
	for i in es.size():
		if es[i]["bench"] and not lit.has("e%d" % i):
			continue
		_draw_badge(es[i], pos, lit.is_empty() or lit.has("e%d" % i))
	if not _bench.is_empty():
		_draw_bench_caption()
	for i in pos.size():
		_draw_face(i, pos[i], lit.is_empty() or lit.has(i))
	_draw_legend()

func _draw_edge(e: Dictionary, pos: Array, lit: bool, hot: bool, faint := false) -> void:
	var seg := _segment(e, pos)
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var band := String(e["band"])
	var col: Color = BAND_COLOR[band]
	col.a = (BENCH_FADE if lit else 0.1) if faint else (1.0 if lit else 0.18)
	var w := 2.0 + 5.0 * minf(absf(float(e["score"])) / PartyOpinion.RANGE, 1.0) + (1.5 if hot else 0.0)
	if faint:
		w = maxf(1.5, w * 0.5)
	match band:
		"rivals":      # a zigzag: the line itself is under strain
			var n := maxi(6, int(a.distance_to(b) / 12.0))
			var side := (b - a).normalized().orthogonal() * 5.0
			var pts := PackedVector2Array()
			for k in n + 1:
				var p := a.lerp(b, float(k) / n)
				pts.append(p if k == 0 or k == n else p + side * (1.0 if k % 2 == 1 else -1.0))
			draw_polyline(pts, col, w, true)
		"cold":
			draw_dashed_line(a, b, col, w, 9.0, true, true)
		"neutral":
			col.a *= 0.75
			draw_dashed_line(a, b, col, 2.0 + (1.5 if hot else 0.0), 3.0, true, true)
		"lovers":      # two strands
			var off := (b - a).normalized().orthogonal() * (w * 0.5 + 1.5)
			draw_line(a + off, b + off, col, w * 0.6, true)
			draw_line(a - off, b - off, col, w * 0.6, true)
		_:
			draw_line(a, b, col, w, true)

func _draw_badge(e: Dictionary, pos: Array, lit: bool) -> void:
	var band := String(e["band"])
	if not BAND_MARK.has(band) and (e["why"] as Array).is_empty():
		return
	var c := _badge_at(e, _segment(e, pos))
	var col: Color = BAND_COLOR[band]
	var fade := 1.0 if lit else 0.25
	if BAND_MARK.has(band):
		draw_circle(c, BADGE_R, Color(Icons.COL_INK, fade))
		draw_arc(c, BADGE_R, 0.0, TAU, 32, Color(col, fade), 2.0, true)
		var font := get_theme_default_font()
		var fs := MARK_FS
		var mark := String(BAND_MARK[band])
		var sz := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-sz.x * 0.5, sz.y * 0.5 - font.get_descent(fs)),
			mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, fade))
	# a trait is part of this pull: a gilt spark on the badge's shoulder
	if not (e["why"] as Array).is_empty():
		var s := c + Vector2(BADGE_R * 0.75, -BADGE_R * 0.75) if BAND_MARK.has(band) else c
		draw_circle(s, 4.5, Color(Icons.COL_INK, fade))
		draw_circle(s, 3.0, Color(Icons.COL_GOLD, fade))

func _draw_face(i: int, at: Vector2, lit: bool) -> void:
	var id: String = ids()[i]
	var ch = _party.get_member(id)
	var benched := is_benched(i)
	var r := _radius(i)
	var px := FACE_PX if not benched else int(r * 2.0 * FACE_PX / (FACE_R * 2.0))
	var fade := 1.0 if lit else 0.4
	var restless := benched and Bench.restless(_party, id)
	var ring := Icons.COL_GOLD if (lit and (_hover_face == i or _hover_edge >= 0)) \
		else (COL_RESTLESS if restless else Icons.COL_EDGE)
	draw_circle(at, r, Color(Icons.COL_INK, fade))
	var cls: String = ch.class_id() if ch != null else ""
	var tex: Texture2D = Portraits.bust(String(HeroModels.get(cls, "")), FACE_PX)
	if tex != null:
		var half := Vector2(px, px) * 0.5
		draw_texture_rect(tex, Rect2(at - half, half * 2.0), false, Color(1, 1, 1, fade))
	else:
		var font := get_theme_default_font()
		var g := Icons.class_glyph(cls)
		var gs := 26 if not benched else 18
		var sz := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
		draw_string(font, at + Vector2(-sz.x * 0.5, sz.y * 0.5 - font.get_descent(gs)),
			g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(Icons.COL_GOLD, fade))
	draw_arc(at, r, 0.0, TAU, 48, Color(ring, fade), 2.5 if not restless else 3.0, true)
	if restless:   # a mark on the shoulder, like the trait spark on a line
		var m := at + Vector2(r * 0.72, -r * 0.72)
		draw_circle(m, 6.5, Color(Icons.COL_INK, fade))
		draw_circle(m, 5.0, Color(COL_RESTLESS, fade))
		var mf := get_theme_default_font()
		var msz := mf.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(mf, m + Vector2(-msz.x * 0.5, msz.y * 0.5 - mf.get_descent(10)), "!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Icons.COL_INK, fade))
	# The first name — the one word the picture needs — on the face's outer
	# side (above the top row, below the bottom one and every benched face),
	# where no line runs.
	var nm: String = String(ch.cname).get_slice(" ", 0) if ch != null else ""
	var font := get_theme_default_font()
	var fs := Icons.FS_SMALL if not benched else 11
	var nsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var above := not benched and at.y < _field().get_center().y
	var base := at + Vector2(-nsz.x * 0.5,
		-r - 4.0 - font.get_descent(fs) if above else r + 3.0 + font.get_ascent(fs))
	draw_string_outline(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Icons.COL_BG, fade))
	draw_string(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Icons.COL_TEXT, fade))

# The bench column's caption over it, and a rule between it and the ring.
func _draw_bench_caption() -> void:
	var font := get_theme_default_font()
	var fs := 12
	var strip := _bench_strip()
	draw_line(Vector2(strip.position.x, 4), Vector2(strip.position.x, strip.end.y - 4),
		Color(Icons.COL_EDGE, 0.5), 1.0)
	var sz := font.get_string_size("Bench", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(strip.get_center().x - sz.x * 0.5, font.get_ascent(fs)), "Bench",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Icons.COL_MUTED)

# The key along the bottom: a short stroke of each band's line, then its name.
func _draw_legend() -> void:
	var font := get_theme_default_font()
	var fs := 12
	var y := size.y - LEGEND_H * 0.5
	var widths: Array = []
	var total := 0.0
	for band in BANDS:
		var wd := 22.0 + 4.0 + font.get_string_size(band, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(wd)
		total += wd
	var gap := 12.0
	total += gap * (BANDS.size() - 1)
	var x := (size.x - total) * 0.5
	for k in BANDS.size():
		var band: String = BANDS[k]
		var col: Color = BAND_COLOR[band]
		var a := Vector2(x, y)
		var b := Vector2(x + 22.0, y)
		match band:
			"rivals":
				draw_polyline(PackedVector2Array([a, a + Vector2(5.5, -3), a + Vector2(11, 3), a + Vector2(16.5, -3), b]), col, 2.0, true)
			"cold":
				draw_dashed_line(a, b, col, 2.0, 5.0, true, true)
			"neutral":
				draw_dashed_line(a, b, col, 2.0, 2.5, true, true)
			"lovers":
				draw_line(a + Vector2(0, -2), b + Vector2(0, -2), col, 1.5, true)
				draw_line(a + Vector2(0, 2), b + Vector2(0, 2), col, 1.5, true)
			_:
				draw_line(a, b, col, 3.0, true)
		draw_string(font, Vector2(x + 26.0, y + font.get_ascent(fs) * 0.5 - 1.0), band,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Icons.COL_MUTED)
		x += float(widths[k]) + gap
