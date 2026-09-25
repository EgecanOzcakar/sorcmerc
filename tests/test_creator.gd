# Drives the character creator's build state end-to-end without any UI: the same
# static choice model scenes/creator/creator.gd's buttons call.
#   godot --headless --path . -s tests/test_creator.gd
extends SceneTree

const Creator = preload("res://scenes/creator/creator.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Save = preload("res://core/character_save.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

# What the UI does when a pending choice's buttons are pressed: N picks off the
# option list, cycling so a repeat-allowed choice (ASI) spreads its points.
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

# The creator's loop: resolve -> render pending -> decide -> re-resolve.
func resolve_all(ch, label: String) -> void:
	for _step in 40:
		var sheet = ch.sheet()
		if sheet.pending.is_empty():
			return
		var p: Dictionary = sheet.pending[0]
		var picks := autopick(p, sheet)
		check(not picks.is_empty(), "%s: %s (%s) offers options" % [label, p["type"], p["key"]])
		if picks.is_empty():
			return
		ch.decide(p["key"], Creator.decision_for(p, picks))
	check(false, "%s: pending choices converged within 40 steps" % label)

func build(name: String, species: String, cls: String, background: String, mode: String):
	var ch = Creator.new_character()
	ch.cname = name
	ch.species_id = species
	ch.add_level(cls, -1)
	ch.background_id = background
	if mode == "pointbuy":
		for a in Creator.ABILS:
			ch.base_abilities[a] = 8
		ch.base_abilities[Catalog.class_src(cls)["primaryAbility"]] = 15
		ch.base_abilities["con"] = 14
	else:
		ch.base_abilities = Creator.recommended_array(cls)
	ch.dirty()
	resolve_all(ch, name)
	# equipment step: first proficient weapon, the best proficient body armor, shield
	var sheet = ch.sheet()
	var weapons := Creator.proficient_weapons(sheet)
	var armors := Creator.proficient_armor(sheet)
	if not weapons.is_empty():
		ch.equipped.append(weapons[0])
	var best := ""
	var best_ac := 0
	for aid in armors:
		var a := Catalog.armor(aid)
		if aid != "shield" and int(a["baseAc"]) > best_ac:
			best_ac = int(a["baseAc"])
			best = aid
	if best != "":
		ch.equipped.append(best)
	if "shield" in armors:
		ch.equipped.append("shield")
	ch.dirty()
	return ch

func assert_sane(ch, label: String) -> void:
	var s = ch.sheet()
	var hit_die := int(Catalog.class_src(ch.class_id())["hitDie"])
	check(s.pending.is_empty(), "%s: no unresolved choices (%d left)" % [label, s.pending.size()])
	check(s.proficiency_bonus == 2, "%s: level-1 proficiency bonus is +2" % label)
	check(s.level == 1, "%s: level 1" % label)
	# 8 = an unarmored caster who dumped DEX; 21 = plate + shield at level 1
	check(s.ac >= 8 and s.ac <= 21, "%s: AC in range (got %d)" % [label, s.ac])
	check(s.max_hp >= hit_die and s.max_hp <= hit_die + 6,
		"%s: HP between d%d and d%d+6 (got %d)" % [label, hit_die, hit_die, s.max_hp])
	# 20 = heavy armour under its Strength floor (#164): Thrun's chain mail at Str 12
	check(int(s.speeds.get("walk", 0)) >= 20, "%s: has a walk speed (got %s)" % [label, s.speeds])
	check(not s.attacks.is_empty(), "%s: has at least one attack" % label)
	for a in s.attacks:
		check(int(a["to_hit"]) >= -1 and int(a["to_hit"]) <= 9, "%s: %s to-hit sane (%d)" % [label, a["name"], int(a["to_hit"])])
	for ab in Creator.ABILS:
		var t := int(s.abilities[ab]["total"])
		check(t >= 3 and t <= 20, "%s: %s total in range (%d)" % [label, ab, t])
	check(int(s.saves.size()) == 6, "%s: six saves" % label)
	for w in s.warnings:
		check(not w.begins_with("BUG:"), "%s: resolver bug warning: %s" % [label, w])
	if s.warnings.size() > 0:
		print("  (%s warnings: %s)" % [label, ", ".join(s.warnings)])

func _init() -> void:
	# point buy: the 2024 costs and the 27-point budget
	check(Creator.point_buy_cost({"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}) == 0, "all-8s costs 0")
	check(Creator.point_buy_cost({"str": 15, "dex": 15, "con": 8, "int": 8, "wis": 8, "cha": 8}) == 18, "two 15s cost 18")
	check(Creator.point_buy_cost({"str": 14, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}) == 7, "a 14 costs 7")
	check(Creator.point_buy_cost({"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}) == 27,
		"the classic 15/14/13/12/10/8 spread costs exactly 27")

	# standard array assignment follows the class quick build
	var rec := Creator.recommended_array("wizard")
	check(rec["int"] == 15, "wizard's quick build puts the 15 in INT")
	check(rec["con"] == 14, "wizard's secondary ability gets the 14")
	var vals: Array = rec.values()
	vals.sort()
	check(vals == [8, 10, 12, 13, 14, 15], "recommendation uses each array value once")

	# toggle: pick, unpick, and the ASI's two-points-in-one-ability cap
	var skill_p := {"type": "skill-choice", "key": "k", "count": 2, "from": ["stealth", "arcana", "insight"]}
	check(Creator.toggle(skill_p, [], "stealth") == ["stealth"], "toggle adds")
	check(Creator.toggle(skill_p, ["stealth"], "stealth") == [], "toggle removes")
	check(Creator.toggle(skill_p, ["stealth", "arcana"], "insight") == ["arcana", "insight"],
		"over-picking evicts the oldest")
	var asi_p := {"type": "asi", "key": "k", "points": 3, "from": ["str", "con", "cha"]}
	check(Creator.pick_count(asi_p) == 3, "an ASI is 3 picks at a background")
	check(Creator.toggle(asi_p, ["str"], "str") == ["str", "str"], "ASI stacks to +2")
	check(Creator.toggle(asi_p, ["str", "str"], "str") == [], "a third press clears the ability")
	check(Creator.decision_for(asi_p, ["str", "str", "con"])["allocation"] == {"str": 2, "con": 1},
		"picks fold into an allocation")

	# decision <-> picks round-trip for every category the creator can render
	for p in [skill_p, asi_p,
			{"type": "spell-choice", "key": "k", "count": 2, "spellList": "wizard", "spellLevel": 0},
			{"type": "subclass", "key": "k", "classId": "cleric", "from": ["lightdomain"]},
			{"type": "feature-choice", "key": "k", "options": [{"optionId": "protector", "featureId": "x"}]},
			{"type": "lineage-choice", "key": "k", "speciesId": "elf", "from": ["drow", "wood-elf"]}]:
		var opts := Creator.options_for(p, null)
		check(not opts.is_empty(), "%s has options" % p["type"])
		var picks := autopick(p, null)
		var back := Creator.picks_from_decision(p, Creator.decision_for(p, picks))
		check(back == picks, "%s: decision round-trips to the same picks (%s vs %s)" % [p["type"], back, picks])

	# --- two full builds, straight through the flow ------------------------
	var vald = build("Valdis Hark", "human", "fighter", "soldier", "array")
	assert_sane(vald, "Valdis (human fighter)")
	check(vald.sheet().subclasses.is_empty(), "no subclass at level 1")

	var nyx = build("Nyx Emberline", "elf", "wizard", "sage", "pointbuy")
	assert_sane(nyx, "Nyx (elf wizard)")
	check(not nyx.sheet().spellcasting.is_empty(), "the wizard casts spells")
	check(int(nyx.sheet().spellcasting["slots"][0]) == 2, "a wizard 1 has two 1st-level slots")
	check(nyx.sheet().spellcasting["save_dc"] >= 12, "spell save DC is at least 12")

	var thrun = build("Thrun Oakfist", "dwarf", "cleric", "acolyte", "array")
	assert_sane(thrun, "Thrun (dwarf cleric)")

	# every class is buildable, not just the three above
	for c in Catalog.all("classes.json"):
		var ch = build("Test " + c["name"], "human", c["id"], "soldier", "array")
		check(ch.sheet().pending.is_empty(), "%s resolves with no pending choices" % c["id"])
		check(ch.sheet().max_hp > 0, "%s has hit points" % c["id"])

	# --- save / load -------------------------------------------------------
	var path := Save.save(vald)
	check(path.ends_with("valdis-hark.json"), "saved under a slug of the name (got %s)" % path)
	var back = Save.load_slug("valdis-hark")
	check(back != null, "the save loads back")
	if back != null:
		check(back.cname == vald.cname, "name round-trips")
		check(back.species_id == vald.species_id and back.background_id == vald.background_id, "species/background round-trip")
		check(back.base_abilities == vald.base_abilities, "base abilities round-trip")
		check(back.levels == vald.levels, "levels round-trip")
		check(back.choices == vald.choices, "choices round-trip")
		check(back.equipped == vald.equipped, "equipment round-trips")
		check(back.sheet().ac == vald.sheet().ac and back.sheet().max_hp == vald.sheet().max_hp,
			"the reloaded build re-resolves to the same sheet")
	check("valdis-hark" in Save.list_slugs(), "the character is listed")

	# presets are loadable through the same door
	var vera = Presets.vera()
	Save.save(vera)
	var vera2 = Save.load_slug("vera")
	check(vera2 != null and vera2.sheet().ac == vera.sheet().ac, "a preset saves and reloads")
	check(vera.sheet().pending.is_empty(), "the Vera preset has no unmade choices")
	Save.delete("valdis-hark")
	Save.delete("vera")
	check(not "valdis-hark" in Save.list_slugs(), "delete removes the file")

	same_name_is_not_the_same_hero()
	casters_keep_their_simple_weapons()
	duplicate_lists_merge()
	feat_follow_ups_come_after_the_feat()
	kit_classes_carry_no_warnings()
	skills_are_rows()

	check(Creator.spell_name("light") == "Light", "the Light cantrip reads as a spell, not as armour (got %s)" % Creator.spell_name("light"))
	check(Creator.humanize("light") == "Light armor", "...while the armour category keeps its own label")
	print("test_creator: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Two heroes with one name. Naming a second character after one already in the
# barracks used to destroy the first (same slug, same file, no warning) and lose
# the second as well, since Party.add_member refuses a duplicate id — you built a
# ranger, and both the ranger and the hero you built next were simply gone.
func same_name_is_not_the_same_hero() -> void:
	for slug in ["aria-vale", "aria-vale-2", "aria-vale-3"]:
		Save.delete(slug)

	var ranger = build("Aria Vale", "human", "ranger", "guide", "array")
	ranger.id = Save.unique_slug(ranger.cname)
	check(ranger.id == "aria-vale", "the first of a name gets the plain slug")
	Save.save(ranger)

	var barbarian = build("Aria Vale", "human", "barbarian", "guide", "array")
	barbarian.id = Save.unique_slug(barbarian.cname)
	check(barbarian.id == "aria-vale-2", "the second of a name gets a slug of its own")
	Save.save(barbarian)

	var reloaded_ranger = Save.load_slug("aria-vale")
	check(reloaded_ranger != null and reloaded_ranger.class_id() == "ranger",
		"the hero already in the barracks is still a ranger")

	# The point of the unique id: a Party takes both, because add_member refuses
	# a second character wearing an id it already has.
	var party := Party.new()
	var loaded := Save.load_all()
	var names: Array = []
	for ch in loaded:
		if ch.cname == "Aria Vale":
			check(party.add_member(ch), "%s (%s) joins the roster" % [ch.cname, ch.id])
			names.append(ch.class_id())
	names.sort()
	check(names == ["barbarian", "ranger"], "both Aria Vales are on the party page (got %s)" % str(names))

	# The file name is the identity, whatever a hand-edited `id` field claims.
	var f := FileAccess.open(Save.path_for("aria-vale-2"), FileAccess.READ_WRITE)
	if f != null:
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		d["id"] = "aria-vale"
		f.seek(0)
		f.store_string(JSON.stringify(d, "  "))
		f.close()
		check(Save.load_slug("aria-vale-2").id == "aria-vale-2",
			"a save wearing somebody else's id comes back under its own file name")

	for slug in ["aria-vale", "aria-vale-2"]:
		Save.delete(slug)


# #192: the wizard, sorcerer and druid name their weapons one by one ("dagger",
# "quarterstaff") where every other class says "simple", and a dagger's own
# weaponProficiencyId is "simple". Read that way the wizard's shelf held the
# light crossbow and nothing else, and the druid's the scimitar — and the sheet
# swung their own quarterstaff without the proficiency bonus.
func casters_keep_their_simple_weapons() -> void:
	for cls in ["wizard", "sorcerer"]:
		var c = build("Test " + cls, "human", cls, "sage", "array")
		var shelf := Creator.proficient_weapons(c.sheet())
		for wid in ["dagger", "dart", "sling", "quarterstaff", "light-crossbow"]:
			check(wid in shelf, "%s: %s is on the equipment shelf (%s)" % [cls, wid, str(shelf)])
		check(not "longsword" in shelf, "%s: no martial weapon on the shelf" % cls)
	var druid = build("Test druid", "human", "druid", "sage", "array")
	var dshelf := Creator.proficient_weapons(druid.sheet())
	for wid in ["club", "dagger", "quarterstaff", "scimitar", "spear", "sling"]:
		check(wid in dshelf, "druid: %s is on the equipment shelf" % wid)
	check("hide" in Creator.proficient_armor(druid.sheet()) and "shield" in Creator.proficient_armor(druid.sheet()),
		"druid: medium-nonmetal and shields-nonmetal open the armor shelf")
	var wiz = build("Staff wizard", "human", "wizard", "sage", "array")
	wiz.equipped.assign(["quarterstaff"])
	wiz.dirty()
	var s = wiz.sheet()
	var staff: Dictionary = {}
	for a in s.attacks:
		if String(a.get("id", "")) == "quarterstaff":
			staff = a
	check(not staff.is_empty() and int(staff["to_hit"]) == int(s.abilities["str"]["mod"]) + s.proficiency_bonus,
		"a wizard's quarterstaff adds the proficiency bonus (%s)" % str(staff.get("to_hit", "none")))

# #191: a human soldier is asked for a language twice (species and background)
# from the same list, and for a skill twice (species: any; fighter: eleven).
# The first pair is one list of two; the second stays two lists, each greying
# what the other took, and both greying what the soldier already has.
func duplicate_lists_merge() -> void:
	var c = Creator.new_character()
	c.species_id = "human"
	c.background_id = "soldier"
	c.add_level("fighter", -1)
	c.dirty()
	var pts: Array = c.sheet().choice_points
	var groups: Array = Creator.choice_groups(pts, c.sheet())
	var langs: Array = groups.filter(func(g): return g[0]["type"] == "language-choice")
	check(langs.size() == 1 and langs[0].size() == 2, "the two language lists are one list (%s)" % str(langs.map(func(g): return g.size())))
	var skills: Array = groups.filter(func(g): return g[0]["type"] == "skill-choice")
	check(skills.size() == 2, "the human's any-skill and the fighter's eleven stay two lists")
	if langs.size() != 1 or skills.size() != 2:
		return
	var g: Array = langs[0]
	var by_key := {}
	for id in ["elvish", "dwarvish", "giant"]:
		by_key = Creator.toggle_group(g, by_key, id)
	var sizes: Array = g.map(func(q): return (by_key[q["key"]] as Array).size())
	check(sizes == [Creator.pick_count(g[0]), Creator.pick_count(g[1])] or sizes.reduce(func(a, b): return a + b) == Creator.pick_count(g[0]) + Creator.pick_count(g[1]),
		"picks fill the first list, then the next (%s)" % str(by_key))
	by_key = Creator.toggle_group(g, by_key, "elvish")
	check(not by_key.values().any(func(v): return "elvish" in v), "a second click takes it off whichever list held it")
	# the fighter takes Perception: the human's any-skill list greys it
	var fighter_skill: Dictionary = skills.filter(func(gg): return gg[0]["source"]["origin"] == "class")[0][0]
	var human_skill: Dictionary = skills.filter(func(gg): return gg[0]["source"]["origin"] == "species")[0][0]
	c.decide(fighter_skill["key"], Creator.decision_for(fighter_skill, ["perception", "survival"]))
	var taken: Dictionary = Creator.taken_elsewhere(human_skill, [human_skill], c.sheet().choice_points, c.choices, c.sheet())
	check(taken.get("perception", "") == "picked in another list", "a skill the fighter list took is greyed in the human's (%s)" % str(taken))
	check(taken.get("athletics", "") == "already known", "and so is one the soldier background already gave")
	check(not taken.has("stealth"), "a skill nobody has stays open")

# #190: a human's origin feat is a feat-choice, and what the chosen feat asks
# for next — Magic Initiate's spell list and then its spells, Skilled's three
# skills — used to be listed with its KIND, which the resolver walks before
# feats: the follow-up turned up above the feat that asked for it. On the page
# it now comes straight after the feat, and nothing else moves.
func feat_follow_ups_come_after_the_feat() -> void:
	for feat in ["magic-initiate", "skilled"]:
		var c = Creator.new_character()
		c.species_id = "human"
		c.background_id = "soldier"
		c.add_level("fighter", -1)
		c.dirty()
		var fc: Dictionary = {}
		for p in c.sheet().choice_points:
			if p["type"] == "feat-choice":
				fc = p
		check(not fc.is_empty(), "%s: a human has an origin feat to choose" % feat)
		if fc.is_empty():
			continue
		c.decide(fc["key"], Creator.decision_for(fc, [feat]))
		if feat == "magic-initiate":   # the list pick brings the spells: they follow it too
			for p in c.sheet().choice_points:
				if p["type"] == "feature-choice" and p["source"]["id"] == feat:
					c.decide(p["key"], Creator.decision_for(p, [Creator.options_for(p)[-1]["id"]]))
		var raw: Array = c.sheet().choice_points
		var page: Array = Creator.page_order(raw, c.choices)
		var keys: Array = page.map(func(p): return String(p["key"]))
		check(page.size() == raw.size(), "%s: page order keeps every point (%d of %d)" % [feat, page.size(), raw.size()])
		var at: int = keys.find(fc["key"])
		var mine: Array = raw.filter(func(p): return p["source"]["origin"] == "feat" and p["source"]["id"] == feat)
		check(not mine.is_empty(), "%s: the feat asks for something" % feat)
		if feat == "magic-initiate":
			check(mine.any(func(p): return p["type"] == "spell-choice"), "magic-initiate: its spells are points too, once the list is picked")
		# the resolver lists at least one of them above the feat: that was the bug
		var raw_keys: Array = raw.map(func(p): return String(p["key"]))
		check(mine.any(func(p): return raw_keys.find(p["key"]) < raw_keys.find(fc["key"])),
			"%s: the resolver's own order does put a follow-up above the feat (else this test proves nothing)" % feat)
		for i in mine.size():
			check(keys.find(mine[i]["key"]) == at + 1 + i,
				"%s: %s sits right under the feat (at %d, feat at %d)" % [feat, mine[i]["key"], keys.find(mine[i]["key"]), at])
		var rest_raw: Array = raw_keys.filter(func(k): return not mine.any(func(p): return p["key"] == k))
		var rest_page: Array = keys.filter(func(k): return not mine.any(func(p): return p["key"] == k))
		check(rest_raw == rest_page, "%s: every other choice keeps its place" % feat)
		# Skilled's any-three-skills is the human's any-skill list over again, and
		# #191 would fold the two into one list — back up where the human's stood.
		var groups: Array = Creator.choice_groups(page, c.sheet(), c.choices)
		for g in groups:
			var feats: Array = g.filter(func(p): return p["source"]["origin"] == "feat")
			check(feats.is_empty() or feats.size() == g.size(),
				"%s: a feat's list is not merged into one from outside the feat (%s)" % [feat, str(g.map(func(p): return p["key"]))])
		var flat: Array = []
		for g in groups:
			flat.append(String(g[0]["key"]))
		check(flat.find(mine[0]["key"]) == flat.find(fc["key"]) + 1,
			"%s: grouped for display, the follow-up is still the next thing under the feat" % feat)

# #189: the Review page reads sheet.warnings out, and every barbarian, fighter
# and rogue walked out of the creator with "bundle-choice ... cannot resolve —
# starting-equipment bundles are not exported (SCHEMA gap #2)" on it, four
# times for a fighter. The kit is the Equipment step's to pick; nothing is wrong.
func kit_classes_carry_no_warnings() -> void:
	for cls in ["barbarian", "fighter", "rogue"]:
		var c = build("Test " + cls, "human", cls, "soldier", "array")
		check(c.sheet().warnings.is_empty(), "%s: a finished build carries no warning (%s)" % [cls, str(c.sheet().warnings)])

# #188: the sheet's skills are rows, not a comma paragraph — proficient ones
# only, by name, the bonus the sheet computed, expertise told apart.
func skills_are_rows() -> void:
	var pike = Presets.pike()
	var s = pike.sheet()
	var rows: Array = Creator.skill_rows(s)
	var names: Array = rows.map(func(r): return String(r["name"]))
	var sorted := names.duplicate()
	sorted.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	check(names == sorted, "skill rows read alphabetically (%s)" % str(names))
	check(rows.size() == s.skill_prof.values().filter(func(g): return g != "none").size(), "one row per proficient skill, and only those")
	var stealth: Array = rows.filter(func(r): return r["id"] == "stealth")
	check(stealth.size() == 1 and stealth[0]["grade"] == "expert" and int(stealth[0]["bonus"]) == int(s.skills["stealth"]),
		"Pike's Stealth is an expert row at the sheet's own bonus (%s)" % str(stealth))
	var table: String = Creator._pair_table(rows.map(func(r): return [r["name"], "%+d" % int(r["bonus"])]), 2)
	check(table.begins_with("[table=4]") and table.count("[cell") == ceili(rows.size() / 2.0) * 4,
		"two pairs a row, the last row padded to full width")
	check(Creator._pair_table([], 2) == "[table=4][/table]\n", "no rows is an empty table, not a stray cell")
