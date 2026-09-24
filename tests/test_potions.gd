# Potions do something now: a combat action off the party stash, or a drink on
# the road that heals or hangs a buff the next fight inherits (core/potions.gd).
#   godot --headless --path . -s tests/test_potions.gd
extends SceneTree

const Combat = preload("res://core/combat.gd")
const Combatant = preload("res://core/combatant.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Potions = preload("res://core/potions.gd")
const Campaign = preload("res://core/campaign.gd")
const Loot = preload("res://core/loot.gd")
const CharSave = preload("res://core/character_save.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_every_potion_has_a_mechanic_or_is_gone()
	test_drink_in_combat_is_an_action_off_the_stash()
	test_buffs_do_what_they_say()
	test_invisibility_ends_on_a_swing()
	test_animal_friendship_wants_a_beast()
	test_road_drink()
	test_road_drink_is_seeded()
	test_road_buff_walks_into_the_fight_and_expires()
	print("test_potions: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _fight(party: Party) -> Array:
	var hero = Adapter.to_combatant(party.roster[0], "party", Vector2i(4, 0))
	var foe = Encounter.spawn("goblin", 1.0, "foe", Vector2i(4, 1), 1)
	var cb = Combat.new(RNG.new(7), [hero, foe], Encounter.board())
	cb.party = party
	cb.begin_turn_for(hero)
	cb.begin_turn_for(foe)
	return [cb, hero, foe]

func _party(potions: Array) -> Party:
	var p := Party.new()
	p.add_member(Presets.vera())
	for id in potions:
		p.stash_add(id)
	return p

func _drink(cb, hero, id: String) -> Dictionary:
	for v in cb.available(hero):
		if String(v["id"]) == "drink:" + id:
			return v
	return {}

func test_every_potion_has_a_mechanic_or_is_gone() -> void:
	for id in Campaign.potion_ids():
		check(Potions.is_potion(id), "%s is sold and does something" % id)
	check(not "potion-of-climbing" in Campaign.potion_ids(), "a potion with no mechanic is not for sale")
	for band in Loot.CONSUMABLE_BANDS.values():
		for id in band:
			check(not String(id).begins_with("potion") or Potions.is_potion(id), "%s drops and does something" % id)
	check(Potions.text("potions-of-healing") != "", "every potion says what it does")

func test_drink_in_combat_is_an_action_off_the_stash() -> void:
	var f := _fight(_party(["potions-of-healing", "potions-of-healing"]))
	var cb = f[0]; var hero = f[1]
	hero.hp = 1
	var v := _drink(cb, hero, "potions-of-healing")
	check(not v.is_empty() and v["cost"] == "action" and v["targeting"] == "self", "the stash offers a Drink action")
	check(cb.available(hero).filter(func(x): return x["kind"] == "drink").size() == 1, "one button per kind of potion, not per bottle")
	cb.perform(hero, v)
	check(hero.hp >= 1 + 4 and hero.hp <= 1 + 10, "healing lands (%d)" % hero.hp)
	check(cb.party.stash_count("potions-of-healing") == 1, "one bottle gone")
	check(int(hero.econ["action"]) == 0, "the action is spent")
	check(_drink(cb, hero, "potions-of-healing").is_empty(), "no action left, no Drink offered")
	var f2 := _fight(_party([]))
	check(f2[0].available(f2[1]).filter(func(x): return x["kind"] == "drink").is_empty(), "an empty stash offers nothing")
	# the trap
	var f3 := _fight(_party(["potion-of-poison"]))
	var hp0: int = f3[1].hp
	f3[0].perform(f3[1], _drink(f3[0], f3[1], "potion-of-poison"))
	check(f3[1].hp < hp0 and f3[1].has("poisoned"), "poison hurts and poisons")

func test_buffs_do_what_they_say() -> void:
	var f := _fight(_party(["potion-of-speed", "potion-of-resistance", "potion-of-heroism",
		"potion-of-giant-strength", "potion-of-gaseous-form"]))
	var cb = f[0]; var hero = f[1]
	var ac0: int = cb.effective_ac(hero)
	cb.perform(hero, _drink(cb, hero, "potion-of-speed"))
	check(cb.effective_ac(hero) == ac0 + 2, "haste: +2 AC")
	cb.begin_turn_for(hero)
	check(int(hero.econ["action"]) == 2 and int(hero.econ["move_left"]) == hero.speed * 2, "haste: two actions and double move next turn")
	hero.econ["action"] = 1
	cb.perform(hero, _drink(cb, hero, "potion-of-resistance"))
	var res: Array = hero.statuses["potion:potion-of-resistance"]["resist"]
	check(res.size() == 1, "resistance picked one type: %s" % str(res))
	var hp0: int = hero.hp
	cb._apply_damage(hero, 10, res[0])
	check(hero.hp == hp0 - 5, "...and halves it")
	hero.econ["action"] = 1
	var hit0: int = int(hero.atk_bonus)
	cb.perform(hero, _drink(cb, hero, "potion-of-heroism"))
	check(cb._buff_sum(hero, "bonus_to_hit") == 2 and cb._buff_sum(hero, "bonus_save") == 2, "heroism: +2 to hit and saves")
	hero.econ["action"] = 1
	cb.perform(hero, _drink(cb, hero, "potion-of-giant-strength"))
	var gain: int = 5 - hero.sheet.mod("str")
	check(cb._buff_sum(hero, "bonus_to_hit") == 2 + gain and cb._buff_sum(hero, "bonus_damage") == gain,
		"giant strength: melee swings as STR 21 (+%d over Vera's own)" % gain)
	hero.econ["action"] = 1
	cb.perform(hero, _drink(cb, hero, "potion-of-gaseous-form"))
	check(cb.available(hero).filter(func(x): return x["kind"] == "attack").is_empty(), "mist cannot attack")
	hp0 = hero.hp
	cb._apply_damage(hero, 10, "slashing")
	check(hero.hp == hp0 - 5, "...but shrugs off half a blade")

func test_invisibility_ends_on_a_swing() -> void:
	var f := _fight(_party(["potion-of-invisibility"]))
	var cb = f[0]; var hero = f[1]; var foe = f[2]
	cb.perform(hero, _drink(cb, hero, "potion-of-invisibility"))
	check(hero.has("invisible"), "invisible after drinking")
	cb.begin_turn_for(hero)
	check(hero.has("invisible"), "...still, next turn")
	cb.resolve_attack(hero, foe)
	check(not hero.has("invisible"), "...until the first swing")

func test_animal_friendship_wants_a_beast() -> void:
	var f := _fight(_party(["potion-of-animal-friendship"]))
	var cb = f[0]; var hero = f[1]; var gob = f[2]
	check(_drink(cb, hero, "potion-of-animal-friendship").is_empty(), "no beast in reach: not offered")
	var wolf = Encounter.spawn("wolf", 1.0, "foe", Vector2i(5, 0), 2)
	cb.combatants.append(wolf); cb.order.append(wolf)
	var v := _drink(cb, hero, "potion-of-animal-friendship")
	check(not v.is_empty() and v["targeting"] == "enemy", "a wolf nearby: a targeted Drink")
	check(cb.legal_target(hero, v, wolf) and not cb.legal_target(hero, v, gob), "the wolf is a target, the goblin is not")
	wolf.saves["wis"] = -20
	cb.perform(hero, v, wolf)
	check(wolf.has("charmed"), "the wolf is charmed")

func test_road_drink() -> void:
	var p := _party(["potions-of-healing", "potion-of-speed", "potion-of-clairvoyance", "potion-of-mind-reading"])
	var ch = p.roster[0]
	ch.hp_current = 1
	p.world_now = 100.0
	Potions.drink_on_road(p, ch, "potions-of-healing", p.world_now, RNG.new(3))
	check(ch.hp_current >= 5 and p.stash_count("potions-of-healing") == 0, "road healing lands and spends the bottle")
	Potions.drink_on_road(p, ch, "potion-of-speed", p.world_now, RNG.new(3))
	check(ch.buffs.has("potion-of-speed") and ch.buffs["potion-of-speed"]["until"] == 101.0, "a timed potion is a buff with a world-clock expiry")
	Potions.drink_on_road(p, ch, "potion-of-clairvoyance", p.world_now, RNG.new(3))
	check(p.scouted_next, "clairvoyance scouts the next fight")
	Potions.drink_on_road(p, ch, "potion-of-mind-reading", p.world_now, RNG.new(3))
	check(Potions.road_buff(ch, "persuasion_adv", 105.0) and not Potions.road_buff(ch, "persuasion_adv", 111.0),
		"mind reading is advantage on the talk for ten minutes")
	var again = CharSave.from_dict(CharSave.to_dict(ch))
	check(again.buffs.has("potion-of-speed"), "buffs survive a save")

# Unpinned, a road drink is seeded off the drink (Potions.road_seed): the same
# hero, bottle, minute and stash roll the same heal — a reload cannot reroll it —
# while the next bottle of the same kind is a roll of its own.
func test_road_drink_is_seeded() -> void:
	var heals: Array = []
	for _i in 2:
		var p := _party(["potions-of-healing", "potions-of-healing"])
		var ch = p.roster[0]
		ch.hp_current = 1
		p.world_now = 250.0
		Potions.drink_on_road(p, ch, "potions-of-healing", p.world_now)
		heals.append(ch.hp_current)
	check(heals[0] == heals[1] and heals[0] > 1, "the same drink heals the same (%s)" % str(heals))
	var p2 := _party(["potions-of-healing", "potions-of-healing"])
	var ch2 = p2.roster[0]
	var a := Potions.road_seed(p2, ch2, "potions-of-healing", 250.0)
	check(a == Potions.road_seed(p2, ch2, "potions-of-healing", 250.0), "the seed is a function of the drink")
	p2.stash_remove("potions-of-healing")
	check(a != Potions.road_seed(p2, ch2, "potions-of-healing", 250.0), "the second bottle rolls its own")
	check(Potions.road_seed(p2, ch2, "potions-of-healing", 250.0) >= 1, "a seed the xorshift can use")

func test_road_buff_walks_into_the_fight_and_expires() -> void:
	var p := _party(["potion-of-speed"])
	var ch = p.roster[0]
	p.world_now = 100.0
	Potions.drink_on_road(p, ch, "potion-of-speed", p.world_now, RNG.new(3))
	var f := _fight(p)
	check(f[0].effective_ac(f[1]) == f[1].ac + 2, "a live road buff is on the combatant")
	Potions.expire(ch, 100.5)
	check(ch.buffs.has("potion-of-speed"), "still holds before its minute is up")
	Potions.expire(ch, 102.0)
	check(not ch.buffs.has("potion-of-speed"), "gone after")
	var f2 := _fight(p)
	check(f2[0].effective_ac(f2[1]) == f2[1].ac, "an expired buff stays behind")
