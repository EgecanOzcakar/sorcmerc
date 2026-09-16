# Spells that used to do nothing, or the wrong thing: buffs land on allies,
# group spells reach everyone in range, riders land on a hit, the regex
# draft's 1d6 can't ship, and the creator only offers spells that work.
#   godot --headless --path . -s tests/test_spell_buffs.gd
extends SceneTree

const Combat = preload("res://core/combat.gd")
const Encounter = preload("res://core/encounter.gd")
const RNG = preload("res://core/rng.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Effects = preload("res://core/rules/effects.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Hex = preload("res://core/hex.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_no_more_1d6()
	test_group_buff_and_heal()
	test_single_buffs()
	test_save_or_debuff_and_rider()
	test_invisibility()
	test_pick_pool()
	test_teleport_obscure_summon()
	print("test_spell_buffs: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Ilsa (cleric 5) with the spells under test, a friend beside her, goblins ahead.
func _fight(spells: Array, goblins := [Vector2i(4, 0)]) -> Array:
	var ch := Presets.ilsa(7)   # 4th-level slots for Stoneskin / Greater Invisibility
	ch.prepared.assign(spells)
	var ilsa = Adapter.to_combatant(ch, "party", Vector2i(2, 0))
	ilsa.slots.assign([4, 3, 3, 1])
	var vera = Adapter.to_combatant(Presets.vera(), "party", Vector2i(2, 1))
	var all: Array = [ilsa, vera]
	var n := 0
	for g in goblins:
		n += 1
		all.append(Encounter.spawn("goblin", 1.0, "foe", g, n))
	var cb := Combat.new(RNG.new(7), all, Encounter.board_for("goblin-camp"))
	for c in cb.combatants:
		cb.begin_turn_for(c)
	return [cb, ilsa, vera]

func _verb(c, spell: String) -> Dictionary:
	for v in c.verbs:
		if String(v.get("spell", "")) == spell and not String(v["id"]).contains("@"):
			return v
	return {}

func test_no_more_1d6() -> void:
	for pair in [["flame-strike", 8, 6], ["lightning-bolt", 8, 6], ["ice-storm", 5, 8], ["moonbeam", 2, 10],
			["insect-plague", 4, 10], ["steel-wind-strike", 6, 10], ["evards-black-tentacles", 3, 6]]:
		var m := Effects.spell(pair[0])
		check(int(m["damage"][0]["count"]) == pair[1] and int(m["damage"][0]["sides"]) == pair[2],
			"%s is authored %dd%d" % pair)
	# the guard: a draft-only damage entry is dropped, never rolled as 1d6
	var draft := {"damage": [{"dice": "8d6"}]}
	check(not Effects._authored_damage(draft["damage"]), "the regex draft's damage shape is not authored")
	check(Effects.validate().is_empty(), "every authored override validates: %s" % str(Effects.validate()))

func test_group_buff_and_heal() -> void:
	var f := _fight(["bless", "mass-healing-word"])
	var cb = f[0]; var ilsa = f[1]; var vera = f[2]
	var bless := _verb(ilsa, "bless")
	check(bless["targeting"] == "allies" and bless.has("buff"), "Bless is a group buff, no aiming")
	cb.perform(ilsa, bless)
	check(cb._buff_sum(ilsa, "bonus_to_hit") == 2 and cb._buff_sum(vera, "bonus_to_hit") == 2
		and cb._buff_sum(vera, "bonus_save") == 2, "both allies get +2 to hit and saves")
	check(cb._buff_sum(cb.combatants[2], "bonus_to_hit") == 0, "the goblin does not")
	check(vera.statuses["spell:bless"].get("held_by") == ilsa, "Bless is held by Ilsa's concentration")
	cb._end_concentration(ilsa, "drops it")
	check(cb._buff_sum(vera, "bonus_to_hit") == 0, "...and goes when she drops it")
	ilsa.hp = 1; vera.hp = 1
	ilsa.econ["bonus"] = 1
	cb.perform(ilsa, _verb(ilsa, "mass-healing-word"))
	check(ilsa.hp > 1 and vera.hp > 1, "Mass Healing Word heals everyone on the side")

func test_single_buffs() -> void:
	var f := _fight(["shield-of-faith", "haste", "stoneskin", "blur"])
	var cb = f[0]; var ilsa = f[1]; var vera = f[2]
	var sof := _verb(ilsa, "shield-of-faith")
	check(sof["targeting"] == "ally" and sof["cost"] == "bonus", "Shield of Faith: one ally, a bonus action")
	var ac0: int = cb.effective_ac(vera)
	cb.perform(ilsa, sof, vera)
	check(cb.effective_ac(vera) == ac0 + 2, "+2 AC on Vera")
	cb.perform(ilsa, _verb(ilsa, "haste"), vera)
	check(cb._buff_sum(vera, "extra_action") == 1 and not cb._buff_sum(ilsa, "ac") == 2,
		"Haste replaced Shield of Faith (one concentration) and rides Vera")
	check(cb._buff_sum(vera, "ac") == 2, "...with its own +2 AC")
	ilsa.econ["action"] = 1
	cb.perform(ilsa, _verb(ilsa, "stoneskin"), vera)
	var hp0: int = vera.hp
	cb._apply_damage(vera, 10, "slashing")
	check(vera.hp == hp0 - 5, "Stoneskin halves a blade")
	ilsa.econ["action"] = 1
	var blur := _verb(ilsa, "blur")
	check(blur["targeting"] == "self", "Blur is on the caster")
	cb.perform(ilsa, blur)
	var seen := false
	for e in cb._cond_effects(ilsa):
		seen = seen or e.get("attacks_against", "") == "dis"
	check(seen, "attacks against a blurred Ilsa are at disadvantage")

func test_save_or_debuff_and_rider() -> void:
	var f := _fight(["bane", "ray-of-sickness", "faerie-fire", "ray-of-enfeeblement"])
	var cb = f[0]; var ilsa = f[1]
	var gob = cb.combatants[2]
	var bane := _verb(ilsa, "bane")
	bane["save_dc"] = 30
	check(bane["targeting"] == "enemy", "Bane is aimed at an enemy")
	cb.perform(ilsa, bane, gob)
	check(cb._buff_sum(gob, "bonus_to_hit") == -2 and cb._buff_sum(gob, "bonus_save") == -2, "a failed save hangs Bane's -2")
	ilsa.econ["action"] = 1
	var ray := _verb(ilsa, "ray-of-sickness")
	ray["attack_bonus"] = 30; ray["save_dc"] = 30
	cb.perform(ilsa, ray, gob)
	check(gob.has("poisoned"), "Ray of Sickness poisons on a hit and a failed save")
	ilsa.econ["action"] = 1
	var ff := _verb(ilsa, "faerie-fire")
	check(ff["targeting"] in ["hex", "corner"], "Faerie Fire is an area (%s)" % ff["targeting"])
	var ray2 := _verb(ilsa, "ray-of-enfeeblement")
	check(ray2["targeting"] == "enemy" and ray2.has("attack_bonus"), "Ray of Enfeeblement is aimed and rolled to hit")
	# Spirit Guardians is an emanation that spares the caster's own side
	var f2 := _fight(["spirit-guardians"], [Vector2i(3, 0)])
	var cb2 = f2[0]; var ilsa2 = f2[1]; var vera2 = f2[2]
	var sg := _verb(ilsa2, "spirit-guardians")
	sg["save_dc"] = 30
	var vhp: int = vera2.hp
	cb2.perform(ilsa2, sg)
	check(vera2.hp == vhp and cb2.combatants[2].hp < cb2.combatants[2].max_hp, "Spirit Guardians burns the goblin, not Vera")

func test_invisibility() -> void:
	var f := _fight(["invisibility", "greater-invisibility"], [Vector2i(3, 1)])   # in Vera's reach
	var cb = f[0]; var ilsa = f[1]; var vera = f[2]
	var gob = cb.combatants[2]
	cb.perform(ilsa, _verb(ilsa, "invisibility"), vera)
	check(vera.has("invisible"), "Invisibility makes Vera invisible")
	cb.resolve_attack(vera, gob)
	check(not vera.has("invisible"), "...until she swings")
	ilsa.econ["action"] = 1
	cb.perform(ilsa, _verb(ilsa, "greater-invisibility"), vera)
	cb.resolve_attack(vera, gob)
	check(vera.has("invisible"), "Greater Invisibility survives the swing")
	cb._end_concentration(ilsa, "drops it")
	check(not vera.has("invisible"), "...and ends with Ilsa's concentration")

func test_pick_pool() -> void:
	var all := Catalog.spell_list("cleric", 1)
	var offered := Effects.pick_pool("cleric", 1)
	check(offered.size() < all.size() and "bless" in offered and not "detect-magic" in offered,
		"a cleric's 1st-level picks offer Bless, not Detect Magic")
	check(Effects.pick_pool("bard", 6).is_empty(), "there are no 6th-level spells to pick")
	var ilsa := Presets.ilsa()
	check(ilsa.sheet().pending.is_empty(), "Ilsa's Light and Guidance stay chosen")

func test_teleport_obscure_summon() -> void:
	var f := _fight(["misty-step", "darkness", "summon-beast"], [Vector2i(3, 0)])   # goblin adjacent to Ilsa
	var cb = f[0]; var ilsa = f[1]
	var gob = cb.combatants[2]
	var step := _verb(ilsa, "misty-step")
	check(step["targeting"] == "hex" and step["cost"] == "bonus" and step.get("teleport", false), "Misty Step aims a hex, as a bonus action")
	var dest := Vector2i(5, 1)
	var hp0: int = ilsa.hp
	var r: Dictionary = cb.perform(ilsa, step, dest)
	check(not r.has("error") and ilsa.pos == dest and ilsa.hp == hp0, "...and she is there, with no opportunity attack taken (%s)" % str(r))
	check(cb.perform(ilsa, _verb(ilsa, "misty-step"), gob.pos).has("error"), "an occupied hex is refused")
	ilsa.econ["action"] = 1
	var dark := _verb(ilsa, "darkness")
	dark["save_dc"] = 0
	cb.perform(ilsa, dark, gob.pos if dark["targeting"] == "hex" else [gob.pos, gob.pos + Vector2i(1, 0), gob.pos + Vector2i(0, 1)])
	var dis := false
	for e in cb._cond_effects(gob):
		dis = dis or (e.get("own_attacks", "") == "dis" and e.get("attacks_against", "") == "dis")
	check(dis, "in the Darkness the goblin attacks and is attacked at disadvantage")
	ilsa.econ["action"] = 1
	var n0: int = cb.combatants.size()
	var sb := _verb(ilsa, "summon-beast")
	check(sb["targeting"] == "self", "Summon Beast needs no aim")
	var res: Dictionary = cb.perform(ilsa, sb)
	check(cb.combatants.size() == n0 + 1 and res.has("summoned"), "a creature joins the fight")
	var wolf = res["summoned"]
	check(wolf.team == "party" and wolf.src_id == "dire-wolf" and wolf.cname.begins_with("Ilsa's"), "...on Ilsa's side, hers by name (%s)" % wolf.cname)
	check(cb.order.find(wolf) == cb.order.find(ilsa) + 1, "...acting right after her")
	check(wolf.short_name() == "Dire Wolf", "the bar calls it by its kind, not \"Ilsa's\" (%s)" % wolf.short_name())
	check(Hex.distance(wolf.pos, ilsa.pos) <= 3 and cb._hex_free(wolf.pos, wolf), "...in a free hex beside her")
	check(not cb.all_verbs(wolf).filter(func(v): return v["kind"] == "attack").is_empty(), "...and it has an attack")
	cb._end_concentration(ilsa, "drops it")
	check(wolf.is_dead() and wolf in cb.order, "the summon fades with her concentration (a corpse in the order, like any)")
	# and a faded summon is not a fallen member
	check(not Encounter.resolve_outcome(cb, null).get("deaths", []).has(wolf.id), "...nor a death the spoils report")
