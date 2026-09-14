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
	check(int(s.speeds.get("walk", 0)) >= 25, "%s: has a walk speed (got %s)" % [label, s.speeds])
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

