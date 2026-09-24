# core/metamagic.gd — the one list of Metamagic options the board plays, and
# everything that reads it (the design audit, docs/audit-game-design.md §8.5):
#   1. the list, the verbs in data/effects/features.json and the chip lines in
#      core/active_effects.gd name the same five options, so building a sixth
#      in one place and not the others fails here;
#   2. ChoicePick.unbuilt greys exactly the other five of the class's ten, and
#      nothing on any other class's feature choice;
#   3. the level-up page draws all ten, the five unbuilt disabled with the
#      reason as their tooltip, and a press on one decides nothing;
#   4. a hireling's auto-picks never land on an unbuilt option.
# That combat refuses an unbuilt option word is in tests/test_sorcerer.gd, with
# the fights the built five are tested in.
#   godot --headless --path . -s tests/test_metamagic.gd
extends SceneTree

const Metamagic = preload("res://core/metamagic.gd")
const ActiveEffects = preload("res://core/active_effects.gd")
const ChoicePick = preload("res://core/rules/choice_pick.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Character = preload("res://core/character.gd")
const Leveling = preload("res://core/leveling.gd")
const Recruits = preload("res://core/recruits.gd")
const RNG = preload("res://core/rng.gd")

const UNBUILT := ["distant", "empowered", "extended", "heightened", "transmuted"]

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_one_list()
	test_option_of()
	test_unbuilt_is_greyed()
	await test_levelup_page()
	test_hirelings_skip_the_unbuilt()
	print("test_metamagic: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _sorcerer(n: int) -> Character:
	var ch := Character.new()
	ch.id = "mm"
	ch.cname = "Mm"
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	Leveling.grant_levels(ch, n, "sorcerer")
	return ch

func _metamagic_point(ch) -> Dictionary:
	for p in ch.sheet().choice_points:
		if String(p["key"]) == "feature-choice:class:sorcerer:0":
			return p
	return {}

func test_one_list() -> void:
	check(Metamagic.BUILT.size() == 5, "five options are built (%s)" % str(Metamagic.BUILT))
	var verbs: Array = []
	var feats = Catalog.all("effects/features.json")
	for fid in feats:
		if String(feats[fid].get("kind", "")) == "metamagic":
			verbs.append(String(feats[fid].get("option", "")))
			check(Metamagic.option_of(fid) == String(feats[fid].get("option", "")),
				"%s's option word is its id's (%s)" % [fid, feats[fid].get("option")])
	verbs.sort()
	var built: Array = Metamagic.BUILT.duplicate()
	built.sort()
	check(verbs == built, "features.json has a verb for every built option and no other (%s)" % str(verbs))
	var chips: Array = ActiveEffects.METAMAGIC_TEXT.keys()
	chips.sort()
	check(chips == built, "the chip has a line for every built option and no other (%s)" % str(chips))

func test_option_of() -> void:
	check(Metamagic.option_of("metamagic-quickened-spell") == "quickened", "quickened")
	check(Metamagic.option_of("metamagic-distant-spell") == "distant", "distant")
	check(Metamagic.option_of("sorcerer-font-of-magic") == "", "Font of Magic is not an option")
	check(Metamagic.is_built("metamagic-seeking-spell"), "Seeking is built")
	check(not Metamagic.is_built("metamagic-empowered-spell"), "Empowered is not")
	check(Metamagic.is_built("protector"), "a feature that is not Metamagic is not refused")

func test_unbuilt_is_greyed() -> void:
	var p := _metamagic_point(_sorcerer(2))
	check(not p.is_empty(), "a level-2 sorcerer has the first Metamagic pick")
	if p.is_empty():
		return
	var opts: Array = ChoicePick.options_for(p).map(func(o): return String(o["id"]))
	check(opts.size() == 10, "all ten are still offered, the book's list (%d)" % opts.size())
	var greyed: Dictionary = ChoicePick.unbuilt(p)
	var want: Array = UNBUILT.map(func(o): return "%s-spell" % o)
	var got: Array = greyed.keys()
	got.sort()
	check(got == want, "the five unbuilt are greyed (%s)" % str(got))
	for id in greyed:
		check(String(greyed[id]) == Metamagic.NOT_BUILT, "%s says why" % id)
	for o in Metamagic.BUILT:
		check(("%s-spell" % o) in opts and not greyed.has("%s-spell" % o), "%s is offered and live" % o)
	# Another class's feature choice is none of this file's business.
	var cleric := Character.new()
	cleric.species_id = "human"
	cleric.background_id = "acolyte"
	cleric.base_abilities = {"str": 12, "dex": 10, "con": 14, "int": 8, "wis": 16, "cha": 12}
	Leveling.grant_levels(cleric, 1, "cleric")
	var any := false
	for q in cleric.sheet().choice_points:
		if String(q["type"]) == "feature-choice":
			any = true
			check(ChoicePick.unbuilt(q).is_empty(), "the cleric's %s greys nothing" % q["key"])
	check(any, "the cleric has a feature choice to ask")
	check(ChoicePick.unbuilt({"type": "skill-choice", "from": null}).is_empty(), "nor does a skill choice")

func test_levelup_page() -> void:
	var ch := _sorcerer(1)
	var scr = load("res://scenes/creator/levelup.tscn").instantiate()
	root.add_child(scr)
	scr.set_character(ch)
	scr.commit()   # to level 2: the Metamagic picks open
	await process_frame
	var key := "feature-choice:class:sorcerer:0"
	var mine: Array = _buttons_of(scr._body).filter(func(b): return String(b.get_meta("choice_key", "")) == key)
	check(mine.size() == 10, "the page draws all ten options (%d)" % mine.size())
	var off: Array = mine.filter(func(b): return b.disabled)
	check(off.size() == 5, "five of them are greyed (%d)" % off.size())
	for b in off:
		check(b.tooltip_text == Metamagic.NOT_BUILT, "%s says why: %s" % [b.text, b.tooltip_text])
		check(UNBUILT.any(func(o): return b.text.to_lower().contains(o)), "%s is an unbuilt one" % b.text)
	for b in mine:
		if not b.disabled:
			check(Metamagic.BUILT.any(func(o): return b.text.to_lower().contains(o)), "%s is a built one" % b.text)
	scr.queue_free()

func test_hirelings_skip_the_unbuilt() -> void:
	# Level 17: six picks from ten, five built — the sixth has to repeat one
	# rather than spend itself on something the board ignores.
	for seed_v in range(1, 25):
		var ch := _sorcerer(17)
		Recruits._settle_fixed(ch, RNG.new(seed_v))
		for i in 6:
			var d = ch.choices.get("feature-choice:class:sorcerer:%d" % i)
			check(d != null, "seed %d: pick %d is made" % [seed_v, i])
			if d == null:
				continue
			var fid := "metamagic-%s" % String(d["optionId"])
			check(Metamagic.is_built(fid), "seed %d: pick %d is a built one (%s)" % [seed_v, i, d["optionId"]])

func _buttons_of(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons_of(c))
	return out
