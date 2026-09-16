# The achievement toast: a card that slides in from the top-right corner the
# moment something is earned, holds long enough to read, and goes away again.
#
# Registered as the `AchievementToasts` autoload, for the same reason core/audio.gd
# is one: core/*.gd is pure logic the headless suite exercises and cannot own
# scene-tree nodes, so the model (core/achievements.gd) only ever appends the
# thing it just unlocked to a small queue. This drains that queue every frame, so
# a fight, a shop, a level-up and the world map all pop toasts without any of
# them knowing this file exists.
#
# A script run as the main loop (`godot -s tests/test_*.gd`) never instantiates
# autoloads, so headless earns achievements with nobody drawing them — which is
# exactly right, and why the queue in core/achievements.gd has a cap.
extends CanvasLayer

const Ach = preload("res://core/achievements.gd")
const Icons = preload("res://core/ui_icons.gd")
const Settings = preload("res://core/settings.gd")
const Sound = preload("res://core/audio.gd")

const WIDTH := 330.0            # the card, in pixels
const MARGIN := Vector2(18, 18) # from the top-right corner of the viewport
const GAP := 8.0                # between stacked cards
const MAX_VISIBLE := 3          # more than this at once is a wall, not a notice
const SLIDE_IN := 0.35
const HOLD := 4.5
const SLIDE_OUT := 0.45
# Above every screen in the game. Every other CanvasLayer in the project (the
# combat screen's HUD overlay is the only one) leaves `layer` at its default 1,
# so this is deliberate headroom rather than a fight over one number.
const LAYER := 128
# The queue is drained every frame; the file underneath it is not. Same
# coalescing core/achievements.gd does, one level up: a run that earns nothing
# never writes at all.
const FLUSH_EVERY := 5.0

var _waiting: Array = []    # earned, not yet shown — defs from core/achievements.gd
var _live: Array = []       # on screen right now, topmost first
var _since_flush := 0.0

func _ready() -> void:
	layer = LAYER
	# Nothing in the game pauses the tree today, but an overlay that starts to
	# would otherwise freeze the card halfway in. ALWAYS costs nothing and
	# means this layer never has to be revisited if one does.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The one place the game looks at the wall clock. Here rather than in
	# core/achievements.gd's load, so a headless test never earns one by accident.
	Ach.check_calendar()
	if DisplayServer.get_name() == "headless":
		set_process(false)

func _process(delta: float) -> void:
	for def in Ach.take_toasts():
		_waiting.append(def)
	while _live.size() < MAX_VISIBLE and not _waiting.is_empty():
		_show(_waiting.pop_front())
	_layout()
	_since_flush += delta
	if _since_flush >= FLUSH_EVERY:
		_since_flush = 0.0
		Ach.flush()

# Godot does not guarantee a _notification on the way out of a headless run, but
# a windowed one always gets this — the last few kills of a session are worth a
# write.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		Ach.flush()

# --- one card --------------------------------------------------------------

func _show(def: Dictionary) -> void:
	if not _popups_on():
		return
	var card := _card(def)
	add_child(card)
	_live.append(card)
	card.modulate.a = 0.0
	card.set_meta("slide", 1.0)
	Sound.play_sfx("quest_complete")

	var tw := create_tween()
	tw.tween_method(_slide.bind(card), 1.0, 0.0, SLIDE_IN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, SLIDE_IN)
	tw.tween_interval(HOLD)
	tw.tween_method(_slide.bind(card), 0.0, 1.0, SLIDE_OUT) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "modulate:a", 0.0, SLIDE_OUT)
	tw.tween_callback(_drop.bind(card))

# The player can turn these off (core/settings.gd). The achievement is still
# earned and still shows up in the viewer — only the card is suppressed.
func _popups_on() -> bool:
	return Settings.current().achievement_popups

func _slide(v: float, card: Control) -> void:
	if is_instance_valid(card):
		card.set_meta("slide", v)

func _drop(card: Control) -> void:
	_live.erase(card)
	if is_instance_valid(card):
		card.queue_free()

# Positions every live card against the top-right corner. Done each frame rather
# than once, because a card's height is only known after the autowrapped
# description has been laid out, and because the window can be resized under it.
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var y := MARGIN.y
	for card in _live:
		if not is_instance_valid(card):
			continue
		card.size = Vector2(WIDTH, card.get_combined_minimum_size().y)
		var slide := float(card.get_meta("slide", 0.0))
		card.position = Vector2(view.x - MARGIN.x - WIDTH + slide * (WIDTH + MARGIN.x), y)
		y += card.size.y + GAP

func _card(def: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme = Icons.dark_theme()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = WIDTH
	# Gilt on the panel and a thicker bar down the left edge — the same shorthand
	# for "earned" the viewer's ledger rows use.
	var box := Icons.box(Icons.COL_PANEL, Icons.COL_GOLD_EDGE, 3, 14, 10)
	box.border_color = Icons.COL_GOLD
	box.border_width_left = 4
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 6
	card.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	var badge := Icons.scene_art("achievement-" + String(def.get("id", "")), null)
	if badge != null:   # the earned one's picture leads the card
		var pic := TextureRect.new()
		pic.texture = badge
		pic.custom_minimum_size = Vector2(44, 44)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(pic)
	var star := Label.new()
	star.text = "★"
	star.add_theme_color_override("font_color", Icons.COL_GOLD)
	head.add_child(star)

	var cap := Label.new()
	cap.text = "Achievement earned"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	cap.add_theme_color_override("font_color", Icons.COL_GOLD)
	head.add_child(cap)

	var title := Label.new()
	title.text = String(def.get("title", ""))
	title.theme_type_variation = "Head"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = WIDTH - 36
	col.add_child(title)

	var desc := Label.new()
	desc.text = String(def.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = WIDTH - 36
	desc.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	desc.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(desc)
	return card
