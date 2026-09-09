# Playable UI for The Sunken Shrine — hex board, drawn tokens, styled buttons.
# All rules live in core/. Built programmatically so it needs no editor work.
extends Control

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")

const HEX_BASE := 34.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var hex_px: float:
	get: return HEX_BASE * _zoom
const FAST := false  # set by _ready from SORCMERC_FAST

var cb
var _seed: int = 0
var _busy = false
var _advancing = false
var _disengage = false
var _mode := "idle"          # idle | cone | target
var _tgt_kind := ""          # attack | sacred | shove_* | heal | heal2 | help
var _cone_level := 1
var _hover_hex := Vector2i(999, 999)
var _anim := 1.0             # animation speed multiplier (huge when FAST)

@onready var _header := Label.new()
@onready var _order := RichTextLabel.new()
@onready var _board := Board.new()
@onready var _actor := Label.new()
@onready var _buttons := HFlowContainer.new()
@onready var _logbox := RichTextLabel.new()
@onready var _cap := Label.new()

# --- palette --------------------------------------------------------------
const COL_BG := Color("14161c")
const COL_HEX := Color("232733")
const COL_HEX_EDGE := Color("39404f")
const COL_BRAZIER := Color("6b2f1c")
const COL_COVER := Color("2a3a3a")
const COL_MOVE := Color(0.30, 0.55, 0.95, 0.35)
const COL_TARGET := Color(0.95, 0.35, 0.30, 0.9)
const COL_CONE := Color(0.98, 0.55, 0.15, 0.30)
const COL_PARTY := Color("5fbf6a")
const COL_FOE := Color("d15750")

func _ready() -> void:
	_anim = 999.0 if OS.get_environment("SORCMERC_FAST") != "" else 1.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 12; root.offset_top = 10
	root.offset_right = -12; root.offset_bottom = -10
	add_child(root)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	add_child(bg)
	move_child(bg, 0)

	_header.add_theme_font_size_override("font_size", 22)
	root.add_child(_header)

	# --- the action log: big, centred, shiny --------------------------
	var logwrap := PanelContainer.new()
	logwrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logwrap.custom_minimum_size = Vector2(820, 210)
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color("0c0e15")
	glow.set_corner_radius_all(14)
	glow.set_border_width_all(2)
	glow.border_color = Color("6f5a30")
	glow.shadow_color = Color(0.95, 0.78, 0.42, 0.22)
	glow.shadow_size = 16
	glow.set_content_margin_all(16)
	logwrap.add_theme_stylebox_override("panel", glow)
	var logcol := VBoxContainer.new()
	logcol.add_theme_constant_override("separation", 4)
	logwrap.add_child(logcol)
	_cap.text = "»   A C T I O N   L O G   «"
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.add_theme_color_override("font_color", Color("c8a75a"))
	logcol.add_child(_cap)
	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	_logbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_logbox.add_theme_font_size_override("normal_font_size", 18)
	_logbox.add_theme_font_size_override("bold_font_size", 18)
	_logbox.add_theme_color_override("default_color", Color("e9e9df"))
	logcol.add_child(_logbox)
	root.add_child(logwrap)

	_order.bbcode_enabled = true
	_order.fit_content = true
	_order.scroll_active = false
	_order.custom_minimum_size = Vector2(0, 26)
	root.add_child(_order)

	_board.main = self
	_board.clip_contents = true
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 240)
	root.add_child(_board)

	_actor.add_theme_font_size_override("font_size", 16)
	root.add_child(_actor)

	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	root.add_child(_buttons)

	set_process(true)
	_apply_ui_scale()
	_new_game()

# Font sizes across the whole combat UI track the zoom level.
func _apply_ui_scale() -> void:
	var u := clampf(_zoom, 0.9, 1.4)
	_header.add_theme_font_size_override("font_size", int(22 * u))
	_actor.add_theme_font_size_override("font_size", int(16 * u))
	_cap.add_theme_font_size_override("font_size", int(12 * u))
	_order.add_theme_font_size_override("normal_font_size", int(14 * u))
	_order.add_theme_font_size_override("bold_font_size", int(14 * u))
	_logbox.add_theme_font_size_override("normal_font_size", int(17 * u))
	_logbox.add_theme_font_size_override("bold_font_size", int(17 * u))
	for b in _buttons.get_children():
		b.add_theme_font_size_override("font_size", int(14 * u))

func set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.45, 3.0)
	_apply_ui_scale()
	if _board:
		_board.queue_redraw()

func pan_by(delta: Vector2) -> void:
	_pan += delta
	if _board:
		_board.queue_redraw()

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_EQUAL, KEY_KP_ADD: set_zoom(_zoom * 1.1)
		KEY_MINUS, KEY_KP_SUBTRACT: set_zoom(_zoom / 1.1)
		KEY_HOME: _zoom = 1.0; _pan = Vector2.ZERO; _apply_ui_scale(); _board.queue_redraw()
		KEY_LEFT: pan_by(Vector2(40, 0))
		KEY_RIGHT: pan_by(Vector2(-40, 0))
		KEY_UP: pan_by(Vector2(0, 40))
		KEY_DOWN: pan_by(Vector2(0, -40))
		KEY_ESCAPE, KEY_B: board_cancel()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_press_hotkey(e.keycode - KEY_1)
		KEY_0:
			_press_hotkey(-1)  # last button (End turn / Cancel)

func _press_hotkey(idx: int) -> void:
	if _busy:
		return
	var kids := _buttons.get_children()
	if kids.is_empty():
		return
	var b = kids[kids.size() - 1] if idx < 0 else (kids[idx] if idx < kids.size() else null)
	if b and not b.disabled:
		b.pressed.emit()

func _build_theme() -> void:
	var th := Theme.new()
	var mk := func(bg: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(6)
		s.content_margin_left = 10; s.content_margin_right = 10
		s.content_margin_top = 6; s.content_margin_bottom = 6
		return s
	th.set_stylebox("normal", "Button", mk.call(Color("2b3040")))
	th.set_stylebox("hover", "Button", mk.call(Color("3a4152")))
	th.set_stylebox("pressed", "Button", mk.call(Color("4a5570")))
	th.set_stylebox("disabled", "Button", mk.call(Color("22252e")))
	th.set_color("font_color", "Button", Color("e6e8ee"))
	th.set_color("font_hover_color", "Button", Color("ffffff"))
	theme = th

func _new_game() -> void:
	var env := OS.get_environment("SORCMERC_SEED")
	_seed = int(env) if env != "" else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)
	cb = Combat.new(RNG.new(_seed), Encounter.all())
	_logbox.text = ""
	_logged = 0
	_board.reset(cb)
	_flush_log()
	_refresh()
	_advance()

# --- turn driver --------------------------------------------------------

func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	while not cb.is_over():
		var c = cb.current()
		cb.begin_turn()
		_flush_log()
		_refresh()
		if c.is_dead() or c.is_stable():
			cb.end_turn()
			continue
		if c.team == "foe" or c.is_down():
			_busy = true
			_set_buttons([])
			await get_tree().create_timer(0.5 / _anim).timeout
			if not c.is_down():
				AI.take_turn(cb, c)
			_flush_log()
			_refresh()
			_busy = false
			cb.end_turn()
			continue
		_disengage = false
		_mode = "idle"
		_build_hero_menu(c)
		_advancing = false
		return
	_advancing = false
	_finish()

func _end_turn() -> void:
	if _busy:
		return
	_mode = "idle"
	cb.end_turn()
	_advance()

# --- hero menu ---------------------------------------------------------

# Verb-level menu. Buttons are numbered [1]..[9]; End turn is [0].
# Verbs that need a target enter "target" mode — hover a token for its %, click to apply.
func _build_hero_menu(h) -> void:
	_mode = "idle"
	_tgt_kind = ""
	var opts: Array = []
	var foes: Array = cb.enemies_of(h)
	var adj_foes := foes.filter(func(f): return Hex.distance(f.pos, h.pos) <= 1)

	var live_allies: Array = cb.combatants.filter(func(a): return a.team == "party" and a != h and a.conscious())

	if not cb.action_used:
		if foes.any(func(f): return cb.in_reach(h, f)):
			opts.append(["Attack", func(): _enter_target(h, "attack")])
		if h.athletics > 0 and not adj_foes.is_empty():
			opts.append(["Shove → prone", func(): _enter_target(h, "shove_prone")])
			opts.append(["Shove → back", func(): _enter_target(h, "shove_push")])
			if adj_foes.any(func(f): return cb.adjacent_to_brazier(f)):
				opts.append(["Shove → brazier", func(): _enter_target(h, "shove_brazier")])
		if "burning_hands" in h.spells and h.slots1 + h.slots2 > 0:
			opts.append(["Burning Hands (aim…)", func(): _enter_cone(h, 1)])
			if h.slots2 > 0:
				opts.append(["Burning Hands ★2 (aim…)", func(): _enter_cone(h, 2)])
		if "sacred_flame" in h.spells and not foes.is_empty():
			opts.append(["Sacred Flame", func(): _enter_target(h, "sacred")])
		if not live_allies.is_empty() and not foes.is_empty():
			opts.append(["Help an ally", func(): _enter_target(h, "help")])
		opts.append(["Dodge", func(): _hero_simple(h, "dodge")])
		opts.append(["Dash (+%d move)" % h.speed, func(): _hero_simple(h, "dash")])

	if not cb.bonus_used:
		if h.second_wind != "" and not h.used_second_wind:
			opts.append(["Second Wind (heal)", func(): _hero_bonus(h, "sw")])
		if "healing_word" in h.spells and h.slots1 + h.slots2 > 0:
			if cb.combatants.any(func(a): return a.team == "party" and a != h and not a.is_dead()):
				opts.append(["Healing Word", func(): _enter_target(h, "heal")])
				if h.slots2 > 0:
					opts.append(["Healing Word ★2", func(): _enter_target(h, "heal2")])
		if h.cunning_action:
			if not h.has("hidden"):
				opts.append(["Hide (bonus)", func(): _hero_bonus(h, "hide")])
			opts.append(["Dash (bonus, +%d)" % h.speed, func(): _hero_bonus(h, "cdash")])

	if cb.move_left > 0:
		opts.append(["Disengage: %s" % ("ON" if _disengage else "off"), func(): _toggle_disengage(h)])

	opts.append(["End turn", _end_turn])
	_set_buttons(opts)
	_board.queue_redraw()

func _toggle_disengage(h) -> void:
	_disengage = not _disengage
	_build_hero_menu(h)

func _enter_cone(h, level: int) -> void:
	_mode = "cone"
	_cone_level = level
	_actor.text = "%s — aim Burning Hands%s: hover a direction, click to cast.  (Esc / right-click cancels)" % [
		h.cname, "  ★2" if level >= 2 else ""]
	_set_buttons([["Cancel", func(): board_cancel()]])
	_board.queue_redraw()

func _enter_target(h, kind: String) -> void:
	_mode = "target"
	_tgt_kind = kind
	_actor.text = "%s — %s: hover a target for the odds, click to apply.  (Esc / right-click cancels)" % [h.cname, _tgt_label(kind)]
	_set_buttons([["Cancel", func(): board_cancel()]])
	_board.queue_redraw()

func _tgt_label(kind: String) -> String:
	match kind:
		"attack": return "Attack"
		"sacred": return "Sacred Flame"
		"shove_prone": return "Shove to prone"
		"shove_push": return "Shove back"
		"shove_brazier": return "Shove into the brazier"
		"heal": return "Healing Word"
		"heal2": return "Healing Word ★2"
		"help": return "Help"
	return kind

# Is `c` a legal target for the pending verb?
func _valid_target(h, c) -> bool:
	match _tgt_kind:
		"attack": return c.team != h.team and c.conscious() and cb.in_reach(h, c)
		"sacred": return c.team != h.team and c.conscious() and Hex.distance(h.pos, c.pos) <= Encounter.RANGE_SPELL_LONG
		"shove_prone", "shove_push": return c.team != h.team and c.conscious() and Hex.distance(h.pos, c.pos) <= 1
		"shove_brazier": return c.team != h.team and c.conscious() and Hex.distance(h.pos, c.pos) <= 1 and cb.adjacent_to_brazier(c)
		"heal", "heal2": return c.team == h.team and c != h and not c.is_dead()
		"help": return c.team == h.team and c != h and c.conscious()
	return false

# The number shown over a valid target while aiming.
func target_readout(h, c) -> String:
	match _tgt_kind:
		"attack": return "%d%%" % int(round(cb.hit_chance(h, c) * 100.0))
		"sacred": return "%d%%" % int(round(cb.save_fail_chance(c, h.save_dc, true) * 100.0))
		"shove_prone", "shove_push", "shove_brazier": return "%d%%" % int(round(cb.shove_chance(h, c) * 100.0))
		"heal": return "revive" if c.is_down() else "≈5 HP"
		"heal2": return "revive" if c.is_down() else "≈8 HP"
		"help": return "advantage"
	return ""

# board callbacks -------------------------------------------------------

func board_hex_clicked(hx: Vector2i) -> void:
	if _busy or cb.is_over():
		return
	var h = cb.current()
	if h.team != "party" or not h.conscious():
		return
	if _mode == "cone":
		var dir = Hex.direction_to(h.pos, hx)
		if dir != Vector2i.ZERO:
			_mode = "idle"
			cb.cast_burning_hands(h, dir, _cone_level)
			_after_hero_action(h)
	elif _mode == "target":
		for c in cb.combatants:
			if c.pos == hx and _valid_target(h, c):
				_apply_target(h, c)
				return
	else:  # idle — default click is Move
		if cb.move_left > 0 and hx != h.pos and cb.move_field(h).has(hx):
			_board.slide_from(h)
			cb.move_to(h, hx, _disengage)
			_after_hero_action(h)

func _apply_target(h, c) -> void:
	_mode = "idle"
	var kind := _tgt_kind
	_tgt_kind = ""
	match kind:
		"attack":
			_board.flash(c.pos)
			cb.resolve_attack(h, c)
		"sacred":
			cb.cast_sacred_flame(h, c)
		"shove_prone":
			cb.act_shove(h, c, "prone")
		"shove_push":
			cb.act_shove(h, c, "push")
		"shove_brazier":
			cb.act_shove(h, c, "brazier")
		"heal":
			cb.cast_healing_word(h, c)
		"heal2":
			cb.cast_healing_word(h, c, 2)
		"help":
			cb.act_help(h, c)
	_after_hero_action(h)

func board_hex_hovered(hx: Vector2i) -> void:
	_hover_hex = hx
	if _mode == "cone" or _mode == "target":
		_board.queue_redraw()

func board_cancel() -> void:
	if _mode != "idle" and cb and not cb.is_over() and cb.current().team == "party":
		_build_hero_menu(cb.current())

# hero actions ---------------------------------------------------------

func _hero_simple(h, kind) -> void:
	if kind == "dodge":
		cb.act_dodge(h)
	elif kind == "dash":
		cb.action_used = true
		cb.move_left += h.speed
	_after_hero_action(h)

func _hero_bonus(h, kind) -> void:
	if kind == "sw":
		cb.act_second_wind(h)
	elif kind == "hide":
		cb.act_hide(h)
	elif kind == "cdash":
		cb.act_cunning_dash(h)
	_after_hero_action(h)

func _after_hero_action(h) -> void:
	_flush_log()
	_refresh()
	if cb.is_over():
		_finish()
		return
	if cb.action_used and cb.bonus_used and cb.move_left == 0:
		_end_turn()
	else:
		_build_hero_menu(h)

# --- rendering --------------------------------------------------------

func _set_buttons(opts: Array) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var count := opts.size()
	for i in count:
		var b := Button.new()
		if count == 1:
			b.text = "[Esc] %s" % opts[i][0]
		elif i == count - 1:
			b.text = "[0] %s" % opts[i][0]
		elif i < 9:
			b.text = "[%d] %s" % [i + 1, opts[i][0]]
		else:
			b.text = opts[i][0]
		b.pressed.connect(opts[i][1])
		_buttons.add_child(b)
	_apply_ui_scale()

func _refresh() -> void:
	_header.text = "THE SUNKEN SHRINE   ·   Round %d   ·   seed %d" % [cb.round_num, _seed]

	var parts: Array = []
	for c in cb.order:
		var nm = c.cname.split(" ")[0]
		var col = "#8fdc97" if c.team == "party" else "#e58a84"
		if c == cb.current():
			nm = "▶ " + nm
			col = "#ffe27a"
		if c.is_dead():
			nm = "[s]%s[/s]" % nm
		parts.append("[color=%s]%s(%d)[/color]" % [col, nm, c.init_roll])
	_order.text = "[b]ORDER[/b]  " + "   ".join(parts) + "     [color=#5a6070]· 1-9 actions · scroll/± zoom · drag/arrows pan · Home reset ·[/color]"

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious() and _mode == "idle":
		var hint := "  ·  click a blue tile to move" if cb.move_left > 0 else ""
		_actor.text = "%s  ·  AC %d  ·  HP %d/%d  ·  slots %d/%d  ·  %s%smove %d%s" % [
			cur.cname, cb.effective_ac(cur), cur.hp, cur.max_hp, cur.slots1, cur.slots2,
			"" if cb.action_used else "[action] ",
			"" if cb.bonus_used else "[bonus] ",
			cb.move_left, hint,
		]
	elif _mode == "idle":
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	_board.queue_redraw()

var _logged = 0

func _flush_log() -> void:
	while _logged < cb.log.size():
		var line: String = cb.log[_logged]
		var col := "#e9e9df"
		var bold := false
		if "CRIT" in line:
			col = "#ff6a4a"; bold = true
		elif "is dead" in line or "has died" in line:
			col = "#ff8866"; bold = true
		elif "revives" in line or "nat 20" in line:
			col = "#8dffb0"; bold = true
		elif "falls unconscious" in line:
			col = "#ffab5c"
		elif "misses" in line or "turned aside" in line:
			col = "#7f7f79"
		elif " hits " in line or " CRITS " in line:
			col = "#ffe0a0"
		elif "casts" in line or "calls" in line or "Second Wind" in line or "healed" in line:
			col = "#9fd0ff"
		elif "Initiative:" in line:
			col = "#c8a75a"
		var body := "[b]%s[/b]" % line if bold else line
		_logbox.append_text("[color=%s]%s[/color]\n" % [col, body])
		_logged += 1

func _finish() -> void:
	var res: String = cb.outcome()
	_flush_log()
	_refresh()
	_set_buttons([["New encounter", _new_game]])
	_actor.text = "  ***  %s  in %d rounds  ***  " % [res.to_upper(), cb.round_num]
	_logbox.append_text("\n[b][color=%s]%s in %d rounds.[/color][/b]\n" % [
		"#7dff9d" if res == "Victory" else "#ff5a4a", res, cb.round_num,
	])

func _process(dt: float) -> void:
	if _board:
		_board.tick(dt * _anim)

# =====================================================================
#  Board — the hex map. Draws tiles, tokens, HP bars, highlights, juice.
# =====================================================================
class Board extends Control:
	var main
	var cb
	var _origin := Vector2.ZERO
	var _tok := {}        # id -> displayed pixel pos (for slide)
	var _hp := {}         # id -> displayed hp value
	var _floats: Array = []   # {pos: Vector2, text, color, age}
	var _flash := {}     # id -> ttl
	var _hover := Vector2i(999, 999)

	func reset(_cb) -> void:
		cb = _cb
		_tok.clear(); _hp.clear(); _floats.clear(); _flash.clear()
		for c in cb.combatants:
			_tok[c.id] = _pix(c.pos)
			_hp[c.id] = float(c.hp)
		queue_redraw()

	func slide_from(c) -> void:
		if not _tok.has(c.id):
			_tok[c.id] = _pix(c.pos)

	func flash(_hx: Vector2i) -> void:
		pass  # target flash handled per-token on hp change

	func _layout() -> void:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for hx in cb.board["hexes"]:
			var p := Hex.to_pixel(hx, main.hex_px)
			mn = mn.min(p); mx = mx.max(p)
		var span := mx - mn
		_origin = (size - span) * 0.5 - mn + main._pan

	func _pix(hx: Vector2i) -> Vector2:
		return _origin + Hex.to_pixel(hx, main.hex_px)

	func _hex_poly(center: Vector2, s: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i)
			pts.append(center + Vector2(cos(a), sin(a)) * s)
		return pts

	func tick(dt: float) -> void:
		if cb == null:
			return
		var k := clampf(dt * 12.0, 0.0, 1.0)
		var dirty := false
		for c in cb.combatants:
			var target := _pix(c.pos)
			var cur: Vector2 = _tok.get(c.id, target)
			if cur.distance_to(target) > 0.5:
				_tok[c.id] = cur.lerp(target, k); dirty = true
			else:
				_tok[c.id] = target
			var hv: float = _hp.get(c.id, float(c.hp))
			if absf(hv - c.hp) > 0.15:
				if hv > c.hp:
					_spawn_float(c, hv - c.hp)
					_flash[c.id] = 0.35
				_hp[c.id] = lerpf(hv, float(c.hp), k); dirty = true
			else:
				_hp[c.id] = float(c.hp)
		for f in _floats:
			f.age += dt; dirty = true
		_floats = _floats.filter(func(f): return f.age < 1.1)
		for id in _flash.keys():
			_flash[id] -= dt
			if _flash[id] <= 0.0:
				_flash.erase(id)
			dirty = true
		if dirty:
			queue_redraw()

	func _spawn_float(c, amount: float) -> void:
		var band := Color("ffd24a")
		if amount >= 12: band = Color("ff5a4a")
		elif amount >= 6: band = Color("ff9146")
		_floats.append({"pos": _pix(c.pos), "text": "-%d" % int(round(amount)), "color": band, "age": 0.0})

	func _gui_input(e: InputEvent) -> void:
		if cb == null:
			return
		if e is InputEventMouseMotion:
			if e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
				main.pan_by(e.relative)
				return
			var hx := Hex.from_pixel(e.position - _origin, main.hex_px)
			if hx != _hover:
				_hover = hx
				main.board_hex_hovered(hx)
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				main.set_zoom(main._zoom * 1.1)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				main.set_zoom(main._zoom / 1.1)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				main.board_cancel()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				main.board_hex_clicked(Hex.from_pixel(e.position - _origin, main.hex_px))

	func _draw() -> void:
		if cb == null:
			return
		_layout()
		var s: float = main.hex_px
		var fz := clampf(main._zoom, 0.75, 1.7)   # font scale, gentler than the hex scale
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0)

		var field := {}
		var provoke := {}
		var cone_hexes := {}
		var cur = cb.current()
		var hero_turn: bool = cur and cur.team == "party" and cur.conscious()
		if hero_turn and main._mode == "idle" and cb.move_left > 0:
			field = cb.move_field(cur)
			for hx in field:
				if not cb.provokers_for(cur, hx).is_empty():
					provoke[hx] = true
		if hero_turn and main._mode == "cone":
			var dir := Hex.direction_to(cur.pos, _hover)
			if dir != Vector2i.ZERO:
				for hx in Hex.cone(cur.pos, dir, Encounter.CONE_BURNING_HANDS):
					cone_hexes[hx] = true

		# tiles
		for hx in cb.board["hexes"]:
			var c := _origin + Hex.to_pixel(hx, s)
			var poly := _hex_poly(c, s - 2.0)
			var fill: Color = main.COL_HEX
			if hx == cb.board["brazier"]:
				fill = main.COL_BRAZIER.lerp(Color("d9622e"), pulse)
			elif cb.is_cover(hx):
				fill = main.COL_COVER
			draw_colored_polygon(poly, fill)
			if field.has(hx) and hx != cur.pos:
				draw_colored_polygon(poly, main.COL_MOVE)
			if cone_hexes.has(hx):
				draw_colored_polygon(poly, main.COL_CONE)
			var edge := _hex_poly(c, s - 2.0)
			edge.append(edge[0])
			draw_polyline(edge, main.COL_HEX_EDGE, 1.5)
			if provoke.has(hx):
				draw_string(ThemeDB.fallback_font, c - Vector2(6, -5), "⚠", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffcf47"))
			if cb.is_cover(hx):
				draw_string(ThemeDB.fallback_font, c - Vector2(s - 6, -s + 12), "cover", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("7fa6a6"))

		# targeting overlay — outline valid targets, float their odds, hovered one brighter
		if hero_turn and main._mode == "target":
			for c in cb.combatants:
				if not main._valid_target(cur, c):
					continue
				var tp := _origin + Hex.to_pixel(c.pos, s)
				var hot: bool = c.pos == _hover
				var poly := _hex_poly(tp, s - 3.0)
				poly.append(poly[0])
				var oc: Color = main.COL_TARGET
				draw_polyline(poly, oc if hot else Color(oc.r, oc.g, oc.b, 0.45), 3.0 if hot else 2.0)
				var txt: String = main.target_readout(cur, c)
				var fs := int((20 if hot else 15) * fz)
				var w := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var chip := tp + Vector2(-w / 2.0, -s - 4.0)
				draw_rect(Rect2(chip - Vector2(5, fs), Vector2(w + 10, fs + 8)), Color(0, 0, 0, 0.72))
				draw_string(ThemeDB.fallback_font, chip, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color("ffe27a") if hot else Color("d7d7cf"))
		elif hero_turn and main._mode == "idle" and not cb.action_used:
			for f in cb.enemies_of(cur):
				if cb.in_reach(cur, f):
					var poly := _hex_poly(_origin + Hex.to_pixel(f.pos, s), s - 3.0)
					poly.append(poly[0])
					draw_polyline(poly, Color(main.COL_TARGET.r, main.COL_TARGET.g, main.COL_TARGET.b, 0.30), 1.5)

		# tokens
		for c in cb.combatants:
			if c.is_dead():
				continue
			var p: Vector2 = _tok.get(c.id, _pix(c.pos))
			var base: Color = main.COL_PARTY if c.team == "party" else main.COL_FOE
			if c.is_down():
				base = Color("6a6a6a")
			if _flash.has(c.id):
				base = base.lerp(Color.WHITE, clampf(_flash[c.id] / 0.35, 0, 1))
			var rad := s * 0.62
			if c == cur:
				draw_arc(p, rad + 4.0, 0, TAU, 32, Color("ffe27a"), 2.0 + pulse * 1.5)
			draw_circle(p, rad, base)
			draw_arc(p, rad, 0, TAU, 24, base.darkened(0.4), 2.0)
			var initials: String = _initials(c.cname)
			draw_string(ThemeDB.fallback_font, p - Vector2(rad * 0.55, -5 * fz), initials,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * fz), Color("101216"))
			var glyph := _glyph(c)
			if glyph != "":
				draw_string(ThemeDB.fallback_font, p + Vector2(rad * 0.1, -rad * 0.65), glyph,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * fz), Color("101216"))

			# hp bar
			var hv: float = _hp.get(c.id, float(c.hp))
			var bw := s * 1.2
			var br := Rect2(p.x - bw / 2.0, p.y + rad + 3.0, bw, 6.0)
			draw_rect(br, Color("0c0d11"))
			var frac := clampf(hv / float(c.max_hp), 0.0, 1.0)
			var hpcol := Color("5fbf6a")
			if frac < 0.33: hpcol = Color("d15750")
			elif frac < 0.66: hpcol = Color("d9a441")
			draw_rect(Rect2(br.position, Vector2(br.size.x * frac, br.size.y)), hpcol)
			draw_string(ThemeDB.fallback_font, br.position + Vector2(0, 12 + 8 * fz),
				"%d/%d" % [c.hp, c.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * fz), Color("c9ccd6"))

			var tags := ""
			if c.has("prone"): tags += "↓"
			if c.has("hidden"): tags += "👁"
			if c.is_down(): tags += " ✗%d/%d" % [c.death_s, c.death_f]
			if tags != "":
				draw_string(ThemeDB.fallback_font, p + Vector2(-rad, -rad - 4), tags,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * fz), Color("e6c15a"))

		# floating damage
		for f in _floats:
			var col: Color = f.color
			col.a = 1.0 - f.age / 1.1
			draw_string(ThemeDB.fallback_font, f.pos + Vector2(-8, -(20.0 + f.age * 34.0)), f.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)

	func _initials(nm: String) -> String:
		var w := nm.split(" ", false)
		if w.size() >= 2:
			return (w[0][0] + w[1][0]).to_upper()
		return nm.substr(0, 2).to_upper()

	func _glyph(c) -> String:
		match c.id:
			"vera", "grull": return "⚔"
			"pike", "kritch": return "➶"
			"ilsa": return "✦"
			_: return ""
