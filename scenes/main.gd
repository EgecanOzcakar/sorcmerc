# Minimal playable UI for The Sunken Shrine. Placeholder art (coloured panels);
# all rules live in core/. Built programmatically so it needs no editor work to run.
extends Control

const RNG = preload("res://core/rng.gd")
const Combat = preload("res://core/combat.gd")
const AI = preload("res://core/ai.gd")
const Encounter = preload("res://core/encounter.gd")

var cb
var _seed: int = 0
var _busy = false
var _disengage = false

@onready var _header = Label.new()
@onready var _order = Label.new()
@onready var _zones = HBoxContainer.new()
@onready var _actor = Label.new()
@onready var _buttons = HFlowContainer.new()
@onready var _logbox = RichTextLabel.new()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_header.add_theme_font_size_override("font_size", 22)
	root.add_child(_header)
	_order.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_order)

	_zones.add_theme_constant_override("separation", 6)
	_zones.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_zones)

	_actor.add_theme_font_size_override("font_size", 16)
	root.add_child(_actor)
	root.add_child(_buttons)

	_logbox.bbcode_enabled = true
	_logbox.scroll_following = true
	_logbox.custom_minimum_size = Vector2(0, 200)
	_logbox.add_theme_color_override("default_color", Color(0.85, 0.85, 0.8))
	root.add_child(_logbox)

	_new_game()

func _new_game() -> void:
	_seed = int(Time.get_unix_time_from_system()) & 0xFFFFFF
	cb = Combat.new(RNG.new(_seed), Encounter.all())
	_logbox.text = ""
	_flush_log()
	_refresh()
	_advance()

# --- turn driver ----------------------------------------------------------

func _advance() -> void:
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
			await get_tree().create_timer(0.5).timeout
			if not c.is_down():
				AI.take_turn(cb, c)
			_flush_log()
			_refresh()
			_busy = false
			cb.end_turn()
			continue
		# conscious hero: hand control to the player
		_disengage = false
		_build_hero_menu(c)
		return
	_finish()

func _end_turn() -> void:
	if _busy:
		return
	cb.end_turn()
	_advance()

# --- hero menu ----------------------------------------------------------

func _build_hero_menu(h) -> void:
	var opts: Array = []
	var foes: Array = cb.enemies_of(h)

	if not cb.action_used:
		for f in foes:
			var pct = int(round(cb.hit_chance(h, f) * 100.0))
			var reach_ok = (h.ranged or f.zone == h.zone)
			if reach_ok:
				opts.append(["Attack %s  (%d%%)" % [f.cname, pct], func(): _hero_attack(h, f)])
		if h.athletics > 0:
			for f in foes:
				if f.zone == h.zone:
					opts.append(["Shove %s → prone" % f.cname, func(): _hero_shove(h, f, "prone")])
					if h.zone == 1:
						opts.append(["Shove %s → brazier" % f.cname, func(): _hero_shove(h, f, "brazier")])
		if "burning_hands" in h.spells and h.slots1 + h.slots2 > 0:
			opts.append(["Burning Hands (your zone)", func(): _hero_cast(h, "bh")])
		if "sacred_flame" in h.spells:
			for f in foes:
				opts.append(["Sacred Flame %s" % f.cname, func(): _hero_cast_target(h, f, "sf")])
		opts.append(["Dodge", func(): _hero_simple(h, "dodge")])
		opts.append(["Dash (move 2)", func(): _hero_simple(h, "dash")])

	if not cb.bonus_used:
		if h.second_wind != "" and not h.used_second_wind:
			opts.append(["Second Wind (heal)", func(): _hero_bonus(h, "sw")])
		if "healing_word" in h.spells and h.slots1 + h.slots2 > 0:
			for a in cb.combatants:
				if a.team == "party" and a != h and not a.is_dead():
					opts.append(["Healing Word → %s" % a.cname, func(): _hero_heal(h, a)])

	if not cb.move_used:
		if h.zone > 0:
			opts.append(["← %s" % Combat.ZONE_NAMES[h.zone - 1], func(): _hero_move(h, h.zone - 1)])
		if h.zone < 2:
			opts.append(["%s →" % Combat.ZONE_NAMES[h.zone + 1], func(): _hero_move(h, h.zone + 1)])
		opts.append(["Disengage: %s" % ("ON" if _disengage else "off"), func(): _toggle_disengage(h)])

	opts.append(["— End turn —", _end_turn])
	_set_buttons(opts)

func _toggle_disengage(h) -> void:
	_disengage = not _disengage
	_build_hero_menu(h)

func _hero_attack(h, f) -> void:
	cb.resolve_attack(h, f)
	_after_hero_action(h)

func _hero_shove(h, f, mode) -> void:
	cb.act_shove(h, f, mode)
	_after_hero_action(h)

func _hero_cast(h, _which) -> void:
	cb.cast_burning_hands(h)
	_after_hero_action(h)

func _hero_cast_target(h, f, _which) -> void:
	cb.cast_sacred_flame(h, f)
	_after_hero_action(h)

func _hero_simple(h, kind) -> void:
	if kind == "dodge":
		cb.act_dodge(h)
	elif kind == "dash":
		cb.move_used = true
		cb.action_used = true
		var foes = cb.enemies_of(h)
		if not foes.is_empty():
			var step = signi(foes[0].zone - h.zone)
			cb.move_to(h, clampi(h.zone + step * 2, 0, 2), _disengage)
	_after_hero_action(h)

func _hero_bonus(h, kind) -> void:
	if kind == "sw":
		cb.act_second_wind(h)
	_after_hero_action(h)

func _hero_heal(h, a) -> void:
	cb.cast_healing_word(h, a)
	_after_hero_action(h)

func _hero_move(h, z) -> void:
	cb.move_used = true
	cb.move_to(h, z, _disengage)
	_after_hero_action(h)

func _after_hero_action(h) -> void:
	_flush_log()
	_refresh()
	if cb.is_over():
		_finish()
		return
	if cb.action_used and cb.move_used and cb.bonus_used:
		_end_turn()
	else:
		_build_hero_menu(h)

# --- rendering --------------------------------------------------------

func _set_buttons(opts: Array) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	for o in opts:
		var b = Button.new()
		b.text = o[0]
		b.pressed.connect(o[1])
		_buttons.add_child(b)

func _refresh() -> void:
	_header.text = "THE SUNKEN SHRINE   ·   Round %d   ·   seed %d" % [cb.round_num, _seed]
	var names: Array = []
	for c in cb.order:
		var mark = "▶" if c == cb.current() else ""
		var s = "%s%s(%d)" % [mark, c.cname.split(" ")[0], c.init_roll]
		if c.is_dead():
			s = "[s]%s[/s]" % s
		names.append(s)
	_order.text = "Order:  " + "   ".join(names)

	for c in _zones.get_children():
		c.queue_free()
	for z in 3:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col = VBoxContainer.new()
		panel.add_child(col)
		var title = Label.new()
		title.text = Combat.ZONE_NAMES[z] + ("  🔥" if z == 1 else ("  (cover)" if z == 2 else ""))
		title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
		col.add_child(title)
		for c in cb.combatants:
			if c.zone != z or c.is_dead():
				continue
			col.add_child(_row(c))
		_zones.add_child(panel)

	var cur = cb.current()
	if cur and cur.team == "party" and cur.conscious():
		_actor.text = "%s  ·  AC %d  ·  HP %d/%d  ·  slots %d/%d  ·  %s%s%s" % [
			cur.cname, cb.effective_ac(cur), cur.hp, cur.max_hp, cur.slots1, cur.slots2,
			"" if cb.action_used else "[action] ",
			"" if cb.bonus_used else "[bonus] ",
			"" if cb.move_used else "[move]",
		]
	else:
		_actor.text = "%s is acting…" % (cur.cname if cur else "?")

func _row(c) -> Control:
	var box = HBoxContainer.new()
	var nm = Label.new()
	var tag = ""
	if c.has("prone"): tag += " ↓"
	if c.has("dodging"): tag += " (dodge)"
	if c.has("hidden"): tag += " (hidden)"
	if c.is_down(): tag += " ✗down[%d/%d]" % [c.death_s, c.death_f]
	nm.text = "%s%s" % [c.cname, tag]
	nm.custom_minimum_size = Vector2(190, 0)
	nm.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if c.team == "party" else Color(1, 0.6, 0.55))
	box.add_child(nm)
	var bar = ProgressBar.new()
	bar.max_value = c.max_hp
	bar.value = c.hp
	bar.custom_minimum_size = Vector2(120, 16)
	bar.show_percentage = false
	box.add_child(bar)
	var hp = Label.new()
	hp.text = " %d/%d" % [c.hp, c.max_hp]
	box.add_child(hp)
	return box

var _logged = 0

func _flush_log() -> void:
	while _logged < cb.log.size():
		var line: String = cb.log[_logged]
		var col = "#d8d8d0"
		if "CRIT" in line: col = "#ff5a4a"
		elif "is dead" in line or "has died" in line: col = "#ff8866"
		elif "revives" in line or "nat 20" in line: col = "#7dff9d"
		elif "misses" in line: col = "#8a8a84"
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
