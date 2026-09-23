# #176 step 1 — the pages personality traits show on: the creator's pick, the
# one-time offer to a hero from before traits (the party page), the profile
# panel, and the combat card's row. Headless.
#   godot --headless --path . -s tests/test_trait_pages.gd
extends SceneTree

const Traits = preload("res://core/traits.gd")
const Character = preload("res://core/character.gd")
const Creator = preload("res://scenes/creator/creator.gd")
const TraitOffer = preload("res://scenes/party/trait_offer.gd")
const CombatCard = preload("res://scenes/combat_card.gd")
const Party = preload("res://core/party.gd")
const Presets = preload("res://core/presets.gd")
const Adapter = preload("res://core/adapter.gd")
const Encounter = preload("res://core/encounter.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	await process_frame
	await test_creator()
	await test_offer()
	await test_party_page_offers_once()
	await test_profile_panel()
	await test_combat_card_row()
	print("test_trait_pages: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _text(n: Node) -> String:
	var out := ""
	if n is Label or n is Button:
		out += n.text + "\n"
	for c in n.get_children():
		out += _text(c)
	return out

func _old_hero(id: String, bg: String) -> Character:
	var ch := Character.new()
	ch.id = id
	ch.cname = id.capitalize()
	ch.species_id = "human"
	ch.background_id = bg
	ch.add_level("fighter", -1)
	return ch   # no traits, never offered: a save from before them

func test_creator() -> void:
	var cre = load("res://scenes/creator/creator.tscn").instantiate()
	root.add_child(cre)
	await process_frame
	cre.ch = Creator.new_character()
	cre.ch.cname = "Brenna"
	cre._set_species("dwarf")
	cre._set_class("fighter")
	cre._set_background("sailor")
	check(Traits.of(cre.ch, "temperament") == "generous" and Traits.of(cre.ch, "origin") == "marsh-bred",
		"a sailor starts Generous and Marsh-bred, pre-selected")
	cre._goto(3)
	await process_frame
	var t := _text(cre._body)
	check("Temperament" in t and "Origin" in t, "the background step has both rows")
	check("● Marsh-bred" in t and "● Generous" in t, "...with the background's picks lit")
	check("+1 AC in the marsh" in t, "...and says what the origin does")
	check(not "(not yet in play)" in t, "...and since step 4, every effect of a sailor's defaults is in play")
	# A trait with something still to come is marked so (Curious's hazard save).
	cre._set_trait("temperament", "curious")
	await process_frame
	check("(not yet in play)" in _text(cre._body), "...and what is still to come is marked")
	cre._set_trait("temperament", "craven")
	cre._set_background("soldier")
	check(Traits.of(cre.ch, "temperament") == "craven", "a temperament the player picked survives a background change")
	check(Traits.of(cre.ch, "origin") == "downs-rider", "...an untouched default follows it")
	cre.queue_free()
	await process_frame

func test_offer() -> void:
	var ch := _old_hero("hale", "guide")
	var o := TraitOffer.new()
	root.add_child(o)
	var got := []
	o.done.connect(func(kept): got.append(kept))
	o.offer(ch)
	await process_frame
	check(o.picks() == {"temperament": "generous", "origin": "woods-born"}, "the offer starts from the background (%s)" % str(o.picks()))
	check("Who is Hale?" in _text(o), "it asks who they are, by name")
	o.choose("temperament", "brave")
	o.choose("temperament", "marsh-bred")   # an origin offered as a temperament: refused
	check(o.picks()["temperament"] == "brave", "a pick changes the offer; a wrong-family pick does not")
	o.keep()
	check(got == [true] and Traits.ids(ch) == ["brave", "woods-born"] and ch.traits_offered, "Keep these writes them, and the hero is never asked again")
	o.keep()
	check(got.size() == 1, "...once")
	o.queue_free()

	var ch2 := _old_hero("tamsin", "sage")
	var o2 := TraitOffer.new()
	root.add_child(o2)
	o2.offer(ch2)
	o2.leave()
	check(Traits.ids(ch2).is_empty() and ch2.traits_offered and not Traits.needs_offer(ch2),
		"Leave them as they are writes nothing, and still counts as asked")
	o2.queue_free()
	await process_frame

func test_party_page_offers_once() -> void:
	var p := Party.new()
	var fresh := _old_hero("owen", "farmer")
	var made := _old_hero("rhea", "noble")
	Traits.fill_defaults(made)
	made.traits_offered = true
	p.add_member(made)
	p.add_member(fresh)
	var page = load("res://scenes/party/party.tscn").instantiate()
	page.party = p
	root.add_child(page)
	await process_frame
	check(page._offer != null, "a hero from before traits is offered the pick when the page opens")
	if page._offer != null:
		check(page._offer._ch == fresh, "...the one who needs it, not the one who has them")
		page._offer.keep()
		await process_frame
		await process_frame
	check(page._offer == null and Traits.of(fresh, "temperament") == "generous", "kept, the offer closes and the hero has traits")
	check("Generous, Downs-rider" in _text(page), "the roster card names them")
	page._refresh()
	await process_frame
	check(page._offer == null, "and it is never asked again")
	page.queue_free()
	await process_frame

	var demo = load("res://scenes/party/party.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	check(demo._offer == null, "the standalone demo roster (presets) is never offered anything")
	demo.queue_free()
	await process_frame

func test_profile_panel() -> void:
	var ch := _old_hero("ivo", "sailor")
	Traits.fill_defaults(ch)
	var p = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(p)
	p.set_character(ch)
	await process_frame
	check(p._fields.has("trait_marsh-bred") and p._fields.has("trait_generous"), "the profile lists both traits")
	var t := _text(p)
	check("Personality traits" in t and "+1 AC in the marsh" in t, "...under their heading, with what they do")
	p.queue_free()
	await process_frame

func test_combat_card_row() -> void:
	var ch := _old_hero("cass", "sailor")
	Traits.set_family(ch, "origin", "cave-dweller")
	Traits.set_family(ch, "temperament", "calm")
	var cb = Encounter.build({"theme": "frozen-cave", "seed": 7, "monsters": [{"id": "goblin", "count": 1}]},
		[Adapter.to_combatant(ch, "party", Encounter.PARTY_STARTS[0])])
	var hero = cb.team_of("party")[0]
	check(Traits.live_here(hero, cb) == ["cave-dweller", "calm"] or Traits.live_here(hero, cb) == ["calm", "cave-dweller"],
		"both count on the frozen cave: %s" % str(Traits.live_here(hero, cb)))
	var card := CombatCard.new()
	root.add_child(card)
	card.show_who(hero, cb)
	await process_frame
	var t := _text(card)
	check("Personality traits" in t and "Cave-dweller" in t and "Calm" in t, "the card has the row, by name")
	card.queue_free()
	var foe = cb.team_of("foe")[0]
	var card2 := CombatCard.new()
	root.add_child(card2)
	card2.show_who(foe, cb)
	await process_frame
	check(not "Personality traits" in _text(card2), "a goblin has no personality traits row")
	card2.queue_free()
	await process_frame
