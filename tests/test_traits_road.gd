# #176 step 4 — personality traits off the fight board: the road's checks
# (a skill's term where the party is, the approach, the road's events, forage,
# the watch, a lair's search), the purse (Greedy, Generous), how the company
# gets on (shared and opposed temperaments, Greedy, Arrogant, Generous's drift,
# a Wrathful caster's friendly fire), and the line said at the fire about a
# trait somebody earned. Headless.
#   godot --headless --path . -s tests/test_traits_road.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const CharacterSave = preload("res://core/character_save.gd")
const Campaign = preload("res://core/campaign.gd")
const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Approach = preload("res://core/approach.gd")
const Travel = preload("res://core/travel.gd")
const World = preload("res://core/world.gd")
const WorldForage = preload("res://core/world_forage.gd")
const WorldCamp = preload("res://core/world_camp.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Visit = preload("res://core/settlement_visit.gd")
const EventCard = preload("res://scenes/world/event_card.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_skill_terms()
	test_the_checks_read_them()
	test_the_purse()
	test_opinion()
	test_camp_beat()
	print("test_traits_road: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _hero(id: String, traits := [], bg := "soldier") -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = bg
	ch.add_level("fighter", -1)
	for t in traits:
		ch.traits.append({"id": t, "why": "test"})
	return ch

func _party(chars: Array) -> Party:
	var p := Party.new()
	for ch in chars:
		p.add_member(ch)
	return p

const MARSH := {"biome": "marsh", "band": "heartland", "site": "road", "night": false}
const DOWNS := {"biome": "downs", "band": "heartland", "site": "road", "night": false}

func test_skill_terms() -> void:
	var m := _hero("brenna", ["marsh-bred"])
	check(Traits.skill_term(m, "survival", MARSH)["n"] == 2, "Marsh-bred: +2 Survival in the marsh")
	check(Traits.skill_term(m, "survival", DOWNS)["n"] == -1, "...−1 on the downs")
	check(Traits.skill_term(m, "survival", {})["n"] == 0, "...and nothing where the party is not known")
	check(Traits.skill_term(m, "survival", MARSH)["who"] == ["Marsh-bred"], "the term says who gave it")
	var s := _hero("pike", ["street-raised", "wrathful"])
	check(Traits.skill_term(s, "persuasion", DOWNS)["n"] == 0, "Street-raised +2 and Wrathful −2 on Persuasion: even")
	check(Traits.skill_term(s, "survival", DOWNS)["n"] == -2, "Street-raised: −2 Survival on the road")
	check(Traits.skill_term(s, "survival", MARSH.merged({"site": "town"}, true))["n"] == 0, "...but not in town")
	check(Traits.skill_term(_hero("vera", ["brave"]), "avoid", DOWNS)["n"] == -2, "Brave: −2 on slipping past a band")
	check(Traits.road_term(_hero("r", ["downs-rider"]), "travel", MARSH)["n"] == 1, "Downs-rider: +1 on the road's checks, anywhere")
	check(Traits.road_term(_hero("c", ["cautious"]), "travel", MARSH)["n"] == -1, "Cautious: −1 (stops to look at everything)")
	check(Traits.road_term(_hero("w", ["woods-born"]), "forage", {"biome": "woods"})["n"] == 2, "Woods-born: +2 to forage in the woods")
	check(Traits.road_term(_hero("w", ["woods-born"]), "forage", MARSH)["n"] == 0, "...and nothing in the marsh")
	for id in ["street-raised", "marsh-bred", "curious", "greedy", "generous", "renowned", "steady-hands"]:
		check(Traits.effect_lines(id).all(func(l): return l["live"]) or id in ["renowned", "curious"],
			"%s: every effect in play now" % id)

func test_the_checks_read_them() -> void:
	# Campaign.skill_bonus: the sheet and the term where the party stands.
	var m := _hero("brenna", ["marsh-bred"])
	var plain := _hero("plain")
	var p := _party([m, plain])
	var c = Campaign.new(p)
	var sheet: int = int(m.sheet().skills.get("survival", 0))
	p.here = MARSH
	check(c.skill_bonus("brenna", "survival") == sheet + 2, "skill_bonus reads party.here: +2 in the marsh")
	p.here = DOWNS
	check(c.skill_bonus("brenna", "survival") == sheet - 1, "...−1 on the downs")
	check(c.skill_bonus("brenna", "survival", MARSH) == sheet + 2, "...and a check can say where it is made")
	# The watch is kept at camp: Street-raised is lost out there.
	var sr := _hero("pike", ["street-raised"])
	var p2 := _party([sr])
	p2.here = DOWNS.merged({"site": "town"}, true)
	var w: Dictionary = WorldCamp.watch_check(p2, RNG.new(3))
	var want := maxi(int(sr.sheet().skills.get("survival", 0)) - 2, int(sr.sheet().skills.get("perception", 0)))
	check(int(w["bonus"]) == want, "the watch counts as camp, not town — Survival −2 there (%d vs %d)" % [int(w["bonus"]), want])
	check(Campaign.new(p2).skill_bonus("pike", "survival", p2.here.merged({"site": "camp"}, true))
		== int(sr.sheet().skills.get("survival", 0)) - 2, "...which is Street-raised's −2 in the wild")
	# The approach: Brave slips past worse.
	var brave := _party([_hero("vera", ["brave"])])
	var calm := _party([_hero("vera")])
	brave.here = DOWNS
	calm.here = DOWNS
	var foe := World.RoamingParty.new("band", Vector2.ZERO, "goblinoid", false)
	var bo: Dictionary = Approach.options(brave, foe).filter(func(o): return o["id"] == "avoid")[0]
	var co: Dictionary = Approach.options(calm, foe).filter(func(o): return o["id"] == "avoid")[0]
	check(int(bo["bonus"]) == int(co["bonus"]) - 2, "the approach card's avoid is 2 worse for a Brave scout (%d vs %d)" % [bo["bonus"], co["bonus"]])
	# Forage: Woods-born in the woods.
	var wb := _party([_hero("wren", ["woods-born"])])
	var wn := _party([_hero("wren")])
	wb.here = {"biome": "woods", "site": "road"}
	wn.here = wb.here
	check(int(WorldForage.check(wb, RNG.new(5))["bonus"]) == int(WorldForage.check(wn, RNG.new(5))["bonus"]) + 2,
		"forage: +2 for Woods-born in the woods")
	# A lair's search: Curious reads the ground too.
	var cu := _party([_hero("ilsa", ["curious"])])
	var nc := _party([_hero("ilsa")])
	check(int(WorldLairs.search_roll(cu, RNG.new(7))["bonus"]) == int(WorldLairs.search_roll(nc, RNG.new(7))["bonus"]) + 2,
		"a lair's search: +2 for a Curious hero")
	# The road's events: the roller's travel term, named on the card.
	var w0 := World.new()
	w0.add_settlement(World.Settlement.new("riverhold", Vector2.ZERO, "human", "city"))
	w0.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	var dr := _party([_hero("rider", ["downs-rider"])])
	dr.here = DOWNS
	var e := {}
	for seed_v in range(1, 400):
		e = Travel.check(dr, w0, RNG.new(seed_v))
		if e.has("trait_term"):
			break
	check(e.get("trait_term", {}).get("n", 0) == 1 and e["trait_term"]["who"] == ["Downs-rider"], "a road event carries the roller's travel term: %s" % str(e.get("trait_term")))
	var card := EventCard.new()
	card._e = e
	check("(Downs-rider +1)" in card._roll_text(), "...and the card's roll line names it: %s" % card._roll_text())
	card.free()

func test_the_purse() -> void:
	check(Traits.party_pct(_party([_hero("g", ["greedy"]), _hero("h")]), "gold") == 10, "a Greedy hero: +10% of a fight's purse")
	check(Traits.party_pct(_party([_hero("g", ["greedy"]), _hero("h", ["greedy"])]), "gold") == 10, "...two do not stack")
	var m := {"markup": 1.0}
	var gen := _party([_hero("g", ["generous"])])
	var none := _party([_hero("g")])
	var full: int = Visit.sell_price(m, "longsword", none)
	var cheap: int = Visit.sell_price(m, "longsword", gen)
	check(full > 1 and cheap < full and absi(cheap - int(round(full * 0.9))) <= 1,
		"a Generous hero lets things go 10%% cheaper: %d vs %d" % [cheap, full])
	check(Visit.sell_price(m, "longsword") == full, "...and nobody else's price moves")

func test_opinion() -> void:
	var b := _hero("a", ["brave"])
	var cr := _hero("b", ["craven"])
	var b2 := _hero("c", ["brave"])
	var plain := _hero("d")
	var base := PartyOpinion.baseline(_hero("x"), _hero("y"))
	check(is_equal_approx(PartyOpinion.baseline(b, cr), base - 10.0), "Brave and Craven: −10 (%.0f vs %.0f)" % [PartyOpinion.baseline(b, cr), base])
	check(is_equal_approx(PartyOpinion.baseline(b, b2), base + 5.0), "two Brave: +5")
	check(is_equal_approx(PartyOpinion.baseline(b, plain), base), "Brave and nobody in particular: as before")
	var g := _hero("e", ["greedy"])
	var g2 := _hero("f", ["greedy"])
	check(is_equal_approx(PartyOpinion.baseline(g, plain), base - 5.0), "Greedy: −5 with a hero who is not")
	check(is_equal_approx(PartyOpinion.baseline(g, g2), base + 5.0), "...two Greedy understand each other (+5 shared, no cost)")
	var ar := _hero("h", ["arrogant"])
	check(is_equal_approx(PartyOpinion.baseline(ar, plain), base - 5.0), "Arrogant: −5 with everyone")
	check("Brave and Craven" in Traits.opinion_terms(b, cr)["why"], "the pull says why: %s" % str(Traits.opinion_terms(b, cr)["why"]))
	var pp := _party([b, cr])
	check(PartyOpinion.describe(pp, "a", "b").ends_with(": Brave and Craven"), "...and the party page's line names it: %s" % PartyOpinion.describe(pp, "a", "b"))
	# A Wrathful caster's friendly fire costs half again.
	var w := _hero("w", ["wrathful"])
	var v := _hero("v")
	var calm := _hero("k")
	var p := _party([w, v, calm])
	var before := PartyOpinion.score(p, "w", "v")
	PartyOpinion.friendly_fire(p, "w", "v")
	var hot := before - PartyOpinion.score(p, "w", "v")
	before = PartyOpinion.score(p, "k", "v")
	PartyOpinion.friendly_fire(p, "k", "v")
	var cool := before - PartyOpinion.score(p, "k", "v")
	check(is_equal_approx(hot, cool * 1.5), "a Wrathful caster's friendly fire: half again (%.1f vs %.1f)" % [hot, cool])
	# Generous warms a day faster; it does not cool faster.
	var gn := _hero("gn", ["generous"])
	var o := _hero("o")
	var o2 := _hero("o2")
	var p2 := _party([gn, o, o2])
	PartyOpinion.set_score(p2, "gn", "o", -20.0)
	PartyOpinion.set_score(p2, "o2", "o", -20.0)
	PartyOpinion.decay(p2, PartyOpinion.DAY)
	var up_g := PartyOpinion.score(p2, "gn", "o") + 20.0
	var up_p := PartyOpinion.score(p2, "o2", "o") + 20.0
	check(is_equal_approx(up_g, up_p * 2.0), "Generous: opinion of them warms twice as fast (%.1f vs %.1f a day)" % [up_g, up_p])

func test_camp_beat() -> void:
	var ch := _hero("pike")
	Traits.grant(ch, "burn-shy", "t", 100.0)
	var beat := Traits.camp_beat([ch], 200.0)
	check(String(beat.get("text", "")) == "Pike sits well back from the fire tonight, and doesn't eat.", "a scar is said at the fire: %s" % beat.get("text", ""))
	check(beat.get("kind") == "bad", "...as a hard night")
	check(Traits.camp_beat([ch], 300.0).is_empty(), "...once")
	var back = CharacterSave.from_dict(JSON.parse_string(JSON.stringify(CharacterSave.to_dict(ch))))
	check(Traits.camp_beat([back], 300.0).is_empty(), "...and a save remembers it was said")
	var old := _hero("vera")
	Traits.grant(old, "fire-tempered", "t", 0.0)
	check(Traits.camp_beat([old], 10 * Traits.DAY).is_empty(), "a trait earned a week ago is old news")
	var chosen := _hero("ilsa", ["brave"])
	check(Traits.camp_beat([chosen], 0.0).is_empty(), "a trait picked at creation has no night of its own")
	var g := _hero("thrun")
	Traits.grant(g, "grudge@goblinoid", "t", 0.0)
	check("goblins" in String(Traits.camp_beat([g], 1.0).get("text", "")), "an instanced trait names its faction at the fire")
