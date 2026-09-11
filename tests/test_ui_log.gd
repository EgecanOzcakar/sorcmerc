# T28: the combat screen's presentation-layer helpers — the log colorizer (a pure
# string -> bbcode function) and the token/order-strip glyph lookup.
#   godot --headless --path . -s tests/test_ui_log.gd
extends SceneTree

const Main = preload("res://scenes/main.gd")
const Icons = preload("res://core/ui_icons.gd")
const Encounter = preload("res://core/encounter.gd")
const Presets = preload("res://core/presets.gd")
const Party = preload("res://core/party.gd")

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
	for phrase in ["7 damage", "12 HP", "30 gold", "50 XP"]:
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
	var p := Party.new()
	for ch in Presets.party():
		p.add_member(ch)
	var cb = Encounter.build({"seed": 7}, p.to_combatants(Encounter.PARTY_STARTS))
	for c in cb.combatants:
		check(Icons.combatant_glyph(c) != "", "%s has a token glyph" % c.cname)
