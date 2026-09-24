# Level-up: the loop from core/leveling.gd driven with the creator's choice model,
# no UI. Same shape as tests/test_creator.gd.
#   godot --headless --path . -s tests/test_leveling.gd
extends SceneTree

const Leveling = preload("res://core/leveling.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Progression = preload("res://core/progression.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# What the level-up screen's buttons do: N picks off the option list.
func autopick(p: Dictionary, sheet) -> Array:
	var opts := Creator.options_for(p, sheet)
	if opts.is_empty():
		return []
	var picks: Array = []
	var i := 0
	while picks.size() < Creator.pick_count(p) and i < opts.size() * 3:
		picks = Creator.toggle(p, picks, opts[i % opts.size()]["id"])
		i += 1
	return picks

func resolve_all(ch, label: String) -> void:
	for _step in 40:
		var p: Array = Leveling.pending(ch)
		if p.is_empty():
			return
		var picks := autopick(p[0], ch.sheet())
		check(not picks.is_empty(), "%s: %s offers options" % [label, p[0]["type"]])
		if picks.is_empty():
			return
		Leveling.decide(ch, p[0]["key"], Creator.decision_for(p[0], picks))
	check(false, "%s: converged within 40 steps" % label)

func fresh(cls: String, background: String):
	var ch = Creator.new_character()
	ch.cname = "Test " + cls
	ch.species_id = "human"
	ch.background_id = background
	ch.base_abilities = Creator.recommended_array(cls)
	ch.add_level(cls, -1)
	resolve_all(ch, cls + " L1")
	return ch

func _init() -> void:
	_climb("fighter", "soldier")
	_climb("wizard", "sage")
	_presets()
	_preview()
	_screen()
	_expertise_shows_its_picks()
	_earlier_levels_are_locked()
	_from_profile()
	_xp_gate()
	_catch_up()
	_finish()   # the creator screen needs a frame before its _ready has run

func _finish() -> void:
	await process_frame
	await _catch_up_in_creator()
	print("test_leveling: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# L1 -> L5: HP grows every level, level 3 asks for a subclass, level 4 for an
# ASI-or-feat, and the picked subclass's features land on the sheet.
func _climb(cls: String, background: String) -> void:
	var ch = fresh(cls, background)
	check(Leveling.can_finalize(ch), "%s L1 has no leftover choices" % cls)
	var die := int(Catalog.class_src(cls)["hitDie"])
	for target in range(2, 6):
		var before = ch.sheet()
		var preview := Leveling.preview(ch)
		Leveling.add_level(ch)
		check(ch.level() == target, "%s reaches level %d" % [cls, target])
		var pend_types: Array = []
		for p in Leveling.pending(ch):
			pend_types.append(p["type"])
		if target == 3:
			check("subclass" in pend_types, "%s level 3 asks for a subclass" % cls)
		if target == 4:
			check("asi" in pend_types and "feat-choice" in pend_types,
				"%s level 4 offers ASI or feat" % cls)
			check(Creator.pick_count(_of_type(ch, "asi")) == 2, "class ASI is 2 points")
		resolve_all(ch, "%s L%d" % [cls, target])
		check(Leveling.can_finalize(ch), "%s L%d resolves every choice" % [cls, target])
		var after = ch.sheet()
		var min_gain: int = die / 2 + 1 + after.mod("con")
		check(after.max_hp >= before.max_hp + min_gain,
			"%s L%d HP %d -> %d (>= +%d)" % [cls, target, before.max_hp, after.max_hp, min_gain])
		check(after.features.size() >= before.features.size(),
			"%s L%d never loses a feature" % [cls, target])
		var gains := Leveling.gains(before, after)
		check(int(gains["hp"]) == after.max_hp - before.max_hp, "%s L%d gains report HP" % [cls, target])
		check(int(preview["hp"]) > 0, "%s L%d preview promised HP" % [cls, target])
		if target == 3:
			check(after.subclasses.has(cls), "%s picked a subclass" % cls)
			check(gains["subclass"] == after.subclasses[cls], "gains name the new subclass")
			# a subclass grants at least one feature at the level it is taken
			check(not gains["features"].is_empty(), "%s subclass brings features" % cls)
		if target == 5:
			check(after.proficiency_bonus == 3, "%s PB is +3 at level 5" % cls)
	var final = ch.sheet()
	if cls == "wizard":
		check(int(final.spellcasting["slots"][2]) > 0, "wizard 5 has level-3 slots")
	if cls == "fighter":
		check(final.attacks.size() > 0, "fighter still has attacks")

func _of_type(ch, t: String) -> Dictionary:
	for p in Leveling.pending(ch):
		if p["type"] == t:
			return p
	return {}

# The presets are level 3; +1 must not disturb anything they already had.
func _presets() -> void:
	for ch in Presets.party():
		var who: String = ch.id
		var before = ch.sheet()
		var kept := {"ac": before.ac, "skills": before.skills.duplicate(),
			"saves": before.saves.duplicate(), "level": before.level}
		Leveling.add_level(ch)
		resolve_all(ch, who)
		var after = ch.sheet()
		check(after.level == int(kept["level"]) + 1, "%s levels to %d" % [who, after.level])
		check(after.max_hp > before.max_hp, "%s gains HP" % who)
		check(after.ac == int(kept["ac"]), "%s AC unchanged" % who)
		for id in kept["skills"]:
			check(int(after.skills[id]) >= int(kept["skills"][id]), "%s skill %s not lost" % [who, id])
		for a in kept["saves"]:
			check(int(after.saves[a]) >= int(kept["saves"][a]), "%s save %s not lost" % [who, a])
		for f in before.features:
			check(after.features.has(f), "%s keeps feature %s" % [who, f])
		for e in before.equipment:
			check(after.equipment.size() >= before.equipment.size(), "%s keeps equipment" % who)

# The overlay: preview -> commit -> answer pending through its own buttons -> Done.
func _screen() -> void:
	var ch = Presets.vera()
	var before: int = ch.sheet().max_hp
	var scr = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(scr)
	scr.set_character(ch)
	check(ch.level() == 3, "screen does not level on open")
	scr.commit()
	check(ch.level() == 4, "commit adds the level")
	check(ch.sheet().max_hp > before, "committing raises max HP")
	var seen := 0
	for _step in 40:
		var pend: Array = Leveling.pending(ch)
		if pend.is_empty():
			break
		seen += 1
		for id in autopick(pend[0], ch.sheet()):
			scr._pick(pend[0], id)
	check(seen > 0, "Vera's level 4 raised at least one choice")
	check(Leveling.can_finalize(ch), "the screen's own buttons resolve them")
	var done := [false]
	scr.finished.connect(func(leveled): done[0] = leveled)
	scr._on_confirm()
	check(done[0], "Done reports the level was taken")
	scr.queue_free()

# Issue #119: a decided expertise choice has to be able to show what it chose.
# pass_profs grades a picked skill "expert", not "prof", and the row's pool was
# filtered on "prof" alone — so the two skills the choice had taken were the two
# the row could not draw. "✓ Expertise — pick 2 (2 chosen)" over nine buttons,
# none of them marked, and pressing any of them evicted an invisible pick.
func _expertise_shows_its_picks() -> void:
	var ch = fresh("rogue", "criminal")
	var pt := {}
	for p in ch.sheet().choice_points:
		if p["type"] == "expertise-choice":
			pt = p
	check(not pt.is_empty(), "a level-1 rogue has an expertise choice")
	if pt.is_empty():
		return
	var picks := Creator.picks_from_decision(pt, ch.choices.get(pt["key"]))
	check(pt.get("decided", false) and picks.size() == 2,
		"...and it is answered (%s)" % str(picks))
	check(ch.sheet().skill_prof.get(picks[0], "") in ["expert", "prof"],
		"the pick landed on the sheet (%s is %s)" % [picks[0], ch.sheet().skill_prof.get(picks[0], "")])
	var ids: Array = Creator.options_for(pt, ch.sheet(), picks).map(func(o): return o["id"])
	for s in picks:
		check(s in ids, "the row offers its own pick %s back to be unpicked (%s)" % [s, str(ids)])
	# ...and only its own. A skill some OTHER expertise grant spent is not on
	# offer here, or a second grant would buy what the first already owns.
	var fresh_ids: Array = Creator.options_for(pt, ch.sheet(), []).map(func(o): return o["id"])
	for s in picks:
		if ch.sheet().skill_prof.get(s, "") == "expert":
			check(not s in fresh_ids, "a choice that did not pick %s is not offered it" % s)

# Issue #120: the level-up screen is where THIS level's choices get made. The
# feat taken at 4 and the background's skills taken at 1 are drawn, with what
# they took still marked, and they are not up for trade. Spell choices are the
# exception — 5e lets one move at level-up, and this game's casters do their
# real picking on the prepare page.
func _earlier_levels_are_locked() -> void:
	var ch = fresh("rogue", "criminal")
	for _i in 4:
		Leveling.add_level(ch)
		resolve_all(ch, "rogue climb")
	var settled: Array = ch.sheet().choice_points.filter(func(p): return p.get("decided", false))
	check(not settled.is_empty(), "the rogue reaches level 5 with choices behind them")
	var scr = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(scr)
	scr.set_character(ch)
	var locked_pt := {}
	for p in settled:
		if p["type"] in scr.LIVE_TYPES:
			check(not scr._locked.has(p["key"]), "a spell choice stays open (%s)" % p["key"])
		else:
			check(scr._locked.has(p["key"]), "%s from an earlier level is locked" % p["type"])
			locked_pt = p
	check(not locked_pt.is_empty(), "at least one of them is locked")
	if locked_pt.is_empty():
		scr.queue_free()
		return

	# The lock is the model's, not the button's: _pick is what a press calls.
	var was := str(Creator.picks_from_decision(locked_pt, ch.choices.get(locked_pt["key"])))
	var opts := Creator.options_for(locked_pt, ch.sheet(),
		Creator.picks_from_decision(locked_pt, ch.choices.get(locked_pt["key"])))
	check(not opts.is_empty(), "the locked choice still draws its options")
	for o in opts:
		scr._pick(locked_pt, o["id"])
	check(str(Creator.picks_from_decision(locked_pt, ch.choices.get(locked_pt["key"]))) == was,
		"pressing every option on it changes nothing (%s)" % was)

	# On screen: a locked choice has no buttons at all — it is one dim line
	# under "Chosen at earlier levels" that names what was taken, so the page
	# reads as a record without offering a press. _render() removes the old
	# rows outright rather than at end of frame, so what is read below is this
	# call's, not the last one's.
	scr.commit()
	var live := 0
	for b in _buttons_of(scr._body):
		if String(b.get_meta("choice_key", "")) == locked_pt["key"]:
			live += 1
	check(live == 0, "not one button belongs to it (%d)" % live)
	var record := ""
	for l in _labels_of(scr._body):
		if String(l.get_meta("choice_key", "")) == locked_pt["key"]:
			record = l.text
	var picks := Creator.picks_from_decision(locked_pt, ch.choices.get(locked_pt["key"]))
	check(record != "" and (picks.is_empty() or record.to_lower().contains(
		Creator.humanize(String(picks[0])).to_lower().substr(0, 3))),
		"and the line says what it chose (%s)" % record)

	# This level's own choices, raised by the commit above, are open as ever.
	for p in Leveling.pending(ch):
		check(not scr._locked.has(p["key"]), "this level's own %s is open" % p["type"])
	scr.queue_free()

func _labels_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels_of(c))
	return out

func _buttons_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons_of(c))
	return out

# The profile's button opens the overlay and the profile re-renders on close.
func _from_profile() -> void:
	var ch = Presets.pike()
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_character(ch)
	p.level_up()
	var scr = null
	for c in p.get_children():
		if c.has_method("commit"):
			scr = c
	check(scr != null, "profile opens the level-up overlay")
	if scr == null:
		return
	scr.commit()
	resolve_all(ch, "pike via profile")
	scr._on_confirm()
	check(p.field("classes").contains("4"), "profile re-renders at the new level (got %s)"
		% p.field("classes"))
	check(p.field("hp") == "%d/%d" % [ch.sheet().max_hp, ch.sheet().max_hp],
		"profile shows the new max HP")
	p.queue_free()

# preview() must not mutate the character it previews.
func _preview() -> void:
	var vera = Presets.vera()
	var before_level := vera.level()
	var before_hp: int = vera.sheet().max_hp
	var p := Leveling.preview(vera)
	check(vera.level() == before_level, "preview leaves the level alone")
	check(vera.sheet().max_hp == before_hp, "preview leaves the sheet alone")
	check(int(p["level"]) == before_level + 1, "preview reports the target level")
	check(int(p["hp"]) > 0, "preview reports an HP gain")

# T10: the XP curve gates level-up, and the profile button follows it.
func _xp_gate() -> void:
	var ch = Presets.vera()          # level 3
	ch.xp = 0
	check(not Leveling.can_level_up(ch), "L3 with 0 XP cannot level")
	check(Leveling.xp_to_next(ch) == 600, "L3 needs 600 XP for level 4")
	ch.xp = 599
	check(not Leveling.can_level_up(ch) and Leveling.xp_to_next(ch) == 1, "one XP short")
	ch.xp = 600
	check(Leveling.can_level_up(ch), "hitting the threshold unlocks level-up")
	check(Leveling.xp_to_next(ch) == 0, "eligible characters need 0 more")
	check(Leveling.xp_for_level(1) == 0 and Leveling.xp_for_level(20) == 19000,
		"the table spans 1..20")

	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	ch.xp = 100
	p.set_character(ch)
	check(p._fields["level_up_btn"].disabled, "the profile disables Level up below the threshold")
	check(p.field("xp").contains("need 500 more"), "the profile says how much XP is missing (got %s)"
		% p.field("xp"))
	ch.xp = 9999
	p.set_character(ch)
	check(not p._fields["level_up_btn"].disabled, "enough XP enables the button")
	p.queue_free()

# A hero created once the party is already several levels in starts at the party's
# level. Those catch-up levels are granted, not earned: they bank exactly the XP
# the level costs and leave the account-wide lifetime XP — the currency that
# unlocks species and classes — where it was.
func _catch_up() -> void:
	var lifetime_before: int = Progression.lifetime_xp_total()
	var wizard_xp_before: int = Progression.class_xp_of("wizard")
	var ch = fresh("wizard", "sage")
	Leveling.grant_levels(ch, 5)
	check(ch.level() == 5, "grant_levels climbs to the target (got %d)" % ch.level())
	check(ch.class_level("wizard") == 5, "every catch-up level is in the same class")
	check(int(ch.xp) == Leveling.xp_for_level(5), "banks exactly level 5's XP (got %d)" % ch.xp)
	check(not Leveling.can_level_up(ch), "and not one XP more")
	check(not Leveling.pending(ch).is_empty(), "the granted levels still ask for their choices")
	resolve_all(ch, "wizard catch-up")
	var sheet = ch.sheet()
	check(sheet.level == 5 and sheet.proficiency_bonus == 3, "the sheet resolves at level 5")
	check(sheet.subclasses.has("wizard"), "the level-3 subclass was among the choices")
	check(Progression.lifetime_xp_total() == lifetime_before,
		"catch-up levels never touch lifetime XP")
	check(Progression.class_xp_of("wizard") == wizard_xp_before,
		"nor the class XP that buys subclasses")

	Leveling.grant_levels(ch, 2)
	check(ch.level() == 5, "a lower target never takes levels away")
	Leveling.grant_levels(ch, 999)
	check(ch.level() == Leveling.MAX_LEVEL, "the target is clamped at level 20")
	var nobody = Creator.new_character()
	Leveling.grant_levels(nobody, 5)
	check(nobody.level() == 0, "no class picked yet: nothing to grant")

# The same thing through the creator screen: start_level is injected, the class
# button builds the whole climb, and Confirm stays blocked until every choice
# those levels raised has been made.
func _catch_up_in_creator() -> void:
	var scr = load("res://scenes/creator/creator.tscn").instantiate()
	scr.set_start_level(5)           # what scenes/party/party.gd hands in
	root.add_child(scr)
	await process_frame
	scr.ch.cname = "Catchup Cleric"
	scr.ch.species_id = "human"
	scr.ch.background_id = "acolyte"
	scr.ch.base_abilities = Creator.recommended_array("cleric")
	scr._set_class("cleric")
	check(scr.ch.level() == 5, "the creator builds the class out to level 5 (got %d)"
		% scr.ch.level())
	check(int(scr.ch.xp) == Leveling.xp_for_level(5), "with level 5's XP banked")
	check(not Leveling.can_finalize(scr.ch), "level 5's choices are pending")
	for _step in 60:
		var pend: Array = Leveling.pending(scr.ch)
		if pend.is_empty():
			break
		for id in autopick(pend[0], scr.ch.sheet()):
			scr._pick(pend[0], id)   # what an option button does
	check(Leveling.can_finalize(scr.ch), "the creator's own buttons answer them")
	check(scr.ch.sheet().level == 5, "and the finished hero is level 5")
	scr.set_start_level(1)
	check(scr.ch.level() == 1 and int(scr.ch.xp) == 0,
		"re-injecting a level-1 party rebuilds the climb")

	# The presets are level-3 builds handed straight to Review — they are topped
	# up to the party's level rather than rebuilt.
	# Ilsa, because the cleric is open from day one and the fighter is not (#200).
	scr.set_start_level(7)
	scr._load_preset("ilsa")
	check(scr.ch.level() == 7, "a preset joins at the party's level too (got %d)"
		% scr.ch.level())
	check(scr.ch.class_level("cleric") == 7, "topped up in its own class")
	check(int(scr.ch.xp) == Leveling.xp_for_level(7), "with level 7's XP banked")
	check(not Leveling.can_finalize(scr.ch), "and the levels above 3 still to choose")

	# A fresh run starts at Leveling.START_LEVEL, presets included: they are
	# level-3 builds cut to 2, the subclass waiting for the level that asks.
	scr.set_start_level(Leveling.START_LEVEL)
	scr._load_preset("ilsa")
	check(scr.ch.level() == 2, "a preset for a fresh run starts at level 2 (got %d)" % scr.ch.level())
	check(Leveling.can_finalize(scr.ch), "...with nothing left to choose")
	check(int(scr.ch.xp) == Leveling.xp_for_level(2), "...and level 2's XP banked")
	check(String(scr.ch.sheet().subclasses.get("cleric", "")) == "", "...and no subclass yet")
	Leveling.add_level(scr.ch)
	check(String(scr.ch.sheet().subclasses.get("cleric", "")) == "lightdomain",
		"at level 3 its own subclass comes in")
	scr.set_start_level(1)
	scr._load_preset("ilsa")
	check(scr.ch.level() == 2, "a standalone creator's preset is never under level 2 either")

	# #200: a preset is gated like the class list beside it. Vera is a Fighter,
	# which a fresh profile has not opened; loading her must not hand it over.
	var Presets = load("res://core/presets.gd")
	check(scr.build_lock_note(Presets.vera()) == scr.lock_note("class", "fighter"),
		"Vera wears the Fighter's lock (%s)" % scr.build_lock_note(Presets.vera()))
	check(scr.build_lock_note(Presets.ilsa()) == "", "Ilsa, a Light Domain cleric, is open from day one")
	if scr.lock_note("class", "fighter") != "":
		var before = scr.ch
		scr._load_preset("vera")
		check(scr.ch == before, "a locked preset does not load (#200)")
	scr.queue_free()
