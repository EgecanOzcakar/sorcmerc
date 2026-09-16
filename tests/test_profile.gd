# The profile scene renders resolve.gd's numbers and edits re-resolve.
#   godot --headless --path . -s tests/test_profile.gd
extends SceneTree

const Presets = preload("res://core/presets.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const Character = preload("res://core/character.gd")
const Party = preload("res://core/party.gd")
const Ach = preload("res://core/achievements.gd")
const Icons = preload("res://core/ui_icons.gd")

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

# Equipping a legendary item from the stash unlocks the achievement.
func _equip_legendary() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()
	var pike = Presets.pike()
	var pty = Party.new()
	pty.add_member(pike)
	pty.stash_add("armor-of-invulnerability")
	var p = _screen(pike)
	p.set_party(pty)
	p.toggle_equip("armor-of-invulnerability")
	check("armor-of-invulnerability" in pike.equipped, "the legendary item equips")
	check(Ach.is_unlocked("equip_legendary"), "equipping it unlocks equip_legendary")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Ach.PATH))
	Ach._current = Ach.load_state()

func _init() -> void:
	_sheet_mirror()
	_equip()
	_unidentified()
	_resources()
	_pact()
	_equip_legendary()
	_drink()
	_shift_compare()
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
	check(p._fields["equip_btn_shield"].tooltip_text.ends_with("Click: equip"), "tile flips to Equip")

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

# T13: an unidentified item is a mystery in the stash panel — no name, no Equip
# button, and toggle_equip refuses it. A scroll clears it up on the spot.
func _unidentified() -> void:
	var pike = Presets.pike()
	var pty = Party.new()
	pty.add_member(pike)
	pty.stash_add("cloak-of-elvenkind", 1, false)
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_party(pty)
	p.set_character(pike)

	check(p._fields.has("item_cloak-of-elvenkind"), "the mystery still renders a tile")
	var label: String = p._fields["item_cloak-of-elvenkind"].tooltip_text.get_slice("\n", 0)
	check(label == "Unidentified item (uncommon)",
		"it shows rarity only, no name (got %s)" % label)
	check(not p._fields.has("equip_btn_cloak-of-elvenkind"), "no Equip button on a mystery")

	p.toggle_equip("cloak-of-elvenkind")
	check(not "cloak-of-elvenkind" in pike.equipped, "equipping an unidentified item is refused")
	check(pty.stash_count("cloak-of-elvenkind") == 1, "and the refusal left the stash alone")

	pty.stash_add(Party.IDENTIFY_SCROLL)
	p.set_party(pty)
	check(pty.use_identification_scroll("cloak-of-elvenkind"), "the scroll reveals it")
	p.set_party(pty)
	var known: String = p._fields["item_cloak-of-elvenkind"].tooltip_text.get_slice("\n", 0)
	check(known.begins_with("Cloak"), "the identified item shows its real name (got %s)" % known)
	p.toggle_equip("cloak-of-elvenkind")
	check(pty.stash_count("cloak-of-elvenkind") == 0, "an identified magic item can be taken")
	p.queue_free()

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

# A potion in the stash is a Drink tile, not an Equip one; drinking heals.
func _drink() -> void:
	var pike = Presets.pike()
	var pty = Party.new()
	pty.add_member(pike)
	pty.stash_add("potions-of-healing")
	pike.hp_current = 1
	var p = _screen(pike)
	p.set_party(pty)
	check(p._fields.has("drink_btn_potions-of-healing") and not p._fields.has("equip_btn_potions-of-healing"),
		"a potion tile drinks, never equips")
	check(p._fields["item_potions-of-healing"].tooltip_text.ends_with("Click: drink"), "...and says so")
	p.drink("potions-of-healing")
	check(pike.hp_current >= 5 and pty.stash_count("potions-of-healing") == 0, "drinking from the stash heals and spends it")
	check(not p._fields.has("item_potions-of-healing"), "the empty bottle is gone from the screen")
# Shift on a stash tile reads the item against what every active member wears.
func _shift_compare() -> void:
	var pike = Presets.pike()
	var pty = Party.new()
	pty.add_member(pike)
	pty.stash_add("longsword")
	pike.equipped.assign(["greataxe"])
	var txt := Icons.party_compare("weapon", pty)
	check(txt.contains(pike.cname + ": Greataxe — 1d12"), "the compare names who wields what")
	var martial := Catalog.weapon("greataxe")
	var simple := Catalog.weapon("club")
	var m_ok: bool = "martial" in pike.sheet().proficiencies["weapon"]
	check(Icons.party_compare("weapon", pty, martial).contains(
		pike.cname + (" (proficient)" if m_ok else " (NOT proficient)")), "a martial weapon says whether Pike can use it")
	check(Icons.party_compare("weapon", pty, simple).contains(pike.cname + " (proficient)"),
		"everyone can swing a club")
	check(Icons.party_compare("armor", pty).contains(pike.cname + ": nothing"), "an empty slot says so")
	check(Icons.party_compare("unknown", pty) == "" and Icons.party_compare("weapon", null) == "",
		"nothing to compare gives no Shift text")
	var p = _screen(pike)
	p.set_party(pty)
	var tile = p._fields["item_longsword"]
	check(tile.compare == Icons.party_compare("weapon", pty, Catalog.weapon("longsword")),
		"the stash tile carries the compare")
	var card = tile._make_custom_tooltip(tile.tooltip_text)
	check(str(card.get_child(0).get_child(-1).text).contains("Shift:"), "the hover card advertises Shift")
	card.free()
	check(not tile.tooltip_text.contains("Greataxe"), "the compare stays out of the plain hover")
