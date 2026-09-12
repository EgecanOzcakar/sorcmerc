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
const LpcArt = preload("res://core/lpc_art.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")

# What T5 injects before the scene runs: the live party, the node's spec (empty ->
# the scaler sizes one) and its difficulty. `result` is resolve_outcome() once the
# fight is over — deaths / xp / gold / loot for the campaign layer.
var party                       # core/party.gd; a Presets demo party when null
var spec: Dictionary = {}
var difficulty := "normal"
var scouted_ahead := false      # T39: campaign scouted this node — surprise is automatic
var tutorial := false           # T32: run the guided walkthrough over this fight
var result: Dictionary = {}
var _own_party := false

const HEX_BASE := 34.0
const REVEAL_PAUSE := 0.75  # beat to read the attack roll (0 under SORCMERC_FAST)
var _zoom := 1.0
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
var _hover_hex := Vector2i(999, 999)
var _anim := 1.0             # animation speed multiplier (huge when FAST)
var _slot_max := {}          # id -> slots at the start of the fight (for the pips)
var _fx_on := false           # attack animations: off under SORCMERC_FAST / headless
# T-actionbar: a compact icon grid, up to BTN_COLUMNS*BUTTON_ROWS visible before
# it scrolls (see _process's _bscroll sizing) — plain text rows read fine up to
# ~9 verbs but sprawled once a caster's spell list pushed past 20.
const BTN_COLUMNS := 6
const BTN_SIZE := Vector2(126, 40)
# Session-only "which verbs does this player actually reach for" — no save file,
# resets with the app. Keyed by a verb's id ("attack", "dash", ...) or "spell:"
# + the base spell id (so a caster's upcast tiers count as the one spell they
# picked, not N separate counters). Read by _prioritize(), written by
# _set_buttons() on every button press.
var _verb_freq: Dictionary = {}

@onready var _header := Label.new()
@onready var _order := HBoxContainer.new()   # turn-order icon strip along the top
@onready var _hint := Label.new()
@onready var _board := Board.new()
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

	_header.add_theme_font_size_override("font_size", Icons.FS_TITLE)
	_header.add_theme_color_override("font_color", Icons.COL_HEAD)
	col.add_child(_header)

	# --- the action log: a full-height sidebar down the left edge -----
	_logwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var logwrap := _logwrap
	logwrap.custom_minimum_size = Vector2(_log_width(), 0)
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
	root.add_child(col)

	# --- turn order: one icon tile per combatant, along the top -------
	var orderwrap := PanelContainer.new()
	var obox := StyleBoxFlat.new()
	obox.bg_color = Icons.COL_PANEL
	obox.set_corner_radius_all(10)
	obox.set_border_width_all(1)
	obox.border_color = Icons.COL_EDGE
	obox.set_content_margin_all(6)
	orderwrap.add_theme_stylebox_override("panel", obox)
	_order.add_theme_constant_override("separation", 10)
	_order.alignment = BoxContainer.ALIGNMENT_CENTER
	_order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orderwrap.add_child(_order)
	col.add_child(orderwrap)

	_hint.text = "1-9 actions · scroll/± zoom · drag/arrows pan · Home reset"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Icons.COL_MUTED)
	_hint.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
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
	_new_game()
	if tutorial:
		_walk_show(0)

# Font sizes across the whole combat UI track the zoom level.
func _apply_ui_scale() -> void:
	var u := clampf(_zoom, 0.9, 1.4)
	_header.add_theme_font_size_override("font_size", int(Icons.FS_TITLE * u))
	_actor.add_theme_font_size_override("normal_font_size", int(Icons.FS_HEAD * u))
	_actor.add_theme_font_size_override("bold_font_size", int(Icons.FS_HEAD * u))
	_cap.add_theme_font_size_override("font_size", int(Icons.FS_CAPTION * u))
	# the log is a narrow sidebar now — body size wraps far less than head size
	_logbox.add_theme_font_size_override("normal_font_size", int(Icons.FS_BODY * u))
	_logbox.add_theme_font_size_override("bold_font_size", int(Icons.FS_BODY * u))
	for b in _buttons.get_children():
		b.add_theme_font_size_override("font_size", int(Icons.FS_BODY * u))
		b.custom_minimum_size = BTN_SIZE * u

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
	if not (e is InputEventKey and e.pressed) or _walk != null:
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
		KEY_0, KEY_SPACE:
			_press_hotkey(-1)  # last button (End turn / Cancel)

func _press_hotkey(idx: int) -> void:
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
	_slot_max.clear()   # the combatant only tracks slots left; the pips need the max
	for c in cb.combatants:
		_slot_max[c.id] = c.slots.duplicate()
	_logbox.text = ""
	_logged = 0
	_last_round = 1
	_board.reset(cb)
	_flush_log()
	_refresh()
	# T39: surprise is settled before anyone acts. Unseen buys a deployment
	# phase — the player permutes who stands on which party start hex.
	if Encounter.surprise_check(cb, scouted_ahead):
		_flush_log()
		_deploy_menu()
		return
	_advance()

# --- T39: deployment phase (unseen only) --------------------------------

func _deploy_menu() -> void:
	_mode = "deploy"
	var heroes: Array = cb.team_of("party").filter(func(c): return c.conscious())
	var opts: Array = []
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			opts.append(["Swap %s ↔ %s" % [heroes[i].cname, heroes[j].cname],
				_swap_deploy.bind(heroes[i], heroes[j])])
	_actor.text = "[b]Unseen.[/b]  Trade starting places, then begin — the enemy loses its first round."
	opts.append(["Begin the ambush", func():
		_mode = "idle"
		_advance()])
	_set_buttons(opts)

func _swap_deploy(a, b) -> void:
	var p: Vector2i = a.pos
	a.pos = b.pos
	b.pos = p
	cb.log.append("%s and %s trade places before the fight." % [a.cname, b.cname])
	_board.reset(cb)
	_flush_log()
	_refresh()
	_deploy_menu()

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
			while _walk != null:      # nobody swings while the walkthrough is up
				await get_tree().process_frame
			await get_tree().create_timer(0.5 / _anim).timeout
			if not c.is_down():
				# ponytail: the AI layer reports no per-attack events, so the FX are
				# inferred from who lost HP over its turn. Good enough to follow a
				# turn; give AI.take_turn a callback if it ever needs to be exact.
				var before := {}
				if _fx_on:
					for x in cb.combatants:
						before[x.id] = x.hp
				AI.take_turn(cb, c)
				for x in cb.combatants:
					if before.get(x.id, x.hp) > x.hp:
						_attack_fx(c, x, {"kind": "attack"})
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

# Verb-level menu. Buttons are numbered [1]..[9]; End turn is [0]; most-used
# verbs (_prioritize) claim those low slots over time instead of whatever
# order cb.available() happened to build them in. Everything on it comes from
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
	var opts: Array = []
	var spell_tiers: Dictionary = {}   # spell id -> Array of this verb's entries, one per castable level
	var spell_order: Array = []        # first-seen order, so a spell keeps its natural position in opts
	for v in cb.available(h):
		var label: String = _verb_label(h, v)
		var tip: String = _verb_tooltip(h, v)
		var sid: String = String(v.get("spell", ""))
		var glyph: String = Icons.school_glyph(Icons.spell_school(sid)) if sid != "" \
			else Icons.verb_glyph(String(v["kind"]))
		var freq_key: String = ("spell:" + sid) if sid != "" else String(v.get("id", v["kind"]))
		var meta := {"glyph": glyph, "freq_key": freq_key}
		var entry: Array
		match v.get("targeting", "self"):
			"enemy", "ally":
				entry = [label + "…", func(): _enter_target(h, v), tip, meta]
			"direction":
				entry = [label + " (aim…)", func(): _enter_cone(h, v), tip, meta]
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
			opts[i] = [base[0], func(): _spell_tier_menu(h, tiers),
				"%d levels available — pick one." % tiers.size(), base[3]]

	opts = _prioritize(opts)

	# T29: melee/ranged toggle — only offered to someone carrying both.
	var swap := _attack_swap(h)
	if not swap.is_empty():
		opts.append(["⇄ Wield %s" % swap["name"],
			func(): Adapter.set_main_attack(h, String(swap["id"])); _build_hero_menu(h),
			"Your Attack action switches to %s (%s): %+d to hit, %s %s damage. Free." % [
				swap["name"], swap["range"], int(swap["to_hit"]), swap["notation"],
				swap.get("damage_type", "")]])

	if h.econ["action"] > 0 and not cb.is_over():
		opts.append(_confirm_opt(h, "end", "End turn (action unspent!)", _end_turn))
	else:
		opts.append(["End turn", _end_turn])
	_set_buttons(opts)
	_board.queue_redraw()

# One spell, several slot levels: a small picker instead of a button per tier.
# Each tier's own entry (built above, already wired to _enter_target/_enter_cone/
# cb.perform exactly as it would have been standalone) is reused verbatim.
func _spell_tier_menu(h, tiers: Array) -> void:
	var opts: Array = tiers.duplicate()
	opts.append(["‹ Back", func(): _build_hero_menu(h, true)])
	_set_buttons(opts)
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
	if _busy or cb.is_over() or _mode == "deploy":
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
	_attack_fx(h, c, v)
	# T29: any resolved roll pops the reveal, not just weapon attacks.
	if typeof(res) == TYPE_DICTIONARY and (res.has("hit") or res.has("saved")):
		_busy = true
		_board.show_reveal(c.id, res, _reveal_head(res))
		await get_tree().create_timer(REVEAL_PAUSE / _anim).timeout
		_busy = false
	_after_hero_action(h)

# The popup's primary readout: the outcome and the damage, never the raw d20
# (that stays as the small line under the dice). -> [text, color]
static func _reveal_head(res: Dictionary) -> Array:
	var dmg := int(res.get("damage", 0))
	var tail := "  %d" % dmg if dmg > 0 else ""
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
	_board.queue_redraw()

func board_cancel() -> void:
	if _mode != "idle" and _mode != "deploy" and cb and not cb.is_over() and cb.current().team == "party":
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
# where meta is {"glyph": String, "freq_key": String}, both optional. Buttons are
# a fixed-size grid (BTN_COLUMNS wide, up to BUTTON_ROWS tall before scrolling —
# see _process), clipped rather than wrapped, so 30 verbs stays tidy instead of
# reflowing the panel. Hotkeys: [1]..[9] on the first nine, [0] on the last
# entry (End turn / Cancel), everything past 9 is click-only.
func _set_buttons(opts: Array) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var count := opts.size()
	for i in count:
		var b := Button.new()
		var meta: Dictionary = opts[i][3] if opts[i].size() > 3 else {}
		var hotkey := ""
		if count == 1:
			hotkey = "Esc"
		elif i == count - 1:
			hotkey = "0"
		elif i < 9:
			hotkey = str(i + 1)
		var glyph: String = String(meta.get("glyph", ""))
		var prefix := ("[%s] " % hotkey if hotkey != "" else "") + (glyph + " " if glyph != "" else "")
		b.text = prefix + String(opts[i][0])
		b.clip_text = true
		b.custom_minimum_size = BTN_SIZE * clampf(_zoom, 0.9, 1.4)
		b.pressed.connect(opts[i][1])
		var freq_key := String(meta.get("freq_key", ""))
		if freq_key != "":
			b.pressed.connect(func(): _bump_freq(freq_key))
		if opts[i].size() > 2 and String(opts[i][2]) != "":
			b.tooltip_text = opts[i][2]   # native hover popup — what the verb actually does
		_buttons.add_child(b)
	_apply_ui_scale()

func _bump_freq(key: String) -> void:
	_verb_freq[key] = int(_verb_freq.get(key, 0)) + 1

# Stable sort, most-used first — ties (including every verb tried 0 times, the
# common case at the start of a fight) keep their original relative order, so
# an unused kit doesn't shuffle itself every turn. Entries without a freq_key
# in meta (the weapon-swap toggle, End turn, "‹ Back", ...) sort as count 0
# but that's fine, callers only run this over the verb list before appending
# those pinned entries.
func _prioritize(opts: Array) -> Array:
	var idx := range(opts.size())
	idx.sort_custom(func(a, b):
		var ka := _freq_of(opts[a])
		var kb := _freq_of(opts[b])
		if ka != kb:
			return ka > kb
		return a < b)
	var out: Array = []
	for i in idx:
		out.append(opts[i])
	return out

func _freq_of(opt: Array) -> int:
	if opt.size() <= 3:
		return 0
	var key := String(opt[3].get("freq_key", ""))
	return int(_verb_freq.get(key, 0)) if key != "" else 0

func _refresh() -> void:
	_header.text = "THE SUNKEN SHRINE   ·   Round %d   ·   seed %d" % [cb.round_num, _seed]

	var n: int = cb.order.size()
	var ci: int = cb.order.find(cb.current())
	_build_order_strip()

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious() and _mode == "idle":
		var hint := "  ·  click a blue tile to move" if cur.econ["move_left"] > 0 else ""
		var before = cb.order[(ci - 1 + n) % n]
		var again := "  ·  you act again after %s" % before.cname.split(" ")[0] if before != cur else ""
		var res := _resources(cur)
		_actor.text = "%s  ·  AC %d  ·  %s%s  ·  %s%s%s" % [
			"[b]%s[/b]" % cur.cname, cb.effective_ac(cur), _hp_bb(cur),
			("  ·  " + res) if res != "" else "",
			_econ_bb(cur), hint, again,
		]
	elif _mode == "idle":
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")
	_board.queue_redraw()

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
	var u := clampf(_zoom, 0.9, 1.4)
	for c in cb.order:
		var tile := PanelContainer.new()
		if c == cb.current():
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.78, 0.65, 0.30, 0.20)
			box.set_corner_radius_all(8)
			box.set_border_width_all(2)
			box.border_color = Icons.COL_GOLD
			box.set_content_margin_all(4)
			tile.add_theme_stylebox_override("panel", box)
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
		nm.text = "%s (%d)" % [c.cname.split(" ")[0], c.init_roll]
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
		_order.add_child(tile)

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
			col = "#c8a75a"
		var body := colorize(line, ncols)
		if bold:
			body = "[b]%s[/b]" % body
		_logbox.append_text("[color=%s]%s[/color]\n" % [col, body])
		_logged += 1

func _finish() -> void:
	result = Encounter.resolve_outcome(cb, party)   # writes HP/pools/slots back to the party
	var res: String = cb.outcome()
	if res == "Defeat":
		_board.play_defeat()
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
		_logbox.append_text("[color=#c8a75a]+%d XP, +%d gold.[/color]\n" % [result["xp"], result["gold"]])

const BUTTON_ROWS := 3

func _process(dt: float) -> void:
	if _board:
		_board.tick(dt * _anim)
	if _bscroll:   # grow with the wrapped rows, up to BUTTON_ROWS, then scroll
		var row := BTN_SIZE.y * clampf(_zoom, 0.9, 1.4) + 6.0
		_bscroll.custom_minimum_size.y = minf(_buttons.get_combined_minimum_size().y,
			row * BUTTON_ROWS)

func _log_width() -> float:
	return clampf(size.x * 0.26, 260.0, 380.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _logwrap:
		_logwrap.custom_minimum_size.x = _log_width()

# =====================================================================
#  T32 walkthrough — presentation only. It spotlights a region of this
#  same screen and blocks play until it's dismissed; the fight underneath
#  is an ordinary fight, resolved by the ordinary code.
# =====================================================================

var _walk: Walk = null      # the live overlay, null whenever the tutorial isn't up

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
	_walk = Walk.new()
	_walk.target = _walk_target(String(step["target"]))
	_walk.set_anchors_preset(Control.PRESET_FULL_RECT)
	_walk.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing underneath is clickable
	add_child(_walk)

	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Icons.COL_INK
	box.set_corner_radius_all(10)
	box.set_border_width_all(2)
	box.border_color = Icons.COL_GOLD_EDGE
	box.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var head := Label.new()
	head.text = "%s   (%d/%d)" % [step["title"], i + 1, Tutorial.STEPS.size()]
	head.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	head.add_theme_color_override("font_color", Icons.COL_GOLD)
	col.add_child(head)

	var body := Label.new()
	body.text = String(step["text"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WALK_CARD_W, 0)
	body.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(body)

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

func _walk_end() -> void:
	if _walk != null:
		_walk.queue_free()
		_walk = null

const WALK_CARD_W := 460.0

# Dims everything but the step's target, outlines it, and parks the card clear of it.
class Walk extends Control:
	var target: Control
	var card: Control
	var _last := Rect2()
	const DIM := Color(0.02, 0.03, 0.05, 0.72)

	func _process(_dt: float) -> void:
		if card == null:
			return
		var r := _spot()
		if r != _last:              # the layout settles a frame or two after the step opens
			_last = r
			queue_redraw()
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
		draw_rect(r, Icons.COL_GOLD, false, 3.0)

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
	var _tok := {}        # id -> displayed pixel pos (for slide)
	var _hp := {}         # id -> displayed hp value
	var _floats: Array = []   # {pos: Vector2, text, color, age}
	var _flash := {}     # id -> ttl
	var _hover := Vector2i(999, 999)
	var _reveal = null   # {tid, dice, nat, bonus, total, ac, hit, crit, age}
	var _barks := {}     # id -> {text, age}; drained from cb.barks (T26)
	const BARK_TTL := 2.2
	# T28 attack FX, cosmetic only: {kind, id, from, to, hexes, age, ttl}
	var _fx: Array = []
	const FX_TTL := {"melee": 0.30, "ranged": 0.34, "spell": 0.45}
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
	func _lunge(id: String) -> Vector2:
		for f in _fx:
			if f.kind == "melee" and f.id == id:
				var t: float = clampf(f.age / f.ttl, 0.0, 1.0)
				var d: Vector2 = _pix(f.to) - _pix(f.from)
				if d.length() < 0.01:
					return Vector2.ZERO
				return d.normalized() * (sin(t * PI) * main.hex_px * 0.55)
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
		var span := mx - mn
		# keep the board from being panned entirely off-screen
		var lim := (size + span) * 0.5 - Vector2(90, 60)
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
	const ISO_YAW := 35.0
	const ISO_SQUASH := 0.38
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
	func _fan(apex: Vector2, rim: PackedVector2Array, inner: Color, outer: Color) -> void:
		var n := rim.size()
		var cols := PackedColorArray([inner, outer, outer])
		var uv := PackedVector2Array()
		for i in n:
			draw_primitive(PackedVector2Array([apex, rim[i], rim[(i + 1) % n]]), cols, uv)

	# A soft drop shadow: three ellipses, each wider and fainter than the last.
	# Cheaper than a blur pass and, at these sizes, indistinguishable from one.
	func _soft_shadow(at: Vector2, r: float, strength := 1.0) -> void:
		for i in 3:
			draw_colored_polygon(_disc(at, r * (1.0 + 0.26 * i)),
				Color(0.02, 0.01, 0.04, strength * (0.20 - 0.05 * i)))

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

	# HP bar + condition strip: identical for a sprite and for a vector token, so
	# both paths call this rather than keeping two copies in step by hand.
	func _draw_token_hud(c, p: Vector2, tp: Vector2, s: float, rad: float, fz: float) -> void:
		var hv: float = _hp.get(c.id, float(c.hp))
		var bw := s * 1.2
		var br := Rect2(p.x - bw / 2.0, p.y + rad * ISO_SQUASH + 4.0, bw, 6.0)
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
			_centered(tags, tp + Vector2(0, -rad * 0.8 - 10), int(13 * fz), Color("e6c15a"))

	# The LPC sprite for `c`, if there is one. Returns false when there isn't, and
	# the caller draws its vector token instead.
	#
	# There is no separate animation clock here on purpose: the frame comes out of
	# the same `_fx` melee entry that `_lunge()` already reads, so the swing, the
	# lunge and the damage number stay locked together and nothing new has to be
	# ticked. Idle is frame 0 — in both rigs that is the rest pose the attack
	# leaves from.
	func _draw_sprite(c, p: Vector2, s: float, tint: Color) -> bool:
		var sf: SpriteFrames = LpcArt.frames(LpcArt.loadout_for(c))
		if sf == null:
			return false
		var facing := "right" if c.team == "party" else "left"
		var phase := -1.0
		for f in _fx:
			if f.kind == "melee" and f.id == c.id:
				phase = clampf(f.age / f.ttl, 0.0, 1.0)
				facing = LpcArt.facing_between(_pix(f.from), _pix(f.to))
		var pick: Array = LpcArt.row_for(sf, facing)
		var anim: String = pick[0]
		var count := sf.get_frame_count(anim)
		var idx := 0 if phase < 0.0 else clampi(int(phase * count), 0, count - 1)
		var tex := sf.get_frame_texture(anim, idx)
		# 64px art on a 34px hex: the same fit the T47 preview was judged at, with
		# the frame's ground row (54) landing on the token's own hex point.
		var sc := s / 26.0
		var w := 64.0 * sc
		var at := p - Vector2(32.0 * sc, 54.0 * sc)
		# Down: no lift, greyed and half-faded, same read as the flattened vector
		# token. ponytail: no death/hurt rows exist in the vendored art, so a KO is
		# a tint, not an animation — revisit if a death row is ever vendored.
		var col := tint if c.is_down() else Color.WHITE
		if _flash.has(c.id):
			col = col.lerp(Color.WHITE, clampf(_flash[c.id] / 0.35, 0, 1) * 0.85)
		if c.is_down():
			col.a = 0.55
			at.y += 12.0 * sc
		if pick[1]:
			# Mirror (merc_01 only ships the right-facing row). It has to be a draw
			# transform about the token's own x: a negative-width Rect2 does NOT
			# flip, it gets normalised and lands one full sprite-width to the right.
			draw_set_transform(p, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, at.y - p.y), Vector2(w, 64.0 * sc)),
				false, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, Rect2(at, Vector2(w, 64.0 * sc)), false, col)
		return true

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
			var hx := _unpix(e.position)
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
				main.board_hex_clicked(_unpix(e.position))

	# Stable per-hex noise: same hex, same salt -> same value, every frame. No RNG
	# state, so nothing here can perturb the game's seeded rolls.
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
	func _draw_foliage(d: Dictionary, s: float) -> void:
		var at: Vector2 = d["at"]
		var k: float = float(d["scale"]) * s
		var col: Color = d["col"]
		_soft_shadow(at, k * 0.26, 0.85)
		if String(d["kind"]) == "tree":
			draw_line(at, at - Vector2(0, k * 0.62), Color("3a2c1c"), maxf(1.5, k * 0.09), true)
			for o in [Vector2(0, -0.95), Vector2(-0.24, -0.66), Vector2(0.24, -0.70)]:
				_lobe(at + o * k, k * 0.30, col)
		else:
			for o in [Vector2(-0.20, -0.16), Vector2(0.20, -0.16), Vector2(0, -0.34)]:
				_lobe(at + o * k, k * 0.24, col)

	# One shaded clump of leaves: the same ball shading the tokens use.
	func _lobe(at: Vector2, r: float, col: Color) -> void:
		_fan(at + LIGHT * r * 0.6, _ring(at, r, false, false, 20),
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
				_fan(c + _iso(LIGHT) * s * 0.28, _disc(c, s * 0.45),
					Color("50707f"), Color("32444f"))
				draw_polyline(_disc(c, s * 0.45, true), Color("6f97ad"), 2.0, true)
			_:
				if o.has("hazard") and not o.get("blocks_movement", false):
					var hot := Color("ffcf7a").lerp(Color("ff6a2a"), pulse)
					_fan(c, _disc(c, s * 0.26), hot, Color(hot.r, hot.g, hot.b, 0.0))
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
		if _defeat >= 0.0 and _defeat < 0.6:     # screen shake on the wipe
			var m := (1.0 - _defeat / 0.6) * 10.0
			_origin += Vector2(randf_range(-m, m), randf_range(-m, m))
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
		var decor: Array = []   # foliage, drawn after every tile so it can overhang
		for hx in cb.board["hexes"]:
			var c := _pix(hx)
			var poly := _hex_poly(c, s - 2.0)
			var fill: Color = main.PALETTES.get(cb.board.get("palette", "shrine"), main.COL_HEX)
			var obj: Dictionary = cb.object_at(hx)
			if obj.has("hazard") and not obj.get("blocks_movement", false):
				fill = main.COL_BRAZIER.lerp(Color("d9622e"), pulse)
			elif obj.get("blocks_movement", false):
				fill = main.COL_PROP
			elif cb.is_cover(hx):
				fill = main.COL_COVER
			# Ground, in two layers: a per-hex tinted slab so the field isn't one
			# flat colour, then a lighter patch drifting off-centre. Neighbouring
			# tiles overlap in tone, which is what stops the borders reading as
			# hard-cut diamonds without needing an actual texture.
			var v := _rand(hx, 1)
			var tint := fill.lightened(0.09 * v).darkened(0.07 * (1.0 - v))
			# lit from the top-left and falling off to the rim, so a tile is a
			# shaded surface rather than a solid lozenge
			_fan(c + _iso(LIGHT * s * 0.55), poly, tint.lightened(0.11), tint.darkened(0.13))
			var blob := c + _iso(Vector2(_rand(hx, 2) - 0.5, _rand(hx, 3) - 0.5) * s * 0.6)
			var br2 := s * (0.45 + 0.30 * _rand(hx, 4))
			for i in 3:   # the mottling, feathered out instead of a hard-edged patch
				draw_colored_polygon(_disc(blob, br2 * (0.55 + 0.225 * i)),
					Color(fill.lightened(0.09), 0.11))
			if field.has(hx) and hx != cur.pos:
				draw_colored_polygon(poly, main.COL_MOVE)
			if cone_hexes.has(hx):
				draw_colored_polygon(poly, main.COL_CONE)
			# Only the outline of a terrain CHANGE is drawn at full strength; seams
			# between two plain tiles stay a whisper, so same-terrain runs blend.
			var edge := _hex_poly(c, s - 2.0)
			edge.append(edge[0])
			var seam: bool = _terrain(hx) != ""
			for n in Hex.neighbors(hx):
				if not n in cb.board["hexes"] or _terrain(n) != _terrain(hx):
					seam = true
			draw_polyline(edge, Color(main.COL_HEX_EDGE, 0.9 if seam else 0.22), 1.5, true)
			if obj.is_empty():
				var d := _foliage_at(hx, c, s)
				if not d.is_empty():
					decor.append(d)
			if provoke.has(hx):
				draw_string(ThemeDB.fallback_font, c - Vector2(6, -5), "⚠", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffcf47"))
			if cb.is_cover(hx):
				draw_string(ThemeDB.fallback_font, c + Vector2(-s * 0.5, s * ISO_SQUASH - 3), "cover", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("7fa6a6"))
			if not obj.is_empty():
				_draw_object(obj, c, s, pulse)

		decor.sort_custom(func(a, b): return a["at"].y < b["at"].y)
		for d in decor:
			_draw_foliage(d, s)

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
			_soft_shadow(p, rad * 0.80, 1.0 if c.is_down() else 1.15)
			if c == cur:
				# A real blink: the ring breathes in alpha, width AND radius, with a
				# faint outer halo — the old width-only wobble read as noise.
				var bl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 170.0)
				base = base.lerp(Color("ffe27a"), 0.18 * bl)
				draw_polyline(_disc(p, rad + 4.0 + bl * 3.0, true),
					Color(1.0, 0.886, 0.478, 0.25 + 0.75 * bl), 2.5 + bl * 3.0, true)
				draw_polyline(_disc(p, rad + 12.0 + bl * 6.0, true),
					Color(1.0, 0.886, 0.478, 0.30 * bl), 2.0, true)
			# Tier 1: a composited LPC sprite, if this combatant has one. It
			# replaces the drawn disc and its glyph only — shadow, active ring,
			# flash, HP bar, condition tags and the _tok/_lunge positioning above
			# are shared with the vector token below, which still draws everyone
			# the art doesn't cover.
			if _draw_sprite(c, p, s, base):
				_draw_token_hud(c, p, tp, s, rad, fz)
				continue
			# The token is shaded like a ball: hotspot toward the light, falling
			# off to a darker rim, with a bright sliver of rim light on the lit
			# side and a dark contact line on the far one.
			var trad := rad * 0.8
			var flat: bool = c.is_down()
			if not flat:
				draw_line(p, tp, base.darkened(0.55), 3.0, true)   # the "post" it stands on
			_fan(tp + (_iso(LIGHT) if flat else LIGHT) * trad * 0.62,
				_ring(tp, trad, flat, false, 28), base.lightened(0.26), base.darkened(0.20))
			draw_polyline(_ring(tp, trad, flat, true, 28), base.darkened(0.45), 1.5, true)
			if not flat:
				var lit := LIGHT.angle()
				draw_arc(tp, trad * 0.93, lit - 0.85, lit + 0.85, 20,
					Color(1, 1, 1, 0.26), 2.0, true)
			# The token's mark: class glyph for heroes, creature-type glyph for foes.
			_centered(_glyph(c), tp, int(24 * fz), Color("101216"))
			_draw_token_hud(c, p, tp, s, rad, fz)

		_draw_fx(s)   # projectiles / spell flashes sit over the tokens

		# the odds chip itself draws last of the per-target overlay — after every
		# token's own circle/badge/HP bar/condition tags, which used to be drawn
		# on top of it and could cover the readout depending on hex spacing.
		if hero_turn and main._mode == "target":
			for c in cb.combatants:
				if not main._valid_target(cur, c):
					continue
				var tp := _pix(c.pos)
				var hot: bool = c.pos == _hover
				var txt: String = main.target_readout(cur, c)
				var fs := int((20 if hot else 15) * fz)
				var w := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var chip := tp + Vector2(-w / 2.0, -s * 1.35)
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

		# --- roll reveal: the OUTCOME first, dice detail underneath ------
		if _reveal != null and _tok.has(_reveal.tid):
			var a := clampf(1.0 - (_reveal.age - 0.9) / 0.5, 0.0, 1.0)   # hold, then fade
			var anchor: Vector2 = _tok[_reveal.tid] + Vector2(0, -s * 1.7)
			# the headline punches in over the first 0.12s, then settles
			var pop := 1.0 + 0.35 * clampf(1.0 - _reveal.age / 0.12, 0.0, 1.0)
			var hcol: Color = _reveal.hcol
			hcol.a = a
			_centered(String(_reveal.head), anchor + Vector2(0, -14 * fz),
				int(26 * fz * pop), hcol)
			var dice: Array = _reveal.dice
			var box := 22.0 * fz
			var total_w: float = maxf(0.0, dice.size() * (box + 5.0) - 5.0)
			var x := anchor.x - total_w / 2.0
			anchor.y += 10.0 * fz
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
				draw_string(ThemeDB.fallback_font, Vector2(x + box * 0.26, anchor.y + box * 0.72),
					str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * fz), dc)
				if not counts:
					var sl := Color("d15750"); sl.a = a
					draw_line(Vector2(x + 3, anchor.y + box - 3), Vector2(x + box - 3, anchor.y + 3), sl, 2.0)
				x += box + 5.0
			if not dice.is_empty():
				var lcol := Color("9aa0ae"); lcol.a = a
				_centered("d20 %+d = %d  vs AC %d" % [_reveal.bonus, _reveal.total, _reveal.ac],
					anchor + Vector2(0, box + 14 * fz), int(11 * fz), lcol)

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

	# draw_string with the string's own width taken out, so `at` is its centre.
	func _centered(text: String, at: Vector2, fs: int, col: Color) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, at - Vector2(w * 0.5, -fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# A hero's class mark, a monster's creature-type mark.
	func _glyph(c) -> String:
		return Icons.combatant_glyph(c)
