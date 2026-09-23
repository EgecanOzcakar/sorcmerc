# #176 step 2 — the per-roll half of personality traits: what only the roll
# knows (bloodied, the first round, who is on the other end, the damage type),
# asked by core/combat.gd's four hooks (to-hit, AC, saves, damage and ward) and
# answered by core/traits.gd's roll(). Headless.
#   godot --headless --path . -s tests/test_traits_roll.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")
const Dice = preload("res://core/dice.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	# Test-only rows for the conditions step 3's earned traits will stand on.
	Traits.all()["t-orcbane"] = {"name": "Orc-bane", "family": "bane",
		"effects": [{"when": {"vs_faction": ["orc"]}, "gives": {"to_hit": 1, "damage": 1}}]}
	Traits.all()["t-goblin-dread"] = {"name": "Goblin-dread", "family": "mark",
		"effects": [{"when": {"vs_faction": ["goblinoid"]}, "gives": {"ac": -1}}]}
	Traits.all()["t-fire-tempered"] = {"name": "Fire-tempered", "family": "mark",
		"effects": [{"gives": {"ward": 3}, "when": {"dtype_in": ["fire"]}}]}
	Traits.all()["t-blade"] = {"name": "Blade-sworn", "family": "mark",
		"effects": [{"when": {"dtype_out": ["slashing", "bludgeoning", "piercing"]}, "gives": {"to_hit": 1}}]}
	Traits.all()["t-lone"] = {"name": "Lone wolf", "family": "mark",
		"effects": [{"when": {"alone": true}, "gives": {"ac": 1}}]}
	test_craven_and_cautious()
	test_wrathful_damage()
	test_brave_saves()
	test_the_foe_and_the_element()
	test_the_cap_counts_the_stamp()
	test_chip_and_roll_agree()
	for k in ["t-orcbane", "t-goblin-dread", "t-fire-tempered", "t-blade", "t-lone"]:
		Traits.all().erase(k)
	print("test_traits_roll: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _hero(id: String, traits: Array) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = "soldier"
	ch.add_level("fighter", -1)
	for t in traits:
		ch.traits.append({"id": t, "why": "test"})
	return ch

func _fight(ch: Character, foe := "goblin", theme := "downs"):
	var cb = Encounter.build({"theme": theme, "seed": 7, "monsters": [{"id": foe, "count": 1}]},
		[Adapter.to_combatant(ch, "party", Encounter.PARTY_STARTS[0])])
	return [cb, cb.team_of("party")[0], cb.team_of("foe")[0]]

func test_craven_and_cautious() -> void:
	var f: Array = _fight(_hero("pike", ["craven"]))
	var cb = f[0]; var hero = f[1]; var foe = f[2]
	var base_ac: int = cb.effective_ac(hero, foe)
	hero.hp = hero.max_hp / 2 - 1
	check(cb.effective_ac(hero, foe) == base_ac + 1, "Craven: +1 AC while under half HP")
	hero.hp = hero.max_hp
	check(cb.round_num == 1 and int(Traits.roll(hero, "to_hit", cb, foe)["n"]) == -1, "Craven: −1 to hit in the first round")
	cb.round_num = 2
	check(int(Traits.roll(hero, "to_hit", cb, foe)["n"]) == 0, "...and not in the second")
	check("craven" in Traits.live_here(hero, cb), "the card lights a roll-time trait: it can count in this fight")

	var g: Array = _fight(_hero("cass", ["cautious"]))
	var ac1: int = g[0].effective_ac(g[1], g[2])
	g[0].round_num = 2
	check(g[0].effective_ac(g[1], g[2]) == ac1 - 1, "Cautious: +1 AC in the first round only")

func test_wrathful_damage() -> void:
	var f: Array = _fight(_hero("rook", ["wrathful"]))
	var cb = f[0]; var hero = f[1]; var foe = f[2]
	check(int(Traits.roll(hero, "damage", cb, foe)["n"]) == 0, "Wrathful at full HP: nothing")
	hero.hp = 1
	var t: Dictionary = Traits.roll(hero, "damage", cb, foe)
	check(int(t["n"]) == 1 and t["who"] == ["Wrathful"], "Wrathful bloodied: +1 damage, named")
	hero.pos = foe.pos + Vector2i(-1, 0)
	var hit := {}
	for i in 40:   # free swings until one lands, to read its extras
		foe.hp = foe.max_hp
		var r: Dictionary = cb.resolve_attack(hero, foe, {"free": true, "no_mastery": true})
		if r.get("hit", false):
			hit = r
			break
	check(not hit.is_empty() and hit["extras"].any(func(e): return e["label"] == "Wrathful" and int(e["amount"]) == 1),
		"...and a hit carries it as a named rider: %s" % str(hit.get("extras", [])))

func test_brave_saves() -> void:
	var f: Array = _fight(_hero("vera", ["brave"]))
	var cb = f[0]; var hero = f[1]
	check(Traits.save_mode(hero, cb, ["frightened"])["adv"], "Brave: advantage against being frightened")
	check(not Traits.save_mode(hero, cb, ["poisoned"])["adv"], "...and not against anything else")
	cb._saving_throw(hero, 12, "wis", false, true, ["frightened"])
	check(cb.log.any(func(l): return l == "Vera is Brave: advantage."), "the save says so, once")
	var n: int = cb.log.size()
	cb._saving_throw(hero, 12, "wis", false, true, ["frightened"])
	check(cb.log.size() == n, "...and only once a fight")

func test_the_foe_and_the_element() -> void:
	var f: Array = _fight(_hero("brenna", ["t-orcbane"]), "orc")
	var cb = f[0]; var hero = f[1]; var orc = f[2]
	check(int(Traits.roll(hero, "to_hit", cb, orc)["n"]) == 1 and int(Traits.roll(hero, "damage", cb, orc)["n"]) == 1,
		"vs_faction: Orc-bane is +1 to hit and damage against an orc")
	var g: Array = _fight(_hero("brenna", ["t-orcbane"]), "goblin")
	check(int(Traits.roll(g[1], "to_hit", g[0], g[2])["n"]) == 0, "...and nothing against a goblin")

	var d: Array = _fight(_hero("owen", ["t-goblin-dread"]), "goblin")
	check(d[0].effective_ac(d[1], d[2]) == d[0].effective_ac(d[1]) - 1, "an AC trait against a faction needs to know the attacker")

	var w: Array = _fight(_hero("ivo", ["t-fire-tempered"]))
	check(w[0]._damage_after_defenses(w[1], 10, "fire") == 7, "a ward: 10 fire lands as 7")
	check(w[0]._damage_after_defenses(w[1], 10, "cold") == 10, "...10 cold as 10")
	check(w[0]._damage_after_defenses(w[1], 2, "fire") == 0, "...and never below 0")
	w[1].resist.append("fire")
	check(w[0]._damage_after_defenses(w[1], 10, "fire") == 2, "after resistance: halve, then the ward (10 -> 5 -> 2)")
	w[1].resist.clear()
	w[0]._apply_damage(w[1], 10, "fire")
	check(w[0].log.any(func(l): return "shrugs off some of the fire" in l), "the log names the ward, not resistance")

	var b: Array = _fight(_hero("gera", ["t-blade"]))
	check(int(Traits.roll(b[1], "to_hit", b[0], b[2], "slashing")["n"]) == 1, "dtype_out: a slashing swing counts")
	check(int(Traits.roll(b[1], "to_hit", b[0], b[2], "fire")["n"]) == 0, "...a fire bolt does not")

	var lone: Array = _fight(_hero("hale", ["t-lone"]))
	check(int(Traits.roll(lone[1], "ac", lone[0], lone[2])["n"]) == 1, "alone: nobody beside them")

func test_the_cap_counts_the_stamp() -> void:
	Traits.all()["t-cave2"] = {"name": "Deep-born", "family": "mark",
		"effects": [{"when": {"board": ["frozen-cave"]}, "gives": {"to_hit": 2}}]}
	var f: Array = _fight(_hero("mo", ["t-cave2", "craven"]), "goblin", "frozen-cave")
	var cb = f[0]; var hero = f[1]; var foe = f[2]
	check(int(hero.statuses[Traits.STATUS]["bonus_to_hit"]) == 2, "the stamp gave +2 on this board")
	check(int(Traits.roll(hero, "to_hit", cb, foe)["n"]) == -1, "Craven's first-round −1 still counts against it")
	Traits.all()["t-more"] = {"name": "More", "family": "mark", "effects": [{"when": {"first_round": true}, "gives": {"to_hit": 3}}]}
	var g: Array = _fight(_hero("mo", ["t-cave2", "t-more"]), "goblin", "frozen-cave")
	check(int(Traits.roll(g[1], "to_hit", g[0], g[2])["n"]) == 0, "a stamped +2 and a roll +3 are +2 in all: the cap covers both")
	Traits.all().erase("t-cave2")
	Traits.all().erase("t-more")

func test_chip_and_roll_agree() -> void:
	var f: Array = _fight(_hero("pike", ["craven"]))
	var cb = f[0]; var hero = f[1]; var foe = f[2]
	hero.pos = foe.pos + Vector2i(-1, 0)
	var expected: int = cb.to_hit_bonus(hero, foe)
	check(expected == hero.atk_bonus + cb.high_ground(hero, foe) - 1, "to_hit_bonus carries Craven's first-round −1")
	var r: Dictionary = cb.resolve_attack(hero, foe, {"free": true, "no_mastery": true})
	check(int(r.get("bonus", 99)) == expected, "the roll adds exactly what the chip shows (%s vs %d)" % [str(r.get("bonus")), expected])
	check(cb.log.any(func(l): return l == "Pike is Craven: -1 to hit."), "and the log says why, once")
	var monster_only: Array = _fight(_hero("nobody", []))
	check(int(Traits.roll(monster_only[2], "to_hit", monster_only[0], monster_only[1])["n"]) == 0, "a goblin has no traits to ask")
