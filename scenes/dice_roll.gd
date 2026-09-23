# A d20 rolled in front of the player (#176's follow-up: "these rolls need to be
# rolled live to hype up interest"). Every check off the fight board — the
# road's events, the approach, a camp's watch, a landmark, a town's haggling —
# is rolled and applied in core/ before any screen exists; this is the replay.
# It tumbles, lands on the face the rules already rolled, then counts up the
# bonus to the total against the DC and says whether it made it.
#
#   const DiceRoll = preload("res://scenes/dice_roll.gd")
#   var d := DiceRoll.new()
#   parent.add_child(d)
#   d.landed.connect(_on_landed)                  # once, when the verdict is up
#   d.play({"nat": 14, "bonus": 5, "dc": 13, "ok": true})
#   # optional keys: "dice": [a, b] and "mode": "adv"|"dis" (both faces shown,
#   # the kept one lit), "label": "Survival" (under the die)
#
# What it does NOT own: the roll (core/ made it; nothing here rolls anything
# that matters — the faces it tumbles through are counted off the tick, not
# drawn from an RNG), whether it passed (the caller's `ok`: the road ignores
# naturals and a carouse honours them, and the die must not re-decide either),
# or what happens next (whoever listens to `landed`).
#
# Settings.anim() scales it and SORCMERC_FAST lands it at once, like
# scenes/world/spoils.gd and scenes/world/trait_moment.gd — every test and
# robot runs with SORCMERC_FAST, and sees the landed die on the first frame.
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Sound = preload("res://core/audio.gd")

signal landed()

const DIE := 92.0              # the die's height; the widget is sized around it
const FACE_SIZE := 40
const TALLY_SIZE := 22
const T_TUMBLE := 0.75         # seconds at anim() == 1: the faces go by
const T_SETTLE := 0.18         # the landing bounce
const T_TALLY := 0.30          # the +bonus = total vs DC line comes up
const T_HOLD := 0.60           # ...and stays, readable, before `landed` lets the caller move on
const TICKS := 11              # face changes during the tumble — each one clicks

var _r: Dictionary = {}
var _playing := false
var _landed := false
var _face := 0                 # what the die shows right now
var _other := 0                # the second die under advantage/disadvantage, 0 = none
var _tally_a := 0.0            # 0..1: how much of the tally line is up
var _spin := 0.0               # radians: the tumble
var _pop := 1.0                # the landing scale
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
	custom_minimum_size = Vector2(0, DIE + TALLY_SIZE + 28)
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
	_tally_a = 0.0
	var speed := Settings.anim()
	if speed >= Settings.FAST:
		finish()
		return
	_playing = true
	_count(true)
	var k := 1.0 / maxf(speed, 0.01)
	_tween = create_tween()
	_tween.tween_method(_tick, 0.0, 1.0, T_TUMBLE * k)
	_tween.tween_callback(_touchdown)
	_tween.tween_property(self, "_pop", 1.0, T_SETTLE * k).from(1.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_tally_a", 1.0, T_TALLY * k)
	_tween.tween_interval(T_HOLD * k)
	_tween.tween_callback(_done)
	queue_redraw()


# Jump to the end: the landed face, the tally, the verdict. A press during the
# roll calls this, so it finishes the roll rather than skipping the result.
func finish() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _landed:
		_touchdown()
	_pop = 1.0
	_tally_a = 1.0
	_done()


func _nat() -> int:
	return clampi(int(_r.get("nat", 1)), 1, 20)


func _tick(f: float) -> void:
	var step := int(f * TICKS)
	var face := 1 + (step * 7 + _nat() * 3) % 20   # counted, not rolled: the show is the same every time
	if face != _face and f < 1.0:
		_face = face
		Sound.play_sfx("click")
	_spin = (1.0 - f) * TAU * 1.5
	queue_redraw()


func _touchdown() -> void:
	_face = _nat()
	_spin = 0.0
	_landed = true
	var sting := "crit" if _nat() == 20 else ("save_made" if ok() else "save_failed")
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


# The tally line as it reads once landed: "14 +5 = 19 vs DC 13 — made it".
func tally() -> String:
	var bonus := int(_r.get("bonus", 0))
	var total := _nat() + bonus
	var line := "%d %s %d = %d vs DC %d" % [_nat(), "+" if bonus >= 0 else "−", absi(bonus), total,
		int(_r.get("dc", 10))]
	return line + ("  —  made it" if ok() else "  —  missed")


func _draw() -> void:
	var col: Color = Icons.COL_PARTY if ok() else Icons.COL_FOE
	if _nat() == 20 and _landed:
		col = Icons.COL_GOLD
	var face_col: Color = col if _landed else Icons.COL_HEAD
	var c := Vector2(size.x * 0.5, DIE * 0.5 + 4.0)
	if _other > 0:
		_die(c + Vector2(DIE * 0.62, 6.0), DIE * 0.62, 0.0, _other, Icons.COL_MUTED, 0.55)
		c.x -= DIE * 0.25
	_die(c, DIE * _pop, _spin, _face if _face > 0 else _nat(), face_col, 1.0)
	var label := String(_r.get("label", ""))
	var y := DIE + 16.0 + TALLY_SIZE
	if _tally_a > 0.0:
		var t := tally()
		var w := Icons.sans(700).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, TALLY_SIZE).x
		draw_string(Icons.sans(700), Vector2((size.x - w) * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TALLY_SIZE, Color(col, _tally_a))
	elif label != "":
		var w2 := Icons.sans().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TALLY_SIZE - 4).x
		draw_string(Icons.sans(), Vector2((size.x - w2) * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TALLY_SIZE - 4, Icons.COL_MUTED)


# A d20 as the icon every table knows: a hexagon with the triangle facets
# inside it, the number on the front face.
func _die(at: Vector2, h: float, rot: float, n: int, col: Color, alpha: float) -> void:
	var r := h * 0.5
	var pts := PackedVector2Array()
	for i in 6:
		var a := rot + TAU * i / 6.0 - PI / 2.0
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(Icons.COL_INK, alpha))
	var edge := Color(col, 0.85 * alpha)
	pts.append(pts[0])
	draw_polyline(pts, edge, 2.0, true)
	# the front triangle and the spokes to the rim
	var tri := PackedVector2Array()
	for i in 3:
		var a := rot + TAU * i / 3.0 - PI / 2.0
		tri.append(at + Vector2(cos(a), sin(a)) * r * 0.55)
	tri.append(tri[0])
	draw_polyline(tri, Color(col, 0.45 * alpha), 1.5, true)
	for i in 6:
		draw_line(tri[(i + 1) / 2 % 3], pts[i], Color(col, 0.25 * alpha), 1.0, true)
	var s := str(n)
	var fs := int(FACE_SIZE * h / DIE)
	var w := Icons.serif(700).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(Icons.serif(700), at + Vector2(-w * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, Color(col.lightened(0.15), alpha))
