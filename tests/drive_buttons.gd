# A silent-no-op sweep. For every screen below, in every mode/page it can be in,
# it finds each visible, enabled Button/OptionButton/CheckBox/CheckButton, presses
# it on a freshly arranged copy of that page, and asserts something observably
# changed. Born out of e3cc910: the creator's quick-build button was wired to a
# handler whose whole body sat inside `if _abil_mode == "array"`, so from Point Buy
# it did nothing at all — no state change, no error, no message. These screens build
# their UI imperatively (`Button.new()` + `pressed.connect(...)`), which makes that
# shape easy to write and invisible without a driver like this one.
#   godot --headless --path . -s tests/drive_buttons.gd
#
# HOW A PRESS IS JUDGED
# Each press is measured against a fingerprint taken one frame before and one frame
# after, in two halves:
#   * the UI — every Control under the screen: class, text, visibility, disabled,
#     button_pressed, an OptionButton's selection and item count, a Range's value,
#     a TabContainer's current tab.
#   * the model — a per-screen string of the state that screen edits (the Character
#     being built, the party's purse and stash, the run's state/stage/journal, the
#     settings object...), supplied by each sweep's `model` callable.
#
# The fingerprint deliberately does NOT cover: colours, fonts and theme overrides
# (a button that only recolours itself reads as inert here — none of these screens
# lean on that); tooltips; layout and geometry; scroll and focus position; icons;
# anything written to disk that is not also mirrored on screen; and anything that
# only settles more than one frame after the press.
#
# Firing never touches the pressed control's own widget state — a plain button gets
# `pressed`, a toggle gets `toggled`, an OptionButton gets `item_selected` for the
# next item — precisely so a control flipping its own checkmark cannot be mistaken
# for the screen having done something. The change has to come out of the handler.
#
# Every page is rebuilt from scratch before every single press, so no press is ever
# judged against a state some earlier press left behind (which is how an inert
# button hides: it looks fine second in a sequence).
#
# NOT COVERED, ON PURPOSE
#   * the world map (scenes/world/*) and the party screen (scenes/party/party.gd).
#     Both are being rewritten as this lands, so sweeping them would be testing a
#     moving target. A deliberate follow-up — each is one more sweep() call.
#   * the creator's "free subclasses — pick 2" widget. Reaching it needs a class
#     unlocked by lifetime XP, and its Confirm calls Prog.unlock_class(), which
#     writes this machine's real user://progression.json. A test may not do that,
#     so the sweep pins an all-default progression profile in memory instead (which
#     also makes every species/class gate deterministic) and leaves that alone.
#   * combat itself (scenes/main.gd) — drive_ui.gd's job. Buttons that open a fight
#     are pressed and checked here; the fight they open is not walked.
#   * sliders, LineEdits and hex clicks: this sweep is about buttons.
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Campaign = preload("res://core/campaign.gd")
const CampaignSave = preload("res://core/campaign_save.gd")
const WorldSave = preload("res://core/world_save.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Prog = preload("res://core/progression.gd")
const Settings = preload("res://core/settings.gd")
const Quest = preload("res://core/quest.gd")

const SEED := 20260913          # any fixed seed; the campaign route must replay
# A route whose merchant is a town, not a village. Settlement size is what decides
# how many specialists a settlement carries (Campaign.SIZE_SPECIALISTS), so a
# single seed only ever reaches Generalist + Innkeeper and the healer/librarian/
# smith tabs would go unpressed. This seed lands a town; both are swept.
const TOWN_SEED := 101

var _pass := 0
var _fail := 0
var _presses := 0
var _pages := 0
var _inert := 0                 # presses allowed to do nothing, each with a reason
var _tally: Array = []          # page -> how many controls it offered
var _host: Control              # every screen mounts under this, never under `root`:
                                # achievements.gd/progression.gd read a root parent
                                # as "running standalone" and their Close button
                                # then calls get_tree().quit().

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	OS.set_environment("SORCMERC_FAST", "1")
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
	Prog._current = Prog.new()
	_settings_backup = FileAccess.get_file_as_string(Settings.PATH)
	CampaignSave.clear()
	WorldSave.clear()
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_host)
	_run_all()

var _settings_backup := ""

# The settings overlay writes straight through to user://settings.json, so put the
# developer's own file back the way we found it.
func _restore_settings() -> void:
	if _settings_backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_settings_backup)
			f.close()
	Settings._current = null

func _run_all() -> void:
	await process_frame
	await _creator()
	await _levelup()
	await _profile()
	await _settings()
	await _viewers()
	await _campaign()
	await _title()
	CampaignSave.clear()
	WorldSave.clear()
	_restore_settings()
	print("  swept: ", ", ".join(PackedStringArray(_tally)))
	print("drive_buttons: %d pages, %d presses (%d inert by design) — %d passed, %d failed" % [
		_pages, _presses, _inert, _pass, _fail])
	quit(1 if _fail > 0 else 0)

# =========================================================================
# The harness
# =========================================================================

# Every pressable control under `n`, in tree order, that a player could click right
# now. Queued-for-deletion nodes are the previous render still waiting out the
# frame; invisible ones include everything on a TabContainer's other tabs.
func controls(n: Node) -> Array:
	var out: Array = []
	_collect(n, out)
	return out

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is BaseButton and not c.is_queued_for_deletion() \
				and c.is_visible_in_tree() and not c.disabled:
			out.append(c)
		_collect(c, out)

# Identity of the i'th control on a page — used to confirm that re-arranging really
# put the same screen back before we press into it.
func key(i: int, c: BaseButton) -> String:
	return "%d %s %s" % [i, c.get_class(), c.text]

func _ui_print(n: Node, out: PackedStringArray) -> void:
	for c in n.get_children():
		if c is Control:
			var line: String = c.get_class()
			if not c.visible:
				line += " hidden"
			if c is Label or c is Button or c is LineEdit or c is RichTextLabel:
				line += " ·" + String(c.text)
			if c is BaseButton:
				line += " ·d%s·p%s" % [c.disabled, c.button_pressed]
			if c is OptionButton:
				line += " ·s%d/%d" % [c.selected, c.item_count]
			if c is Range:
				line += " ·v%.2f" % c.value
			if c is TabContainer:
				line += " ·tab%d" % c.current_tab
			out.append(line)
		_ui_print(c, out)

# `screen` is untyped on purpose: a press can free the screen, and a typed Node
# parameter rejects an already-freed object before the guard below can answer.
func fingerprint(screen, model: Callable) -> String:
	if not is_instance_valid(screen) or screen.is_queued_for_deletion():
		return "<the screen is gone>"
	var ui := PackedStringArray()
	_ui_print(screen, ui)
	var m: String = String(model.call()) if model.is_valid() else ""
	return "%d\n%s\n--\n%s" % [ui.size(), "\n".join(ui), m]

# Fire the signal the handler is connected to, without mutating the control's own
# state — see the header: a self-flip must never pass for "the screen did something".
func fire(c: BaseButton) -> void:
	_presses += 1
	if c is OptionButton:
		var ob: OptionButton = c
		if ob.item_count > 0:
			ob.item_selected.emit((ob.selected + 1) % ob.item_count)
	elif c.toggle_mode:
		c.toggled.emit(not c.button_pressed)
	else:
		c.pressed.emit()

# One page of one screen.
#   arrange — rebuilds this exact page from scratch and returns the screen node.
#   model   — the screen's own state, stringified (see the header).
#   expect  — Callable(BaseButton) -> String, the screen's verdict on a control
#             before it is pressed: "" demands a change, "inert: why" allows one
#             that legitimately does nothing here, "gone: why" is a control that
#             leaves the screen, "skip: why" one that must not be pressed at all.
#   least   — how many pressable controls this page must have. A page that renders
#             nothing passes every press check it has, which is none: the floor is
#             what stops that from reading as success (see _creator() for the
#             regression that made this necessary).
func sweep(page: String, arrange: Callable, model: Callable, expect: Callable,
		least := 1) -> void:
	_pages += 1
	var screen: Node = arrange.call()
	await process_frame
	var found: Array = controls(screen)
	var keys := PackedStringArray()
	for i in found.size():
		keys.append(key(i, found[i]))
	check(keys.size() >= least, "%s: renders its controls (%d pressable, want >= %d)"
		% [page, keys.size(), least])
	_tally.append("%s:%d" % [page, keys.size()])

	for i in keys.size():
		screen = arrange.call()
		await process_frame
		var now: Array = controls(screen)
		if i >= now.size() or key(i, now[i]) != keys[i]:
			check(false, "%s: re-arranging did not reproduce the page (wanted '%s', got '%s')"
				% [page, keys[i], key(i, now[i]) if i < now.size() else "nothing (%d controls)" % now.size()])
			continue
		var c: BaseButton = now[i]
		var verdict: String = String(expect.call(c))
		if verdict.begins_with("skip"):
			continue
		# Read the label now: a press that re-renders the page frees the very button
		# that was pressed, and the failure message still has to name it.
		var label: String = c.text
		var before := fingerprint(screen, model)
		fire(c)
		await process_frame
		var after := fingerprint(screen, model)

		if verdict.begins_with("gone"):
			check(not is_instance_valid(screen) or screen.is_queued_for_deletion(),
				"%s: '%s' should leave the screen (%s)" % [page, label, verdict])
		elif verdict.begins_with("inert"):
			_inert += 1
			check(before == after,
				"%s: '%s' was expected to do nothing (%s) but changed something"
					% [page, label, verdict])
		else:
			check(before != after,
				"%s: pressing '%s' changed nothing — silent no-op" % [page, label])

# Clears the mount point and stands a scene up on it. `setup` runs on the instance
# before it enters the tree, which is the only way to inject into a screen whose
# _ready() branches on what it was handed (campaign.gd, game.gd).
#
# queue_free() only, deliberately no remove_child(): a screen this sweep opened may
# still have a coroutine in flight (scenes/main.gd's turn loop, campaign.gd's
# wait-out-the-fight poll), and detaching the node before it is freed leaves that
# coroutine to resume on a node with no tree — get_tree() then returns null and the
# console fills with errors this sweep caused rather than found. Left in the tree it
# dies quietly at the end of the frame instead. controls() and the fingerprint both
# skip queued nodes, so the corpse is never pressed or measured.
func fresh(path: String, setup := Callable()) -> Control:
	for c in _host.get_children():
		c.queue_free()
	var o: Control = load(path).instantiate()
	if setup.is_valid():
		setup.call(o)
	_host.add_child(o)
	return o

# =========================================================================
# 1. the creator — six steps, two ability modes
# =========================================================================

var _cre: Control = null

# A fresh build parked at a known point in the flow. _goto() re-renders the whole
# body from `ch`, so resetting the character is a complete reset of the page — no
# need to re-instantiate the scene between presses.
func _creator_at(step: int, species: String, cls: String, background: String,
		mode: String, equip: Array = []) -> Control:
	if _cre == null or not is_instance_valid(_cre) or _cre.is_queued_for_deletion():
		_cre = fresh("res://scenes/creator/creator.tscn")
	var manual = _cre.get_node_or_null("ManualOverlay")   # #103: a press opened it; the next page starts without it
	if manual != null:
		_cre.remove_child(manual)
		manual.queue_free()
	var ch = Creator.new_character()
	ch.cname = "Sweep Testerson"
	if species != "":
		ch.species_id = species
	if cls != "":
		ch.add_level(cls, -1)
	if background != "":
		ch.background_id = background
	for item in equip:
		ch.equipped.append(String(item))
	if mode == "pointbuy":
		# Point buy starts every score at 8, where "−" is correctly refused (the
		# floor) — no press on that page would prove anything. Start from an
		# interior spread instead: 20 of the 27 points spent, every score both
		# raisable within budget and lowerable above the floor.
		ch.base_abilities = {"str": 13, "dex": 13, "con": 12, "int": 10, "wis": 10, "cha": 10}
	_cre.ch = ch
	_cre._confirmed = null
	_cre._free_picks.clear()
	_cre._abil_mode = mode
	ch.dirty()
	_cre._goto(step)
	return _cre

func _creator_model() -> String:
	var ch = _cre.ch
	return "%s|%s|%s|%s|%d|%s|%s|%s|%s|%s" % [ch.cname, ch.species_id, String(ch.class_id()),
		ch.background_id, _cre._step, _cre._abil_mode, ch.base_abilities,
		ch.choices, ch.equipped, _cre._confirmed != null]

# The creator marks the currently-picked option in a group with a "● " prefix. Four
# of those are genuinely idempotent, so the allowance is written per group rather
# than granted to every "● " on the screen: Species, Class and Background, whose
# setters all open with "if it is already that, return", and the armor rack's
# "● None".
#
# Everything else marked "● " still has to act, and does: a "● " inside a choice
# widget un-picks it (toggle() reads the second press as "take it back"), "● Standard
# array" re-applies the class's recommended array over whatever is there, and
# "● Point buy (27)" resets every score to 8. Every unpicked option in all of these
# groups is pressed for real as well, so no page passes vacuously.
func _creator_expect(c: BaseButton) -> String:
	# #82: the outline bar's lit step is the page already showing.
	if c.get_parent() == _cre._steps and c.theme_type_variation == &"Picked":
		return "inert: the step bar's lit step is the page already showing"
	# The class step carries the climb now, so it inherits the level-up page's one
	# excuse verbatim — same widget, same reason, and found the same way. See
	# _levelup_expect below for why the marking is what identifies it.
	if c.has_meta("level") and c.has_theme_stylebox_override("normal"):
		return "inert: the climb's open rung — the panel beside it already reads this level"
	if not c.text.begins_with("● "):
		return ""
	var group: String = _creator_group(c)
	if group in ["Species", "Class", "Background"]:
		return "inert: re-picking what the build already is; the setter returns early"
	if group == "Armor" and c.text.begins_with("● None"):
		# "● None" is _set_armor("") with nothing to take off: it erases no armor
		# and appends none. Its neighbours are not idempotent and are not excused —
		# re-pressing the armor you wear takes it off and puts it back on the end of
		# the list, which the "Equipped: ..." line under the rack shows, and the
		# shield is a _toggle_equip that has to come off on the second press.
		return "inert: no armor is worn, so there is none to take off"
	return ""

# Which _head() the control sits under. The creator lays each step out as a flat run
# of heads, notes and option flows in _body, so the nearest heading above a control
# names its group.
const CREATOR_GROUPS := ["Name", "Species", "Load a preset", "Class", "Ability scores",
	"Background", "Choices", "Weapons", "Armor"]

func _creator_group(c: BaseButton) -> String:
	var block: Node = c
	while block != null and block.get_parent() != _cre._body:
		block = block.get_parent()
	if block == null:
		return ""
	var kids: Array = _cre._body.get_children()
	for i in range(kids.find(block), -1, -1):
		if not (kids[i] is Label):
			continue
		for g in CREATOR_GROUPS:
			if String(kids[i].text).begins_with(g):
				return g
	return ""

func _creator() -> void:
	await sweep("creator/basics", func(): return _creator_at(0, "", "", "", "array"),
		_creator_model, _creator_expect)
	# ...and again with a species already picked: that is what renders the lineage
	# widget and the "● Elf" case.
	await sweep("creator/basics+species", func(): return _creator_at(0, "elf", "", "", "array"),
		_creator_model, _creator_expect)
	await sweep("creator/class", func(): return _creator_at(1, "elf", "", "", "array"),
		_creator_model, _creator_expect)
	# ...and again with a class already picked, which is the only thing that renders
	# the climb: the sweep above stands on a step with no class chosen, so its twenty
	# rungs and its four path branches were never driven at all.
	await sweep("creator/class+picked", func(): return _creator_at(1, "elf", "rogue", "", "array"),
		_creator_model, _creator_expect)
	# Both ability modes. The bug this whole file exists for lived on exactly this
	# page, in exactly the mode nobody drove — and a second one was still sitting
	# here when the sweep was written: e3cc910 wedged _apply_quick_build()'s
	# definition into the middle of _build_abilities(), so everything after it (the
	# mode note and the whole 6-ability grid) became part of the new function. The
	# step rendered its three mode buttons and nothing else in either mode: no array
	# selectors, no point-buy steppers, and Point Buy was a mode you could enter and
	# then never change a score in. A page with no widgets has no presses to fail,
	# which is why these two carry a floor: 3 mode buttons + 6 OptionButtons on the
	# array page, 3 + 6×(− and +) on point buy.
	await sweep("creator/abilities-array",
		func(): return _creator_at(2, "elf", "wizard", "", "array"),
		_creator_model, _creator_expect, 9)
	await sweep("creator/abilities-pointbuy",
		func(): return _creator_at(2, "elf", "wizard", "", "pointbuy"),
		_creator_model, _creator_expect, 15)
	await sweep("creator/choices", func(): return _creator_at(3, "elf", "wizard", "", "array"),
		_creator_model, _creator_expect)
	await sweep("creator/choices+background",
		func(): return _creator_at(3, "elf", "wizard", "sage", "array"),
		_creator_model, _creator_expect)
	# Two equipment pages, because an elf wizard is proficient with exactly one
	# weapon and no armor at all — a page with nothing on it proves nothing. A
	# cleric brings the whole rack: simple weapons, light and medium armor, a
	# shield. Once with an empty kit (every armor button is a fresh pick) and once
	# already dressed, which is the only way "None" and the shield's un-equip
	# direction are reachable.
	await sweep("creator/equipment-wizard",
		func(): return _creator_at(4, "elf", "wizard", "sage", "array"),
		_creator_model, _creator_expect)
	await sweep("creator/equipment-cleric",
		func(): return _creator_at(4, "elf", "cleric", "sage", "array"),
		_creator_model, _creator_expect)
	await sweep("creator/equipment-cleric-dressed",
		func(): return _creator_at(4, "elf", "cleric", "sage", "array",
			["chain-shirt", "shield", "mace"]),
		_creator_model, _creator_expect)
	await sweep("creator/review",
		func(): return _creator_at(5, "elf", "wizard", "sage", "array"),
		_creator_model, _creator_expect)

# =========================================================================
# 2. the level-up overlay — before and after Confirm
# =========================================================================

var _lvl: Control = null
var _lvl_finished := ""

# Cancel and Close do not touch the build — they emit `finished`, and the profile
# screen that opened the overlay is what acts on it. Standing the overlay up alone
# would make them unobservable (and so unpressable), so the sweep listens the way
# the profile does and folds what it heard into the fingerprint.
func _levelup_at(committed: bool) -> Control:
	_lvl = fresh("res://scenes/creator/levelup.tscn")
	var ch = Presets.vera()
	ch.id = ""                     # keep Save.save() out of it: Confirm is a model
	                               # action here, not a save test
	_lvl_finished = ""
	_lvl.finished.connect(func(leveled: bool): _lvl_finished = "finished(%s)" % leveled)
	_lvl.set_character(ch)
	if committed:
		_lvl.commit()
	return _lvl

func _levelup_preview() -> Control:
	return _levelup_at(false)

func _levelup_committed() -> Control:
	return _levelup_at(true)

func _levelup_model() -> String:
	return "%d|%s|%s|%s|%s" % [_lvl._ch.level(), _lvl._committed, _lvl._ch.choices,
		_lvl._status.text, _lvl_finished]

# Nothing on this screen is excused except one rung of the climb. Its "● " options
# are all choice widgets, where a second press un-picks, and Cancel/Confirm/Done are
# all observable now that the overlay has a listener.
#
# The climb (scenes/creator/climb_view.gd) hangs twenty label-only buttons under the
# card, one per level, and a rung press moves the right-hand panel to that level.
# Nineteen of them rewrite that panel and are pressed for real; the twentieth is the
# rung the page opened at — levelup.gd opens the climb on the level being taken — so
# its panel already reads that level and re-picking it is the same no-op as the
# creator's lit step above. climb_view marks the open rung, and only the open rung,
# with a "normal" stylebox (_mark_selected clears every other), which is how we find
# it: the sweep does not fingerprint theme overrides, so were that marking to move
# elsewhere this excuse would go with it and the rung would fail again rather than
# pass quietly.
func _levelup_expect(c: BaseButton) -> String:
	if c.has_meta("level") and c.has_theme_stylebox_override("normal"):
		return "inert: the climb's open rung — the panel beside it already reads this level"
	return ""

func _levelup() -> void:
	await sweep("levelup/preview", _levelup_preview, _levelup_model, _levelup_expect)
	await sweep("levelup/committed", _levelup_committed, _levelup_model, _levelup_expect)

# =========================================================================
# 3. the character profile
# =========================================================================

var _prof: Control = null

func _profile_at(which: String) -> Control:
	_prof = fresh("res://scenes/profile/profile.tscn")
	var ch
	match which:
		"pike": ch = Presets.pike()
		"ilsa": ch = Presets.ilsa()
		_: ch = Presets.vera()
	var pty = Party.new()
	pty.add_member(ch)
	# Six points of damage, so all five of the HP row's buttons (−5 −1 +1 +5 full)
	# have something to do. At full HP three of them are correctly inert, which
	# would prove nothing.
	ch.hp_current = maxi(1, ch.sheet().max_hp - 6)
	pty.stash_add("shortsword")                       # something to equip
	pty.stash_add("cloak-of-elvenkind", 1, false)     # a mystery, and the scroll
	pty.stash_add(Party.IDENTIFY_SCROLL)              # that reads it (T13)
	_prof.set_party(pty)
	_prof.set_character(ch)
	return _prof

# No hp_current and no pools here, deliberately. Both are rendered on the screen as
# "cur/max" already, and both are stored lazily — a clamped no-op write ("+" on a
# full pool) materialises the key with the value it already had, which moves the
# model string without moving anything a player could see. Counting that as a change
# is how a dead stepper would slip through.
func _profile_model() -> String:
	var ch = _prof.character()
	return "%s|%s|%s|%d" % [ch.equipped, ch.offhand, _prof.party().stash, ch.level()]

# A stepper at the end of its range: the row it sits in reads "cur/max", so "+" on
# a full pool and "−" on an empty one genuinely have nothing to do. That is the pool
# being full, not a dead button — and the other direction of the same pair is always
# pressed for real.
func _profile_expect(c: BaseButton) -> String:
	if c.text != "+" and c.text != "−":
		return ""
	var h: Node = c.get_parent()
	if h == null or h.get_child_count() < 2 or not (h.get_child(1) is Label):
		return ""
	var parts: PackedStringArray = String(h.get_child(1).text).split("/")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ""
	if c.text == "+" and int(parts[0]) >= int(parts[1]):
		return "inert: the pool is already full"
	if c.text == "−" and int(parts[0]) <= 0:
		return "inert: the pool is already empty"
	return ""

func _profile() -> void:
	# Three builds, because which panels exist is build-dependent: Vera has fighting
	# styles and Second Wind, Pike a light weapon (the off-hand button), Ilsa spell
	# slots and a spell-save-DC row.
	for who in ["vera", "pike", "ilsa"]:
		await sweep("profile/" + who, func(): return _profile_at(who),
			_profile_model, _profile_expect)

# =========================================================================
# 4. the settings overlay
# =========================================================================

var _set: Control = null

# There used to be a second page here: Settings -> Art credits, the attribution
# screen the CC-BY-SA pixel art obliged us to ship. The art tier had been off
# since the 3D figures landed, so the art, the screen and this page all went
# together rather than leaving a credits list for art that is no longer in the
# build.
func _settings_plain() -> Control:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Settings._current = null
	_set = fresh("res://scenes/settings/settings.tscn")
	return _set

func _settings_model() -> String:
	var s = _set._s
	return "%.1f|%s|%.1f|%.1f|%s|%s|%s" % [s.anim_speed_multiplier, s.default_difficulty,
		s.sfx_volume, s.music_volume, s.reaction_prompts, s.achievement_popups,
		_set._note.text]

func _settings_expect(c: BaseButton) -> String:
	return "gone: closes the overlay" if c.text == "Close" else ""

func _settings() -> void:
	await sweep("settings", _settings_plain, _settings_model, _settings_expect)

# =========================================================================
# 5. the read-only viewers (achievements, progression)
# =========================================================================

func _viewer_expect(_c: BaseButton) -> String:
	return "gone: read-only screens; Close is the only control they have"

func _viewers() -> void:
	for path in ["res://scenes/achievements/achievements.tscn",
			"res://scenes/progression/progression.tscn"]:
		var label: String = path.get_file().get_basename()
		await sweep("viewer/" + label, func(): return fresh(path), Callable(),
			_viewer_expect)

# =========================================================================
# 6. the campaign screen — one page per node kind, one per merchant tab
# =========================================================================

var _camp: Control = null
var _camp_kind := ""
var _camp_tab := -1
var _camp_fallen := false
var _camp_armed := false
var _camp_retired := false
var _camp_seed := SEED
var _camp_node := ""

func _camp_party():
	var pty = Party.new()
	for ch in Party.demo_roster():
		pty.add_member(ch)
	pty.add_gold(900)                                # the healer, the librarian and
	                                                 # most of a smith's stock
	pty.stash_add("longsword")                       # something to sell
	pty.stash_add("cloak-of-elvenkind", 1, false)    # something to identify
	if _camp_fallen:
		pty.roster[0].dead = true
		pty.stash_add(Campaign.SCROLL)               # ...and a way to raise them
	# A job ready to hand in and one already filed, both straight out of Quest.CURATED.
	# Without
	# the first the innkeeper never draws its "Turn in" button, and without the second
	# the quest log never draws its History toggle — two buttons that only exist once a
	# run has some history behind it, which a freshly-built run has not.
	var ready: Dictionary = Quest.CURATED[1].duplicate(true)
	ready["state"] = "active"
	ready["progress"] = int(ready["required"])
	var done: Dictionary = Quest.CURATED[0].duplicate(true)
	done["state"] = "turned_in"
	done["progress"] = int(done["required"])
	pty.quests.append(ready)
	pty.quests.append(done)
	return pty

# A seeded run parked on the first node of _camp_kind its route offers ("" leaves it
# between nodes, on the pick list). Injected before the scene enters the tree:
# campaign.gd's _ready() only leaves the demo run and the "a run is saved" overlay
# alone when it was handed something.
func _campaign_at() -> Control:
	CampaignSave.clear()
	var pty = _camp_party()
	var run = Campaign.new(pty, _camp_seed)
	_camp = fresh("res://scenes/campaign/campaign.tscn", func(s):
		s.party = pty
		s.run = run)
	if _camp_node != "":
		# One settlement in the pool carries the Healer and the Librarian, and no
		# seed is guaranteed to deal it. Deal it by hand — into the route, then in
		# through enter(), so the run does its own bookkeeping rather than having
		# `node` poked behind its back.
		for n in Campaign.POOL:
			if String(n["id"]) == _camp_node:
				var late: int = maxi(0, run.route.size() - 2)
				run.route[late] = [n]
				run.stage = late
				run.enter(0)
				break
		check(String(run.node.get("id", "")) == _camp_node,
			"campaign: '%s' is still in the node pool" % _camp_node)
	elif _camp_kind != "":
		for stage in run.route.size():
			var opts: Array = run.route[stage]
			var hit := -1
			for i in opts.size():
				if String(opts[i]["kind"]) == _camp_kind:
					hit = i
					break
			if hit >= 0:
				run.stage = stage
				run.enter(hit)
				break
	if _camp_retired:
		run.retire()
	_camp._retire_armed = _camp_armed
	_camp._show_history = false
	_camp._refresh()
	if _camp_tab >= 0:
		var tabs: TabContainer = _find_tabs(_camp)
		if tabs != null and _camp_tab < tabs.get_tab_count():
			tabs.current_tab = _camp_tab
	return _camp

func _find_tabs(n: Node) -> TabContainer:
	for c in n.get_children():
		if c is TabContainer:
			return c
		var hit: TabContainer = _find_tabs(c)
		if hit != null:
			return hit
	return null

func _campaign_model() -> String:
	var r = _camp.run
	return "%s|%d|%s|%d|%d|%s|%d|%d|%s|%s|%s|%s|%s" % [r.state, r.stage,
		r.node.get("id", ""), _camp.party.gold, r.log.size(), _camp.party.stash,
		r.short_rests_used, r.long_rests_used, _camp.party.quests, r.identify_failed,
		r.opportunity_taken, _camp._retire_armed, _camp._show_history]

func _campaign_expect(c: BaseButton) -> String:
	if c.text == "Party":
		# Instantiates scenes/party/party.tscn, which this file deliberately stays
		# out of (see the header). drive_game.gd covers that handoff.
		return "skip: opens the party screen, out of scope here"
	return ""

func _campaign_page(kind: String, tab: int, fallen: bool, armed: bool, retired: bool,
		seed_value := SEED, node_id := "") -> void:
	_camp_kind = kind
	_camp_tab = tab
	_camp_fallen = fallen
	_camp_armed = armed
	_camp_retired = retired
	_camp_seed = seed_value
	_camp_node = node_id

# Every tab of one settlement, each its own page: the other tabs are hidden, so
# their buttons are unreachable until the tab is the current one.
func _sweep_merchant_tabs(label: String, seed_value: int, node_id := "") -> void:
	_campaign_page("merchant", -1, false, false, false, seed_value, node_id)
	_campaign_at()
	check(String(_camp.run.node.get("kind", "")) == "merchant",
		"campaign: the '%s' page lands on a merchant node" % label)
	var tabs: TabContainer = _find_tabs(_camp)
	var count: int = tabs.get_tab_count() if tabs != null else 0
	check(count > 0, "campaign: the %s renders its service tabs" % label)
	for t in count:
		_campaign_page("merchant", t, false, false, false, seed_value, node_id)
		await sweep("campaign/%s-tab%d" % [label, t], _campaign_at, _campaign_model,
			_campaign_expect)

func _campaign() -> void:
	# Between nodes: the road's cards, plus T17's two-press Retire...
	_campaign_page("", -1, false, false, false)
	await sweep("campaign/picking", _campaign_at, _campaign_model, _campaign_expect)
	# ...and its armed half, a different button on the same card, reachable only
	# after one press.
	_campaign_page("", -1, false, true, false)
	await sweep("campaign/picking-armed", _campaign_at, _campaign_model, _campaign_expect)

	# Standing on a node: one page per kind the route deals out.
	for kind in ["rest", "treasure"]:
		_campaign_page(kind, -1, false, false, false)
		_campaign_at()
		check(String(_camp.run.node.get("kind", "")) == kind,
			"campaign: seed %d puts a '%s' node on the route" % [SEED, kind])
		await sweep("campaign/" + kind, _campaign_at, _campaign_model, _campaign_expect)

	# Settlements: a village (Generalist + Innkeeper) and a town, which is the only
	# size that carries specialists — the Healer, Librarian and smith tabs live
	# nowhere else.
	await _sweep_merchant_tabs("village", SEED)
	await _sweep_merchant_tabs("town", TOWN_SEED)
	# ...and the one settlement in the pool that staffs a Healer and a Librarian —
	# the two service pages with their own model calls (heal_party, identify_for_fee)
	# and nothing else in the game that reaches them.
	await _sweep_merchant_tabs("caravanserai", SEED, "caravanserai")

	# The fallen panel, and the end-of-run panel behind Retire.
	_campaign_page("", -1, true, false, false)
	await sweep("campaign/fallen", _campaign_at, _campaign_model, _campaign_expect)
	_campaign_page("", -1, false, false, true)
	await sweep("campaign/ended", _campaign_at, _campaign_model, _campaign_expect)
	_campaign_page("", -1, false, false, false, SEED)

# =========================================================================
# 7. the title screen
# =========================================================================

var _game: Control = null
var _title_saved := false

func _title_at() -> Control:
	CampaignSave.clear()
	WorldSave.clear()
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "1" if _title_saved else "")
	if _title_saved:
		var pty = Party.new()
		for ch in Party.demo_roster():
			pty.add_member(ch)
		CampaignSave.save(Campaign.new(pty, SEED))
	_game = fresh("res://scenes/game/game.tscn")
	_game.campaign = null
	_game.show_title()
	return _game

func _title_model() -> String:
	return "%s|%s" % [_game._screen, _game.campaign != null]

func _title_expect(c: BaseButton) -> String:
	if "Quit" in c.text:
		return "skip: get_tree().quit() would take the test process with it"
	if "New run" in c.text:
		# Opens scenes/party/party.tscn — same reason as the campaign screen's Party
		# button. drive_game.gd walks this door for real.
		return "skip: opens the party screen, out of scope here"
	return ""

func _title() -> void:
	_title_saved = false
	await sweep("title", _title_at, _title_model, _title_expect)
	# With an autosave and the linear flag on, the front door grows a Resume.
	_title_saved = true
	await sweep("title/resumable", _title_at, _title_model, _title_expect)
	_title_saved = false
	OS.set_environment("SORCMERC_LINEAR_CAMPAIGN", "")
