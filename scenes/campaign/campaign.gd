# T5+T9 — the campaign screen: the route on the left, the quest log on the right,
# the run journal underneath. All state lives in core/campaign.gd; this draws it
# and launches scenes/main.tscn for combat nodes.
#
# Run standalone:  godot --path . scenes/campaign/campaign.tscn
extends Control

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const Party = preload("res://core/party.gd")
const Quest = preload("res://core/quest.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")

const Icons = preload("res://core/ui_icons.gd")

const COL_BG := Icons.COL_BG
const COL_CARD := Icons.COL_PANEL
const COL_EDGE := Icons.COL_EDGE
const COL_GOLD := Icons.COL_GOLD
const COL_DIM := Icons.COL_MUTED
const COL_PARTY := Icons.COL_PARTY
const COL_FOE := Icons.COL_FOE

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
	var injected := party != null or run != null
	if run != null:                 # T17: the hub hands a loaded/resumed run straight in
		party = run.party
	if party == null:
		party = Party.new()
		for ch in Party.demo_roster():
			party.add_member(ch)
		party.add_gold(120)
	# T12: the route is seed-generated, so honour SORCMERC_SEED here the way
	# scenes/main.gd does for fights — a replayed run walks the same road.
	if run == null:
		run = Campaign.new(party, int(OS.get_environment("SORCMERC_SEED")))

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
	_header.add_theme_font_size_override("font_size", Icons.FS_TITLE)
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
	_journal.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	root.add_child(_journal)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var pbtn := Button.new()
	pbtn.text = "Party"
	pbtn.pressed.connect(_open_party)
	footer.add_child(pbtn)
	var sbtn := Button.new()
	sbtn.text = "⚙  Settings"
	sbtn.pressed.connect(func(): SettingsOverlay.toggle(self))
	footer.add_child(sbtn)

	_refresh()
	if not injected and CampaignSave.has_save():
		_offer_continue()

# No main menu exists yet (deliberately out of scope): when the scene is run on its
# own and an autosave is sitting there, ask once, over the fresh demo run.
func _offer_continue() -> void:
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_theme_stylebox_override("panel", _box(COL_CARD, COL_GOLD))
	add_child(overlay)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	overlay.add_child(col)
	col.add_child(_caption("A   R U N   I S   S A V E D"))
	var cont := Button.new()
	cont.text = "Resume the last run"
	cont.pressed.connect(func():
		var saved = CampaignSave.load_latest()
		overlay.queue_free()
		if saved == null:
			return
		run = saved
		party = run.party
		_refresh())
	col.add_child(cont)
	var fresh := Button.new()
	fresh.text = "Begin a new run"
	fresh.pressed.connect(func(): overlay.queue_free())
	col.add_child(fresh)

func _column(title: String, body: VBoxContainer, stretch: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = stretch
	var cap := Label.new()
	cap.text = title
	cap.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
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
		mini(run.stage + 1, Campaign.STAGE_COUNT), Campaign.STAGE_COUNT, party.gold, run.xp]

	var fallen: Array = party.roster.filter(func(ch): return ch.dead)
	if not fallen.is_empty():
		_body.add_child(_fallen_panel(fallen))

	match run.state:
		"picking":
			for i in run.options().size():
				_body.add_child(_node_card(i, run.options()[i]))
			_body.add_child(_retire_card())
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
		lines.append("[color=%s]%s[/color]" % [Icons.COL_BODY.to_html(false), line])
	_journal.text = "\n".join(lines)

func _node_card(index: int, node: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_EDGE))
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := Label.new()
	title.text = "%s  %s" % [Icons.node_glyph(node["kind"]), node["title"]]
	title.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	title.add_theme_color_override("font_color", KIND_COL.get(node["kind"], COL_DIM))
	col.add_child(title)
	var desc := Label.new()
	desc.text = "%s  ·  %s" % [node["kind"], node.get("desc", "")]
	desc.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	desc.add_theme_color_override("font_color", COL_DIM)
	col.add_child(desc)
	var go := Button.new()
	go.text = "Take this road"
	go.pressed.connect(func(): _enter(index))
	col.add_child(go)
	return panel

# T17 — the fourth road: none of them. Only ever offered while picking (the
# model refuses it anywhere else), and armed by a second press so nobody ends a
# good run with a stray click.
var _retire_armed := false

func _retire_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_GOLD if _retire_armed else COL_EDGE))
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := Label.new()
	title.text = "⌂  Retire from the road"
	title.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)
	col.add_child(_dim("Walk home with the gold, XP and loot you have. The run ends here."))
	var b := Button.new()
	b.text = "Yes — end the run now" if _retire_armed else "Retire…"
	b.pressed.connect(func():
		if _retire_armed:
			run.retire()
		_retire_armed = not _retire_armed
		_refresh())
	col.add_child(b)
	return panel

# The node you are standing on: its kind's controls, then Continue.
func _node_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "%s  %s" % [Icons.node_glyph(run.node.get("kind", "")), run.node.get("title", "")]
	title.add_theme_font_size_override("font_size", Icons.FS_HEAD)
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	match run.node.get("kind", ""):
		"rest":
			for kind in ["short-rest", "long-rest"]:
				var b := Button.new()
				b.text = "Take a %s" % kind.replace("-", " ")
				b.pressed.connect(func(): run.rest(kind); _refresh())
				col.add_child(b)
			_identify_ui(col)
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
		b.add_theme_color_override("font_color", Icons.item_color(String(e["item_id"])))
		b.disabled = party.gold < int(e["price"])
		b.pressed.connect(func(): run.buy(String(e["item_id"])); _refresh())
		col.add_child(b)

	if not party.stash.is_empty():
		col.add_child(_caption("Y O U R   S T A S H"))
		for e in party.stash:
			var id := String(e["item_id"])
			var b := Button.new()
			var nm: String = Campaign.item_name(id) if Party.is_identified(e) \
				else Campaign.mystery_name(id)
			b.text = "Sell  %s ×%d   —   %d gp" % [nm, int(e["quantity"]),
				maxi(1, int(Campaign.item_price(id) * Campaign.SELL_RATE))]
			b.add_theme_color_override("font_color", Icons.item_color(id))
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

# Examining loot over the short rest: Intelligence (Arcana) vs a DC that scales
# with the item's rarity (rarer = harder — see Campaign.IDENTIFY_TARGET), one
# attempt per item per camp. The party's best arcanist does the examining —
# nobody sits their wizard out of this, so there is no chooser, just the button.
func _identify_ui(col: VBoxContainer) -> void:
	var mysteries: Array = party.unidentified()
	if mysteries.is_empty():
		return
	col.add_child(_caption("U N I D E N T I F I E D   ·   Arcana check"))
	var who := run.arcana_examiner()
	for e in mysteries:
		var id := String(e["item_id"])
		if who == "":
			col.add_child(_dim("%s — nobody is awake to examine it." % Campaign.mystery_name(id)))
			continue
		var bonus := run.arcana_bonus(who)
		var b := Button.new()
		b.text = "Examine  %s   (%s, Arcana %+d vs DC %d)" % [Campaign.mystery_name(id),
			party.get_member(who).cname, bonus, Campaign.identify_dc(id)]
		b.disabled = id in run.identify_failed
		if b.disabled:
			b.text += "   — nothing learned here"
		b.pressed.connect(func(): run.identify_check(id, who); _refresh())
		col.add_child(b)

# The fallen: Revivify from an active caster, or burn a Scroll of Resurrection.
# 300 gp either way; both bring the target back benched at 1 HP.
func _fallen_panel(fallen: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_FOE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_caption("T H E   F A L L E N   ·   %d gp to raise one" % Party.REVIVE_COST))
	var caster := Party.resurrection_caster(party)
	var scroll := Party.has_resurrection_scroll(party)
	for ch in fallen:
		col.add_child(_dim("%s lies dead." % ch.cname))
		if caster != "":
			var b := Button.new()
			b.text = "Revivify  %s   (%s casts, −%d gp)" % [ch.cname, caster, Party.REVIVE_COST]
			b.disabled = not Party.can_resurrect(party)
			b.pressed.connect(func(): run.resurrect(ch.id, "spell", caster); _refresh())
			col.add_child(b)
		if scroll:
			var b2 := Button.new()
			b2.text = "Read the Scroll of Resurrection over %s   (−%d gp)" % [ch.cname, Party.REVIVE_COST]
			b2.disabled = not Party.can_resurrect(party)
			b2.pressed.connect(func(): run.resurrect(ch.id, "scroll"); _refresh())
			col.add_child(b2)
		if caster == "" and not scroll:
			col.add_child(_dim("No one can raise them — no Revivify, no scroll."))
	return panel

func _end_panel() -> Control:
	var panel := PanelContainer.new()
	var won: bool = run.state in ["won", "retired"]
	panel.add_theme_stylebox_override("panel", _box(COL_CARD, COL_PARTY if won else COL_FOE))
	var col := VBoxContainer.new()
	panel.add_child(col)
	var l := Label.new()
	l.text = "The road is walked. %d XP, %d gp." % [run.xp, party.gold] if run.state == "won" \
		else "Retired. %d XP, %d gp brought home." % [run.xp, party.gold] if run.state == "retired" \
		else "The party falls. The run ends here."
	l.add_theme_font_size_override("font_size", Icons.FS_HEAD)
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
		l.add_theme_font_size_override("font_size", Icons.FS_BODY)
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
	l.add_theme_font_size_override("font_size", Icons.FS_CAPTION)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
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
	_retire_armed = false
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
	_combat.difficulty = run.node_difficulty()
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
