# Level-up: the loop from core/leveling.gd driven with the creator's choice model,
# no UI. Same shape as tests/test_creator.gd.
#   godot --headless --path . -s tests/test_leveling.gd
extends SceneTree

const Leveling = preload("res://core/leveling.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")

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
	_from_profile()
	_xp_gate()
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

# The profile's button opens the overlay and the profile re-renders on close.
func _from_profile() -> void:
	var ch = Presets.pike()
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_character(ch)
	p._level_up()
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

# T10: the 5e XP table gates level-up, and the profile button follows it.
func _xp_gate() -> void:
	var ch = Presets.vera()          # level 3
	ch.xp = 0
	check(not Leveling.can_level_up(ch), "L3 with 0 XP cannot level")
	check(Leveling.xp_to_next(ch) == 2700, "L3 needs 2700 XP for level 4")
	ch.xp = 2699
	check(not Leveling.can_level_up(ch) and Leveling.xp_to_next(ch) == 1, "one XP short")
	ch.xp = 2700
	check(Leveling.can_level_up(ch), "hitting the threshold unlocks level-up")
	check(Leveling.xp_to_next(ch) == 0, "eligible characters need 0 more")
	check(Leveling.xp_for_level(1) == 0 and Leveling.xp_for_level(20) == 355000,
		"the table spans 1..20")

	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	ch.xp = 100
	p.set_character(ch)
	check(p._fields["level_up_btn"].disabled, "the profile disables Level up below the threshold")
	check(p.field("xp").contains("need 2600 more"), "the profile says how much XP is missing (got %s)"
		% p.field("xp"))
	ch.xp = 9999
	p.set_character(ch)
	check(not p._fields["level_up_btn"].disabled, "enough XP enables the button")
	p.queue_free()
