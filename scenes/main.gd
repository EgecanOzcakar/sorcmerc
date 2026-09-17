# Playable UI for The Sunken Shrine — hex board, drawn tokens, styled buttons.
# All rules live in core/. Built programmatically so it needs no editor work.
extends Control

const AI = preload("res://core/ai.gd")
const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Effects = preload("res://core/rules/effects.gd")
const Encounter = preload("res://core/encounter.gd")
const Scaler = preload("res://core/scaler.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Hex = preload("res://core/hex.gd")
const Settings = preload("res://core/settings.gd")
const Tutorial = preload("res://core/tutorial.gd")
const Icons = preload("res://core/ui_icons.gd")
const Campaign = preload("res://core/campaign.gd")   # item_name, for the loot line at the end of a fight
const SettingsOverlay = preload("res://scenes/settings/settings.gd")
const ManualOverlay = preload("res://scenes/manual/manual.gd")
const BugReportOverlay = preload("res://scenes/bugreport/bug_report.gd")
const BugReport = preload("res://core/bug_report.gd")

# What T5 injects before the scene runs: the live party, the node's spec (empty ->
# the scaler sizes one) and its difficulty. `result` is resolve_outcome() once the
# fight is over — deaths / xp / gold / loot for the campaign layer.
var party                       # core/party.gd; a Presets demo party when null
var spec: Dictionary = {}
var difficulty := "normal"
var scouted_ahead := false      # T39: campaign scouted this node — surprise is automatic
var forced_ambush := false      # T9x: camp-ambush item, watch check failed — the foe gets the surprise round, no roll
var tutorial := false           # T32: run the guided walkthrough over this fight
var result: Dictionary = {}
var _own_party := false

const HEX_BASE := 34.0
const REVEAL_PAUSE := 0.75  # beat to read the attack roll (0 under SORCMERC_FAST)
const ZOOM_DEFAULT := 1.5     # ceiling: the board fits the whole map first (Board._layout)
var _zoom := ZOOM_DEFAULT
var _pan := Vector2.ZERO
var hex_px: float:
	get: return HEX_BASE * _zoom
var cb
var _seed: int = 0
var _busy = false
var _advancing = false
var _mode := "idle"          # idle | cone | target
var _tgt_verb: Dictionary = {}   # the verb being aimed, straight from cb.available()
var _armed := ""             # a confirm-guarded verb waiting for its second press
var _deploy_pick := ""       # T39: the hero picked up for a trade, waiting for who to trade with
var _viewing := false        # #72: the bar shows a party member whose turn it is not — read-only
var _hover_hex := Vector2i(999, 999)
var _anim := 1.0             # animation speed multiplier (huge when FAST)
var _slot_max := {}          # id -> slots at the start of the fight (for the pips)
var _fx_on := false           # attack animations: off under SORCMERC_FAST / headless
# T-actionbar: a compact icon grid, up to BTN_COLUMNS*BUTTON_ROWS visible before
# it scrolls (see _process's _bscroll sizing) — plain text rows read fine up to
# ~9 verbs but sprawled once a caster's spell list pushed past 20.
#
# T-skillicons: and now the button IS the badge. Every skill the bar can offer
# has its own art (assets/icons/skills, one per castable spell and per feature),
# so the name, the prose and the numbers moved into the hover popup and the
# label came off the button entirely. A 126x40 row that clipped "Burning Ha…"
# is a 52x52 square that shows the whole spell. What stays on the face is the
# hotkey, in the corner, and an upcast tier when there is one.
const BTN_COLUMNS := 11   # the nine slots, Swap, End turn: one row
const BTN_SIZE := Vector2(52, 52)
# T-hud: HP bar + condition tags, painted above every tier (see
# Board._paint_token_hud / _draw_hud_overlay below) instead of inline in
# Board._draw() — a figure in front used to be able to cover the HP bar of
# the hex behind it, since Figures3D (a Board child) draws after Board itself.
var _hud_layer: CanvasLayer
var _hud_overlay: Control

@onready var _header := Label.new()
@onready var _order := HBoxContainer.new()   # turn-order icon strip along the top
var _order_tiles := {}    # combatant id -> its tile in that strip
var _order_aimed := {}    # ids currently wearing the aim highlight — see _paint_order_aim
@onready var _hint := Label.new()
@onready var _board := Board.new()
const Figures3D := preload("res://scenes/figures3d.gd")
var _figures
@onready var _actor := RichTextLabel.new()
@onready var _buttons := GridContainer.new()
@onready var _bscroll := ScrollContainer.new()
@onready var _logbox := RichTextLabel.new()
@onready var _cap := Label.new()
@onready var _logwrap := PanelContainer.new()

# --- palette (core/ui_icons.gd is the source; board-only tints stay here) ---
const COL_BG := Icons.COL_BG
const COL_HEX := Color("232733")
const COL_HEX_EDGE := Color("39404f")
const COL_HEX_GRID := Color("6b7386")   # the grid line over the floor: lighter than the old gutter, since it sits on stone
const COL_BRAZIER := Color("6b2f1c")
const COL_COVER := Color("2f4744")       # the slab under a cover hex
# T-cover: half cover is +2 AC and +2 on Dex saves (core/combat.gd's
# effective_ac / _saving_throw) — the difference between a 55% swing and a 45%
# one. It was announced by a slab two shades off the ordinary floor and the
# word "cover" in 10px grey-teal at the bottom-left corner, under the foliage
# that always grows on a cover hex, over a textured floor, at any zoom. These
# are what say so instead: a rim around the tile in a colour nothing else on
# the board uses, and a chip that states the number rather than the noun.
const COL_COVER_EDGE := Color("74c2b4")
const COL_PROP := Color("4a3826")       # barrels, crates, fountains
const COL_BLOCKED_EDGE := Color("c98a5a")   # the rim on a hex nobody can stand on — ochre, against cover's teal
const COL_TORCH := Color("ffd98a")
# T11: per-theme floor tint, palette only — no mechanical difference.
const PALETTES := {"shrine": COL_HEX, "camp": Color("2a2a26"), "city": Color("2c2c33"),
	"forest": Color("1f2a22"), "ice": Color("222c36"), "shop": Color("2b2620")}
# T9b: a seamless ground texture per palette (tools/localgen/gen_floor_textures.py),
# laid on the hex plane in ground space so it foreshortens with the board and
# runs unbroken across tiles; the tinted slab underneath still carries the
# theme colour, the texture only gives the ground a surface.
const FLOORS := {
	"shrine": preload("res://assets/board/floor_shrine.png"),
	"camp": preload("res://assets/board/floor_camp.png"),
	"city": preload("res://assets/board/floor_city.png"),
	"forest": preload("res://assets/board/floor_forest.png"),
	"ice": preload("res://assets/board/floor_ice.png"),
	"shop": preload("res://assets/board/floor_shop.png"),
}
const FLOOR_SPAN := 3.0    # hexes per texture repeat
const FLOOR_ALPHA := 0.9    # the texture is the ground now, not a wash over a slab
const FLOOR_TONE := 0.72    # ...held down to the board's dark palette, the board light on top
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
	_fx_on = OS.get_environment("SORCMERC_FAST") == "" and DisplayServer.get_name() != "headless"
	if spec.is_empty():       # standalone: no campaign node dictating difficulty
		difficulty = Settings.current().default_difficulty
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_theme()

	# Root is log sidebar | right column (order strip, board, actor, buttons).
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 12; root.offset_top = 10
	root.offset_right = -12; root.offset_bottom = -10
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

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

	_header.theme_type_variation = "Title"
	var head := HBoxContainer.new()
	col.add_child(head)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_header)
	var manual := Button.new()
	manual.text = "Manual  [F2]"
	manual.theme_type_variation = "Quiet"
	manual.focus_mode = Control.FOCUS_NONE   # hotkeys 1-9 must keep going to the board
	manual.pressed.connect(func(): ManualOverlay.toggle(self))
	head.add_child(manual)
	# A fight is where the rules go wrong, so this is the one screen where the
	# reporter is most worth a click of its own rather than a trip to the title.
	var bug := Button.new()
	bug.text = "Report a bug  [F3]"
	bug.theme_type_variation = "Quiet"
	bug.focus_mode = Control.FOCUS_NONE
	bug.pressed.connect(report_bug)
	head.add_child(bug)
	# Yielding is a wipe without the wait. Up here with the other out-of-fight
	# controls, not in the action bar, so a misclick mid-turn cannot reach it.
	var yield_btn := Button.new()
	yield_btn.text = "Admit defeat"
	yield_btn.theme_type_variation = "Quiet"
	yield_btn.focus_mode = Control.FOCUS_NONE
	yield_btn.pressed.connect(func():
		if cb == null or cb.is_over() or _busy:
			return
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Admit defeat? The fight ends as a loss."
		dlg.ok_button_text = "Admit defeat"
		dlg.confirmed.connect(func(): cb.surrender(); _finish())
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		add_child(dlg)
		dlg.popup_centered())
	head.add_child(yield_btn)

	# --- the action log: a full-height sidebar down the left edge -----
	_logwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var logwrap := _logwrap
	logwrap.custom_minimum_size = Vector2(_log_width(), 0)
	# The ledger's margin column: ink, with the gilt rule down its right edge
	# where it meets the board. No glow — the fight is the bright thing.
	var glow := Icons.box(Icons.COL_INK, Color(0, 0, 0, 0), 0, 16, 14)
	glow.border_color = Icons.COL_GOLD_EDGE
	glow.border_width_right = 2
	logwrap.add_theme_stylebox_override("panel", glow)
	var logcol := VBoxContainer.new()
	logcol.add_theme_constant_override("separation", 4)
	logwrap.add_child(logcol)
	_cap.text = "Action log"
	_cap.theme_type_variation = "Caption"
	logcol.add_child(_cap)
	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	_logbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_logbox.add_theme_font_size_override("normal_font_size", 18)
	_logbox.add_theme_font_size_override("bold_font_size", 18)
	_logbox.add_theme_color_override("default_color", Icons.COL_TEXT)
	logcol.add_child(_logbox)
	root.add_child(logwrap)
	root.add_child(col)

	# --- turn order: one icon tile per combatant, along the top -------
	var orderwrap := PanelContainer.new()
	orderwrap.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, Color(0, 0, 0, 0), 0, 8, 6))
	_order.add_theme_constant_override("separation", 10)
	_order.alignment = BoxContainer.ALIGNMENT_CENTER
	_order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orderwrap.add_child(_order)
	col.add_child(orderwrap)

	_hint.text = "1-9 act, Tab swaps weapon, Space ends the turn, Esc backs out.  Scroll zooms, drag pans, Home resets the view."
	_hint.theme_type_variation = "Dim"
	col.add_child(_hint)

	_board.main = self
	# Pixel art must not be filtered into mush at non-integer zoom. Glyphs are
	# rasterised at their own size and sampled 1:1, so this costs the text nothing.
	_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_board.clip_contents = true
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(0, 240)
	col.add_child(_board)
	_figures = Figures3D.new()
	_figures.board = _board
	_figures.main = self
	_board.add_child(_figures)

	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5   # above Board and Figures3D, both layer 0 — see _draw_hud_overlay
	add_child(_hud_layer)
	_hud_overlay = Control.new()
	_hud_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_overlay.draw.connect(_draw_hud_overlay)
	_hud_layer.add_child(_hud_overlay)

	_actor.bbcode_enabled = true
	_actor.fit_content = true
	_actor.scroll_active = false
	_actor.add_theme_font_size_override("normal_font_size", Icons.FS_HEAD)
	_actor.add_theme_font_size_override("bold_font_size", Icons.FS_HEAD)
	_actor.add_theme_color_override("default_color", Icons.COL_BODY)
	col.add_child(_actor)

	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	_buttons.columns = BTN_COLUMNS
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# T29: the row wraps, and once it's wrapped past BUTTON_ROWS it scrolls —
	# a caster with 20 verbs used to push the rest off the bottom of the screen.
	_bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bscroll.add_child(_buttons)
	col.add_child(_bscroll)

	set_process(true)
	_apply_ui_scale()
	# T32: armed, not opened. The walkthrough used to come up the instant the
	# screen did, which put its cards over whatever the bar happened to be at
	# that moment — an empty one while the goblin takes the first turn, or
	# T39's deployment bar ("Swap Vera Kord", "Begin the ambush") when the
	# party rolled its Stealth well. Neither is the fixed nine-slot bar the
	# card describes. _advance() opens it on the first hero turn instead, when
	# the bar it explains is the bar on screen.
	_walk_pending = tutorial
	_new_game()

# Font sizes across the whole combat UI track the zoom level.
func _apply_ui_scale() -> void:
	var u := clampf(_zoom, 0.9, 1.4)
	_header.add_theme_font_size_override("font_size", int(Icons.FS_TITLE * u))
	_actor.add_theme_font_size_override("normal_font_size", int(Icons.FS_HEAD * u))
	_actor.add_theme_font_size_override("bold_font_size", int(Icons.FS_HEAD * u))
	# the log is a narrow sidebar now — body size wraps far less than head size
	_logbox.add_theme_font_size_override("normal_font_size", int(Icons.FS_BODY * u))
	_logbox.add_theme_font_size_override("bold_font_size", int(Icons.FS_BODY * u))
	for b in _buttons.get_children():
		if b is Button and b.icon != null:   # the Field Manual search box shares this grid
			b.custom_minimum_size = BTN_SIZE * u
			b.add_theme_constant_override("icon_max_width", int(Icons.ICON_PX * u))
			for chip in b.get_children():
				if chip is Label:
					chip.add_theme_font_size_override("font_size", int(12 * u))
		else:
			b.add_theme_font_size_override("font_size", int(Icons.FS_BODY * u))
			b.custom_minimum_size = Vector2(126, 40) * u

func set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.45, 3.0)
	if _board:
		_board._auto_fit = false
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
	if _walk != null and not _walk_key_ok(e.keycode):
		return
	if e.echo and e.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return   # key repeat pans; it must not end turns or press hotkeys twice
	if _wash != null:   # #74: any key is the click
		_dismiss_wash()
		return
	match e.keycode:
		KEY_EQUAL, KEY_KP_ADD: set_zoom(_zoom * 1.1)
		KEY_MINUS, KEY_KP_SUBTRACT: set_zoom(_zoom / 1.1)
		KEY_HOME: _zoom = ZOOM_DEFAULT; _pan = Vector2.ZERO; _board._auto_fit = true; _apply_ui_scale(); _board.queue_redraw()
		KEY_LEFT: pan_by(Vector2(40, 0))
		KEY_RIGHT: pan_by(Vector2(-40, 0))
		KEY_UP: pan_by(Vector2(0, 40))
		KEY_DOWN: pan_by(Vector2(0, -40))
		KEY_ESCAPE, KEY_B: board_cancel()
		KEY_TAB: _press_key("Tab")
		KEY_R: if cb and cb.is_over(): _new_game()
		KEY_F1: SettingsOverlay.toggle(self, func(): _anim = Settings.anim())
		KEY_F2: ManualOverlay.toggle(self)
		KEY_F3: report_bug()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_press_hotkey(e.keycode - KEY_1, e.shift_pressed)
		KEY_0, KEY_SPACE:
			_press_hotkey(-1)  # last button (End turn / Cancel)

# The bug reporter, from the fight. The context is the board as it stands —
# which is exactly the thing a rules bug is about and the thing a screenshot of
# the log would not say.
func report_bug() -> void:
	BugReportOverlay.toggle(self, bug_context())

func bug_context() -> Dictionary:
	var ctx := {"Screen": "combat%s" % ("  (tutorial)" if tutorial else "")}
	ctx["Map"] = String(spec.get("theme", "sunken-shrine"))
	ctx["Difficulty"] = difficulty
	if cb != null:
		ctx["Round"] = str(cb.round_num)
		if cb.is_over():
			ctx["Over"] = "yes — %s" % cb.outcome()
		elif cb.turn_idx >= 0 and cb.turn_idx < cb.order.size():
			# Indexed by hand rather than through current(): this runs while the
			# game is in whatever state the player is reporting, which is exactly
			# when the turn cursor might be somewhere current() would fault on.
			var up = cb.order[cb.turn_idx]
			ctx["Whose turn"] = "%s (%s)" % [up.cname, up.team]
		var standing: Array = []
		for c in cb.combatants:
			standing.append("%s [%s] %d/%d hp at %d,%d" % [
				c.cname, c.team, c.hp, c.max_hp, c.pos.x, c.pos.y])
		ctx["Board"] = "; ".join(standing)
	ctx["Seed"] = str(_seed)
	ctx["Aiming"] = _mode
	return ctx

func _press_hotkey(idx: int, shift := false) -> void:
	# A reaction question is the one thing asked while the board is busy, and
	# [1] Yes / [2] or Space Hold it must reach it. #76: it has its own card
	# now (_build_reaction_card), so the keys answer it directly.
	if _reaction_answer < 0:
		if idx == 0:
			_reaction_answer = 1
		elif idx == 1 or idx < 0:
			_reaction_answer = 0
		return
	if _busy:
		return
	# T29: while aiming, the number keys still address the verb menu — drop out
	# of targeting first instead of indexing into the lone [Esc] Cancel button.
	if idx >= 0 and _mode != "idle" and _mode != "deploy" and cb and not cb.is_over() \
			and cb.current().team == "party" and cb.current().conscious():
		_build_hero_menu(cb.current())
	var kids := _buttons.get_children()
	if kids.is_empty():
		return
	var b = kids[kids.size() - 1] if idx < 0 else (kids[idx] if idx < kids.size() else null)
	if b is Button and not b.disabled:
		if shift and b.has_meta("shift_fn"):
			b.get_meta("shift_fn").call()
		else:
			b.pressed.emit()

# The button wearing a named key chip (Tab for Swap weapon).
func _press_key(key: String) -> void:
	if _busy:
		return
	for b in _buttons.get_children():
		if b is Button and String(b.get_meta("hotkey", "")) == key and not b.disabled:
			b.pressed.emit()
			return

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
	cb.party = party   # the stash is the potion shelf (core/potions.gd)
	# The one thing that makes a reaction stop the fight and ask. Installed only
	# here, only for a player who is actually watching: with it unset the
	# resolver auto-resolves reactions exactly as it always has, which is what
	# every headless run and every test gets (Settings.reaction_prompts_on()
	# refuses under SORCMERC_FAST — a prompt nobody answers is a hang).
	if Settings.reaction_prompts_on():
		cb.reaction_decider = _ask_reaction
	# A foe's action draws the same lunge / shot / flash a hero's does, at the
	# moment it happens, hit or miss. Heroes draw their own from _apply_target,
	# which knows the verb before perform() does.
	cb.on_perform = func(a, v: Dictionary, t) -> void:
		if a.team == "foe" and t is Object and "pos" in t:
			_attack_fx(a, t, v)
	_slot_max.clear()   # the combatant only tracks slots left; the pips need the max
	for c in cb.combatants:
		_slot_max[c.id] = c.slots.duplicate()
	_deploy_pick = ""
	_logbox.text = ""
	_logged = 0
	_last_round = 1
	_board.reset(cb)
	_figures.reset(cb)
	_flush_log()
	_refresh()
	# T9x: a failed camp-ambush watch check — the foe gets the surprise round
	# unconditionally, no Stealth roll (the roll already happened, and failed,
	# in core/world_camp.gd). Checked first: an ambushed party was never given
	# a chance to be the ones sneaking up.
	if forced_ambush:
		cb.begin_ambush_round()
		_flush_log()
		_advance()
		return
	# T39: surprise is settled before anyone acts. Unseen buys a deployment
	# phase — the player permutes who stands on which party start hex.
	if Encounter.surprise_check(cb, scouted_ahead):
		_flush_log()
		# T32: the guided fight takes the free round and skips the phase. Its
		# bar is the phase's own, which contradicts the walkthrough's card, and
		# the phase itself is a mechanic no card explains — T32's brief is that
		# nothing is on screen the walkthrough has not named.
		if tutorial:
			_advance()
		else:
			_deploy_menu()
		return
	_advance()

# --- T39: deployment phase (unseen only) --------------------------------

# Pick somebody up, then click who they change places with — on the map, or off
# the bar, the same two-step the party screen's roster/slot click already is.
#
# It used to be one button per PAIR: with four heroes that is six lines of
# "Swap Vera ↔ Pike" to read before you can move anybody, and the list grows
# quadratically (fifteen at six heroes) while saying nothing about where on the
# board anyone is standing. The choice is a spatial one, so it is made on the
# board: the swappable hexes are ringed, the one you have picked up is ringed
# brighter, and clicking a second hero trades them.
func _deploy_menu() -> void:
	_mode = "deploy"
	var heroes: Array = cb.team_of("party").filter(func(c): return c.conscious())
	if _deploy_pick != "" and not heroes.any(func(c): return c.id == _deploy_pick):
		_deploy_pick = ""          # they went down between menus; nobody is held
	var opts: Array = []
	for h in heroes:
		var held: bool = h.id == _deploy_pick
		opts.append([("▣  %s" % h.cname) if held else "Swap %s" % h.cname,
			_pick_deploy.bind(h.id)])
	if _deploy_pick == "":
		_actor.text = "[b]Unseen.[/b]  Click a hero on the map (or here) to pick them up, then click who they trade places with. Begin when they stand where you want them — the enemy loses its first round."
	else:
		_actor.text = "[b]Unseen.[/b]  %s is picked up — click another hero to trade places, or click them again to put them back." \
			% _deploy_name(_deploy_pick)
	opts.append(["Begin the ambush", func():
		_deploy_pick = ""
		_mode = "idle"
		_advance()])
	_set_buttons(opts)

# combat.gd holds combatants in a flat array with no lookup of its own, and one
# deployment phase is not a reason to add an index to the resolver.
func _combatant(id: String):
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

func _deploy_name(id: String) -> String:
	var c = _combatant(id)
	return c.cname if c != null else "?"

# One click of the two. The first picks a hero up, a second click on the same
# hero puts them back, and a click on anybody else is the trade.
func _pick_deploy(id: String) -> void:
	if _mode != "deploy":
		return
	if _deploy_pick == "" or _deploy_pick == id:
		_deploy_pick = "" if _deploy_pick == id else id
		_board.queue_redraw()
		_deploy_menu()
		return
	var a = _combatant(_deploy_pick)
	var b = _combatant(id)
	_deploy_pick = ""
	if a == null or b == null:
		_deploy_menu()
		return
	_swap_deploy(a, b)

func _swap_deploy(a, b) -> void:
	var p: Vector2i = a.pos
	a.pos = b.pos
	b.pos = p
	cb.log.append("%s and %s trade places before the fight." % [a.cname, b.cname])
	_board.reset(cb)
	_figures.reset(cb)
	_flush_log()
	_refresh()
	_deploy_menu()

# Who on the board can be picked up right now: the conscious party, since the
# whole phase is permuting where they stand.
func deploy_swappable(c) -> bool:
	return _mode == "deploy" and c != null and c.team == "party" and c.conscious()

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
			_viewing = false
			_set_buttons([])
			while _walk != null:      # nobody swings while the walkthrough is up
				await get_tree().process_frame
			await get_tree().create_timer(TURN_BEAT / _anim).timeout
			if not c.is_down():
				# Awaited because the AI now stops between its own actions to
				# offer the party its reactions (core/ai.gd). With prompts off
				# it never suspends and this is the same call it always was.
				# Its swings draw through cb.on_perform (see _start_combat).
				await AI.take_turn(cb, c)
			_flush_log()
			_refresh()
			_busy = false
			cb.end_turn()
			continue
		_mode = "idle"
		_viewing = false
		_build_hero_menu(c)
		_advancing = false
		if _walk_pending:        # T32: the bar the cards describe is now up
			_walk_pending = false
			_walk_show(0)
		return
	_advancing = false
	_finish()

# --- reaction prompts ---------------------------------------------------
#
# combat.gd cannot stop to ask (GDScript has no way to block, which is why
# combat-design.md §2 cut prompts in the first place), so the question is put
# from here, one step before the action resolves: core/ai.gd calls
# cb.offer_reactions() ahead of every swing and every cast, that reaches this,
# and the answer is waiting by the time the trigger fires.
#
# Only reactions that spend a slot get here. An opportunity attack and Uncanny
# Dodge cost nothing and still fire by themselves — there is one sensible answer
# to those and it is not worth a key press.
var _reaction_answer := 0    # -1 only while the question is up, then 0 no / 1 yes
var _reaction_card: PanelContainer = null   # #76: the question, centred over the board

func _ask_reaction(reactor, v: Dictionary, trigger: String, ctx: Dictionary) -> bool:
	var was_busy: bool = _busy
	_busy = true
	_reaction_answer = -1
	_set_buttons([])
	_reaction_card = _build_reaction_card(_reaction_question(reactor, v, trigger, ctx), [
		["Yes — " + String(v["label"]) + "  [1]", func(): _reaction_answer = 1,
			"Spend %s's reaction and the slot." % reactor.cname],
		["Hold it  [2 / Space]", func(): _reaction_answer = 0,
			"Keep the reaction and the slot for later."],
	])
	while _reaction_answer < 0:
		await get_tree().process_frame
	_reaction_card.queue_free()
	_reaction_card = null
	_busy = was_busy
	return _reaction_answer == 1

# #76: a reaction is a stop-everything question, so it sits in the middle of
# the screen over the board rather than down in the action bar. On _hud_layer
# like the tutorial's cards, and for the same reason — above the HP bars.
func _build_reaction_card(question: String, opts: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = theme
	card.add_theme_stylebox_override("panel", Icons.box(Icons.COL_INK, Icons.COL_GOLD_EDGE, 0, 22, 16))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var head := Label.new()
	head.text = "Reaction"
	head.theme_type_variation = "Caption"
	col.add_child(head)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(WALK_CARD_W, 0)
	body.add_theme_font_size_override("normal_font_size", Icons.FS_HEAD)
	body.add_theme_font_size_override("bold_font_size", Icons.FS_HEAD)
	body.add_theme_color_override("default_color", Icons.COL_BODY)
	body.text = question
	col.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for o in opts:
		var b := Button.new()
		b.text = String(o[0])
		b.tooltip_text = String(o[2])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(o[1])
		row.add_child(b)
	_hud_layer.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	return card

# What the question says. The cost is in it because the cost is the decision,
# and for a swing the hit chance is too — the answer is given before the d20,
# so the player is committing against a number rather than against a result.
func _reaction_question(reactor, v: Dictionary, trigger: String, ctx: Dictionary) -> String:
	var lvl := int(v.get("slot_level", 0))
	var cost := ""
	if lvl > 0:
		cost = " — a level-%d slot (%d left)" % [lvl, reactor.slots[lvl - 1]]
	elif v.has("pool"):
		cost = " — %d use%s left" % [reactor.pool_left(v["pool"]),
			"" if reactor.pool_left(v["pool"]) == 1 else "s"]
	var head := ""
	if trigger == "spell_cast":
		head = "[b]%s[/b] is casting [b]%s[/b]." % [ctx["caster"].cname, ctx["verb"]["label"]]
	else:
		var atk = ctx["attacker"]
		head = "[b]%s[/b] swings at [b]%s[/b] — %d%% to hit." % [atk.cname, ctx["target"].cname,
			int(round(cb.hit_chance(atk, ctx["target"]) * 100.0))]
	var tail := ", if it lands" if trigger == "damaged_by_attack" else ""
	return "%s  %s can answer with [b]%s[/b]%s%s." % [head, reactor.cname, v["label"], cost, tail]

func _end_turn() -> void:
	if _busy:
		return
	_mode = "idle"
	cb.end_turn()
	_advance()

# --- hero menu ---------------------------------------------------------

# What a bar button's mark is made of: the drawn badge (assets/icons, via
# Icons.verb_icon / school_icon), the glyph to fall back to if that build has no
# icons, and the frequency key the press counts against (empty for the bar's own
# controls — End turn and Back don't reorder anything). No colour: the badges
# are finished art and carry their own.
static func _mark(tex: Texture2D, glyph := "", freq_key := "") -> Dictionary:
	return {"icon": tex, "glyph": glyph, "freq_key": freq_key}

# Verb-level menu. Every verb becomes an entry here, then _slotted() lays the
# entries into the fixed bar (see SLOTS). Everything on it comes from
# cb.available(h) — no hero, class or spell is named here.
# Verbs that need a target enter "target" mode — hover a token for its %, click to apply.
#
# A spell castable at several slot levels used to get one full-width row per
# level ("Cure Wounds", "Cure Wounds ★2", "Cure Wounds ★3", ...) — fine at 2
# tiers, unreadable at 5. Now every tier after the loop is collapsed into the
# one spell's tiers[] and only its base entry reaches `opts`; picking it opens
# _spell_tier_menu instead of casting directly, unless there's only one tier,
# which behaves exactly as before.
func _build_hero_menu(h, keep_armed := false) -> void:
	if not keep_armed:
		_armed = ""
	_mode = "idle"
	_tgt_verb = {}
	_submenu = ""
	_submenu_page = 0
	_tier_spell = ""
	_set_buttons(_slotted(h, _menu_entries(h)["opts"]))
	_paint_order_aim()   # aim dropped: clear any highlight it left on the strip
	_board.queue_redraw()

# Every verb the character has, as a bar entry, before _slotted() lays them into
# the fixed nine. Split out of _build_hero_menu so a page can be re-derived
# rather than re-shown: arming a two-press confirm changes one entry's label and
# its armed flag, and whatever page you armed it FROM has to be rebuilt from the
# new entries. Issue #24 is what re-showing the stale ones looked like — arming
# Rage inside the [3] Bonus submenu dropped you back on the main bar with the
# confirm nowhere on it, so the second press of the same key swung the greataxe
# instead and Rage took four presses (3, 1, 3, 1) to come out.
func _menu_entries(h) -> Dictionary:
	var opts: Array = []
	var spell_tiers: Dictionary = {}   # spell id -> Array of this verb's entries, one per castable level
	var spell_order: Array = []        # first-seen order, so a spell keeps its natural position in opts
	var usable := {}
	if not _viewing:   # #72: a sheet being looked at fires nothing
		for v in cb.available(h):
			usable[String(v.get("id", v["kind"]))] = true
	# The whole kit, not just what is affordable this instant: an unavailable
	# verb keeps its slot, greyed, so nothing to its right ever moves.
	for v in cb.all_verbs(h):
		var on: bool = usable.has(String(v.get("id", v["kind"])))
		var label: String = _verb_label(h, v)
		# The name leads the popup now that it has left the button face.
		var tip: String = label + "\n" + _verb_tooltip(h, v)
		var sid: String = String(v.get("spell", ""))
		var glyph: String = Icons.school_glyph(Icons.spell_school(sid)) if sid != "" \
			else Icons.verb_glyph(String(v["kind"]))
		var freq_key: String = ("spell:" + sid) if sid != "" else String(v.get("id", v["kind"]))
		# The drawn badge: a spell wears its school (the disc under the art is
		# school_color, the same one spell_bb tints its name with), everything
		# else the martial set. `glyph` stays as the fallback for a build where
		# the icons aren't there — see Icons.verb_icon.
		var meta := _mark(Icons.skill_icon(v), glyph, freq_key)
		meta["slot_level"] = int(v.get("slot_level", 0))
		meta["cost"] = String(v.get("cost", "action"))
		if label.contains("★"):
			meta["tier"] = label.substr(label.find("★"))   # the upcast slot, on the badge's corner
		if _armed == String(v.get("id", "")):
			meta["armed"] = true
		meta["disabled"] = not on
		var entry: Array
		match v.get("targeting", "self"):
			"enemy", "ally":
				entry = [label + "…", func(): _enter_target(h, v), tip, meta]
			"direction":
				entry = [label + " (aim…)", func(): _enter_cone(h, v), tip, meta]
			"hex", "corner", "line":
				entry = [label + " (aim…)", func(): _enter_area(h, v), tip, meta]
			_:
				if _costly(v):
					var opt := _confirm_opt(h, v["id"], label, func(): cb.perform(h, v); _after_hero_action(h))
					opt.append(tip)
					opt.append(meta)
					entry = opt
				else:
					var fn := func(): cb.perform(h, v); _after_hero_action(h)
					entry = [label, fn, tip, meta]
		if sid != "":
			if not spell_tiers.has(sid):
				spell_tiers[sid] = []
				spell_order.append(sid)
				opts.append(sid)   # placeholder — replaced once every tier of this spell is seen
			spell_tiers[sid].append(entry)
		else:
			opts.append(entry)

	for sid in spell_order:
		var tiers: Array = spell_tiers[sid]
		var i: int = opts.find(sid)
		if tiers.size() == 1:
			opts[i] = tiers[0]
		else:
			var base: Array = tiers[0]
			# The name has to lead here too: this entry replaces the per-tier
			# ones wholesale, and its tooltip is the only place left that says
			# which spell the badge belongs to. One badge for the spell, live
			# while ANY of its tiers is — the picker greys the tiers there are
			# no slots for, the same way the bar greys anything else spent.
			var head: Dictionary = base[3].duplicate()
			var castable: int = tiers.filter(func(t): return not bool(t[3].get("disabled", false))).size()
			head["disabled"] = castable == 0
			head["shift_fn"] = func(): _spell_tier_menu(h, sid)   # Shift+number: pick the slot level
			opts[i] = [base[0], func(): _spell_tier_menu(h, sid),
				"%s\n%d of %d levels castable — pick one (Shift+key for the levels)." % [base[0], castable, tiers.size()], head]

	return {"opts": opts, "tiers": spell_tiers}

# --- the fixed bar --------------------------------------------------------
#
# Nine slots, the same for every character, the same every fight:
#   [1] Attack  [2] Spells ▸  [3] Bonus ▸  [4] Features ▸  [5] Dash
#   [6] Disengage  [7] Dodge  [8] Hide  [9] Other ▸ (Help, Shove, Smash)
#   then [Tab] Swap weapon   [Space] End turn.
# A slot the character has nothing for stays put, greyed; a list slot with a
# single entry (a barbarian's Rage) fires it directly, no submenu. Spells are
# one list under [2]; [3] is everything that costs a bonus action (or
# nothing) — Second Wind, Rage, Cunning Action's
# Dash/Disengage/Hide, a Nick off-hand, Healing Word — so the second thing
# you do each turn is one key away; [4] is the action-cost kit (Channel
# Divinity today). No more most-used-first reshuffling: the
# point of a fixed bar is that 5 is Dash on Vera, on Ilsa, and next week.
const SLOTS := ["attack", "spells", "bonus", "features", "dash", "disengage", "dodge", "hide", "other"]
const SLOT_NAMES := {"attack": "Attack", "spells": "Spells", "features": "Features", "bonus": "Bonus actions",
	"dash": "Dash", "disengage": "Disengage", "dodge": "Dodge", "hide": "Hide", "other": "Help & Shove"}
const LIST_SLOTS := ["spells", "features", "bonus", "other"]
var _submenu := ""      # "" on the main bar, else the open slot's id (Esc goes back)
var _submenu_page := 0  # which page of a long slot list is showing
var _tier_spell := ""   # which spell's tier picker is open, while _submenu == "tiers"

# Which slots an entry belongs in, from the meta _build_hero_menu attached. A
# bonus-action spell sits under [2] with its level AND under [4].
static func _slots_of(opt: Array) -> Array:
	var meta: Dictionary = opt[3] if opt.size() > 3 else {}
	var key := String(meta.get("freq_key", ""))
	var cost := String(meta.get("cost", "action"))
	var out: Array = []
	if key.begins_with("spell:"):
		out.append("spells")
	elif key.begins_with("shove") or key in ["smash", "help"]:
		out.append("other")
	elif key in ["attack", "dash", "disengage", "dodge", "hide"] and cost == "action":
		out.append(key)
	elif cost != "bonus" and cost != "free":
		out.append("features")
	if cost == "bonus" or cost == "free":
		out.append("bonus")
	return out

# One slot's entries, in the order the submenu shows them. A function rather
# than a local so _open_list can re-derive the page it is re-rendering.
func _slot_list(opts: Array, s: String) -> Array:
	var mine: Array = opts.filter(func(o): return s in _slots_of(o))
	if s == "spells":
		mine.sort_custom(func(a, b): return _tier_of(a) < _tier_of(b) or (_tier_of(a) == _tier_of(b) and a[0] < b[0]))
	return mine

func _slotted(h, opts: Array) -> Array:
	var out: Array = []
	for s in SLOTS:
		var mine: Array = _slot_list(opts, s)
		var live: int = mine.filter(func(o): return not bool(o[3].get("disabled", false))).size()
		if s in LIST_SLOTS and mine.size() > 1:   # one thing to pick from is no pick: the key fires it
			var meta := _mark(_slot_icon(s), "▸")
			meta["disabled"] = mine.is_empty() or (live == 0 and not _viewing)
			meta["key"] = str(SLOTS.find(s) + 1)
			var tip := "%s\n%s" % [SLOT_NAMES[s], ("Nothing to pick from." if mine.is_empty()
				else "%d of %d ready — press to pick one." % [live, mine.size()])]
			out.append([SLOT_NAMES[s] + " ▸", _open_list.bind(h, s), tip, meta])
		elif mine.is_empty():
			var meta := _mark(_slot_icon(s))
			meta["disabled"] = true
			meta["key"] = str(SLOTS.find(s) + 1)
			out.append([SLOT_NAMES[s], func(): pass, "%s\nNot something this character can do." % SLOT_NAMES[s], meta])
		else:
			var o: Array = mine[0].duplicate()
			var meta: Dictionary = o[3].duplicate()
			meta["key"] = str(SLOTS.find(s) + 1)
			o[3] = meta
			out.append(o)
	# T29: melee/ranged toggle — the slot is always there, live only for someone carrying both.
	var swap := _attack_swap(h)
	var swap_meta := _mark(Icons.verb_icon("swap"), "⇄")
	swap_meta["key"] = "Tab"
	if swap.is_empty():
		swap_meta["disabled"] = true
		out.append(["Swap weapon", func(): pass, "Swap weapon\nOnly one weapon to hand.", swap_meta])
	else:
		out.append(["Wield %s" % swap["name"],
			func(): Adapter.set_main_attack(h, String(swap["id"])); _build_hero_menu(h),
			"Wield %s\nYour Attack action switches to %s (%s): %+d to hit, %s %s damage. Free." % [
				swap["name"], swap["name"], swap["range"], int(swap["to_hit"]),
				swap["notation"], swap.get("damage_type", "")], swap_meta])
	var end_mark := _mark(Icons.verb_icon("end_turn"))
	end_mark["key"] = "Spc"
	if _viewing:
		var back := _mark(Icons.verb_icon("back"), "‹")
		back["key"] = "Esc"
		out.append(["Back", _stop_viewing, "Back\nBack to whoever is acting.", back])
	elif h.econ["action"] > 0 and not cb.is_over():
		end_mark["armed"] = _armed == "end"
		var end_opt := _confirm_opt(h, "end", "End turn (action unspent!)", _end_turn)
		end_opt.append("End turn\nYour action is still unspent.")
		end_opt.append(end_mark)
		out.append(end_opt)
	else:
		out.append(["End turn", _end_turn, "End turn", end_mark])
	return out

static func _tier_of(opt: Array) -> int:
	var meta: Dictionary = opt[3] if opt.size() > 3 else {}
	return int(meta.get("slot_level", 0))

func _slot_icon(s: String) -> Texture2D:
	match s:
		"spells": return Icons.school_icon("evocation")
		"features": return Icons.verb_icon("self_buff")
		"bonus": return Icons.verb_icon("grant_action")
		"other": return Icons.verb_icon("shove")
	return Icons.verb_icon(s)

# A slot's own list: numbered from 1, Esc (the last button) goes back. Spells
# are one flat list, lowest level first, one button per spell — a spell with
# several castable levels opens its own tier picker (_spell_tier_menu) when
# pressed; any list longer than nine pages on slot 9 (More ▸), in a stable order.
const LIST_KEYS := 9

# One flat list, nine to a page. The entries are re-derived on every call rather
# than carried in the binding, so re-opening the page after something on it
# changed (a confirm armed, a use spent) shows what is true now — see
# _menu_entries.
func _open_list(h, slot: String, page := 0) -> void:
	_submenu = slot
	_submenu_page = page
	_tier_spell = ""
	var name: String = SLOT_NAMES.get(slot, slot)
	var entries: Array = _slot_list(_menu_entries(h)["opts"], slot)
	var opts: Array = []
	var per := LIST_KEYS if entries.size() <= LIST_KEYS else LIST_KEYS - 1
	var start := page * per
	opts.append_array(entries.slice(start, mini(entries.size(), start + per)))
	if entries.size() > LIST_KEYS:
		var next_page := page + 1 if start + per < entries.size() else 0
		var meta := _mark(Icons.verb_icon("generic"), "…")
		opts.append(["More ▸", _open_list.bind(h, slot, next_page),
			"%s — page %d of %d\nPress for the next page." % [name, page + 1, ceili(float(entries.size()) / per)], meta])
	opts.append(["Back", func(): _build_hero_menu(h, true), "Back", _mark(Icons.verb_icon("back"), "‹")])
	_set_buttons(opts)
	_walk_try("open_list")
	_board.queue_redraw()

# One spell, several slot levels: a small picker instead of a button per tier.
# Each tier's own entry (built above, already wired to _enter_target/_enter_cone/
# cb.perform exactly as it would have been standalone) is reused verbatim, and
# re-derived on every call for the same reason _open_list re-derives its page.
func _spell_tier_menu(h, sid: String) -> void:
	_submenu = "tiers"
	_submenu_page = 0
	_tier_spell = sid
	var opts: Array = (_menu_entries(h)["tiers"].get(sid, []) as Array).duplicate()
	opts.append(["Back", func(): _build_hero_menu(h, true), "Back",
		_mark(Icons.verb_icon("back"), "‹")])
	_set_buttons(opts)
	_board.queue_redraw()

# Re-render whatever page is showing from freshly built entries — the main bar,
# an open slot list, or a spell's tier picker. What a two-press confirm calls
# when it arms: the confirm has to appear where the player's finger already is.
func _refresh_menu(h) -> void:
	match _submenu:
		"": _set_buttons(_slotted(h, _menu_entries(h)["opts"]))
		"tiers": _spell_tier_menu(h, _tier_spell)
		_: _open_list(h, _submenu, _submenu_page)
	_board.queue_redraw()

# The other weapon this character could be swinging: the first equipped attack
# of the opposite range class. {} unless they carry both melee and ranged.
static func _attack_swap(h) -> Dictionary:
	if h.attacks.size() < 2:
		return {}
	var cur := String(h.attacks[0].get("range", ""))
	for a in h.attacks:
		if String(a.get("range", "")) != cur:
			return a
	return {}

# The cost tag is what tells a bonus-action Dash from the Attack-action one.
func _verb_label(h, v: Dictionary) -> String:
	var label: String = v["label"]
	if v["kind"] == "attack" and not h.attacks.is_empty():
		label += " (%s)" % h.attacks[0].get("name", "unarmed")   # which weapon is up
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
	"attack": "Swing the weapon in your main hand.",
	"offhand_attack": "A second swing with your off-hand weapon.",
	"heal_self": "Patch yourself up.",
	"heal_ally": "Restore an ally's hit points.",
	"self_buff": "A boon on yourself.",
	"ally_buff": "A boon on an ally.",
	"attack_modifier": "Attack with advantage — until your next turn, attacks against you have advantage too.",
	"grant_action": "Gain extra actions this turn.",
	"save_effect": "The target rolls a saving throw or suffers the effect.",
	"spell": "Cast the spell.",
}

# Prose first (a spell's own SRD text, else the kind blurb), then the resolved
# numbers. Anything that deals or heals damage always names its dice (T29).
static func _verb_tooltip(h, v: Dictionary) -> String:
	var head := ""
	if v.has("spell"):
		head = String(Catalog.spell(v["spell"]).get("description", ""))
	if head == "":
		head = String(KIND_BLURB.get(v["kind"], ""))
	var bits: Array = []
	match String(v["kind"]):
		"attack":
			var a: Dictionary = h.attacks[0] if not h.attacks.is_empty() else {}
			bits.append("%s: %+d to hit, %s %s" % [a.get("name", "Unarmed strike"),
				int(h.atk_bonus), h.damage, a.get("damage_type", "damage")])
			bits.append("reach %d hex%s" % [h.atk_range, "" if h.atk_range == 1 else "es"])
		"offhand_attack":
			bits.append("%+d to hit, %s damage" % [int(v.get("to_hit", 0)), v.get("damage", "")])
		"grant_action":
			bits.append("+%d action" % int(v.get("amount", 1)))
	if v.has("dice_count") and v.has("dice_sides"):
		var bonus: int = int(v.get("dice_bonus", v.get("bonus_damage", 0)))
		var notation := "%dd%d%s" % [int(v["dice_count"]), int(v["dice_sides"]),
			("+%d" % bonus) if bonus > 0 else ""]
		if v["kind"] in ["heal_self", "heal_ally"]:
			bits.append("Heals %s HP" % notation)
		else:
			bits.append("%s %s" % [notation, v.get("damage_type", "damage")])
	if int(v.get("rays", 1)) > 1:
		bits.append("%d rays, each rolled to hit" % int(v["rays"]))
	if v["kind"] == "drink":
		bits.append(String(v.get("text", "")))
	if int(v.get("targets", 1)) > 1:
		bits.append("up to %d targets within 30 ft of each other" % int(v["targets"]))
	if v.has("heal_count"):
		var hb: int = int(v.get("heal_bonus", 0))
		bits.append("Heals %dd%d%s HP" % [int(v["heal_count"]), int(v.get("heal_sides", 8)),
			("+%d" % hb) if hb > 0 else ""])
	if String(v.get("save", "")) != "":
		bits.append("DC %d %s save%s" % [int(v.get("save_dc", 0)), String(v["save"]).to_upper(),
			" for half" if v.get("half_on_save", false) else ""])
	if not v.get("conditions", []).is_empty():
		bits.append("Inflicts: %s" % ", ".join(v["conditions"]))
	if int(v.get("bonus_damage", 0)) > 0 and not v.has("dice_count"):
		bits.append("+%d damage on your hits" % int(v["bonus_damage"]))
	if int(v.get("extra_attacks", 0)) > 0:
		bits.append("+%d attack%s" % [int(v["extra_attacks"]), "" if int(v["extra_attacks"]) == 1 else "s"])
	if v.has("amount") and not v.has("dice_count") and v["kind"] != "grant_action":
		bits.append("%d" % int(v["amount"]))
	if not v.get("resist", []).is_empty():
		bits.append("Resist: %s" % ", ".join(v["resist"]))
	if int(v.get("slot_level", 0)) > 0:
		bits.append("level %d slot" % int(v["slot_level"]))
	if v.has("pool"):
		bits.append("%d of %d uses left" % [h.pool_left(v["pool"]), int(h.pools[v["pool"]]["max"])])
	if String(v.get("cost", "action")) != "action":
		bits.append("%s action" % String(v["cost"]).capitalize() if v["cost"] != "free" else "free")
	var tail := " · ".join(bits)
	if head == "" or tail == "":
		return head + tail
	return "%s\n%s" % [head, tail]

# Two-press confirm on anything that burns a limited resource, plus the two
# turn-enders that are easy to misclick.
func _costly(v: Dictionary) -> bool:
	return v.has("pool") or int(v.get("slot_level", 0)) > 0 or v["kind"] in ["dodge", "dash"]

# A two-press guard: first press arms and relabels, second press fires. The
# relabel lands on whatever page the first press came from — issue #24: arming
# from a submenu used to rebuild the main bar under the player, so the same key
# pressed twice ran the main bar's slot instead of confirming.
func _confirm_opt(h, key: String, label: String, fn: Callable) -> Array:
	if _armed == key:
		return ["✓ Confirm: %s" % label, func(): _armed = ""; fn.call()]
	return [label, func(): _armed = key; _refresh_menu(h)]

func _enter_cone(h, v: Dictionary) -> void:
	_mode = "cone"
	_tgt_verb = v
	_actor.text = "%s — aim %s: hover a direction, click to cast.  (Esc / right-click cancels)" % [
		h.cname, v["label"]]
	_set_buttons([["Cancel", func(): board_cancel(), "Cancel",
		_mark(Icons.verb_icon("back"), "‹")]])
	_paint_order_aim()
	_board.queue_redraw()

# A hex, a corner or a line: the board's hover is the aim; click commits.
func _enter_area(h, v: Dictionary) -> void:
	_mode = "area"
	_tgt_verb = v
	var how: String = {"hex": "hover a hex", "corner": "hover a hex corner", "line": "hover a hex to aim the line"}.get(v["targeting"], "aim")
	_actor.text = "%s — %s: %s, click to cast.  (Esc / right-click cancels)" % [h.cname, v["label"], how]
	_set_buttons([["Cancel", func(): board_cancel(), "Cancel",
		_mark(Icons.verb_icon("back"), "‹")]])
	_paint_order_aim()
	_board.queue_redraw()

# What the pending area verb would cover at the board's current hover, [] if
# it can't be aimed there. Shared by the preview and the click.
func _area_aim(h) -> Array:
	if _tgt_verb.is_empty():
		return []
	var target = _board.aim_target(_tgt_verb["targeting"])
	if target == null or not cb.legal_area(h, _tgt_verb, target):
		return []
	return cb.area_hexes(h, _tgt_verb, target)

func _enter_target(h, v: Dictionary) -> void:
	_mode = "target"
	_tgt_verb = v
	_actor.text = "%s — %s: hover a target for the odds, click to apply.  (Esc / right-click cancels)" % [
		h.cname, v["label"]]
	_set_buttons([["Cancel", func(): board_cancel(), "Cancel",
		_mark(Icons.verb_icon("back"), "‹")]])
	_paint_order_aim()
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
	# T39: during deployment the board is the control — click a hero to pick
	# them up, click another to trade places. Nobody has a turn yet, so none of
	# the acting-hero checks below apply.
	if _mode == "deploy":
		for c in cb.combatants:
			if c.pos == hx and deploy_swappable(c):
				_pick_deploy(c.id)
				return
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
			if _fx_on:
				var swept := Hex.cone(h.pos, dir, int(v.get("radius", 2)))
				_board.play_fx("spell", h.id, h.pos, swept[swept.size() - 1] if not swept.is_empty() else h.pos, swept)
			_after_hero_action(h)
	elif _mode == "area":
		var target = _board.aim_target(_tgt_verb["targeting"])
		if target != null and cb.legal_area(h, _tgt_verb, target):
			_mode = "idle"
			var v := _tgt_verb
			_tgt_verb = {}
			var swept: Array = cb.area_hexes(h, v, target)
			cb.perform(h, v, target)
			if _fx_on and not swept.is_empty():
				_board.play_fx("spell", h.id, h.pos, swept[-1], swept)
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
			_walk_try("move")
			_after_hero_action(h)

func _apply_target(h, c) -> void:
	_mode = "idle"
	var v := _tgt_verb
	_tgt_verb = {}
	var res = cb.perform(h, v, c)
	_attack_fx(h, c, v)
	# T29: any resolved roll pops the reveal, not just weapon attacks. A
	# countered spell pops one too: the action is gone and nothing happened,
	# which without a word on the board reads as a button that did nothing.
	if typeof(res) == TYPE_DICTIONARY and (res.has("hit") or res.has("saved")
			or res.get("countered", false)):
		_busy = true
		# The news belongs over whoever answered, not over the target the spell
		# never reached.
		var on = res.get("by") if res.get("countered", false) else c
		_board.show_reveal((on if on != null else c).id, res, _reveal_head(res))
		await get_tree().create_timer(REVEAL_PAUSE / _anim).timeout
		_busy = false
	_after_hero_action(h)

# The popup's primary readout: the outcome and the damage, never the raw d20
# (that stays as the small line under the dice). -> [text, color]
static func _reveal_head(res: Dictionary) -> Array:
	var dmg := int(res.get("damage", 0))
	var tail := "  %d" % dmg if dmg > 0 else ""
	if res.get("countered", false):
		return ["COUNTERED", Color("b98fe0")]
	if res.has("hit"):
		if not res["hit"]:
			return ["MISS", Color("8a8a84")]
		if res.get("crit", false):
			return ["CRIT!" + tail, Color("ff6a4a")]
		return ["HIT" + tail, Color("8dffb0")]
	if res.get("saved", false):
		return [("SAVED" + tail) if dmg > 0 else "SAVED", Color("8fb7d8")]
	return ["FAILED SAVE" + tail, Color("ffc46a")]

func board_hex_hovered(hx: Vector2i) -> void:
	_hover_hex = hx
	if _walk != null:
		# The stat card is drawn by Board for anybody standing here (see
		# _stat_card), so a hover that landed on a living token is the
		# walkthrough's "inspect". Behind the null check because every other
		# fight there has ever been pays for every hover otherwise.
		for c in cb.combatants:
			if c.pos == hx and not c.is_dead():
				_walk_try("inspect")
				break
	_paint_order_aim()
	_board.queue_redraw()

func board_cancel() -> void:
	if _reaction_answer < 0:   # Esc on a reaction question is "hold it"
		_reaction_answer = 0
		return
	if _mode == "deploy":
		if _deploy_pick != "":      # put down whoever is held; the phase itself stays open
			_deploy_pick = ""
			_board.queue_redraw()
			_deploy_menu()
		return
	if _viewing:
		_stop_viewing()
		return
	if (_mode != "idle" or _submenu != "") and cb and not cb.is_over() and cb.current().team == "party":
		_build_hero_menu(cb.current())

# hero actions ---------------------------------------------------------

# Cosmetic attack animation. Kind comes from the verb: a spell flashes, a ranged
# weapon throws a projectile, anything else lunges.
func _attack_fx(a, t, v: Dictionary) -> void:
	if not _fx_on or a == null or t == null or a == t:
		return
	var kind := "melee"
	if v.has("spell") or v.get("kind", "") in ["heal_ally", "heal_self"]:
		kind = "spell"
	elif a.ranged or int(v.get("range", a.atk_range)) > 1:
		kind = "ranged"
	_board.play_fx(kind, a.id, a.pos, t.pos)

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

# opts entries: [label, fn] or [label, fn, tooltip] or [label, fn, tooltip, meta]
# where meta is {"icon": Texture2D, "glyph": String, "freq_key": String,
# "tier": String, "armed": bool}, all optional. Buttons are a fixed-size grid
# (BTN_COLUMNS wide, up to BUTTON_ROWS tall before scrolling — see _process).
#
# T-skillicons: a button is its skill's badge and nothing else. `label` is not
# drawn any more — it leads the tooltip instead (see _build_hero_menu), which is
# what lets the grid be squares. Two things still ride on the face, both as
# corner chips rather than as button text, so neither can push the badge around:
# the hotkey, and an upcast tier. A build with no icons falls back to the old
# labelled row, glyph and all, so the bar is never a grid of blank squares.
#
# Hotkeys: [1]..[9] on the first nine, [0] on the last entry (End turn /
# Cancel), everything past 9 is click-only.
func _set_buttons(opts: Array) -> void:
	# Out of the tree now, not at the end of the frame. A queue_free()d child is
	# still a child until the frame turns over, and _press_hotkey indexes
	# get_children() by position — so a key pressed in the same frame a new bar
	# was built addressed the OLD bar's slots. Rare in play (it needs the press
	# and the rebuild in one frame) and reliable in a harness, which is how it
	# turned up: pressing [3] right after a turn began hit the deploy bar's
	# third button instead of Bonus actions. scenes/party/party.gd's _clear()
	# already does it this way, for its own version of the same reason.
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var count := opts.size()
	var u := clampf(_zoom, 0.9, 1.4)
	for i in count:
		var b := Button.new()
		var meta: Dictionary = opts[i][3] if opts[i].size() > 3 else {}
		var hotkey := String(meta.get("key", ""))
		if hotkey == "":
			if count == 1 or (_submenu != "" and i == count - 1):
				hotkey = "Esc"
			elif i == count - 1:
				hotkey = "0"
			elif i < 9:
				hotkey = str(i + 1)
		var tex: Texture2D = meta.get("icon")
		Icons.icon_button(b, tex, int(Icons.ICON_PX * u))
		var tip := String(opts[i][2]) if opts[i].size() > 2 else ""
		if tex != null:
			b.custom_minimum_size = BTN_SIZE * u
			_chip(b, hotkey, Control.PRESET_BOTTOM_RIGHT, Icons.COL_HEAD, u)
			_chip(b, String(meta.get("tier", "")), Control.PRESET_TOP_LEFT, Icons.COL_GOLD, u)
		else:
			# no art in this build: the pre-badge bar, verbatim
			var glyph: String = String(meta.get("glyph", ""))
			b.text = ("[%s] " % hotkey if hotkey != "" else "") \
				+ (glyph + " " if glyph != "" else "") + String(opts[i][0])
			b.custom_minimum_size = Vector2(126, 40) * u
		if meta.get("disabled", false):
			# Still in its slot, still the same badge — just not right now. The
			# alternative is dropping it, which moves every badge after it.
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.35)
			# Appended, not prefixed: the skill's NAME leads every tooltip on
			# this bar, and it is the line that says which badge you are over.
			tip = tip + "\n\nNot available right now."
		elif meta.get("armed", false):
			# A two-press verb is armed: with no label to relabel, the badge says
			# so by going warm, and the popup says it in words.
			b.modulate = Color("ffb3a8")
			tip = "Press again to confirm.\n" + tip
		b.pressed.connect(opts[i][1])
		b.set_meta("hotkey", hotkey)
		if tutorial:
			# T32: the walkthrough's bar card asks for a slot to be hovered, and
			# this is how it hears that one was. Wired only for the guided fight
			# — an ordinary bar is rebuilt on every action and owes nothing.
			b.mouse_entered.connect(_walk_try.bind("hover_slot"))
		if meta.has("shift_fn"):
			b.set_meta("shift_fn", meta["shift_fn"])
		if tip != "":
			b.tooltip_text = tip   # native hover popup — the name, then what it does
		_buttons.add_child(b)
	_apply_ui_scale()

# A corner chip on a badge button: the hotkey, or an upcast tier. A Label child
# rather than the Button's own text, because Button lays its text out next to
# the icon and would squeeze the badge to fit it.
func _chip(b: Button, text: String, preset: int, col: Color, u: float) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(12 * u))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Icons.COL_INK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	b.add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(3 * u))

func _refresh() -> void:
	_header.text = "The Sunken Shrine, round %d" % cb.round_num
	_header.tooltip_text = "seed %d" % _seed

	var n: int = cb.order.size()
	var ci: int = cb.order.find(cb.current())
	_build_order_strip()

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious() and _mode == "idle":
		var hint := "    click a blue tile to move" if cur.econ["move_left"] > 0 else ""
		var before = cb.order[(ci - 1 + n) % n]
		var again := "    you act again after %s" % before.short_name() if before != cur else ""
		var res := _resources(cur)
		_actor.text = "%s    AC %d    %s%s    %s%s%s" % [
			"[b]%s[/b]" % cur.cname, cb.effective_ac(cur), _hp_bb(cur),
			("    " + res) if res != "" else "",
			_econ_bb(cur), hint, again,
		]
	elif _mode == "idle" and not _viewing:
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	_board.queue_redraw()

# --- #72: looking at a party member off their turn ------------------------
#
# The strip is where a fight is read, and a tile is the natural place to ask
# "what has Ilsa got left?". The bar it shows is the real one (_menu_entries,
# _slotted), with every action greyed and the lists still openable, so the
# tooltips say what each spell and feature does. Esc, Back, or the next hero
# turn puts the acting hero's bar back.
func view_hero(c) -> void:
	if cb == null or cb.is_over() or c == null or c.team != "party" or _mode == "deploy" \
			or _reaction_answer < 0:
		return
	if c == cb.current() and c.conscious():
		_stop_viewing()
		return
	_viewing = true
	_build_hero_menu(c)
	var res := _resources(c)
	_actor.text = "%s    [i]not their turn[/i]    AC %d    %s%s" % [
		"[b]%s[/b]" % c.cname, cb.effective_ac(c), _hp_bb(c), ("    " + res) if res != "" else ""]

func _stop_viewing() -> void:
	_viewing = false
	var cur = cb.current() if cb != null else null
	if cur != null and cur.team == "party" and cur.conscious() and not _advancing and not _busy:
		_build_hero_menu(cur)
	else:
		_set_buttons([])
	_refresh()

# T29 spellcaster resources: one pip row per slot level the caster actually has
# (● unspent, ○ spent) plus every feature pool by name, replacing the old
# "slots 2/3" counter that only ever reported level-1 slots.
func _resources(c) -> String:
	var bits: Array = []
	var maxes: Array = _slot_max.get(c.id, [])
	for i in c.slots.size():
		var mx: int = int(maxes[i]) if i < maxes.size() else int(c.slots[i])
		if mx <= 0:
			continue
		var left: int = int(c.slots[i])
		bits.append("L%d %s%s" % [i + 1, "●".repeat(left), "○".repeat(maxi(0, mx - left))])
	for pid in c.pools:
		var p: Dictionary = c.pools[pid]
		if int(p["max"]) > 0:
			bits.append("%s %d/%d" % [Effects.verb_label(pid), int(p["cur"]), int(p["max"])])
	return "  ".join(bits)

# One tile per combatant in initiative order: glyph over short name, team-tinted,
# the current turn boxed in gold and the dead greyed out.
func _build_order_strip() -> void:
	for c in _order.get_children():
		c.queue_free()
	_order_tiles.clear()
	_order_aimed.clear()
	var u := clampf(_zoom, 0.9, 1.4)
	for c in cb.order:
		var tile := PanelContainer.new()
		var base: StyleBox
		if c == cb.current():
			# whose turn it is: a gilt rule under the tile, nothing boxed
			var box := Icons.box(Color(0.79, 0.64, 0.35, 0.12), Color(0, 0, 0, 0), 0, 6, 4)
			box.border_color = Icons.COL_GOLD
			box.border_width_bottom = 3
			base = box
		else:
			base = Icons.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 4)
		tile.add_theme_stylebox_override("panel", base)
		tile.set_meta("base_box", base)
		_order_tiles[c.id] = tile
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tile.add_child(tv)
		var tint: Color = COL_PARTY if c.team == "party" else COL_FOE
		if c == cb.current():
			tint = Icons.COL_GOLD
		var g := Label.new()
		g.text = Icons.combatant_glyph(c)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", int(28 * u))
		g.add_theme_color_override("font_color", tint)
		tv.add_child(g)
		var nm := Label.new()
		nm.text = "%s (%d)" % [c.short_name(), c.init_roll]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", int(Icons.FS_SMALL * u))
		nm.add_theme_color_override("font_color", tint if c == cb.current() else Icons.COL_BODY)
		tv.add_child(nm)
		# The strip is still initiative order (cb.order, untouched) -- the name
		# label keeps the roll so you can read the actual initiative, and HP
		# shows alongside it rather than replacing it.
		var hp := Label.new()
		hp.text = "%d/%d" % [c.hp, c.max_hp]
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp.add_theme_font_size_override("font_size", int(Icons.FS_SMALL * u))
		hp.add_theme_color_override("font_color", _hp_color(c))
		tv.add_child(hp)
		if c.is_dead():
			tile.modulate = Color(1, 1, 1, 0.35)
		elif c.is_down():
			tile.modulate = Color(1, 1, 1, 0.6)
		if c.team == "party":   # #72
			tile.tooltip_text = "Click to look at %s's sheet" % c.short_name()
			tile.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					view_hero(c))
		_order.add_child(tile)
	_paint_order_aim(true)

# --- issue #29: what the aim is on, said on the turn strip ------------------
#
# Hovering a token mid-aim already shows its odds over its own head, but a fight
# is read off the strip at the top — whose turn, who is hurt, who is next — and
# nothing up there said which of those tiles the spell in hand was pointed at.
# A cone or a burst makes that worse: the hexes light up on the board, but which
# NAMES are standing in them is exactly the thing the strip knows and the board
# does not spell out.
#
# Who the aim currently lands on: {} when not aiming, or when the cursor is
# somewhere the verb cannot go.
func aimed_ids() -> Dictionary:
	var out := {}
	if cb == null or cb.is_over() or _tgt_verb.is_empty():
		return out
	var cur = cb.current()
	if cur == null or cur.team != "party" or not cur.conscious():
		return out
	match _mode:
		"target":
			for c in cb.combatants:
				if c.pos == _board._hover and _valid_target(cur, c):
					out[c.id] = true
		"area", "cone":
			var hexes: Array = _area_aim(cur)
			if hexes.is_empty():
				return out
			for c in cb.combatants:
				if not c.is_dead() and c.pos in hexes:
					out[c.id] = true
	return out

# Repaint only when the set actually changed — this is called off mouse motion.
func _paint_order_aim(force := false) -> void:
	var want := aimed_ids()
	if not force and want == _order_aimed:
		return
	_order_aimed = want
	for id in _order_tiles:
		var tile = _order_tiles[id]
		if not is_instance_valid(tile):
			continue
		if want.has(id):
			var box: StyleBoxFlat = (tile.get_meta("base_box") as StyleBoxFlat).duplicate()
			box.bg_color = Color(COL_FOE.r, COL_FOE.g, COL_FOE.b, 0.22)
			box.border_color = COL_FOE
			box.set_border_width_all(2)
			tile.add_theme_stylebox_override("panel", box)
		else:
			tile.add_theme_stylebox_override("panel", tile.get_meta("base_box"))

# Same three bands the token HP bar uses.
static func _hp_color(c) -> Color:
	var frac := float(c.hp) / maxf(1.0, float(c.max_hp))
	if frac < 0.33: return Color("d15750")
	if frac < 0.66: return Color("d9a441")
	return Color("5fbf6a")

# The actor line's HP readout, colored by the same three bands as the token's
# own bar — one glance tells you if the acting hero is in trouble.
static func _hp_bb(c) -> String:
	return "[color=#%s]♥ %d/%d[/color]" % [_hp_color(c).to_html(false), c.hp, c.max_hp]

# Action-economy badges: a filled glyph per resource still available this
# turn, gone (not just dimmed) once spent — the request was "more compact",
# so a spent resource takes zero space rather than a struck-through slot.
static func _econ_bb(c) -> String:
	var gold := Icons.COL_GOLD.to_html(false)
	var bits: Array = []
	if int(c.econ.get("action", 0)) > 0:
		bits.append("[color=#%s]Ⓐ[/color]" % gold)
	if int(c.econ.get("bonus", 0)) > 0:
		bits.append("[color=#%s]Ⓑ[/color]" % gold)
	bits.append("➤ %d" % int(c.econ.get("move_left", 0)))
	return " ".join(bits)

var _logged = 0
var _last_round = 1

# --- log colorization (presentation only; core/combat.gd stays plain text) ---
# Spans are found on the ORIGINAL line and only then spliced, so inserted bbcode
# is never re-scanned. First match of an overlapping pair wins, names first.
const VERB_COLORS := {
	"CRIT": "#ff6a4a", "CRITS": "#ff6a4a", "crits": "#ff6a4a",
	"hits": "#ffe0a0", "hit": "#ffe0a0",
	"misses": "#7f7f79", "miss": "#7f7f79",
	"moves": "#8fb7d8", "casts": "#9fd0ff", "uses": "#9fd0ff",
	"heals": "#8dffb0", "healed": "#8dffb0", "revives": "#8dffb0",
}
const COL_DICE := "#8fb7d8"
const COL_NUM := "#ffd24a"

static var _re_dice := RegEx.create_from_string(r"d20\[[^\]]*\]|\b\d+d\d+\b")
static var _re_num := RegEx.create_from_string(r"\b(\d+)\s+(?:damage|HP|hp|gold|XP)\b")
static var _re_verb := RegEx.create_from_string(r"\b(CRITS?|crits?|hits?|misses|miss|moves|casts|uses|heals|healed|revives)\b")

# `name_colors`: combatant name -> html colour. Returns bbcode for one log line.
static func colorize(line: String, name_colors: Dictionary) -> String:
	var spans: Array = []   # [start, end, color]
	var claim := func(a: int, b: int, col: String) -> void:
		for s in spans:
			if a < s[1] and s[0] < b:
				return
		spans.append([a, b, col])
	for nm in name_colors:
		var from := 0
		while true:
			var at := line.find(nm, from)
			if at < 0:
				break
			claim.call(at, at + nm.length(), String(name_colors[nm]))
			from = at + nm.length()
	for m in _re_dice.search_all(line):
		claim.call(m.get_start(), m.get_end(), COL_DICE)
	for m in _re_num.search_all(line):
		claim.call(m.get_start(1), m.get_end(1), COL_NUM)
	for m in _re_verb.search_all(line):
		claim.call(m.get_start(1), m.get_end(1), VERB_COLORS.get(m.get_string(1), COL_DICE))
	spans.sort_custom(func(a, b): return a[0] < b[0])
	var out := ""
	var cut := 0
	for s in spans:
		out += line.substr(cut, s[0] - cut)
		out += "[color=%s]%s[/color]" % [s[2], line.substr(s[0], s[1] - s[0])]
		cut = s[1]
	return out + line.substr(cut)

# Names as the colorizer wants them: longest first so "Vess the Quick" beats "Vess".
func _name_colors() -> Dictionary:
	var names: Array = []
	for c in cb.combatants:
		names.append(c)
	names.sort_custom(func(a, b): return a.cname.length() > b.cname.length())
	var d := {}
	for c in names:
		d[c.cname] = "#8fdc97" if c.team == "party" else "#e58a84"
	return d

func _flush_log() -> void:
	if cb.round_num != _last_round:
		_last_round = cb.round_num
		_logbox.append_text("\n[color=#6a6f80]─────────   ROUND %d   ─────────[/color]\n" % _last_round)
	var ncols := _name_colors()
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
			col = "#c9a45a"
		var body := colorize(line, ncols)
		if bold:
			body = "[b]%s[/b]" % body
		_logbox.append_text("[color=%s]%s[/color]\n" % [col, body])
		BugReport.note(line)
		_logged += 1

func _finish() -> void:
	var outcome: Dictionary = Encounter.resolve_outcome(cb, party)   # writes HP/pools/slots back to the party
	var res: String = cb.outcome()
	if res == "Defeat":
		_board.play_defeat()
	# #74: the host (world, site, campaign) tears this scene down the frame
	# `result` is set. With a screen to look at, the verdict is held behind a
	# tinted wash the player clicks through first; headless and FAST hand it
	# straight back, as they always did.
	if _fx_on:
		_show_wash(res, outcome)
	else:
		result = outcome
	_flush_log()
	_refresh()
	for c in _buttons.get_children():
		c.queue_free()
	if OS.is_debug_build():   # T29: replay/reseed are dev tools, not shipped UI
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
		_logbox.append_text("[color=#c9a45a]+%d XP, +%d gold.[/color]\n" % [result["xp"], result["gold"]])
		# What came off the bodies, by name and in its rarity colour. It goes
		# into the shared stash either way (campaign.gd's finish_combat /
		# world.gd's _bank) — but loot that lands silently is loot nobody knows
		# they have.
		var taken: Array = result.get("loot", [])
		if not taken.is_empty():
			var names: Array = []
			for id in taken:
				names.append(Icons.item_img_bb(String(id)) + Icons.item_bb(String(id), Campaign.item_name(String(id))))
			_logbox.append_text("[color=#c9a45a]Taken from the dead:[/color] %s\n" % ", ".join(names))

# --- #74: the verdict, held for a click -------------------------------------
var _wash: Control = null
var _wash_age := 0.0
var _wash_result: Dictionary = {}

func _show_wash(res: String, outcome: Dictionary) -> void:
	_wash_result = outcome
	_wash_age = 0.0
	_wash = Control.new()
	_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_STOP
	_wash.draw.connect(_draw_wash.bind(res))
	_wash.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_dismiss_wash())
	_hud_layer.add_child(_wash)

func _dismiss_wash() -> void:
	if _wash == null:
		return
	_wash.queue_free()
	_wash = null
	result = _wash_result

func _draw_wash(res: String) -> void:
	var won := res == "Victory"
	var t := _wash_age
	var k := clampf(t / 0.8, 0.0, 1.0)
	var fz := clampf(_zoom, 0.9, 1.4)
	var mid: Vector2 = _wash.size * 0.5
	# The board's own DEFEAT slam already plays underneath; the victory one is
	# drawn here, in the same voice: a wash, one word, one line under it.
	if won:
		_wash.draw_rect(Rect2(Vector2.ZERO, _wash.size), Color(0.10, 0.09, 0.02, 0.55 * k))
		var slam := 1.0 + 1.6 * pow(1.0 - clampf(t / 0.30, 0.0, 1.0), 2)
		Board._centered_on(_wash, "V I C T O R Y", mid, int(54 * fz * slam),
			Color(Icons.COL_GOLD, clampf(t / 0.12, 0.0, 1.0)))
		Board._centered_on(_wash, "+%d XP, +%d %s" % [int(_wash_result.get("xp", 0)),
			int(_wash_result.get("gold", 0)), Icons.GP], mid + Vector2(0, 46 * fz), int(18 * fz),
			Color(Icons.COL_BODY, clampf((t - 0.5) / 0.6, 0.0, 1.0)))
	Board._centered_on(_wash, "click to continue", mid + Vector2(0, 90 * fz), int(14 * fz),
		Color(Icons.COL_BODY, 0.7 * clampf((t - 1.2) / 0.6, 0.0, 1.0)))

# The pause before a monster acts, so its turn is a beat and not a jump cut.
# Raised with the strike timings below it: at 0.5 the next turn started while
# the last swing was still on screen, which is what stacked several turns into
# one unreadable blur. Divided by the pace setting like every other wait.
const TURN_BEAT := 0.75

const BUTTON_ROWS := 3

func _process(dt: float) -> void:
	if _wash != null:
		_wash_age += dt
		_wash.queue_redraw()
	if _board:
		_board.tick(dt * _anim)
	if _hud_overlay:
		_hud_overlay.queue_redraw()
	if _bscroll:   # grow with the wrapped rows, up to BUTTON_ROWS, then scroll
		var row := BTN_SIZE.y * clampf(_zoom, 0.9, 1.4) + 6.0
		_bscroll.custom_minimum_size.y = minf(_buttons.get_combined_minimum_size().y,
			row * BUTTON_ROWS)

# T-hud: HP bar + condition tags for every living combatant, painted on a
# CanvasLayer above Board and everything Board parents (Figures3D included) —
# see Board._paint_token_hud's header comment for why this can't just call
# back into Board's own drawing code. Coordinates are Board-local; draw_set_
# transform(origin) once up front instead of adding board.global_position to
# every point below.
func _draw_hud_overlay() -> void:
	if cb == null or _board == null:
		return
	_hud_overlay.draw_set_transform(_board.global_position)
	var s: float = hex_px
	var fz := clampf(_zoom, 0.75, 1.7)
	for c in cb.combatants:
		if c.is_dead():
			continue
		var p: Vector2 = _board._tok.get(c.id, _board._pix(c.pos)) + _board._lunge(c.id)
		var rad := s * 0.62
		var tp := p if c.is_down() else p + Vector2(0, -rad * 0.55)
		Board._paint_token_hud(_hud_overlay, c, _board._hp.get(c.id, float(c.hp)), p, tp, s, rad, fz)

	# The attack/save/shove odds chip: same layer as the HP bar above, and for
	# the same reason — a Figures3D model is a Board child, so it draws on top
	# of anything Board paints regardless of ordering, and a tall figure (the
	# ranger rig, notably) could stand over the chip's fixed screen offset and
	# block the readout the player is hovering to see.
	var cur = cb.current()
	var hero_turn: bool = cur and cur.team == "party" and cur.conscious()
	if hero_turn and _mode == "target":
		for c in cb.combatants:
			if not _valid_target(cur, c):
				continue
			var tp2 := _board._pix(c.pos)
			var hot: bool = c.pos == _board._hover
			var txt: String = target_readout(cur, c)
			var fs := int((20 if hot else 15) * fz)
			var w := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var chip := tp2 + Vector2(-w / 2.0, -s * 1.35)
			_hud_overlay.draw_rect(Rect2(chip - Vector2(5, fs), Vector2(w + 10, fs + 8)), Color(0, 0, 0, 0.72))
			_hud_overlay.draw_string(ThemeDB.fallback_font, chip, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color("ffe27a") if hot else Color("d7d7cf"))

	# T26 barks, up here for the same reason the two above are: what somebody
	# says over their own hex was being covered by whoever was standing in
	# front of them. Still plain text over the speaker's hex at the offset it
	# always had — only the layer changed — with a dropped shadow now that it
	# lands on top of the figure art rather than behind it.
	for id in _board._barks:
		var bk: Dictionary = _board._barks[id]
		var col := Color("ffe9b0")
		col.a = clampf((Board.BARK_TTL - bk.age) / 0.5, 0.0, 1.0)
		var at: Vector2 = _board._tok.get(id, Vector2.ZERO) + Vector2(0, -s * 1.15)
		var fs2 := int(14 * fz)
		var shade := Color(0, 0, 0, col.a * 0.8)
		Board._centered_on(_hud_overlay, String(bk.text), at + Vector2(1, 1), fs2, shade)
		Board._centered_on(_hud_overlay, String(bk.text), at, fs2, col)

	# T-dmg: the damage numbers, up here for the same reason as the three above
	# — a figure standing in front used to cover the number over the body it
	# was hitting. They are the only damage readout the player gets for a foe's
	# attack or for any area spell (show_reveal fires on the hero's
	# single-target path alone), so this is the half of the fight that most
	# needs to be legible.
	var rv = _board._reveal
	# "" would be a live id if a combatant ever had one, so the reveal's absence
	# is checked on rv itself rather than smuggled through an empty string.
	var told: String = String(rv.tid) if rv != null else ""
	for f in _board._floats:
		# The reveal's headline already reads "HIT  7" over this same body, and
		# at these sizes the two land on top of each other. One event, one
		# number: the headline wins where it exists, which is the hero's
		# single-target path and nowhere else.
		if rv != null and String(f.id) == told:
			continue
		var ffs := float(f.fs) * fz
		var fcol: Color = f.color
		fcol.a = clampf(1.0 - f.age / Board.FLOAT_TTL, 0.0, 1.0)
		# Clear of the head, not on it: the offset carries half the glyph now
		# that the glyph is not a fixed 18px any more.
		Board._shout(_hud_overlay, String(f.text),
			f.pos + Vector2(0, -(20.0 + ffs * 0.5 + f.age * 34.0)), int(ffs), fcol)

	# The roll reveal last, so the outcome of a blow sits over everything.
	if rv != null and _board._tok.has(rv.tid):
		Board._paint_reveal(_hud_overlay, rv, _board._tok[rv.tid], s, fz)

func _log_width() -> float:
	return clampf(size.x * 0.26, 260.0, 380.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _logwrap:
		_logwrap.custom_minimum_size.x = _log_width()

# =====================================================================
#  T32 walkthrough — presentation only. It spotlights a region of this
#  same screen; the fight underneath is an ordinary fight, resolved by
#  the ordinary code.
#
#  A card that names something you can do (Tutorial.STEPS' `try`) hands
#  its own region back while it is up: the spotlight becomes a hole in
#  the dim, so the board takes the click that moves you and the bar takes
#  the hover that pops a tooltip, through the same handlers play goes
#  through. Everything outside that region stays blocked, the goblin
#  still waits (see _advance), and nothing is a gate — Next leaves any
#  card whether or not the practice was done.
# =====================================================================

var _walk: Walk = null      # the live overlay, null whenever the tutorial isn't up
var _walk_pending := false  # tutorial armed in _ready, waiting on the first hero turn

# Which control each step in Tutorial.STEPS points at.
func _walk_target(key: String) -> Control:
	match key:
		"log": return _logwrap
		"order": return _order.get_parent()
		"actions": return _bscroll
		"actor": return _actor
	return _board

func _walk_show(i: int) -> void:
	_walk_end()
	if i >= Tutorial.STEPS.size():
		return
	var step: Dictionary = Tutorial.STEPS[i]
	var practice: Dictionary = step.get("try", {})
	_walk = Walk.new()
	_walk.target = _walk_target(String(step["target"]))
	# STOP, with Walk._has_point cutting the spotlight out of it on a step with
	# something to practise: everything else on the screen is still deaf.
	_walk.mouse_filter = Control.MOUSE_FILTER_STOP
	_walk.act = String(practice.get("act", ""))
	_walk.live = _walk.act != ""
	_walk.keys = bool(practice.get("keys", false))
	_walk.done_text = String(practice.get("done", ""))
	# On _hud_layer rather than on this Control, and added after _hud_overlay so
	# it draws after it. T-hud put the HP bars and condition glyphs on a
	# CanvasLayer above every ordinary child, which included this overlay: a
	# card parked over a token had that token's HP bar painted across its own
	# title. The dim belongs over the HUD too — a bright HP bar in the darkened
	# half of the screen is exactly what the spotlight is meant to remove.
	# A CanvasLayer breaks the Control chain a theme is inherited down, so the
	# combat screen's own theme is handed over rather than left to the default.
	_walk.theme = theme
	_hud_layer.add_child(_walk)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Icons.box(Icons.COL_INK, Icons.COL_GOLD_EDGE, 0, 18, 14))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var head := Label.new()
	head.text = "%s   (%d/%d)" % [step["title"], i + 1, Tutorial.STEPS.size()]
	head.theme_type_variation = "Head"
	col.add_child(head)

	var body := Label.new()
	body.text = String(step["text"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WALK_CARD_W, 0)
	body.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(body)

	if _walk.live:
		var hint := Label.new()
		hint.text = "▸  " + String(practice.get("hint", ""))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(WALK_CARD_W, 0)
		hint.add_theme_color_override("font_color", Icons.COL_ACCENT)
		col.add_child(hint)
		_walk.hint = hint

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.pressed.connect(_walk_end)
	row.add_child(skip)
	var next := Button.new()
	next.text = "Start fighting  →" if i == Tutorial.STEPS.size() - 1 else "Next  →"
	next.pressed.connect(func(): _walk_show(i + 1))
	row.add_child(next)
	col.add_child(row)

	_walk.card = card
	_walk.add_child(card)

# The player did the thing the open card invited. Called from the ordinary
# handlers — the move, the hover, the list — rather than from anything the
# walkthrough owns, so there is no second, tutorial-only path through any of
# it, and a step nobody is on costs one comparison.
func _walk_try(act: String) -> void:
	if _walk == null or _walk.done or _walk.act != act:
		return
	_walk.done = true
	if _walk.hint != null:
		_walk.hint.text = "✓  " + _walk.done_text
		_walk.hint.add_theme_color_override("font_color", WALK_DONE)

# Which keys survive the walkthrough. The view controls always — zoom and pan
# move nothing in the fight, and a card is easier to read over a board you have
# framed yourself. The bar's own keys only while a step is inviting them, since
# a number is the other half of "press [2] to open its list". Never Space or
# [0]: the turn must not be handed over under a card, because _advance holds
# the goblin while the overlay is up and would sit there waiting for it.
const WALK_VIEW_KEYS := [KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT, KEY_HOME,
	KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
const WALK_BAR_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_TAB, KEY_ESCAPE, KEY_B]

func _walk_key_ok(k: int) -> bool:
	if k in WALK_VIEW_KEYS:
		return true
	return _walk != null and _walk.keys and k in WALK_BAR_KEYS

func _walk_end() -> void:
	if _walk != null:
		_walk.queue_free()
		_walk = null
	# Practice can leave the bar inside a list, or in aim with the board behind
	# the dim it cannot reach. Neither is a state to hand the next card or,
	# after Skip and after the last step, ordinary play — so the bar goes back
	# to the nine slots the way Esc would put it.
	if (_submenu == "" and _mode == "idle") or _mode == "deploy" or cb == null or cb.is_over():
		return
	if cb.turn_idx < 0 or cb.turn_idx >= cb.order.size():
		return   # combat.gd's current() indexes straight in — see bug_context()
	var up = cb.current()
	if up.team == "party" and up.conscious():
		_build_hero_menu(up)

const WALK_CARD_W := 460.0
const WALK_DONE := Color("8dffb0")   # the ✓ line, the log's own green for something that landed

# Dims everything but the step's target, outlines it, and parks the card clear of it.
class Walk extends Control:
	var target: Control
	var card: Control
	var live := false        # the spotlight is a hole: its region takes mouse input
	var keys := false        # ...and the bar's keys are unlocked too
	var act := ""            # the practice this step waits for, "" for a card that only reads
	var done := false
	var done_text := ""
	var hint: Label = null
	var _last := Rect2()
	const DIM := Color(0.02, 0.03, 0.05, 0.72)

	# The whole overlay is one full-screen Control, so "everything but the
	# spotlight is blocked" is simply this: inside the hole the overlay is not
	# there, and the click or the motion falls through to the board, or to the
	# bar, on the canvas below. The card is a child, and Godot picks children
	# before their parent, so its own buttons keep working even on the steps
	# where it has to sit over the lit region.
	func _has_point(p: Vector2) -> bool:
		return not (live and _spot().grow(4.0).has_point(p))

	func _process(_dt: float) -> void:
		var vp := get_viewport_rect().size
		if size != vp:              # no Control parent to anchor to — see _walk_show
			size = vp
			queue_redraw()
		if card == null:
			return
		var r := _spot()
		if r != _last:              # the layout settles a frame or two after the step opens
			_last = r
			queue_redraw()
		elif live and not done:
			queue_redraw()          # the ring breathes while the step's practice is outstanding
		var cs := card.get_combined_minimum_size()
		var p := Vector2((size.x - cs.x) * 0.5, r.end.y + 16.0)
		if p.y + cs.y > size.y - 8.0:                       # no room below — go above
			p.y = r.position.y - cs.y - 16.0
		card.position = p.clamp(Vector2(8, 8), (size - cs - Vector2(8, 8)).max(Vector2(8, 8)))
		card.size = cs

	func _spot() -> Rect2:
		if target == null or not is_instance_valid(target):
			return Rect2(size * 0.5, Vector2.ZERO)
		return Rect2(target.global_position - global_position, target.size)

	func _draw() -> void:
		var r := _spot().grow(4.0)
		draw_rect(Rect2(0, 0, size.x, r.position.y), DIM)
		draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), DIM)
		draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), DIM)
		draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), DIM)
		# A live region is ringed brighter and breathing, a read-only one flat:
		# the outline is the only thing on screen that can say "this half of the
		# screen is yours again" before the player has tried it.
		var ring := Icons.COL_GOLD
		if live:
			ring = Icons.COL_GOLD.lerp(Color.WHITE, 0.35)
			if not done:
				ring.a = 0.65 + 0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0))
		draw_rect(r, ring, false, 4.0 if live else 3.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

# =====================================================================
#  Board — the hex map. Draws tiles, tokens, HP bars, highlights, juice.
# =====================================================================
class Board extends Control:
	var main
	var cb
	var _origin := Vector2.ZERO
	# The ground (slab, floor texture, mottling, seams, foliage) is the same
	# picture every frame until the layout or the board changes, and it was
	# ~9 ms of the ~11 ms a Board redraw cost (124 hexes × a dozen draw calls,
	# in GDScript) — every frame of every slide, float and flash. It lives on
	# this child, drawn behind the Board, and tick() redraws it only when
	# what it depends on moves. Board._draw keeps what changes per frame.
	class Ground extends Control:
		var board
		func _draw() -> void:
			if board.cb != null:
				board._paint_ground(self)
	var _ground := Ground.new()
	var _ground_key := 0
	var _field := {}      # move_field of the hero whose turn it is, memoised
	var _provoke := {}    # ...and the hexes a walk there would draw an OA on
	var _field_key := 0

	func _init() -> void:
		_ground.board = self
		_ground.show_behind_parent = true
		_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ground)
	var _auto_fit := false    # zoom-to-fit each layout until the user zooms (new fight, Home)
	var _tok := {}        # id -> displayed pixel pos (for slide)
	var _slide := {}      # id -> {from, to, t, dur}: the traversal in progress, see tick()
	var _view_origin := Vector2(1e9, 1e9)   # the view _tok/_slide were last laid out in — see _rebase_view
	var _view_hex := 0.0
	var _hp := {}         # id -> displayed hp value
	# T-dmg: the hp each body was last seen at, so a hit spawns ONE number. _hp
	# is the bar's eased value and lags for ~20 frames; this one snaps.
	var _dmg_goal := {}   # id -> hp at the last damage event
	# `fs`, never `size`: Dictionary.size() owns that name and f.size would
	# reach the method, not the entry.
	var _floats: Array = []   # {id, pos, text, color, age, fs}
	var _flash := {}     # id -> ttl
	var _hover := Vector2i(999, 999)
	var _hover_pt := Vector2(1e9, 1e9)   # un-iso'd pixel point under the mouse, for corner aiming

	# The aim for an area verb at the current hover: a hex, a corner (three
	# hexes) or the aimed hex of a line; null when the mouse is off the board.
	func aim_target(kind: String):
		if not (_hover in cb.board["hexes"]):
			return null
		if kind == "corner":
			return Hex.corner_at(_hover_pt, main.hex_px)
		return _hover
	var _reveal = null   # {tid, dice, nat, bonus, total, ac, hit, crit, age}
	var _barks := {}     # id -> {text, age}; drained from cb.barks (T26)
	const BARK_TTL := 2.2
	# T28 attack FX, cosmetic only: {kind, id, from, to, hexes, age, ttl}
	var _fx: Array = []
	# How long a strike is on screen. Raised across the board: at 0.30 a melee
	# swing was over before the eye found it, which is most of why a fight read
	# as "fast mode" even at 1x. Every one of these is divided by the pace
	# setting through Board.tick's own dt, so Instant still skips them.
	const FX_TTL := {"melee": 0.46, "ranged": 0.52, "spell": 0.70}
	# T-dmg: the damage number's size range before the zoom multiplies it. The
	# floor is the old flat 18 plus the weight it was missing; the ceiling is
	# what a blow that takes half a body deserves. The roll reveal's headline
	# (HIT / MISS / CRIT!) sits between them.
	const FLOAT_FS_MIN := 23.0
	const FLOAT_FS_MAX := 42.0
	const REVEAL_FS := 32.0
	# How long a damage number lives. Unchanged at 1.1s — named here because the
	# reaper and the fade now have to agree on it from two different scripts.
	const FLOAT_TTL := 1.1
	var _defeat := -1.0   # T29: seconds since the party wipe, -1 = not wiped

	func play_defeat() -> void:
		_defeat = 0.0
		queue_redraw()

	# The wipe: the board lurches, a blood-red wash floods in behind a shockwave
	# ring, and DEFEAT slams down over it.
	func _draw_defeat(fz: float) -> void:
		var t := _defeat
		var wash := clampf(t / 0.9, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.02, 0.03, 0.62 * wash))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.35 * wash))
		var mid := size * 0.5
		if t < 0.9:                       # shockwave out of the centre
			var k := t / 0.9
			draw_arc(mid, size.x * 0.75 * k, 0, TAU, 48,
				Color(1.0, 0.42, 0.30, 0.55 * (1.0 - k)), 6.0 * (1.0 - k))
		var slam := 1.0 + 2.2 * pow(1.0 - clampf(t / 0.30, 0.0, 1.0), 2)
		_centered("D E F E A T", mid, int(54 * fz * slam),
			Color(0.92, 0.22, 0.18, clampf(t / 0.12, 0.0, 1.0)))
		_centered("the party falls…", mid + Vector2(0, 46 * fz), int(16 * fz),
			Color(0.86, 0.74, 0.68, clampf((t - 0.6) / 0.7, 0.0, 1.0)))

	# Queued by main only when FX are on (never under SORCMERC_FAST/headless).
	func play_fx(kind: String, id: String, from_hx: Vector2i, to_hx: Vector2i, hexes: Array = []) -> void:
		_fx.append({"kind": kind, "id": id, "from": from_hx, "to": to_hx, "hexes": hexes,
			"age": 0.0, "ttl": float(FX_TTL.get(kind, 0.35))})
		queue_redraw()

	# How far the lunging attacker's token is pushed off its hex right now.
	# The melee step-in. sin(t * PI) is a symmetric there-and-back, which reads
	# as a nudge; a swing wants to go out fast and come back slow, so the curve
	# is skewed to peak at about a third of the way through and recover over the
	# rest. Reaches further too — 0.55 of a hex barely left the tile.
	const LUNGE_REACH := 0.66
	func _lunge(id: String) -> Vector2:
		for f in _fx:
			if f.kind == "melee" and f.id == id:
				var t: float = clampf(f.age / f.ttl, 0.0, 1.0)
				var d: Vector2 = _pix(f.to) - _pix(f.from)
				if d.length() < 0.01:
					return Vector2.ZERO
				return d.normalized() * (sin(pow(t, 0.62) * PI) * main.hex_px * LUNGE_REACH)
		return Vector2.ZERO

	func _draw_fx(s: float) -> void:
		for f in _fx:
			var t: float = clampf(f.age / f.ttl, 0.0, 1.0)
			match String(f.kind):
				"ranged":
					var a: Vector2 = _pix(f.from)
					var b: Vector2 = _pix(f.to)
					draw_line(a, a.lerp(b, t), Color(1.0, 0.92, 0.66, 0.35 * (1.0 - t)), 2.0)
					draw_circle(a.lerp(b, t), s * 0.13, Color(1.0, 0.92, 0.66, 1.0 - t * 0.4))
				"spell":
					var col := Color(0.72, 0.86, 1.0, 1.0 - t)
					for hx in f.hexes:              # AoE: light up the swept hexes
						draw_colored_polygon(_hex_poly(_pix(hx), s - 3.0), Color(col.r, col.g, col.b, 0.35 * (1.0 - t)))
					var c: Vector2 = _pix(f.to)
					draw_polyline(_disc(c, s * (0.25 + 1.0 * t), true), col, 3.0)
					draw_circle(c, s * 0.3 * (1.0 - t), Color(col.r, col.g, col.b, 0.5 * (1.0 - t)))

	func reset(_cb) -> void:
		cb = _cb
		_defeat = -1.0
		_auto_fit = true
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # the floor texture wraps across hexes
		_tok.clear(); _slide.clear(); _hp.clear(); _floats.clear(); _flash.clear()
		_dmg_goal.clear()
		_view_origin = _origin; _view_hex = main.hex_px   # fresh _pix()es are in this view
		for c in cb.combatants:
			_tok[c.id] = _pix(c.pos)
			_hp[c.id] = float(c.hp)
		_barks.clear()
		queue_redraw()

	func slide_from(c) -> void:
		_rebase_view()   # a fresh _pix() must be in the same view as the rest
		if not _tok.has(c.id):
			_tok[c.id] = _pix(c.pos)

	func flash(_hx: Vector2i) -> void:
		pass  # target flash handled per-token on hp change

	func show_reveal(tid: String, res: Dictionary, head: Array) -> void:
		_reveal = {
			"tid": tid, "dice": res.get("dice", []), "nat": res.get("nat", 0),
			"bonus": res.get("bonus", 0), "total": res.get("total", 0), "ac": res.get("ac", 0),
			"head": String(head[0]), "hcol": head[1] as Color, "age": 0.0,
		}
		if res.get("hit", false):
			_flash[tid] = 0.35
		queue_redraw()

	# zoom keeping the hex under `sp` (screen point) roughly fixed
	func _zoom_at(sp: Vector2, factor: float) -> void:
		var anchor := _unpix(sp)
		main.set_zoom(main._zoom * factor)
		_layout()
		main.pan_by(sp - _pix(anchor))

	func _layout() -> void:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for hx in cb.board["hexes"]:
			var p := _iso(Hex.to_pixel(hx, main.hex_px))
			mn = mn.min(p); mx = mx.max(p)
		# centres only — pad by a hex so the outermost tiles (and their labels) sit inside the frame
		var pad: Vector2 = Vector2(1.0, ISO_SQUASH) * float(main.hex_px)
		var span: Vector2 = mx - mn + pad * 2.0
		mn -= pad
		# TFT-style: the whole map is on screen at once. Zoom down from ZOOM_DEFAULT
		# until it fits (once per fight / Home), never up — small maps stay readable.
		# Re-evaluated every layout (the rect settles over the first frames and
		# font scale feeds back into it); the user's own zoom switches it off.
		if _auto_fit and size.y > 0.0:
			var fit: float = main._zoom * minf((size.x - 60.0) / span.x, (size.y - 40.0) / span.y)
			var z := clampf(minf(main.ZOOM_DEFAULT, fit), 0.45, 3.0)
			if not is_equal_approx(z, main._zoom):
				main._zoom = z
				main._apply_ui_scale()
				_layout()
				return
		# keep the board from being panned entirely off-screen
		var lim: Vector2 = (size + span) * 0.5 - Vector2(90, 60)
		lim = lim.max(Vector2.ZERO)
		main._pan = main._pan.clamp(-lim, lim)
		_origin = (size - span) * 0.5 - mn + main._pan

	# --- isometric projection ------------------------------------------
	# Purely a _draw()-time view transform: hex.gd still speaks flat-top axial
	# pixels, we just tilt the plane those pixels live on. Linear, so projecting
	# an offset and adding it to a projected centre == projecting the world point.
	# The camera: yaw the ground plane by ISO_YAW, then squash it vertically —
	# ISO_SQUASH is the sine of the pitch, so 0.45 ≈ looking down from ~27°,
	# the flat wide RTS angle rather than a steep 45° overhead.
	# ponytail: fixed camera. Make these vars if it ever needs to orbit/tilt.
	const ISO_YAW := -30.0    # long axis of the strip runs left-right, TFT-style; was 35
	const ISO_SQUASH := 0.71    # sin(45°): a TFT-style three-quarter view; was 0.38 (22°)
	const ISO_GAIN := 1.85    # the whole plane, scaled to fill the viewport

	func _iso(v: Vector2) -> Vector2:
		var r := v.rotated(deg_to_rad(ISO_YAW)) * ISO_GAIN
		return Vector2(r.x, r.y * ISO_SQUASH)

	func _iso_inv(v: Vector2) -> Vector2:
		return Vector2(v.x, v.y / ISO_SQUASH).rotated(-deg_to_rad(ISO_YAW)) / ISO_GAIN

	func _pix(hx: Vector2i) -> Vector2:
		return _origin + _iso(Hex.to_pixel(hx, main.hex_px))

	# screen point -> hex, the inverse of _pix
	func _unpix(sp: Vector2) -> Vector2i:
		return Hex.from_pixel(_iso_inv(sp - _origin), main.hex_px)

	# The native hover popup, for the tiles that change the rules. A plain
	# hex says nothing, so the popup only ever appears over something worth
	# reading. Static so a test can ask about a board without a screen.
	func _get_tooltip(at: Vector2) -> String:
		return hex_tip(cb, _unpix(at)) if cb != null else ""

	static func hex_tip(combat, hx: Vector2i) -> String:
		if combat == null or not (hx in combat.board["hexes"]):
			return ""
		var lines: PackedStringArray = []
		var o: Dictionary = combat.object_at(hx)
		if not o.is_empty():
			var what: String = String(o["type"]).capitalize()
			var h: Dictionary = o.get("hazard", {})
			if int(o.get("hp", 0)) > 0:
				what += " — smash it from beside it (one action, %d HP)" % int(o["hp"])
				if o.get("explosive", false):
					what += "; it bursts for %s %s to everything around it" % [h.get("dice", "2d6"), h.get("damage_type", "fire")]
				what += "."
			elif not h.is_empty():
				what += " — a hazard. Shove somebody standing beside it in for %s %s." % [h.get("dice", "2d6"), h.get("damage_type", "fire")]
			elif o.get("blocks_movement", false):
				what += " — in the way. Nobody can stand here."
			else:
				what += " — light and nothing more."
			lines.append(what)
		if combat.is_cover(hx):
			lines.append("Half cover — +2 AC and +2 on Dexterity saves for whoever stands here.")
		if hx in combat._rough():
			lines.append("Rough ground — every step here costs two.")
		return "\n".join(lines)

	func _hex_poly(center: Vector2, s: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i)
			pts.append(center + _iso(Vector2(cos(a), sin(a)) * s))
		return pts

	# A ring of points. `flat` lays it on the board plane (an ellipse on screen);
	# without it you get a true screen circle, for things that face the camera.
	func _ring(center: Vector2, r: float, flat := true, closed := false, segs := 32) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in segs:
			var v := Vector2(cos(TAU * i / segs), sin(TAU * i / segs)) * r
			pts.append(center + (_iso(v) if flat else v))
		if closed:
			pts.append(pts[0])
		return pts

	# A circle lying flat on the board plane, i.e. an ellipse on screen.
	func _disc(center: Vector2, r: float, closed := false) -> PackedVector2Array:
		return _ring(center, r, true, closed)

	# --- shading helpers -------------------------------------------------
	# The light: up and to the left, so every highlight in the scene agrees.
	const LIGHT := Vector2(-0.30, -0.34)

	# A radial gradient, as a triangle fan from `apex` out to `rim` with the
	# vertex colours interpolated across each triangle. Offsetting the apex
	# toward the light gives an off-centre hotspot, which is what makes a disc
	# read as a sphere rather than a coin. No shader, no texture, no per-frame
	# allocation beyond the fan itself.
	func _fan(canvas: CanvasItem, apex: Vector2, rim: PackedVector2Array, inner: Color, outer: Color) -> void:
		var n := rim.size()
		var cols := PackedColorArray([inner, outer, outer])
		var uv := PackedVector2Array()
		for i in n:
			canvas.draw_primitive(PackedVector2Array([apex, rim[i], rim[(i + 1) % n]]), cols, uv)

	# A soft drop shadow: three ellipses, each wider and fainter than the last.
	# Cheaper than a blur pass and, at these sizes, indistinguishable from one.
	func _soft_shadow(canvas: CanvasItem, at: Vector2, r: float, strength := 1.0) -> void:
		for i in 3:
			canvas.draw_colored_polygon(_disc(at, r * (1.0 + 0.26 * i)),
				Color(0.02, 0.01, 0.04, strength * (0.20 - 0.05 * i)))

	# How a token covers ground. This used to be exponential smoothing at a fixed
	# rate — `cur.lerp(target, dt * 12)` — which has two problems and they are
	# both "no weight". It has no idea how far the token is going, so a six-hex
	# dash and a one-hex sidestep take the same quarter of a second; and it
	# starts at full speed and creeps into the destination, which is the exact
	# opposite of how something with mass moves.
	#
	# A token now crosses the board at a speed measured in HEXES, eased in and
	# out: a dash reads as ground covered, a step reads as a step, and both
	# start heavy and settle rather than snapping and drifting.
	const TOKEN_HEXES_PER_SEC := 6.0
	const STEP_MIN := 0.20    # even a one-hex shuffle gets this long
	const STEP_MAX := 1.10    # ...and the longest dash is not a journey

	static func _ease_move(u: float) -> float:
		return u * u * (3.0 - 2.0 * u)    # smoothstep: lean in, cruise, settle

	# The point `d` pixels along the polyline `pts`.
	static func _along(pts: Array, d: float) -> Vector2:
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var seg := a.distance_to(b)
			if d <= seg or i == pts.size() - 1:
				return a.lerp(b, clampf(d / maxf(seg, 0.001), 0.0, 1.0))
			d -= seg
		return pts[-1]

	# #71/#78: _tok and _slide are screen pixels, and a pan or a zoom moves the
	# screen under them. Left alone, every token then "walked" to its new spot
	# — lagging behind the drag, and turning its figure to face the drag. The
	# projection is affine in _origin and hex_px, so the stored points are
	# carried over exactly rather than animated.
	func _rebase_view() -> void:
		var hx: float = main.hex_px
		if _view_origin == _origin and is_equal_approx(_view_hex, hx):
			return
		if _view_hex > 0.0:
			var k: float = hx / _view_hex
			var map := func(q: Vector2) -> Vector2: return _origin + (q - _view_origin) * k
			for id in _tok:
				_tok[id] = map.call(_tok[id])
			for id in _slide:
				var s: Dictionary = _slide[id]
				s["from"] = map.call(s["from"]); s["to"] = map.call(s["to"])
				s["pts"] = s["pts"].map(map); s["len"] = float(s["len"]) * k
			for f in _floats:
				f["pos"] = map.call(f["pos"])
		_view_origin = _origin
		_view_hex = hx

	func tick(dt: float) -> void:
		if cb == null:
			return
		_rebase_view()
		var k := clampf(dt * 12.0, 0.0, 1.0)
		var dirty := false
		for c in cb.combatants:
			var target := _pix(c.pos)
			var cur: Vector2 = _tok.get(c.id, target)
			var slide: Dictionary = _slide.get(c.id, {})
			if slide.is_empty() or not (slide["to"] as Vector2).is_equal_approx(target):
				# A walk follows its route hex by hex; a shove or a teleport cuts straight.
				var pts: Array = [cur]
				var walk: Array = cb.walks.get(c.id, [])
				cb.walks.erase(c.id)
				if walk.size() > 2 and walk[-1] == c.pos:
					for hx in walk.slice(1):
						pts.append(_pix(hx))
				else:
					pts.append(target)
				var length := 0.0
				for i in range(1, pts.size()):
					length += (pts[i] as Vector2).distance_to(pts[i - 1])
				slide = {"from": cur, "to": target, "pts": pts, "len": length, "t": 0.0,
					"dur": clampf(length / maxf(1.0, main.hex_px) / TOKEN_HEXES_PER_SEC, STEP_MIN, STEP_MAX)}
				_slide[c.id] = slide
			if cur.distance_to(target) > 0.5 and float(slide["t"]) < float(slide["dur"]):
				slide["t"] = minf(float(slide["dur"]), float(slide["t"]) + dt)
				_tok[c.id] = _along(slide["pts"], float(slide["len"]) * _ease_move(float(slide["t"]) / float(slide["dur"])))
				dirty = true
			else:
				_tok[c.id] = target
			# T-dmg: one number per blow. This used to hang off the bar's lerp
			# below, which fires every frame the bar is still travelling — so a
			# 14-damage hit drew 21 numbers stacked inside 11 px, each carrying
			# the *remaining* gap rather than the damage, counting down through
			# the colour bands to a pile of "-0" in yellow. The newest drew last
			# and opaque, so "-0" was what the player actually read. Worse the
			# slower the pace (39 numbers at Weighty) and worse the faster the
			# monitor (53 at 144 fps); at Instant k clamps to 1 and it was
			# correctly one, which is why the headless robots never caught it.
			# docs/spike-damage-numbers.md has the measurement.
			# First sight primes the latch and reports nothing — a body walking
			# onto the board has not just taken the hp it happens to be on. It
			# has to be a real write: defaulting to c.hp without storing it
			# would re-prime every frame and never see a blow at all.
			if not _dmg_goal.has(c.id):
				_dmg_goal[c.id] = float(c.hp)
			elif not is_equal_approx(float(_dmg_goal[c.id]), float(c.hp)):
				if float(c.hp) < float(_dmg_goal[c.id]):
					_spawn_float(c, float(_dmg_goal[c.id]) - float(c.hp))
					_flash[c.id] = 0.35
				_dmg_goal[c.id] = float(c.hp)
			var hv: float = _hp.get(c.id, float(c.hp))
			if absf(hv - c.hp) > 0.15:
				_hp[c.id] = lerpf(hv, float(c.hp), k); dirty = true
			else:
				_hp[c.id] = float(c.hp)
		for f in _floats:
			f.age += dt; dirty = true
		_floats = _floats.filter(func(f): return f.age < FLOAT_TTL)
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
		if _defeat >= 0.0 and _defeat < 3.0:
			_defeat += dt; dirty = true
		for f in _fx:
			f.age += dt; dirty = true
		_fx = _fx.filter(func(f): return f.age < f.ttl)
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
		_layout()
		var key := hash([_origin, main.hex_px, cb.board])
		if key != _ground_key:
			_ground_key = key
			_ground.queue_redraw()

	# HP bar + condition strip: identical for a sprite and for a vector token, so
	# both paths call this rather than keeping two copies in step by hand.
	# T-hud: static and canvas-agnostic on purpose. A figure standing in front of
	# a hex behind it (Figures3D, a Board child, so it draws after Board's own
	# _draw()) could cover that hex's HP bar — the fix main.gd uses is a
	# CanvasLayer overlay sitting above everything, which means this has to
	# paint onto a DIFFERENT CanvasItem than Board itself. draw_rect/draw_string
	# always target whatever `self` is bound to, so `canvas` is threaded through
	# explicitly instead of implied. See main.gd's _draw_hud_overlay.
	static func _paint_token_hud(canvas: CanvasItem, c, hp_shown: float,
			p: Vector2, tp: Vector2, s: float, rad: float, fz: float) -> void:
		var bw := s * 1.2
		var br := Rect2(p.x - bw / 2.0, p.y + rad * ISO_SQUASH + 4.0, bw, 6.0)
		canvas.draw_rect(br, Color("0c0d11"))
		var frac := clampf(hp_shown / float(c.max_hp), 0.0, 1.0)
		var hpcol := Color("5fbf6a")
		if frac < 0.33: hpcol = Color("d15750")
		elif frac < 0.66: hpcol = Color("d9a441")
		canvas.draw_rect(Rect2(br.position, Vector2(br.size.x * frac, br.size.y)), hpcol)
		canvas.draw_string(ThemeDB.fallback_font, br.position + Vector2(0, 12 + 8 * fz),
			"%d/%d" % [c.hp, c.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * fz), Color("c9ccd6"))

		# condition strip, centred over the token (the shoulder is the class badge's)
		var tags: String = Icons.status_glyphs(c)
		if c.is_down(): tags += " %s%d/%d" % [Icons.condition_glyph("down"), c.death_s, c.death_f]
		if tags != "":
			var fs := int(13 * fz)
			var f := ThemeDB.fallback_font
			var w := f.get_string_size(tags, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := tp + Vector2(0, -rad * 0.8 - 10)
			canvas.draw_string(f, at - Vector2(w * 0.5, -fs * 0.36), tags,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e6c15a"))

	# The size is the hit as a fraction of what the body had to lose: 12 damage
	# ends a goblin and scratches a giant, and the number should not be the same
	# size in both. sqrt so the ramp is quick at the bottom — most hits are a
	# small slice of a healthy body, and a flat ratio would leave nearly all of
	# them at the floor.
	func _spawn_float(c, amount: float) -> void:
		var band := Color("ffd24a")
		if amount >= 12: band = Color("ff5a4a")
		elif amount >= 6: band = Color("ff9146")
		var bite := sqrt(clampf(amount / maxf(1.0, float(c.max_hp)), 0.0, 1.0))
		_rebase_view()
		_floats.append({"id": c.id, "pos": _pix(c.pos), "text": "-%d" % int(round(amount)),
			"color": band, "age": 0.0, "fs": lerpf(FLOAT_FS_MIN, FLOAT_FS_MAX, bite)})

	func _gui_input(e: InputEvent) -> void:
		if cb == null:
			return
		if e is InputEventMouseMotion:
			if e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
				main.pan_by(e.relative)
				return
			var hx := _unpix(e.position)
			_hover_pt = _iso_inv(e.position - _origin)
			if hx != _hover:
				_hover = hx
				main.board_hex_hovered(hx)
			elif main._mode == "area":
				queue_redraw()   # a corner can change without the hex changing
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(e.position, 1.1)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(e.position, 1.0 / 1.1)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				main.board_cancel()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				main.board_hex_clicked(_unpix(e.position))

	# Stable per-hex noise: same hex, same salt -> same value, every frame. No RNG
	# state, so nothing here can perturb the game's seeded rolls.
	static func _is_hazard(obj: Dictionary) -> bool:
		return obj.has("hazard") and not obj.get("blocks_movement", false)

	# Everything about the ground that is the same picture every frame: the
	# slab, floor texture, mottling, seams, the cover label and the foliage.
	# Hazards are skipped — their glow pulses, so Board._draw paints them live.
	func _paint_ground(canvas: CanvasItem) -> void:
		var s: float = main.hex_px
		var decor: Array = []   # foliage, drawn after every tile so it can overhang
		# The ground goes on past the board's edge and fades into the dark, two
		# rings deep, the way the map's fog does — a board is a lit patch of a
		# place, not a lozenge cut out of nothing.
		var halo: Dictionary = {}
		for hx in cb.board["hexes"]:
			for n in Hex.neighbors(hx):
				if not n in cb.board["hexes"] and not halo.has(n):
					halo[n] = 1
		for hx in halo.keys():
			for n in Hex.neighbors(hx):
				if not n in cb.board["hexes"] and not halo.has(n):
					halo[n] = 2
		_light_board()
		for hx in halo:
			_paint_floor(canvas, _hex_poly(_pix(hx), s), s, HALO_ALPHA[halo[hx]], _light_at(_pix(hx)))
		for hx in cb.board["hexes"]:
			var c := _pix(hx)
			var obj: Dictionary = cb.object_at(hx)
			if not _is_hazard(obj):
				_paint_tile(canvas, hx, c, s, 0.0)
			if obj.is_empty():
				var d := _foliage_at(hx, c, s)
				if not d.is_empty():
					decor.append(d)
		decor.sort_custom(func(a, b): return a["at"].y < b["at"].y)
		for d in decor:
			_draw_foliage(canvas, d, s)

	# Beyond the board's edge the ground fades out over two rings.
	const HALO_ALPHA := {1: 0.32, 2: 0.10}
	const GRID_ALPHA := 0.34   # the hex line on a plain tile

	# One light over the whole board rather than one per tile: brightest a
	# little up and left of the board's middle, falling off toward its rim.
	# A tile's floor is multiplied by _light_at(), so the whole surface is lit
	# as one thing and nothing draws past the edge.
	var _light_mid := Vector2.ZERO
	var _light_reach := 1.0
	const LIGHT_FALL := 0.38
	func _light_board() -> void:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for hx in cb.board["hexes"]:
			var c := _pix(hx)
			lo = lo.min(c); hi = hi.max(c)
		_light_mid = (lo + hi) * 0.5 + _iso(LIGHT) * main.hex_px * 3.0
		_light_reach = maxf(1.0, (hi - lo).length() * 0.6)
	func _light_at(c: Vector2) -> float:
		return 1.0 - LIGHT_FALL * clampf(c.distance_to(_light_mid) / _light_reach, 0.0, 1.0)

	# The floor, laid flat on the board in ground space so it runs continuous
	# from hex to hex — the same seamless painted texture the map's ground is,
	# and the whole of what a plain tile is now.
	func _paint_floor(canvas: CanvasItem, poly: PackedVector2Array, s: float, alpha: float, light := 1.0) -> void:
		var floor_tex: Texture2D = main.FLOORS.get(cb.board.get("palette", "shrine"))
		var fill: Color = main.PALETTES.get(cb.board.get("palette", "shrine"), main.COL_HEX)
		canvas.draw_colored_polygon(poly, Color(fill, alpha))
		if floor_tex == null:
			return
		var uvs := PackedVector2Array()
		for pt in poly:
			uvs.append(_iso_inv(pt - _origin) / (s * main.FLOOR_SPAN))
		var tone: float = main.FLOOR_TONE * light
		canvas.draw_polygon(poly, PackedColorArray([Color(tone, tone, tone * 1.04, main.FLOOR_ALPHA * alpha)]), uvs, floor_tex)

	func _paint_tile(canvas: CanvasItem, hx: Vector2i, c: Vector2, s: float, pulse: float) -> void:
		var poly := _hex_poly(c, s)   # full size: no gutter between hexes, the texture runs through
		var obj: Dictionary = cb.object_at(hx)
		if obj.is_empty():
			_paint_floor(canvas, poly, s, 1.0, _light_at(c))
		else:
			var fill: Color = main.COL_PROP
			if _is_hazard(obj):
				fill = main.COL_BRAZIER.lerp(Color("d9622e"), pulse)
			_fan(canvas, c + _iso(LIGHT * s * 0.55), poly, fill.lightened(0.11), fill.darkened(0.13))
		if cb.is_cover(hx) and obj.is_empty():
			canvas.draw_colored_polygon(poly, Color(main.COL_COVER, 0.35))   # a wash, the rim says the rest
		# Only a terrain change gets a seam; between two plain tiles there is none,
		# so a run of the same ground is one surface.
		var seam: bool = _terrain(hx) != ""
		for n in Hex.neighbors(hx):
			if n in cb.board["hexes"] and _terrain(n) != _terrain(hx):
				seam = true
		# The grid is a line on the surface, not a gap in it: every hex gets a
		# thin one so the board still reads as hexes, a terrain change a firmer one.
		var edge := _hex_poly(c, s - 0.5)
		edge.append(edge[0])
		canvas.draw_polyline(edge, Color(main.COL_HEX_GRID, 0.7 if seam else GRID_ALPHA), 1.5 if seam else 1.0, true)
		if cb.is_cover(hx):
			_paint_cover(canvas, c, s)
		elif not cb.passable(hx):
			_paint_blocked(canvas, c, s)

	# An impassable hex, said the way cover is said: a rim in its own colour
	# plus a mark — a cross where cover has a "+2" — so a crate you cannot walk
	# through and a wall you can duck behind stop looking like the same prop.
	func _paint_blocked(canvas: CanvasItem, c: Vector2, s: float) -> void:
		var rim := _hex_poly(c, s - 2.5)
		rim.append(rim[0])
		canvas.draw_polyline(rim, Color(main.COL_BLOCKED_EDGE, 0.9), COVER_RIM_W, true)
		var inner := _hex_poly(c, s - 2.5 - COVER_RIM_W * 1.6)
		inner.append(inner[0])
		canvas.draw_polyline(inner, Color(main.COL_BLOCKED_EDGE, 0.22), 1.0, true)
		var fs := int(clampf(s * 0.30, 9.0, 18.0))
		if fs < 10:
			return
		var f := ThemeDB.fallback_font
		var w := f.get_string_size("✕", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := c + Vector2(0.0, s * ISO_SQUASH * 0.92)
		var pad := Vector2(fs * 0.42, fs * 0.30)
		canvas.draw_colored_polygon(_disc(at, (w * 0.5 + pad.x) * 1.05), Color(0.05, 0.03, 0.02, 0.72))
		canvas.draw_string(f, at - Vector2(w * 0.5, -fs * 0.34), "✕",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, main.COL_BLOCKED_EDGE)

	# A cover hex, said twice: a rim in a colour nothing else on the board
	# wears, and a chip carrying the number it is worth. Both scale with the
	# hex, so zooming out loses the chip's text before it loses the rim — the
	# rim is the part that has to survive, because it is what lets you read the
	# shape of the cover on a board at a glance.
	const COVER_RIM_W := 2.4
	const COVER_CHIP := "+2"
	func _paint_cover(canvas: CanvasItem, c: Vector2, s: float) -> void:
		var rim := _hex_poly(c, s - 2.5)
		rim.append(rim[0])
		canvas.draw_polyline(rim, Color(main.COL_COVER_EDGE, 0.9), COVER_RIM_W, true)
		# ...and an inner line, so the rim reads as a lip of something rather
		# than as a selection outline (which is what the move/aim overlays are).
		var inner := _hex_poly(c, s - 2.5 - COVER_RIM_W * 1.6)
		inner.append(inner[0])
		canvas.draw_polyline(inner, Color(main.COL_COVER_EDGE, 0.22), 1.0, true)
		var fs := int(clampf(s * 0.30, 9.0, 18.0))
		if fs < 10:
			return            # too small to read; the rim carries it alone
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(COVER_CHIP, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := c + Vector2(0.0, s * ISO_SQUASH * 0.92)
		var pad := Vector2(fs * 0.42, fs * 0.30)
		# A backing plate, because this lands on a textured floor with a plant
		# on it: without one the chip is legible on some tiles and not others.
		canvas.draw_colored_polygon(_disc(at, (w * 0.5 + pad.x) * 1.05),
			Color(0.02, 0.05, 0.05, 0.72))
		canvas.draw_string(f, at - Vector2(w * 0.5, -fs * 0.34), COVER_CHIP,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, main.COL_COVER_EDGE)

	static func _rand(hx: Vector2i, salt: int) -> float:
		var n: int = hash(Vector3i(hx.x, hx.y, salt))
		return float(n % 4096) / 4096.0 if n >= 0 else float(-n % 4096) / 4096.0

	# What KIND of ground this is, for the seam test — "" is plain floor.
	func _terrain(hx: Vector2i) -> String:
		var o: Dictionary = cb.object_at(hx)
		if o.has("hazard") and not o.get("blocks_movement", false):
			return "hazard"
		if o.get("blocks_movement", false):
			return "prop"
		return "cover" if cb.is_cover(hx) else ""

	# How thickly each theme is planted. Cosmetic only — foliage is never
	# consulted by movement, targeting or line of sight, it is picked from the
	# hex's own hash at draw time and never stored.
	const FLORA := {"forest": 0.55, "camp": 0.22, "shrine": 0.12, "ice": 0.14,
		"city": 0.0, "shop": 0.0}
	const FLORA_COL := {"forest": "3f6b3a", "camp": "5c5f33", "shrine": "3a5548",
		"ice": "5d7a84", "city": "3f5240", "shop": "3f5240"}

	# {} for bare ground, else the plant to draw. Cover hexes always get one —
	# the thing you are hiding behind should be visible.
	func _foliage_at(hx: Vector2i, c: Vector2, s: float) -> Dictionary:
		var pal := String(cb.board.get("palette", "shrine"))
		var r := _rand(hx, 5)
		var cover: bool = cb.is_cover(hx)
		if not cover and r > float(FLORA.get(pal, 0.1)):
			return {}
		var off := _iso(Vector2(_rand(hx, 6) - 0.5, _rand(hx, 7) - 0.5) * s * 0.7)
		return {"at": c + off, "kind": "tree" if _rand(hx, 8) > 0.55 else "bush",
			"col": Color(String(FLORA_COL.get(pal, "3f5240"))),
			"scale": (0.85 + 0.45 * _rand(hx, 9)) * (1.15 if cover else 1.0)}

	# A plant: flat shapes only, standing upright out of a projected shadow.
	func _draw_foliage(canvas: CanvasItem, d: Dictionary, s: float) -> void:
		var at: Vector2 = d["at"]
		var k: float = float(d["scale"]) * s
		var col: Color = d["col"]
		_soft_shadow(canvas, at, k * 0.26, 0.85)
		if String(d["kind"]) == "tree":
			canvas.draw_line(at, at - Vector2(0, k * 0.62), Color("3a2c1c"), maxf(1.5, k * 0.09), true)
			for o in [Vector2(0, -0.95), Vector2(-0.24, -0.66), Vector2(0.24, -0.70)]:
				_lobe(canvas, at + o * k, k * 0.30, col)
		else:
			for o in [Vector2(-0.20, -0.16), Vector2(0.20, -0.16), Vector2(0, -0.34)]:
				_lobe(canvas, at + o * k, k * 0.24, col)

	# One shaded clump of leaves: the same ball shading the tokens use.
	func _lobe(canvas: CanvasItem, at: Vector2, r: float, col: Color) -> void:
		_fan(canvas, at + LIGHT * r * 0.6, _ring(at, r, false, false, 20),
			col.lightened(0.28), col.darkened(0.26))

	# T11 interactables: shapes only, no sprites. Hazards pulse (the hex fill already
	# glows), props get a crate mark, torches a small bright flame.
	# ponytail: a torch could ignite adjacent flammable terrain — not built.
	func _draw_object(o: Dictionary, c: Vector2, s: float, pulse: float) -> void:
		match String(o["type"]):
			"torch":
				for i in 3:   # a soft glow around the flame, not a hard ring
					draw_circle(c, s * (0.22 + 0.10 * i), Color(1.0, 0.78, 0.45, 0.10 - 0.02 * i))
				draw_circle(c, s * 0.16, main.COL_TORCH.lerp(Color("ff9d3d"), pulse))
			"fountain":     # lies flat on the board, so it projects
				_fan(self, c + _iso(LIGHT) * s * 0.28, _disc(c, s * 0.45),
					Color("50707f"), Color("32444f"))
				draw_polyline(_disc(c, s * 0.45, true), Color("6f97ad"), 2.0, true)
			_:
				if o.has("hazard") and not o.get("blocks_movement", false):
					var hot := Color("ffcf7a").lerp(Color("ff6a2a"), pulse)
					_fan(self, c, _disc(c, s * 0.26), hot, Color(hot.r, hot.g, hot.b, 0.0))
					return
				var r := s * 0.42
				var quad := PackedVector2Array()
				for d in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
					quad.append(c + _iso(d))
				draw_colored_polygon(quad, Color("6b5236"))
				draw_line(c + _iso(Vector2(-r, 0)), c + _iso(Vector2(r, 0)),
					Color("ff8c42") if o.get("explosive", false) else Color("3a2c1c"), 2.0)

	func _draw() -> void:
		if cb == null:
			return
		_layout()
		_ground.position = Vector2.ZERO
		if _defeat >= 0.0 and _defeat < 0.6:     # screen shake on the wipe
			var m := (1.0 - _defeat / 0.6) * 10.0
			_ground.position = Vector2(randf_range(-m, m), randf_range(-m, m))
			_origin += _ground.position
		var s: float = main.hex_px
		var fz := clampf(main._zoom, 0.75, 1.7)   # font scale, gentler than the hex scale
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0)

		var field := {}
		var provoke := {}
		var cone_hexes := {}
		var cur = cb.current()
		var hero_turn: bool = cur and cur.team == "party" and cur.conscious()
		if hero_turn and main._mode == "idle" and cur.econ["move_left"] > 0:
			# One A* per reachable hex — 15-20 ms a frame in GDScript, so it is
			# memoised on everything it reads until something on the field moves.
			var key := hash([cur.id, cb.log.size(), cb.board,
				cb.combatants.map(func(c): return [c.pos, c.hp, c.econ, c.statuses])])
			if key != _field_key:
				_field_key = key
				_field = cb.move_field(cur)
				_provoke = {}
				for hx in _field:
					if not cb.provokers_for(cur, hx).is_empty():
						_provoke[hx] = true
			field = _field
			provoke = _provoke
		if hero_turn and main._mode == "cone":
			var dir := Hex.direction_to(cur.pos, _hover)
			if dir != Vector2i.ZERO:
				for hx in Hex.cone(cur.pos, dir, int(main._tgt_verb.get("radius", 2))):
					cone_hexes[hx] = true
		if hero_turn and main._mode == "area":
			for hx in main._area_aim(cur):
				cone_hexes[hx] = true

		# lingering spell areas (combat.gd zones): a wash in the school's colour,
		# a shade deeper at the rim so two overlapping clouds still read apart.
		var zone_tint := {}
		for z in cb.live_zones():
			var col: Color = Icons.school_color(String(Catalog.spell(String(z["spell"])).get("school", "")))
			for hx in z["hexes"]:
				zone_tint[hx] = col
		# tiles: the ground itself is on _ground (see Ground); only what moves
		# frame to frame is painted here, on top of it.
		for hx in cb.board["hexes"]:
			var c := _pix(hx)
			var poly := _hex_poly(c, s - 2.0)
			var obj: Dictionary = cb.object_at(hx)
			if _is_hazard(obj):
				_paint_tile(self, hx, c, s, pulse)   # its glow pulses, so it can't be cached
			if zone_tint.has(hx):
				var zc: Color = zone_tint[hx]
				draw_colored_polygon(poly, Color(zc.r, zc.g, zc.b, 0.30 + 0.06 * pulse))
				var rim := _hex_poly(c, s - 3.0)
				rim.append(rim[0])
				draw_polyline(rim, Color(zc.r, zc.g, zc.b, 0.75), 1.5, true)
			if field.has(hx) and hx != cur.pos:
				draw_colored_polygon(poly, main.COL_MOVE)
			if cone_hexes.has(hx):
				draw_colored_polygon(poly, main.COL_CONE)
			if provoke.has(hx):
				draw_string(ThemeDB.fallback_font, c - Vector2(6, -5), "⚠", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffcf47"))
			if not obj.is_empty():
				_draw_object(obj, c, s, pulse)

		# the valid-target ring stays here, under the tokens — it just traces the
		# hex edge, which reads fine as "this hex is targetable," not a card that
		# needs to sit on top of anything.
		if hero_turn and main._mode == "target":
			for c in cb.combatants:
				if not main._valid_target(cur, c):
					continue
				var tp := _pix(c.pos)
				var hot: bool = c.pos == _hover
				var poly := _hex_poly(tp, s - 3.0)
				poly.append(poly[0])
				var oc: Color = main.COL_TARGET
				draw_polyline(poly, oc if hot else Color(oc.r, oc.g, oc.b, 0.45), 3.0 if hot else 2.0, true)
		elif main._mode == "deploy":
			# Who can be picked up, and who is held — the same hex-edge ring the
			# targeting mode above uses, since it means the same thing: this hex
			# is the one to click.
			for c in cb.combatants:
				if not main.deploy_swappable(c):
					continue
				var held: bool = c.id == main._deploy_pick
				var hot: bool = c.pos == _hover
				var poly := _hex_poly(_pix(c.pos), s - 3.0)
				poly.append(poly[0])
				var oc: Color = main.COL_PARTY
				draw_polyline(poly, oc if (held or hot) else Color(oc.r, oc.g, oc.b, 0.40),
					3.5 if held else (3.0 if hot else 2.0), true)
		elif hero_turn and main._mode == "idle" and cur.econ["action"] > 0:
			for f in cb.enemies_of(cur):
				if cb.in_reach(cur, f):
					var poly := _hex_poly(_pix(f.pos), s - 3.0)
					poly.append(poly[0])
					draw_polyline(poly, Color(main.COL_TARGET.r, main.COL_TARGET.g, main.COL_TARGET.b, 0.30), 1.5, true)

		# tokens, painted back-to-front so nearer ones overlap farther ones
		var order: Array = cb.combatants.filter(func(c): return not c.is_dead())
		order.sort_custom(func(a, b): return _tok.get(a.id, _pix(a.pos)).y < _tok.get(b.id, _pix(b.pos)).y)
		for c in order:
			var p: Vector2 = _tok.get(c.id, _pix(c.pos)) + _lunge(c.id)
			var base: Color = main.COL_PARTY if c.team == "party" else main.COL_FOE
			if c.is_down():
				base = Color("6a6a6a")
			if _flash.has(c.id):
				base = base.lerp(Color.WHITE, clampf(_flash[c.id] / 0.35, 0, 1))
			var rad := s * 0.62
			# The token stands ON its hex: a flat shadow ellipse marks the footprint,
			# the disc itself floats a little above it. Unconscious, it drops onto
			# the ground — no lift, and flat to the board plane like everything
			# else lying on it.
			var tp := p if c.is_down() else p + Vector2(0, -rad * 0.55)
			_soft_shadow(self, p, rad * 0.80, 1.0 if c.is_down() else 1.15)
			if c == cur:
				# A real blink: the ring breathes in alpha, width AND radius, with a
				# faint outer halo — the old width-only wobble read as noise.
				var bl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 170.0)
				base = base.lerp(Color("ffe27a"), 0.18 * bl)
				draw_polyline(_disc(p, rad + 4.0 + bl * 3.0, true),
					Color(1.0, 0.886, 0.478, 0.25 + 0.75 * bl), 2.5 + bl * 3.0, true)
				draw_polyline(_disc(p, rad + 12.0 + bl * 6.0, true),
					Color(1.0, 0.886, 0.478, 0.30 * bl), 2.0, true)
			# Tier 0: a 3D figure in the Figures3D layer above this Board. It
			# replaces the drawn disc and its glyph only — shadow and active ring
			# are shared with the vector token below, which still draws everyone
			# the models don't cover. HP bar, condition tags and barks are all
			# T-hud's job (main.gd's _draw_hud_overlay, a CanvasLayer above every
			# tier including Figures3D — a figure standing in front used to be
			# able to cover the HP bar of the hex behind it when those drew
			# inline here).
			#
			# There used to be a tier between the two: 64px composited LPC pixel
			# art. It was switched off when the 3D foes landed (it clashed) and
			# then sat there dead, along with the CC-BY-SA source art it was
			# composited from and the credits screen that art obliged us to ship.
			# All three are gone now rather than half-gone.
			if main._figures and main._figures.has_figure(c):
				continue
			# The token is shaded like a ball: hotspot toward the light, falling
			# off to a darker rim, with a bright sliver of rim light on the lit
			# side and a dark contact line on the far one.
			var trad := rad * 0.8
			var flat: bool = c.is_down()
			if not flat:
				draw_line(p, tp, base.darkened(0.55), 3.0, true)   # the "post" it stands on
			_fan(self, tp + (_iso(LIGHT) if flat else LIGHT) * trad * 0.62,
				_ring(tp, trad, flat, false, 28), base.lightened(0.26), base.darkened(0.20))
			draw_polyline(_ring(tp, trad, flat, true, 28), base.darkened(0.45), 1.5, true)
			if not flat:
				var lit := LIGHT.angle()
				draw_arc(tp, trad * 0.93, lit - 0.85, lit + 0.85, 20,
					Color(1, 1, 1, 0.26), 2.0, true)
			# The token's mark: class glyph for heroes, creature-type glyph for foes.
			_centered(_glyph(c), tp, int(24 * fz), Color("101216"))

		_draw_fx(s)   # projectiles / spell flashes sit over the tokens

		# The odds chip used to draw here, last, on the theory that nothing after it
		# would cover it — but a Figures3D model is a Board *child*, so it draws
		# after this whole block regardless of order within it, and a tall figure
		# (the ranger rig runs taller than most) could stand right over the chip's
		# fixed -s*1.35 offset and block it. It now lives in main.gd's
		# _draw_hud_overlay, the CanvasLayer above Board and every tier including
		# Figures3D — same fix as the HP bar above.

		# T26 barks used to draw here, and went the same way as the odds chip
		# above and the HP bar before it: a Figures3D model is a Board child, so
		# it draws after this whole block whatever the order within it, and the
		# bark sits lower over its hex than either of those — right where a tall
		# rig's chest is. What a character says was being read by the model
		# standing in front of it. They paint in main.gd's _draw_hud_overlay now.

		# The damage numbers went the same way as the barks above, the odds chip
		# and the HP bar before them, and for the fourth time for the same
		# reason: a Figures3D model is a Board child and draws over everything
		# painted here, so whoever was standing in front of a body covered that
		# body's damage. They paint in main.gd's _draw_hud_overlay now.

		# The roll reveal — HIT / MISS / CRIT! and the dice under it — went the
		# same way, and it is the one that needed it most: its dice row sits
		# lowest of all of these, right at a tall rig's chest, and a figure
		# standing in front sliced the headline in half. main.gd's
		# _draw_hud_overlay calls _paint_reveal now.

		if _defeat >= 0.0:
			_draw_defeat(fz)
			return   # nothing hovers over a wipe

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

	# The roll reveal: the OUTCOME first, the dice that produced it underneath.
	# Static and canvas-agnostic for the same reason _paint_token_hud is — it
	# paints on the HUD overlay, which is a different CanvasItem from Board, and
	# draw_rect/draw_string always target whatever `self` is bound to.
	static func _paint_reveal(ci: CanvasItem, rv: Dictionary, tok: Vector2,
			s: float, fz: float) -> void:
		var a := clampf(1.0 - (float(rv.age) - 0.9) / 0.5, 0.0, 1.0)   # hold, then fade
		var anchor: Vector2 = tok + Vector2(0, -s * 1.7)
		# the headline punches in over the first 0.12s, then settles
		var pop := 1.0 + 0.35 * clampf(1.0 - float(rv.age) / 0.12, 0.0, 1.0)
		var hcol: Color = rv.hcol
		hcol.a = a
		_shout(ci, String(rv.head), anchor + Vector2(0, -14 * fz),
			int(REVEAL_FS * fz * pop), hcol)
		var dice: Array = rv.dice
		var box := 22.0 * fz
		var total_w: float = maxf(0.0, dice.size() * (box + 5.0) - 5.0)
		var x := anchor.x - total_w / 2.0
		anchor.y += 10.0 * fz
		for d in dice:
			var counts: bool = int(d) == int(rv.nat)
			var bg := Color("2a2f3d")
			bg.a = a
			ci.draw_rect(Rect2(x, anchor.y, box, box), bg)
			var edge := (Color("ffe27a") if counts else Color("6a6f80"))
			edge.a = a
			ci.draw_rect(Rect2(x, anchor.y, box, box), edge, false, 2.0)
			var dc := (Color("ffffff") if counts else Color("7f8494"))
			dc.a = a
			ci.draw_string(ThemeDB.fallback_font, Vector2(x + box * 0.26, anchor.y + box * 0.72),
				str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * fz), dc)
			if not counts:
				var sl := Color("d15750"); sl.a = a
				ci.draw_line(Vector2(x + 3, anchor.y + box - 3), Vector2(x + box - 3, anchor.y + 3), sl, 2.0)
			x += box + 5.0
		if not dice.is_empty():
			var lcol := Color("9aa0ae"); lcol.a = a
			_centered_on(ci, "d20 %+d = %d  vs AC %d" % [rv.bonus, rv.total, rv.ac],
				anchor + Vector2(0, box + 14 * fz), int(11 * fz), lcol)

	# T-dmg: the board's loud text — the outcome of a roll, the damage a body
	# took. Three things separate it from _centered's quiet label: the game's own
	# bold face (Icons.sans(700)) instead of ThemeDB.fallback_font, which is
	# Godot's built-in and not a face this game ships; an ink outline, because
	# this lands on painted ground, on a lit token and on a 3D figure's chest and
	# has to hold on all three; and a size the caller scales with the zoom, which
	# the damage number never did — it was a literal 18 while every other
	# readout on the board multiplied by `fz`, so zooming IN to watch a fight
	# made the damage relatively smaller.
	static func _shout(ci: CanvasItem, text: String, at: Vector2, fs: int, col: Color) -> void:
		var f := Icons.sans(700)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := at - Vector2(w * 0.5, -fs * 0.36)
		ci.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			maxi(2, fs / 7), Color(0.04, 0.04, 0.06, col.a * 0.9))
		ci.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# draw_string with the string's own width taken out, so `at` is its centre.
	# The static one takes its canvas, which is what lets the HUD overlay paint
	# Board-authored text; _centered is the same thing bound to Board itself. It
	# lives in here rather than on the outer script because an inner class does
	# not see the outer script's statics, and _paint_reveal above needs it.
	static func _centered_on(ci: CanvasItem, text: String, at: Vector2, fs: int, col: Color) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, at - Vector2(w * 0.5, -fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _centered(text: String, at: Vector2, fs: int, col: Color) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, at - Vector2(w * 0.5, -fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# A hero's class mark, a monster's creature-type mark.
	func _glyph(c) -> String:
		return Icons.combatant_glyph(c)
