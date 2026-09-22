# #173 — the character card on the left of the combat screen.
#
# Three claims worth holding down, and all three are the kind that fail
# silently: a card that shows the wrong creature just looks like a card, and a
# card that never clears looks like one too.
#
#   1. it fills from a hover and STAYS filled — that is the whole feature
#   2. it reads a hero and a monster, which carry their numbers differently
#      (a hero has a sheet with ability scores; a monster has save bonuses)
#   3. spells and traits come out as two lists, not one run
#
#   godot --headless --path . -s tests/test_combat_card.gd
extends SceneTree

const CombatCard = preload("res://scenes/combat_card.gd")
const Encounter = preload("res://core/encounter.gd")
const Adapter = preload("res://core/adapter.gd")
const Presets = preload("res://core/presets.gd")
const Icons = preload("res://core/ui_icons.gd")

var _pass = 0
var _fail = 0

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _init() -> void:
	root.theme = Icons.dark_theme()
	await test_fills_and_sticks()
	await test_reads_a_hero_and_a_monster()
	await test_spells_and_traits_are_separate()
	await test_every_verb_explains_itself()
	print("test_combat_card: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _fight():
	var chars: Array = Presets.party()
	var party: Array = []
	for i in chars.size():
		party.append(Adapter.to_combatant(chars[i], "party", Encounter.PARTY_STARTS[i]))
	return Encounter.build({"monsters": [{"id": "goblin", "count": 2, "mult": 1.0}],
		"theme": "goblin-camp", "seed": 7}, party)


func _card_with(cb) -> CombatCard:
	var card := CombatCard.new()
	root.add_child(card)
	return card


# Every Label anywhere under the card, joined — what a reader actually sees.
func _text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += n.text + "\n"
	for c in n.get_children():
		out += _text(c)
	return out


func test_fills_and_sticks() -> void:
	var cb = _fight()
	var card := _card_with(cb)
	check(not card.visible, "a card with nobody on it is not shown")
	check(card.showing() == "", "...and names nobody")

	var hero = cb.team_of("party")[0]
	card.show_who(hero, cb)
	await process_frame
	check(card.visible and card.showing() == hero.id, "a hover fills it")

	# The feature: nothing about moving the mouse away clears it. The screen
	# calls show_who only when a hover LANDS on somebody, so the proof is that
	# no other call is needed to keep it up.
	check(card.visible and card.showing() == hero.id, "...and it stays filled")

	var foe = cb.team_of("foe")[0]
	card.show_who(foe, cb)
	await process_frame
	check(card.showing() == foe.id, "hovering somebody else swaps it over")

	card.clear()
	await process_frame
	check(not card.visible and card.showing() == "", "the close button empties it")

	card.show_who(hero, cb)
	await process_frame
	check(card.visible, "...and a later hover fills it again")
	card.queue_free()


func test_reads_a_hero_and_a_monster() -> void:
	var cb = _fight()
	var card := _card_with(cb)

	var hero = cb.team_of("party")[0]
	card.show_who(hero, cb)
	await process_frame
	var t := _text(card)
	check(t.contains(hero.cname), "the card names the hero")
	check(t.contains("Abilities"), "a hero shows ability scores (it has a sheet)")
	for a in CombatCard.ABILITIES:
		check(t.contains(a.to_upper()), "...all six, including %s" % a.to_upper())
	check(t.contains("hp"), "and the health line")
	check(t.contains("AC %d" % cb.effective_ac(hero)), "and the AC the fight would use")

	var foe = cb.team_of("foe")[0]
	card.show_who(foe, cb)
	await process_frame
	t = _text(card)
	check(t.contains("Saves"), "a monster has no sheet, so it shows save bonuses instead")
	check(not t.contains("Abilities"), "...and does not claim to have ability scores")
	# "-/+": every one of the six is signed, either way.
	var signed := 0
	for line in t.split("\n"):
		for a in CombatCard.ABILITIES:
			if line.begins_with(a.to_upper()) and (line.contains("+") or line.contains("-")):
				signed += 1
	check(signed == 6, "all six read as signed numbers (%d did)" % signed)
	card.queue_free()


func test_spells_and_traits_are_separate() -> void:
	var cb = _fight()
	var card := _card_with(cb)
	# A caster, so there is something to put under each heading.
	var who = null
	for c in cb.team_of("party"):
		for v in c.verbs:
			if v.has("spell"):
				who = c
				break
		if who != null:
			break
	check(who != null, "the preset party fields somebody who casts")
	if who == null:
		card.queue_free()
		return
	card.show_who(who, cb)
	await process_frame
	var t := _text(card)
	check(t.contains("Spells"), "%s's spells get their own heading" % who.cname)
	# Every spell label is under Spells and no spell label is under Traits.
	var spells := t.split("Spells")[1] if t.contains("Spells") else ""
	var traits := spells.split("Traits")[1] if spells.contains("Traits") else ""
	if spells.contains("Traits"):
		spells = spells.split("Traits")[0]
	for v in who.verbs:
		if not v.has("spell"):
			continue
		var label := String(v.get("label", ""))
		if label == "":
			continue
		check(spells.contains(label), "'%s' is listed as a spell" % label)
		check(traits == "" or not traits.contains(label), "'%s' is not also a trait" % label)
	card.queue_free()


# The traits and spells on the card explain themselves on hover (a Bugbear
# having "Surprise Attack" tells a reader nothing about what Surprise Attack
# does). The text is main.gd's own _verb_tooltip, so what is checked here is
# that every chip HAS one and that it leads with the name — not the wording,
# which belongs to the action bar and is tested with it.
func test_every_verb_explains_itself() -> void:
	var cb = _fight()
	var card := _card_with(cb)
	var checked := 0
	# Every combatant, so the count is the roster's rather than a guess: the
	# first pass of this test asked for six chips across two cards and found
	# three, which was the threshold being wrong rather than the card.
	for who in cb.combatants:
		card.show_who(who, cb)
		await process_frame
		var tips: Array = _tips(card)
		for tip in tips:
			checked += 1
			check(tip[1] != "", "%s: '%s' has a tooltip" % [who.cname, tip[0]])
			check(tip[1].begins_with(tip[0]), "%s: '%s' leads with its own name" % [who.cname, tip[0]])
			check("\n" in tip[1], "%s: '%s' says more than its name" % [who.cname, tip[0]])
		# The real claim: one chip per distinct labelled verb, none dropped.
		var want := {}
		for v in who.verbs:
			if String(v.get("label", "")) != "":
				want[String(v["label"])] = true
		check(tips.size() == want.size(),
			"%s: a chip for each of its %d verbs (got %d)" % [who.cname, want.size(), tips.size()])
	check(checked > 0, "the roster fielded verbs to check at all (%d)" % checked)
	card.queue_free()
	await process_frame


# [label, tooltip] for every chip that takes the mouse.
func _tips(n: Node) -> Array:
	var out: Array = []
	if n is PanelContainer and n.mouse_filter == Control.MOUSE_FILTER_STOP \
			and n.get_child_count() == 1 and n.get_child(0) is Label:
		out.append([n.get_child(0).text, n.tooltip_text])
	for c in n.get_children():
		out.append_array(_tips(c))
	return out
