# D3 — the road event card (scenes/world/event_card.gd). What is under test is
# the receipt, not the road: travel.gd has already rolled and already applied
# everything, so every case here is a hand-built dict of exactly the shape
# check() returns, plus one real Travel.check() event to prove the two halves
# still agree on key names.
#
# The house rule the card exists to keep — name the check and name the roll — is
# checked literally: the drawn text has to contain the skill, the natural, the
# bonus and the DC. The look is checked by eye with a shot script; what is
# checked here is that nothing is silently dropped and that a garbage dict
# cannot take the map down with it.
#   godot --headless --path . -s tests/test_event_card.gd
extends SceneTree

const EventCard = preload("res://scenes/world/event_card.gd")
const Icons = preload("res://core/ui_icons.gd")
const Travel = preload("res://core/travel.gd")
const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0
var _acks := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Everything the card actually put on screen, as one string. The card's _ops are
# the single source both _draw() and the button placement read, so asserting on
# them is asserting on the frame. Joined with a space, not a newline: a wrapped
# sentence is several ops, and a phrase that happens to straddle the wrap should
# still count as drawn.
func drawn(card) -> String:
	var out := ""
	for op in card._ops:
		if op.has("text"):
			out += String(op["text"]) + " "
	return out

func chip_count(card) -> int:
	var n := 0
	for op in card._ops:
		if op.has("rect"):
			n += 1
	return n

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func press(node: Node, label: String) -> bool:
	for b in buttons(node):
		if label in b.text and not b.disabled:
			b.pressed.emit()
			return true
	return false

func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

# A card of a known size, so "does this fit at 400px" is a real question and not
# whatever the headless window happens to be.
func card(w := 1280.0, h := 720.0):
	var c = EventCard.new()
	root.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.size = Vector2(w, h)
	return c

func good() -> Dictionary:
	return {"id": "cache", "title": "Something half-buried", "kind": "good", "ok": true,
		"text": "Vera Kord turns it up: a stash, and whoever left it is past needing it.",
		"cname": "Vera Kord", "skill": "investigation", "nat": 14, "bonus": 5, "dc": 14,
		"named": false}

func bad() -> Dictionary:
	return {"id": "foul-water", "title": "The stream runs wrong", "kind": "bad", "ok": false,
		"text": "It is noticed too late. The party travels the next stretch sick and slow.",
		"cname": "Brother Aldo", "skill": "medicine", "nat": 6, "bonus": -2, "dc": 13,
		"named": true}


func _init() -> void:
	# This file checks the OPEN card — what it says once the die has landed.
	# The live roll that comes first (scenes/dice_roll.gd) is tests/test_dice_roll.gd's;
	# SORCMERC_FAST opens the card on the first frame, as it does for every robot.
	OS.set_environment("SORCMERC_FAST", "1")
	# --- a good event and a bad one both render, and read apart ------------
	var g = card()
	g.show_event(good())
	var gt := drawn(g)
	check("Something half-buried" in gt, "a good event shows its title")
	check("half-buried" in gt and "stash" in gt, "...and the prose travel.gd wrote")
	check(g._btn != null and g._btn.text != "", "...with one obvious way out")

	var b = card()
	b.show_event(bad())
	var bt := drawn(b)
	check("The stream runs wrong" in bt, "a bad event shows its title")
	check("sick and slow" in bt, "...and its prose")

	# The glance-level read, before a word: a different stripe colour, a
	# different mark, a different caption.
	check(g._kind_color() != b._kind_color(), "good and bad wear different colours")
	check(g._kind_color() == preload("res://core/ui_icons.gd").COL_GOLD,
		"...good is the payoff colour, not an invented one")
	check(b._kind_color() == preload("res://core/ui_icons.gd").COL_FOE,
		"...bad is the cost colour")
	check(EventCard.KIND_GLYPH["good"] != EventCard.KIND_GLYPH["bad"],
		"...and a different mark")
	check(EventCard.KIND_CAPTION["good"] in gt, "the good caption is actually drawn")
	check(EventCard.KIND_CAPTION["bad"] in bt, "...and the bad one")
	check(not (EventCard.KIND_CAPTION["bad"] in gt), "...and they do not both draw")

	# --- name the check, name the roll ------------------------------------
	check("Vera Kord" in gt, "the roll line names who rolled")
	check("Investigation" in gt, "...and the skill")
	check("14" in gt, "...and the natural")
	check("+5" in gt, "...and the bonus, signed")
	check("DC 14" in gt, "...and the DC")
	check("Investigation 14+5 vs DC 14" in gt, "the whole roll reads as one house-rule line")
	# A forced march is -2 (travel.gd PACE); "6+-2" is not a roll.
	check("Medicine 6-2 vs DC 13" in bt, "a negative bonus renders as a subtraction")
	check("made it" in gt, "a passed roll says so")
	check("missed" in bt, "...and a failed one says so")

	# --- the standing order is credited -----------------------------------
	check("Brother Aldo" in bt and "standing orders" in bt.to_lower(),
		"named=true credits the player's own standing order")
	check("No standing order" in gt, "named=false says nobody was named")
	var e_unnamed := good()
	e_unnamed.erase("named")
	g.show_event(e_unnamed)
	check(not ("standing order" in drawn(g).to_lower()),
		"no `named` key at all means no claim either way")

	# --- the optional keys, each one present then absent -------------------
	var lean := good()
	g.show_event(lean)
	var lean_chips := chip_count(g)
	check(lean_chips == 0, "an event with no consequences draws no chips")

	var paid := good()
	paid["gold"] = 37
	g.show_event(paid)
	check("+37 gold" in drawn(g), "gold is shown when it was paid")
	check(chip_count(g) == lean_chips + 1, "...as exactly one chip")

	var hurt := bad()
	hurt["hurt"] = 12
	b.show_event(hurt)
	check("12 hp" in drawn(b), "hp lost is shown")

	var slow := bad()
	slow["minutes"] = 240.0
	b.show_event(slow)
	check("4h" in drawn(b), "time lost is shown in hours, the way the clock reads")
	check("lost" in drawn(b), "...and says it was lost")

	var quick := good()
	quick["minutes"] = -90.0
	g.show_event(quick)
	check("1h 30m" in drawn(g), "time saved is shown to the minute")
	check("saved" in drawn(g), "...and says it was saved")

	var found := good()
	found["lair"] = "Blackfen Barrow"
	g.show_event(found)
	check("Blackfen Barrow" in drawn(g), "a revealed lair is named")
	check("on the map" in drawn(g), "...and says where to look for it")

	# D3.1: the road can take coin as well as hand it over (a ford that keeps a
	# pack, a toll post that gets paid — and D4's parley toll, which has always
	# passed a negative gold through this card and always drew it as "+-40").
	var robbed := bad()
	robbed["gold"] = -40
	b.show_event(robbed)
	check("-40 gold" in drawn(b), "gold taken renders as a subtraction, not as +-")
	check(not ("+-" in drawn(b)), "...with no doubled sign anywhere on the card")

	var mended := good()
	mended["healed"] = 9
	g.show_event(mended)
	check("+9 hp" in drawn(g), "hp healed is shown")
	check("across the party" in drawn(g), "...and says who got it")

	var salvaged := good()
	salvaged.merge({"item": "chain-shirt", "item_name": "Chain Shirt"}, true)
	g.show_event(salvaged)
	check("Chain Shirt" in drawn(g), "salvage is named")
	check("stash" in drawn(g), "...and says where it went")

	var thanked := good()
	thanked["thanks"] = "Riverhold"
	g.show_event(thanked)
	check("Riverhold hears of it" in drawn(g), "goodwill names who heard about it")

	# The skill is labelled the way the character sheet labels it. Every other
	# skill id is one word and capitalize() is right; "animalhandling" is the one
	# that is two, and "Animalhandling" on a card is a typo with a reason.
	var beasts := good()
	beasts["skill"] = "animalhandling"
	g.show_event(beasts)
	check("Animal Handling" in drawn(g), "a two-word skill reads as two words")
	check(not ("Animalhandling" in drawn(g)), "...and not as the id it came from")

	var everything := good()
	everything.merge({"gold": 20, "hurt": 3, "minutes": 60.0, "lair": "Grey Fen"}, true)
	g.show_event(everything)
	check(chip_count(g) == 4, "all four consequences can coexist")
	var the_lot := good()
	the_lot.merge({"gold": -20, "hurt": 3, "healed": 2, "minutes": 60.0, "lair": "Grey Fen",
		"item": "dagger", "item_name": "Dagger", "thanks": "Riverhold"}, true)
	g.show_event(the_lot)
	check(chip_count(g) == 7, "...and so can every consequence D3.1 added (%d)" % chip_count(g))
	g.show_event(good())
	check(chip_count(g) == 0, "...and none of them stick around for the next event")

	# --- garbage in, a card out -------------------------------------------
	var junk = card()
	junk.show_event({})
	var jt := drawn(junk)
	check(jt.strip_edges() != "", "an empty dict still renders something")
	check(EventCard.NO_TITLE in jt, "...a stand-in title")
	check(EventCard.NO_TEXT in jt, "...and a stand-in line")
	check(not ("vs DC" in jt), "...but no roll it does not have")
	check(chip_count(junk) == 0, "...and no consequences it does not have")
	junk.show_event({"kind": 7, "title": null, "nat": "x", "gold": "many", "minutes": {}})
	check(drawn(junk).strip_edges() != "", "a dict of wrong types does not take the map down")

	# --- it fits where it has to ------------------------------------------
	var narrow = card(400.0, 640.0)
	narrow.show_event(everything)
	check(narrow._panel.position.x >= 0.0 and narrow._panel.end.x <= 400.0,
		"the panel stays inside a ~400px window")
	check(narrow._btn.position.x >= narrow._panel.position.x
			and narrow._btn.position.x + narrow._btn.size.x <= narrow._panel.end.x,
		"...and so does its button")
	var wide = card(1280.0, 720.0)
	wide.show_event(everything)
	check(wide._panel.size.x <= EventCard.PANEL_MAX_W,
		"a 1280px window does not stretch the body text across the whole screen")
	check(wide._panel.position.y >= 0.0, "the card is on screen vertically too")

	# --- the one signal, exactly once -------------------------------------
	var d = card()
	d.acknowledged.connect(_ack)
	d.show_event(bad())
	check(press(d, "road"), "the dismiss button is pressable")
	check(_acks == 1, "the button emits acknowledged")
	press(d, "road")
	d._input(key(KEY_ESCAPE))
	d._input(key(KEY_ENTER))
	check(_acks == 1, "...exactly once, however many ways out are taken after it")

	_acks = 0
	d.show_event(good())
	d._input(key(KEY_ESCAPE))
	check(_acks == 1, "Esc dismisses a fresh card")

	_acks = 0
	d.show_event(good())
	d._input(key(KEY_ENTER))
	check(_acks == 1, "Enter dismisses a fresh card")

	_acks = 0
	d.show_event(good())
	d._input(key(KEY_KP_ENTER))
	check(_acks == 1, "so does the keypad's Enter")

	_acks = 0
	d.show_event(good())
	d._input(key(KEY_A))
	check(_acks == 0, "a key that is not a way out is not a way out")

	# --- the seam with travel.gd ------------------------------------------
	# Not a re-test of travel.gd's maths: this only proves the card can read a
	# dict it did not make up, so a renamed key fails here instead of on screen.
	var real := _real_event()
	if not real.is_empty():
		var r = card()
		r.show_event(real)
		var rt := drawn(r)
		check(String(real["title"]) in rt, "a real Travel.check() event renders its title")
		if real.has("nat"):
			check("vs DC %d" % int(real["dc"]) in rt, "...and its actual DC")
			check(String(real["cname"]) in rt, "...and whoever travel.gd picked")
	else:
		check(false, "Travel.check() produced no event to render")

	# --- the picture: the outcome's frame when there is one, and space made for it
	var pic = card()
	pic.show_event({"id": "tracks", "title": "Tracks", "kind": "good", "ok": true, "text": "x"})
	check(pic._art == Icons.event_art("tracks", true) and pic._art != null, "a passed Tracks shows the pass frame")
	check(pic._art_rect.size.y == pic.ART_H and pic._art_rect.position.y > pic._panel.position.y,
		"...and the card makes room for it")
	var pf = card()
	pf.show_event({"id": "tracks", "title": "Tracks", "kind": "bad", "ok": false, "text": "x"})
	check(pf._art == Icons.event_art("tracks", false) and pf._art != pic._art, "a failed one shows the fail frame")
	var none = card()
	none.show_event({"id": "no-such-event", "title": "?", "kind": "good", "text": "x"})
	check(none._art == null and none._art_rect.size == Vector2.ZERO, "an event with no art reserves no space")
	var named = card()
	named.show_event({"id": "no-such-event", "art": "camp-night", "title": "?", "kind": "good", "text": "x"})
	check(named._art != null and named._art == Icons.scene_art("camp-night", null), "an `art` key names the picture outright, whatever the id")
	check(Icons.event_art("good-ground", false) == Icons.event_art("good-ground", null), "no fail frame: the plain scene")
	for e in Travel.EVENTS:
		check(Icons.event_art(String(e["id"]), true) != null, "every road event has a picture (%s)" % e["id"])

	print("test_event_card: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ack() -> void:
	_acks += 1


# Wind the clock until travel.gd actually fires something. check() is seeded off
# world.clock.elapsed, so stepping it is enough; a handful of tries is plenty.
func _real_event() -> Dictionary:
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	var w = World.new()
	w.add_party(World.RoamingParty.new("player", Vector2.ZERO, "human", true))
	Travel.set_orders(p, "careful", "", "")
	for i in 60:
		w.clock.elapsed += Travel.EVENT_INTERVAL
		var e: Dictionary = Travel.check(p, w)
		if not e.is_empty() and e.has("nat"):
			return e
	return {}
