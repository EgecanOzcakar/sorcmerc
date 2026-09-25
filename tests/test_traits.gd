# #176 step 1 — personality traits: the data, the pick, the save shape, and the
# half of a trait decided where the fight is (core/traits.gd). Headless.
#   godot --headless --path . -s tests/test_traits.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const Save = preload("res://core/character_save.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Catalog = preload("res://core/rules/catalog.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_data_is_whole()
	test_pick_and_defaults()
	test_save_round_trip()
	test_the_fight_reads_the_place()
	test_the_cap()
	print("test_traits: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _hero(id: String, bg := "soldier") -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = bg
	ch.add_level("fighter", -1)
	return ch

func test_data_is_whole() -> void:
	check(Traits.of_family("temperament").size() == 8, "eight temperaments")
	check(Traits.of_family("origin").size() == 6, "six origins")
	for id in Traits.all():
		var r: Dictionary = Traits.row(id)
		check(String(r.get("name", "")) != "" and String(r.get("text", "")) != "", "%s has a name and a line" % id)
		for o in r.get("opposes", []):
			check(id in Traits.row(o).get("opposes", []), "%s and %s oppose each other both ways" % [id, o])
		for line in Traits.effect_lines(id):
			check(String(line["text"]).strip_edges() != "", "%s: every effect says something" % id)
		check(Traits.effect_lines(id).any(func(l): return l["live"]) or r["family"] != "origin",
			"%s: an origin always does something in a fight now" % id)
		# Step 3's earned rows: each says what kind of moment it is.
		if r["family"] in ["mark", "bane", "wound"]:
			check(String(r.get("kind", "")) in ["triumph", "resilience", "scar", "wound"], "%s: an earned row has a kind" % id)
	for b in Catalog.all("backgrounds.json"):
		for fam in Traits.FAMILIES:
			var d := Traits.default_for(b["id"], fam)
			check(String(Traits.row(d).get("family", "")) == fam, "%s has a default %s (%s)" % [b["id"], fam, d])
	check(Traits.describe({"when": {"biome": ["marsh"]}, "gives": {"ac": 1}}) == "+1 AC in the marsh", "words: +1 AC in the marsh")
	check(Traits.describe({"when": {"night": false}, "gives": {"initiative": -1}}) == "−1 initiative by day", "words: −1 initiative by day")

func test_pick_and_defaults() -> void:
	var ch := _hero("vera", "soldier")
	check(Traits.ids(ch).is_empty() and Traits.needs_offer(ch), "a hero with no traits is owed the offer")
	Traits.fill_defaults(ch)
	check(Traits.of(ch, "temperament") == "brave" and Traits.of(ch, "origin") == "downs-rider", "a soldier starts Brave and Downs-rider")
	check(not Traits.needs_offer(ch), "...and is owed nothing")
	Traits.set_family(ch, "origin", "marsh-bred")
	check(Traits.of(ch, "origin") == "marsh-bred" and Traits.ids(ch).size() == 2, "picking an origin replaces the old one")
	var prev := ch.background_id
	ch.background_id = "sage"
	Traits.fill_defaults(ch, prev)
	check(Traits.of(ch, "origin") == "marsh-bred", "a background change keeps a choice the player made")
	check(Traits.of(ch, "temperament") == "curious", "...and moves a default that was never touched")
	Traits.set_family(ch, "origin", "brave")
	check(Traits.of(ch, "origin") == "marsh-bred", "a temperament cannot be filed as an origin")
	ch.traits.append({"id": "no-such-trait", "why": ""})
	check(not "no-such-trait" in Traits.ids(ch), "an id the data does not have is skipped, not crashed on")
	check(Traits.opposed("brave", "craven") and not Traits.opposed("brave", "calm"), "Brave and Craven are opposed; Brave and Calm are not")

func test_save_round_trip() -> void:
	var ch := _hero("ilsa", "acolyte")
	Traits.fill_defaults(ch)
	var back = Save.from_dict(Save.to_dict(ch))
	check(Traits.ids(back) == Traits.ids(ch), "traits survive a save: %s" % str(Traits.ids(back)))
	check(back.traits[0].get("why", "") == "born to it", "...with their reason")
	var old: Dictionary = Save.to_dict(_hero("old"))
	old.erase("traits")
	old.erase("traits_offered")
	var from_before = Save.from_dict(old)
	check(from_before.traits.is_empty() and not from_before.traits_offered and Traits.needs_offer(from_before),
		"a save from before traits loads with none, and is owed the offer")
	from_before.traits_offered = true
	check(not Traits.needs_offer(Save.from_dict(Save.to_dict(from_before))), "the offer, once made, is remembered")

func _fight_with(ch: Character, theme: String, where := {}, night := false):
	var spec := {"theme": theme, "seed": 7, "monsters": [{"id": "goblin", "count": 1}], "night": night}
	if not where.is_empty():
		spec["where"] = where
	var cb = Encounter.build(spec, [Adapter.to_combatant(ch, "party", Encounter.PARTY_STARTS[0])])
	for c in cb.combatants:
		if c.id == ch.id:
			return [cb, c]
	return [cb, null]

func test_the_fight_reads_the_place() -> void:
	var ch := _hero("brenna", "sailor")
	Traits.set_family(ch, "origin", "marsh-bred")
	var bare := _hero("plain")
	var base_ac: int = Adapter.to_combatant(bare, "party", Vector2i.ZERO).ac
	var c = Adapter.to_combatant(ch, "party", Vector2i.ZERO)
	check(c.traits == ["marsh-bred"] and c.clone().traits == ["marsh-bred"], "the Combatant carries the ids, and a clone keeps them")

	var r: Array = _fight_with(ch, "marsh", {"biome": "marsh", "band": "heartland", "site": "road"})
	check(r[0].effective_ac(r[1]) - (1 if r[0].is_cover(r[1].pos) else 0) * 2 == base_ac + 1, "Marsh-bred: +1 AC in a marsh fight")
	check(r[0].log.any(func(l): return l.begins_with("Brenna — Marsh-bred here: +1 AC")), "...and the log says so")
	r = _fight_with(ch, "downs", {"biome": "downs", "band": "heartland", "site": "road"})
	check(not r[1].statuses.has(Traits.STATUS), "Marsh-bred on the downs: nothing in a fight")
	r = _fight_with(ch, "marsh")
	check(not r[1].statuses.has(Traits.STATUS), "a fight that does not know its biome fires no biome trait")

	Traits.set_family(ch, "origin", "cave-dweller")
	var cave: Array = _fight_with(ch, "frozen-cave")
	check(cave[1].statuses.get(Traits.STATUS, {}).get("bonus_to_hit", 0) == 1, "Cave-dweller: +1 to hit on the frozen cave, known from the board alone")
	var open_day: Array = _fight_with(ch, "downs")
	check(open_day[1].statuses.get(Traits.STATUS, {}).get("bonus_to_hit", 0) == -1, "...and −1 on an open board by day")
	var open_night: Array = _fight_with(ch, "downs", {}, true)
	check(not open_night[1].statuses.has(Traits.STATUS), "...but not at night")

	Traits.set_family(ch, "origin", "night-owl")
	var plain_init: int = _fight_with(bare, "downs")[1].init_mod
	check(_fight_with(ch, "downs", {}, true)[1].statuses.get(Traits.STATUS, {}).get("bonus_to_hit", 0) == 1, "Night-owl: +1 to hit at night")
	check(_fight_with(ch, "downs")[1].init_mod == plain_init - 1, "...−1 initiative by day")
	# ...and it is the ROLL that moves, not just the modifier after the roll:
	# Combat rolls initiative in its constructor, so the stamp has to land first.
	var owl: Array = _fight_with(ch, "downs")
	check(owl[1].init_roll == _fight_with(bare, "downs")[1].init_roll - 1, "the initiative roll itself is 1 lower (the same seed, the same d20)")
	check(String(owl[0].log[0]).begins_with("Brenna — Night-owl here") and String(owl[0].log[1]).begins_with("Initiative:"),
		"the trait's line comes before the initiative it fed: %s" % str(owl[0].log.slice(0, 2)))

	Traits.set_family(ch, "origin", "")
	Traits.set_family(ch, "temperament", "calm")
	var calm: Array = _fight_with(ch, "downs")
	var plain_con: int = int(_fight_with(bare, "downs")[1].saves.get("con", 0))
	check(int(calm[1].saves.get("con", 0)) == plain_con + 1 and calm[1].init_mod == plain_init - 1,
		"Calm: +1 CON saves and −1 initiative, everywhere")
	check(_fight_with(bare, "marsh", {"biome": "marsh"})[1].statuses.get(Traits.STATUS) == null, "a hero with no traits is untouched")
	# A band is asked as a country (2026-09-25): a trait "in the deeps" holds out
	# in the Unmapped, the Far Deeps' outer half, and not the other way about.
	check(Traits.holds({"band": ["deeps"]}, {"band": "unmapped"}), "\"in the deeps\" holds in the Unmapped")
	check(Traits.holds({"band": ["deeps"]}, {"band": "deeps"}), "...and in the deeps")
	check(not Traits.holds({"band": ["unmapped"]}, {"band": "deeps"}), "\"in the Unmapped\" is only there")
	check(not Traits.holds({"band": ["deeps"]}, {"band": "frontier"}), "...and the frontier is neither")
	check(Traits._road_holds({"band": ["deeps"]}, {"band": "unmapped"}), "the road reads it the same way")

func test_the_cap() -> void:
	Traits.all()["test-a"] = {"name": "A", "family": "mark", "effects": [{"gives": {"ac": 2, "to_hit": -3}}]}
	Traits.all()["test-b"] = {"name": "B", "family": "mark", "effects": [{"gives": {"ac": 2}}]}
	var t: Dictionary = Traits.terms(["test-a", "test-b"], {})
	check(t["ac"] == Traits.CAP and t["to_hit"] == -Traits.CAP, "stacked traits are capped at ±%d (%s)" % [Traits.CAP, str(t)])
	Traits.all().erase("test-a")
	Traits.all().erase("test-b")
