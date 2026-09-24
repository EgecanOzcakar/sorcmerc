# T28: the combat screen's presentation-layer helpers — the log colorizer (a pure
# string -> bbcode function) and the token/order-strip glyph lookup.
#   godot --headless --path . -s tests/test_ui_log.gd
extends SceneTree

const Main = preload("res://scenes/main.gd")
const Icons = preload("res://core/ui_icons.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")
const Adapter = preload("res://core/adapter.gd")

const NAMES := {"Kaelin Vore": "#8fdc97", "Grull": "#e58a84"}

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	test_names()
	test_dice()
	test_numbers()
	test_verbs()
	test_plain_and_safety()
	test_glyphs()
	test_reveal_head()
	test_tooltips_name_their_dice()
	test_attack_swap()
	test_actor_economy_badges()
	test_actor_hp_readout_is_colored()
	print("test_ui_log: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# Strip every [color=..]..[/color] wrapper: the visible text must never change.
func _plain(bb: String) -> String:
	var re := RegEx.create_from_string(r"\[/?color[^\]]*\]")
	return re.sub(bb, "", true)

func test_names() -> void:
	var out: String = Main.colorize("Kaelin Vore hits Grull.", NAMES)
	check("[color=#8fdc97]Kaelin Vore[/color]" in out, "party name tinted green")
	check("[color=#e58a84]Grull[/color]" in out, "foe name tinted red")
	check(_plain(out) == "Kaelin Vore hits Grull.", "colorizing never changes the text")
	# A name appearing twice is tinted both times.
	check(Main.colorize("Grull vs Grull", NAMES).count("[color=#e58a84]") == 2, "every occurrence tinted")

func test_dice() -> void:
	var out: String = Main.colorize("rolls d20[14, 3] and 2d6+2", {})
	check("[color=%s]d20[14, 3][/color]" % Main.COL_DICE in out, "d20[..] notation tinted")
	check("[color=%s]2d6[/color]" % Main.COL_DICE in out, "NdM notation tinted")
	check(_plain(out) == "rolls d20[14, 3] and 2d6+2", "dice text unchanged")

func test_numbers() -> void:
	for phrase in ["7 damage", "12 HP", "30 gold", "50 XP", "40 ◉"]:
		var out: String = Main.colorize("gains " + phrase, {})
		check("[color=%s]%s[/color]" % [Main.COL_NUM, phrase.split(" ")[0]] in out,
			"number before '%s' tinted" % phrase.split(" ")[1])
	check(not ("[color" in Main.colorize("speed 4 hexes", {})), "bare numbers left alone")

func test_verbs() -> void:
	check("[color=%s]hits[/color]" % Main.VERB_COLORS["hits"] in Main.colorize("a hits b", {}), "hits")
	check("[color=%s]misses[/color]" % Main.VERB_COLORS["misses"] in Main.colorize("a misses b", {}), "misses")
	check("[color=%s]CRITS[/color]" % Main.VERB_COLORS["CRITS"] in Main.colorize("a CRITS b", {}), "CRITS")
	check("[color=%s]casts[/color]" % Main.VERB_COLORS["casts"] in Main.colorize("a casts Shield", {}), "casts")
	check("[color=%s]moves[/color]" % Main.VERB_COLORS["moves"] in Main.colorize("a moves 2", {}), "moves")
	check(not ("[color" in Main.colorize("hitsomething", {})), "verbs match whole words only")

func test_plain_and_safety() -> void:
	check(Main.colorize("The shrine is quiet.", {}) == "The shrine is quiet.", "plain line untouched")
	check(Main.colorize("", NAMES) == "", "empty line survives")
	# Overlapping spans (name containing a verb-like word) must not nest tags.
	var out: String = Main.colorize("Grull hits Grull for 5 damage", NAMES)
	check(out.count("[color=") == out.count("[/color]"), "tags balanced")
	check(_plain(out) == "Grull hits Grull for 5 damage", "overlap-safe")

func test_glyphs() -> void:
	for c in _fight().combatants:
		check(Icons.combatant_glyph(c) != "", "%s has a token glyph" % c.cname)

func _fight():
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	return Encounter.build({"seed": 7}, p.to_combatants(Encounter.PARTY_STARTS))

# T29: the popup leads with the outcome, never the raw d20.
func test_reveal_head() -> void:
	check(Main._reveal_head({"hit": false, "damage": 0})[0] == "MISS", "miss reads MISS")
	check("HIT" in Main._reveal_head({"hit": true, "damage": 7})[0], "hit reads HIT")
	check("7" in Main._reveal_head({"hit": true, "damage": 7})[0], "hit shows the damage")
	check("CRIT" in Main._reveal_head({"hit": true, "crit": true, "damage": 12})[0], "crit reads CRIT")
	check("SAVED" in Main._reveal_head({"saved": true, "damage": 3})[0], "made save reads SAVED")
	check("FAILED" in Main._reveal_head({"saved": false, "damage": 9})[0], "failed save reads FAILED")
	check(Main._reveal_head({"countered": true})[0] == "COUNTERED",
		"a countered spell says so on the board, not only in the log")

# T29: every verb gets a tooltip, and every damaging one names its dice.
func test_tooltips_name_their_dice() -> void:
	var re := RegEx.create_from_string(r"\d+d\d+")
	var cb = _fight()
	for c in cb.combatants:
		for v in cb.available(c):
			var tip: String = Main._verb_tooltip(c, v)
			check(tip.strip_edges() != "", "%s: %s has a tooltip" % [c.cname, v["label"]])
			if v["kind"] == "attack":
				check(re.search(tip) != null, "%s: Attack names its dice" % c.cname)
			elif v.has("dice_count") or v.has("heal_count"):
				check(re.search(tip) != null, "%s: %s names its dice" % [c.cname, v["label"]])

# T29: the melee/ranged toggle rewrites the stats the Attack verb swings with.
func test_attack_swap() -> void:
	var c = _fight().combatants[0]
	c.attacks = [
		{"id": "sword", "name": "Sword", "to_hit": 5, "notation": "1d8+3", "range": "melee", "normal_ft": 5},
		{"id": "bow", "name": "Bow", "to_hit": 7, "notation": "1d6+4", "range": "ranged", "normal_ft": 80},
	]
	Adapter.set_main_attack(c, "sword")
	check(not c.ranged and c.atk_range == 1 and c.damage == "1d8+3", "melee main hand")
	var other := Main._attack_swap(c)
	check(other.get("id") == "bow", "the swap offers the ranged weapon")
	check(Adapter.set_main_attack(c, "bow"), "switching to the bow works")
	check(c.ranged and c.atk_range > 1 and c.atk_bonus == 7 and c.damage == "1d6+4", "ranged stats applied")
	check(Main._attack_swap(c).get("id") == "sword", "and the swap offers the sword back")
	check(not Adapter.set_main_attack(c, "trebuchet"), "an unequipped weapon is refused")

# The actor line's action-economy badges: present while the resource is
# unspent, gone (not dimmed) once it's not -- compact over exhaustive.
func test_actor_economy_badges() -> void:
	var c = _fight().combatants[0]
	c.econ["action"] = 1; c.econ["bonus"] = 1; c.econ["move_left"] = 5
	var full := Main._econ_bb(c)
	check("Ⓐ" in full and "Ⓑ" in full and "➤ 5" in full, "both badges show while unspent")
	c.econ["action"] = 0
	var spent := Main._econ_bb(c)
	check(not "Ⓐ" in spent and "Ⓑ" in spent, "a spent resource's badge disappears, not just dims")

func test_actor_hp_readout_is_colored() -> void:
	var c = _fight().combatants[0]
	c.hp = c.max_hp
	check("[color=" in Main._hp_bb(c) and "%d/%d" % [c.hp, c.max_hp] in Main._hp_bb(c),
		"HP is colorized and shows current/max")
