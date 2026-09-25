# SPIKE — party opinions and romance (docs/spike-party-opinions.md). The model
# only, headless: the pair score, its baseline, the bands, what moves it, the
# courtship ladder and its gates, the three combat hooks, and the save shape.
#   godot --headless --path . -s tests/test_party_opinion.gd
extends SceneTree

const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Character = preload("res://core/character.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Encounter = preload("res://core/encounter.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_symmetric_clamped_and_self()
	test_baseline_from_sheets()
	test_unrecorded_pair_sits_at_baseline()
	test_bands_are_ordered()
	test_events_move_the_pair()
	test_road_result_only_blames_bad_events()
	test_decay_drifts_to_baseline_not_zero()
	test_morale_and_travel_bonus()
	test_courtship_gates()
	test_courtship_answers()
	test_breakup()
	test_camp_moment_shapes()
	test_camp_moment_never_asks_twice()
	test_camp_lines_by_temperament()
	test_courtship_line_asker_is_a()
	test_headers_are_current()
	test_combat_hooks()
	test_rally_status_survives_new_turn()
	test_save_round_trip()
	print("test_party_opinion: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# The three presets: Vera (human soldier), Pike (human criminal), Ilsa (human
# acolyte). Soldier|criminal is a temper grudge, so Vera and Pike start cold-ish;
# all three are human, so every pair carries the kinship bonus.
func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _demo(id: String, species: String, background: String) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = species
	ch.background_id = background
	ch.add_level("fighter", -1)
	return ch

func test_symmetric_clamped_and_self() -> void:
	var p := _party()
	PartyOpinion.set_score(p, "vera", "pike", 30.0)
	check(PartyOpinion.score(p, "pike", "vera") == 30.0, "a pair is one number, read either way")
	check(PartyOpinion.key("vera", "pike") == PartyOpinion.key("pike", "vera"), "one key per pair")
	PartyOpinion.adjust(p, "vera", "pike", 1000.0)
	check(PartyOpinion.score(p, "vera", "pike") == PartyOpinion.RANGE, "clamped at +RANGE")
	PartyOpinion.adjust(p, "vera", "pike", -1000.0)
	check(PartyOpinion.score(p, "vera", "pike") == -PartyOpinion.RANGE, "clamped at -RANGE")
	check(PartyOpinion.score(p, "vera", "vera") == 0.0, "nobody has an opinion of themselves")
	PartyOpinion.set_score(p, "vera", "vera", 50.0)
	check(not p.relations.has("vera|vera"), "...and one cannot be written")

func test_baseline_from_sheets() -> void:
	check(PartyOpinion.baseline(_demo("a", "human", "soldier"), _demo("b", "human", "guard"))
		== PartyOpinion.SAME_TEMPER + PartyOpinion.SAME_SPECIES, "same temper, same species")
	check(PartyOpinion.baseline(_demo("a", "human", "soldier"), _demo("b", "elf", "criminal"))
		== PartyOpinion.TEMPER_GRUDGE["crooked|martial"], "a soldier and a thief grate")
	check(PartyOpinion.baseline(_demo("a", "elf", "sage"), _demo("b", "dwarf", "farmer"))
		== PartyOpinion.SPECIES_GRUDGE["dwarf|elf"], "the classic grudge, no temper clash")
	check(PartyOpinion.baseline(_demo("a", "dwarf", "farmer"), _demo("b", "elf", "sage"))
		== PartyOpinion.baseline(_demo("b", "elf", "sage"), _demo("a", "dwarf", "farmer")),
		"baseline is symmetric")
	check(PartyOpinion.baseline(_demo("a", "gnome", "wayfarer"), _demo("b", "halfling", "sage")) == 0.0,
		"nothing in common, nothing against: neutral")
	check(PartyOpinion.baseline(null, _demo("b", "human", "sage")) == 0.0, "a missing sheet is neutral")

func test_unrecorded_pair_sits_at_baseline() -> void:
	var p := _party()
	check(p.relations.is_empty(), "a fresh party has nothing recorded")
	check(PartyOpinion.score(p, "vera", "pike") == PartyOpinion.baseline_of(p, "vera", "pike"),
		"an unrecorded pair reads as its baseline")
	check(PartyOpinion.score(p, "vera", "pike") < 0.0, "Vera (soldier) and Pike (criminal) start below neutral")
	check(PartyOpinion.score(p, "vera", "ilsa") > 0.0, "Vera and Ilsa (both human, no grudge) start above")
	check(p.relations.is_empty(), "reading writes nothing")
	PartyOpinion.adjust(p, "vera", "pike", 1.0)
	check(PartyOpinion.score(p, "vera", "pike") == PartyOpinion.baseline_of(p, "vera", "pike") + 1.0,
		"the first change moves off the baseline, not off 0")

func test_bands_are_ordered() -> void:
	check(PartyOpinion.RIVALS < PartyOpinion.COLD and PartyOpinion.COLD < 0.0
		and 0.0 < PartyOpinion.WARM and PartyOpinion.WARM < PartyOpinion.BONDED
		and PartyOpinion.BONDED < PartyOpinion.COURTSHIP_MIN, "thresholds read low to high")
	var p := _party()
	var want := {-100.0: "rivals", PartyOpinion.RIVALS: "rivals", PartyOpinion.RIVALS + 1: "cold",
		PartyOpinion.COLD: "cold", 0.0: "neutral", PartyOpinion.WARM - 1: "neutral",
		PartyOpinion.WARM: "warm", PartyOpinion.BONDED: "bonded", 100.0: "bonded"}
	for s in want:
		PartyOpinion.set_score(p, "vera", "pike", s)
		check(PartyOpinion.band(p, "vera", "pike") == want[s], "score %s is %s" % [s, want[s]])
	check(PartyOpinion.describe(p, "vera", "pike") == "Vera Kord and Pike Sallow — bonded (+100)",
		"describe() is the party page's one line")

func test_events_move_the_pair() -> void:
	var p := _party()
	var base := PartyOpinion.score(p, "ilsa", "vera")
	PartyOpinion.saved(p, "ilsa", "vera")
	check(PartyOpinion.score(p, "ilsa", "vera") == base + PartyOpinion.SAVED, "being saved is the big one")
	PartyOpinion.friendly_fire(p, "ilsa", "vera")
	check(PartyOpinion.score(p, "ilsa", "vera") == base + PartyOpinion.SAVED - PartyOpinion.FRIENDLY_FIRE,
		"a cone that catches an ally costs")
	var b2 := PartyOpinion.score(p, "vera", "pike")
	var b3 := PartyOpinion.score(p, "pike", "ilsa")
	PartyOpinion.fought_beside(p, ["vera", "pike"])
	check(PartyOpinion.score(p, "vera", "pike") == b2 + PartyOpinion.FOUGHT_BESIDE, "the two who stood warm to each other")
	check(PartyOpinion.score(p, "pike", "ilsa") == b3, "...and not to the one who did not")

func test_road_result_only_blames_bad_events() -> void:
	var p := _party()
	var vp := PartyOpinion.score(p, "vera", "pike")
	var vi := PartyOpinion.score(p, "vera", "ilsa")
	var pi := PartyOpinion.score(p, "pike", "ilsa")
	PartyOpinion.road_result(p, "vera", true, "good")
	check(PartyOpinion.score(p, "vera", "pike") == vp + PartyOpinion.ROAD_PASS
		and PartyOpinion.score(p, "vera", "ilsa") == vi + PartyOpinion.ROAD_PASS,
		"a pass earns a little from everyone else marching")
	check(PartyOpinion.score(p, "pike", "ilsa") == pi, "...and moves nobody else")
	PartyOpinion.road_result(p, "vera", false, "good")
	check(PartyOpinion.score(p, "vera", "pike") == vp + PartyOpinion.ROAD_PASS,
		"failing to find a cache is nobody's fault")
	PartyOpinion.road_result(p, "vera", false, "bad")
	check(PartyOpinion.score(p, "vera", "pike") == vp + PartyOpinion.ROAD_PASS - PartyOpinion.ROAD_FAIL,
		"walking the party into a snare is")
	PartyOpinion.road_result(p, "", true, "good")
	check(PartyOpinion.score(p, "vera", "pike") == vp + PartyOpinion.ROAD_PASS - PartyOpinion.ROAD_FAIL,
		"an event nobody rolled moves nobody")

func test_decay_drifts_to_baseline_not_zero() -> void:
	var p := _party()
	var base := PartyOpinion.baseline_of(p, "vera", "pike")
	PartyOpinion.set_score(p, "vera", "pike", base + 30.0)
	PartyOpinion.decay(p, PartyOpinion.DAY)
	check(is_equal_approx(PartyOpinion.score(p, "vera", "pike"), base + 30.0 - PartyOpinion.DRIFT_PER_DAY),
		"a day of nothing drifts a pair down toward where they started")
	for i in 100:
		PartyOpinion.decay(p, PartyOpinion.DAY)
	check(PartyOpinion.score(p, "vera", "pike") == base, "...and stops at the baseline, not at 0")
	PartyOpinion.set_score(p, "vera", "pike", base - 30.0)
	for i in 100:
		PartyOpinion.decay(p, PartyOpinion.DAY)
	check(PartyOpinion.score(p, "vera", "pike") == base, "from below too")
	PartyOpinion.set_score(p, "vera", "pike", base + 5.0)
	PartyOpinion.decay(p, 0.0)
	check(PartyOpinion.score(p, "vera", "pike") == base + 5.0, "a paused clock drifts nothing")
	PartyOpinion.set_score(p, "vera", "pike", base + 5.0)
	p.remove_member("pike")
	PartyOpinion.decay(p, PartyOpinion.DAY * 50)
	check(float(p.relations["pike|vera"]["score"]) == base + 5.0,
		"a pair with somebody gone is left alone (re-recruit them and it is still there)")

func test_morale_and_travel_bonus() -> void:
	var p := _party()
	check(PartyOpinion.morale(p) == 0, "three humans with one grudge between them: an even mood")
	for pr in PartyOpinion.active_pairs(p):
		PartyOpinion.set_score(p, pr[0], pr[1], PartyOpinion.WARM)
	check(PartyOpinion.morale(p) == 1 and PartyOpinion.travel_bonus(p) == 1, "a party that likes itself: +1 on the road")
	PartyOpinion.set_score(p, "vera", "pike", -2.0 * PartyOpinion.WARM)
	check(PartyOpinion.morale(p) == 0, "one feud drags a warm party back to even")
	PartyOpinion.set_score(p, "vera", "pike", -100.0)
	check(PartyOpinion.morale(p) == -1, "...and a bad enough one drags it under")
	for pr in PartyOpinion.active_pairs(p):
		PartyOpinion.set_score(p, pr[0], pr[1], PartyOpinion.COLD)
	check(PartyOpinion.travel_bonus(p) == -1, "a party that does not: -1")
	p.bench("pike")
	p.bench("ilsa")
	check(PartyOpinion.morale(p) == 0, "a party of one has nobody to get on with")

func test_courtship_gates() -> void:
	var p := _party()
	check(not PartyOpinion.courtship_possible(p, "vera", "ilsa"), "not at baseline")
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN - 1)
	check(not PartyOpinion.courtship_possible(p, "vera", "ilsa"), "not one point short of the line")
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN)
	check(PartyOpinion.courtship_possible(p, "vera", "ilsa"), "at the line, possible")
	check(PartyOpinion.courtship_possible(p, "ilsa", "vera"), "...either way round")
	p.get_member("ilsa").dead = true
	check(not PartyOpinion.courtship_possible(p, "vera", "ilsa"), "not with the dead")
	p.get_member("ilsa").dead = false
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.COURTSHIP_MIN)
	PartyOpinion.answer_courtship(p, "vera", "pike", true)
	check(not PartyOpinion.courtship_possible(p, "vera", "ilsa"), "Vera is spoken for")
	check(PartyOpinion.partner(p, "vera") == "pike" and PartyOpinion.partner(p, "pike") == "vera"
		and PartyOpinion.partner(p, "ilsa") == "", "partner() reads both ways and nobody else's")

func test_courtship_answers() -> void:
	var p := _party()
	check(PartyOpinion.answer_courtship(p, "vera", "ilsa", true).is_empty(), "an answer nobody was asked for does nothing")
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN)
	var r: Dictionary = PartyOpinion.answer_courtship(p, "vera", "ilsa", false)
	check(r["status"] == "declined" and PartyOpinion.score(p, "vera", "ilsa")
		== PartyOpinion.COURTSHIP_MIN - PartyOpinion.COURTSHIP_DECLINED, "declined: remembered, and a little awkward")
	check(PartyOpinion.band(p, "vera", "ilsa") == "bonded", "...but still bonded — a no is not a feud")
	check(not PartyOpinion.courtship_possible(p, "vera", "ilsa"), "the fire does not ask that pair again")
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.COURTSHIP_MIN)
	r = PartyOpinion.answer_courtship(p, "vera", "pike", true)
	check(r["status"] == "lovers" and r["band"] == "lovers", "accepted: lovers")
	check(PartyOpinion.score(p, "vera", "pike") == PartyOpinion.COURTSHIP_MIN + PartyOpinion.COURTSHIP_ACCEPTED,
		"...and warmer for it")
	check(PartyOpinion.is_close(p, "vera", "pike") and "pike" in PartyOpinion.close_to(p, "vera"),
		"lovers count as close for every hook that asks")

func test_breakup() -> void:
	var p := _party()
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.COURTSHIP_MIN)
	PartyOpinion.answer_courtship(p, "vera", "pike", true)
	var r: Dictionary = PartyOpinion.adjust(p, "vera", "pike", -20.0)
	check(not r["broke_up"] and PartyOpinion.band(p, "vera", "pike") == "lovers",
		"lovers weather a bad patch")
	var before := PartyOpinion.score(p, "vera", "pike")
	r = PartyOpinion.adjust(p, "vera", "pike", -100.0)
	check(r["broke_up"], "...but not falling all the way to nothing")
	check(PartyOpinion.status(p, "vera", "pike") == "" and PartyOpinion.partner(p, "vera") == "",
		"lovers no longer")
	check(PartyOpinion.score(p, "vera", "pike") == before - 100.0 - PartyOpinion.BREAKUP,
		"and worse than strangers for it: the fall plus BREAKUP on top")
	check(PartyOpinion.courtship_possible(p, "vera", "pike") == false, "no courtship at that score")
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.COURTSHIP_MIN)
	check(PartyOpinion.courtship_possible(p, "vera", "pike"), "...but the door is open again if they get back there")

func test_camp_moment_shapes() -> void:
	var p := _party()
	var kinds := {}
	var asked := 0
	var applied := 0
	for seed_v in range(1, 400):
		var q := _party()
		PartyOpinion.set_score(q, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN + 5)
		var before := PartyOpinion.score(q, "vera", "ilsa")
		var m: Dictionary = PartyOpinion.camp_moment(q, RNG.new(seed_v))
		if m.is_empty():
			kinds["none"] = int(kinds.get("none", 0)) + 1
			continue
		kinds[m["kind"]] = int(kinds.get(m["kind"], 0)) + 1
		check(m.has("text") and m["text"].find("%") < 0, "the line is filled in")
		if m["kind"] == "courtship":
			asked += 1
			check(m["options"] == ["accept", "decline"], "a courtship ASKS")
			check(PartyOpinion.score(q, "vera", "ilsa") == before and PartyOpinion.status(q, "vera", "ilsa") == "",
				"...and applies nothing until it is answered")
			check([m["a"], m["b"]] in [["vera", "ilsa"], ["ilsa", "vera"]], "only the eligible pair is asked")
		else:
			applied += 1
			check(absf(float(m["delta"])) == (PartyOpinion.CAMP_QUARREL if m["kind"] == "quarrel" else PartyOpinion.CAMP_WARMING),
				"a warming or a quarrel resolves itself")
			check(PartyOpinion.score(q, m["a"], m["b"]) == float(m["score"]), "and reports the score it left")
	check(kinds.has("none") and kinds.has("warming") and kinds.has("quarrel") and kinds.has("courtship"),
		"all four outcomes come up in 400 camps: %s" % [kinds])
	check(asked > 0 and applied > 0, "both shapes seen")
	# The lean: a pair below 0 quarrels more than it warms, a pair above warms more.
	var cold_q := 0
	var cold_w := 0
	for seed_v in range(1, 400):
		var q := _party()
		p = q
		for pr in PartyOpinion.active_pairs(q):
			PartyOpinion.set_score(q, pr[0], pr[1], -30.0)
		var m: Dictionary = PartyOpinion.camp_moment(q, RNG.new(seed_v))
		if m.get("kind", "") == "quarrel": cold_q += 1
		elif m.get("kind", "") == "warming": cold_w += 1
	check(cold_q > cold_w, "a party that does not get on quarrels at the fire more than it warms (%d vs %d)" % [cold_q, cold_w])

func test_camp_moment_never_asks_twice() -> void:
	for seed_v in range(1, 300):
		var q := _party()
		PartyOpinion.set_score(q, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN + 5)
		PartyOpinion.answer_courtship(q, "vera", "ilsa", false)
		var m: Dictionary = PartyOpinion.camp_moment(q, RNG.new(seed_v))
		if m.get("kind", "") == "courtship":
			check(false, "a declined pair was asked again (seed %d)" % seed_v)
			return
	check(true, "a declined pair is never asked again")

# The audit's §2.6: the fire's lines are picked by the pair's temperaments.
# Every pairing of the eight — and a pair where one or both hold none — has
# several lines of every kind, each filled with both names and nothing left
# over, and a pairing's lines are its own (Brave and Craven do not hear what
# two Calm heroes hear).
const Traits = preload("res://core/traits.gd")

func test_camp_lines_by_temperament() -> void:
	var tempers: Array = Traits.of_family("temperament")
	tempers.append("")   # a hero from before traits
	var a := _demo("anna", "human", "farmer")
	var b := _demo("bram", "human", "farmer")
	var thin := []
	var unfilled := []
	for ta in tempers:
		for tb in tempers:
			Traits.set_family(a, "temperament", ta)
			Traits.set_family(b, "temperament", tb)
			for kind in ["warming", "quarrel", "courtship"]:
				var ls: Array = PartyOpinion.lines_for(a, b, kind)
				var want := 2 if (ta == "" and tb == "" and kind == "courtship") else 3
				if ls.size() < want:
					thin.append("%s|%s %s (%d)" % [ta, tb, kind, ls.size()])
				for l in ls:
					var t := String(l[0])
					if not ("{a}" in t and "{b}" in t) or "%s" in t:
						unfilled.append(t)
	check(thin.is_empty(), "every pairing has several lines of every kind: %s" % str(thin))
	check(unfilled.is_empty(), "every line names both of them, {a} and {b}: %s" % str(unfilled))
	Traits.set_family(a, "temperament", "brave")
	Traits.set_family(b, "temperament", "craven")
	var bc := PartyOpinion.lines_for(a, b, "quarrel").map(func(l): return l[0])
	Traits.set_family(a, "temperament", "calm")
	Traits.set_family(b, "temperament", "calm")
	var cc := PartyOpinion.lines_for(a, b, "quarrel").map(func(l): return l[0])
	var shared := bc.filter(func(l): return l in cc)
	check(shared.is_empty(), "Brave and Craven quarrel differently from two Calm heroes")
	for l in PartyOpinion.PAIR_LINES["brave|craven"]["quarrel"]:
		check(l in bc, "the opposed pair hears its own lines")
	# With none held on either side, the old shared lines.
	Traits.set_family(a, "temperament", "")
	Traits.set_family(b, "temperament", "")
	check(PartyOpinion.lines_for(a, b, "warming").map(func(l): return l[0]) == PartyOpinion.LINES["warming"],
		"no temperaments: the shared lines")

# {a} in a line is whoever the moment's "a" is — so the Brave one, in a Brave
# line, whichever of the pair was drawn first; and in a courtship, the asker.
func test_courtship_line_asker_is_a() -> void:
	var p := Party.new()
	var x := _demo("xan", "human", "farmer")
	var y := _demo("yve", "human", "farmer")
	Traits.set_family(x, "temperament", "cautious")
	Traits.set_family(y, "temperament", "brave")
	p.add_member(x)
	p.add_member(y)
	var seen := 0
	for s in range(1, 300):
		PartyOpinion.set_score(p, "xan", "yve", PartyOpinion.COURTSHIP_MIN + 5)
		p.relations[PartyOpinion.key("xan", "yve")]["status"] = ""
		var m: Dictionary = PartyOpinion.camp_moment(p, RNG.new(s))
		if m.get("kind", "") != "courtship":
			continue
		seen += 1
		var asker: String = m["a_name"]
		var ok := false
		for pool in [PartyOpinion.TEMPER_LINES["brave"]["courtship"], PartyOpinion.TEMPER_LINES["cautious"]["courtship"]]:
			for l in pool:
				var want: String = String(l)
				var holder := "Yve" if pool == PartyOpinion.TEMPER_LINES["brave"]["courtship"] else "Xan"
				if want.replace("{a}", holder).replace("{b}", "Xan" if holder == "Yve" else "Yve") == m["text"]:
					ok = holder == asker
		check(ok, "the one who asks in the line is the moment's a (%s): %s" % [asker, m["text"]])
	check(seen > 0, "courtships came up (%d)" % seen)

func test_headers_are_current() -> void:
	for path in ["res://core/party_opinion.gd", "res://core/callings.gd"]:
		var src := FileAccess.get_file_as_string(path)
		check(not "player-made" in src, "%s no longer says every member is player-made" % path)

# A real Combat on a real board: the three hooks answer off positions and bands.
func _fight(p: Party) -> Combat:
	var spec := {"theme": "sunken-shrine", "seed": 7, "monsters": [{"id": "goblin", "count": 2}]}
	return Encounter.build(spec, p.to_combatants(Encounter.PARTY_STARTS))

func _c(cb: Combat, id: String):
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

func test_combat_hooks() -> void:
	var p := _party()
	var cb := _fight(p)
	var vera = _c(cb, "vera")
	var pike = _c(cb, "pike")
	var ilsa = _c(cb, "ilsa")
	var foe = cb.team_of("foe")[0]
	check(vera != null and pike != null and ilsa != null, "the presets are on the board")
	# neutral party: every hook is inert
	vera.pos = Vector2i(2, 0); ilsa.pos = Vector2i(2, 1); pike.pos = Vector2i(2, 2)
	check(PartyOpinion.shoulder_bonus(p, vera, cb) == 0 and PartyOpinion.bicker_penalty(p, vera, cb) == 0,
		"nothing between them: no bonus, no penalty")
	check(PartyOpinion.rally(p, vera, cb).is_empty(), "nobody rallies to a stranger")
	check(PartyOpinion.shoulder_bonus(p, foe, cb) == 0 and PartyOpinion.bicker_penalty(p, foe, cb) == 0
		and PartyOpinion.rally(p, foe, cb).is_empty(), "foes have no relations")
	# bonded, adjacent
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.BONDED)
	check(PartyOpinion.shoulder_bonus(p, vera, cb) == PartyOpinion.SHOULDER_AC
		and PartyOpinion.shoulder_bonus(p, ilsa, cb) == PartyOpinion.SHOULDER_AC, "bonded and adjacent: +1 AC each")
	check(PartyOpinion.shoulder_bonus(p, pike, cb) == 0, "...not the third who is only next to one of them")
	ilsa.pos = Vector2i(2, 3)
	check(PartyOpinion.shoulder_bonus(p, vera, cb) == 0, "apart: nothing")
	ilsa.pos = Vector2i(2, 1)
	ilsa.statuses["down"] = true
	check(PartyOpinion.shoulder_bonus(p, vera, cb) == 0, "a partner on the ground is no shoulder")
	# ...and that partner going down rallies Vera
	var rallied: Array = PartyOpinion.rally(p, ilsa, cb)
	check(rallied == ["vera"], "Vera rallies when Ilsa falls; Pike (neutral) does not")
	check(vera.has(PartyOpinion.RALLY_STATUS), "the status is on her")
	ilsa.statuses.erase("down")
	# rivals, adjacent
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.RIVALS)
	vera.pos = Vector2i(2, 1); pike.pos = Vector2i(2, 2); ilsa.pos = Vector2i(0, 0)
	check(PartyOpinion.bicker_penalty(p, vera, cb) == PartyOpinion.BICKER_TO_HIT
		and PartyOpinion.bicker_penalty(p, pike, cb) == PartyOpinion.BICKER_TO_HIT, "rivals adjacent: -1 to hit each")
	pike.pos = Vector2i(4, 0)
	check(PartyOpinion.bicker_penalty(p, vera, cb) == 0, "apart: they can behave")

func test_rally_status_survives_new_turn() -> void:
	# Rally keeps its own status rather than riding Help's "helped": Help's is
	# the helper's to take back (combat._release_helps, 2024 RAW), a rally is
	# nobody's. Both survive the bearer's own turn reset.
	var p := _party()
	var cb := _fight(p)
	var vera = _c(cb, "vera")
	vera.statuses["helped"] = {"by": _c(cb, "ilsa")}
	vera.statuses[PartyOpinion.RALLY_STATUS] = true
	vera.new_turn()
	check(vera.has("helped"), "Help's advantage survives the ally's own turn reset (the helper's next turn ends it)")
	check(vera.has(PartyOpinion.RALLY_STATUS), "a rally does too")

func test_save_round_trip() -> void:
	var p := _party()
	PartyOpinion.set_score(p, "vera", "ilsa", PartyOpinion.COURTSHIP_MIN)
	PartyOpinion.answer_courtship(p, "vera", "ilsa", true)
	PartyOpinion.set_score(p, "vera", "pike", -33.5)
	var d := PartyOpinion.to_dict(p)
	var json := JSON.stringify(d)
	var back = JSON.parse_string(json)
	var q := _party()
	PartyOpinion.from_dict(q, back)
	check(PartyOpinion.status(q, "vera", "ilsa") == "lovers" and PartyOpinion.score(q, "vera", "ilsa")
		== PartyOpinion.COURTSHIP_MIN + PartyOpinion.COURTSHIP_ACCEPTED, "lovers survive JSON")
	check(PartyOpinion.score(q, "vera", "pike") == -33.5, "so does a plain score")
	check(PartyOpinion.score(q, "pike", "ilsa") == PartyOpinion.baseline_of(q, "pike", "ilsa"),
		"an unrecorded pair is still at baseline after a load")
	PartyOpinion.from_dict(q, {"vera|pike": {"score": 900.0}, "junk": 3, "x|y": "no"})
	check(PartyOpinion.score(q, "vera", "pike") == PartyOpinion.RANGE and q.relations.size() == 1,
		"a hand-edited save is clamped and its junk dropped")
	PartyOpinion.from_dict(q, null)
	check(q.relations.is_empty(), "an old save with no relations loads as a fresh party")
