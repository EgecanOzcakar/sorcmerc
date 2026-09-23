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
# What it does not own: any rule about opinion (all of it is PartyOpinion's —
# this reads band/score/describe and Traits.opinion_terms, and writes nothing),
# or the choice of who is drawn (the party's active list, in marching order).
# Faces are scenes/portraits.gd's busts; headless and for a class the art does
# not cover, the class glyph stands in, the way the rest of the page falls back.
extends Control

const PartyOpinion = preload("res://core/party_opinion.gd")
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

var _party = null
var _ids: Array = []          # the marching party, in order
var _hover_face := -1
var _hover_edge := -1         # an index into edges()


func _init() -> void:
	name = "RelationsWeb"
	custom_minimum_size = Vector2(460, 250)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(party) -> void:
	_party = party
	_ids = Array(party.active).map(func(i): return String(i))
	_hover_face = -1
	_hover_edge = -1
	queue_redraw()


# One entry per active pair, in PartyOpinion.active_pairs()'s order: who, the
# band, the score, and the traits behind the pull. What the lines are drawn
# from, and what a test reads.
func edges() -> Array:
	var out: Array = []
	if _party == null:
		return out
	for pr in PartyOpinion.pairs(_ids):
		var a := String(pr[0])
		var b := String(pr[1])
		var ca = _party.get_member(a)
		var cb = _party.get_member(b)
		out.append({
			"a": a, "b": b,
			"band": PartyOpinion.band(_party, a, b),
			"score": PartyOpinion.score(_party, a, b),
			"why": Traits.opinion_terms(ca, cb)["why"] if ca != null and cb != null else [],
		})
	return out


# --- where things are ---------------------------------------------------------

func _field() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x, size.y - LEGEND_H))

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
	return out

func _index(id: String) -> int:
	return _ids.find(id)

func _is_diagonal(e: Dictionary) -> bool:
	return _ids.size() == 4 and absi(_index(e["a"]) - _index(e["b"])) == 2

# The line between two faces, trimmed to their rims.
func _segment(e: Dictionary, pos: Array) -> Array:
	var p: Vector2 = pos[_index(e["a"])]
	var q: Vector2 = pos[_index(e["b"])]
	var d := (q - p).normalized()
	return [p + d * (FACE_R + 4.0), q - d * (FACE_R + 4.0)]

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
		if at.distance_to(pos[i]) <= FACE_R + 2.0:
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

# Over a line: that pair's describe(). Over a face: every line they are on.
func tooltip_at(at: Vector2) -> String:
	if _party == null:
		return ""
	var f := face_at(at)
	if f >= 0:
		var mine: Array = []
		for e in edges():
			if e["a"] == _ids[f] or e["b"] == _ids[f]:
				mine.append(PartyOpinion.describe(_party, e["a"], e["b"]))
		return "\n".join(mine)
	var i := edge_at(at)
	if i < 0:
		return ""
	var e: Dictionary = edges()[i]
	return PartyOpinion.describe(_party, e["a"], e["b"])

func _get_tooltip(at: Vector2) -> String:
	return tooltip_at(at)


# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _party == null or _ids.size() < 2:
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
	for i in es.size():
		_draw_edge(es[i], pos, lit.is_empty() or lit.has("e%d" % i), i == _hover_edge)
	for i in es.size():
		_draw_badge(es[i], pos, lit.is_empty() or lit.has("e%d" % i))
	for i in pos.size():
		_draw_face(i, pos[i], lit.is_empty() or lit.has(i))
	_draw_legend()

func _draw_edge(e: Dictionary, pos: Array, lit: bool, hot: bool) -> void:
	var seg := _segment(e, pos)
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var band := String(e["band"])
	var col: Color = BAND_COLOR[band]
	col.a = 1.0 if lit else 0.18
	var w := 2.0 + 5.0 * minf(absf(float(e["score"])) / PartyOpinion.RANGE, 1.0) + (1.5 if hot else 0.0)
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
	var ch = _party.get_member(_ids[i])
	var fade := 1.0 if lit else 0.4
	var ring := Icons.COL_GOLD if (lit and (_hover_face == i or _hover_edge >= 0)) else Icons.COL_EDGE
	draw_circle(at, FACE_R, Color(Icons.COL_INK, fade))
	var cls: String = ch.class_id() if ch != null else ""
	var tex: Texture2D = Portraits.bust(String(HeroModels.get(cls, "")), FACE_PX)
	if tex != null:
		var half := Vector2(FACE_PX, FACE_PX) * 0.5
		draw_texture_rect(tex, Rect2(at - half, half * 2.0), false, Color(1, 1, 1, fade))
	else:
		var font := get_theme_default_font()
		var g := Icons.class_glyph(cls)
		var sz := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		draw_string(font, at + Vector2(-sz.x * 0.5, sz.y * 0.5 - font.get_descent(26)),
			g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(Icons.COL_GOLD, fade))
	draw_arc(at, FACE_R, 0.0, TAU, 48, Color(ring, fade), 2.5, true)
	# The first name — the one word the picture needs — on the face's outer
	# side (above the top row, below the bottom one), where no line runs.
	var nm: String = String(ch.cname).get_slice(" ", 0) if ch != null else ""
	var font := get_theme_default_font()
	var fs := Icons.FS_SMALL
	var nsz := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var above := at.y < _field().get_center().y
	var base := at + Vector2(-nsz.x * 0.5,
		-FACE_R - 4.0 - font.get_descent(fs) if above else FACE_R + 4.0 + font.get_ascent(fs))
	draw_string_outline(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Icons.COL_BG, fade))
	draw_string(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Icons.COL_TEXT, fade))

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
