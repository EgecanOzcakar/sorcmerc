# T5+T9 — the campaign screen: the route on the left, the quest log on the right,
# the run journal underneath. All state lives in core/campaign.gd; this draws it
# and launches scenes/main.tscn for combat nodes.
#
# Run standalone:  godot --path . scenes/campaign/campaign.tscn
extends Control

const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")
const Creator = preload("res://scenes/creator/creator.gd")

const COL_BG := Color("14161c")
const COL_CARD := Color("1b1f29")
const COL_EDGE := Color("39404f")
const COL_GOLD := Color("c8a75a")
const COL_DIM := Color("8f95a3")
const COL_PARTY := Color("5fbf6a")
const COL_FOE := Color("d15750")

const KIND_COL := {"combat": COL_FOE, "treasure": COL_GOLD, "merchant": Color("8fb7d8"),
	"rest": COL_PARTY}

var party: Party            # injected, or a demo roster
var run: Campaign

var _body := VBoxContainer.new()
var _quests := VBoxContainer.new()
var _header := Label.new()
var _journal := RichTextLabel.new()
var _show_history := false
var _combat = null          # the live scenes/main.tscn instance, while fighting
var _combat_overlay: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Creator.dark_theme()
	if party == null:
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
		party.add_gold(120)
	run = Campaign.new(party)

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16; root.offset_top = 12
	root.offset_right = -16; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 22)
	_header.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(_header)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	cols.add_child(_column("T H E   R O A D", _body, 1.7))
	cols.add_child(_column("Q U E S T   L O G", _quests, 1.0))

	_journal.bbcode_enabled = true
	_journal.scroll_following = true
	_journal.custom_minimum_size = Vector2(0, 96)
	_journal.add_theme_font_size_override("normal_font_size", 13)
	root.add_child(_journal)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var pbtn := Button.new()
	pbtn.text = "Party"
	pbtn.pressed.connect(_open_party)
	footer.add_child(pbtn)

	_refresh()

func _column(title: String, body: VBoxContainer, stretch: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = stretch
	var cap := Label.new()
	cap.text = title
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", COL_GOLD)
	wrap.add_child(cap)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	wrap.add_child(scroll)
	return wrap

# --- rendering ------------------------------------------------------------

func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	_header.text = "»   S T A G E   %d / %d   ·   %d gp   ·   %d XP   «" % [
		mini(run.stage + 1, Campaign.STAGES.size()), Campaign.STAGES.size(), party.gold, run.xp]

	match run.state:
		"picking":
			for i in run.options().size():
				_body.add_child(_node_card(i, run.options()[i]))
		"visiting":
			_body.add_child(_node_panel())
		"combat":
			var l := Label.new()
			l.text = "Fighting…"
			_body.add_child(l)
		_:
			_body.add_child(_end_panel())

	_refresh_quests()
	var lines: Array = []
	for line in run.log:
		lines.append("[color=#c9ccd6]%s[/color]" % line)
	_journal.text = "\n".join(lines)

func _node_card(index: int, node: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_EDGE))
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := Label.new()
	title.text = node["title"]
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", KIND_COL.get(node["kind"], COL_DIM))
	col.add_child(title)
	var desc := Label.new()
	desc.text = "%s  ·  %s" % [node["kind"], node.get("desc", "")]
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", COL_DIM)
	col.add_child(desc)
	var go := Button.new()
	go.text = "Take this road"
	go.pressed.connect(func(): _enter(index))
	col.add_child(go)
	return panel

# The node you are standing on: its kind's controls, then Continue.
func _node_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = run.node.get("title", "")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	match run.node.get("kind", ""):
		"rest":
			for kind in ["short-rest", "long-rest"]:
				var b := Button.new()
				b.text = "Take a %s" % kind.replace("-", " ")
				b.pressed.connect(func(): run.rest(kind); _refresh())
				col.add_child(b)
		"merchant":
			_merchant_ui(col)

	var on := Button.new()
	on.text = "Continue  →"
	on.pressed.connect(func(): run.leave(); _refresh())
	col.add_child(on)
	return panel

func _merchant_ui(col: VBoxContainer) -> void:
	col.add_child(_caption("F O R   S A L E   ·   %d gp in purse" % party.gold))
	for e in run.stock():
		var b := Button.new()
		b.text = "Buy  %s   —   %d gp" % [e["name"], e["price"]]
		b.disabled = party.gold < int(e["price"])
		b.pressed.connect(func(): run.buy(String(e["item_id"])); _refresh())
		col.add_child(b)

	if not party.stash.is_empty():
		col.add_child(_caption("Y O U R   S T A S H"))
		for e in party.stash:
			var id := String(e["item_id"])
			var b := Button.new()
			b.text = "Sell  %s ×%d   —   %d gp" % [Campaign.item_name(id), int(e["quantity"]),
				maxi(1, int(Campaign.item_price(id) * Campaign.SELL_RATE))]
			b.pressed.connect(func(): run.sell(id); _refresh())
			col.add_child(b)

	col.add_child(_caption("W O R K"))
	var offer := run.offer()
	if offer.is_empty():
		col.add_child(_dim("Nothing else needs doing here."))
	else:
		var b := Button.new()
		b.text = "Accept:  %s   (%d gp)" % [offer["title"], int(offer["reward"].get("gold", 0))]
		b.pressed.connect(func(): run.accept(offer); _refresh())
		col.add_child(b)
	for q in Quest.active(party):
		if not Quest.can_turn_in(q):
			continue
		var b := Button.new()
		b.text = "Turn in:  %s   (+%d gp)" % [q["title"], int(q["reward"].get("gold", 0))]
		b.pressed.connect(func(): run.turn_in(q); _refresh())
		col.add_child(b)

func _end_panel() -> Control:
	var panel := PanelContainer.new()
	var won: bool = run.state == "won"
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_PARTY if won else COL_FOE))
	var col := VBoxContainer.new()
	panel.add_child(col)
	var l := Label.new()
	l.text = "The road is walked. %d XP, %d gp." % [run.xp, party.gold] if won \
		else "The party falls. The run ends here."
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", COL_PARTY if won else COL_FOE)
	col.add_child(l)
	var again := Button.new()
	again.text = "New run"
	again.pressed.connect(func(): run = Campaign.new(party); _refresh())
	col.add_child(again)
	return panel

# --- quest log panel ------------------------------------------------------

func _refresh_quests() -> void:
	for c in _quests.get_children():
		c.queue_free()
		_quests.remove_child(c)
	var live := Quest.active(party)
	if live.is_empty():
		_quests.add_child(_dim("No quests. Merchants have work."))
	for q in live:
		var l := Label.new()
		l.text = Quest.describe(q)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", COL_GOLD if q["state"] == "complete" else COL_PARTY)
		_quests.add_child(l)

	var done: Array = party.quests.filter(func(q): return q["state"] == "turned_in")
	if done.is_empty():
		return
	var toggle := Button.new()
	toggle.text = "%s  History (%d)" % ["▾" if _show_history else "▸", done.size()]
	toggle.pressed.connect(func(): _show_history = not _show_history; _refresh_quests())
	_quests.add_child(toggle)
	if _show_history:
		for q in done:
			_quests.add_child(_dim("✔ %s" % q["title"]))

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_DIM)
	return l

func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = edge
	s.set_content_margin_all(10)
	return s

# --- node entry / combat handoff ------------------------------------------

const COMBAT_SCENE := "res://scenes/main.tscn"

func _enter(index: int) -> void:
	var node := run.enter(index)
	if not node.is_empty() and run.state == "combat":
		_launch_combat()
	_refresh()

# The whole handoff: inject party/spec/difficulty, let the combat screen run, and
# read `result` back off it when the fight is over.
func _launch_combat() -> void:
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	_combat.spec = run.combat_spec()
	_combat.difficulty = run.node.get("difficulty", "normal")
	_combat_overlay.add_child(_combat)

	# Wait out the fight — main.gd fills `result` in its _finish().
	while _combat != null and _combat.result.is_empty():
		await get_tree().process_frame
	if _combat == null:
		return
	var result: Dictionary = _combat.result
	_combat = null
	var back := Button.new()
	back.text = "←  Back to the road"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -220; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(func():
		_combat_overlay.queue_free()
		_combat_overlay = null
		run.finish_combat(result)
		_refresh())
	_combat_overlay.add_child(back)

const PARTY_SCENE := "res://scenes/party/party.tscn"

func _open_party() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	overlay.add_child(screen)
	var back := Button.new()
	back.text = "←  Back to the road"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -220; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(func():
		overlay.queue_free()
		_refresh())
	overlay.add_child(back)
