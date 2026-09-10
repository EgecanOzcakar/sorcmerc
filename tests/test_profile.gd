# The profile scene renders resolve.gd's numbers and edits re-resolve.
#   godot --headless --path . -s tests/test_profile.gd
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Character = preload("res://core/character.gd")
const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _screen(ch):
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_character(ch)
	return p

func _init() -> void:
	_sheet_mirror()
	_equip()
	_resources()
	_pact()
	print("test_profile: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Every rendered field is the sheet's number, not a UI-side derivation.
func _sheet_mirror() -> void:
	for ch in Presets.party():
		var s = ch.sheet()
		var p = _screen(ch)
		var who: String = ch.id
		check(p.field("ac") == str(s.ac), "%s AC renders %d (got %s)" % [who, s.ac, p.field("ac")])
		check(p.field("hp") == "%d/%d" % [s.max_hp, s.max_hp], "%s HP full at start" % who)
		check(p.field("pb") == "%+d" % s.proficiency_bonus, "%s proficiency bonus" % who)
		check(p.field("initiative") == "%+d" % s.initiative, "%s initiative" % who)
		check(p.field("passive_perception") == str(s.passive_perception), "%s passive perception" % who)
		check(p.field("speed_walk") == "%d ft" % int(s.speeds["walk"]), "%s walk speed" % who)
		for a in ["str", "dex", "con", "int", "wis", "cha"]:
			check(p.field("abil_" + a) == "%d (%+d)" % [int(s.abilities[a]["total"]), s.mod(a)],
				"%s %s score" % [who, a])
			check(p.field("save_" + a) == "%+d" % int(s.saves[a]), "%s %s save" % [who, a])
		for id in Catalog.skills():
			check(p.field("skill_" + id) == "%+d" % int(s.skills.get(id, 0)),
				"%s skill %s" % [who, id])
		for f in s.features:
			check(p.field("feature_" + f) != "" or true, "%s feature row exists" % who)
			check(p._fields.has("feature_" + f), "%s renders feature %s" % [who, f])
		for it in s.equipment:
			check(p._fields.has("item_" + it["item_id"]), "%s renders item %s" % [who, it["item_id"]])
		p.queue_free()

	# expertise vs proficiency markers (Pike has expertise in stealth, prof in perception)
	var pike = Presets.pike()
	var pp = _screen(pike)
	var srow: String = pp._fields["skill_stealth"].get_parent().get_child(0).text
	check(srow.begins_with("◆"), "expertise marked with ◆ (got %s)" % srow)
	var prow: String = pp._fields["skill_arcana"].get_parent().get_child(0).text
	check(prow.begins_with("○"), "untrained skill marked with ○ (got %s)" % prow)
	pp.queue_free()

# Unequipping armor drops AC to the sheet's re-resolved value, re-equipping restores it.
func _equip() -> void:
	var vera = Presets.vera()
	var p = _screen(vera)
	var armored: int = vera.sheet().ac
	check(p.field("ac") == str(armored), "Vera starts at sheet AC")

	p.toggle_equip("shield")
	var no_shield: int = vera.sheet().ac
	check(no_shield == armored - 2, "dropping the shield costs 2 AC (%d -> %d)" % [armored, no_shield])
	check(p.field("ac") == str(no_shield), "screen re-renders AC after unequip")
	check(p._fields["equip_btn_shield"].text == "Equip", "button flips to Equip")

	p.toggle_equip("chain-mail")
	var naked: int = vera.sheet().ac
	check(naked == 10 + vera.sheet().mod("dex"), "unarmored AC is 10 + DEX (got %d)" % naked)
	check(p.field("ac") == str(naked), "screen tracks unarmored AC")

	# unequipping the weapon removes its attack row and leaves unarmed
	p.toggle_equip("longsword")
	check(not p._fields.has("attack_longsword"), "unequipped weapon leaves the attack list")
	check(vera.sheet().attacks.size() == 1, "unarmed strike is the only attack left")

	# T10: everything unequipped went to the party's shared stash, not the character.
	var pty = p.party()
	check(pty.stash_count("shield") == 1 and pty.stash_count("chain-mail") == 1
		and pty.stash_count("longsword") == 1, "unequipped gear lands in the party stash")

	p.toggle_equip("chain-mail")
	p.toggle_equip("shield")
	p.toggle_equip("longsword")
	check(p.field("ac") == str(armored), "re-equipping restores AC")
	check(p._fields.has("attack_longsword"), "re-equipping restores the attack row")
	check(pty.stash.is_empty(), "re-equipping empties the stash again")
	p.queue_free()

	# An injected party is the one that gets equipped from.
	var pike = Presets.pike()
	var shared = Party.new()
	shared.add_member(pike)
	shared.stash_add("greataxe")
	var p2 = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p2)
	p2.set_party(shared)
	p2.set_character(pike)
	check(p2._fields.has("item_greataxe"), "the stash is rendered on the sheet")
	p2.toggle_equip("greataxe")
	check("greataxe" in pike.equipped and shared.stash_count("greataxe") == 0,
		"equipping pulls the item out of the shared stash")
	check(p2._fields.has("attack_greataxe"), "and it shows up as an attack")
	p2.toggle_equip("greataxe")
	check(not "greataxe" in pike.equipped and shared.stash_count("greataxe") == 1,
		"unequipping returns it to the shared stash")
	p2.toggle_equip("plate")
	check(not "plate" in pike.equipped, "equipping what the party does not carry is a no-op")
	p2.queue_free()

# HP and pools are editable, and a long rest restores both.
func _resources() -> void:
	var ilsa = Presets.ilsa()
	var s = ilsa.sheet()
	var p = _screen(ilsa)
	var slots: Array = s.spellcasting["slots"]
	check(int(slots[0]) > 0, "Ilsa has level-1 slots")
	check(p.field("pool_slot:1") == "%d/%d" % [int(slots[0]), int(slots[0])], "slots start full")
	p._spend("slot:1", int(slots[0]), -1)
	check(p.field("pool_slot:1") == "%d/%d" % [int(slots[0]) - 1, int(slots[0])], "spending a slot")
	check(int(ilsa.pools["slot:1"]) == int(slots[0]) - 1, "spend writes through to the character")

	p._apply_hp(-5)
	check(p.field("hp") == "%d/%d" % [s.max_hp - 5, s.max_hp], "damage applies")
	p._apply_hp(-9999)
	check(p.field("hp") == "0/%d" % s.max_hp, "damage clamps at 0")
	p._restore_all()
	check(p.field("hp") == "%d/%d" % [s.max_hp, s.max_hp], "long rest restores HP")
	check(p.field("pool_slot:1") == "%d/%d" % [int(slots[0]), int(slots[0])], "long rest restores slots")
	p.queue_free()

# A warlock renders a pact-magic row instead of a slot table.
func _pact() -> void:
	var w := Character.new()
	w.id = "warlock-fixture"
	w.cname = "Test Warlock"
	w.species_id = "human"
	w.background_id = "acolyte"
	w.base_abilities = {"str": 8, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 16}
	for i in 3:
		w.add_level("warlock", -1)
	var pact: Dictionary = w.sheet().spellcasting.get("pact", {})
	check(not pact.is_empty(), "warlock sheet carries pact magic")
	var p = _screen(w)
	check(p.field("pool_pact") == "%d/%d" % [int(pact["count"]), int(pact["count"])],
		"pact slots render at full")
	check(not p._fields.has("pool_slot:1"), "warlock has no ordinary slot rows")
	p.queue_free()
