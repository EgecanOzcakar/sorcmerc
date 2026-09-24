# The action bar's hover card (scenes/skill_card.gd), the dice it draws
# (scenes/die_icon.gd) and the damage/condition palette they share with the log
# and the combat card (core/ui_icons.gd). Uses the demo fight's Ilsa Vane for
# real verbs, the way tests/test_action_bar.gd does.
#   godot --headless --path . -s tests/test_skill_card.gd
extends SceneTree

const Icons = preload("res://core/ui_icons.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const SkillCard = preload("res://scenes/skill_card.gd")
const DieIcon = preload("res://scenes/die_icon.gd")
const Main = preload("res://scenes/main.gd")
const Settings = preload("res://core/settings.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Every node under `n` of type `cls`.
func _all(n: Node, pred: Callable) -> Array:
	var out: Array = []
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c, pred))
	return out

func _init() -> void:
	# --- the palette ------------------------------------------------------
	check(Icons.damage_color("Fire") == Icons.DAMAGE_COLORS["fire"], "a damage type's colour ignores case")
	check(Icons.damage_color("fire") != Icons.damage_color("cold"), "fire and cold differ")
	check(Icons.condition_color("poisoned") == Icons.CONDITION_COLORS["poisoned"], "a condition has its colour")
	for id in Icons.CONDITION_GLYPHS:
		check(Icons.CONDITION_COLORS.has(id), "every condition with a glyph has a colour: %s" % id)
	var bb := Icons.tint_terms("A creature takes 3d6 Fire damage and is Poisoned.")
	check(bb.contains("[color=#%s]Fire[/color]" % Icons.damage_color("fire").to_html(false)), "tint_terms colours Fire: %s" % bb)
	check(bb.contains("[color=#%s]Poisoned[/color]" % Icons.condition_color("poisoned").to_html(false)), "...and Poisoned")
	check(not Icons.tint_terms("the fire-giant calms down").contains("[color=#%s]down" % Icons.condition_color("down").to_html(false)),
		"'down' in a sentence is just a word")
	check(Icons.tint_terms("roll [d4]") == "roll [lb]d4]", "square brackets are escaped for bbcode")
	check(Icons.tint_terms("firework") == "firework", "only whole words")
	var logged := Main.colorize("Ilsa hits the goblin for 7 fire damage", {})
	check(logged.contains("[color=#%s]fire[/color]" % Icons.damage_color("fire").to_html(false)),
		"the combat log tints damage types too: %s" % logged)

	# --- the shape tags -----------------------------------------------------
	check(SkillCard.shape_of({"targeting": "enemy"})[0] == "single", "an enemy-targeted verb is Single target")
	check(SkillCard.shape_of({"targeting": "ally"})[0] == "single", "...so is an ally-targeted one")
	check(SkillCard.shape_of({"targeting": "direction", "size_ft": 15}) == ["cone", "15 ft"], "a direction is a Cone, with its size")
	check(SkillCard.shape_of({"targeting": "corner", "size_ft": 20})[0] == "aoe", "a corner-anchored circle is AoE")
	check(SkillCard.shape_of({"targeting": "line", "size_ft": 100}) == ["aoe", "100 ft line"], "a line is AoE")
	check(SkillCard.shape_of({"targeting": "self_area", "size_ft": 10})[0] == "aoe", "an emanation is AoE")
	check(SkillCard.shape_of({"targeting": "self"})[0] == "self", "a self verb is Self")
	check(SkillCard.shape_of({"targeting": "hex", "teleport": true})[0] == "self", "Misty Step is Self, not AoE")

	# --- the two voices -----------------------------------------------------
	var split := SkillCard.split_prose(String(Catalog.spell("burning-hands")["description"]))
	check(split[0].contains("thin sheet of flames") and not split[0].contains("saving throw"),
		"Burning Hands' lore is its picture: %s" % split[0])
	check(split[1].begins_with("Each creature") and split[1].contains("3d6"), "...and its rules the rest: %s" % split[1])
	var ray := SkillCard.split_prose(String(Catalog.spell("scorching-ray")["description"]))
	check(not ray[0].contains("spell attack") and ray[1].begins_with("Make a ranged spell attack"),
		"'Make a ranged spell attack' is where Scorching Ray's rules start: %s" % ray[1])
	var cure := SkillCard.split_prose(String(Catalog.spell("cure-wounds")["description"]))
	check(cure[0] == "" and cure[1].contains("2d8"), "Cure Wounds is rules from its first word, so no lore half")
	check(SkillCard.parse_dice("1d6+3") == [1, 6, 3] and SkillCard.parse_dice("2d8 - 1") == [2, 8, -1]
		and SkillCard.parse_dice("7").is_empty(), "notation parses")

	# --- the dice -------------------------------------------------------------
	for pair in [[4, 3], [6, 4], [8, 4], [10, 4], [12, 5], [20, 6], [100, 6]]:
		check(DieIcon.outline(Vector2.ZERO, 40.0, pair[0]).size() == pair[1],
			"a d%d is a %d-cornered silhouette" % pair)
	for s in [4, 6, 8, 10, 12, 20]:
		var box := Rect2(-24, -24, 48, 48)
		check(Array(DieIcon.outline(Vector2.ZERO, 40.0, s)).all(func(p): return box.has_point(p)),
			"a d%d stays inside its box" % s)

	# --- a real verb, through the real bar ------------------------------------
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var ilsa = null
	for c in main.cb.combatants:
		if c.cname == "Ilsa Vane":
			ilsa = c
	check(ilsa != null, "Ilsa Vane is in the demo party")
	if ilsa == null:
		print("test_skill_card: %d passed, %d failed" % [_pass, _fail])
		quit(1); return

	var bh: Dictionary = {}
	for v in main.cb.all_verbs(ilsa):
		if String(v.get("spell", "")) == "burning-hands" and bh.is_empty():
			bh = v
	check(not bh.is_empty(), "she has Burning Hands")
	var prose: Array = Main._verb_prose(bh)
	var card := SkillCard.from_verb(ilsa, bh, prose[0], prose[1], Main._card_title(ilsa, bh))
	check(card["title"] == "Burning Hands", "the card is titled with the plain name")
	check(String(card["tags"][0][1]).begins_with("Cone"), "Burning Hands is tagged Cone (%s)" % str(card["tags"]))
	check(String(card["subtitle"]).contains("evocation") and String(card["subtitle"]).contains("Action"),
		"the subtitle names its school and its cost: %s" % card["subtitle"])
	var dmg: Array = (card["rolls"] as Array).filter(func(r): return int(r["sides"]) == 6)
	check(dmg.size() == 1 and int(dmg[0]["count"]) == 3 and dmg[0]["color"] == Icons.damage_color("fire"),
		"its damage row is three d6, drawn in fire's colour")
	var save: Array = (card["rolls"] as Array).filter(func(r): return int(r["sides"]) == 20)
	check(save.size() == 1 and String(save[0]["bb"]).contains("DEX"), "and a d20 row for the DEX save")

	var atk: Dictionary = main.cb.all_verbs(ilsa).filter(func(v): return v["kind"] == "attack")[0]
	var ac := SkillCard.from_verb(ilsa, atk, "", "", "Attack")
	check(String(ac["tags"][0][1]) == "Single target", "the Attack verb is Single target")
	check((ac["rolls"] as Array).any(func(r): return int(r["sides"]) == 20 and String(r["bb"]).contains("to hit")),
		"and rolls a d20 to hit")

	# The card, built: fixed width, both fonts, the dice drawn.
	var built: Control = SkillCard.build(card)
	root.add_child(built)
	await process_frame
	var w := SkillCard.CARD_W * Settings.chrome_scale()
	check(built.get_combined_minimum_size().x <= w + 40.0, "the card holds its width (%.0f for %.0f)" % [built.get_combined_minimum_size().x, w])
	var dice := _all(built, func(n): return n.get_script() == DieIcon)
	check(dice.size() == 4, "four dice drawn: the d20 for the save, three d6 (%d)" % dice.size())
	var fonts := _all(built, func(n): return n is Label and n.has_theme_font_override("font")) \
		.map(func(l): return l.get_theme_font("font"))
	check(fonts.has(Icons.serif_italic()), "the lore is set in the slanted serif")
	var rich := _all(built, func(n): return n is RichTextLabel)
	check(rich.any(func(r): return r.get_theme_font("normal_font") == Icons.sans(400)), "the rules in the sans")
	built.free()

	# A long plain text wraps instead of stretching the card.
	var long := SkillCard.build(SkillCard.from_text("Title\n" + "word ".repeat(200)))
	root.add_child(long)
	await process_frame
	check(long.get_combined_minimum_size().x <= w + 40.0, "a long text wraps inside the width")
	long.free()

	# The bar's buttons carry the card.
	main._build_hero_menu(ilsa)
	await process_frame
	var btns: Array = main._buttons.get_children()
	check(btns.all(func(b): return b is SkillCard.HoverButton and not b.card.is_empty()),
		"every bar button is a HoverButton with a card")
	var tip = btns[0]._make_custom_tooltip(btns[0].tooltip_text)
	check(tip is PanelContainer, "the hover builds the card")
	tip.free()
	main._buttons.get_child(1).pressed.emit()   # [2] Spells
	await process_frame
	var spells: Array = main._buttons.get_children().filter(func(b): return b.card.has("tags"))
	check(not spells.is_empty() and spells.all(func(b): return String(b.card["tags"][0][1]).split(" ")[0] in ["Single", "Cone", "AoE", "Self"]),
		"every spell on the list wears one of the four tags")

	print("test_skill_card: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
