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
const ManualOverlay = preload("res://scenes/manual/manual.gd")
const BugReportOverlay = preload("res://scenes/bugreport/bug_report.gd")

const Icons = preload("res://core/ui_icons.gd")

const COL_BG := Icons.COL_BG
const COL_CARD := Icons.COL_PANEL
const COL_EDGE := Icons.COL_EDGE
const COL_GOLD := Icons.COL_GOLD
const COL_DIM := Icons.COL_MUTED
const COL_PARTY := Icons.COL_PARTY
const COL_FOE := Icons.COL_FOE

const KIND_COL := {"combat": COL_FOE, "treasure": COL_GOLD, "merchant": Icons.COL_ACCENT,
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

	_header.theme_type_variation = "Title"
	root.add_child(_header)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	cols.add_child(_column("The road", _body, 1.7))
	cols.add_child(_column("Quest log", _quests, 1.0))

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
	var mbtn := Button.new()
	mbtn.text = "Manual"
	mbtn.pressed.connect(func(): ManualOverlay.toggle(self))
	footer.add_child(mbtn)
	var bbtn := Button.new()
	bbtn.text = "Report a bug"
	bbtn.pressed.connect(func(): BugReportOverlay.toggle(self, {
		"Screen": "the linear campaign map",
		"Stage": "%d of %d" % [run.stage, Campaign.STAGE_COUNT],
		"State": run.state,
		"Gold": "%d ◉" % run.party.gold,
	}))
	footer.add_child(bbtn)

	_refresh()
	# A run saved mid-fight comes back to the fight — otherwise the map sits on
	# "Fighting…" with nothing to fight.
	if run.state == "combat" and not run.node.is_empty():
		_launch_combat()
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
	col.add_child(_caption("A run is saved"))
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
	cap.theme_type_variation = "Caption"
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
	_header.text = "Stage %d of %d.  %d ◉, %d XP" % [
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
	title.theme_type_variation = "Head"
	title.add_theme_color_override("font_color", KIND_COL.get(node["kind"], COL_DIM))
	col.add_child(title)
	var desc := Label.new()
	# The difficulty rides beside the kind, not in the title: "The warband camp
	# (hard)" was the only node that said it, and it said it in the fiction.
	var kind := String(node["kind"]).capitalize()
	var diff := String(node.get("difficulty", "normal"))
	if diff != "normal":
		kind += ", " + diff
	desc.text = "%s.  %s" % [kind, node.get("desc", "")]
	desc.theme_type_variation = "Dim"
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
	title.theme_type_variation = "Head"
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
	title.theme_type_variation = "Head"
	title.add_theme_color_override("font_color", COL_GOLD)
	col.add_child(title)

	match run.node.get("kind", ""):
		"rest":
			for kind in ["short-rest", "long-rest"]:
				var b := Button.new()
				var left := run.long_rests_left() if kind == "long-rest" else run.short_rests_left()
				b.text = "Take a %s   (%d left this run)" % [kind.replace("-", " "), left]
				b.disabled = left <= 0
				b.pressed.connect(func(): run.rest(kind); _refresh())
				col.add_child(b)
			_identify_ui(col)
		"merchant":
			_merchant_ui(col)
		"treasure", "combat":
			_opportunity_ui(col)

	var on := Button.new()
	on.text = "Continue  →"
	on.pressed.connect(func(): run.leave(); _refresh())
	col.add_child(on)
	return panel

# T25 — a settlement is one tab per service it carries, Generalist always first.
# Every tab buys/sells through the same run.buy()/run.sell(); the only difference
# is which catalog it shows. The NPC's one flavour line heads their tab.
func _merchant_ui(col: VBoxContainer) -> void:
	col.add_child(_caption("%s.  %d ◉ in the purse" % [
		String(run.node.get("size", "camp")).to_upper(), party.gold]))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 300)
	col.add_child(tabs)
	for service in run.services():
		var page := VBoxContainer.new()
		page.name = String(Campaign.SERVICE_NAMES.get(service, service))
		tabs.add_child(page)
		# Campaign merchant nodes have no faction; the road is human country.
		var pic := Icons.portrait_rect(String(run.node.get("faction", "human")), service, 120)
		var line := run.npc_line(service)
		var head := HBoxContainer.new()
		page.add_child(head)
		if pic != null:
			pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			head.add_child(pic)
		if line != "":
			var l := _dim(line)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			head.add_child(l)
		_service_page(service, page)

func _service_page(service: String, page: VBoxContainer) -> void:
	for e in run.service_stock(service):
		var b := Button.new()
		b.text = "Buy  %s   —   %d ◉" % [e["name"], e["price"]]
		b.add_theme_color_override("font_color", Icons.item_color(String(e["item_id"])))
		b.disabled = party.gold < int(e["price"]) or int(e["price"]) <= 0
		b.pressed.connect(func(): run.buy(String(e["item_id"])); _refresh())
		page.add_child(b)

	match service:
		"generalist":
			if not party.stash.is_empty():
				page.add_child(_caption("Your stash"))
				for e in party.stash:
					var id := String(e["item_id"])
					var b := Button.new()
					var nm: String = Campaign.item_name(id) if Party.is_identified(e) \
						else Campaign.mystery_name(id)
					b.text = "Sell  %s ×%d   —   %d ◉" % [nm, int(e["quantity"]),
						maxi(1, int(Campaign.item_price(id) * Campaign.SELL_RATE))]
					b.add_theme_color_override("font_color", Icons.item_color(id))
					b.pressed.connect(func(): run.sell(id); _refresh())
					page.add_child(b)
		"librarian":
			page.add_child(_caption("Readings, %d ◉ and no roll" % Campaign.IDENTIFY_FEE_GP))
			var mysteries: Array = party.unidentified()
			if mysteries.is_empty():
				page.add_child(_dim("Nothing of yours needs reading."))
			for e in mysteries:
				var id := String(e["item_id"])
				var b := Button.new()
				b.text = "Identify  %s   —   %d ◉" % [Campaign.mystery_name(id),
					Campaign.IDENTIFY_FEE_GP]
				b.disabled = party.gold < Campaign.IDENTIFY_FEE_GP
				b.pressed.connect(func(): run.identify_for_fee(id); _refresh())
				page.add_child(b)
		"healer":
			var b := Button.new()
			b.text = "Tend the whole party   —   %d ◉" % Campaign.HEALER_GP
			b.disabled = party.gold < Campaign.HEALER_GP
			b.pressed.connect(func(): run.heal_party(); _refresh())
			page.add_child(b)
		"innkeeper":
			page.add_child(_caption("Work"))
			var offer := run.offer()
			if offer.is_empty():
				page.add_child(_dim("Nothing else needs doing here."))
			else:
				var b := Button.new()
				b.text = "Accept:  %s   (%d ◉)" % [offer["title"], int(offer["reward"].get("gold", 0))]
				b.pressed.connect(func(): run.accept(offer); _refresh())
				page.add_child(b)
			for q in Quest.active(party):
				if not Quest.can_turn_in(q, party):
					continue
				var b := Button.new()
				b.text = "Turn in:  %s   (+%d ◉)" % [q["title"], int(q["reward"].get("gold", 0))]
				b.pressed.connect(func(): run.turn_in(q); _refresh())
				page.add_child(b)

# Examining loot over the short rest: Intelligence (Arcana) vs a DC that scales
# with the item's rarity (rarer = harder — see Campaign.IDENTIFY_TARGET), one
# attempt per item per camp. The party's best arcanist does the examining —
# nobody sits their wizard out of this, so there is no chooser, just the button.
# T30 — a Perception/Survival check on offer at a treasure room or a just-won
# fight: one attempt, pass or fail, no retry at this node.
func _opportunity_ui(col: VBoxContainer) -> void:
	if not run.scouted.is_empty():
		col.add_child(_caption("The road ahead"))
		for n in run.scouted:
			col.add_child(_dim("%s — %s" % [n["title"], String(n.get("difficulty", "?"))]))
		return
	var opp := run.opportunity()
	if opp.is_empty():
		return
	var who = party.get_member(String(opp["char_id"]))
	if who == null:
		return
	var skill: String = String(opp["skill"])
	var bonus := run.skill_bonus(who.id, skill)
	var b := Button.new()
	b.text = "%s   (%s, %s %+d vs DC %d)" % [String(opp["label"]), who.cname,
		skill.capitalize(), bonus, int(opp["dc"])]
	b.pressed.connect(func(): run.opportunity_check(who.id); _refresh())
	col.add_child(b)

func _identify_ui(col: VBoxContainer) -> void:
	var mysteries: Array = party.unidentified()
	if mysteries.is_empty():
		return
	col.add_child(_caption("Unidentified, an Arcana check each"))
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
	col.add_child(_caption("The fallen, %d ◉ a level to raise" % Party.REVIVE_PER_LEVEL))
	var caster := Party.resurrection_caster(party)
	var scroll := Party.has_resurrection_scroll(party)
	for ch in fallen:
		col.add_child(_dim("%s lies dead." % ch.cname))
		if caster != "":
			var b := Button.new()
			b.text = "Revivify  %s   (%s casts, −%d ◉)" % [ch.cname, caster, Party.revive_cost(ch)]
			b.disabled = not Party.can_resurrect(party, ch.id)
			b.pressed.connect(func(): run.resurrect(ch.id, "spell", caster); _refresh())
			col.add_child(b)
		if scroll:
			var b2 := Button.new()
			b2.text = "Read the Scroll of Resurrection over %s   (−%d ◉)" % [ch.cname, Party.revive_cost(ch)]
			b2.disabled = not Party.can_resurrect(party, ch.id)
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
	l.text = "The road is walked. %d XP, %d ◉." % [run.xp, party.gold] if run.state == "won" \
		else "Retired. %d XP, %d ◉ brought home." % [run.xp, party.gold] if run.state == "retired" \
		else "The company falls. The run ends here."
	l.theme_type_variation = "Head"
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
	l.theme_type_variation = "Caption"
	return l

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "Dim"
	return l

# A node card: the ledger row's left bar in the kind's colour — a fight is
# red down the edge, a cache gilt — over the plain panel.
func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := Icons.box(bg, Color(0, 0, 0, 0), 0, 14, 10)
	s.border_color = edge
	s.border_width_left = 3
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
# T41: whether this fight was scouted comes off the run (enter() works it out and
# campaign_save.gd persists it), so resuming a mid-combat save keeps the ambush.
func _launch_combat() -> void:
	_combat_overlay = Control.new()
	_combat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_combat_overlay)
	_combat = load(COMBAT_SCENE).instantiate()
	_combat.party = party
	_combat.spec = run.combat_spec()
	_combat.difficulty = run.node_difficulty()
	_combat.scouted_ahead = run.node_scouted
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
