# #176 — three things the traits design needs the fight to tell the truth about,
# found while surveying its hooks (docs/superpowers/specs/2026-09-23-traits-design.md
# §9 step 0). The model only, headless:
#   1. a hero's own resistances reach the Combatant (a dwarf's poison),
#   2. the odds chip counts every term the roll counts (hit_chance vs resolve_attack),
#   3. the fight records who killed what, what put a hero down, and who got them up.
#   godot --headless --path . -s tests/test_combat_credit.gd
extends SceneTree

const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Character = preload("res://core/character.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Encounter = preload("res://core/encounter.gd")
const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Dice = preload("res://core/dice.gd")
const RNG = preload("res://core/rng.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_hero_resistances_reach_the_fight()
	test_odds_chip_agrees_with_the_roll()
	test_credit_kills_downs_and_revivals()
	test_credit_rides_the_outcome()
	print("test_combat_credit: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func _fight(p: Party) -> Combat:
	var spec := {"theme": "sunken-shrine", "seed": 7, "monsters": [{"id": "goblin", "count": 2}]}
	var cb := Encounter.build(spec, p.to_combatants(Encounter.PARTY_STARTS))
	cb.party = p
	return cb

func _c(cb: Combat, id: String):
	for c in cb.combatants:
		if c.id == id:
			return c
	return null

func test_hero_resistances_reach_the_fight() -> void:
	var dwarf := Character.new()
	dwarf.id = "brenna"
	dwarf.cname = "Brenna"
	dwarf.species_id = "dwarf"
	dwarf.background_id = "soldier"
	dwarf.add_level("fighter", -1)
	check("poison" in dwarf.sheet().resistances, "the sheet has the dwarf's poison resistance (it always did)")
	var c = Adapter.to_combatant(dwarf, "party", Vector2i.ZERO)
	check("poison" in c.resist, "...and now so does the Combatant")
	var human = Adapter.to_combatant(Presets.party()[0], "party", Vector2i.ZERO)
	check(human.resist.is_empty() and human.immune.is_empty(), "a human carries no defences in")
	var cb := Combat.new(RNG.new(1), [c], {})
	check(cb._damage_after_defenses(c, 10, "poison") == 5, "10 poison lands as 5 on a dwarf")
	check(cb._damage_after_defenses(c, 10, "fire") == 10, "...and 10 fire as 10")
	check(c.clone().resist == c.resist, "a clone keeps them")

func test_odds_chip_agrees_with_the_roll() -> void:
	var p := _party()
	var cb := _fight(p)
	var vera = _c(cb, "vera")
	var pike = _c(cb, "pike")
	var foe = cb.team_of("foe")[0]
	vera.pos = Vector2i(2, 0)
	pike.pos = Vector2i(2, 1)
	foe.pos = Vector2i(3, 0)
	var plain: int = cb.to_hit_bonus(vera, foe)
	check(plain == vera.atk_bonus + cb.high_ground(vera, foe), "nothing on her: the weapon's bonus and the ground")

	vera.statuses["spell:bless-ish"] = {"bonus_to_hit": 2}
	check(cb.to_hit_bonus(vera, foe) == plain + 2, "a bonus_to_hit status counts")
	PartyOpinion.set_score(p, "vera", "pike", PartyOpinion.RIVALS - 5)
	check(cb.to_hit_bonus(vera, foe) == plain + 2 - PartyOpinion.BICKER_TO_HIT, "a rival at her elbow counts")
	check(cb.to_hit_bonus(vera, foe, {"opportunity": true}) == plain + 2,
		"...but not on an opportunity attack, which the roll never charged it on")

	# The chip is the same arithmetic as the roll, read off the same terms.
	var mode: int = cb._attack_mode(vera, foe)
	var need: int = cb.effective_ac(foe) - cb.to_hit_bonus(vera, foe)
	var p_hit: float = clampf((21.0 - need) / 20.0, 0.05, 0.95)
	if mode == Dice.ADV:
		p_hit = 1.0 - (1.0 - p_hit) * (1.0 - p_hit)
	elif mode == Dice.DIS:
		p_hit = p_hit * p_hit
	check(is_equal_approx(cb.hit_chance(vera, foe), p_hit), "hit_chance is built on to_hit_bonus")

	# ...and the roll adds exactly that (no Inspiration on her to add a die).
	var expected: int = cb.to_hit_bonus(vera, foe)
	var r: Dictionary = cb.resolve_attack(vera, foe, {"free": true, "no_mastery": true})
	check(not r.has("error") and int(r["bonus"]) == expected,
		"the roll's bonus is the chip's bonus (%s vs %d)" % [str(r.get("bonus")), expected])

	# A rally is advantage, and the chip shows it now.
	vera.statuses.erase("spell:bless-ish")
	PartyOpinion.set_score(p, "vera", "pike", 0.0)
	var before: float = cb.hit_chance(vera, foe)
	vera.statuses[PartyOpinion.RALLY_STATUS] = true
	check(cb.hit_chance(vera, foe) >= before, "a rallied swing is never shown as worse")
	if cb._attack_mode(vera, foe) == Dice.NORMAL and before < 0.95:
		check(cb.hit_chance(vera, foe) > before, "...and shown as better when nothing else is in play")

func test_credit_kills_downs_and_revivals() -> void:
	var p := _party()
	var cb := _fight(p)
	var vera = _c(cb, "vera")
	var ilsa = _c(cb, "ilsa")
	var foes: Array = cb.team_of("foe")
	var foe = foes[0]
	check(cb.credit.is_empty(), "nothing has happened yet")

	foe.hp = 1
	cb._apply_damage(foe, 5, "slashing", false, vera)
	check(foe.is_dead(), "the goblin is dead")
	check(cb.credit.get("vera", {}).get("kills", []) == ["goblin"], "...and it is Vera's kill, by bestiary id")
	cb._apply_damage(foe, 5, "slashing", false, ilsa)
	check(not cb.credit.has("ilsa"), "hitting a corpse kills nothing")

	var other = foes[1]
	other.hp = 1
	cb._apply_damage(other, 5, "fire")
	check(other.is_dead() and cb.credit.get("vera", {}).get("kills", []).size() == 1,
		"a blow that names nobody credits nobody")

	vera.hp = 3
	cb._apply_damage(vera, 5, "fire", false, other)
	check(vera.is_down(), "Vera is down")
	var by: Array = cb.credit["vera"]["downed_by"]
	check(by.size() == 1 and by[0]["dtype"] == "fire" and by[0]["by"] == "goblin" and by[0]["team"] == "foe",
		"what put her down: fire, from a goblin")
	cb._apply_damage(vera, 1, "fire", false, other)
	check(cb.credit["vera"]["downed_by"].size() == 1, "a blow on a body already down is not a second downing")

	cb.heal(vera, 4, ilsa)
	check(vera.conscious() and cb.credit["vera"]["revived_by"] == ["ilsa"], "Ilsa got her up, and it is written down")
	cb.heal(vera, 4, ilsa)
	check(cb.credit["vera"]["revived_by"].size() == 1, "healing someone already up is not a revival")

func test_credit_rides_the_outcome() -> void:
	var p := _party()
	var cb := _fight(p)
	var vera = _c(cb, "vera")
	for f in cb.team_of("foe"):
		f.hp = 1
		cb._apply_damage(f, 5, "slashing", false, vera)
	var out: Dictionary = Encounter.resolve_outcome(cb, p)
	check(out.has("credit") and out["credit"]["vera"]["kills"].size() == 2, "the fight result carries the credit")
	cb.credit["vera"]["kills"].clear()
	check(out["credit"]["vera"]["kills"].size() == 2, "...as a copy, not the live Combat's own")
