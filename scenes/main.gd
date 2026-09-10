# Playable UI for The Sunken Shrine — hex board, drawn tokens, styled buttons.
# All rules live in core/. Built programmatically so it needs no editor work.
extends Control

const AI = preload("res://core/ai.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Hex = preload("res://core/hex.gd")
const Settings = preload("res://core/settings.gd")
const Icons = preload("res://core/ui_icons.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")

# What T5 injects before the scene runs: the live party, the node's spec (empty ->
# the scaler sizes one) and its difficulty. `result` is resolve_outcome() once the
# fight is over — deaths / xp / gold / loot for the campaign layer.
var party                       # core/party.gd; a Presets demo party when null
var spec: Dictionary = {}
var difficulty := "normal"
var result: Dictionary = {}
var _own_party := false

const HEX_BASE := 34.0
const REVEAL_PAUSE := 0.75  # beat to read the attack roll (0 under SORCMERC_FAST)
var _zoom := 1.0
var _pan := Vector2.ZERO
var hex_px: float:
	get: return HEX_BASE * _zoom
const FAST := false  # set by _ready from SORCMERC_FAST

var cb
var _seed: int = 0
var _busy = false
var _advancing = false
var _mode := "idle"          # idle | cone | target
var _tgt_verb: Dictionary = {}   # the verb being aimed, straight from cb.available()
var _armed := ""             # a confirm-guarded verb waiting for its second press
var _hover_hex := Vector2i(999, 999)
var _anim := 1.0             # animation speed multiplier (huge when FAST)

@onready var _header := Label.new()
@onready var _order := RichTextLabel.new()
@onready var _board := Board.new()
@onready var _actor := Label.new()
@onready var _buttons := HFlowContainer.new()
@onready var _logbox := RichTextLabel.new()
@onready var _cap := Label.new()
@onready var _logwrap := PanelContainer.new()

# --- palette (core/ui_icons.gd is the source; board-only tints stay here) ---
const COL_BG := Icons.COL_BG
const COL_HEX := Color("232733")
const COL_HEX_EDGE := Color("39404f")
const COL_BRAZIER := Color("6b2f1c")
const COL_COVER := Color("2a3a3a")
const COL_PROP := Color("4a3826")       # barrels, crates, fountains
const COL_TORCH := Color("ffd98a")
# T11: per-theme floor tint, palette only — no mechanical difference.
const PALETTES := {"shrine": COL_HEX, "camp": Color("2a2a26"), "city": Color("2c2c33"),
	"forest": Color("1f2a22"), "ice": Color("222c36"), "shop": Color("2b2620")}
const COL_MOVE := Color(0.30, 0.55, 0.95, 0.35)
const COL_TARGET := Color(0.95, 0.35, 0.30, 0.9)
const COL_CONE := Color(0.98, 0.55, 0.15, 0.30)
const COL_GOLD_EDGE := Icons.COL_GOLD_EDGE
const COL_HEAD := Icons.COL_HEAD
const COL_BODY := Icons.COL_BODY
const COL_ACCENT := Icons.COL_ACCENT
const COL_PARTY := Icons.COL_PARTY
const COL_FOE := Icons.COL_FOE

func _ready() -> void:
	_anim = Settings.anim()   # the in-game setting, or SORCMERC_FAST when set
	if spec.is_empty():       # standalone: no campaign node dictating difficulty
		difficulty = Settings.current().default_difficulty
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
	# move_child(bg, 0) below is enough to keep it behind this scene's own
	# content (earlier siblings draw first/behind). A negative z_index isn't
	# scoped to local siblings — it's global across the canvas layer — so it
	# was pushing this "opaque background" behind whatever scene is UNDER this
	# one too (the campaign screen, when combat is shown as an overlay),
	# letting that screen's own log text bleed through wherever the combat UI
	# has empty space instead of being properly blacked out.
	add_child(bg)
	move_child(bg, 0)

	_header.add_theme_font_size_override("font_size", Icons.FS_TITLE)
	_header.add_theme_color_override("font_color", Icons.COL_HEAD)
	root.add_child(_header)

	# --- the action log: big, centred, shiny --------------------------
	_logwrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var logwrap := _logwrap
	logwrap.custom_minimum_size = Vector2(min(820.0, size.x * 0.72), 210)
	var glow := StyleBoxFlat.new()
	glow.bg_color = Icons.COL_INK
	glow.set_corner_radius_all(14)
	glow.set_border_width_all(2)
	glow.border_color = Icons.COL_GOLD_EDGE
	glow.shadow_color = Color(0.95, 0.78, 0.42, 0.22)
	glow.shadow_size = 16
	glow.set_content_margin_all(16)
	logwrap.add_theme_stylebox_override("panel", glow)
	var logcol := VBoxContainer.new()
	logcol.add_theme_constant_override("separation", 4)
	logwrap.add_child(logcol)
	_cap.text = "»   A C T I O N   L O G   «"
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.add_theme_color_override("font_color", Icons.COL_GOLD)
	logcol.add_child(_cap)
	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	_logbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_logbox.add_theme_font_size_override("normal_font_size", 18)
	_logbox.add_theme_font_size_override("bold_font_size", 18)
	_logbox.add_theme_color_override("default_color", Icons.COL_TEXT)
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

	_actor.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	_actor.add_theme_color_override("font_color", Icons.COL_BODY)
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
	_header.add_theme_font_size_override("font_size", int(Icons.FS_TITLE * u))
	_actor.add_theme_font_size_override("font_size", int(Icons.FS_HEAD * u))
	_cap.add_theme_font_size_override("font_size", int(Icons.FS_CAPTION * u))
	_order.add_theme_font_size_override("normal_font_size", int(Icons.FS_BODY * u))
	_order.add_theme_font_size_override("bold_font_size", int(Icons.FS_BODY * u))
	_logbox.add_theme_font_size_override("normal_font_size", int(Icons.FS_HEAD * u))
	_logbox.add_theme_font_size_override("bold_font_size", int(Icons.FS_HEAD * u))
	for b in _buttons.get_children():
		b.add_theme_font_size_override("font_size", int(Icons.FS_BODY * u))

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
		KEY_R: if cb and cb.is_over(): _new_game()
		KEY_F1: SettingsOverlay.toggle(self, func(): _anim = Settings.anim())
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
	if b is Button and not b.disabled:
		b.pressed.emit()

func _build_theme() -> void:
	theme = Icons.dark_theme()

func _new_game(forced := 0) -> void:
	var env := OS.get_environment("SORCMERC_SEED")
	if forced > 0:
		_seed = forced
	else:
		_seed = int(env) if env != "" else (int(Time.get_unix_time_from_system()) & 0xFFFFFF)
	if _own_party:
		party = null    # a demo party is rebuilt per fight, so replays start fresh
	if party == null:   # standalone: the three presets
		_own_party = true
		party = Party.new()
		for ch in Presets.party():
			party.add_member(ch)
	var chars: Array = party.party_characters()
	var sp: Dictionary = (spec if not spec.is_empty() else Scaler.roster_for(chars, difficulty)).duplicate(true)
	sp["seed"] = _seed
	result = {}
	cb = Encounter.build(sp, party.to_combatants(Encounter.PARTY_STARTS))   # sp["theme"] picks the board
	_logbox.text = ""
	_logged = 0
	_last_round = 1
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
# Everything on it comes from cb.available(h) — no hero, class or spell is named here.
# Verbs that need a target enter "target" mode — hover a token for its %, click to apply.
func _build_hero_menu(h, keep_armed := false) -> void:
	if not keep_armed:
		_armed = ""
	_mode = "idle"
	_tgt_verb = {}
	var opts: Array = []
	for v in cb.available(h):
		var label: String = _verb_label(h, v)
		var tip: String = _verb_tooltip(v)
		match v.get("targeting", "self"):
			"enemy", "ally":
				opts.append([label + "…", func(): _enter_target(h, v), tip])
			"direction":
				opts.append([label + " (aim…)", func(): _enter_cone(h, v), tip])
			_:
				if _costly(v):
					var opt := _confirm_opt(h, v["id"], label, func(): cb.perform(h, v); _after_hero_action(h))
					opt.append(tip)
					opts.append(opt)
				else:
					var fn := func(): cb.perform(h, v); _after_hero_action(h)
					opts.append([label, fn, tip])

	if h.econ["action"] > 0 and not cb.is_over():
		opts.append(_confirm_opt(h, "end", "End turn (action unspent!)", _end_turn))
	else:
		opts.append(["End turn", _end_turn])
	_set_buttons(opts)
	_board.queue_redraw()

# The cost tag is what tells a bonus-action Dash from the Attack-action one.
func _verb_label(h, v: Dictionary) -> String:
	var label: String = v["label"]
	if v["kind"] == "dash":
		label += " (+%d move)" % h.speed
	if v.get("cost", "action") != "action":
		label += " [%s]" % v["cost"]
	if v.has("pool"):
		label += " %d/%d" % [h.pool_left(v["pool"]), int(h.pools[v["pool"]]["max"])]
	return label

# Hover text for an action button. A spell gets its real SRD description
# (data/spells.json — class features carry no prose at all, SCHEMA gap #4, so
# there's nothing to quote for them); everything else gets a short line
# synthesized from the verb's own resolved numbers — cheap, and honest about
# only describing what's actually there instead of needing hand-authored
# blurbs for ~30 features before this could ship at all.
const KIND_BLURB := {
	"dodge": "Until your next turn, attacks against you have disadvantage and you have advantage on DEX saves.",
	"dash": "Gain extra movement equal to your speed.",
	"disengage": "Your movement doesn't provoke opportunity attacks this turn.",
	"hide": "Make a Stealth check to become hidden from enemies who can't see you.",
	"help": "Grant an ally advantage on their next check or attack roll.",
	"shove": "Contested Athletics check: knock the target prone or push it back.",
	"smash": "Destroy a barrel or crate within reach.",
}

func _verb_tooltip(v: Dictionary) -> String:
	if v.has("spell"):
		var desc := String(Catalog.spell(v["spell"]).get("description", ""))
		return desc if desc != "" else KIND_BLURB.get(v["kind"], "")
	if KIND_BLURB.has(v["kind"]):
		return KIND_BLURB[v["kind"]]
	var bits: Array = []
	if v.has("dice_count") and v.has("dice_sides"):
		var bonus: int = int(v.get("dice_bonus", v.get("bonus_damage", 0)))
		bits.append("%dd%d%s %s" % [int(v["dice_count"]), int(v["dice_sides"]),
			("+%d" % bonus) if bonus > 0 else "", v.get("damage_type", "damage")])
	if v.has("heal_count"):
		var hb: int = int(v.get("heal_bonus", 0))
		bits.append("Heal %dd%d%s" % [int(v["heal_count"]), int(v.get("heal_sides", 8)),
			("+%d" % hb) if hb > 0 else ""])
	if v.has("save"):
		bits.append("DC %d %s save" % [int(v.get("save_dc", 0)), String(v["save"]).to_upper()])
	if not v.get("conditions", []).is_empty():
		bits.append("Inflicts: %s" % ", ".join(v["conditions"]))
	if v.has("amount") and not v.has("dice_count"):
		bits.append(str(int(v["amount"])))
	if not v.get("resist", []).is_empty():
		bits.append("Resist: %s" % ", ".join(v["resist"]))
	return ". ".join(bits)

# Two-press confirm on anything that burns a limited resource, plus the two
# turn-enders that are easy to misclick.
func _costly(v: Dictionary) -> bool:
	return v.has("pool") or int(v.get("slot_level", 0)) > 0 or v["kind"] in ["dodge", "dash"]

# A two-press guard: first press arms and relabels, second press fires.
func _confirm_opt(h, key: String, label: String, fn: Callable) -> Array:
	if _armed == key:
		return ["✓ Confirm: %s" % label, func(): _armed = ""; fn.call()]
	return [label, func(): _armed = key; _build_hero_menu(h, true)]

func _enter_cone(h, v: Dictionary) -> void:
	_mode = "cone"
	_tgt_verb = v
	_actor.text = "%s — aim %s: hover a direction, click to cast.  (Esc / right-click cancels)" % [
		h.cname, v["label"]]
	_set_buttons([["Cancel", func(): board_cancel()]])
	_board.queue_redraw()

func _enter_target(h, v: Dictionary) -> void:
	_mode = "target"
	_tgt_verb = v
	_actor.text = "%s — %s: hover a target for the odds, click to apply.  (Esc / right-click cancels)" % [
		h.cname, v["label"]]
	_set_buttons([["Cancel", func(): board_cancel()]])
	_board.queue_redraw()

# Is `c` a legal target for the pending verb?
func _valid_target(h, c) -> bool:
	return not _tgt_verb.is_empty() and cb.legal_target(h, _tgt_verb, c)

# The number shown over a valid target while aiming.
func target_readout(h, c) -> String:
	var v := _tgt_verb
	match v["kind"]:
		"attack": return "%d%%" % int(round(cb.hit_chance(h, c) * 100.0))
		"shove": return "%d%%" % int(round(cb.shove_chance(h, c) * 100.0))
		"help": return "advantage"
	if v.has("heal_count") or v["kind"] in ["heal_self", "heal_ally"]:
		if c.is_down():
			return "revive"
		var n := int(v.get("heal_count", v.get("dice_count", 1)))
		var s := int(v.get("heal_sides", v.get("dice_sides", 8)))
		return "≈%d HP" % int(n * (s + 1) / 2.0 + int(v.get("heal_bonus", v.get("dice_bonus", 0))))
	if v.get("save", "") != "":
		return "%d%%" % int(round(cb.save_fail_chance(c, int(v.get("save_dc", h.save_dc)),
			v["save"], v.get("ignores_cover", false)) * 100.0))
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
			var v := _tgt_verb
			_tgt_verb = {}
			cb.perform(h, v, dir)
			_after_hero_action(h)
	elif _mode == "target":
		for c in cb.combatants:
			if c.pos == hx and _valid_target(h, c):
				_apply_target(h, c)
				return
	else:  # idle — default click is Move
		if h.econ["move_left"] > 0 and hx != h.pos and cb.move_field(h).has(hx):
			_board.slide_from(h)
			cb.move_to(h, hx)
			_after_hero_action(h)

func _apply_target(h, c) -> void:
	_mode = "idle"
	var v := _tgt_verb
	_tgt_verb = {}
	var res = cb.perform(h, v, c)
	if v["kind"] == "attack" and typeof(res) == TYPE_DICTIONARY and not res.has("error"):
		_busy = true
		_board.show_reveal(c.id, res)
		await get_tree().create_timer(REVEAL_PAUSE / _anim).timeout
		_busy = false
	_after_hero_action(h)

func board_hex_hovered(hx: Vector2i) -> void:
	_hover_hex = hx
	_board.queue_redraw()

func board_cancel() -> void:
	if _mode != "idle" and cb and not cb.is_over() and cb.current().team == "party":
		_build_hero_menu(cb.current())

# hero actions ---------------------------------------------------------

func _after_hero_action(h) -> void:
	_armed = ""
	_flush_log()
	_refresh()
	if cb.is_over():
		_finish()
		return
	if h.econ["action"] <= 0 and h.econ["bonus"] <= 0 and h.econ["move_left"] <= 0:
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
		if opts[i].size() > 2 and String(opts[i][2]) != "":
			b.tooltip_text = opts[i][2]   # native hover popup — what the verb actually does
		_buttons.add_child(b)
	_apply_ui_scale()

func _refresh() -> void:
	_header.text = "THE SUNKEN SHRINE   ·   Round %d   ·   seed %d" % [cb.round_num, _seed]

	var n: int = cb.order.size()
	var ci: int = cb.order.find(cb.current())
	var parts: Array = []
	for i in n:
		var c = cb.order[i]
		var nm = c.cname.split(" ")[0]
		var col = "#8fdc97" if c.team == "party" else "#e58a84"
		if c == cb.current():
			nm = "▶ " + nm
			col = "#ffe27a"
		if c.is_dead():
			nm = "[s]%s[/s]" % nm
		var slot: int = i - ci
		if slot < 0:
			slot += n
		var chunk := "[color=%s]%s(%d)[/color]" % [col, nm, c.init_roll]
		if slot >= 1 and slot <= 3:
			chunk = "[b]%s[/b]" % chunk
		parts.append(chunk)
	_order.text = "[b]ORDER[/b]  " + "   ".join(parts) + "     [color=#5a6070]· 1-9 actions · scroll/± zoom · drag/arrows pan · Home reset ·[/color]"

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious() and _mode == "idle":
		var hint := "  ·  click a blue tile to move" if cur.econ["move_left"] > 0 else ""
		var before = cb.order[(ci - 1 + n) % n]
		var again := "  ·  you act again after %s" % before.cname.split(" ")[0] if before != cur else ""
		_actor.text = "%s  ·  AC %d  ·  HP %d/%d  ·  slots %d/%d  ·  %s%smove %d%s%s" % [
			cur.cname, cb.effective_ac(cur), cur.hp, cur.max_hp, cur.slots[0], cur.slots[1],
			"[action] " if cur.econ["action"] > 0 else "",
			"[bonus] " if cur.econ["bonus"] > 0 else "",
			cur.econ["move_left"], hint, again,
		]
	elif _mode == "idle":
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	_board.queue_redraw()

var _logged = 0
var _last_round = 1

func _flush_log() -> void:
	if cb.round_num != _last_round:
		_last_round = cb.round_num
		_logbox.append_text("\n[color=#6a6f80]─────────   ROUND %d   ─────────[/color]\n" % _last_round)
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
	result = Encounter.resolve_outcome(cb, party)   # writes HP/pools/slots back to the party
	var res: String = cb.outcome()
	_flush_log()
	_refresh()
	for c in _buttons.get_children():
		c.queue_free()
	var seed_edit := LineEdit.new()
	seed_edit.text = str(_seed)
	seed_edit.custom_minimum_size.x = 130
	_buttons.add_child(seed_edit)
	var replay := Button.new()
	replay.text = "Replay seed"
	replay.pressed.connect(func(): _new_game(maxi(1, int(seed_edit.text))))
	_buttons.add_child(replay)
	var fresh := Button.new()
	fresh.text = "New encounter  (R)"
	fresh.pressed.connect(func(): _new_game())
	_buttons.add_child(fresh)
	_apply_ui_scale()
	_actor.text = "  ***  %s  in %d rounds  ***  " % [res.to_upper(), cb.round_num]
	_logbox.append_text("\n[b][color=%s]%s in %d rounds.[/color][/b]\n" % [
		"#7dff9d" if res == "Victory" else "#ff5a4a", res, cb.round_num,
	])
	if res == "Victory":
		_logbox.append_text("[color=#c8a75a]+%d XP, +%d gold.[/color]\n" % [result["xp"], result["gold"]])

func _process(dt: float) -> void:
	if _board:
		_board.tick(dt * _anim)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _logwrap:
		_logwrap.custom_minimum_size.x = min(820.0, size.x * 0.72)

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
	var _reveal = null   # {tid, dice, nat, bonus, total, ac, hit, crit, age}
	var _barks := {}     # id -> {text, age}; drained from cb.barks (T26)
	const BARK_TTL := 2.2

	func reset(_cb) -> void:
		cb = _cb
		_tok.clear(); _hp.clear(); _floats.clear(); _flash.clear()
		for c in cb.combatants:
			_tok[c.id] = _pix(c.pos)
			_hp[c.id] = float(c.hp)
		_barks.clear()
		queue_redraw()

	func slide_from(c) -> void:
		if not _tok.has(c.id):
			_tok[c.id] = _pix(c.pos)

	func flash(_hx: Vector2i) -> void:
		pass  # target flash handled per-token on hp change

	func show_reveal(tid: String, res: Dictionary) -> void:
		_reveal = {
			"tid": tid, "dice": res.get("dice", []), "nat": res.get("nat", 0),
			"bonus": res.get("bonus", 0), "total": res.get("total", 0), "ac": res.get("ac", 0),
			"hit": res.get("hit", false), "crit": res.get("crit", false), "age": 0.0,
		}
		if res.get("hit", false):
			_flash[tid] = 0.35
		queue_redraw()

	# zoom keeping the hex under `sp` (screen point) roughly fixed
	func _zoom_at(sp: Vector2, factor: float) -> void:
		var anchor := Hex.from_pixel(sp - _origin, main.hex_px)
		main.set_zoom(main._zoom * factor)
		_layout()
		main.pan_by(sp - (_origin + Hex.to_pixel(anchor, main.hex_px)))

	func _layout() -> void:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for hx in cb.board["hexes"]:
			var p := Hex.to_pixel(hx, main.hex_px)
			mn = mn.min(p); mx = mx.max(p)
		var span := mx - mn
		# keep the board from being panned entirely off-screen
		var lim := (size + span) * 0.5 - Vector2(90, 60)
		lim = lim.max(Vector2.ZERO)
		main._pan = main._pan.clamp(-lim, lim)
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
		# T26 barks: drain the queue, age them out. One line per speaker at a time.
		while not cb.barks.is_empty():
			var b: Dictionary = cb.barks.pop_front()
			_barks[b["id"]] = {"text": String(b["text"]), "age": 0.0}
			dirty = true
		for id in _barks.keys():
			_barks[id].age += dt
			if _barks[id].age > BARK_TTL:
				_barks.erase(id)
			dirty = true
		if _reveal != null:
			_reveal.age += dt; dirty = true
			if _reveal.age > 1.4:
				_reveal = null
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
				_zoom_at(e.position, 1.1)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(e.position, 1.0 / 1.1)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				main.board_cancel()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				main.board_hex_clicked(Hex.from_pixel(e.position - _origin, main.hex_px))

	# T11 interactables: shapes only, no sprites. Hazards pulse (the hex fill already
	# glows), props get a crate mark, torches a small bright flame.
	# ponytail: a torch could ignite adjacent flammable terrain — not built.
	func _draw_object(o: Dictionary, c: Vector2, s: float, pulse: float) -> void:
		match String(o["type"]):
			"torch":
				draw_circle(c, s * 0.16, main.COL_TORCH.lerp(Color("ff9d3d"), pulse))
				draw_circle(c, s * 0.30, Color(1.0, 0.78, 0.45, 0.12 + 0.10 * pulse))
			"fountain":
				draw_circle(c, s * 0.45, Color("3d5566"))
				draw_arc(c, s * 0.45, 0, TAU, 20, Color("6f97ad"), 2.0)
			_:
				if o.has("hazard") and not o.get("blocks_movement", false):
					draw_circle(c, s * 0.22, Color("ffcf7a").lerp(Color("ff6a2a"), pulse))
					return
				var r := s * 0.42
				draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), Color("6b5236"))
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0),
					Color("ff8c42") if o.get("explosive", false) else Color("3a2c1c"), 2.0)

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
		if hero_turn and main._mode == "idle" and cur.econ["move_left"] > 0:
			field = cb.move_field(cur)
			for hx in field:
				if not cb.provokers_for(cur, hx).is_empty():
					provoke[hx] = true
		if hero_turn and main._mode == "cone":
			var dir := Hex.direction_to(cur.pos, _hover)
			if dir != Vector2i.ZERO:
				for hx in Hex.cone(cur.pos, dir, int(main._tgt_verb.get("radius", 2))):
					cone_hexes[hx] = true

		# tiles
		for hx in cb.board["hexes"]:
			var c := _origin + Hex.to_pixel(hx, s)
			var poly := _hex_poly(c, s - 2.0)
			var fill: Color = main.PALETTES.get(cb.board.get("palette", "shrine"), main.COL_HEX)
			var obj: Dictionary = cb.object_at(hx)
			if obj.has("hazard") and not obj.get("blocks_movement", false):
				fill = main.COL_BRAZIER.lerp(Color("d9622e"), pulse)
			elif obj.get("blocks_movement", false):
				fill = main.COL_PROP
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
			if not obj.is_empty():
				_draw_object(obj, c, s, pulse)

		# the valid-target ring stays here, under the tokens — it just traces the
		# hex edge, which reads fine as "this hex is targetable," not a card that
		# needs to sit on top of anything.
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
		elif hero_turn and main._mode == "idle" and cur.econ["action"] > 0:
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
			# class mark as a small badge pinned to the token's shoulder — legible
			# against the token fill, and it never collides with the initials.
			var glyph := _glyph(c)
			if glyph != "":
				var bc := p + Vector2(-rad * 0.72, -rad * 0.72)
				var brad := rad * 0.46
				draw_circle(bc, brad, base.darkened(0.62))
				draw_arc(bc, brad, 0, TAU, 16, base.lightened(0.15), 1.5)
				_centered(glyph, bc, int(14 * fz), Color("f0e6cf"))

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

			# condition strip, centred over the token (the shoulder is the class badge's)
			var tags: String = Icons.status_glyphs(c)
			if c.is_down(): tags += " %s%d/%d" % [Icons.condition_glyph("down"), c.death_s, c.death_f]
			if tags != "":
				_centered(tags, p + Vector2(0, -rad - 10), int(13 * fz), Color("e6c15a"))

		# the odds chip itself draws last of the per-target overlay — after every
		# token's own circle/badge/HP bar/condition tags, which used to be drawn
		# on top of it and could cover the readout depending on hex spacing.
		if hero_turn and main._mode == "target":
			for c in cb.combatants:
				if not main._valid_target(cur, c):
					continue
				var tp := _origin + Hex.to_pixel(c.pos, s)
				var hot: bool = c.pos == _hover
				var txt: String = main.target_readout(cur, c)
				var fs := int((20 if hot else 15) * fz)
				var w := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var chip := tp + Vector2(-w / 2.0, -s - 4.0)
				draw_rect(Rect2(chip - Vector2(5, fs), Vector2(w + 10, fs + 8)), Color(0, 0, 0, 0.72))
				draw_string(ThemeDB.fallback_font, chip, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color("ffe27a") if hot else Color("d7d7cf"))

		# T26 barks — plain text over the speaker's hex, fading out at the end
		for id in _barks:
			var bk: Dictionary = _barks[id]
			var col := Color("ffe9b0")
			col.a = clampf((BARK_TTL - bk.age) / 0.5, 0.0, 1.0)
			_centered(String(bk.text), _tok.get(id, Vector2.ZERO) + Vector2(0, -s * 1.15),
				int(14 * fz), col)

		# floating damage
		for f in _floats:
			var col: Color = f.color
			col.a = 1.0 - f.age / 1.1
			draw_string(ThemeDB.fallback_font, f.pos + Vector2(-8, -(20.0 + f.age * 34.0)), f.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)

		# --- attack roll reveal (dice + verdict over the target) ---------
		if _reveal != null and _tok.has(_reveal.tid):
			var a := clampf(1.0 - (_reveal.age - 0.9) / 0.5, 0.0, 1.0)   # hold, then fade
			var anchor: Vector2 = _tok[_reveal.tid] + Vector2(0, -s * 1.7)
			var dice: Array = _reveal.dice
			var box := 30.0 * fz
			var total_w: float = dice.size() * (box + 6.0) - 6.0
			var x := anchor.x - total_w / 2.0
			for d in dice:
				var counts: bool = int(d) == int(_reveal.nat)
				var bg := Color("2a2f3d")
				bg.a = a
				draw_rect(Rect2(x, anchor.y, box, box), bg)
				var edge := (Color("ffe27a") if counts else Color("6a6f80"))
				edge.a = a
				draw_rect(Rect2(x, anchor.y, box, box), edge, false, 2.0)
				var dc := (Color("ffffff") if counts else Color("7f8494"))
				dc.a = a
				draw_string(ThemeDB.fallback_font, Vector2(x + box * 0.22, anchor.y + box * 0.72),
					str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * fz), dc)
				if not counts:
					var sl := Color("d15750"); sl.a = a
					draw_line(Vector2(x + 3, anchor.y + box - 3), Vector2(x + box - 3, anchor.y + 3), sl, 2.0)
				x += box + 6.0
			var verdict := "CRIT!" if _reveal.crit else ("HIT" if _reveal.hit else "MISS")
			var vcol := Color("ff6a4a") if _reveal.crit else (Color("8dffb0") if _reveal.hit else Color("8a8a84"))
			vcol.a = a
			var line := "d20 %+d = %d  vs AC %d" % [_reveal.bonus, _reveal.total, _reveal.ac]
			var lcol := Color("cfd2db"); lcol.a = a
			draw_string(ThemeDB.fallback_font, Vector2(anchor.x - total_w / 2.0, anchor.y + box + 16 * fz),
				line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * fz), lcol)
			draw_string(ThemeDB.fallback_font, Vector2(anchor.x - total_w / 2.0, anchor.y - 6),
				verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * fz), vcol)

		# --- hover stat card ------------------------------------------
		if main._mode == "idle":
			for c in cb.combatants:
				if c.pos == _hover and not c.is_dead():
					_stat_card(c, fz)
					break

	func _stat_card(c, fz: float) -> void:
		var lines: Array = [
			c.cname,
			"AC %d   HP %d/%d" % [cb.effective_ac(c), c.hp, c.max_hp],
			"speed %d   %s" % [c.speed, cb.region_at(c.pos)],
		]
		var st: Array = []
		for s in Icons.CONDITION_ORDER:
			if s != "down" and c.has(s): st.append("%s %s" % [Icons.condition_glyph(s), s])
		if c.is_down(): st.append("%s down %d/%d" % [Icons.condition_glyph("down"), c.death_s, c.death_f])
		if cb.is_cover(c.pos): st.append("cover")
		if not st.is_empty(): lines.append(" · ".join(st))
		var kit: Array = []
		for v in c.verbs:
			if not v["label"] in kit: kit.append(v["label"])
		if not kit.is_empty(): lines.append(", ".join(kit))

		var fs := int(12 * clampf(fz, 0.9, 1.3))
		var pad := 8.0
		var w := 0.0
		for l in lines:
			w = maxf(w, ThemeDB.fallback_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var lh := fs + 5.0
		var box := Vector2(w + pad * 2, lines.size() * lh + pad * 2)
		var p: Vector2 = _tok.get(c.id, _pix(c.pos)) + Vector2(main.hex_px * 0.8, -box.y * 0.5)
		p.x = clampf(p.x, 4, size.x - box.x - 4)
		p.y = clampf(p.y, 4, size.y - box.y - 4)
		draw_rect(Rect2(p, box), Color(0.05, 0.06, 0.09, 0.94))
		draw_rect(Rect2(p, box), main.COL_GOLD_EDGE, false, 1.0)
		for i in lines.size():
			var col: Color = main.COL_HEAD if i == 0 else main.COL_BODY
			if i == lines.size() - 1 and not lines[i].begins_with(c.cname): col = main.COL_ACCENT
			draw_string(ThemeDB.fallback_font, p + Vector2(pad, pad + fs + i * lh),
				lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# draw_string with the string's own width taken out, so `at` is its centre.
	func _centered(text: String, at: Vector2, fs: int, col: Color) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, at - Vector2(w * 0.5, -fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _initials(nm: String) -> String:
		var w := nm.split(" ", false)
		if w.size() >= 2:
			return (w[0][0] + w[1][0]).to_upper()
		return nm.substr(0, 2).to_upper()

	# A hero's class mark, whatever class the creator made them — monsters get none.
	func _glyph(c) -> String:
		return Icons.combatant_glyph(c)
