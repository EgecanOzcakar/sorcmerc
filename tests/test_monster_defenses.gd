# T94: the statblock defences the catalog always carried and the engine dropped —
# damage resistance / immunity / vulnerability, condition immunity, Magic
# Resistance, Parry, Undead Fortitude / Relentless, Death Burst — plus the senses
# half of it: a keen-nosed foe is harder to hide from, and a blinded one is not.
#   godot --headless --path . -s tests/test_monster_defenses.gd
extends SceneTree

const RNG = preload("res://core/rng.gd")
const Dice = preload("res://core/dice.gd")
const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Adapter = preload("res://core/adapter.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_catalog_lists_reach_the_combatant()
	test_nonmagical_weapon_clause()
	test_damage_stack()
	test_condition_immunity()
	test_magic_resistance()
	test_parry()
	test_undead_fortitude()
	test_relentless()
	test_death_burst()
	test_keen_senses_raise_the_hide_dc()
	test_blinding_an_observer()
	test_defences_are_priced()
	print("test_monster_defenses: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _spawn(id: String, pos := Vector2i(4, 0)):
	return Adapter.from_monster(Catalog.index("bestiary.json")[id], "foe", pos)

func _hero(p := Vector2i(4, 1)):
	var c = Combatant.new()
	c.id = "hero"; c.cname = "Hero"; c.team = "party"; c.pos = p
	c.ac = 5; c.max_hp = 200; c.hp = 200; c.speed = 4; c.stealth = 0
	c.passive_perception = 10
	c.saves = {"str": -5, "dex": -5, "con": -5, "int": -5, "wis": -5, "cha": -5}
	return c

func _cb(all: Array) -> Combat:
	var cb = Combat.new(RNG.new(3), all, Encounter.board())
	for c in all:
		cb.begin_turn_for(c)
	return cb

# The bug this whole pass starts from: bestiary.json has carried these four keys
# on all 316 entries since F1b, and Adapter's generic c.set() dropped every one
# of them because combatant.gd declared no such property.
func test_catalog_lists_reach_the_combatant() -> void:
	var skeleton = _spawn("skeleton")
	check("poison" in skeleton.immune, "a skeleton's poison immunity survives the spawn")
	check("bludgeoning" in skeleton.vulnerable, "and so does its bludgeoning vulnerability")
	check("exhaustion" in skeleton.cond_immune, "and its condition immunities")
	var carried := 0
	for e in Catalog.all("bestiary.json"):
		var c = Encounter.spawn(e["id"], 1.0, "foe", Vector2i.ZERO)
		if not (c.resist.is_empty() and c.immune.is_empty()
				and c.vulnerable.is_empty() and c.cond_immune.is_empty()):
			carried += 1
	check(carried > 120, "%d of 316 entries now field a defence they always had" % carried)

# The only prose in those lists: "<types> from nonmagical weapons[ that aren't
# silvered/adamantine]". No weapon in this game is any of those things, so the
# clause holds and the honest reading is the types it names.
func test_nonmagical_weapon_clause() -> void:
	var wraith = _spawn("wraith")
	for t in ["bludgeoning", "piercing", "slashing"]:
		check(t in wraith.resist, "a wraith resists %s (nonmagical-weapon clause)" % t)
	check(not "nonmagical" in wraith.resist and not "weapons" in wraith.resist,
		"and nothing that isn't a damage type leaks into the list")
	for e in Catalog.all("bestiary.json"):
		var c = Encounter.spawn(e["id"], 1.0, "foe", Vector2i.ZERO)
		for t in c.resist + c.immune + c.vulnerable:
			check(String(t).find(" ") < 0, "%s: %s is not a damage type id" % [e["id"], t])

func test_damage_stack() -> void:
	var sk = _spawn("skeleton")
	sk.max_hp = 200                      # the arithmetic is under test, not the corpse
	var cb := _cb([sk, _hero()])
	sk.hp = sk.max_hp
	cb._apply_damage(sk, 10, "poison")
	check(sk.hp == sk.max_hp, "immunity means no damage at all")
	cb._apply_damage(sk, 10, "bludgeoning")
	check(sk.hp == sk.max_hp - 20, "vulnerability doubles it")
	var troll = _spawn("troll")
	troll.resist = ["fire"]
	var cb2 := _cb([troll, _hero()])
	troll.hp = troll.max_hp
	cb2._apply_damage(troll, 10, "fire")
	check(troll.hp == troll.max_hp - 5, "resistance halves it")
	troll.statuses["rage"] = {"resist": ["fire"]}
	troll.hp = troll.max_hp
	cb2._apply_damage(troll, 10, "fire")
	check(troll.hp == troll.max_hp - 5, "and two sources of resistance still only halve (RAW)")
	troll.hp = troll.max_hp
	cb2._apply_damage(troll, 10, "")
	check(troll.hp == troll.max_hp - 10, "an untyped hit is unaffected by any of it")

func test_condition_immunity() -> void:
	var sk = _spawn("skeleton")
	var cb := _cb([sk, _hero()])
	check("poisoned" in sk.cond_immune, "a skeleton cannot be poisoned")
	cb.apply_condition(sk, "poisoned", null, "round")
	check(not sk.has("poisoned"), "and apply_condition refuses it")
	cb.apply_condition(sk, "prone", null, "round")
	check(sk.has("prone"), "a condition it is not immune to still lands")
	# exhaustion is the one path that never re-enters apply_condition, so the
	# immunity check has to sit ahead of it
	var golem = _spawn("stone-golem")
	var cb2 := _cb([golem, _hero()])
	check("exhaustion" in golem.cond_immune, "a stone golem cannot be exhausted")
	cb2.apply_condition(golem, "exhaustion")
	check(cb2.exhaustion_level(golem) == 0, "and gains no level of it")

# Advantage on saves against spells and other magical effects — and NOT against
# a dragon's breath or a ghoul's claws, which force saves but are not magic.
func test_magic_resistance() -> void:
	var satyr = _spawn("satyr")
	var cb := _cb([satyr, _hero()])
	var magical := 0
	var mundane := 0
	for i in 400:
		if cb._saving_throw(satyr, 14, "wis", false, true):
			magical += 1
		if cb._saving_throw(satyr, 14, "wis", false, false):
			mundane += 1
	check(magical > mundane + 20,
		"magic resistance only helps against magic (%d magical vs %d mundane of 400)" % [magical, mundane])
	var plain = _spawn("gnoll")
	var cb2 := _cb([plain, _hero()])
	var a := 0
	var b := 0
	for i in 400:
		if cb2._saving_throw(plain, 14, "wis", false, true):
			a += 1
		if cb2._saving_throw(plain, 14, "wis", false, false):
			b += 1
	check(absi(a - b) < 60, "a monster without it saves the same either way (%d vs %d)" % [a, b])

func test_parry() -> void:
	var noble = _spawn("noble")
	var hero = _hero()
	hero.atk_bonus = 0
	var cb := _cb([noble, hero])
	check(not cb.available(noble).any(func(v): return String(v["id"]).begins_with("monster-parry")),
		"parry is a reaction, never a button")
	var ac: int = cb.effective_ac(noble)
	# a roll that clears AC by exactly 1 is the one parry is for
	hero.atk_bonus = ac - 10
	var parried := 0
	var landed := 0
	for i in 60:
		noble.econ["reaction"] = 1
		noble.hp = noble.max_hp
		var out: Dictionary = cb.resolve_attack(hero, noble, {"free": true})
		if out.get("hit", false):
			landed += 1
		elif int(out.get("ac", 0)) > ac:
			parried += 1
	check(parried > 0, "parry turns a would-be hit into a miss (%d of 60)" % parried)
	check(landed > 0, "and does not stop everything (%d landed)" % landed)
	# spent, it raises nothing: the logged AC is the plain one on every swing
	# (some still miss — a natural 1 always does — but not to a parry)
	noble.econ["reaction"] = 0
	var raised := 0
	for i in 40:
		noble.hp = noble.max_hp
		noble.statuses.clear()
		if int(cb.resolve_attack(hero, noble, {"free": true}).get("ac", 0)) > ac:
			raised += 1
	check(raised == 0, "with no reaction left, nothing is parried")

func test_undead_fortitude() -> void:
	var z = _spawn("zombie")
	var cb := _cb([z, _hero()])
	var survived := 0
	for i in 40:
		z.hp = 3
		z.statuses.clear()
		cb._apply_damage(z, 3, "slashing")
		if z.hp == 1:
			survived += 1
	check(survived > 0, "undead fortitude leaves a zombie at 1 HP (%d of 40)" % survived)
	# radiant and a crit both defeat it outright
	var by_radiant := 0
	var by_crit := 0
	for i in 40:
		z.hp = 3
		z.statuses.clear()
		cb._apply_damage(z, 3, "radiant")
		if z.hp == 1:
			by_radiant += 1
		z.hp = 3
		z.statuses.clear()
		cb._apply_damage(z, 3, "slashing", true)
		if z.hp == 1:
			by_crit += 1
	check(by_radiant == 0, "radiant damage allows no save")
	check(by_crit == 0, "and neither does a critical hit")
	# the DC is 5 + the damage taken, so a big hit is unsurvivable
	var big := 0
	for i in 40:
		z.hp = 3
		z.statuses.clear()
		cb._apply_damage(z, 40, "slashing")
		if z.hp == 1:
			big += 1
	check(big == 0, "DC 5 + damage means a big blow is not walked off")

func test_relentless() -> void:
	var boar = _spawn("boar")
	var cb := _cb([boar, _hero()])
	boar.hp = 3
	cb._apply_damage(boar, 5, "slashing")
	check(boar.hp == 1, "relentless: a small blow leaves the boar standing")
	cb._apply_damage(boar, 5, "slashing")
	check(boar.hp == 0 and boar.is_dead(), "one use per fight, then it dies")
	var big = _spawn("giant-boar")
	var cb2 := _cb([big, _hero()])
	big.hp = 3
	cb2._apply_damage(big, 11, "slashing")
	check(big.is_dead(), "and a blow over the threshold kills anyway (giant boar, 10)")
	check(int(_spawn("wereboar-hybrid").verb("monster-relentless-14")["max_damage"]) == 14,
		"the three SRD thresholds stay distinct")

func test_death_burst() -> void:
	var mephit = _spawn("magmin", Vector2i(4, 0))
	var near = _hero(Vector2i(4, 1))
	var far = _hero(Vector2i(9, 4))
	far.id = "far"; far.cname = "Far"
	var cb := _cb([mephit, near, far])
	check(not cb.available(mephit).any(func(v): return String(v["id"]).begins_with("monster-death-burst")),
		"a living magmin is not offered its own death burst")
	var before_near: int = near.hp
	var before_far: int = far.hp
	mephit.hp = 1
	cb._apply_damage(mephit, 20, "slashing")
	check(mephit.is_dead(), "the magmin dies")
	check(near.hp < before_near, "and the burst catches what stood beside it")
	check(far.hp == before_far, "but nothing out of range")
	# a hit on the corpse must not set it off a second time
	var after: int = near.hp
	cb._apply_damage(mephit, 5, "slashing")
	check(near.hp == after, "a corpse does not burst twice")

# The user's ask: a sense-sharp foe should make hiding near it harder.
func test_keen_senses_raise_the_hide_dc() -> void:
	var wolf = _spawn("wolf")               # Keen Hearing and Smell
	var gnoll = _spawn("gnoll")             # nothing of the kind
	var rogue = _hero()
	var cb := _cb([wolf, gnoll, rogue])
	check(cb.hide_dc_against(wolf) == wolf.passive_perception + 5,
		"a keen sense is worth RAW advantage on the check: +5 passive")
	check(cb.hide_dc_against(gnoll) == gnoll.passive_perception,
		"a monster with no keen sense is just its passive Perception")
	check(not cb.available(wolf).any(func(v): return String(v["id"]).begins_with("monster-keen")),
		"and a keen sense is never a button")
	# act_hide takes the hardest observer on the board, so the wolf sets the DC
	rogue.stealth = 100
	check(cb.act_hide(rogue), "an impossible Stealth still gets you hidden")

func test_blinding_an_observer() -> void:
	var wolf = _spawn("wolf")               # hearing + smell: blinding costs it nothing
	var hawk = _spawn("hawk")               # Keen Sight: blinding takes it all
	var cb := _cb([wolf, hawk, _hero()])
	var wolf_seeing: int = cb.hide_dc_against(wolf)
	var hawk_seeing: int = cb.hide_dc_against(hawk)
	cb.apply_condition(wolf, "blinded")
	cb.apply_condition(hawk, "blinded")
	check(cb.usable_senses(wolf) == ["hearing", "smell"],
		"blinded takes sight off the list, per conditions.json's auto_fail")
	check(cb.hide_dc_against(wolf) == wolf_seeing - Combat.BLIND_PERCEPTION_PENALTY,
		"a blinded wolf is easier to pass, but still smells you")
	check(cb.hide_dc_against(hawk) == hawk_seeing - Combat.BLIND_PERCEPTION_PENALTY - 5,
		"a blinded hawk loses its Keen Sight as well")
	cb.apply_condition(hawk, "deafened")
	check(cb.usable_senses(hawk) == ["smell"], "deafened stacks with it")

# The scaler buys bodies by Power.estimate, so a defence it cannot see is a
# defence the party gets for free.
func test_defences_are_priced() -> void:
	var plain = _spawn("gnoll")
	var base: float = Power.estimate(plain)["score"]
	var tough = _spawn("gnoll")
	tough.resist = ["bludgeoning", "piercing", "slashing"]
	check(Power.estimate(tough)["score"] > base, "physical resistance costs the budget more")
	var elemental = _spawn("gnoll")
	elemental.resist = ["fire"]
	var el: float = Power.estimate(elemental)["score"]
	check(el > base and el < Power.estimate(tough)["score"],
		"an elemental line costs less than a physical one, and more than nothing")
	var frail = _spawn("gnoll")
	frail.vulnerable = ["slashing"]
	check(Power.estimate(frail)["score"] < base, "and a vulnerability is a discount")
	check(Power.estimate(_spawn("satyr"))["score"] > 0.0, "magic resistance prices without blowing up")
