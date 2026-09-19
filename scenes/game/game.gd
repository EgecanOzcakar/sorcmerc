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
const ManualOverlay = preload("res://scenes/manual/manual.gd")
const AchievementsOverlay = preload("res://scenes/achievements/achievements.gd")
const BugReportOverlay = preload("res://scenes/bugreport/bug_report.gd")
const BugReport = preload("res://core/bug_report.gd")
const Sound = preload("res://core/audio.gd")
const Tutorial = preload("res://core/tutorial.gd")
const Registry = preload("res://core/mod/registry.gd")
const StoryRuntime = preload("res://core/mod/story_runtime.gd")
const Coop = preload("res://core/coop.gd")

const PARTY_SCENE := "res://scenes/party/party.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign/campaign.tscn"
const COMBAT_SCENE := "res://scenes/main.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const MODS_SCENE := "res://scenes/mods/mods.tscn"

# O8's one switch. Read live (not cached) so a test can set it between runs.
static func linear_campaign() -> bool:
	return OS.get_environment("SORCMERC_LINEAR_CAMPAIGN") != ""

var _screen: Control = null      # whatever is on show right now
# Which screen that is, in words, for the bug reporter: the routing table above
# is the only thing that knows, and a report filed three screens later still
# wants to say where it came from.
var _screen_label := "title"
# M8: the content pack the player picked out of the browser, waiting for a
# party to be assembled for it. Null is normal play on a built-in map.
var _pack = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Icons.dark_theme()
	# M6: every enabled pack's data lands in the catalog before anything reads
	# it — the front door is the one place that happens, so no screen has to
	# know packs exist to get a pack's monsters and items.
	Registry.scan()
	Registry.apply_data()
	var bg := ColorRect.new()
	bg.color = Icons.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_title()

# One screen at a time; the old one goes. `label` is the screen in words —
# every route through the game passes here, which makes it the one honest place
# to record where the player has been (core/bug_report.gd's breadcrumb trail).
func _swap(to: Control, label: String) -> void:
	_screen_label = label
	BugReport.note("opened the %s screen" % label)
	if _screen != null:
		_screen.queue_free()
	_screen = to
	to.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(to)

# The bug reporter, from the title. Nothing is in play here, so the context is
# just "which screen" — the overlay adds the build and the trail itself.
func report_bug() -> void:
	BugReportOverlay.toggle(self, {"Screen": _screen_label})

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
	# The front page of the company book: the name set large in the serif, the
	# one thing you are most likely to do next in gilt, everything else as a
	# plain list under it. Left-aligned like every ledger page after it.
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 520
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Sorcmerc"
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 64)
	col.add_child(title)
	var tag := Label.new()
	tag.text = "A short road, a hard fight, and whatever you carry home."
	tag.theme_type_variation = "Serif"
	tag.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(tag)
	col.add_child(_gap(18))

	# Two slots, two doors: the linear run's autosave is debug-only (behind the flag),
	# the open world's is normal play's.
	#
	# Both of them ROLL — one slot each, written over as you play — and the title
	# used to say nothing about that at all. "Resume the open world" was the whole
	# of it: no saying what you would be resuming, no saying that New run is going
	# to write over it, and no way to clear it. All three are here now.
	if linear_campaign() and CampaignSave.has_save():
		col.add_child(_button("Resume the last run", _resume))
	var slot: Dictionary = WorldSave.summary()
	if not slot.is_empty():
		col.add_child(_button("Resume the open world", _resume_world, true))
		col.add_child(_dim(slot_lines(slot)))
		col.add_child(_gap(6))
	col.add_child(_button("New run", show_party_setup, slot.is_empty()))
	if not slot.is_empty():
		col.add_child(_dim("One autosave slot. A new run writes over the one above."))
		col.add_child(_gap(6))
	col.add_child(_button("Campaigns & mods", show_content))
	col.add_child(_button("Play together" if Coop.link == null else "Play together  ·  room %s" % Coop.link.code, show_coop))
	col.add_child(_button("Tutorial", show_tutorial))
	var roster := CharacterSave.list_slugs().size()
	col.add_child(_dim("%d in the barracks." % roster if roster != 1 else "1 in the barracks."))
	col.add_child(_gap(12))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.add_child(_quiet("Settings", func(): SettingsOverlay.toggle(self)))
	foot.add_child(_quiet("Field manual", func(): ManualOverlay.toggle(self)))
	# The achievements viewer had no door in the whole game until now: the model
	# and the panel both shipped with T19 and nothing ever opened it.
	foot.add_child(_quiet("Achievements", func(): AchievementsOverlay.open(self)))
	foot.add_child(_quiet("Report a bug", report_bug))
	foot.add_child(_quiet("Random battle (debug)", show_random_battle))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	foot.add_child(_quiet("Quit", func(): get_tree().quit()))
	col.add_child(foot)

	var centre := CenterContainer.new()
	centre.add_child(col)
	_swap(centre, "title")

# What is in the open-world slot, on one line: when the party stopped, where
# they were, who was standing, and what they were carrying.
static func slot_line(slot: Dictionary) -> String:
	var bits: Array = [WorldSave.day_clock(float(slot.get("elapsed", 0.0)))]
	var map := String(slot.get("map", ""))
	if map != "":
		bits.append("%s map" % map)
	var who: Array = slot.get("party", [])
	bits.append(", ".join(who) if not who.is_empty() else "nobody standing")
	bits.append("%d ◉" % int(slot.get("gold", 0)))
	var story := String(slot.get("story", ""))
	if story != "":
		bits.append(story)
	var when: int = int(slot.get("written_at", 0))
	if when > 0:
		bits.append("saved %s" % Time.get_datetime_string_from_unix_time(when, true).replace("T", " "))
	return "  ·  ".join(bits)

# The same facts as two short lines: when and where, then who and what.
static func slot_lines(slot: Dictionary) -> String:
	var when := WorldSave.day_clock(float(slot.get("elapsed", 0.0)))
	var map := String(slot.get("map", ""))
	var who: Array = slot.get("party", [])
	var first := when + (", %s map" % map if map != "" else "")
	var story := String(slot.get("story", ""))
	if story != "":
		first += ", " + story
	var second := (", ".join(who) if not who.is_empty() else "nobody standing") + ", %d ◉" % int(slot.get("gold", 0))
	return first + "\n" + second

# Deleting the only copy of a run is not a one-click thing: this is its own
# screen, and the way back is a button rather than a guess.
func _confirm_delete_world_save() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := Label.new()
	head.text = "Delete the open-world autosave?"
	head.theme_type_variation = "Title"
	col.add_child(head)
	col.add_child(_dim(slot_lines(WorldSave.summary())))
	var body := Label.new()
	body.text = "The characters stay in the barracks. The map, the purse, the stash and the quests do not. This cannot be undone."
	body.theme_type_variation = "Serif"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size.x = 520
	col.add_child(body)
	col.add_child(_gap(8))
	col.add_child(_button("Delete it", func():
		WorldSave.clear()
		show_title()))
	col.add_child(_quiet("Keep it", show_title))
	var centre := CenterContainer.new()
	centre.add_child(col)
	_swap(centre, "delete-the-autosave confirmation")

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
func _resume_world() -> void:
	var saved = WorldSave.load_latest()
	if saved == null:
		show_title()
		return
	show_world(saved["party"], saved["world"], "small", _story_from(saved))

# M7: a save that was telling a story names the pack it came from. The story
# itself is not in the save — only the progress through it — so resuming means
# finding the pack again. A pack that has since been uninstalled, disabled or
# (a bought DLC on a machine that no longer owns it) locked simply resumes as
# the map it already is: the run is not lost, the story is just not being told.
func _story_from(saved: Dictionary):
	var state: Dictionary = saved.get("story", {})
	var pack_id := String(state.get("pack", ""))
	if pack_id.is_empty():
		return null
	var pack = Registry.find(pack_id)
	if pack == null or not pack.live():
		return null
	var story_def = Registry.story_of(pack)
	return StoryRuntime.new(story_def, state, pack_id) if story_def != null else null

# --- M8: campaigns and mods -----------------------------------------------
#
# The browser lists what is installed; picking one only remembers it, because a
# campaign still needs a party and the party screen is where parties are made.

func show_content() -> void:
	var screen = load(MODS_SCENE).instantiate()
	screen.on_back = show_title
	screen.on_play = _choose_pack
	_swap(screen, "campaigns & mods")

func _choose_pack(pack) -> void:
	_pack = pack
	show_party_setup()

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
	back.text = "Title"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -160; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap, "tutorial fight")

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
	back.text = "Title"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -160; back.offset_top = 12; back.offset_right = -16
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap, "random battle (debug)")

# --- play together (docs/spike-coop.md) ------------------------------------
#
# Two players, one party, a six-letter room code and no accounts. The host
# runs the road exactly as in single player — every fight their world puts up
# is announced on the room (scenes/main.gd sees Coop.link) — and the guest's
# screen is the fight, and between fights the wait for the next one. The link
# is made here and lives in Coop.link until "Leave the room".

var _lobby_status: Label = null      # "waiting for your friend" / "your friend is here", live
var _guest_combat = null             # the guest's live scenes/main.tscn, while one is up
var _guest_on_map := false           # the guest is looking at the host's map (world.gd, spectator)

func show_coop() -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 520
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = "Play together"
	title.theme_type_variation = "Title"
	col.add_child(title)
	var tag := Label.new()
	tag.text = "One party, two players. The host runs the road; you both fight."
	tag.theme_type_variation = "Serif"
	tag.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(tag)
	col.add_child(_gap(18))
	_lobby_status = null
	if Coop.link == null:
		col.add_child(_button("Host a room", func():
			Coop.link = Coop.Link.new(Coop.relay_url(), Coop.room_code(), "host")
			show_coop(), true))
		col.add_child(_dim("You get a code to read out. Then start a run as usual."))
		col.add_child(_gap(6))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var code := LineEdit.new()
		code.placeholder_text = "ROOM CODE"
		code.max_length = 6
		code.custom_minimum_size.x = 170
		row.add_child(code)
		var join := func():
			var c := code.text.strip_edges().to_upper()
			if not Coop.valid_code(c):
				code.text = ""
				code.placeholder_text = "SIX LETTERS"
				return
			Coop.link = Coop.Link.new(Coop.relay_url(), c, "guest")
			show_coop_guest()
		code.text_submitted.connect(func(_t): join.call())
		row.add_child(_button("Join", join))
		col.add_child(row)
		col.add_child(_dim("Your friend's code. You play the heroes they hand you."))
	else:
		var code := Label.new()
		code.text = " ".join(Coop.link.code.split(""))
		code.theme_type_variation = "Title"
		code.add_theme_font_size_override("font_size", 56)
		col.add_child(code)
		col.add_child(_dim("Read it out. Your friend types it under Play together → Join."))
		_lobby_status = _dim("")
		col.add_child(_lobby_status)
		col.add_child(_gap(12))
		var slot: Dictionary = WorldSave.summary()
		if not slot.is_empty():
			col.add_child(_button("Resume the open world", _resume_world, true))
		col.add_child(_button("New run", show_party_setup, slot.is_empty()))
		col.add_child(_button("Quick fight — the preset party", show_random_battle))
		col.add_child(_dim("You choose who plays whom as each fight begins. Your friend can join any time, even mid-fight."))
		col.add_child(_gap(6))
		col.add_child(_quiet("Leave the room", func():
			Coop.link.close()
			Coop.link = null
			Coop.split = {}
			show_coop()))
	col.add_child(_gap(12))
	col.add_child(_quiet("Back", show_title))
	var centre := CenterContainer.new()
	centre.add_child(col)
	_swap(centre, "play together")

# The guest before the host has a map up: the room, who is here, and nothing
# to press but Leave. The host's map replaces this the moment it arrives
# (Coop.link.world_pending), and a fight replaces either.
func show_coop_guest() -> void:
	_guest_combat = null
	_guest_on_map = false
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 520
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = "Riding along"
	title.theme_type_variation = "Title"
	col.add_child(title)
	var tag := Label.new()
	tag.text = "Room %s. The next fight your host walks into opens here." % Coop.link.code
	tag.theme_type_variation = "Serif"
	tag.add_theme_color_override("font_color", Icons.COL_BODY)
	col.add_child(tag)
	_lobby_status = _dim("")
	col.add_child(_lobby_status)
	col.add_child(_gap(12))
	col.add_child(_quiet("Leave the room", func():
		Coop.link.close()
		Coop.link = null
		show_coop()))
	var centre := CenterContainer.new()
	centre.add_child(col)
	_swap(centre, "co-op guest")

# The guest's fight: scenes/main.tscn with the message that announced it. The
# screen keeps the link's inbox from here on — the next setup rebuilds the
# fight in place — so this is only ever entered from the waiting screen.
func _guest_fight(first: Dictionary) -> void:
	_guest_on_map = false
	_guest_combat = load(COMBAT_SCENE).instantiate()
	_guest_combat.coop_first = first
	var wrap := Control.new()
	wrap.add_child(_guest_combat)
	var leave := Button.new()
	leave.text = "Leave the room"
	leave.theme_type_variation = "Quiet"
	leave.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)   # under the action log; the header's corner is taken
	leave.offset_left = 16; leave.offset_top = -48; leave.offset_right = 200; leave.offset_bottom = -12
	leave.pressed.connect(func():
		Coop.link.close()
		Coop.link = null
		_guest_combat = null
		show_coop())
	wrap.add_child(leave)
	_swap(wrap, "co-op fight")

func _process(_dt: float) -> void:
	if Coop.link == null:
		return
	Coop.link.pump()   # keeps the socket alive between fights; the fight screen takes what it needs
	if _lobby_status != null and is_instance_valid(_lobby_status):
		_lobby_status.text = ("Your friend is here." if Coop.link.role == "host" else "The host is here. Waiting for a fight…") \
			if Coop.link.other_here() else ("Waiting for your friend…" if Coop.link.role == "host" else "Waiting for the host…")
	if Coop.link.role != "guest":
		return
	var fighting: bool = _guest_combat != null and _guest_combat.result.is_empty()
	if fighting:
		return   # the fight screen owns the inbox; the map waits
	for m in Coop.link.take():
		if m.get("t", "") == "setup" or (m.get("t", "") == "replay" and not m["log"].is_empty()):
			_guest_fight(m)
			return
	# The host's map: on arrival, and again after anything structural (the
	# host autosaves; each autosave is a full save on the wire). A fresh screen
	# each time — the map is cheap to rebuild, and it keeps world.gd's
	# spectator to "do not tick" rather than "also merge".
	if not Coop.link.world_pending.is_empty() and not (_guest_on_map and _screen.has_method("mirror_busy") and _screen.mirror_busy()):
		var saved = WorldSave.from_dict(Coop.link.world_pending)
		Coop.link.world_pending = {}
		Coop.split = Coop.link.owners_latest   # the host's choice of who plays whom, so Coop.mine() agrees here
		if saved != null:
			var old = _screen if _guest_on_map else null   # keep the guest's own camera across the rebuild
			_guest_combat = null
			_guest_on_map = true
			show_world(saved["party"], saved["world"], "small", _story_from(saved), true)
			if old != null and is_instance_valid(old):
				_screen._pan = old._pan; _screen._zoom = old._zoom
				_screen._yaw = old._yaw; _screen._pitch = old._pitch

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
	# The Title/Campaigns and Begin buttons below sit in a row along the top of
	# the wrapper; the screen starts under that row so its header stays clear.
	screen.offset_top = 56

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
			show_world(party, null, size)

	# M8: a chosen pack replaces the three built-in maps with its own — there is
	# one thing to begin, and it is the campaign the player just picked.
	if _pack != null:
		var begin_pack := Button.new()
		begin_pack.text = "Begin %s" % _pack.title()
		begin_pack.theme_type_variation = "Primary"
		begin_pack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		begin_pack.offset_left = -360; begin_pack.offset_top = 12; begin_pack.offset_right = -16
		begin_pack.pressed.connect(func():
			if party.active.is_empty():
				screen._hint.text = "Put at least one character in the active party first."
				return
			_start_pack(party))
		wrap.add_child(begin_pack)
		var cancel := Button.new()
		cancel.text = "Campaigns"
		cancel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cancel.offset_left = 16; cancel.offset_top = 12; cancel.offset_right = 160
		cancel.pressed.connect(func():
			_pack = null
			show_content())
		wrap.add_child(cancel)
		_swap(wrap, "party setup")
		return

	var begin_small := Button.new()
	begin_small.text = "Begin, small world"
	begin_small.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_small.offset_left = -320; begin_small.offset_top = 12; begin_small.offset_right = -168
	begin_small.pressed.connect(begin.bind("small"))
	wrap.add_child(begin_small)

	var begin_large := Button.new()
	begin_large.text = "Begin, large world"
	begin_large.theme_type_variation = "Primary"
	begin_large.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_large.offset_left = -160; begin_large.offset_top = 12; begin_large.offset_right = -16
	begin_large.pressed.connect(begin.bind("large"))
	wrap.add_child(begin_large)

	# T9x: a seeded procedural map — scenes/world/procedural_world.gd, same
	# content types as the two hand-placed maps, a fresh layout every run
	# (SORCMERC_SEED pins it, same env var the linear campaign already honours).
	var begin_proc := Button.new()
	begin_proc.text = "Begin, procedural world"
	begin_proc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	begin_proc.offset_left = -496; begin_proc.offset_top = 12; begin_proc.offset_right = -328
	begin_proc.pressed.connect(begin.bind("procedural"))
	wrap.add_child(begin_proc)

	var back := Button.new()
	back.text = "Title"
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 16; back.offset_top = 12; back.offset_right = 130
	back.pressed.connect(show_title)
	wrap.add_child(back)
	_swap(wrap, "party setup")

# M8: a pack run is an ordinary open-world run — the same scene, the same
# party, the same autosave. The pack supplies the map, and (when it has one) a
# core/mod/story_runtime.gd that the world screen polls.
func _start_pack(party) -> void:
	var world = Registry.world_of(_pack, int(OS.get_environment("SORCMERC_SEED")))
	var story_def = Registry.story_of(_pack)
	var run = StoryRuntime.new(story_def, {}, _pack.id()) if story_def != null else null
	_pack = null
	if world == null:
		# A story-only pack rides on whichever map is already the default: it
		# declared no world, so it did not ask for one.
		show_world(party, null, "small", run)
		return
	show_world(party, world, "small", run)

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
func show_world(party, world = null, size := "small", story = null, spectator := false) -> void:
	var screen = load(WORLD_SCENE).instantiate()
	screen.party = party
	screen.world_size = size
	if world != null:
		screen.world = world
	screen.story = story
	screen.spectator = spectator
	_swap(screen, "co-op map" if spectator else "open world")

# --- the run (linear, debug-only) -----------------------------------------

var campaign = null      # the live campaign.tscn instance, while a run is on

func _show_campaign(run) -> void:
	campaign = load(CAMPAIGN_SCENE).instantiate()
	campaign.run = run                    # party comes off the run
	_swap(campaign, "linear campaign")
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
	panel.add_theme_stylebox_override("panel", Icons.box(Icons.COL_PANEL, _end_color(run.state), 0, 24, 20))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var end_art := Icons.scene_art({"won": "summary-victory", "lost": "summary-defeat"}.get(run.state, ""), null)
	if end_art != null:
		var pic := TextureRect.new()
		pic.texture = end_art
		pic.custom_minimum_size = Vector2(480, 180)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.clip_contents = true
		col.add_child(pic)
	var head := Label.new()
	head.text = {"won": "Victory", "retired": "Retired",
		"lost": "Defeat"}.get(run.state, "The run ends")
	head.theme_type_variation = "Title"
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
	col.add_child(_gap(6))
	col.add_child(_button("Back to the hub", show_title, true))

	var centre := CenterContainer.new()
	centre.add_child(panel)
	_swap(centre, "run summary")

# Everything off what the run already tracked — no summary-only bookkeeping.
static func summary_lines(run) -> Array:
	var out: Array = ["Stages cleared:  %d / %d" % [run.stage, Campaign.STAGE_COUNT],
		"Gold in the purse:  %d ◉" % run.party.gold,
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
func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if primary:
		b.theme_type_variation = "Primary"
	b.pressed.connect(cb)
	Icons.clicks(b)
	return b

func _quiet(text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.theme_type_variation = "Quiet"
	return b

func _gap(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Dim"
	return l
