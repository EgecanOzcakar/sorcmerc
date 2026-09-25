# Magic items that work in a fight (the design audit §5.1c, 2026-09-25): the
# first tranche of data/effects/items.json, put on the sheet by
# core/rules/pass_items.gd. Every check equips an item the way the profile does
# (its id into ch.equipped), re-resolves, and reads the sheet or the combatant
# the adapter builds from it — the only places the fight and the budget look.
#   godot --headless --path . -s tests/test_items.gd
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Power = preload("res://core/rules/power.gd")
const PassItems = preload("res://core/rules/pass_items.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Loot = preload("res://core/loot.gd")
const Icons = preload("res://core/ui_icons.gd")
const Registry = preload("res://core/mod/registry.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_every_entry_is_a_real_item()
	test_weapon()
	test_armor_and_shield()
	test_protection_and_luck()
	test_set_ability()
	test_narrow_and_casting()
	test_raw_limits()
	test_the_fight_and_the_budget_see_it()
	test_found_and_sold()
	test_pack_validation()
	print("test_items: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _wear(ch, ids: Array):
	for id in ids:
		ch.equipped.append(String(id))
	ch.dirty()
	return ch.sheet()

func _attack(s, id: String) -> Dictionary:
	for a in s.attacks:
		if String(a["id"]) == id:
			return a
	return {}

func test_every_entry_is_a_real_item() -> void:
	var d = Catalog.all(PassItems.FILE)
	check(d is Dictionary and d.size() > 15, "data/effects/items.json loads (%d entries)" % (d.size() if d is Dictionary else 0))
	for id in d:
		if String(id).begins_with("_"):
			continue
		var e: Dictionary = d[id]
		check(PassItems.is_magic_item(String(id)), "%s is a magic-items.json id" % id)
		check(String(e.get("slot", "")) in PassItems.SLOTS, "%s has a known slot" % id)
		check(e.keys().all(func(k): return String(k) in PassItems.KEYS), "%s uses only known keys" % id)
		check(String(e.get("text", "")) != "", "%s says what it does" % id)

func test_weapon() -> void:
	var plain = Presets.vera().sheet()
	var base: Dictionary = _attack(plain, "longsword")
	var v = Presets.vera()
	var s = _wear(v, ["weapon-1"])
	var a: Dictionary = _attack(s, "longsword")
	check(int(a["to_hit"]) == int(base["to_hit"]) + 1 and int(a["dmg_bonus"]) == int(base["dmg_bonus"]) + 1,
		"a +1 weapon: +1 to hit and damage with the sword in hand (%s -> %s)" % [base["notation"], a["notation"]])
	check(String(a["notation"]) == "1d8%+d" % (int(base["dmg_bonus"]) + 1), "the notation is rebuilt (%s)" % a["notation"])
	check(String(a["versatile_notation"]).begins_with("1d10") and String(a["versatile_notation"]).ends_with("%+d" % (int(base["dmg_bonus"]) + 1)),
		"...and the two-handed grip with it (%s)" % a["versatile_notation"])
	var s2 = _wear(v, ["weapon-2"])
	check(int(_attack(s2, "longsword")["to_hit"]) == int(base["to_hit"]) + 2, "a +1 and a +2 is a +2, not a +3")
	var u: Dictionary = _attack(s2, "unarmed-strike")
	check(u.is_empty() or int(u["to_hit"]) == int(_attack(plain, "unarmed-strike").get("to_hit", u["to_hit"])), "the fist is not enchanted")

func test_armor_and_shield() -> void:
	var ac0: int = Presets.vera().sheet().ac
	check(_wear(Presets.vera(), ["armor-1"]).ac == ac0 + 1, "+1 armor over chain mail: +1 AC")
	var bare = Presets.vera()
	bare.equipped.assign(["longsword"])
	var bare_ac: int = bare.sheet().ac
	check(_wear(bare, ["armor-2"]).ac == bare_ac, "+2 armor with no armor on does nothing")
	check(PassItems.worn_note(bare, "armor-2") == "", "(it counts; there is simply nothing for it to ride)")
	# A +1 shield IS a shield: swap the plain one for it and AC goes up by one.
	var v = Presets.vera()
	v.equipped.assign(["longsword", "chain-mail", "shield-1"])
	v.dirty()
	check(v.sheet().ac == ac0 + 1, "a +1 shield in place of a plain one: +1 AC (%d vs %d)" % [v.sheet().ac, ac0])
	var no_shield = Presets.vera()
	no_shield.equipped.assign(["longsword", "chain-mail"])
	no_shield.dirty()
	check(v.sheet().ac == no_shield.sheet().ac + 3, "...which is the shield's +2 and its own +1")
	var worn_rows: Array = v.sheet().equipment.filter(func(it): return String(it["item_id"]) == "shield-1")
	check(worn_rows.size() == 1 and worn_rows[0]["kind"] == "armor" and String(worn_rows[0]["def"]["category"]) == "shield",
		"the sheet lists it as the shield it is")

func test_protection_and_luck() -> void:
	var plain = Presets.pike().sheet()
	var s = _wear(Presets.pike(), ["cloak-of-protection"])
	check(s.ac == plain.ac + 1, "a cloak of protection: +1 AC")
	check(plain.saves.keys().all(func(k): return int(s.saves[k]) == int(plain.saves[k]) + 1), "...and +1 to every save")
	var r = _wear(Presets.pike(), ["cloak-of-protection", "ring-of-protection"])
	check(r.ac == plain.ac + 2 and int(r.saves["wis"]) == int(plain.saves["wis"]) + 2, "a ring beside it stacks, as RAW has it")
	var luck = _wear(Presets.pike(), ["stone-of-good-luck-(luckstone)"])
	check(int(luck.saves["dex"]) == int(plain.saves["dex"]) + 1 and int(luck.skills["stealth"]) == int(plain.skills["stealth"]) + 1
		and luck.initiative == plain.initiative + 1 and luck.ac == plain.ac, "a luckstone: +1 to saves and checks, initiative included, not AC")
	check(luck.passive_perception == plain.passive_perception + 1, "...and passive Perception with it")
	var bracers = Presets.pike()
	bracers.equipped.assign(["shortbow"])
	bracers.dirty()
	var unarmored: int = bracers.sheet().ac
	check(_wear(bracers, ["bracers-of-defense"]).ac == unarmored + 2, "bracers of defense with no armor: +2 AC")
	check(_wear(Presets.pike(), ["bracers-of-defense"]).ac == plain.ac, "...and nothing over studded leather")

func test_set_ability() -> void:
	var plain = Presets.pike().sheet()
	var s = _wear(Presets.pike(), ["gauntlets-of-ogre-power"])
	check(int(s.abilities["str"]["total"]) == 19 and s.mod("str") == 4, "gauntlets of ogre power: Strength 19 (was %d)" % int(plain.abilities["str"]["total"]))
	check(int(s.saves["str"]) == int(plain.saves["str"]) + 4 - plain.mod("str"), "the Strength save follows the new score")
	var v_plain = Presets.vera().sheet()
	var v = _wear(Presets.vera(), ["gauntlets-of-ogre-power"])
	check(int(_attack(v, "longsword")["to_hit"]) == int(_attack(v_plain, "longsword")["to_hit"]) + 4 - v_plain.mod("str"),
		"...and so does the sword swung with it")
	var strong = Presets.vera()
	strong.base_abilities["str"] = 20
	strong.dirty()
	var twenty: int = int(strong.sheet().abilities["str"]["total"])
	check(int(_wear(strong, ["gauntlets-of-ogre-power"]).abilities["str"]["total"]) == twenty, "a score already higher is left alone")
	var tough = _wear(Presets.ilsa(), ["amulet-of-health"])
	check(tough.max_hp > Presets.ilsa().sheet().max_hp, "an amulet of health is Constitution 19, and the hit points with it")

func test_narrow_and_casting() -> void:
	var plain = Presets.pike().sheet()
	var s = _wear(Presets.pike(), ["bracers-of-archery"])
	var bow: Dictionary = _attack(s, "shortbow")
	check(int(bow["dmg_bonus"]) == int(_attack(plain, "shortbow")["dmg_bonus"]) + 2 and int(bow["to_hit"]) == int(_attack(plain, "shortbow")["to_hit"]),
		"bracers of archery: +2 damage with the shortbow, nothing to hit")
	var il = Presets.ilsa().sheet()
	var w = _wear(Presets.ilsa(), ["wand-of-the-war-mage-1"])
	check(int(w.spellcasting["attack_bonus"]) == int(il.spellcasting["attack_bonus"]) + 1, "a wand of the war mage: +1 to spell attacks")
	check(int(_attack(w, "mace")["to_hit"]) == int(_attack(il, "mace")["to_hit"]), "...and not to the mace")
	check("force" in _wear(Presets.ilsa(), ["brooch-of-shielding"]).resistances, "a brooch of shielding: resistance to force")

func test_raw_limits() -> void:
	var p = Presets.pike()
	var s = _wear(p, ["cloak-of-protection", "cloak-of-protection"])
	check(s.ac == Presets.pike().sheet().ac + 1, "two cloaks are one cloak")
	var four = Presets.pike()
	var plain_ac: int = four.sheet().ac
	var s4 = _wear(four, ["cloak-of-protection", "gauntlets-of-ogre-power", "stone-of-good-luck-(luckstone)", "ring-of-protection"])
	check(s4.ac == plain_ac + 1, "three attuned items count; the fourth (the ring) is inert (%d vs %d)" % [s4.ac, plain_ac])
	check(s4.warnings.any(func(w): return String(w).contains("ring-of-protection") and String(w).contains("attunement")),
		"...and the sheet says why")
	check(PassItems.worn_note(four, "ring-of-protection").contains("attuned"), "the profile's tooltip line says so too")
	check(PassItems.worn_note(four, "cloak-of-protection") == "", "the ones that count carry no note")
	var mixed = Presets.vera()
	_wear(mixed, ["weapon-2", "weapon-1"])
	check(PassItems.worn_note(mixed, "weapon-1").contains("better"), "the lesser of two weapon enchantments is outclassed")
	check(PassItems.worn_note(mixed, "bag-of-holding").contains("nothing"), "an item with no mechanic says it does nothing yet")

func test_the_fight_and_the_budget_see_it() -> void:
	var plain = Presets.vera()
	var geared = Presets.vera()
	_wear(geared, ["weapon-2", "armor-1", "cloak-of-protection"])
	var c0 = Adapter.to_combatant(plain, "party", Vector2i.ZERO)
	var c1 = Adapter.to_combatant(geared, "party", Vector2i.ZERO)
	check(c1.ac == c0.ac + 2, "the combatant carries the AC (%d vs %d)" % [c1.ac, c0.ac])
	check(c1.atk_bonus == c0.atk_bonus + 2 and String(c1.damage) != String(c0.damage), "...the swing (%s vs %s)" % [c1.damage, c0.damage])
	check(int(c1.saves["con"]) == int(c0.saves["con"]) + 1, "...and the saves")
	var s0: float = Power.team_score([c0])
	var s1: float = Power.team_score([c1])
	check(s1 > s0 * 1.05, "power.gd prices the gear through the sheet: a geared Vera is worth more (%.1f vs %.1f)" % [s1, s0])

func test_found_and_sold() -> void:
	var unc: Array = Loot.items_of_rarity("uncommon")
	for id in ["weapon-1", "shield-1", "cloak-of-protection", "gauntlets-of-ogre-power", "bracers-of-archery"]:
		check(id in unc and not PassItems.entry(id).is_empty(), "%s drops from the uncommon shelf and works when worn" % id)
	var tip := Icons.item_tooltip("cloak-of-protection", Catalog.magic_item("cloak-of-protection"), "magic")
	check(tip.contains("Worn: +1 AC") and tip.contains("attunement"), "the tooltip says what it does, and that it needs attuning:\n%s" % tip.left(120))
	var inert := Icons.item_tooltip("bag-of-holding", Catalog.magic_item("bag-of-holding"), "magic")
	check(inert.contains("does nothing in a fight yet"), "and says plainly when an item does nothing yet")
	var v = Presets.vera()
	_wear(v, ["bag-of-holding"])
	check(v.sheet().warnings.all(func(w): return not String(w).contains("bag-of-holding")),
		"a worn magic item with no mechanic is a magic row, not an unknown-item warning")
	check(v.sheet().equipment.any(func(it): return String(it["item_id"]) == "bag-of-holding" and it["kind"] == "magic"),
		"...so the profile can take it back off")

func test_pack_validation() -> void:
	var good := {"errors": []}
	Registry._check_item(good, "items.json", "cloak-of-protection", {"slot": "worn", "ac": 2, "text": "x"}, {})
	check(good["errors"].is_empty(), "a well-formed overlay passes (%s)" % [good["errors"]])
	var bad := {"errors": []}
	Registry._check_item(bad, "items.json", "cloak-of-protection", {"slot": "cape", "armour_class": 1}, {})
	check(bad["errors"].size() == 2, "a bad slot and an unknown key are both refused (%s)" % [bad["errors"]])
	var ghost := {"errors": []}
	Registry._check_item(ghost, "items.json", "no-such-cloak", {"slot": "worn"}, {})
	check(ghost["errors"].size() == 1, "an id nobody wrote is refused")
	var stat := {"errors": []}
	Registry._check_item(stat, "items.json", "headband-of-intellect", {"slot": "worn", "set_ability": {"luck": 19}}, {})
	check(stat["errors"].size() == 1, "an ability that is not one of the six is refused")
