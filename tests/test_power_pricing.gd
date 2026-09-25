# The design audit §7.4: what core/rules/power.gd (and, for the company's own
# bonds, core/regions.gd's fresh_score) now prices that it used to read as
# nothing — Quickened Spell, a potion still running from the road, and a bond
# between two companions — and the one thing measured and left unpriced
# (weapon mastery). The sizes are tests/sweep_metamagic.gd's and
# tests/sweep_unpriced.gd's; this only holds the prices in place.
#   godot --headless --path . -s tests/test_power_pricing.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Character = preload("res://core/character.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const Encounter = preload("res://core/encounter.gd")
const Party = preload("res://core/party.gd")
const PartyOpinion = preload("res://core/party_opinion.gd")
const Potions = preload("res://core/potions.gd")
const Power = preload("res://core/rules/power.gd")
const Presets = preload("res://core/presets.gd")
const Regions = preload("res://core/regions.gd")
const RNG = preload("res://core/rng.gd")
const Scaler = preload("res://core/scaler.gd")
const WorldThreat = preload("res://core/world_threat.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_quickened()
	test_road_buffs()
	test_bonds()
	test_mastery_stays_unpriced()
	print("test_power_pricing: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# A sorcerer of `level` who picked `options` at level 2, a damage list prepared.
func _sorcerer(level: int, options: Array):
	var ch := Character.new()
	ch.id = "sorc"
	ch.cname = "Sorc"
	ch.species_id = "human"
	ch.background_id = "sage"
	ch.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	for i in level:
		ch.add_level("sorcerer", -1)
	for i in options.size():
		ch.decide("feature-choice:class:sorcerer:%d" % i, {"type": "feature-choice", "optionId": "%s-spell" % options[i]})
	for p in ch.sheet().pending:
		if String(p["key"]) == "spell-choice:class:sorcerer:0":
			ch.decide(p["key"], Creator.decision_for(p, ["fire-bolt", "ray-of-frost", "shocking-grasp", "mind-sliver"]))
	ch.prepared.assign(["burning-hands", "chromatic-orb", "scorching-ray"])
	ch.dirty()
	return Adapter.to_combatant(ch, "party", Vector2i.ZERO)

func test_quickened() -> void:
	var quick = _sorcerer(3, ["quickened", "twinned"])
	var plain = _sorcerer(3, ["careful", "subtle"])
	check(Power.quickened_turns(plain, 6) == 0, "no Quickened, no quickened turns")
	check(Power.quickened_turns(quick, 6) == 1, "3 sorcery points buy one Quickened turn (%d)" % Power.quickened_turns(quick, 6))
	check(Power.quickened_turns(quick, 0) == 0, "and none without a leveled slot to quicken")
	quick.pools["sorcery-points"]["cur"] = 20
	check(Power.quickened_turns(quick, 9) == Power.ROUNDS, "never more than a fight's ROUNDS")
	quick.pools["sorcery-points"]["cur"] = 3
	var q: float = float(Power.estimate(quick)["score"])
	var p: float = float(Power.estimate(plain)["score"])
	check(q > p * 1.02, "a sorcerer who knows Quickened is priced above one who does not (%.1f vs %.1f)" % [q, p])
	quick.pools["sorcery-points"]["cur"] = 0
	check(is_equal_approx(float(Power.estimate(quick)["score"]), p),
		"...by the points it holds: with none left the two read the same")

func test_road_buffs() -> void:
	var vera = Presets.vera()
	var bare = Adapter.to_combatant(vera, "party", Vector2i.ZERO)
	check(Power.road_buffs(bare) == {"to_hit": 0, "damage": 0, "ac": 0}, "no potion, nothing added")
	vera.buffs["potion-of-heroism"] = {"status": Potions.buff("potion-of-heroism", RNG.new(1), vera.sheet())}
	var brave = Adapter.to_combatant(vera, "party", Vector2i.ZERO)
	check(int(Power.road_buffs(brave)["to_hit"]) == 2, "Heroism reads as +2 to hit (%s)" % Power.road_buffs(brave))
	check(float(Power.estimate(brave)["dpr"]) > float(Power.estimate(bare)["dpr"]),
		"and the fighter under it is priced to hit harder")
	var strong = Presets.vera()
	strong.buffs["potion-of-giant-strength"] = {"status": Potions.buff("potion-of-giant-strength", RNG.new(1), strong.sheet())}
	var sc = Adapter.to_combatant(strong, "party", Vector2i.ZERO)
	check(int(Power.road_buffs(sc)["damage"]) > 0 and float(Power.estimate(sc)["score"]) > float(Power.estimate(bare)["score"]),
		"Giant Strength's to-hit and damage are priced (%s)" % Power.road_buffs(sc))
	# a fight's own statuses are not a road buff: only the potion prefix counts
	bare.statuses["spell:bless"] = {"bonus_to_hit": 2}
	check(int(Power.road_buffs(bare)["to_hit"]) == 0, "a status that is not a road potion is not counted")
	# and the road's budget sees it: the same trio buys a bigger fight with a potion running
	var chars := Presets.party()
	var before: float = Scaler._budget(chars, "easy")
	chars[0].buffs["potion-of-heroism"] = {"status": Potions.buff("potion-of-heroism", RNG.new(1), chars[0].sheet())}
	check(Scaler._budget(chars, "easy") > before, "a company with a road potion running is sent a bigger fight")

func _party() -> Party:
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return p

func test_bonds() -> void:
	var p := _party()
	var fresh := Regions.fresh_score(p)
	check(is_equal_approx(WorldThreat.slot_hold(p), 1.0), "the preset trio starts with no bond: the hold is 1.0")
	PartyOpinion.set_score(p, p.active[0], p.active[1], PartyOpinion.BONDED)
	var bonded := Regions.fresh_score(p)
	check(bonded > fresh, "a bonded pair raises the company's reading (%.1f > %.1f)" % [bonded, fresh])
	check(WorldThreat.slot_hold(p) > 1.0, "so the road holds a bonded company's fight at the bigger size (%.3f)" % WorldThreat.slot_hold(p))
	var r := _party()
	PartyOpinion.set_score(r, r.active[0], r.active[1], PartyOpinion.RIVALS)
	check(is_equal_approx(Regions.fresh_score(r), fresh), "rivals are left unpriced (the harder, safe direction)")

func test_mastery_stays_unpriced() -> void:
	var c = Adapter.to_combatant(Presets.vera(), "party", Vector2i.ZERO)
	check(String(c.attacks[0].get("mastery", "")) != "", "the scene: Vera's weapon has a mastery")
	var with: float = float(Power.estimate(c)["score"])
	for a in c.attacks:
		a.erase("mastery")
	check(is_equal_approx(float(Power.estimate(c)["score"]), with),
		"weapon mastery is measured and left unpriced (tests/sweep_unpriced.gd)")
