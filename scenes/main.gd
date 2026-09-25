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
const Coop = preload("res://core/coop.gd")
const Combat = preload("res://core/combat.gd")   # spell_dc(), for the static tooltip
const Active = preload("res://core/active_effects.gd")

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
# #152: the camera follows the action. Measured before this (docs/spike-combat-
# camera.md): the fit-all view gives a hex 17-20 canvas px at 1280x800 — the
# whole map, and figures the size of a fingernail. ZOOM_FOLLOW is what the
# camera glides to over the actor (and the target, when there is one — the pair
# is kept in frame, which lowers it for a long shot). The chrome — bar, strip,
# chips — scales by Settings.chrome_scale() and nothing else: a bar that breathed
# with every action was the first thing wrong with the prototype, and a bar
# that grew when the player zoomed the map was the second.
const ZOOM_FOLLOW := 1.1     # ~2x the fit-all view; 1.65 read as a close-up once the group was tight
# A turn is framed with its context — the actor and every enemy within
# CAM_CONTEXT hexes — so the camera never shows one figure and nothing to
# act on. Nearer enemies fit at ZOOM_FOLLOW; a spread-out fight lowers it.
const CAM_CONTEXT := 7
var _cam_follow := true       # Home toggles it; a new fight sets it
var _cam_ids: Array = []      # who the camera is on: combatant ids, their tokens tracked as they slide
var _cam_hold := false        # the player panned or zoomed: stay put until the next action
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
var _viewed_id := ""         # #97: who, so the strip can mark them
var _hover_verb: Dictionary = {}   # #92: the bar button under the mouse — its reach is drawn on the board
var _hover_hex := Vector2i(999, 999)
var _anim := 1.0             # animation speed multiplier (huge when FAST)
var _slot_max := {}          # id -> slots at the start of the fight (for the pips)
var _fx_on := false           # attack animations: off under SORCMERC_FAST / headless
# Co-op (docs/spike-coop.md). null is the whole game exactly as it was. The
# link is the lobby's (Coop.link, scenes/game/game.gd) or, for a bare combat
# scene, the env var: SORCMERC_COOP=host opens a room, =CODE joins one as the
# guest, =host:CODE hosts that room — fresh if the relay has nothing for it, a
# rejoin if it has. SORCMERC_RELAY overrides Coop.RELAY_URL.
var _coop = null              # Coop.Link
var coop_first: Dictionary = {}   # a message the screen that made us already took off the link (the guest's setup)
var _owners := {}             # hero id -> "host" | "guest", from the setup
var _coop_inbox: Array = []   # intents received and not yet applied — drained on the turn they belong to
var _coop_answers: Array = [] # reaction answers received and not yet consumed, in order
var _coop_rebuilding := false # this _new_game is from a received setup, not one to announce
var _coop_waiting := false    # the other player's hero is up: we watch
var _gen := 0                 # bumped by every _new_game; a turn loop that wakes to find it changed is over
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
# #195: the bars themselves, on a Control of their own that is the board's
# rect and clips to it (see _draw_hud_bars).
var _hud_bars: Control

@onready var _header := Label.new()
@onready var _order := HBoxContainer.new()   # turn-order icon strip along the top
var _order_tiles := {}    # combatant id -> its tile in that strip
var _order_aimed := {}    # ids currently wearing the aim highlight — see _paint_order_aim
@onready var _hint := Label.new()
@onready var _board := Board.new()
const Figures3D := preload("res://scenes/figures3d.gd")
const CombatCard := preload("res://scenes/combat_card.gd")   # #173
const SkillCard := preload("res://scenes/skill_card.gd")     # the bar's hover card
const Portraits := preload("res://scenes/portraits.gd")
var _figures
@onready var _actor := RichTextLabel.new()
@onready var _buttons := GridContainer.new()
@onready var _bscroll := ScrollContainer.new()
@onready var _fx := HFlowContainer.new()   # what is riding on the bar's hero (core/active_effects.gd)
@onready var _fxscroll := ScrollContainer.new()
const FX_ROWS := 2   # the strip's fixed height, in chip rows; more than that scrolls
const FX_ROW_H := 30.0
var _fx_sig := ""
@onready var _logbox := RichTextLabel.new()
@onready var _cap := Label.new()
@onready var _logwrap := PanelContainer.new()
@onready var _card := CombatCard.new()   # #173: who is under the cursor, top of the left column

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
# #156: the two colours a raised tile is drawn in, from the board's own floor
# colour so a shelf on the ice board is blue rock and one in the shrine brown.
# Out here, and static, because the one thing about them that matters cannot be
# seen in a screenshot and can be asserted: the rim has to come out BRIGHTER
# than COL_HEX_GRID, which is the ordinary line between two tiles. The first
# gain (1.7, lerped toward COL_GOLD_EDGE) did not — COL_GOLD_EDGE is itself
# dark, so the mix pulled the blue down faster than the gain lifted it and the
# rim landed on (88, 81, 71) against the grid's (107, 115, 134). The edge that
# was supposed to say "there is a step here" was dimmer than every edge that
# says nothing, which is how the shelf in this PR's own screenshot got read as
# the cover hexes three rows above it. tests/test_height.gd holds the floor.
const SHELF_DARK := 0.34    # the cut earth under the edge, against the floor's fill
const SHELF_RIM := 3.0      # ...and the lit edge along the top of it
const SHELF_WARMTH := 0.45  # how far that edge is pulled toward the gilt
static func shelf_face(fill: Color) -> Color:
	return Color(fill.r * SHELF_DARK, fill.g * SHELF_DARK, fill.b * SHELF_DARK, 1.0)
static func shelf_rim(fill: Color) -> Color:
	var lit := Color(minf(fill.r * SHELF_RIM, 1.0), minf(fill.g * SHELF_RIM, 1.0),
		minf(fill.b * SHELF_RIM, 1.0)).lerp(Icons.COL_GOLD, SHELF_WARMTH)
	lit.a = 0.9
	return lit
# T11: per-theme floor tint, palette only — no mechanical difference.
const PALETTES := {"shrine": COL_HEX, "camp": Color("2a2a26"), "city": Color("2c2c33"),
	"forest": Color("1f2a22"), "ice": Color("222c36"), "shop": Color("2b2620"),
	# O-biome: open moor reads greyer and drier than the wood, marsh darker and wetter.
	"downs": Color("2e3327"), "marsh": Color("1c2622")}
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
	"downs": preload("res://assets/board/floor_downs.png"),
	"marsh": preload("res://assets/board/floor_marsh.png"),
}
const FLOOR_SPAN := 3.0    # hexes per texture repeat
# #73: a painted backdrop behind the board, one per palette, from the scene
# art the game already ships (assets/generated). Held well down so the lit
# hexes stay the picture; the board is a patch of a place, and this is the place.
const BACKDROPS := {
	"shrine": "res://assets/generated/room-cistern.png",
	"camp": "res://assets/generated/camp-night.png",
	"city": "res://assets/generated/room-gallery.png",
	"forest": "res://assets/generated/event-tracks.png",
	"ice": "res://assets/generated/event-storm.png",
	"shop": "res://assets/generated/room-forge.png",
	# Reused rather than newly painted: the road events already have the two
	# skies these boards stand under, and a backdrop is a blurred tone behind
	# the board, not a picture anybody reads.
	"downs": "res://assets/generated/event-good-ground.png",
	"marsh": "res://assets/generated/event-ford.png",
}
const BACKDROP_TONE := Color(0.42, 0.40, 0.40)
const BACKDROP_NIGHT := Color(0.16, 0.17, 0.26)
const COL_NIGHT := Color(0.02, 0.03, 0.09, 0.62)   # #85: an unlit hex after dark
const FLOOR_ALPHA := 0.9    # the texture is the ground now, not a wash over a slab
const FLOOR_TONE := 0.72    # ...held down to the board's dark palette, the board light on top
const COL_MOVE := Color(0.30, 0.55, 0.95, 0.35)
const COL_EXIT := Color(0.85, 0.72, 0.30, 0.32)      # objectives: the road out / the treeline
const COL_EDGE := Color(0.95, 0.90, 0.72, 0.55)      # the audit's 3.5: the edge a hero can walk off (a rim)
const COL_BYSTANDER := Color("d8cfae")               # objectives: a captive's or carter's token
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
	# #173: the character card takes the top of this column and the log moves
	# under it. The column used to be log from the caption to the floor; a card
	# that is meant to be READ while you choose an answer to it has to sit
	# somewhere the board never covers, and this is the only such place.
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logcol.add_child(_card)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	logcol.add_child(spacer)
	_cap.text = "Action log"
	_cap.theme_type_variation = "Caption"
	logcol.add_child(_cap)
	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	# Bounded rather than greedy, and smaller type: the log is a record of what
	# already happened and the card is about the decision in front of you, so
	# when the column is short the log is what gives way. It keeps its own
	# scrollbar, so nothing is lost by making it a window instead of a wall.
	_logbox.custom_minimum_size.y = LOG_MIN_H
	_logbox.size_flags_vertical = Control.SIZE_FILL
	_logbox.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	_logbox.add_theme_font_size_override("bold_font_size", Icons.FS_SMALL)
	_logbox.add_theme_color_override("default_color", Icons.COL_TEXT)
	# One event, one paragraph: a gap between entries and none inside a wrapped
	# one, so a swing, its miss and the next actor's move read as three things
	# rather than one column of ink.
	_logbox.add_theme_constant_override("paragraph_separation", 7)
	_logbox.add_theme_constant_override("line_separation", 1)
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

	_hint.text = "1-9 act, Tab swaps weapon, Space ends the turn, Esc backs out.  Scroll zooms, drag pans, Home toggles the camera between the action and the whole board."
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
	_hud_bars = Control.new()
	_hud_bars.clip_contents = true
	_hud_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_bars.draw.connect(_draw_hud_bars)
	_hud_layer.add_child(_hud_bars)   # first, so the chips and numbers below draw over it
	_hud_overlay = Control.new()
	_hud_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_overlay.draw.connect(_draw_hud_overlay)
	_hud_layer.add_child(_hud_overlay)

	_actor.bbcode_enabled = true
	# #91: NOT fit_content. The line under the board is held at ACTOR_LINES
	# tall whatever it says, so a two-line readout does not shove the board
	# up and a one-line one does not drop it back.
	_actor.fit_content = false
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
	_bscroll.add_child(_buttons)
	# The effect strip rides beside the buttons, in the room the fixed row
	# leaves to its right: the one place a player is always looking when they
	# choose what to press, and the only place a buff is said for as long as
	# it lasts (see _show_effects).
	var barrow := HBoxContainer.new()
	barrow.add_theme_constant_override("separation", 14)
	barrow.add_child(_bscroll)
	# Held at FX_ROWS tall whatever it carries, the way the actor line is held
	# (#91): a buff arriving must not shove the board up.
	_fxscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fxscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fx.add_theme_constant_override("h_separation", 5)
	_fx.add_theme_constant_override("v_separation", 4)
	_fxscroll.add_child(_fx)
	_fxscroll.custom_minimum_size.y = (FX_ROW_H * FX_ROWS + 4.0) * Settings.chrome_scale()
	barrow.add_child(_fxscroll)
	col.add_child(barrow)

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
	_coop = Coop.link if Coop.link != null else Coop.from_env()
	if _coop == null:
		_new_game()
		return
	_actor.text = "Joining room [b]%s[/b]…" % _coop.code   # the relay's replay decides what happens next
	if not coop_first.is_empty():
		_coop_recv(coop_first)
	elif Coop.link != null and _coop.role == "host":
		_new_game()   # the lobby's host: every fight the world puts up is announced from here

# Font sizes across the whole combat UI track the zoom level.
func _apply_ui_scale() -> void:
	var u := Settings.chrome_scale()
	_header.add_theme_font_size_override("font_size", int(Icons.FS_TITLE * u))
	_actor.add_theme_font_size_override("normal_font_size", int(Icons.FS_HEAD * u))
	_actor.add_theme_font_size_override("bold_font_size", int(Icons.FS_HEAD * u))
	_actor.custom_minimum_size.y = _actor.get_theme_font("normal_font").get_height(int(Icons.FS_HEAD * u)) \
		* ACTOR_LINES + _actor.get_theme_constant("line_separation") * (ACTOR_LINES - 1) + 6
	# the log is a narrow sidebar now — body size wraps far less than head size
	_logbox.add_theme_font_size_override("normal_font_size", int(Icons.FS_SMALL * u))
	_logbox.add_theme_font_size_override("bold_font_size", int(Icons.FS_SMALL * u))
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
	_cam_hold = true   # #152: the player's view, until the next action
	if _board:
		_board._auto_fit = false
		_board.queue_redraw()

func pan_by(delta: Vector2) -> void:
	_pan += delta
	_cam_hold = true   # #152
	if _board:
		_board.queue_redraw()

# #152: the camera's next subject — the actor, or the actor and what it is
# acting on. Ids, not hexes, so a walking token is followed as it slides.
func focus_cam(ids: Array) -> void:
	_cam_ids = ids
	_cam_hold = false
	if _cam_follow and _board:
		_board._auto_fit = false

# The actor and every enemy within CAM_CONTEXT hexes, nearest first.
func _cam_context(c) -> Array:
	var ids: Array = [c.id]
	for o in cb.enemies_of(c):
		if Hex.distance(c.pos, o.pos) <= CAM_CONTEXT:
			ids.append(o.id)
	return ids

# Home: the whole board, or back to following — one key, both ways.
func toggle_cam() -> void:
	_cam_follow = not _cam_follow
	_cam_hold = false
	if _cam_follow:
		_board._auto_fit = false   # or _layout() fits the whole board back every frame
		return
	_zoom = ZOOM_DEFAULT; _pan = Vector2.ZERO
	_board._auto_fit = true
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
		KEY_HOME: toggle_cam()   # #152
		KEY_LEFT: pan_by(Vector2(40, 0))
		KEY_RIGHT: pan_by(Vector2(-40, 0))
		KEY_UP: pan_by(Vector2(0, 40))
		KEY_DOWN: pan_by(Vector2(0, -40))
		KEY_ESCAPE, KEY_B: board_cancel()
		KEY_TAB: _press_key("Tab")
		KEY_R: if cb and cb.is_over(): _new_game()
		KEY_F1: SettingsOverlay.toggle(self, func(): _anim = Settings.anim(); _apply_ui_scale())
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
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), _seed)   # sp["theme"] picks the board
	cb = Encounter.build(sp, party.to_combatants(Encounter.starts_for(sp, board, _seed)), board)   # #114; objectives pick the starts
	cb.party = party   # the stash is the potion shelf (core/potions.gd)
	# The one thing that makes a reaction stop the fight and ask. Installed only
	# here, only for a player who is actually watching: with it unset the
	# resolver auto-resolves reactions exactly as it always has, which is what
	# every headless run and every test gets (Settings.reaction_prompts_on()
	# refuses under SORCMERC_FAST — a prompt nobody answers is a hang).
	# Co-op installs its own on both peers whatever the setting: the reactor's
	# owner answers (or auto-yes, prompts off) and the answer crosses the wire.
	if _coop != null:
		cb.reaction_decider = _coop_decide
	elif Settings.reaction_prompts_on():
		cb.reaction_decider = _ask_reaction
	# A foe's action draws the same lunge / shot / flash a hero's does, at the
	# moment it happens, hit or miss. Heroes draw their own from _apply_target,
	# which knows the verb before perform() does.
	cb.on_perform = func(a, v: Dictionary, t) -> void:
		# #152: a melee blow frames the pair; a shot or a spell frames where it
		# lands — the one who is hit is the one to watch, not the one aiming.
		if t is Object and "id" in t and t != a:
			var reach: bool = v.has("spell") or a.ranged or int(v.get("range", a.atk_range)) > 1
			focus_cam([t.id] if reach else [a.id, t.id])
		else:
			focus_cam([a.id])
		if a.team == "foe" and t is Object and "pos" in t:
			_attack_fx(a, t, v)
	_slot_max.clear()   # a foe with no sheet only tracks slots left; its pips take this as the max
	for c in cb.combatants:
		_slot_max[c.id] = c.slots.duplicate()
	_deploy_pick = ""
	_gen += 1            # any suspended turn loop from the last fight ends when it wakes
	_advancing = false
	_busy = false
	_coop_waiting = false
	_coop_inbox.clear()
	_coop_answers.clear()
	_logbox.text = ""
	_card.clear()   # #173: a new fight starts with nobody on the card
	_logged = 0
	_last_round = 1
	_board.reset(cb)
	_figures.reset(cb)
	_cam_follow = true; _cam_ids = []; _cam_hold = false   # #152: fit-all until the first turn
	_flush_log()
	_refresh()
	if _coop != null and _coop.role == "host" and not _coop_rebuilding:
		_split_menu(sp)   # who plays whom, then Begin announces the setup and opens the fight
		return
	_open_fight()

# Everything after the board is built: surprise, deployment, the first turn.
func _open_fight() -> void:
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
	if _coop != null and _coop.role == "guest":
		_actor.text = "[b]Unseen.[/b]  Waiting for the host to place the party…"
		_set_buttons([])
		return
	var heroes: Array = cb.heroes()
	if _deploy_pick != "" and not heroes.any(func(c): return c.id == _deploy_pick):
		_deploy_pick = ""          # they went down between menus; nobody is held
	var opts: Array = []
	for h in heroes:
		var held: bool = h.id == _deploy_pick
		# #90: words, not a glyph — "▣" read as a broken character on the button.
		opts.append([("Put %s back" % h.cname) if held else "Swap %s" % h.cname,
			_pick_deploy.bind(h.id)])
	if _deploy_pick == "":
		_actor.text = "[b]Unseen — place the party.[/b]  Click a merc, then who they trade places with. Begin when you like it; the enemy loses its first round."
	else:
		_actor.text = "[b]Unseen.[/b]  %s is picked up — click another merc to trade places, or click them again to put them back." \
			% _deploy_name(_deploy_pick)
	opts.append(["Begin the ambush", func():
		_deploy_pick = ""
		_mode = "idle"
		_coop_send({"t": "go"})
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
	if _mode != "deploy" or (_coop != null and _coop.role == "guest"):
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
	if _coop != null and _coop.role == "host":
		_coop.send(Coop.swap(a, b))
	_board.reset(cb)
	_figures.reset(cb)
	_flush_log()
	_refresh()
	_deploy_menu()

# Who on the board can be picked up right now: the conscious party, since the
# whole phase is permuting where they stand.
func deploy_swappable(c) -> bool:
	return _mode == "deploy" and c != null and c.team == "party" and c.conscious() and not c.has("bystander")

# --- turn driver --------------------------------------------------------

func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	var gen := _gen
	while not cb.is_over():
		var c = cb.current()
		cb.begin_turn()
		_flush_log()
		_refresh()
		if c.is_dead() or c.is_stable():
			cb.end_turn()
			continue
		focus_cam(_cam_context(c))   # #152: whoever's turn it is, and what is near them
		if c.team == "foe" or c.is_down():
			_busy = true
			_viewing = false
			_set_buttons([])
			while _walk != null:      # nobody swings while the walkthrough is up
				await get_tree().process_frame
			if _coop_inbox.is_empty():   # a rejoin replays without the beats
				await get_tree().create_timer(TURN_BEAT / _anim).timeout
			if gen != _gen:
				return   # the fight was rebuilt under us (co-op resync); its own loop is running
			if not c.is_down():
				# Awaited because the AI now stops between its own actions to
				# offer the party its reactions (core/ai.gd). With prompts off
				# it never suspends and this is the same call it always was.
				# Its swings draw through cb.on_perform (see _start_combat).
				await AI.take_turn(cb, c)
				if gen != _gen:
					return
			_flush_log()
			_refresh()
			_busy = false
			cb.end_turn()
			continue
		# Co-op: the other peer's hero, or a rejoin still replaying the log —
		# either way this turn's presses come off the wire, end_turn included.
		if _coop != null and (_owners.get(c.id, "host") != _coop.role or not _coop_inbox.is_empty()):
			_busy = true
			_viewing = false
			_set_buttons([])
			_coop_waiting = true
			_refresh()
			var ended: bool = await _coop_remote_turn(c)
			if gen != _gen:
				return
			_busy = false
			if ended:
				continue
			# Our own hero, and the replay ran dry partway through their turn:
			# the rest of it is ours to press.
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
	_coop_send(Coop.end_turn(cb))
	_advance()

# --- co-op (docs/spike-coop.md) -------------------------------------------

func _perform(h, v: Dictionary, target = null) -> Dictionary:
	var res = cb.perform(h, v, target)
	_coop_send(Coop.perform(h, v, target))
	return res

func _coop_send(m: Dictionary) -> void:
	if _coop != null:
		_coop.send(m)

func _mine(c) -> bool:
	return _coop == null or _owners.get(c.id, "host") == _coop.role

# The host's one pre-fight choice: who plays whom. Remembered across fights
# (Coop.split), so after the first it is a look and a Begin.
func _split_menu(sp: Dictionary) -> void:
	_mode = "split"
	var opts: Array = []
	var owners := Coop.owners_for(party)
	_owners = owners   # so the strip says whose hand each hero is in while choosing
	_build_order_strip()
	for h in cb.heroes():
		var theirs: bool = owners.get(h.id, "host") == "guest"
		opts.append(["%s — %s" % [h.cname, "your friend" if theirs else "you"], func():
			Coop.split[h.id] = "host" if theirs else "guest"
			_split_menu(sp)])
	opts.append(["Begin", func():
		_mode = "idle"
		var setup: Dictionary = Coop.setup_for(_seed, sp, party, _opening())
		_owners = setup["owners"]
		_coop.send(setup)
		_open_fight()])
	_actor.text = "[b]Room %s.[/b]  %s  Click a name to hand them over, then Begin." % [_coop.code,
		"Your friend is here." if _coop.other_here() else "Your friend can join at any time — even mid-fight."]
	_set_buttons(opts)

# Issue #132: everything the board is built from crosses in the setup — the
# seed, the encounter spec, the party. These three do not: they are set on this
# screen by whoever put the fight up (world.gd's scouted node and its camp
# ambush, game.gd's guided fight), and the guest's screen is built by game.gd
# with all three at their defaults. Left out, the guest rolled its own Stealth
# check in _open_fight() and opened a fight that was not the host's — a
# different first round, and a hash mismatch on every end_turn after it.
func _opening() -> Dictionary:
	return {"scouted": scouted_ahead, "ambush": forced_ambush, "tutorial": tutorial}

# The same, on the guest, before _new_game() builds the fight the flags decide.
# `tutorial` is taken for one reason only: it is what makes _open_fight() skip
# the deployment phase, and a host that skips it never presses Begin — so a
# guest that did not skip it sat in "waiting for the host to place the party"
# for the rest of the fight. The walkthrough cards themselves are armed in
# _ready() and are not re-armed here; they are the host's screen's business.
func _take_opening(m: Dictionary) -> void:
	var o: Dictionary = m.get("opening", {})
	scouted_ahead = bool(o.get("scouted", false))
	forced_ambush = bool(o.get("ambush", false))
	tutorial = bool(o.get("tutorial", false))

func _coop_recv(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"replay":   # the room so far: nothing (a new room — the host starts it) or everything
			if cb != null and _coop.role == "host" and not m.get("reconnect", false):
				return   # the lobby's host already has its fight up; what the room holds is stale
			if m["log"].is_empty():
				if _coop.role == "host" and cb == null:
					_new_game()
			else:   # a join, a rejoin, or a socket that dropped and came back: the log is the truth
				for e in m["log"]:
					_coop_recv(e)
		"setup":   # a guest joining, or either peer rejoining: the relay replays it
			if m.has("build") and String(m["build"]) != Coop.build_stamp():
				# Lockstep on different code is a desync waiting for its first
				# roll; better to say so at the door.
				_actor.text = "[b]Different builds.[/b]  The host runs %s; this is %s. Update, then join again." % [m["build"], Coop.build_stamp()]
				_set_buttons([])
				return
			_dismiss_wash()   # the last fight's verdict, if it is still up
			result = {}
			party = Coop.party_from(m)
			_own_party = false
			spec = m["spec"]
			_owners = m["owners"]
			_take_opening(m)   # #132: how the host is opening it, before the board is built
			_coop_rebuilding = true
			_new_game(int(m["seed"]))
			_coop_rebuilding = false
		"swap":
			if _coop.role == "guest":
				_swap_deploy(_combatant(String(m["a"])), _combatant(String(m["b"])))
		"go":
			if _coop.role == "guest":
				_mode = "idle"
				_advance()
		"perform", "move", "end_turn":
			_coop_inbox.append(m)
		"reaction":
			_coop_answers.append(bool(m["yes"]))
		"hover":
			if cb != null and _coop_waiting:
				_board._hover = Vector2i(int(m["hex"][0]), int(m["hex"][1]))
				_hover_verb = {}
				for v in cb.all_verbs(cb.current()):
					if String(v["id"]) == String(m.get("verb", "")):
						_hover_verb = v
				_board.queue_redraw()

# One turn off the wire: apply what arrives until its end_turn has been applied
# (that call does the cb.end_turn()) or the fight is over — true. False when
# the inbox runs dry on one of OUR heroes: a rejoin replaying our own
# half-finished turn, which nobody else is going to finish.
func _coop_remote_turn(c) -> bool:
	_coop_waiting = true
	while true:
		while _coop_inbox.is_empty():
			if _mine(c):
				_coop_waiting = false
				return false
			var gen := _gen
			await get_tree().process_frame
			if gen != _gen:
				return true
		var m: Dictionary = _coop_inbox.pop_front()
		var h = Coop.find(cb, String(m.get("hero", "")))
		if m["t"] == "move" and h != null:
			_board.slide_from(h)
		Coop.apply(cb, m)
		if m["t"] == "perform" and m.has("c"):
			_attack_fx(h, Coop.find(cb, String(m["c"])), {})
		_flush_log()
		_refresh()
		if m["t"] == "end_turn":
			if m.has("hash") and int(m["hash"]) != Coop.state_hash(cb):
				cb.log.append("⚠ DESYNC: this screen's fight no longer matches the other player's (seed %d, round %d)." % [_seed, cb.round_num])
				_flush_log()
			break
		if cb.is_over():
			break
	_coop_waiting = false
	_hover_verb = {}
	return true

# The reaction decider in co-op: the reactor's owner answers — through the
# card if prompts are on, else the auto-yes the resolver always gave — and the
# answer crosses the wire; the other peer waits for it. Both peers reach the
# same prompts in the same order, so answers are consumed in order, which is
# also what makes a rejoin's replayed answers land on the right prompts.
func _coop_decide(reactor, v: Dictionary, trigger: String, ctx: Dictionary) -> bool:
	if not _coop_answers.is_empty():
		return _coop_answers.pop_front()
	if _mine(reactor):
		var yes := true
		if Settings.reaction_prompts_on():
			yes = await _ask_reaction(reactor, v, trigger, ctx)
		_coop_send(Coop.reaction(yes))
		return yes
	_actor.text = "[b]%s[/b] — your friend is deciding: %s?" % [reactor.cname, String(v["label"])]
	var gen := _gen
	while _coop_answers.is_empty():
		await get_tree().process_frame
		if gen != _gen:
			return false   # the fight was rebuilt under us; this resolver is orphaned
	return _coop_answers.pop_front()

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
	_show_effects(h)   # a bar rebuilt after a press: what that press spent or set
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
		var prose := _verb_prose(v)
		var sid: String = String(v.get("spell", ""))
		var glyph: String = Icons.school_glyph(Icons.spell_school(sid)) if sid != "" \
			else Icons.verb_glyph(String(v["kind"]))
		var freq_key: String = ("spell:" + sid) if sid != "" else String(v.get("id", v["kind"]))
		# The drawn badge: a spell wears its school (the disc under the art is
		# school_color, the same one spell_bb tints its name with), everything
		# else the martial set. `glyph` stays as the fallback for a build where
		# the icons aren't there — see Icons.verb_icon.
		var meta := _mark(Icons.skill_icon(v), glyph, freq_key)
		meta["verb"] = v   # #92: hovering the button shows the reach on the board
		# What the popup draws: the same verb, as a card (scenes/skill_card.gd).
		# `tip` stays the plain string the tests and the robots read.
		meta["card"] = SkillCard.from_verb(h, v, prose[0], prose[1], _card_title(h, v))
		meta["slot_level"] = int(v.get("slot_level", 0))
		meta["cost"] = String(v.get("cost", "action"))
		if label.contains("★"):
			meta["tier"] = label.substr(label.find("★"))   # the upcast slot, on the badge's corner
		if _armed == String(v.get("id", "")):
			meta["armed"] = true
		meta["disabled"] = not on
		# What a buff or condition on this hero does to THIS button — ADV from a
		# Hide, DIS from Poisoned, ✦ where an armed Metamagic will ride. The
		# mark goes on the face, the reason at the head of the popup.
		var fx: Array = Active.marks(cb, h, v)
		if not fx.is_empty():
			meta["fx"] = fx
			tip = label + "\n" + "\n".join(fx.map(func(m): return String(m["why"]))) + "\n\n" + _verb_tooltip(h, v)
			meta["card"]["effects"] = fx.map(func(m): return [String(m["why"]), _tone_color(String(m["tone"]))])
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
					var opt := _confirm_opt(h, v["id"], label, func(): _perform(h, v); _after_hero_action(h))
					opt.append(tip)
					opt.append(meta)
					entry = opt
				else:
					var fn := func(): _perform(h, v); _after_hero_action(h)
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
			head["card"] = (head["card"] as Dictionary).duplicate()
			var castable: int = tiers.filter(func(t): return not bool(t[3].get("disabled", false))).size()
			head["disabled"] = castable == 0
			head["shift_fn"] = func(): _spell_tier_menu(h, sid)   # Shift+number: pick the slot level
			head["card"]["foot"] = "%d of %d slot levels castable — press to pick one (Shift+key for the levels)" % [
				castable, tiers.size()]
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
	elif key.begins_with("shove") or key in ["smash", "help", "grapple", "escape"]:
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
			# A mark inside the list shows on the list's own button too: an
			# armed Quickened Spell is no use if you have to open [2] to see it.
			for o in mine:
				if o[3].has("fx"):
					meta["fx"] = o[3]["fx"]
					break
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
		var end_opt := _confirm_opt(h, "end", "End turn (action unspent)", _end_turn)
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
# pressed; a list too long for the bar pages on the last slot (More ▸, Tab),
# in a stable order.
#
# Issue #124: a page used to be nine long because nine is how many number keys
# there are, which left a caster reading their spells eight at a time across a
# bar with room for thirty-two of them — three pages of paging in front of two
# empty rows. The keys and the page are two different things now: the bar shows
# as many badges as it can fit, and [1]..[9] land on the first nine of them.
# Everything past the ninth is click-only, which is what the badges were for.
const LIST_KEYS := 9                                # entries that get a number key
const LIST_PAGE := BTN_COLUMNS * BUTTON_ROWS - 1    # entries that fit, less Back

# One flat list, a bar-full to a page. The entries are re-derived on every call
# rather than carried in the binding, so re-opening the page after something on
# it changed (a confirm armed, a use spent) shows what is true now — see
# _menu_entries.
func _open_list(h, slot: String, page := 0) -> void:
	_submenu = slot
	_submenu_page = page
	_tier_spell = ""
	var name: String = SLOT_NAMES.get(slot, slot)
	var entries: Array = _slot_list(_menu_entries(h)["opts"], slot)
	var opts: Array = []
	var per := LIST_PAGE if entries.size() <= LIST_PAGE else LIST_PAGE - 1
	var start := page * per
	opts.append_array(entries.slice(start, mini(entries.size(), start + per)))
	if entries.size() > LIST_PAGE:
		var next_page := page + 1 if start + per < entries.size() else 0
		var meta := _mark(Icons.verb_icon("generic"), "…")
		# Tab, because every number key is spoken for by the page it is turning
		# and a keyboard has to be able to reach the next one. Nothing else on a
		# submenu wears Tab — Swap weapon is a main-bar slot.
		meta["key"] = "Tab"
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
	"shove": "An unarmed strike (one of your attacks): the target saves against DC 8 + STR + proficiency or is knocked prone / pushed back.",
	"grapple": "An unarmed strike (one of your attacks): the target saves against DC 8 + STR + proficiency or is held at speed 0 until it breaks free.",
	"escape": "Athletics or Acrobatics against your grappler's DC to break the hold.",
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
	"font_of_magic": "Font of Magic: burn a spell slot into sorcery points (no action), or spend points on a new slot (a bonus action). A made slot lasts until your next long rest.",
	"metamagic": "Metamagic: bend the next spell you cast. The points are paid now and come back if no spell takes it this turn.",
}

# The martial verbs' lore line on the hover card (scenes/skill_card.gd). A
# spell's comes out of its SRD text; the verbs every character has were never
# given any, and a card that is all rules for Dash and half story for Fireball
# reads as two different games. Only the verbs everybody has: a class feature
# (Second Wind, Rage) is too particular for one line per kind to be true of it,
# and gets its rules blurb alone.
const KIND_LORE := {
	"attack": "Steel, and the arm behind it.",
	"offhand_attack": "The other hand was never only there for balance.",
	"dodge": "Stop trying to win for a moment. Just don't get hit.",
	"dash": "Run now; work out where to later.",
	"disengage": "Back off a step at a time, blade up, and leave them no opening.",
	"hide": "Get something solid between you and them, and keep still.",
	"help": "A feint, an elbow, a shout at the right moment.",
	"shove": "Some fights go better with the other one on the floor.",
	"grapple": "Get a hand on them and don't let go.",
	"escape": "Twist, shove, and get loose.",
	"smash": "It's a barrel. It won't mind.",
}

# [lore, rules] for the card: a spell's SRD description cut where its rules
# start (SkillCard.split_prose), else KIND_LORE over the kind blurb.
static func _verb_prose(v: Dictionary) -> Array:
	if v.has("spell"):
		var desc := String(Catalog.spell(v["spell"]).get("description", ""))
		if desc != "":
			return SkillCard.split_prose(desc)
	return [String(KIND_LORE.get(v["kind"], "")), String(KIND_BLURB.get(v["kind"], ""))]

# The card's title: the verb's plain name — its cost and pool, which the bar
# label carries as " [bonus]" and " 2/3", have their own lines on the card.
static func _card_title(h, v: Dictionary) -> String:
	var t := String(v["label"])
	if v["kind"] == "attack" and not h.attacks.is_empty():
		t += " (%s)" % h.attacks[0].get("name", "unarmed")
	return t

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
		bits.append("DC %d %s save%s" % [Combat.spell_dc(h, v) if v["kind"] == "spell" else int(v.get("save_dc", 0)), String(v["save"]).to_upper(),
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
	return v.has("pool") or int(v.get("slot_level", 0)) > 0 or v["kind"] in ["dodge", "dash", "withdraw"]

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
	_picked.clear()
	_actor.text = "%s — %s: hover a target for the odds, click to apply.  (Esc / right-click cancels)" % [
		h.cname, v["label"]]
	_set_buttons([["Cancel", func(): board_cancel(), "Cancel",
		_mark(Icons.verb_icon("back"), "‹")]])
	_paint_order_aim()
	_board.queue_redraw()

# A verb that takes several targets (an upcast Hold Person): the ones clicked
# so far, in order. The player picks each; the engine only auto-fills when it
# is handed a single Combatant (the AI's path).
var _picked: Array = []

# Is `c` a legal target for the pending verb? For a multi-target verb, also not
# one already picked and within the "30 feet of each other" of the first.
func _valid_target(h, c) -> bool:
	if _tgt_verb.is_empty() or not cb.legal_target(h, _tgt_verb, c):
		return false
	if _picked.is_empty():
		return true
	return not c in _picked and Hex.distance(_picked[0].pos, c.pos) <= cb.SPREAD_HEXES

# The number shown over a valid target while aiming.
func target_readout(h, c) -> String:
	var v := _tgt_verb
	match v["kind"]:
		"attack": return "%d%%" % int(round(cb.hit_chance(h, c) * 100.0))
		"shove", "grapple": return "%d%%" % int(round(cb.shove_chance(h, c) * 100.0))
		"help": return "advantage"
	if v.has("heal_count") or v["kind"] in ["heal_self", "heal_ally"]:
		if c.is_down():
			return "revive"
		var n := int(v.get("heal_count", v.get("dice_count", 1)))
		var s := int(v.get("heal_sides", v.get("dice_sides", 8)))
		return "≈%d HP" % int(n * (s + 1) / 2.0 + int(v.get("heal_bonus", v.get("dice_bonus", 0))))
	if v.get("save", "") != "":
		return "%d%%" % int(round(cb.save_fail_chance(c, Combat.spell_dc(h, v) if v["kind"] == "spell" else int(v.get("save_dc", h.save_dc)),
			v["save"], v.get("ignores_cover", false), v.get("magical", v["kind"] == "spell"),
			v.get("conditions", [])) * 100.0))
	return ""

# board callbacks -------------------------------------------------------

func board_hex_clicked(hx: Vector2i) -> void:
	if (_busy and not _coop_waiting) or cb.is_over() or _mode == "split":
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
	# #97: a click on a party member's token looks at their sheet (#72); while
	# looking, any other click just puts the acting hero's bar back — it must
	# never move them, which is what a stray click used to do.
	if _mode == "idle" or _viewing:
		for c in cb.combatants:
			if c.pos == hx and c.team == "party" and c != h and c.conscious():
				view_hero(c)
				return
		if _viewing:
			_stop_viewing()
			return
	if h.team != "party" or not h.conscious():
		return
	if _mode == "cone":
		var dir = Hex.direction_to(h.pos, hx)
		if dir != Vector2i.ZERO:
			_mode = "idle"
			var v := _tgt_verb
			_tgt_verb = {}
			_perform(h, v, dir)
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
			_perform(h, v, target)
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
			_coop_send(Coop.move(h, hx))
			_walk_try("move")
			_after_hero_action(h)

func _apply_target(h, c) -> void:
	var want := int(_tgt_verb.get("targets", 1))
	if want > 1:
		_picked.append(c)
		var more: bool = _picked.size() < want and cb.combatants.any(func(o): return _valid_target(h, o))
		if more:
			_actor.text = "%s — %s: %d of %d picked. Click another, or cast now.  (Esc cancels)" % [
				h.cname, _tgt_verb["label"], _picked.size(), want]
			_set_buttons([["Cast on %d" % _picked.size(), func(): _apply_target_list(h), "Cast now",
				_mark(Icons.verb_icon("spell"), "✓")],
				["Cancel", func(): board_cancel(), "Cancel", _mark(Icons.verb_icon("back"), "‹")]])
			_board.queue_redraw()
			return
		_apply_target_list(h)
		return
	_mode = "idle"
	var v := _tgt_verb
	_tgt_verb = {}
	var res = _perform(h, v, c)
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

# Every target the player picked, primary first; cast() reads the Array as
# "these and no others".
func _apply_target_list(h) -> void:
	_mode = "idle"
	var v := _tgt_verb
	_tgt_verb = {}
	var picked: Array = _picked.duplicate()
	_picked.clear()
	if picked.is_empty():
		_after_hero_action(h)
		return
	var res = _perform(h, v, picked)
	_attack_fx(h, picked[0], v)
	if typeof(res) == TYPE_DICTIONARY and (res.has("hit") or res.has("saved")):
		_busy = true
		_board.show_reveal(picked[0].id, res, _reveal_head(res))
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
			return ["CRIT" + tail, Color("ff6a4a")]
		return ["HIT" + tail, Color("8dffb0")]
	if res.get("saved", false):
		return [("SAVED" + tail) if dmg > 0 else "SAVED", Color("8fb7d8")]
	return ["FAILED SAVE" + tail, Color("ffc46a")]

func board_hex_hovered(hx: Vector2i) -> void:
	if _coop_waiting:
		return   # the board shows the other player's cursor, not ours
	_hover_hex = hx
	if _coop != null and cb.current() != null and _mine(cb.current()) and not _busy:
		_coop_send(Coop.hover(hx, _tgt_verb if _mode in ["target", "area", "cone"] else _hover_verb))
	# #173: whoever is standing here fills the card on the left, and it STAYS
	# filled — a hover that lands on nobody leaves the last one up. That is what
	# makes it readable while you reach for the verb that answers it.
	for c in cb.combatants:
		if c.pos == hx and not c.is_dead():
			_card.show_who(c, cb)
			break
	if _walk != null:
		# The card on the left fills for anybody standing here (#173), so a
		# hover that landed on a living token is the walkthrough's "inspect". Behind the null check because every other
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
	focus_cam(_cam_context(h))   # #152: the swing framed the target; the next choice needs the room
	if cb.is_over():
		_finish()
		return
	# Walked off the edge (the audit's 3.5): nothing left for them to do here.
	if h.has("withdrawn") or (h.econ["action"] <= 0 and h.econ["bonus"] <= 0 and h.econ["move_left"] <= 0):
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
	_hover_verb = {}
	var count := opts.size()
	var u := Settings.chrome_scale()
	for i in count:
		var b := SkillCard.HoverButton.new()
		var meta: Dictionary = opts[i][3] if opts[i].size() > 3 else {}
		var hotkey := String(meta.get("key", ""))
		if hotkey == "":
			if count == 1 or (_submenu != "" and i == count - 1):
				hotkey = "Esc"
			elif i == count - 1:
				hotkey = "0"
			elif i < LIST_KEYS:   # #124: the keys run out long before the bar does
				hotkey = str(i + 1)
		var tex: Texture2D = meta.get("icon")
		Icons.icon_button(b, tex, int(Icons.ICON_PX * u))
		var tip := String(opts[i][2]) if opts[i].size() > 2 else ""
		# The popup's card: the verb's own when _menu_entries built one, else
		# one made of the plain text (the slots, Swap, End turn, Cancel).
		b.card = (meta["card"] as Dictionary).duplicate() if meta.has("card") else SkillCard.from_text(tip)
		if tex != null:
			b.custom_minimum_size = BTN_SIZE * u
			_chip(b, hotkey, Control.PRESET_BOTTOM_RIGHT, Icons.COL_HEAD, u)
			_chip(b, String(meta.get("tier", "")), Control.PRESET_TOP_LEFT, Icons.COL_GOLD, u)
			if meta.has("fx"):
				var fx: Array = meta["fx"]
				_fx_mark(b, " ".join(fx.map(func(m): return String(m["text"]))), _tone_color(String(fx[0]["tone"])), u)
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
			b.card["alert"] = ["Not available right now.", Icons.COL_FOE]
		elif meta.get("armed", false):
			# A two-press verb is armed: with no label to relabel, the badge says
			# so by going warm, and the popup says it in words.
			b.modulate = Color("ffb3a8")
			tip = "Press again to confirm.\n" + tip
			b.card["alert"] = ["Press again to confirm.", Color("ffb3a8")]
		b.pressed.connect(opts[i][1])
		b.set_meta("hotkey", hotkey)
		if tutorial:
			# T32: the walkthrough's bar card asks for a slot to be hovered, and
			# this is how it hears that one was. Wired only for the guided fight
			# — an ordinary bar is rebuilt on every action and owes nothing.
			b.mouse_entered.connect(_walk_try.bind("hover_slot"))
		if meta.has("shift_fn"):
			b.set_meta("shift_fn", meta["shift_fn"])
		if meta.has("verb"):   # #92
			var hv: Dictionary = meta["verb"]
			b.mouse_entered.connect(func(): _hover_verb = hv; _board.queue_redraw())
			b.mouse_exited.connect(func():
				if _hover_verb == hv:
					_hover_verb = {}
					_board.queue_redraw())
		if tip != "":
			b.tooltip_text = tip   # the popup's trigger, and what tests read; b.card is what it shows
		_buttons.add_child(b)
	_apply_ui_scale()

# What an effect does to this button, loud enough to see without hovering: the
# badge framed in the effect's colour and a filled pill on its top-right
# corner ("ADV", "DIS", "✦", "+2d8"). The popup says why (_menu_entries).
func _fx_mark(b: Button, text: String, col: Color, u: float) -> void:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(0, 0, 0, 0)
	edge.border_color = col
	edge.set_border_width_all(maxi(2, int(2 * u)))
	edge.set_corner_radius_all(int(5 * u))
	frame.add_theme_stylebox_override("panel", edge)
	b.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pill := Label.new()
	pill.text = text
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_font_size_override("font_size", int(12 * u))
	pill.add_theme_color_override("font_color", Icons.COL_INK)
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.set_corner_radius_all(int(4 * u))
	box.content_margin_left = int(4 * u)
	box.content_margin_right = int(4 * u)
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	pill.add_theme_stylebox_override("normal", box)
	b.add_child(pill)
	pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(-4 * u))

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
	_header.text = "%s, round %d%s" % [Encounter.board_name(String(cb.board.get("theme", ""))),
		cb.round_num, "  ·  night" if cb.is_night() else ""]
	_header.tooltip_text = "seed %d" % _seed
	if _coop != null:
		_header.text += "  ·  room %s" % _coop.code
	if not cb.objective.is_empty():
		_header.text += "  ·  " + cb.objective_line()

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
	elif _coop_waiting and not _viewing:
		_actor.text = "[b]%s[/b] — your friend's turn.  Click one of yours to look at their sheet." % (cur.cname if cur else "?")
	elif _mode == "idle" and not _viewing:
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	if not _viewing:
		_show_effects(cur if cur != null and cur.team == "party" and cur.conscious() else null)
	_board.queue_redraw()

# --- the effect strip ------------------------------------------------------
#
# Beside the action bar: one chip per buff, hindrance or held spell on the
# hero whose bar it is (core/active_effects.gd says what they are and what they
# do). Edges first in green, what you are holding up in verdigris, what hurts
# you in red; the clock says how long ("3 rounds", "next attack"), the popup
# says what it does. A foe's turn clears it — nothing on it is theirs.
func _show_effects(c) -> void:
	var chips: Array = Active.of(cb, c) if c != null and cb != null else []
	var sig := var_to_str([c.id if c != null else "", chips.map(func(x): return [x["id"], x["label"], x["clock"], x["tone"]]),
		Settings.chrome_scale()])
	if sig == _fx_sig:
		return
	_fx_sig = sig
	for n in _fx.get_children():
		_fx.remove_child(n)
		n.queue_free()
	var u := Settings.chrome_scale()
	_fxscroll.custom_minimum_size.y = (FX_ROW_H * FX_ROWS + 4.0) * u
	for x in chips:
		_fx.add_child(_effect_chip(x, u))

func _effect_chip(x: Dictionary, u: float) -> PanelContainer:
	var col := _tone_color(String(x["tone"]))
	var box := Icons.box(Color(col, 0.12), col.darkened(0.15), 4, int(7 * u), int(2 * u))
	box.border_width_left = int(3 * u)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(5 * u))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = String(x["label"])
	lbl.add_theme_font_size_override("font_size", int(15 * u))
	lbl.add_theme_color_override("font_color", col.lightened(0.25))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	if String(x["clock"]) != "":
		var clk := Label.new()
		clk.text = String(x["clock"])
		clk.add_theme_font_size_override("font_size", int(12 * u))
		clk.add_theme_color_override("font_color", Icons.COL_MUTED)
		clk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(clk)
	p.add_child(row)
	p.tooltip_text = "%s%s\n%s" % [x["label"], (" — " + String(x["clock"])) if String(x["clock"]) != "" else "", x["detail"]]
	return p

static func _tone_color(tone: String) -> Color:
	match tone:
		Active.EDGE: return Icons.COL_PARTY
		Active.HINDRANCE: return Icons.COL_FOE
		Active.HOLD: return Icons.COL_ACCENT
	return Icons.COL_GOLD   # mixed

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
	_viewed_id = c.id
	_build_hero_menu(c)
	_build_order_strip()
	var res := _resources(c)
	_show_effects(c)
	_actor.text = "%s    [i]not their turn[/i]    AC %d    %s%s" % [
		"[b]%s[/b]" % c.cname, cb.effective_ac(c), _hp_bb(c), ("    " + res) if res != "" else ""]

func _stop_viewing() -> void:
	_viewing = false
	_viewed_id = ""
	var cur = cb.current() if cb != null else null
	if cur != null and cur.team == "party" and cur.conscious() and not _advancing and not _busy:
		_build_hero_menu(cur)
	else:
		_set_buttons([])
	_refresh()

# T29 spellcaster resources: one pip row per slot level the caster actually has
# (● unspent, ○ spent) plus every feature pool by name, replacing the old
# "slots 2/3" counter that only ever reported level-1 slots.
# Audit 4.1: the rows are Adapter.combat_slot_table(), whose maximum is the
# hero's SHEET, not what they walked on with — a slot spent two fights ago is
# an empty pip, and a level with nothing left is still a row. Only a foe with no
# sheet falls back to the count it started this fight with.
func _resources(c) -> String:
	var bits: Array = []
	for row in Adapter.combat_slot_table(c, _slot_max.get(c.id, [])):
		bits.append(Adapter.slot_pips(row))
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
	var u := Settings.chrome_scale()
	for c in cb.order:
		var tile := PanelContainer.new()
		var base: StyleBox
		if c == cb.current():
			# whose turn it is: a gilt rule under the tile, nothing boxed
			var box := Icons.box(Color(0.79, 0.64, 0.35, 0.12), Color(0, 0, 0, 0), 0, 6, 4)
			box.border_color = Icons.COL_GOLD
			box.border_width_bottom = 3
			base = box
		elif _viewing and c.id == _viewed_id:
			# #97: being looked at — the party's green, boxed, so the strip says
			# whose sheet the bar is showing and that it is not their turn
			var box := Icons.box(Color(0.50, 0.75, 0.42, 0.12), COL_PARTY, 0, 6, 4)
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
		# #165: the model's own face where there is one (rendered lazily, so
		# the glyph holds the spot until the next rebuild); team tint stays
		# on the name, not the portrait.
		var face := Portraits.bust(Figures3D._model_path(c), int(40 * u))
		if face != null:
			var tr := TextureRect.new()
			tr.texture = face
			tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			tv.add_child(tr)
		else:
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
		hp.text = "%d/%d%s" % [c.hp, c.max_hp, ("+%d" % c.temp_hp) if c.temp_hp > 0 else ""]
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp.add_theme_font_size_override("font_size", int(Icons.FS_SMALL * u))
		hp.add_theme_color_override("font_color", _hp_color(c))
		tv.add_child(hp)
		if _coop != null and c.team == "party":   # whose hand this one is in
			var who := Label.new()
			who.text = "yours" if _mine(c) else "theirs"
			who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			who.theme_type_variation = "Dim"
			who.add_theme_font_size_override("font_size", int(Icons.FS_SMALL * u))
			tv.add_child(who)
		if c.is_dead() or c.has("withdrawn"):   # dead, or off the field (the audit's 3.5)
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
	return "[color=#%s]♥ %d/%d%s[/color]" % [_hp_color(c).to_html(false), c.hp, c.max_hp,
		(" +%d" % c.temp_hp) if c.temp_hp > 0 else ""]

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
static var _re_num := RegEx.create_from_string(r"\b(\d+)\s+(?:(?:damage|HP|hp|gold|XP)\b|◉)")   # ◉: the coin (ui_icons.gd GP)
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
	# Damage types and conditions, in the one colour each has everywhere
	# (Icons.DAMAGE_COLORS / CONDITION_COLORS): "fire" here is the orange on
	# the spell's hover card. Last, so a name that happens to hold one of the
	# words ("Frost Giant" does not, "Poison Drake" would) keeps its team colour.
	for t in Icons.term_spans(line):
		claim.call(t[0], t[1], t[2])
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
		# `outcome`, not `result`: with a screen to look at (#74) the verdict is
		# held behind the wash and `result` stays empty until it is clicked
		# through, so reading it here threw "Invalid access to key 'xp'" and
		# took the rest of this function with it — the XP line and the loot line
		# below never printed in a played game. Headless and FAST set `result`
		# straight away, which is the whole reason no test saw it.
		_logbox.append_text("[color=#c9a45a]+%d XP, +%d ◉.[/color]\n" % [outcome["xp"], outcome["gold"]])
		# What came off the bodies, by name and in its rarity colour. It goes
		# into the shared stash either way (campaign.gd's finish_combat /
		# world.gd's _bank) — but loot that lands silently is loot nobody knows
		# they have.
		var taken: Array = outcome.get("loot", [])
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
	if _wash == null:
		return   # dismissed this frame: the node lives until queue_free lands, and still draws
	var won := res == "Victory"
	var t := _wash_age
	var k := clampf(t / 0.8, 0.0, 1.0)
	var fz := clampf(_zoom, 0.9, 1.4)
	var mid: Vector2 = _wash.size * 0.5
	# #93: both verdicts draw HERE, on the HUD layer above the figures and the
	# HP bars. The DEFEAT slam used to be the Board's own and the figures stood
	# in front of it. The Board keeps only the screen shake.
	if not won:
		_wash.draw_rect(Rect2(Vector2.ZERO, _wash.size), Color(0.30, 0.02, 0.03, 0.62 * clampf(t / 0.9, 0.0, 1.0)))
		_wash.draw_rect(Rect2(Vector2.ZERO, _wash.size), Color(0.0, 0.0, 0.0, 0.35 * clampf(t / 0.9, 0.0, 1.0)))
		if t < 0.9:                       # shockwave out of the centre
			var kk := t / 0.9
			_wash.draw_arc(mid, _wash.size.x * 0.75 * kk, 0, TAU, 48,
				Color(1.0, 0.42, 0.30, 0.55 * (1.0 - kk)), 6.0 * (1.0 - kk))
		var dslam := 1.0 + 2.2 * pow(1.0 - clampf(t / 0.30, 0.0, 1.0), 2)
		Board._centered_on(_wash, "D E F E A T", mid, int(54 * fz * dslam),
			Color(0.92, 0.22, 0.18, clampf(t / 0.12, 0.0, 1.0)))
		Board._centered_on(_wash, "the company falls…", mid + Vector2(0, 46 * fz), int(16 * fz),
			Color(0.86, 0.74, 0.68, clampf((t - 0.6) / 0.7, 0.0, 1.0)))
	else:
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
const ACTOR_LINES := 2   # #91: the readout's fixed height, in lines

# The full-screen overlays this screen can put over itself. Each one names its
# node when it opens (see each script's toggle()), so presence is the test.
const OVERLAY_NODES := ["ManualOverlay", "SettingsOverlay", "BugReportOverlay"]

func _overlay_up() -> bool:
	for n in OVERLAY_NODES:
		if has_node(NodePath(n)):
			return true
	return false

func _process(dt: float) -> void:
	if _coop != null:
		for m in _coop.take():
			_coop_recv(m)
	if _wash != null:
		_wash_age += dt
		_wash.queue_redraw()
	if _board:
		_board.tick(dt * _anim)
	if _hud_layer:
		# Issue #121: the HUD is a CanvasLayer above everything on layer 0, and
		# a full-screen overlay is an ordinary child — so HP bars, barks, damage
		# numbers and the odds chip painted straight across the open manual. The
		# tutorial card hit this first and answered it by moving ONTO this layer
		# (see _open_walk); the manual, settings and bug-report overlays are
		# shared screens that cannot, so the layer stands down while one is up.
		# They are modal anyway — "the screen underneath sleeps while we're up".
		_hud_layer.visible = not _overlay_up()
	if _hud_overlay:
		_hud_overlay.queue_redraw()
	if _hud_bars and _board:
		# The board's rect, carried by hand: a CanvasLayer breaks the Control
		# chain, so no anchor can follow the board from here.
		_hud_bars.position = _board.global_position
		_hud_bars.size = _board.size
		_hud_bars.queue_redraw()
	if _bscroll:   # grow with the wrapped rows, up to BUTTON_ROWS, then scroll
		var row := BTN_SIZE.y * Settings.chrome_scale() + 6.0
		_bscroll.custom_minimum_size.y = minf(_buttons.get_combined_minimum_size().y,
			row * BUTTON_ROWS)

# #195: "Z fighting bug exists in the health bars on fighting screen". T-hud
# lifted the bars onto a CanvasLayer above everything so a figure could not
# cover them, and that layer was the whole window. Two things followed.
#
# The bars were not the board's any more. A body panned or zoomed off the
# board's edge — or just standing on its top or bottom row, whose bar hangs
# below the token — painted its bar and "21/21" straight over the turn-order
# strip, the log, the action line and the skill bar, on top of chrome that has
# its own HP numbers in the same green: two health readouts fighting for one
# spot. They are clipped to the board's rect now, on a Control of their own
# that is that rect (the odds chip, barks and damage numbers stay on the
# unclipped overlay: they are brief, and are read over the action anyway).
#
# And they were painted in roster order, so where two bars overlapped — two
# bodies a hex apart on a diagonal, or the conditions strip of one over the
# bar of the next — whichever was fielded first went underneath whatever the
# figures in front said. Back to front now, the order the figures themselves
# stand in: the nearer body's bar is the one on top.
func _draw_hud_bars() -> void:
	if cb == null or _board == null:
		return
	var s: float = hex_px
	var fz := clampf(_zoom, 0.75, 1.7)
	var shown: Array = []
	for c in cb.combatants:
		if c.is_dead() or c.has("withdrawn"):
			continue
		shown.append([_board._tok.get(c.id, _board._pix(c.pos)) + _board._lunge(c.id), c])
	shown.sort_custom(func(a, b): return a[0].y < b[0].y)
	for e in shown:
		var p: Vector2 = e[0]
		var c = e[1]
		var rad := s * 0.62
		var tp := p if c.is_down() else p + Vector2(0, -rad * 0.55)
		Board._paint_token_hud(_hud_bars, c, _board._hp.get(c.id, float(c.hp)), p, tp, s, rad, fz)

# T-hud: what floats over the fight — odds chips, barks, damage numbers, the
# roll reveal — painted on a CanvasLayer above Board and everything Board
# parents (Figures3D included); see Board._paint_token_hud's header comment for
# why this can't just call back into Board's own drawing code. The HP bars and
# condition tags were here too, and are _draw_hud_bars' now (#195), on the same
# layer. Coordinates are Board-local; draw_set_transform(origin) once up front
# instead of adding board.global_position to every point below.
func _draw_hud_overlay() -> void:
	if cb == null or _board == null:
		return
	_hud_overlay.draw_set_transform(_board.global_position)
	var s: float = hex_px
	var fz := clampf(_zoom, 0.75, 1.7)

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

# How much of the left column the log keeps when the card is up. Tall enough
# for roughly eight entries at FS_SMALL, which is a round of a four-a-side
# fight — the window a player actually scrolls back through.
const LOG_MIN_H := 220.0

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
	#
	# #140: "what it depends on" deliberately no longer includes _origin. The
	# ground is painted in WORLD space — every tile at _pix(hx) — so moving the
	# view is a pure translation of the picture, and translating a Control is
	# free where repainting it is 124 hexes of GDScript. The cache used to key
	# on _origin, which was fine while only a drag or a zoom moved the view;
	# since the camera started following the action (#152) the pan glides after
	# every single action and converges asymptotically, so the key changed on
	# essentially every frame and the cache never hit once. Measured on this
	# board: 410 repaints in 411 frames. Now the ground is painted once per
	# board (and per zoom, which really does change the picture) and carried by
	# _ground.position; see _ground_at.
	# A Node2D, not a Control: Godot culls a Control by its own rect, and this
	# one is zero-sized and carried off by a pan (_place_layers). Once its
	# origin left the window (zoom in, then pan so the top of the board's world
	# is off-screen) the whole floor vanished under the props standing on it,
	# though every tile of it was on screen. A Node2D is culled by what it draws.
	class Ground extends Node2D:
		var board
		func _draw() -> void:
			if board.cb != null:
				board._paint_ground(self)
	# The backdrop is the one part of the old ground that is NOT world-fixed:
	# it fills the frame and crops, so it belongs to the viewport, not to the
	# hexes. It rode along inside Ground, which is why the ground could not be
	# translated. Its own child now, added first so it stays behind the ground
	# (both show_behind_parent, drawn in child order), and repainted only when
	# the rect, the palette or nightfall change.
	class Backdrop extends Control:
		var board
		func _draw() -> void:
			if board.cb != null:
				board._paint_backdrop(self)
	var _backdrop := Backdrop.new()
	var _backdrop_key := 0
	var _ground := Ground.new()
	var _ground_key := 0
	var _ground_at := Vector2.ZERO   # the _origin the ground was last painted in
	var _field := {}      # move_field of the hero whose turn it is, memoised
	var _provoke := {}    # ...and the hexes a walk there would draw an OA on
	var _field_key := 0

	func _init() -> void:
		for layer in [_backdrop, _ground]:
			layer.board = self
			layer.show_behind_parent = true
			if layer is Control:
				layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(layer)
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
	# #198: the right button both pans (held and dragged) and cancels (clicked).
	# Cancelling on the press threw away an aimed spell every time the player
	# only meant to look round the board, so the cancel waits for the release
	# and is skipped when the button travelled further than a click wobbles.
	var _rmb_travel := -1.0   # pixels dragged since the right press; < 0 when it is up
	const RMB_CLICK_SLOP := 6.0

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
						_fill_seen(hx, _hex_poly(_pix(hx), s - 3.0), Color(col.r, col.g, col.b, 0.35 * (1.0 - t)))
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
		# A new board is a new picture: drop both cached layers rather than
		# trusting the hash to differ (an identical board at an identical zoom
		# is a legal thing for a rematch to be).
		_ground_key = 0; _backdrop_key = 0; _ground_at = _origin
		_ground.queue_redraw(); _backdrop.queue_redraw()
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
		var tallest := 0
		for hx in cb.board["hexes"]:
			var p := _iso(Hex.to_pixel(hx, main.hex_px))
			mn = mn.min(p); mx = mx.max(p)
			tallest = maxi(tallest, cb.height_at(hx))
		# centres only — pad by a hex so the outermost tiles (and their labels) sit inside the frame
		var pad: Vector2 = Vector2(1.0, ISO_SQUASH) * float(main.hex_px)
		# #156: a shelf is drawn above where its hex is, so the fit has to leave
		# room for the tallest one or the top row goes under the header.
		mn.y -= RISE * float(main.hex_px) * float(tallest)
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
				_layout()
				return
		# keep the board from being panned entirely off-screen
		var lim: Vector2 = (size + span) * 0.5 - Vector2(90, 60)
		lim = lim.max(Vector2.ZERO)
		main._pan = main._pan.clamp(-lim, lim)
		_origin = (size - span) * 0.5 - mn + main._pan

	# #152: glide the view onto the camera's subjects. Zoom first — ZOOM_FOLLOW,
	# or less when the pair would not both fit — then pan so their midpoint
	# sits at the centre of the board. The pan is a delta off where they were
	# drawn last frame, so it converges instead of computing the layout twice;
	# under SORCMERC_FAST _anim is huge and both land in one frame.
	const CAM_RATE := 4.0       # 1/e in a quarter second
	const CAM_MARGIN := 140.0   # px kept round a pair, so a token is not on the edge
	func _follow_cam(dt: float) -> void:
		if not main._cam_follow or main._cam_hold or main._cam_ids.is_empty() or size.y <= 0.0:
			return
		var pts: Array = []
		for id in main._cam_ids:
			var c = main._combatant(id)
			if c != null and not c.is_dead() and not c.has("withdrawn"):
				pts.append(_tok.get(id, _pix(c.pos)))
		if pts.is_empty():
			return
		var k := clampf(dt * CAM_RATE * main._anim, 0.0, 1.0)
		var mn: Vector2 = pts[0]
		var mx: Vector2 = pts[0]
		for p in pts:
			mn = mn.min(p); mx = mx.max(p)
		var z: float = main.ZOOM_FOLLOW
		if pts.size() > 1:
			var spread: Vector2 = (mx - mn) / main._zoom   # at zoom 1
			z = minf(z, minf((size.x - CAM_MARGIN * 2.0) / maxf(spread.x, 1.0),
				(size.y - CAM_MARGIN * 2.0) / maxf(spread.y, 1.0)))
		z = clampf(z, 0.45, 3.0)
		var mid := (mn + mx) * 0.5
		if not is_equal_approx(main._zoom, z):
			# Zoom about the subject, not the origin: the midpoint stays put on
			# screen while the hexes grow under it.
			var before: Vector2 = _iso_inv(mid - _origin) / main.hex_px   # flat, zoom-free
			main._zoom = lerpf(main._zoom, z, k)
			_layout()
			mid = _pix_f(before)
		main._pan += (size * 0.5 - mid) * k
		queue_redraw()

	# A flat, zoom-free ground point (hex pixels over hex_px) back to the
	# screen, for the zoom-about-a-point step above; _pix() takes whole hexes.
	func _pix_f(flat: Vector2) -> Vector2:
		return _origin + _iso(flat * main.hex_px)

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

	# #156: how far UP the screen a hex's floor sits, per level of height. A
	# level is five feet, one hex radius, and a vertical rise is the one
	# direction the projection does not squash along the ground — it comes
	# toward the camera, so it is foreshortened by cos(pitch) and lands as a
	# plain screen-y offset. The honest number is ISO_GAIN * cos(45°) ≈ 1.3 hex
	# radii, which reads as a staircase on a board where two shelves can touch;
	# RISE is the same idea pulled back to where a shelf still says "up" at a
	# glance without the board looking terraced. scenes/figures3d.gd derives a
	# figure's world lift from this, so the model and its tile stay welded.
	const RISE := 0.9

	func _rise(hx: Vector2i) -> float:
		return -RISE * main.hex_px * float(cb.height_at(hx)) if cb != null else 0.0

	# Where the hex's floor would be with no height in it. This — not _pix — is
	# a hex's DEPTH in the scene, so it is what the ground sorts on: a shelf is
	# drawn above its own footprint, but still behind the row in front of it.
	func _flat_pix(hx: Vector2i) -> Vector2:
		return _origin + _iso(Hex.to_pixel(hx, main.hex_px))

	func _pix(hx: Vector2i) -> Vector2:
		return _flat_pix(hx) + Vector2(0, _rise(hx))

	# screen point -> hex, the inverse of _pix
	func _unpix(sp: Vector2) -> Vector2i:
		var flat := Hex.from_pixel(_iso_inv(sp - _origin), main.hex_px)
		if cb == null or cb.board.get("height", {}).is_empty():
			return flat
		# With height in the board the inverse is no longer a function: a point
		# on a shelf's top face and a point on the ground behind it are the same
		# pixel. Take whichever nearby hex is actually drawn with its centre
		# nearest the cursor, and on a tie the higher one, since that is the one
		# painted over the other.
		var best := flat
		var best_d := (sp - _pix(flat)).length_squared()
		var best_h: int = cb.height_at(flat)
		for h in Hex.within(flat, 2):
			if not (h in cb.board["hexes"]):
				continue
			var d := (sp - _pix(h)).length_squared()
			var hh: int = cb.height_at(h)
			if d < best_d or (is_equal_approx(d, best_d) and hh > best_h):
				best = h
				best_d = d
				best_h = hh
		return best

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
				if o.get("blocks_sight", false):
					what += "; until then it blocks the way and the line of sight"
				if o.get("explosive", false):
					what += "; it bursts for %s %s to everything around it" % [h.get("dice", "2d6"), h.get("damage_type", "fire")]
				what += "."
			elif not h.is_empty():
				what += " — a hazard. Shove somebody standing beside it in for %s %s." % [h.get("dice", "2d6"), h.get("damage_type", "fire")]
			elif o.get("blocks_sight", false):
				what += " — solid. Nobody can stand here, see through it or shoot past it."
			elif o.get("blocks_movement", false):
				what += " — in the way. Nobody can stand here."
			else:
				what += " — light and nothing more."
			lines.append(what)
		if combat.is_cover(hx):
			lines.append("Half cover — +2 AC and +2 on saving throws for whoever stands here.")
			if hx in combat.board.get("screens", []):
				lines.append("Tall enough to hide behind — nobody sees or shoots across it.")
		if hx in combat._rough():
			lines.append("Rough ground — every step here costs two.")
		var up: int = combat.height_at(hx)
		if up > 0:
			lines.append(("Raised ground, %d up — climbing on costs a step extra, "
				+ "and anything you swing at or shoot from up here is +%d to hit.")
				% [up, combat.HIGH_GROUND_HIT])
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
		# #239: and the picture this layer painted is in the old view too. The
		# figures (Figures3D._process) and the HP bars (main's HUD overlay) are
		# placed every frame off _tok, so they followed the move at once; this
		# layer only repaints when something queues it, and a view that moved
		# inside a _layout() — the pan clamp, the board's rect settling, a zoom
		# the follow-cam finished — queued nothing. What was left behind was
		# every token's shadow disc and the active ring, still where the tokens
		# USED to be: dark rings on empty tiles under nobody, and a gold ring
		# with no one standing in it. Same family as #194 was for the ground.
		queue_redraw()

	func tick(dt: float) -> void:
		if cb == null:
			return
		_follow_cam(dt)
		# #112: lay out FIRST. _layout() used to run at the end of this, so the
		# re-base and every _pix() below saw last frame's origin while _draw()
		# saw this frame's — one frame of lag per frame of drag, which is the
		# wobble the discs and HP bars had after #71 fixed the figures' slide.
		_layout()
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
		# #140: no _origin here — see the Ground comment. A pan is carried by
		# _ground.position in _draw(); only the scale and the board itself
		# change the picture. cb.board stays in the key because a smashed crate
		# or a spent hazard is painted into the ground.
		var key := hash([main.hex_px, cb.board])
		if key != _ground_key:
			_ground_key = key
			_covers_of = null   # #242: the same board change can move a shelf
			_ground_at = _origin
			_ground.queue_redraw()
			queue_redraw()   # the tokens, marks and figures are in the new view too
		# #194: the layer is carried here as well as in _draw(). A repaint above
		# re-bases it (_ground_at = _origin), but only the board's own _draw()
		# used to move it, and nothing queues that when the zoom changed inside
		# a _layout() (auto-fit) or while nothing on the board was animating.
		# The fresh ground then sat at the OLD offset, out from under the props
		# and figures, until some animation happened to redraw the board: "the
		# grid and the ground are off, and correct themselves after a few
		# seconds".
		_ground.position = _origin - _ground_at
		var back := hash([size, cb.board.get("palette", "shrine"), cb.is_night()])
		if back != _backdrop_key:
			_backdrop_key = back
			_backdrop.queue_redraw()

	# #92: the reach of `v` from where `cur` stands. Range is the verb's own
	# (a weapon's is the wielder's reach); a cone is everything it could sweep;
	# #242: "height difference shows the overlap color, just keep the high and
	# visible color". The ground is painted back to front (_paint_ground_at), so
	# a raised tile covers the ground behind it. Everything painted on top of the
	# ground each frame — the move field, a spell's reach, a zone, the dark, the
	# rings — was not: it is drawn per hex, in board order, at the full size of
	# the hex. So the wash of a low tile behind a shelf spilled up over the
	# shelf's top face, and where that face had a wash of its own the two
	# stacked into a third, deeper colour in a band across the step: the tile
	# you can see, tinted by one you cannot. The fix is the ground's own rule —
	# what is behind a raised tile is hidden by it — applied to the overlays:
	# each is cut by the top faces of the higher tiles in front of it before it
	# is drawn, so a hex's wash lands only on the part of it the player can see.
	#
	# Only a HIGHER tile in FRONT can cover a hex. One behind is painted first
	# and drawn higher up the screen, away from it; one at the same height or
	# lower has its top face beside or below this one's; and the cut earth under
	# a shelf hangs off its front edges only, toward the row in front of it. So
	# the top faces are the whole of what can hide a hex, and the list per hex
	# is short — usually empty. Which hexes those are depends on the board
	# alone, never on the pan or the zoom, so it is worked out once per board
	# (and again whenever tick() sees the board change, the same key the ground
	# repaints on). Flat boards have no list at all and draw exactly what they
	# always drew.
	var _covers := {}          # hex -> [hexes whose top face can hide part of it]
	var _covers_of = null      # the board dictionary _covers was built for

	func _covering(hx: Vector2i) -> Array:
		if not is_same(_covers_of, cb.board):
			_covers_of = cb.board
			_covers = {}
			var hs: Dictionary = cb.board.get("height", {})
			var on := {}
			for h in cb.board["hexes"]:
				on[h] = true
			var depth := func(h: Vector2i) -> float: return _iso(Hex.to_pixel(h, 1.0)).y
			# From each raised tile outward, not from every hex inward: a board
			# has a handful of raised tiles and a hundred-odd flat ones. A tile
			# lifted h levels moves 0.9 h hex radii up the screen (RISE) and a
			# row is about two radii deep, so h + 2 rings is past anything its
			# top face can reach; anything it does not actually overlap is
			# harmless in the list — the clip hands the polygon back whole.
			for n in hs:
				var hn: int = cb.height_at(n)
				if hn <= 0 or not on.has(n):
					continue
				for a in Hex.within(n, hn + 2):
					if on.has(a) and cb.height_at(a) < hn and depth.call(a) < depth.call(n):
						if not _covers.has(a):
							_covers[a] = []
						_covers[a].append(n)
		return _covers.get(hx, [])

	# The parts of `poly` (drawn for hex `hx`) that no higher tile in front
	# covers. [poly] itself on a flat board or an uncovered hex.
	func _seen(hx: Vector2i, poly: PackedVector2Array) -> Array:
		var over := _covering(hx)
		if over.is_empty():
			return [poly]
		var out: Array = [poly]
		for n in over:
			var top := _hex_poly(_pix(n), main.hex_px)
			var cut: Array = []
			for p in out:
				# Two hexes never nest, so clip_polygons hands back outlines
				# only — no holes to draw around.
				cut.append_array(Geometry2D.clip_polygons(p, top))
			out = cut
			if out.is_empty():
				break
		return out

	# #242: draw_colored_polygon for a hex's overlay, cut to what is visible.
	func _fill_seen(hx: Vector2i, poly: PackedVector2Array, col: Color) -> void:
		for p in _seen(hx, poly):
			draw_colored_polygon(p, col)

	# ...and draw_polyline for a ring round a hex, the same way: a ring is a
	# closed outline, so what survives the cut is one or more open runs of it.
	func _ring_seen(hx: Vector2i, ring: PackedVector2Array, col: Color, w: float) -> void:
		var runs: Array = [ring]
		for n in _covering(hx):
			var top := _hex_poly(_pix(n), main.hex_px)
			var cut: Array = []
			for r in runs:
				cut.append_array(Geometry2D.clip_polyline_with_polygon(r, top))
			runs = cut
		for r in runs:
			if r.size() >= 2:
				draw_polyline(r, col, w, true)

	# Whether a point on hex `hx` — its centre, where a glyph goes — is in view.
	func _point_seen(hx: Vector2i, at: Vector2) -> bool:
		for n in _covering(hx):
			if Geometry2D.is_point_in_polygon(at, _hex_poly(_pix(n), main.hex_px)):
				return false
		return true

	# an area spell is every hex it could be centred on. Targets ring in the
	# side's colour — red for a foe, the party's green for an ally.
	const COL_REACH := Color(0.95, 0.85, 0.45, 0.14)
	func _draw_reach(cur, v: Dictionary, s: float) -> void:
		var targeting := String(v.get("targeting", "self"))
		var r := int(v.get("range", 1))
		if v["kind"] in ["attack", "offhand_attack"] and (targeting == "enemy"):
			r = cur.atk_range if cur.ranged else cur.reach
		elif targeting == "direction":
			r = int(v.get("radius", 2))
		elif targeting in ["self", "self_area"]:
			r = int(v.get("radius", 0))
		for hx in cb.board["hexes"]:
			if hx == cur.pos or Hex.distance(cur.pos, hx) > r or not cb.has_line_of_sight(cur.pos, hx):
				continue
			if targeting in ["hex", "line"] and not cb.legal_area(cur, v, hx):
				continue
			_fill_seen(hx, _hex_poly(_pix(hx), s - 2.0), COL_REACH)
		if targeting in ["enemy", "ally"]:
			var oc: Color = main.COL_TARGET if targeting == "enemy" else main.COL_PARTY
			for c in cb.combatants:
				if cb.legal_target(cur, v, c):
					var poly := _hex_poly(_pix(c.pos), s - 3.0)
					poly.append(poly[0])
					_ring_seen(c.pos, poly, Color(oc.r, oc.g, oc.b, 0.55), 2.0)
		elif targeting == "self":
			var poly := _hex_poly(_pix(cur.pos), s - 3.0)
			poly.append(poly[0])
			_ring_seen(cur.pos, poly, Color(main.COL_PARTY, 0.55), 2.0)

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
			"%d/%d%s" % [c.hp, c.max_hp, ("+%d" % c.temp_hp) if c.temp_hp > 0 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * fz), Color("c9ccd6"))

		# condition strip, centred over the token (the shoulder is the class badge's).
		# One run per condition, each in its own colour (Icons.CONDITION_COLORS):
		# a stunned goblin's ✷ is the yellow the log says "stunned" in.
		var runs: Array = []   # [text, colour]
		for id in Icons.CONDITION_ORDER:
			if id != "down" and c.has(id):
				runs.append([Icons.condition_glyph(id), Icons.condition_color(id)])
		if c.is_stable(): runs.append([" %s stable" % Icons.condition_glyph("down"), Icons.condition_color("down")])
		elif c.is_down(): runs.append([" %s%d/%d" % [Icons.condition_glyph("down"), c.death_s, c.death_f],
			Icons.condition_color("down")])
		if not runs.is_empty():
			var fs := int(13 * fz)
			var f := ThemeDB.fallback_font
			var w := 0.0
			for r in runs:
				w += f.get_string_size(String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := tp + Vector2(0, -rad * 0.8 - 10) - Vector2(w * 0.5, -fs * 0.36)
			for r in runs:
				canvas.draw_string_outline(f, at, String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Icons.COL_INK)
				canvas.draw_string(f, at, String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, r[1])
				at.x += f.get_string_size(String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

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
				if _rmb_travel >= 0.0:
					_rmb_travel += e.relative.length()
				main.pan_by(e.relative)
				return
			var hx := _unpix(e.position)
			_hover_pt = _iso_inv(e.position - _origin)
			if main._coop_waiting:
				return   # the board is showing the other player's cursor
			if hx != _hover:
				_hover = hx
				main.board_hex_hovered(hx)
			elif main._mode == "area":
				queue_redraw()   # a corner can change without the hex changing
		elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var click := _rmb_travel >= 0.0 and _rmb_travel <= RMB_CLICK_SLOP
			_rmb_travel = -1.0
			if click:
				main.board_cancel()
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(e.position, 1.1)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(e.position, 1.0 / 1.1)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				_rmb_travel = 0.0
			elif e.button_index == MOUSE_BUTTON_LEFT:
				main.board_hex_clicked(_unpix(e.position))

	# Stable per-hex noise: same hex, same salt -> same value, every frame. No RNG
	# state, so nothing here can perturb the game's seeded rolls.
	static func _is_hazard(obj: Dictionary) -> bool:
		return obj.has("hazard") and not obj.get("blocks_movement", false)

	# Everything about the ground that is the same picture every frame: the
	# slab, floor texture, mottling, seams, the cover label and the foliage.
	# Hazards are skipped — their glow pulses, so Board._draw paints them live.
	# #73: fill the frame, crop the overflow, keep the horizon high. Its own
	# layer since #140 — it is the one thing here that belongs to the viewport
	# rather than to the hexes, and keeping it inside the ground is what stopped
	# the ground from being translated instead of repainted.
	func _paint_backdrop(canvas: CanvasItem) -> void:
		var back: Texture2D = Icons.image_at(String(main.BACKDROPS.get(cb.board.get("palette", "shrine"), "")))
		if back == null:
			return
		var k := maxf(size.x / back.get_width(), size.y / back.get_height())
		var sz := back.get_size() * k
		canvas.draw_texture_rect(back, Rect2(Vector2((size.x - sz.x) * 0.5, minf(0.0, (size.y - sz.y) * 0.3)), sz),
			false, BACKDROP_NIGHT if cb.is_night() else BACKDROP_TONE)

	# Painted in the view _ground_at names, not the one on screen: _draw()
	# translates the layer onto the live one. Every _pix() below therefore has
	# to read _ground_at, which is what the swap around the body is for — the
	# alternative is threading an origin through _pix, _paint_tile, _paint_floor,
	# _light_board and _foliage_at, all of which exist to be read at a glance.
	func _paint_ground(canvas: CanvasItem) -> void:
		var live := _origin
		_origin = _ground_at
		_paint_ground_at(canvas)
		_origin = live

	# #140: where the two cached layers sit this frame — the ground carried from
	# the view it was painted in onto the one being drawn, the sky viewport-fixed
	# and so only ever shaken. Its own function rather than four lines inside
	# _draw() because it is the whole of the cache's correctness, and a test can
	# ask for it without a draw pass.
	func _place_layers(shake: Vector2) -> void:
		_ground.position = _origin - _ground_at
		_backdrop.position = shake

	func _paint_ground_at(canvas: CanvasItem) -> void:
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
		# #156: a raised tile is drawn over its own footprint, so the tiles stop
		# being disjoint and the order they are painted in starts to matter.
		# Back to front by DEPTH — where each hex's floor would be with no
		# height in it — so a shelf covers the ground it stands on and the row
		# in front of it still covers the shelf. Flat boards skip the sort and
		# keep the order they always had.
		var tiles: Array = cb.board["hexes"]
		var raised: bool = not cb.board.get("height", {}).is_empty()
		if raised:
			tiles = tiles.duplicate()
			tiles.sort_custom(func(a, b): return _flat_pix(a).y < _flat_pix(b).y)
		for hx in tiles:
			var c := _pix(hx)
			var obj: Dictionary = cb.object_at(hx)
			if raised:
				_paint_shelf(canvas, hx, c, s)
			if not _is_hazard(obj):
				_paint_tile(canvas, hx, c, s, 0.0)
			if obj.is_empty():
				var d := _foliage_at(hx, c, s)
				if not d.is_empty():
					decor.append(d)
		decor.sort_custom(func(a, b): return a["at"].y < b["at"].y)
		for d in decor:
			_draw_foliage(canvas, d, s)

	# #156: the cut earth under a raised tile. Only the edges facing the camera
	# are drawn — the other three are behind the tile's own top face — and each
	# one drops to the height of the neighbour it faces, so a two-level shelf
	# beside a one-level one shows one level of rock, not two. The rim line is
	# what makes a shelf read as a step rather than as a differently-lit tile.
	# Cut earth, not a hole: the face is the board's own floor colour taken
	# down, and the rim is that colour taken up, so a shelf on the ice board is
	# blue rock and one in the shrine is brown. A flat dark quad read as a gap
	# in the ground rather than as a step in it.
	func _paint_shelf(canvas: CanvasItem, hx: Vector2i, c: Vector2, s: float) -> void:
		var here: int = cb.height_at(hx)
		if here <= 0:
			return
		var fill: Color = main.PALETTES.get(cb.board.get("palette", "shrine"), main.COL_HEX)
		var face: Color = main.shelf_face(fill)
		var rim: Color = main.shelf_rim(fill)
		var floor_tex: Texture2D = main.FLOORS.get(cb.board.get("palette", "shrine"))
		var top := _hex_poly(c, s)
		var lip: Array = []
		for i in top.size():
			var a: Vector2 = top[i]
			var b: Vector2 = top[(i + 1) % top.size()]
			if (a.y + b.y) * 0.5 <= c.y:
				continue                       # an upper edge: the top face hides it
			var below: int = cb.height_at(_edge_neighbour(hx, (a + b) * 0.5 - c))
			var drop: float = RISE * s * float(here - below)
			if drop <= 0.0:
				continue
			_paint_cliff(canvas, a, b, drop, s, face, floor_tex, hx)
			lip.append([a, b])
		for e in lip:
			canvas.draw_line(e[0], e[1], rim, maxf(1.5, s * 0.07))

	# #197: one face of cut earth. It used to be a flat fill of shelf_face,
	# which on the dark boards came out near black and read as a hole in the
	# ground ("empty space between the cells"). It is rock now: the floor's own
	# texture run down the face, lit at the lip and dark at the foot, a face
	# turned toward the board's light a shade brighter than one turned away,
	# and a dark line where it meets the ground so it stands ON something.
	const CLIFF_TOP := 1.55    # the face's colour at the lip, against shelf_face
	const CLIFF_FOOT := 0.6    # ...and at the foot
	const CLIFF_TURN := 0.22   # how much the side turned to the light gains over the side turned away
	func _paint_cliff(canvas: CanvasItem, a: Vector2, b: Vector2, drop: float, s: float,
			face: Color, tex: Texture2D, hx: Vector2i) -> void:
		var down := Vector2(0, drop)
		var quad := PackedVector2Array([a, b, b + down, a + down])
		var edge := (b - a).normalized()
		var toward: float = clampf(Vector2(-edge.y, edge.x).dot(_iso(LIGHT).normalized()) * -1.0, -1.0, 1.0)
		var k: float = 1.0 + CLIFF_TURN * toward
		var lit := Color(face.r * CLIFF_TOP * k, face.g * CLIFF_TOP * k, face.b * CLIFF_TOP * k)
		var foot := Color(face.r * CLIFF_FOOT * k, face.g * CLIFF_FOOT * k, face.b * CLIFF_FOOT * k)
		canvas.draw_polygon(quad, PackedColorArray([lit, lit, foot, foot]))
		if tex != null:
			# u along the edge, v down the face: the strata run level, and each
			# hex starts the texture somewhere of its own so a long wall does not
			# repeat one tile's worth of rock.
			var span: float = s * main.FLOOR_SPAN
			var u0: float = float(absi(hash(hx)) % 97) / 97.0
			var w: float = a.distance_to(b) / span
			var h: float = drop / span
			var uvs := PackedVector2Array([Vector2(u0, 0.0), Vector2(u0 + w, 0.0),
				Vector2(u0 + w, h), Vector2(u0, h)])
			var t: float = main.FLOOR_TONE * 0.55 * k
			canvas.draw_polygon(quad, PackedColorArray([Color(t, t, t, 0.55), Color(t, t, t, 0.55),
				Color(t * 0.5, t * 0.5, t * 0.5, 0.55), Color(t * 0.5, t * 0.5, t * 0.5, 0.55)]), uvs, tex)
		canvas.draw_line(a + down, b + down, Color(0, 0, 0, 0.55), maxf(1.0, s * 0.05))

	# Which neighbour of `hx` lies across an edge, given that edge's midpoint as
	# an offset from the hex's own centre. Asked this way rather than carried
	# through _hex_poly, whose corner order every other caller depends on.
	func _edge_neighbour(hx: Vector2i, toward: Vector2) -> Vector2i:
		var here := _flat_pix(hx)
		var best: Vector2i = hx
		var best_d := 1e30
		for n in Hex.neighbors(hx):
			var d: float = toward.distance_squared_to(_flat_pix(n) - here)
			if d < best_d:
				best_d = d
				best = n
		return best

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
	# `lift` is how far up the screen the tile is drawn (_rise). The texture is
	# read where the tile's FOOTPRINT is, so a shelf carries its own patch of
	# ground up with it. #197: reading it where the tile is drawn made a raised
	# top continue the pattern of the lower tile behind it, seamlessly, and the
	# step vanished into one flat picture.
	func _paint_floor(canvas: CanvasItem, poly: PackedVector2Array, s: float, alpha: float, light := 1.0, lift := 0.0) -> void:
		var floor_tex: Texture2D = main.FLOORS.get(cb.board.get("palette", "shrine"))
		var fill: Color = main.PALETTES.get(cb.board.get("palette", "shrine"), main.COL_HEX)
		canvas.draw_colored_polygon(poly, Color(fill, alpha))
		if floor_tex == null:
			return
		var uvs := PackedVector2Array()
		for pt in poly:
			uvs.append(_iso_inv(pt - Vector2(0, lift) - _origin) / (s * main.FLOOR_SPAN))
		var tone: float = main.FLOOR_TONE * light
		canvas.draw_polygon(poly, PackedColorArray([Color(tone, tone, tone * 1.04, main.FLOOR_ALPHA * alpha)]), uvs, floor_tex)

	# #156: and a step up is a step nearer the light. A small brightening, but
	# it is what stops a shelf's top from reading as the same tile drawn a few
	# pixels north of where it belongs.
	const SHELF_LIT := 0.13
	func _paint_tile(canvas: CanvasItem, hx: Vector2i, c: Vector2, s: float, pulse: float) -> void:
		var poly := _hex_poly(c, s)   # full size: no gutter between hexes, the texture runs through
		var obj: Dictionary = cb.object_at(hx)
		if obj.is_empty():
			_paint_floor(canvas, poly, s, 1.0, _light_at(c) * (1.0 + SHELF_LIT * float(cb.height_at(hx))), _rise(hx))
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
	# O-biome: the moor is scrubbier than a wood floor but nothing like as
	# dense; the marsh is reed, which stands in clumps and is the thickest of
	# the set. Cosmetic only — cover and rough are the board's, not this.
	const FLORA := {"forest": 0.55, "camp": 0.22, "shrine": 0.12, "ice": 0.14,
		"city": 0.0, "shop": 0.0, "downs": 0.34, "marsh": 0.62}
	const FLORA_COL := {"forest": "3f6b3a", "camp": "5c5f33", "shrine": "3a5548",
		"ice": "5d7a84", "city": "3f5240", "shop": "3f5240",
		"downs": "6b7a42", "marsh": "4c6b4a"}

	# {} for bare ground, else the plant to draw. Cover hexes always get one —
	# the thing you are hiding behind should be visible.
	func _foliage_at(hx: Vector2i, c: Vector2, s: float) -> Dictionary:
		# #167: when the 3D layer has furniture up, it owns what stands on a hex.
		# Two answers to "what is on this tile" drawn one over the other reads as
		# neither, and the 3D layer draws above this one.
		if main._figures != null and main._figures.props_on():
			return {}
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
		# #167: the 3D layer draws the furniture itself when it is up. A hazard
		# still pulses here whatever is standing on it — that glow is a rule being
		# told, not a picture of a barrel, and it is the one thing on this hex a
		# player is entitled to see through anything drawn over it.
		if main._figures != null and main._figures.props_on() \
				and not (o.has("hazard") and not o.get("blocks_movement", false)):
			return
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
		var shake := Vector2.ZERO
		if _defeat >= 0.0 and _defeat < 0.6:     # screen shake on the wipe
			var m := (1.0 - _defeat / 0.6) * 10.0
			shake = Vector2(randf_range(-m, m), randf_range(-m, m))
			_origin += shake
		_place_layers(shake)
		var s: float = main.hex_px
		var fz := clampf(main._zoom, 0.75, 1.7)   # font scale, gentler than the hex scale
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 350.0)

		var field := {}
		var provoke := {}
		var cone_hexes := {}
		var cur = cb.current()
		var hero_turn: bool = cur and cur.team == "party" and cur.conscious()
		if hero_turn and main._mode == "idle" and not main._viewing and main._hover_verb.is_empty() \
				and cur.econ["move_left"] > 0 and not main._coop_waiting:   # #92: a hovered skill's reach replaces the move field; the watcher is not offered one
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
		# objectives: the road out of a breakout, the treeline a quarry runs for
		var road := {}
		for e in cb.objective.get("exit", []):
			road[e] = true
		# The design audit §3.5: where a hero can walk off the field, shown on a
		# hero's turn in a fight that allows it — brighter under the hero who
		# is standing on it, so "Leave the field" is never a hidden button.
		var edge := {}
		if hero_turn and cb.can_withdraw and cb.is_hero(cur):
			for e in cb.edge_hexes():
				edge[e] = true
		# tiles: the ground itself is on _ground (see Ground); only what moves
		# frame to frame is painted here, on top of it.
		var night: bool = cb.is_night()
		for hx in cb.board["hexes"]:
			var c := _pix(hx)
			var poly := _hex_poly(c, s - 2.0)
			var obj: Dictionary = cb.object_at(hx)
			if _is_hazard(obj):
				_paint_tile(self, hx, c, s, pulse)   # its glow pulses, so it can't be cached
			# #242: every wash and rim below goes through _fill_seen/_ring_seen,
			# cut to the part of this hex a raised tile in front does not hide.
			if night and not cb.lit(hx):   # #85: the dark, over everything the ground painted
				_fill_seen(hx, _hex_poly(c, s), main.COL_NIGHT)
			if zone_tint.has(hx):
				var zc: Color = zone_tint[hx]
				_fill_seen(hx, poly, Color(zc.r, zc.g, zc.b, 0.30 + 0.06 * pulse))
				var rim := _hex_poly(c, s - 3.0)
				rim.append(rim[0])
				_ring_seen(hx, rim, Color(zc.r, zc.g, zc.b, 0.75), 1.5)
			if field.has(hx) and hx != cur.pos:
				_fill_seen(hx, poly, main.COL_MOVE)
			if road.has(hx):
				_fill_seen(hx, poly, main.COL_EXIT)
			elif edge.has(hx):
				# a pale rim on every edge hex, and the one under the hero filled
				var erim := _hex_poly(c, s - 4.0)
				erim.append(erim[0])
				_ring_seen(hx, erim, main.COL_EDGE, 2.0)
				if hx == cur.pos:
					_fill_seen(hx, poly, Color(main.COL_EDGE, 0.30 + 0.12 * pulse))
			if cone_hexes.has(hx):
				_fill_seen(hx, poly, main.COL_CONE)
			if provoke.has(hx) and _point_seen(hx, c):
				draw_string(ThemeDB.fallback_font, c - Vector2(6, -5), "⚠", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffcf47"))
			if not obj.is_empty():
				_draw_object(obj, c, s, pulse)

		# the valid-target ring stays here, under the tokens — it just traces the
		# hex edge, which reads fine as "this hex is targetable," not a card that
		# needs to sit on top of anything.
		# #92: what the skill in hand (aimed, or just hovered on the bar) can
		# reach — a wash over the hexes in range, a ring on each legal target.
		if hero_turn and not main._viewing:
			var shown: Dictionary = main._tgt_verb if main._mode in ["target", "area", "cone"] else main._hover_verb
			if not shown.is_empty():
				_draw_reach(cur, shown, s)
		if hero_turn and main._mode == "target":
			for c in cb.combatants:
				if not main._valid_target(cur, c):
					continue
				var tp := _pix(c.pos)
				var hot: bool = c.pos == _hover
				var poly := _hex_poly(tp, s - 3.0)
				poly.append(poly[0])
				var oc: Color = main.COL_TARGET
				_ring_seen(c.pos, poly, oc if hot else Color(oc.r, oc.g, oc.b, 0.45), 3.0 if hot else 2.0)
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
				_ring_seen(c.pos, poly, oc if (held or hot) else Color(oc.r, oc.g, oc.b, 0.40),
					3.5 if held else (3.0 if hot else 2.0))
		elif hero_turn and main._mode == "idle" and cur.econ["action"] > 0:
			for f in cb.enemies_of(cur):
				if cb.in_reach(cur, f):
					var poly := _hex_poly(_pix(f.pos), s - 3.0)
					poly.append(poly[0])
					_ring_seen(f.pos, poly, Color(main.COL_TARGET.r, main.COL_TARGET.g, main.COL_TARGET.b, 0.30), 1.5)

		# tokens, painted back-to-front so nearer ones overlap farther ones
		# ...and not the ones who walked off the edge (the audit's 3.5): gone, not dead
		var order: Array = cb.combatants.filter(func(c): return not c.is_dead() and not c.has("withdrawn"))
		order.sort_custom(func(a, b): return _tok.get(a.id, _pix(a.pos)).y < _tok.get(b.id, _pix(b.pos)).y)
		for c in order:
			var p: Vector2 = _tok.get(c.id, _pix(c.pos)) + _lunge(c.id)
			var base: Color = main.COL_PARTY if c.team == "party" else main.COL_FOE
			if c.has("bystander"):
				base = main.COL_BYSTANDER
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
			return   # nothing hovers over a wipe (#93: the slam itself is main's wash, on the HUD layer)

		# #173: the hover stat card that used to be drawn here is
		# scenes/combat_card.gd now — top of the left column, sticky, and with
		# room for the ability scores and the spell/trait split it never had.
		# Nothing replaces it on the board: a second copy of the same four lines
		# under the cursor is what made the first one unreadable.

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
