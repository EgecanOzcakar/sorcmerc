# The dice, drawn. One painter for every die the game shows: the big d20 that
# tumbles in scenes/dice_roll.gd when a check is rolled live, and the small
# still ones in an action's hover card (scenes/skill_card.gd) that say what a
# spell or a swing will roll. The owner's ask was that the card show "the dice
# rolled with their static image as used in the live rolls", so the live roll
# calls paint() too and the two cannot drift apart.
#
#   const DieIcon = preload("res://scenes/die_icon.gd")
#   DieIcon.paint(self, centre, height, 20, 14, col)   # from any _draw()
#   var d := DieIcon.new(); d.sides = 6; d.color = Icons.damage_color("fire")
#   row.add_child(d)                                   # a still one, laid out
#
# Each size is the silhouette a player knows it by, in the d20's hand: an ink
# body, a lit rim, faint facet lines, the number on the front face. d4 a
# triangle, d6 a square, d8 a diamond, d10 a kite, d12 a pentagon, d20 the
# hexagon with the triangle inside it. The still icon's number is the die's
# own size — "6" on the d6 — because it says which die, not what came up.
# The number is dice_roll.gd's FACE_SIZE (64) at its DIE (150), scaled.
# A die size the game never rolls (a d100, a content pack's d3) draws as a d20
# with its number on: still a die, still labelled.
#
# What it does NOT own: any roll, any animation. dice_roll.gd spins it; this
# only knows how one frame of a die looks.
extends Control

const Icons = preload("res://core/ui_icons.gd")

var sides := 20
var face := 0          # the number on it; 0 = the die's own size
var color := Icons.COL_HEAD

func _init() -> void:
	custom_minimum_size = Vector2(24, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var h := minf(size.x, size.y)
	paint(self, size * 0.5, h, sides, face if face > 0 else sides, color, 1.0)

# The silhouette's corners around `at`, height `h`, turned by `rot`.
static func outline(at: Vector2, h: float, sides: int, rot := 0.0) -> PackedVector2Array:
	var r := h * 0.5
	var pts := PackedVector2Array()
	match sides:
		4:   # sat a little low, so the triangle fills the box its height is measured in
			for i in 3:
				pts.append(_polar(at + Vector2(0, r * 0.15).rotated(rot), r * 1.1, rot + TAU * i / 3.0 - PI / 2.0))
		6:
			for i in 4:
				pts.append(_polar(at, r * 1.1, rot + TAU * i / 4.0 - PI / 4.0 * 3.0))
		8:
			for i in 4:
				var k := 1.0 if i % 2 == 0 else 0.78   # taller than wide: a diamond, not a square on end
				pts.append(_polar(at, r * k, rot + TAU * i / 4.0 - PI / 2.0))
		10:  # a kite: the point, the two shoulders just below the middle, a short tail
			for p in [Vector2(0, -1.0), Vector2(0.86, 0.12), Vector2(0, 0.86), Vector2(-0.86, 0.12)]:
				pts.append(at + (p * r).rotated(rot))
		12:
			for i in 5:
				pts.append(_polar(at, r, rot + TAU * i / 5.0 - PI / 2.0))
		_:
			for i in 6:
				pts.append(_polar(at, r, rot + TAU * i / 6.0 - PI / 2.0))
	return pts

static func _polar(at: Vector2, r: float, a: float) -> Vector2:
	return at + Vector2(cos(a), sin(a)) * r

# One die on `ci`, centred on `at`, `h` tall. n = 0 draws no number (the live
# roll's motion trail). Line weights thin out below 60 px, so the live d20
# (150 px) and its advantage twin (75) keep the 3 / 2 / 1.5 px strokes they
# have always had and a 22 px icon does not drown in its own outline.
static func paint(ci: CanvasItem, at: Vector2, h: float, sides: int, n: int, col: Color,
		alpha: float, rot := 0.0) -> void:
	var r := h * 0.5
	var k := clampf(h / 60.0, 0.45, 1.0)
	var pts := outline(at, h, sides, rot)
	ci.draw_colored_polygon(pts, Color(Icons.COL_INK, alpha))
	var ring := pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, Color(col, 0.9 * alpha), 3.0 * k, true)
	var facet := Color(col, 0.5 * alpha)
	var spoke := Color(col, 0.3 * alpha)
	match sides:
		4:   # the ridge up the middle
			ci.draw_line(pts[0], at + Vector2(0, r * 0.7).rotated(rot), spoke, 1.5 * k, true)
		6:   # a bevelled top face
			var inner := outline(at, h * 0.62, 6, rot)
			inner.append(inner[0])
			ci.draw_polyline(inner, facet, 2.0 * k, true)
		8:   # the belt between the two pyramids
			ci.draw_line(pts[1], pts[3], spoke, 1.5 * k, true)
		10:  # the kite's front face: shoulders in to the waist, the waist down to the tail
			var waist := at + Vector2(0, r * 0.45).rotated(rot)
			ci.draw_line(pts[1], waist, spoke, 1.5 * k, true)
			ci.draw_line(pts[3], waist, spoke, 1.5 * k, true)
			ci.draw_line(waist, pts[2], spoke, 1.5 * k, true)
		12:  # the front pentagon and its spokes
			var inner := outline(at, h * 0.55, 12, rot)
			var closed := inner.duplicate()
			closed.append(inner[0])
			ci.draw_polyline(closed, facet, 2.0 * k, true)
			for i in 5:
				ci.draw_line(inner[i], pts[i], spoke, 1.5 * k, true)
		_:   # d20: the front triangle and the spokes to the rim
			var tri := PackedVector2Array()
			for i in 3:
				tri.append(_polar(at, r * 0.55, rot + TAU * i / 3.0 - PI / 2.0))
			tri.append(tri[0])
			ci.draw_polyline(tri, facet, 2.0 * k, true)
			for i in 6:
				ci.draw_line(tri[(i + 1) / 2 % 3], pts[i], spoke, 1.5 * k, true)
	if n <= 0:
		return
	var s := str(n)
	var font := Icons.serif(700)
	# The number sits where the face is: lower on the d4, whose centre is above
	# its visual weight. 64 at 150 px is the live roll's FACE_SIZE; small dice
	# get a touch more, or a two-digit "12" is unreadable at icon size.
	var fs := maxi(9, int(64.0 * h / 150.0 * (1.0 if h >= 60.0 else 1.15)))
	if s.length() > 1 and h < 60.0:
		fs = int(fs * 0.85)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lift := r * 0.3 if sides == 4 else (-r * 0.12 if sides == 10 else 0.0)
	ci.draw_string(font, at + Vector2(-w * 0.5, fs * 0.36 + lift), s, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, Color(col.lightened(0.15), alpha))
