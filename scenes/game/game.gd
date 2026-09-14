# T17 — the game. The one entry point (project.godot's run/main_scene), and
# nothing but routing: every screen it shows is an existing scene, instantiated
# as a full-screen child.
#
#   title  →  party setup (party.tscn + creator.tscn)  →  world.tscn (the open world)
#
# O8: the open world is normal play. The old linear route is still wired up, but
# only when SORCMERC_LINEAR_CAMPAIGN is in the environment (same debug-gate shape
# as SORCMERC_SEED/SORCMERC_FAST) — its determinism is what the test suite leans
# on, so it is kept, not user-facing. With the var set the flow is the old one:
#
#   title  →  party setup  →  campaign.tscn  →  summary  →  title
#            └ resume ──────────┘   (the autosave is a linear-run thing too)
#
# Run standalone:  godot --path . scenes/game/game.tscn
extends Control

const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const WorldSave = preload("res://core/world_save.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Scaler = preload("res://core/scaler.gd")
const Icons = preload("res://core/ui_icons.gd")
const SettingsOverlay = preload("res://scenes/settings/settings.gd")
const Sound = preload("res://core/audio.gd")
const Tutorial = preload("res://core/tutorial.gd")

const PARTY_SCENE := "res://scenes/party/party.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign/campaign.tscn"
const COMBAT_SCENE := "res://scenes/main.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"

# O8's one switch. Read live (not cached) so a test can set it between runs.
static func linear_campaign() -> bool:
	return OS.get_environment("SORCMERC_LINEAR_CAMPAIGN") != ""

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
	# T27: title.wav has shipped since the audio pass and nothing ever played it —
	# the front door was the one screen with a bed of its own and no way to hear
	# it. set_combat(false) because the title is also where you land after a run:
	# the tension layer must not follow you out of the fight you just left.
	Sound.set_environment("title")
	Sound.set_combat(false)
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

	# Two slots, two doors: the linear run's autosave is debug-only (behind the flag),
	# the open world's is normal play's.
	if linear_campaign() and CampaignSave.has_save():
		col.add_child(_button("▶  Resume the last run", _resume))
	# O13x: one button per open-world slot, newest first — multiple playthroughs
	# can coexist now, so "Resume" is a list, not a single fixed door.
	for slot in WorldSave.list_slots():
		col.add_child(_button("▶  Resume the open world — %s" % _slot_label(slot),
			_resume_world.bind(slot["id"])))
	col.add_child(_button("✦  New run", show_party_setup))
	col.add_child(_button("❖  Tutorial", show_tutorial))
	col.add_child(_button("⚔  Random battle (debug)", show_random_battle))
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

# O13: the open world has no terminal state to check — there is no "finished" world,
# only the map you left. WorldSave.from_dict re-applies faction opinion itself.
func _resume_world(slot_id: String) -> void:
	WorldSave.set_active_slot(slot_id)
	var saved = WorldSave.load_latest()
	if saved == null:
		show_title()
		return
	show_world(saved["party"], saved["world"])

# "Day 3  08:40  ·  #91A2C4" — the same day/hour/minute arithmetic world.gd's HUD
# clock uses, plus a slice of the slot id so two saves are never indistinguishable
# even when their in-game clocks happen to tie.
func _slot_label(slot: Dictionary) -> String:
	var elapsed: float = slot["elapsed"]
	return "Day %d  %02d:%02d  ·  #%s" % [
		int(elapsed / 1440.0) + 1, int(elapsed / 60.0) % 24, int(elapsed) % 60,
		String(slot["id"]).replace("-", "").right(6).to_upper()]

# --- tutorial -------------------------------------------------------------
#
# T32: straight into the fixed fight — no party setup, the party is pre-made and
# thrown away afterwards. The only thing that differs from a normal fight is the
# `tutorial` flag, which turns on main.gd's walkthrough overlay.

func show_tutorial() -> void:
	var combat = load(COMBAT_SCENE).instantiate()
	combat.party = Tutorial.party()
	combat.spec = Tutorial.SPEC.duplicate(true)
	combat.difficulty = Tutorial.DIFFICULTY
	combat.tutorial = true
	var wrap := Control.new()
	wrap.add_child(combat)
	var back := Button.new()
	back.text = "←  Title"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -160; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap)

# --- random battle (debug) -------------------------------------------------
#
# T42: a quick way to drop into a fight without a whole run, for debugging.
# Cycles through 4 fixed theme/difficulty combos rather than rolling one, so
# a bug seen on press N is the same fight again on the next press N presses
# later — reproducible, not "try again and hope".

const TEST_FIGHTS := [
	{"theme": "goblin-camp", "difficulty": "normal"},
	{"theme": "forest-clearing", "difficulty": "easy"},
	{"theme": "frozen-cave", "difficulty": "hard"},
	{"theme": "sunken-shrine", "difficulty": "normal"},
]
var _test_fight_i := 0

func show_random_battle() -> void:
	var fight: Dictionary = TEST_FIGHTS[_test_fight_i % TEST_FIGHTS.size()]
	_test_fight_i += 1
	var party := Party.new()
	for ch in Presets.party():
		party.add_member(ch)
	var chars: Array = party.party_characters()
	var spec := Scaler.roster_for(chars, fight["difficulty"], {}, fight["theme"])
	spec["theme"] = fight["theme"]

	var combat = load(COMBAT_SCENE).instantiate()
	combat.party = party
	combat.spec = spec
	combat.difficulty = fight["difficulty"]
	var wrap := Control.new()
	wrap.add_child(combat)
	var back := Button.new()
	back.text = "←  Title"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -160; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap)

# --- party setup ----------------------------------------------------------
#
# The party screen does the work (roster, slots, the creator, profiles); this
# only supplies the saved roster and the door out of it.

func show_party_setup() -> void:
	var party := Party.new()
	for ch in CharacterSave.load_all():
		ch.dead = false                  # the barracks is for the living
		ch.hp_current = -1               # ...and rested up — a new run starts at full HP,
		party.add_member(ch)             # not however hurt/downed they were saved
	var wrap := Control.new()
	var screen = load(PARTY_SCENE).instantiate()
	screen.party = party
	wrap.add_child(screen)

	# T-worlds / T9x: three starting maps — small (4 settlements, hand-placed),
	# large (8 settlements, hand-placed, scenes/world/large_world.gd), or
	# procedural (seeded, scenes/world/procedural_world.gd). Meaningless for
	# the linear campaign, which never touches world.gd at all, so only the
	# open-world path reads it.
	var begin := func(size: String) -> void:
		if party.active.is_empty():
			screen._hint.text = "Put at least one character in the active party first."
			return
		if linear_campaign():
			_show_campaign(Campaign.new(party, int(OS.get_environment("SORCMERC_SEED"))))
		else:
			WorldSave.new_slot()          # O13x: a fresh run gets its own slot, never
			show_world(party, null, size) # one an earlier run's autosave still owns

	var begin_small := Button.new()
	begin_small.text = "Begin — Small World  →"
	begin_small.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_small.offset_left = -320; begin_small.offset_top = 12; begin_small.offset_right = -168
	begin_small.pressed.connect(begin.bind("small"))
	wrap.add_child(begin_small)

	var begin_large := Button.new()
	begin_large.text = "Begin — Large World  →"
	begin_large.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_large.offset_left = -160; begin_large.offset_top = 12; begin_large.offset_right = -16
	begin_large.pressed.connect(begin.bind("large"))
	wrap.add_child(begin_large)

	# T9x: a seeded procedural map — scenes/world/procedural_world.gd, same
	# content types as the two hand-placed maps, a fresh layout every run
	# (SORCMERC_SEED pins it, same env var the linear campaign already honours).
	var begin_proc := Button.new()
	begin_proc.text = "Begin — Procedural World  →"
	begin_proc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_proc.offset_left = -496; begin_proc.offset_top = 12; begin_proc.offset_right = -328
	begin_proc.pressed.connect(begin.bind("procedural"))
	wrap.add_child(begin_proc)

	var back := Button.new()
	back.text = "←  Title"
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 16; back.offset_top = 12; back.offset_right = 130
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap)

# --- the open world (normal play) -----------------------------------------
#
# O8: the whole integration is one field — the party the player just assembled
# goes in instead of world.gd's demo roster fallback. The starting map itself
# is one of world.gd's three built-in ones (_small_world / _large_world via
# large_world.gd / ProceduralWorld.build()), picked by the button below.
# `world` is O13's resume path: a loaded map instead of one of world.gd's own
# built-in ones. `size` ("small" | "large" | "procedural") only matters when
# `world` is null — a resumed save already has its map, the size that built
# it is moot.
func show_world(party, world = null, size := "small") -> void:
	var screen = load(WORLD_SCENE).instantiate()
	screen.party = party
	screen.world_size = size
	if world != null:
		screen.world = world
	_swap(screen)

# --- the run (linear, debug-only) -----------------------------------------

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

# Every button on the title and summary screens comes through here. The click
# itself is Icons.clicks() — the same helper the five menu screens use — so the
# sound has one definition for the whole game rather than one per screen.
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	Icons.clicks(b)
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
