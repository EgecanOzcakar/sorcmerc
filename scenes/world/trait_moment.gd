# #176 — the moment a hero becomes someone slightly different: a personality
# trait gained in triumph, a scar or a resilience decided on a save, a wound, a
# fear overcome. The owner's brief: "a huge popup for these occasions — make it
# obvious that something important is happening to their character". So this is
# not a card over the map like the road's (event_card.gd). It takes the whole
# screen, it is coloured by what kind of moment it is, the hero's whole figure
# stands on it, the save that decided it is rolled in front of the player, and
# the trait's name lands last, large, with a sting. The spec is
# docs/superpowers/specs/2026-09-23-traits-design.md §6 and §8.
#
#   const TraitMoment = preload("res://scenes/world/trait_moment.gd")
#   _moment = TraitMoment.new()
#   add_child(_moment)
#   _moment.finished.connect(_on_moments_done)   # () -> resume clock, free me
#   _moment.show_moments([m, m2])                # one per hero, in order
#
# One moment dict, every key optional (the card renders a fallback rather than
# an empty screen, event_card.gd's rule):
#   {"cname": "Vera Kord", "figure": <model path, Figures3D.model_path_for>,
#    "kind": "triumph" | "resilience" | "scar" | "wound" | "cure",
#    "event": "Downed by the fire giant",
#    "save": {"ability": "wis", "dc": 18, "nat": 16, "bonus": 5, "mode": "adv"|"dis"|""},
#    "trait": {"name": "Fire-tempered", "text": "...", "effects": ["...", ...], "cure": "..."},
#    "line": "She comes back from the fire tempered by it."}
# The save is absent for a triumph, which is rolled on chance and not on a save
# (§6: triumph traits are the likelier kind). `nat` and `bonus` are the roll
# core/traits.gd already made; nothing here rolls anything that matters.
#
# What it does NOT own, the same split as the other cards: the outcome (the
# trait is already on the sheet when this opens — this is the ceremony), the
# clock (the caller pauses before and resumes on `finished`), and freeing itself.
#
# The show is about 2.5 seconds at normal speed. Any key or click during it jumps
# to the end rather than dismissing, so nobody skips a scar by accident; the
# next press moves on. Settings.anim() scales it and SORCMERC_FAST skips it,
# as spoils.gd does.
extends Control

const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Portraits = preload("res://scenes/portraits.gd")
const Sound = preload("res://core/audio.gd")

# Emitted once, after the last moment in the queue is acknowledged.
signal finished()

const SCRIM := 0.92            # darker than a road card: the map is not the point now
const GLOW_ALPHA := 0.45       # the kind's colour, bleeding up from the bottom of the screen
const MARGIN := 28.0
const FIGURE_PX := Vector2i(300, 520)   # the whole hero, bigger than anywhere else they appear
const COL_W := 620.0           # the words column; past this a paragraph stops scanning
const NAME_SIZE := 84          # the trait's name: the largest text in the game on purpose
const CAPTION_SIZE := 24
const HERO_SIZE := 36
const D20_SIZE := 60
const DISMISS_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
const DISMISS_TEXT := "So it is   (Enter)"

# What kind of moment, before a word is read: the colour of the glow, the rule,
# the caption and the name. A scar is the foe's red; a triumph the gilt every
# reward in the game wears; resilience the verdigris of a thing that held.
const KIND_COL := {
	"triumph": Icons.COL_GOLD, "resilience": Icons.COL_ACCENT,
	"scar": Icons.COL_FOE, "wound": Color("c9803f"), "cure": Icons.COL_PARTY,
}
const KIND_CAPTION := {
	"triumph": "A   T R I U M P H", "resilience": "T E M P E R E D",
	"scar": "S C A R R E D", "wound": "W O U N D E D", "cure": "M E N D E D",
}
# The caption over a trait name that is being taken away rather than given.
const KIND_VERB := {"triumph": "is now", "resilience": "is now", "scar": "is now",
	"wound": "is", "cure": "is no longer"}
const KIND_STING := {"triumph": "music_deed", "resilience": "music_deed", "cure": "music_relief",
	"scar": "save_failed", "wound": "down"}
const ABILITY_NAME := {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}

# Beats, in seconds at anim() == 1. The trait's name is the last thing to land
# and the only one with a sound, so the player's eye is on it when it does.
const T_SCRIM := 0.30
const T_FIGURE := 0.45
const T_ROLL := 0.90           # the d20 ticks for this long before it stops
const T_STAMP := 0.35
const T_REST := 0.30

var _queue: Array = []
var _i := 0
var _playing := false          # true while the show runs; a press ends it instead of moving on
var _tween: Tween = null
var _emitted := false

# The nodes the show animates, rebuilt per moment.
var _scrim: ColorRect
var _glow: ColorRect
var _figure: Control
var _heading: Control
var _roll_box: Control
var _d20: Label
var _verdict: Label
var _stamp: Control
var _name_label: Label
var _details: Control
var _btn: Button
var _count: Label


func _ready() -> void:
	# ...AND offsets: anchors alone keep a zero-size rect under a Window, and a
	# zero-size moment centres nothing and draws no scrim (the first render of
	# this sat in the top-left corner of a dark screen).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # modal: nothing reaches the map under it
	theme = Icons.dark_theme()


# The whole public surface, besides `finished`.
func show_moments(moments: Array) -> void:
	_queue = moments.duplicate()
	_i = 0
	_emitted = false
	if _queue.is_empty():
		_queue = [{}]   # a blank screen reads as a crash; the fallback text is better
	_show(_queue[0])


# How many moments are left to see, this one included. For the caller and the tests.
func remaining() -> int:
	return maxi(0, _queue.size() - _i)


# Where the show stands, for tests and robots: the texts as a player would read them.
func texts() -> Dictionary:
	return {
		"caption": _find_text(_heading, "caption"), "hero": _find_text(_heading, "hero"),
		"event": _find_text(_heading, "event"), "d20": _d20.text if _d20 != null else "",
		"verdict": _verdict.text if _verdict != null else "", "name": _name_label.text if _name_label != null else "",
		"verb": _find_text(_stamp, "verb"), "count": _count.text if _count != null else "",
		"button": _btn.text if _btn != null else "", "playing": _playing,
	}


# --- building one moment ------------------------------------------------------

func _show(m: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	var kind := String(m.get("kind", "triumph"))
	if not KIND_COL.has(kind):
		kind = "triumph"
	var col: Color = KIND_COL[kind]

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, SCRIM)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_scrim.gui_input.connect(_on_click)

	# The kind's colour rising from the floor: a gradient the height of the
	# screen, transparent at the top. The first thing the eye gets.
	_glow = ColorRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = _glow_material(col)
	add_child(_glow)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	_figure = _figure_for(m, col)
	row.add_child(_figure)

	var words := VBoxContainer.new()
	words.custom_minimum_size = Vector2(COL_W, 0)
	words.add_theme_constant_override("separation", 14)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)

	_heading = _heading_for(m, kind, col)
	words.add_child(_heading)
	_roll_box = _roll_for(m, col)
	words.add_child(_roll_box)
	_stamp = _stamp_for(m, kind, col)
	words.add_child(_stamp)
	_details = _details_for(m, col)
	words.add_child(_details)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	words.add_child(foot)
	_btn = Button.new()
	_btn.text = DISMISS_TEXT
	_btn.theme_type_variation = "Primary"
	_btn.custom_minimum_size = Vector2(200, 38)
	Icons.clicks(_btn)
	_btn.pressed.connect(_advance)
	foot.add_child(_btn)
	_count = Label.new()
	_count.theme_type_variation = "Dim"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.text = "%d of %d" % [_i + 1, _queue.size()] if _queue.size() > 1 else ""
	foot.add_child(_count)

	_play(m, kind)


func _figure_for(m: Dictionary, col: Color) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Icons.box(Icons.COL_INK, col.darkened(0.2), 2, 0, 0))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.custom_minimum_size = Vector2(FIGURE_PX)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = Portraits.figure(String(m.get("figure", "")), FIGURE_PX)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(FIGURE_PX)
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(r)
	else:
		# No model for this class, or headless: the hero's initial, big, in the
		# kind's colour. The frame keeps its size so the layout does not jump.
		var l := Label.new()
		l.text = String(m.get("cname", "?")).left(1).to_upper()
		l.add_theme_font_override("font", Icons.serif(700))
		l.add_theme_font_size_override("font_size", 140)
		l.add_theme_color_override("font_color", col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(l)
	return frame


func _heading_for(m: Dictionary, kind: String, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _label(KIND_CAPTION[kind], Icons.sans(700), CAPTION_SIZE, col)
	cap.name = "caption"
	box.add_child(cap)
	box.add_child(_rule(col))
	var hero := _label(String(m.get("cname", "One of the company")), Icons.serif(700), HERO_SIZE, Icons.COL_HEAD)
	hero.name = "hero"
	box.add_child(hero)
	var ev := _label(String(m.get("event", "Something happened that will not unhappen.")),
		Icons.serif(400), 20, Icons.COL_BODY)
	ev.name = "event"
	ev.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.custom_minimum_size = Vector2(COL_W, 0)
	box.add_child(ev)
	return box


# The save, rolled in front of the player: a d20 face that ticks and stops on
# the number core/traits.gd rolled, and the verdict beside it. No save (a
# triumph) is an empty box that takes no room.
func _roll_for(m: Dictionary, col: Color) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d20 = null
	_verdict = null
	var sv = m.get("save")
	if not (sv is Dictionary) or sv.is_empty():
		box.visible = false
		return box
	var die := PanelContainer.new()
	die.add_theme_stylebox_override("panel", Icons.box(Icons.COL_INK, col, 4, 14, 2))
	die.custom_minimum_size = Vector2(96, 84)
	_d20 = _label("", Icons.serif(700), D20_SIZE, Icons.COL_HEAD)
	_d20.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d20.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	die.add_child(_d20)
	box.add_child(die)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_label("%s save  ·  DC %d%s" % [ABILITY_NAME.get(String(sv.get("ability", "wis")), "WIS"),
		int(sv.get("dc", 10)), _mode_note(String(sv.get("mode", ""))) ], Icons.sans(500), 18, Icons.COL_BODY))
	_verdict = _label("", Icons.sans(700), 22, Icons.COL_HEAD)
	right.add_child(_verdict)
	box.add_child(right)
	return box


func _stamp_for(m: Dictionary, kind: String, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Dictionary = m.get("trait", {}) if m.get("trait") is Dictionary else {}
	var verb := _label(KIND_VERB[kind], Icons.serif(400), 22, Icons.COL_MUTED)
	verb.name = "verb"
	box.add_child(verb)
	_name_label = _label(String(t.get("name", "Changed")), Icons.serif(700), NAME_SIZE, col)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.custom_minimum_size = Vector2(COL_W, 0)
	# A dark outline so the name reads over the glow at any colour.
	_name_label.add_theme_constant_override("outline_size", 10)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	box.add_child(_name_label)
	return box


func _details_for(m: Dictionary, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Dictionary = m.get("trait", {}) if m.get("trait") is Dictionary else {}
	if String(t.get("text", "")) != "":
		box.add_child(_para(String(t["text"]), Icons.serif(400), 19, Icons.COL_TEXT))
	for e in t.get("effects", []):
		box.add_child(_para("◆  " + String(e), Icons.sans(500), 18, col.lightened(0.25)))
	if String(t.get("cure", "")) != "":
		box.add_child(_para("What would mend it: " + String(t["cure"]), Icons.sans(400), 16, Icons.COL_MUTED))
	if String(m.get("line", "")) != "":
		box.add_child(_rule(col))
		box.add_child(_para(String(m["line"]), Icons.serif(400), 19, Icons.COL_BODY))
	return box


# --- the show -------------------------------------------------------------------

func _play(m: Dictionary, kind: String) -> void:
	var sv = m.get("save")
	var has_save: bool = sv is Dictionary and not sv.is_empty()
	var total := 0
	var nat := 0
	if has_save:
		nat = int(sv.get("nat", 10))
		total = nat + int(sv.get("bonus", 0))
	var speed := Settings.anim()
	if speed >= Settings.FAST:
		_end_state(m, has_save, nat, total)
		_sting(kind)
		return
	_playing = true
	_btn.disabled = true
	for n in [_figure, _heading, _roll_box, _stamp, _details, _btn]:
		n.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_scrim.modulate.a = 0.0
	var k := 1.0 / maxf(speed, 0.01)
	_tween = create_tween()
	_tween.tween_property(_scrim, "modulate:a", 1.0, T_SCRIM * k)
	_tween.parallel().tween_property(_glow, "modulate:a", 1.0, T_SCRIM * 2.0 * k)
	_tween.tween_property(_figure, "modulate:a", 1.0, T_FIGURE * k)
	_tween.parallel().tween_property(_heading, "modulate:a", 1.0, T_FIGURE * k)
	if has_save:
		_tween.tween_property(_roll_box, "modulate:a", 1.0, 0.15 * k)
		# The die ticks through faces and stops on the real one. Cosmetic noise:
		# the faces in between come off the tick's own index, not an RNG, so the
		# show is the same every time it is watched.
		_tween.tween_method(func(f: float): _d20.text = str(1 + (int(f * 37.0) * 7 + nat) % 20),
			0.0, 1.0, T_ROLL * k)
		_tween.tween_callback(func(): _land_roll(sv, nat, total))
	_tween.tween_interval(0.15 * k)
	_tween.tween_callback(func(): _pop_stamp(kind, k))
	_tween.tween_property(_stamp, "modulate:a", 1.0, T_STAMP * k)
	_tween.tween_property(_details, "modulate:a", 1.0, T_REST * k)
	_tween.parallel().tween_property(_btn, "modulate:a", 1.0, T_REST * k)
	_tween.tween_callback(_done_playing)


func _pop_stamp(kind: String, k: float) -> void:
	_sting(kind)
	# The name lands: from larger than life to its size, like a seal pressed.
	_name_label.pivot_offset = _name_label.size * 0.5
	_name_label.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(_name_label, "scale", Vector2.ONE, T_STAMP * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _land_roll(sv: Dictionary, nat: int, total: int) -> void:
	_d20.text = str(nat)
	var dc := int(sv.get("dc", 10))
	var made: bool = nat == 20 or (nat != 1 and total >= dc)
	var by := absi(total - dc)
	var how: String
	if nat == 20:
		how = "A natural 20."
	elif nat == 1:
		how = "A natural 1."
	elif made:
		how = "%d — made it%s." % [total, " by %d" % by if by > 0 else ""]
	else:
		how = "%d — failed by %d." % [total, by]
	_verdict.text = how
	_verdict.add_theme_color_override("font_color", Icons.COL_PARTY if made else Icons.COL_FOE)
	_d20.add_theme_color_override("font_color", Icons.COL_PARTY if made else Icons.COL_FOE)


func _end_state(m: Dictionary, has_save: bool, nat: int, total: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for n in [_scrim, _glow, _figure, _heading, _roll_box, _stamp, _details, _btn]:
		n.modulate.a = 1.0
	_name_label.scale = Vector2.ONE
	if has_save:
		_land_roll(m["save"], nat, total)
	_done_playing()


func _done_playing() -> void:
	_playing = false
	_btn.disabled = false
	if is_inside_tree():
		_btn.grab_focus()


func _sting(kind: String) -> void:
	var s: String = KIND_STING.get(kind, "")
	if s == "":
		return
	if s.begins_with("music_"):
		Sound.play_sting(s)
	else:
		Sound.play_sfx(s)


# --- moving on ----------------------------------------------------------------

func _skip_or_advance() -> void:
	if _playing:
		var m: Dictionary = _queue[_i]
		var sv = m.get("save")
		var has_save: bool = sv is Dictionary and not sv.is_empty()
		var nat := int(sv.get("nat", 10)) if has_save else 0
		_end_state(m, has_save, nat, nat + (int(sv.get("bonus", 0)) if has_save else 0))
		return
	_advance()


func _advance() -> void:
	if _playing or _emitted:
		return
	_i += 1
	if _i < _queue.size():
		_show(_queue[_i])
		return
	_emitted = true
	finished.emit()


func _on_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_skip_or_advance()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode in DISMISS_KEYS:
		accept_event()
		_skip_or_advance()


# --- small builders -------------------------------------------------------------

func _label(text: String, font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _para(text: String, font: Font, px: int, color: Color) -> Label:
	var l := _label(text, font, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COL_W, 0)
	return l


func _rule(col: Color) -> Control:
	var r := ColorRect.new()
	r.color = Color(col, 0.55)
	r.custom_minimum_size = Vector2(COL_W, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _mode_note(mode: String) -> String:
	match mode:
		"adv": return "  ·  with advantage"
		"dis": return "  ·  at disadvantage"
	return ""


func _find_text(root: Node, node_name: String) -> String:
	if root == null:
		return ""
	var n := root.find_child(node_name, true, false)
	return n.text if n is Label else ""


# A vertical gradient in the kind's colour, strongest at the floor.
func _glow_material(col: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 tint : source_color;
uniform float strength;
void fragment() {
	float rise = smoothstep(0.15, 1.0, UV.y);
	float centre = 1.0 - smoothstep(0.0, 0.75, abs(UV.x - 0.5));
	COLOR = vec4(tint.rgb, strength * rise * (0.55 + 0.45 * centre));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("strength", GLOW_ALPHA)
	return mat
