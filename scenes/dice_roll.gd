# A d20 rolled in front of the player (#176's follow-up: "these rolls need to be
# rolled live to hype up interest"). Every check off the fight board — the
# road's events, the approach, a camp's watch, a landmark, a town's haggling —
# is rolled and applied in core/ before any screen exists; this is the replay.
# It drops in spinning, tumbles through faces that slow as it settles, slams
# down on the face the rules already rolled — flash, shockwave, rays, sparks —
# and then the verdict word lands on top of the arithmetic that made it.
#
#   const DiceRoll = preload("res://scenes/dice_roll.gd")
#   var d := DiceRoll.new()
#   parent.add_child(d)
#   d.landed.connect(_on_landed)                  # once, when the verdict is up
#   d.play({"nat": 14, "bonus": 5, "dc": 13, "ok": true})
#   # optional keys: "dice": [a, b] and "mode": "adv"|"dis" (both faces shown,
#   # the kept one lit), "label": "Survival" (under the die while it rolls)
#
# What it does NOT own: the roll (core/ made it; nothing here rolls anything
# that matters — the faces it tumbles through, the sparks' angles and the shake
# are all counted off the clock and the natural, not drawn from an RNG, so the
# show is the same every time it is watched), whether it passed (the caller's
# `ok`: the road ignores naturals and a carouse honours them, and the die must
# not re-decide either), or what happens next (whoever listens to `landed`).
# The flourish reaches past the widget's rect on purpose — the rays and the
# rings belong to the screen, not to the box the die is laid out in.
#
# Settings.anim() scales it and SORCMERC_FAST lands it at once, like
# scenes/world/spoils.gd and scenes/world/trait_moment.gd — every test and
# robot runs with SORCMERC_FAST, and sees the landed die on the first frame.
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Sound = preload("res://core/audio.gd")

signal landed()

# Sizes. The owner: "make the dice larger and animations flashy" — the die was
# 92 px high and read as an icon; at 150 it is the thing on the screen.
const DIE := 150.0             # the die's height
const FACE_SIZE := 64          # the number on it
const VERDICT_SIZE := 40       # "MADE IT!"
const TALLY_SIZE := 24         # "14 + 5 = 19 vs DC 13  —  made it"
const LABEL_SIZE := 20         # "Survival — Vera Kord", while it rolls
const TOP := 16.0              # room above the die for the drop's last bounce
const HEIGHT := TOP + DIE + 22.0 + VERDICT_SIZE + 12.0 + TALLY_SIZE + 12.0   # what a caller sizes it to

# The show runs off one clock, `_t`, in seconds at anim() == 1:
const T_LAND := 1.05           # the tumble: dropping in, spinning down, faces slowing
const T_BURST := 0.6           # after touchdown: the flash, the rings, the rays, the sparks
const T_VERDICT := 0.28        # the verdict word slams in, from big to its size
const T_TALLY := 0.3           # the arithmetic slides up under it
const T_HOLD := 0.9            # all of it up, readable, before `landed` lets the caller move on
const T_TOTAL := T_LAND + 0.3 + T_TALLY + T_HOLD
const TICKS := 14              # face changes during the tumble — each one clicks
const RAYS := 16
const SPARKS := 14

var _r: Dictionary = {}
var _playing := false
var _landed := false
var _face := 0                 # what the die shows right now
var _other := 0                # the second die under advantage/disadvantage, 0 = none
var _t := 0.0                  # the show's clock
var _tween: Tween = null
var _emitted := false

# How many dice are in the air anywhere, for whatever must wait for them — the
# achievement toast (scenes/achievements/toast.gd) holds its queue, or "Talked
# Down" pops up over a haggle's die before it has landed.
static var _in_air := 0
var _counted := false

static func in_air() -> bool:
	return _in_air > 0


func _count(on: bool) -> void:
	if on == _counted:
		return
	_counted = on
	_in_air = maxi(0, _in_air + (1 if on else -1))


func _exit_tree() -> void:
	_count(false)   # freed mid-roll (a panel rebuilt under it): not in the air any more


# Defaults, set before the caller's own: a popup gives the die a width to
# centre in, and a click to land it (these were in _ready once, which ran after
# the caller and quietly undid both).
func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_playing() -> bool:
	return _playing


func has_landed() -> bool:
	return _landed


func play(r: Dictionary) -> void:
	_r = r.duplicate()
	var dice: Array = _r.get("dice", [])
	var mode := String(_r.get("mode", ""))
	_other = 0
	if dice.size() == 2 and mode in ["adv", "dis"]:
		_other = int(dice[1]) if int(dice[0]) == _nat() else int(dice[0])
	_landed = false
	_emitted = false
	_face = 0
	_t = 0.0
	var speed := Settings.anim()
	if speed >= Settings.FAST:
		finish()
		return
	_playing = true
	_count(true)
	_tween = create_tween()
	_tween.tween_method(_advance, 0.0, T_TOTAL, T_TOTAL / maxf(speed, 0.01))
	_tween.tween_callback(_done)
	queue_redraw()


# Jump to the end: the landed face, the verdict, the tally. A press during the
# roll calls this, so it finishes the roll rather than skipping the result.
func finish() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _landed:
		_touchdown()
	_t = T_TOTAL
	_done()


func _nat() -> int:
	return clampi(int(_r.get("nat", 1)), 1, 20)


func _advance(t: float) -> void:
	_t = t
	if t < T_LAND:
		# The faces slow as the die settles — the last few are the suspense.
		var e := _out(t / T_LAND)
		var face := 1 + (int(e * TICKS) * 7 + _nat() * 3) % 20   # counted, not rolled
		if face == _nat():
			face = face % 20 + 1   # never show the answer early
		if face != _face:
			_face = face
			Sound.play_sfx("click")
	elif not _landed:
		_touchdown()
	queue_redraw()


func _touchdown() -> void:
	_face = _nat()
	_landed = true
	var sting := "crit" if _crit() else ("save_made" if ok() else "save_failed")
	Sound.play_sfx(sting)
	queue_redraw()


func _done() -> void:
	_playing = false
	_count(false)
	queue_redraw()
	if not _emitted:
		_emitted = true
		landed.emit()


# The tween moves script variables, which do not redraw on their own.
func _process(_dt: float) -> void:
	if _playing:
		queue_redraw()


func ok() -> bool:
	return bool(_r.get("ok", false))


# A natural 20 that the rule counted: the gold show. A 20 that still missed
# (the road ignores naturals) gets the miss's, as the verdict says.
func _crit() -> bool:
	return _nat() == 20 and ok()


# The tally line as it reads once landed: "14 + 5 = 19 vs DC 13  —  made it".
func tally() -> String:
	var bonus := int(_r.get("bonus", 0))
	var total := _nat() + bonus
	var line := "%d %s %d = %d vs DC %d" % [_nat(), "+" if bonus >= 0 else "−", absi(bonus), total,
		int(_r.get("dc", 10))]
	return line + ("  —  made it" if ok() else "  —  missed")


# The one big word on top of it.
func verdict() -> String:
	if _crit():
		return "NATURAL 20!"
	if ok():
		return "MADE IT!"
	return "NATURAL 1" if _nat() == 1 else "MISSED"


func _col() -> Color:
	if not _landed:
		return Icons.COL_HEAD
	if _crit():
		return Icons.COL_GOLD
	return Icons.COL_PARTY if ok() else Icons.COL_FOE


static func _out(f: float) -> float:
	var x := clampf(f, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


func _draw() -> void:
	var col := _col()
	var r := DIE * 0.5
	var c := Vector2(size.x * 0.5, TOP + r)
	var since := _t - T_LAND       # time since touchdown; negative while it tumbles
	var rot := 0.0
	var sc := 1.0
	if not _landed:
		var f := clampf(_t / T_LAND, 0.0, 1.0)
		var e := _out(f)
		c.y -= DIE * 1.1 * pow(1.0 - minf(f / 0.32, 1.0), 2.0)   # drops in from above
		rot = pow(1.0 - e, 2.0) * TAU * 3.0                      # spins fast, spins down
		sc = 1.0 + 0.09 * sin(f * TAU * 4.0) * (1.0 - f)          # wobbles as it goes
		_glow(c, r * 1.7, Icons.COL_HEAD, 0.10 + 0.05 * sin(_t * 14.0))
		for i in range(3, 0, -1):                                 # the motion trail
			_die(c, DIE * sc, rot + i * 0.28 * (1.0 - e), 0, Icons.COL_HEAD, 0.10 * (4 - i) / 3.0)
	else:
		var b := clampf(since / T_BURST, 0.0, 1.0)
		sc = maxf(0.85, 1.0 + 0.5 * exp(-since * 9.0) * cos(since * 22.0))   # slams, then springs
		if not ok() or _crit():
			c += Vector2(sin(since * 70.0), cos(since * 53.0)) * 9.0 * exp(-since * 10.0)
		_glow(c, r * 2.4, col, 0.14 + 0.40 * (1.0 - b) + 0.05 * sin(_t * 6.0))
		_rays(c, r, col, since, b)
		_rings(c, r, col, since)
		_sparks(c, r, col, b)
	if _other > 0:
		_die(c + Vector2(DIE * 0.78, DIE * 0.12), DIE * 0.5, 0.0, _other, Icons.COL_MUTED, 0.55)
	_die(c, DIE * sc, rot, _face if _face > 0 else _nat(), col, 1.0)
	if _landed and since < 0.3:   # the white flash of the impact
		_hex(c, DIE * sc * 0.5, rot, Color(1, 1, 1, 0.75 * (1.0 - since / 0.3)))

	var y_v := TOP + DIE + 22.0 + VERDICT_SIZE * 0.8
	var y_t := y_v + 12.0 + TALLY_SIZE
	if not _landed:
		var label := String(_r.get("label", ""))
		if label != "":
			_text(label, Vector2(size.x * 0.5, y_v), LABEL_SIZE, Icons.COL_MUTED, 1.0, false)
		return
	var v := clampf((since - 0.06) / T_VERDICT, 0.0, 1.0)
	if v > 0.0:
		var k := 1.0 + 1.4 * pow(1.0 - v, 3.0)   # from big to its size: a slam, not a fade
		draw_set_transform(Vector2(size.x * 0.5, y_v - VERDICT_SIZE * 0.3), 0.0, Vector2(k, k))
		_text(verdict(), Vector2(0, VERDICT_SIZE * 0.3), VERDICT_SIZE, col.lightened(0.1), v, true)
		draw_set_transform(Vector2.ZERO)
	var tl := clampf((since - 0.3) / T_TALLY, 0.0, 1.0)
	if tl > 0.0:
		_text(tally(), Vector2(size.x * 0.5, y_t + 14.0 * (1.0 - tl)), TALLY_SIZE, col, tl, false)


# Centred text with a dark outline, so it reads over whatever the popup darkened.
func _text(s: String, at: Vector2, fs: int, col: Color, a: float, bold: bool) -> void:
	var font: Font = Icons.serif(700) if bold else Icons.sans(700)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w * 0.5, 0)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(Icons.COL_INK, 0.85 * a))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))


# A soft round light: stacked discs, each faint, brightest where they overlap
# (enough of them that the steps between them do not read as rings).
const GLOW_STEPS := 24

func _glow(at: Vector2, r: float, col: Color, a: float) -> void:
	for i in GLOW_STEPS:
		draw_circle(at, r * (1.0 - float(i) / GLOW_STEPS), Color(col, a / GLOW_STEPS))


# Two shockwave rings off the impact, the second a beat behind the first.
func _rings(at: Vector2, r: float, col: Color, since: float) -> void:
	for j in 2:
		var q := clampf((since - j * 0.12) / T_BURST, 0.0, 1.0)
		if q <= 0.0 or q >= 1.0:
			continue
		draw_arc(at, r * (0.9 + 2.0 * _out(q)), 0.0, TAU, 64, Color(col.lightened(0.3), 1.0 - q),
			2.0 + 7.0 * (1.0 - q), true)


# Light spears out of the die. A natural 20 keeps them: a slow gold sunburst
# behind the die for as long as it holds.
func _rays(at: Vector2, r: float, col: Color, since: float, b: float) -> void:
	var a := 0.55 * (1.0 - b)
	var turn := 0.3
	var reach := 1.3 + 1.2 * _out(b)
	if _crit():
		a = maxf(a, 0.30)
		turn += since * 0.6
		reach = maxf(reach, 2.2)
	if a <= 0.0:
		return
	for i in RAYS:
		var ang := turn + TAU * i / RAYS
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x) * r * 0.09
		var long := 1.0 if i % 2 == 0 else 0.7
		draw_colored_polygon(PackedVector2Array([at + dir * r * 0.8 + side, at + dir * r * reach * long,
			at + dir * r * 0.8 - side]), Color(col.lightened(0.25), a))


# Sparks thrown off the impact; a miss's are shards that fall.
func _sparks(at: Vector2, r: float, col: Color, b: float) -> void:
	if b >= 1.0:
		return
	var fall := 0.0 if ok() else 1.0
	for i in SPARKS:
		var ang := i * 2.39996 + _nat() * 0.7   # the golden angle: spread even, the same every time
		var dir := Vector2(cos(ang), sin(ang))
		var dist := r * (0.7 + (1.6 + 0.6 * (i % 3)) * _out(b))
		var p := at + dir * dist + Vector2(0, 220.0 * b * b * fall)
		draw_circle(p, (5.0 if i % 2 == 0 else 3.0) * (1.0 - b), Color(col.lightened(0.4), 1.0 - b))


func _hex(at: Vector2, r: float, rot: float, col: Color) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := rot + TAU * i / 6.0 - PI / 2.0
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
	return pts


# A d20 as the icon every table knows: a hexagon with the triangle facets
# inside it, the number on the front face (none, n = 0, for the motion trail).
func _die(at: Vector2, h: float, rot: float, n: int, col: Color, alpha: float) -> void:
	var r := h * 0.5
	var pts := _hex(at, r, rot, Color(Icons.COL_INK, alpha))
	var edge := Color(col, 0.9 * alpha)
	pts.append(pts[0])
	draw_polyline(pts, edge, 3.0, true)
	# the front triangle and the spokes to the rim
	var tri := PackedVector2Array()
	for i in 3:
		var a := rot + TAU * i / 3.0 - PI / 2.0
		tri.append(at + Vector2(cos(a), sin(a)) * r * 0.55)
	tri.append(tri[0])
	draw_polyline(tri, Color(col, 0.5 * alpha), 2.0, true)
	for i in 6:
		draw_line(tri[(i + 1) / 2 % 3], pts[i], Color(col, 0.3 * alpha), 1.5, true)
	if n <= 0:
		return
	var s := str(n)
	var fs := int(FACE_SIZE * h / DIE)
	var w := Icons.serif(700).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(Icons.serif(700), at + Vector2(-w * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, Color(col.lightened(0.15), alpha))
