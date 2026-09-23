# #176 step 3 — earning a personality trait: what a fight or a cleared lair
# leaves on the people in it (core/traits.gd's after_fight / after_lair, spec
# §6). Triumphs on chance, hardships on a save and the degree it is made or
# failed by, temperament riding the save, cures as the save asked again, banes
# and Veteran by count, wounds that lapse — and every roll seeded, so the same
# fight at the same minute leaves the same marks. Headless.
#   godot --headless --path . -s tests/test_traits_earn.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_instanced_rows()
	test_triumph_rates_and_shape()
	test_one_story_per_hero()
	test_hardship_degrees()
	test_temperament_rides_the_save()
	test_wrathful_grudge()
	test_counted_marks()
	test_cures()
	test_lapse_and_rest()
	test_save_round_trip()
	test_in_the_fight()
	test_determinism()
	print("test_traits_earn: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _hero(id: String, traits := [], cls := "fighter", level := 3) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = "soldier"
	for i in level:
		ch.add_level(cls, -1)
	for t in traits:
		ch.traits.append({"id": t, "why": "test"})
	return ch

func _won(credit := {}, extra := {}) -> Dictionary:
	var r := {"outcome": "Victory", "credit": credit, "deaths": [], "kills": [], "downed": []}
	r.merge(extra, true)
	return r

func _downed(by: String, dtype: String, fails := 0) -> Dictionary:
	var c := {"kills": [], "downed_by": [{"dtype": dtype, "by": by, "team": "foe"}], "revived_by": []}
	if fails > 0:
		c["death_fails"] = fails
	return c

func test_instanced_rows() -> void:
	check(Traits.name_of("grudge@goblinoid") == "Grudge: goblins", "an instanced row names its faction: %s" % Traits.name_of("grudge@goblinoid"))
	check(Traits.row("haunted@orc")["effects"][0]["when"]["vs_faction"] == ["orc"], "...and its effects are about that faction")
	check(Traits.name_of("bane@dragon") == "Dragon-bane", "a bane is named in the singular: %s" % Traits.name_of("bane@dragon"))
	check(Traits.row("nope@orc").is_empty(), "an instance of no row is no row")
	var ch := _hero("vera")
	ch.traits.append({"id": "bane@goblinoid", "why": "t"})
	check("bane@goblinoid" in Traits.ids(ch), "a hero holds an instanced trait like any other")
	for id in ["emboldened", "fire-tempered", "burn-shy", "wounded", "maimed", "hard-to-kill", "giant-killer"]:
		check(Traits.effect_lines(id).all(func(l): return l["live"]) or id in ["renowned"],
			"%s's fight effects are all in play" % id)

func test_triumph_rates_and_shape() -> void:
	# A flawless hard win: 40% each, over many minutes.
	var got := 0
	var n := 400
	var first := {}
	for i in n:
		var ch := _hero("ilsa")
		var out := Traits.after_fight([ch], _won(), {"now": float(i * 37), "difficulty": "hard"})
		if not out["moments"].is_empty():
			got += 1
			if first.is_empty():
				first = out["moments"][0]
	var rate := float(got) / n
	check(rate > 0.33 and rate < 0.47, "a flawless hard win tempers about 40%% of heroes: %.2f" % rate)
	check(first.get("kind") == "triumph" and not first.has("save"), "a triumph has no save, and no die")
	check(String(first["trait"]["name"]) in ["Emboldened", "Overconfident"], "...and is one of its table's: %s" % first["trait"]["name"])
	check(String(first["cname"]) == "Ilsa" and String(first["line"]).begins_with("Ilsa is now"), "the moment names the hero: %s" % first["line"])
	# Not on a normal fight, and not on a hard one where somebody went down.
	var none := 0
	for i in 60:
		none += Traits.after_fight([_hero("ilsa")], _won(), {"now": float(i), "difficulty": "normal"})["moments"].size()
		none += Traits.after_fight([_hero("ilsa")], _won({}, {"downed": ["x"]}), {"now": float(i), "difficulty": "hard"})["moments"].size()
	check(none == 0, "an ordinary win, or a hard one somebody went down in, leaves nothing")
	# Emboldened lapses in three days.
	for i in 200:
		var ch := _hero("ilsa")
		Traits.after_fight([ch], _won(), {"now": 1000.0 + i, "difficulty": "hard"})
		if Traits.has(ch, "emboldened"):
			var t: Dictionary = ch.traits.filter(func(x): return x["id"] == "emboldened")[0]
			check(is_equal_approx(float(t["until"]), 1000.0 + i + 3 * Traits.DAY), "Emboldened is three days' worth")
			break

func test_one_story_per_hero() -> void:
	# A boss kill and a revive in one fight: one triumph for the killer at most.
	var most := 0
	for i in 200:
		var ch := _hero("pike", [], "fighter", 3)
		var credit := {"pike": {"kills": ["ogre"], "downed_by": [], "revived_by": []},
			"vera": {"kills": [], "downed_by": [], "revived_by": ["pike"]}}
		var out := Traits.after_fight([ch], _won(credit, {"kills": ["ogre"]}), {"now": float(i), "difficulty": "hard"})
		most = maxi(most, out["moments"].filter(func(m): return m["kind"] == "triumph").size())
	check(most == 1, "at most one triumph per hero per fight (%d)" % most)
	# The dead roll nothing.
	var dead := _hero("pike")
	var out2 := Traits.after_fight([dead], _won({"pike": _downed("goblin", "fire", 3)}, {"deaths": ["pike"]}), {"now": 5.0})
	check(out2["moments"].is_empty() and out2["lines"].is_empty(), "a hero who died in it rolls nothing")

func test_hardship_degrees() -> void:
	# Downed by fire: a WIS save, and every degree turns up over the minutes;
	# each is exactly what its own dice say.
	var seen := {}
	var ok := true
	for i in 300:
		var ch := _hero("brenna")
		var out := Traits.after_fight([ch], _won({"brenna": _downed("fire-giant", "fire")}), {"now": float(i * 11)})
		var ms: Array = out["moments"]
		var sv: Dictionary = {}
		for m in ms:
			if m.has("save"):
				sv = m["save"]
		var line := String(out["lines"][0]) if not out["lines"].is_empty() else ""
		if sv.is_empty() and "shakes it off" in line:
			seen["made"] = true
			continue
		if sv.is_empty():
			ok = false
			continue
		var margin := int(sv["nat"]) + int(sv["bonus"]) - int(sv["dc"])
		if i == 0:
			check(int(sv["dc"]) == 14, "DC 10 + half the fire giant's CR 9 = 14 (%d)" % int(sv["dc"]))
		var names: Array = ms.map(func(m): return String(m["trait"]["name"]))
		if int(sv["nat"]) == 20 or margin >= Traits.DEGREE:
			seen["tempered"] = true
			ok = ok and names == ["Fire-tempered"] and Traits.has(ch, "fire-tempered")
		elif margin < 0 and (int(sv["nat"]) == 1 or margin <= -Traits.DEGREE):
			seen["scar+wound"] = true
			ok = ok and names == ["Burn-shy", "Shaken"] and Traits.has(ch, "shaken")
		elif margin < 0:
			seen["scar"] = true
			ok = ok and names == ["Burn-shy"]
	check(ok, "every roll left exactly what its degree says")
	check(seen.size() == 4, "all four degrees turn up: %s" % [seen.keys()])
	# A scar remembers how to be cured.
	for i in 300:
		var ch := _hero("brenna")
		Traits.after_fight([ch], _won({"brenna": _downed("fire-giant", "fire")}), {"now": float(i * 11)})
		if Traits.has(ch, "burn-shy"):
			var t: Dictionary = ch.traits.filter(func(x): return x["id"] == "burn-shy")[0]
			check(int(t["dc"]) == 14 and t["cure"] == {"deals": ["fire"]} and t["event"] == "downed_fire",
				"the scar keeps its DC and its cure: %s" % t)
			break
	# The boss aggravates it, and so does a death save failed.
	var ch2 := _hero("brenna")
	var out := Traits.after_fight([ch2], _won({"brenna": _downed("fire-giant", "fire", 1)}, {"kills": ["fire-giant"]}), {"now": 3.0})
	var dc := -1
	for m in out["moments"]:
		if m.has("save"):
			dc = int(m["save"]["dc"])
	for l in out["lines"]:
		if "DC" in l:
			dc = int(String(l).get_slice("DC ", 1).to_int())
	check(dc == 18, "the boss and a failed death save: 14 + 2 + 2 = 18 (%d)" % dc)

func test_temperament_rides_the_save() -> void:
	var sv := _first_save(_hero("vera", ["brave"]), "fire")
	check(sv.get("mode") == "adv", "Brave: advantage on a fear save")
	sv = _first_save(_hero("pike", ["craven"]), "fire")
	check(sv.get("mode") == "dis", "Craven: disadvantage on it")
	sv = _first_save(_hero("pike", ["craven"]), "cold")
	check(sv.get("mode") == "", "...but the cold is a CON save and not a fear one")
	var calm := _first_save(_hero("ilsa", ["calm"]), "fire")
	var plain := _first_save(_hero("ilsa"), "fire")
	check(int(calm["bonus"]) == int(plain["bonus"]) + 2, "Calm: +2 on a hardship's WIS save (%d vs %d)" % [calm["bonus"], plain["bonus"]])
	check(int(plain["bonus"]) == int(_hero("ilsa").sheet().saves["wis"]), "the bonus is the hero's own WIS save")

func _first_save(ch: Character, dtype: String) -> Dictionary:
	for i in 300:
		var c2 := Character.new()
		c2 = _hero(ch.id, Traits.ids(ch))
		var out := Traits.after_fight([c2], _won({ch.id: _downed("young-red-dragon", dtype)}), {"now": float(i)})
		for m in out["moments"]:
			if m.has("save"):
				return m["save"]
	return {}

func test_wrathful_grudge() -> void:
	# Put down by goblins twice: the second time asks the faction save.
	var plain := false
	var wrath := false
	for i in 200:
		var ch := _hero("pike")
		var w := _hero("pike", ["wrathful"])
		for h in [ch, w]:
			Traits.after_fight([h], _won({"pike": _downed("goblin", "slashing")}), {"now": float(i)})
			Traits.after_fight([h], _won({"pike": _downed("bugbear", "slashing")}), {"now": float(i) + 1.0})
		plain = plain or Traits.has(ch, "haunted@goblinoid")
		wrath = wrath or Traits.has(w, "grudge@goblinoid")
		if i < 3:
			check(not Traits.has(w, "haunted@goblinoid"), "a Wrathful hero is never haunted: the fear turns outward")
		if plain and wrath:
			break
	check(plain, "put down by goblins twice can leave a hero Haunted by goblins")
	check(wrath, "...and a Wrathful one with a Grudge instead")

func test_counted_marks() -> void:
	var ch := _hero("vera")
	var out: Dictionary = {}
	for i in 10:
		out = Traits.after_fight([ch], _won({"vera": {"kills": ["goblin"], "downed_by": [], "revived_by": []}}), {"now": float(i)})
	check(Traits.has(ch, "bane@goblinoid"), "ten goblins make a Goblin-bane")
	check(out["moments"].any(func(m): return m["trait"]["name"] == "Goblin-bane"), "...on the tenth, with its moment")
	var d := _hero("vera")
	for i in 3:
		Traits.after_fight([d], _won({"vera": {"kills": ["young-red-dragon"], "downed_by": [], "revived_by": []}}), {"now": float(i)})
	check(Traits.has(d, "bane@dragon"), "three dragons make a Dragon-bane")
	d.traits.append({"id": "bane@orc", "why": "t"})
	for i in 10:
		Traits.after_fight([d], _won({"vera": {"kills": ["skeleton"], "downed_by": [], "revived_by": []}}), {"now": float(i)})
	check(Traits._count_family(d, "bane") == 2, "two banes at most")
	var v := _hero("vera")
	v.trait_counts["wins"] = 19
	Traits.after_fight([v], _won(), {"now": 1.0})
	check(Traits.has(v, "veteran"), "the twentieth won fight makes a Veteran")

func test_cures() -> void:
	var cured := false
	var kept := false
	for i in 200:
		var ch := _hero("pike")
		Traits.grant(ch, "burn-shy", "t", 0.0, {"event": "downed_fire", "dc": 14, "cure": {"deals": ["fire"]}})
		var out := Traits.after_fight([ch], _won({}, {"kills": ["goblin"]}), {"now": float(i)})
		if i == 0:
			check(Traits.has(ch, "burn-shy"), "a win against goblins asks nothing of a burn")
		out = Traits.after_fight([ch], _won({}, {"kills": ["fire-giant"]}), {"now": float(i)})
		if not Traits.has(ch, "burn-shy"):
			cured = true
			check(out["moments"][0]["kind"] == "cure" and out["moments"][0].has("save"), "the cure is a moment, with its save")
		else:
			kept = true
		if cured and kept:
			break
	check(cured and kept, "beating a fire-dealer asks the save again: sometimes it mends, sometimes not")

func test_lapse_and_rest() -> void:
	var ch := _hero("pike", ["calm"])
	Traits.grant(ch, "wounded", "t", 0.0)
	Traits.grant(ch, "shaken", "t", 0.0)
	Traits.grant(ch, "maimed", "t", 0.0)
	check(Traits._count_family(ch, "wound") == 2, "two wounds at most")
	var sh: Dictionary = ch.traits.filter(func(x): return x["id"] == "shaken")[0]
	check(is_equal_approx(float(sh["until"]), 2 * Traits.DAY), "a Calm hero sheds Shaken in two days")
	check(Traits.expire(ch, Traits.DAY).is_empty(), "nothing lapses early")
	check(Traits.expire(ch, 2 * Traits.DAY) == ["Shaken"], "...and Shaken on its day")
	check(Traits.heal_rest(ch, false) == ["Wounded"], "a long rest at an inn mends Wounded")
	var m := _hero("pike")
	Traits.grant(m, "maimed", "t", 0.0)
	check(Traits.heal_rest(m, false).is_empty() and Traits.heal_rest(m, true) == ["Maimed"], "Maimed wants a city's healers")
	# The profile's line: what mends it, and how long is left.
	var w := _hero("pike")
	Traits.grant(w, "wounded", "t", 0.0)
	check(Traits.mend_text(w, "wounded", Traits.DAY * 0.5) == "A long rest at an inn, or three days — 3 days left",
		"a wound says what mends it and how long: %s" % Traits.mend_text(w, "wounded", Traits.DAY * 0.5))
	Traits.grant(w, "burn-shy", "t", 0.0, {"cure": {"deals": ["fire"]}})
	check(Traits.mend_text(w, "burn-shy", 0.0).begins_with("Win against something that deals fire"), "...a scar what cures it")
	check(Traits.mend_text(w, "brave", 0.0) == "", "...and a temperament nothing")

func test_save_round_trip() -> void:
	var ch := _hero("pike")
	Traits.grant(ch, "burn-shy", "Went down in the fire", 120.0, {"event": "downed_fire", "dc": 14, "cure": {"deals": ["fire"]}})
	Traits.grant(ch, "wounded", "t", 120.0)
	ch.trait_counts = {"kill:goblinoid": 4, "wins": 7}
	var back = CharacterSave.from_dict(JSON.parse_string(JSON.stringify(CharacterSave.to_dict(ch))))
	var t: Dictionary = back.traits.filter(func(x): return x["id"] == "burn-shy")[0]
	check(t["dc"] is int and int(t["dc"]) == 14 and t["cure"] == {"deals": ["fire"]} and float(t["since"]) == 120.0,
		"an earned scar survives the save: %s" % t)
	check(back.traits.filter(func(x): return x["id"] == "wounded")[0].has("until"), "...and a wound its day")
	check(back.trait_counts == {"kill:goblinoid": 4, "wins": 7} and back.trait_counts["wins"] is int, "...and the counts")
	var d := CharacterSave.to_dict(_hero("old"))
	d.erase("trait_counts")
	check(CharacterSave.from_dict(d).trait_counts.is_empty(), "a save from before step 3 has no counts")

func test_in_the_fight() -> void:
	# Maimed takes a hex; Hard to kill rolls its death saves with advantage.
	var ch := _hero("pike", ["maimed"])
	var c = Adapter.to_combatant(ch, "party", Encounter.PARTY_STARTS[0])
	var speed: int = c.speed
	var cb = Encounter.build({"theme": "downs", "seed": 7, "monsters": [{"id": "goblin", "count": 1}]}, [c])
	check(cb.team_of("party")[0].speed == speed - 1, "Maimed: a hex of movement gone (%d -> %d)" % [speed, cb.team_of("party")[0].speed])
	check(Traits.flag(Adapter.to_combatant(_hero("x", ["hard-to-kill"]), "party", Encounter.PARTY_STARTS[0]), "death_save_adv") != null,
		"Hard to kill is asked by the death save")
	# The fight records the death saves a hero failed.
	var h := _hero("pike")
	var cb2 = Encounter.build({"theme": "downs", "seed": 7, "monsters": [{"id": "goblin", "count": 1}]},
		[Adapter.to_combatant(h, "party", Encounter.PARTY_STARTS[0])])
	var p = cb2.team_of("party")[0]
	p.hp = 0
	p.statuses["down"] = true
	var most := 0
	for i in 6:
		if p.is_dead() or not p.is_down():
			break
		cb2._death_save(p)
		most = maxi(most, p.death_f)
	check(most > 0 and int(cb2.credit.get("pike", {}).get("death_fails", 0)) == most,
		"the credit keeps the most death saves failed (%d): %s" % [most, cb2.credit.get("pike", {})])

func test_determinism() -> void:
	var a := _hero("brenna", ["brave"])
	var b := _hero("brenna", ["brave"])
	var r := _won({"brenna": _downed("fire-giant", "fire")}, {"kills": ["fire-giant"]})
	var oa := Traits.after_fight([a], r, {"now": 4321.0, "difficulty": "hard"})
	var ob := Traits.after_fight([b], r, {"now": 4321.0, "difficulty": "hard"})
	check(oa["lines"] == ob["lines"] and Traits.ids(a) == Traits.ids(b), "the same fight at the same minute leaves the same marks")
