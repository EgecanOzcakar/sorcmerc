# Playable UI for The Sunken Shrine — hex board, drawn tokens, styled buttons.
# All rules live in core/. Built programmatically so it needs no editor work.
extends Control

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")

const HEX_SIZE := 34.0
const FAST := false  # set by _ready from SORCMERC_FAST

var cb
var _seed: int = 0
var _busy = false
var _advancing = false
var _disengage = false
var _mode := "idle"          # idle | move | cone
var _anim := 1.0             # animation speed multiplier (huge when FAST)

@onready var _header := Label.new()
@onready var _order := RichTextLabel.new()
@onready var _board := Board.new()
@onready var _actor := Label.new()
@onready var _buttons := HFlowContainer.new()
@onready var _logbox := RichTextLabel.new()

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

	_order.bbcode_enabled = true
	_order.fit_content = true
	_order.scroll_active = false
	_order.custom_minimum_size = Vector2(0, 26)
	root.add_child(_order)

	_board.main = self
	_board.clip_contents = true
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 300)
	root.add_child(_board)

	_actor.add_theme_font_size_override("font_size", 16)
	root.add_child(_actor)

	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	root.add_child(_buttons)

	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	_logbox.custom_minimum_size = Vector2(0, 150)
	_logbox.add_theme_color_override("default_color", Color(0.85, 0.85, 0.8))
	root.add_child(_logbox)

	set_process(true)
	_new_game()

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

func _build_hero_menu(h) -> void:
	var opts: Array = []
	var foes: Array = cb.enemies_of(h)

	if not cb.action_used:
		for f in foes:
			if cb.in_reach(h, f):
				var pct = int(round(cb.hit_chance(h, f) * 100.0))
				opts.append(["Attack %s  (%d%%)" % [f.cname.split(" ")[0], pct], func(): _hero_attack(h, f)])
		if h.athletics > 0:
			for f in foes:
				if Hex.distance(f.pos, h.pos) <= 1:
					opts.append(["Shove %s → prone" % f.cname.split(" ")[0], func(): _hero_shove(h, f, "prone")])
					opts.append(["Shove %s → back" % f.cname.split(" ")[0], func(): _hero_shove(h, f, "push")])
					if cb.adjacent_to_brazier(f):
						opts.append(["Shove %s → brazier 🔥" % f.cname.split(" ")[0], func(): _hero_shove(h, f, "brazier")])
		if "burning_hands" in h.spells and h.slots1 + h.slots2 > 0:
			opts.append(["Burning Hands (aim…)", func(): _enter_cone(h)])
		if "sacred_flame" in h.spells:
			for f in foes:
				opts.append(["Sacred Flame %s" % f.cname.split(" ")[0], func(): _hero_cast_target(h, f, "sf")])
		opts.append(["Dodge", func(): _hero_simple(h, "dodge")])
		opts.append(["Dash (+%d move)" % h.speed, func(): _hero_simple(h, "dash")])

	if not cb.bonus_used:
		if h.second_wind != "" and not h.used_second_wind:
			opts.append(["Second Wind (heal)", func(): _hero_bonus(h, "sw")])
		if "healing_word" in h.spells and h.slots1 + h.slots2 > 0:
			for a in cb.combatants:
				if a.team == "party" and a != h and not a.is_dead():
					opts.append(["Healing Word → %s" % a.cname.split(" ")[0], func(): _hero_heal(h, a)])

	if cb.move_left > 0:
		var verb = "Moving… (click a tile)" if _mode == "move" else "Move (%d)" % cb.move_left
		opts.append([verb, func(): _toggle_move(h)])
		opts.append(["Disengage: %s" % ("ON" if _disengage else "off"), func(): _toggle_disengage(h)])

	opts.append(["— End turn —", _end_turn])
	_set_buttons(opts)

func _toggle_move(h) -> void:
	_mode = "idle" if _mode == "move" else "move"
	_build_hero_menu(h)
	_board.queue_redraw()

func _toggle_disengage(h) -> void:
	_disengage = not _disengage
	_build_hero_menu(h)

func _enter_cone(h) -> void:
	_mode = "cone"
	_actor.text = "%s — aim Burning Hands: hover a direction, click to cast.  (right-click cancels)" % h.cname
	_set_buttons([["Cancel", func(): _cancel_cone(h)]])
	_board.queue_redraw()

func _cancel_cone(h) -> void:
	_mode = "idle"
	_build_hero_menu(h)
	_board.queue_redraw()

# board callbacks -------------------------------------------------------

func board_hex_clicked(hx: Vector2i) -> void:
	if _busy or cb.is_over():
		return
	var h = cb.current()
	if h.team != "party" or not h.conscious():
		return
	if _mode == "move":
		if cb.move_field(h).has(hx) and hx != h.pos:
			_board.slide_from(h)
			cb.move_to(h, hx, _disengage)
			_mode = "idle" if cb.move_left == 0 else "move"
			_after_hero_action(h)
	elif _mode == "cone":
		var dir = Hex.direction_to(h.pos, hx)
		if dir != Vector2i.ZERO:
			cb.cast_burning_hands(h, dir)
			_mode = "idle"
			_after_hero_action(h)
	elif _mode == "idle" and not cb.action_used:
		for f in cb.enemies_of(h):
			if f.pos == hx and cb.in_reach(h, f):
				_hero_attack(h, f)
				return

func board_hex_hovered(_hx: Vector2i) -> void:
	if _mode == "cone":
		_board.queue_redraw()

func board_cancel() -> void:
	if _mode != "idle":
		_mode = "idle"
		if cb and cb.current().team == "party":
			_build_hero_menu(cb.current())
		_board.queue_redraw()

# hero actions ---------------------------------------------------------

func _hero_attack(h, f) -> void:
	_board.flash(f.pos)
	cb.resolve_attack(h, f)
	_after_hero_action(h)

func _hero_shove(h, f, mode) -> void:
	cb.act_shove(h, f, mode)
	_after_hero_action(h)

func _hero_cast_target(h, f, _which) -> void:
	cb.cast_sacred_flame(h, f)
	_after_hero_action(h)

func _hero_simple(h, kind) -> void:
	if kind == "dodge":
		cb.act_dodge(h)
	elif kind == "dash":
		cb.action_used = true
		cb.move_left += h.speed
		_mode = "move"
	_after_hero_action(h)

func _hero_bonus(h, kind) -> void:
	if kind == "sw":
		cb.act_second_wind(h)
	_after_hero_action(h)

func _hero_heal(h, a) -> void:
	cb.cast_healing_word(h, a)
	_after_hero_action(h)

func _after_hero_action(h) -> void:
	_flush_log()
	_refresh()
	if cb.is_over():
		_finish()
		return
	if cb.action_used and cb.bonus_used and cb.move_left == 0:
		_end_turn()
	elif _mode == "cone":
		pass
	else:
		_build_hero_menu(h)

# --- rendering --------------------------------------------------------

func _set_buttons(opts: Array) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	for o in opts:
		var b := Button.new()
		b.text = o[0]
		b.pressed.connect(o[1])
		_buttons.add_child(b)

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
	_order.text = "[b]ORDER[/b]  " + "   ".join(parts)

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious() and _mode != "cone":
		_actor.text = "%s  ·  AC %d  ·  HP %d/%d  ·  slots %d/%d  ·  %s%smove %d" % [
			cur.cname, cb.effective_ac(cur), cur.hp, cur.max_hp, cur.slots1, cur.slots2,
			"" if cb.action_used else "[action] ",
			"" if cb.bonus_used else "[bonus] ",
			cb.move_left,
		]
	elif _mode != "cone":
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	_board.queue_redraw()

var _logged = 0

func _flush_log() -> void:
	while _logged < cb.log.size():
		var line: String = cb.log[_logged]
		var col = "#d8d8d0"
		if "CRIT" in line: col = "#ff5a4a"
		elif "is dead" in line or "has died" in line: col = "#ff8866"
		elif "revives" in line or "nat 20" in line: col = "#7dff9d"
		elif "misses" in line or "turned aside" in line: col = "#8a8a84"
		_logbox.append_text("[color=%s]%s[/color]\n" % [col, line])
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
			var p := Hex.to_pixel(hx, main.HEX_SIZE)
			mn = mn.min(p); mx = mx.max(p)
		var span := mx - mn
		_origin = (size - span) * 0.5 - mn

	func _pix(hx: Vector2i) -> Vector2:
		return _origin + Hex.to_pixel(hx, main.HEX_SIZE)

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
			var hx := Hex.from_pixel(e.position - _origin, main.HEX_SIZE)
			if hx != _hover:
				_hover = hx
				main.board_hex_hovered(hx)
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT:
				main.board_cancel()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				main.board_hex_clicked(Hex.from_pixel(e.position - _origin, main.HEX_SIZE))

	func _draw() -> void:
		if cb == null:
			return
		_layout()
		var s: float = main.HEX_SIZE
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0)

		var field := {}
		var provoke := {}
		var cone_hexes := {}
		var cur = cb.current()
		var hero_turn: bool = cur and cur.team == "party" and cur.conscious()
		if hero_turn and main._mode == "move":
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

		# targetable outlines
		if hero_turn and main._mode == "idle" and not cb.action_used:
			for f in cb.enemies_of(cur):
				if cb.in_reach(cur, f):
					var poly := _hex_poly(_origin + Hex.to_pixel(f.pos, s), s - 3.0)
					poly.append(poly[0])
					draw_polyline(poly, main.COL_TARGET, 2.0)

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
			draw_string(ThemeDB.fallback_font, p - Vector2(rad * 0.55, -5), initials,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("101216"))
			var glyph := _glyph(c)
			if glyph != "":
				draw_string(ThemeDB.fallback_font, p + Vector2(rad * 0.1, -rad * 0.65), glyph,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("101216"))

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
			draw_string(ThemeDB.fallback_font, br.position + Vector2(0, 20),
				"%d/%d" % [c.hp, c.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c9ccd6"))

			var tags := ""
			if c.has("prone"): tags += "↓"
			if c.has("hidden"): tags += "👁"
			if c.is_down(): tags += " ✗%d/%d" % [c.death_s, c.death_f]
			if tags != "":
				draw_string(ThemeDB.fallback_font, p + Vector2(-rad, -rad - 4), tags,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e6c15a"))

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
