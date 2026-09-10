# T17 — the game. The one entry point (project.godot's run/main_scene), and
# nothing but routing: every screen it shows is an existing scene, instantiated
# as a full-screen child.
#
#   title  →  party setup (party.tscn + creator.tscn)  →  campaign.tscn  →  summary  →  title
#            └ resume ──────────────────────────────────────┘
#
# Run standalone:  godot --path . scenes/game/game.tscn
extends Control

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Party = preload("res://core/party.gd")
const Icons = preload("res://core/ui_icons.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")

const PARTY_SCENE := "res://scenes/party/party.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign/campaign.tscn"

var _screen: Control = null      # whatever is on show right now

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_title()

# One screen at a time; the old one goes.
func _swap(to: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = to
	to.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(to)

# --- title / continue -----------------------------------------------------
#
# Hoisted out of campaign.gd's _offer_continue(): the autosave question belongs
# at the front door, not on top of a half-built run. (campaign.tscn keeps its own
# copy for running that scene standalone — a dev convenience, not the game.)

func show_title() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "S O R C M E R C"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Icons.FS_TITLE)
	title.add_theme_color_override("font_color", Icons.COL_GOLD)
	col.add_child(title)
	col.add_child(_dim("A short road, a hard fight, and whatever you carry home."))

	if CampaignSave.has_save():
		col.add_child(_button("▶  Resume the last run", _resume))
	col.add_child(_button("✦  New run", show_party_setup))
	var roster := CharacterSave.list_slugs().size()
	col.add_child(_dim("%d character(s) in the barracks." % roster))
	col.add_child(_button("⚙  Settings", func(): SettingsOverlay.toggle(self)))
	col.add_child(_button("Quit", func(): get_tree().quit()))

	var centre := CenterContainer.new()
	centre.add_child(col)
	_swap(centre)

func _resume() -> void:
	var saved = CampaignSave.load_latest()
	if saved == null:
		show_title()
		return
	if saved.state in Campaign.TERMINAL:   # a finished run is not a run
		CampaignSave.clear()
		show_summary(saved)
		return
	_show_campaign(saved)

# --- party setup ----------------------------------------------------------
#
# The party screen does the work (roster, slots, the creator, profiles); this
# only supplies the saved roster and the door out of it.

func show_party_setup() -> void:
	var party := Party.new()
	for ch in CharacterSave.load_all():
		ch.dead = false                  # the barracks is for the living
		party.add_member(ch)
	var wrap := Control.new()
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	wrap.add_child(screen)

	var begin := Button.new()
	begin.text = "Begin the run  →"
	begin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin.offset_left = -220; begin.offset_top = 12; begin.offset_right = -16
	begin.pressed.connect(func():
		if party.active.is_empty():
			screen._hint.text = "Put at least one character in the active party first."
			return
		_show_campaign(Campaign.new(party, int(OS.get_environment("SORCMERC_SEED")))))
	wrap.add_child(begin)

	var back := Button.new()
	back.text = "←  Title"
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 16; back.offset_top = 12; back.offset_right = 130
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap)

# --- the run --------------------------------------------------------------

var campaign = null      # the live campaign.tscn instance, while a run is on

func _show_campaign(run) -> void:
	campaign = load(CAMPAIGN_SCENE).instantiate()
	campaign.run = run                    # party comes off the run
	_swap(campaign)
	await _await_end(run)

# Victory, defeat and retirement all land in the same place: the summary.
# Polled rather than signalled — campaign.gd owns no signal, and this is the
# same wait-it-out shape it already uses for the combat screen.
func _await_end(run) -> void:
	while campaign != null and not (run.state in Campaign.TERMINAL):
		await get_tree().process_frame
	if campaign == null:
		return
	campaign = null
	show_summary(run)

# --- run summary ----------------------------------------------------------

func show_summary(run) -> void:
	# The roster outlives the run: bank the XP and the survivors for next time.
	for ch in run.party.roster:
		CharacterSave.save(ch)
	CampaignSave.clear()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Icons.COL_PANEL, _end_color(run.state)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var head := Label.new()
	head.text = {"won": "V I C T O R Y", "retired": "R E T I R E D",
		"lost": "D E F E A T"}.get(run.state, "T H E   R U N   E N D S")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", Icons.FS_TITLE)
	head.add_theme_color_override("font_color", _end_color(run.state))
	col.add_child(head)

	for line in summary_lines(run):
		col.add_child(_dim(line))

	# The journal, verbatim — it already holds every notable thing that happened.
	var journal := RichTextLabel.new()
	journal.bbcode_enabled = true
	journal.custom_minimum_size = Vector2(560, 200)
	journal.add_theme_font_size_override("normal_font_size", Icons.FS_SMALL)
	journal.text = "[color=%s]%s[/color]" % [Icons.COL_BODY.to_html(false),
		"\n".join(PackedStringArray(run.log))]
	col.add_child(journal)
	col.add_child(_button("←  Back to the hub", show_title))

	var centre := CenterContainer.new()
	centre.add_child(panel)
	_swap(centre)

# Everything off what the run already tracked — no summary-only bookkeeping.
static func summary_lines(run) -> Array:
	var out: Array = ["Stages cleared:  %d / %d" % [run.stage, Campaign.STAGE_COUNT],
		"Gold in the purse:  %d gp" % run.party.gold,
		"Run XP:  %d" % run.xp]
	for ch in run.party.roster:
		out.append("    %s  %s  —  %d XP%s" % [Icons.class_glyph(_class_of(ch)), ch.cname, ch.xp,
			"   (fell on the road)" if ch.dead else ""])
	var loot: Array = []
	for e in run.party.stash:
		loot.append("%s ×%d" % [Campaign.item_name(String(e["item_id"])), int(e["quantity"])])
	out.append("Carried home:  %s" % (", ".join(loot) if not loot.is_empty() else "nothing"))
	return out

static func _class_of(ch) -> String:
	return String(ch.levels[0]["class_id"]) if not ch.levels.is_empty() else ""

static func _end_color(state: String) -> Color:
	return Icons.COL_FOE if state == "lost" else Icons.COL_GOLD

# --- small builders -------------------------------------------------------

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Icons.FS_SMALL)
	l.add_theme_color_override("font_color", Icons.COL_MUTED)
	return l

func _box(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = edge
	s.set_content_margin_all(14)
	return s
