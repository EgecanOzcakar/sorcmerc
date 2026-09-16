# D4 — the approach card (scenes/world/approach_card.gd). What is under test is
# the *asking*: that every way approach.gd offers gets a row, that each row
# prices itself (who rolls, what they roll, their bonus, the DC) before the
# press, and that whichever of the several doors the player takes, the world
# screen is told exactly once.
#
# Most cases are hand-built option arrays of the shape Approach.options()
# returns, so a row can be given exactly one interesting property at a time; the
# last block runs the real Approach.options() against a monster band and a
# civilized one, so a renamed key fails in CI rather than on screen.
#
# The look is checked by eye with a shot script. What is checked here is that
# nothing load-bearing is silently dropped, that a garbage array cannot take the
# map down, and that a card with no cancel cannot be left with no way out.
#   godot --headless --path . -s tests/test_approach_card.gd
extends SceneTree

const ApproachCard = preload("res://scenes/world/approach_card.gd")
const Approach = preload("res://core/approach.gd")
const Travel = preload("res://core/travel.gd")
const World = preload("res://core/world.gd")
const Party = preload("res://core/party.gd")

var _pass := 0
var _fail := 0
var _got: Array[String] = []

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Everything the card put on screen, as one string. _ops is the single source
# _draw() replays, so asserting on it is asserting on the frame.
func drawn(card) -> String:
	var out := ""
	for op in card._ops:
		if op.has("text"):
			out += String(op["text"]) + " "
	return out

# Just one option's row. The rows are real rectangles (the buttons are placed on
# them), so "is the DC on the ambush button" is a question with a literal answer
# rather than a search of the whole card.
func row_text(card, i: int) -> String:
	if i < 0 or i >= card._rows.size():
		return ""
	var r := Rect2(card._rows[i]["rect"])
	var out := ""
	for op in card._ops:
		if not op.has("text") or not op.has("pos"):
			continue
		var p := Vector2(op["pos"])
		if p.y >= r.position.y and p.y <= r.end.y and p.x >= r.position.x and p.x <= r.end.x + 2.0:
			out += String(op["text"]) + " "
	return out

func buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(buttons(c))
	return out

func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

# A card of a known size, so "does this fit at 400px" is a real question and not
# whatever the headless window happens to be.
func card(w := 1280.0, h := 720.0):
	var c = ApproachCard.new()
	root.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.size = Vector2(w, h)
	c.chosen.connect(_chose)
	return c

# The four ways, in approach.gd's own order, with the shape options() returns.
func four() -> Array:
	return [
		{"id": "avoid", "label": "Slip away", "note": "No fight, and nothing to show for it.",
			"dc": 13, "char_id": "vera", "cname": "Vera Kord", "skill": "stealth",
			"bonus": 7, "named": true},
		{"id": "parley", "label": "Parley", "note": "Buy your way past. They will want something.",
			"dc": 14, "char_id": "aldo", "cname": "Brother Aldo", "skill": "persuasion",
			"bonus": 3, "named": false},
		{"id": "ambush", "label": "Set an ambush",
			"note": "Take the first round — or hand it to them.",
			"dc": 15, "char_id": "vera", "cname": "Vera Kord", "skill": "survival",
			"bonus": -2, "named": false},
		{"id": "engage", "label": "Engage", "dc": 0,
			"note": "Straight at them. No edge, no surprises."},
	]

# A band that cannot be talked to (approach.gd's MINDLESS): parley is dropped,
# and three options is not a broken four. The card must never assume a fixed
# number of rows.
func three() -> Array:
	var out := four()
	out.remove_at(1)
	return out


func _init() -> void:
	# --- a row per way, and nothing else -----------------------------------
	var c = card()
	c.show_approach(four(), "Goblins (3)")
	check(c._btns.size() == 4, "four options get four buttons")
	check(buttons(c).size() == 4, "...and the card has no other button on it")
	check(c._rows.size() == 4, "...each with a row drawn under it")
	var t := drawn(c)
	check("Goblins (3)" in t, "the band the caller named is on the card")
	check(ApproachCard.CAPTION in t, "...under the caption")
	check("Slip away" in t and "Parley" in t and "Set an ambush" in t and "Engage" in t,
		"every option's label is drawn")
	check("No fight, and nothing to show for it." in t, "...and approach.gd's sell with it")

	# --- the whole point: each row prices itself ---------------------------
	var r0 := row_text(c, 0)
	check("Slip away" in r0, "row 1 is the first option in the array")
	check("Vera Kord" in r0, "...and names who would roll")
	check("Stealth" in r0, "...and the skill")
	check("+7" in r0, "...and the bonus, signed")
	check("vs DC 13" in r0, "...and the DC")
	check("Vera Kord · Stealth +7 vs DC 13" in r0, "...as one priced line")
	var r1 := row_text(c, 1)
	check("Brother Aldo · Persuasion +3 vs DC 14" in r1, "row 2 prices its own check")
	# A forced march is a -2 (travel.gd PACE) and approach.gd has already folded
	# it in; "Survival 2" when the real number is -2 is the one lie that matters.
	var r2 := row_text(c, 2)
	check("Survival -2" in r2, "a negative bonus renders as a subtraction")
	check("vs DC 15" in r2, "...and the hardest DC is the ambush's")

	# --- engage is the one with no roll ------------------------------------
	var r3 := row_text(c, 3)
	check("Engage" in r3, "the last row is engage")
	check(not ("vs DC" in r3), "engage shows no DC, because it rolls nothing")
	check(ApproachCard.NO_ROLL_TEXT in r3, "...and says so rather than leaving a hole")
	check(not (ApproachCard.NO_ROLL_TEXT in r0), "a row that does roll does not say 'no roll'")

	# --- the key binding is announced --------------------------------------
	check("1-4" in t, "the header says which number keys are bound")
	var c3 = card()
	c3.show_approach(three(), "Goblins (3)")
	check("1-3" in drawn(c3), "...and counts the options it actually has")

	# --- three options is not a broken four --------------------------------
	check(c3._btns.size() == 3, "three options get three buttons")
	check(not ("Parley" in drawn(c3)), "a band that will not talk shows no parley row")
	check("Slip away" in row_text(c3, 0) and "Set an ambush" in row_text(c3, 1)
		and "Engage" in row_text(c3, 2), "...and the rest keep their order")

	# --- the standing order is credited ------------------------------------
	check(ApproachCard.NAMED_MARK in r0, "named=true marks the row")
	check(not (ApproachCard.NAMED_MARK in r1), "named=false does not")
	check("standing orders" in t.to_lower(), "...and the header says what the mark means")
	var none := four()
	for o in none:
		o.erase("named")
	var c4 = card()
	c4.show_approach(none, "Goblins (3)")
	check(not (ApproachCard.NAMED_MARK in drawn(c4)), "no named key at all, no mark")
	check(not ("standing orders" in drawn(c4).to_lower()),
		"...and no explanation of a mark that is not there")

	# --- pressing, exactly once --------------------------------------------
	_got.clear()
	var p = card()
	p.show_approach(four(), "Goblins (3)")
	p._btns[2].pressed.emit()
	check(_got == ["ambush"], "pressing a row emits that row's id")
	p._btns[0].pressed.emit()
	p._btns[3].pressed.emit()
	p._input(key(KEY_1))
	check(_got == ["ambush"], "...and nothing after it, however many rows are pressed")

	_got.clear()
	var e = card()
	e.show_approach(four(), "Goblins (3)")
	e._input(key(KEY_ESCAPE))
	check(_got.is_empty(), "there is no cancel: Esc is not a way out")
	e._btns[1].pressed.emit()
	check(_got == ["parley"], "...and the card still works after it")

	# --- the number keys ----------------------------------------------------
	for i in 4:
		_got.clear()
		var k = card()
		k.show_approach(four(), "Goblins (3)")
		k._input(key(ApproachCard.NUM_KEYS[i]))
		check(_got == [String(four()[i]["id"])],
			"key %d picks option %d" % [i + 1, i + 1])
	_got.clear()
	var kp = card()
	kp.show_approach(four(), "Goblins (3)")
	kp._input(key(KEY_KP_3))
	check(_got == ["ambush"], "the keypad's numbers work too")
	_got.clear()
	var over = card()
	over.show_approach(three(), "Goblins (3)")
	over._input(key(KEY_4))
	check(_got.is_empty(), "a number with no option under it does nothing")
	over._input(key(KEY_A))
	check(_got.is_empty(), "...and neither does a key that was never bound")
	over._input(key(KEY_2))
	check(_got == ["ambush"], "...while the keys that are bound still are")

	# --- nothing in, a card out ---------------------------------------------
	# An empty array should be impossible — approach.gd always offers engage —
	# but a modal with no buttons over a paused world is a soft-lock.
	_got.clear()
	var empty = card()
	empty.show_approach([], "")
	check(empty._btns.size() == 1, "an empty options array still leaves one way out")
	check(ApproachCard.NO_FOE in drawn(empty), "...and a stand-in for the band's name")
	check(drawn(empty).strip_edges() != "", "...and renders something rather than a gilt box")
	empty._btns[0].pressed.emit()
	check(_got == [ApproachCard.FALLBACK_WAY],
		"...that the world screen's rules can actually resolve")

	# --- garbage in, a card out ---------------------------------------------
	_got.clear()
	var junk = card()
	junk.show_approach([{"label": null, "dc": "x", "bonus": {}, "skill": 7, "named": "false"},
		5, null], "Goblins (3)")
	check(junk._btns.size() == 3, "a row per entry, whatever the entries are")
	check(drawn(junk).strip_edges() != "", "a dict of wrong types does not take the map down")
	check(ApproachCard.NO_LABEL in drawn(junk), "...an entry with no label gets a stand-in one")
	check(not (ApproachCard.NAMED_MARK in drawn(junk)),
		"the string \"false\" is not a true flag")
	junk._btns[1].pressed.emit()
	check(_got == [ApproachCard.FALLBACK_WAY],
		"an entry that is not even a dictionary still emits a resolvable way")

	# --- it fits where it has to --------------------------------------------
	var narrow = card(400.0, 720.0)
	narrow.show_approach(four(), "Goblins (3)")
	check(narrow._panel.position.x >= 0.0 and narrow._panel.end.x <= 400.0,
		"the panel stays inside a ~400px window")
	var inside := true
	for i in narrow._btns.size():
		var b: Button = narrow._btns[i]
		inside = inside and b.position.x >= narrow._panel.position.x \
			and b.position.x + b.size.x <= narrow._panel.end.x and b.size.y > 0.0
	check(inside, "...and so does every one of its rows")
	check("vs DC 13" in row_text(narrow, 0), "...and a narrow row still shows its DC")
	# With the stakes lines a row is four lines, not two, so the tallest real card
	# (four ways, all of them priced) has to be re-checked against a small window
	# rather than assumed from the two-line version.
	var tall = card(400.0, 720.0)
	var tp = _party()
	tp.gold = 400
	tall.show_approach(Approach.options(tp, World.RoamingParty.new("men", Vector2(40.0, 0.0), "orc")),
		"Orc raiders (8)")
	check(tall._panel.end.y <= 720.0, "a fully priced four-way card still fits a 400x720 window (%.0f)" % tall._panel.end.y)
	# ...the picture is what gave way: a roomy window shows the full banner
	var roomy = card(1280.0, 900.0)
	roomy.show_approach(Approach.options(tp, World.RoamingParty.new("men", Vector2(40.0, 0.0), "orc")), "Orc raiders (8)")
	check(roomy._art_rect.size.y == roomy.ART_H and tall._art_rect.size.y < roomy.ART_H,
		"the banner is full-height where there is room (%.0f) and gives way where there is not (%.0f)" % [roomy._art_rect.size.y, tall._art_rect.size.y])
	check(roomy._art_of("avoid") != null and roomy._art_of("engage") != null, "every way has a picture")
	check(tall._panel.position.y >= 0.0, "...from the top edge down")
	var wide = card(1280.0, 720.0)
	wide.show_approach(four(), "Goblins (3)")
	check(wide._panel.size.x <= ApproachCard.PANEL_MAX_W,
		"a 1280px window does not stretch the rows across the whole screen")
	check(wide._panel.position.y >= 0.0, "the card is on screen vertically too")

	# --- the seam with approach.gd -------------------------------------------
	# Not a re-test of approach.gd's rules: this only proves the card can read an
	# array it did not make up, so a renamed key fails here instead of on screen.
	# The two bands are picked so the real options() comes back at both lengths:
	# undead are on approach.gd's MINDLESS deny-list, orcs want something.
	var party = _party()
	var mindless = World.RoamingParty.new("band", Vector2(40.0, 0.0), "undead")
	var men = World.RoamingParty.new("men", Vector2(40.0, 0.0), "orc")

	var mopts := Approach.options(party, mindless)
	var m = card()
	m.show_approach(mopts, "Barrow-wights (4)")
	check(mopts.size() == 3, "a real band that cannot be talked to offers three ways")
	check(m._btns.size() == mopts.size(), "...and the card draws a row for each")
	check("Barrow-wights (4)" in drawn(m), "...under the label the caller passed")
	var priced := true
	for i in mopts.size():
		var o: Dictionary = mopts[i]
		var rt := row_text(m, i)
		priced = priced and String(o["label"]) in rt
		if o.has("cname"):
			priced = priced and String(o["cname"]) in rt \
				and ("vs DC %d" % int(o["dc"])) in rt \
				and ("%+d" % int(o["bonus"])) in rt
	check(priced, "every real option draws its own label, roller, bonus and DC")

	# Both halves of every gamble, on the row. This is the fix for the thing that
	# was actually wrong with this card: it showed what each way BOUGHT and never
	# what it cost, so the three ways that roll all read as free upside and
	# engage — the one that cannot fail — read as the row with nothing on it.
	var staked := true
	var risked := true
	for i in mopts.size():
		var o: Dictionary = mopts[i]
		var rt := row_text(m, i)
		staked = staked and String(o.get("win", "")) != "" and String(o["win"]) in rt
		if String(o["id"]) == "engage":
			check(not o.has("lose"), "engage has no downside to state")
			check(not ApproachCard.LOSE_GLYPH in rt, "...and draws no loss line")
		else:
			risked = risked and String(o.get("lose", "")) != "" and String(o["lose"]) in rt
			# The subtraction a player would otherwise do under time pressure.
			staked = staked and ("needs %d+" % int(o["needs"])) in rt
	check(staked, "every way says what it buys, and what the die has to show")
	check(risked, "every way that rolls says what happens when it does not land")

	# The two ends of the odds display. 5.5e has no natural 1 or 20 on an ability
	# check, so both of these are real states a party can actually be in, and a
	# card that printed "needs 0+" or "needs 24+" would be lying about the only
	# number on it that decides anything.
	var sure = card()
	sure.show_approach([{"id": "avoid", "label": "Slip away", "dc": 10, "cname": "Pike",
		"skill": "stealth", "bonus": 12, "needs": Approach.needs(10, 12),
		"win": "Gone.", "lose": "Seen."}], "Bandits (2)")
	check("cannot fail" in drawn(sure), "a bonus past the DC says so (%s)" % drawn(sure))
	var hopeless = card()
	hopeless.show_approach([{"id": "ambush", "label": "Set an ambush", "dc": 30, "cname": "Pike",
		"skill": "stealth", "bonus": 2, "needs": Approach.needs(30, 2),
		"win": "First round.", "lose": "Their first round."}], "Bandits (2)")
	check("out of reach" in drawn(hopeless), "and a DC past the die says that (%s)" % drawn(hopeless))

	var copts := Approach.options(party, men)
	var cc = card()
	cc.show_approach(copts, "Orc raiders (8)")
	check(copts.size() == 4, "a band that can be talked to offers four")
	# A price you cannot see is not a price. "They will want something" was the
	# old line, and it is not a number anybody can weigh against a fight.
	var rich = _party()
	rich.gold = 400
	var rich_opts := Approach.options(rich, men)
	var rc = card()
	rc.show_approach(rich_opts, "Orc raiders (8)")
	for o in rich_opts:
		if String(o["id"]) == "parley":
			check(int(o["toll"]) > 0 and String(o["win"]).find(str(int(o["toll"]))) >= 0,
				"the parley names the actual toll (%s)" % o["win"])
			check(String(o["win"]) in drawn(rc), "...on the card, before it is chosen")
	# And an empty purse does not print "0 gold" at somebody.
	for o in copts:
		if String(o["id"]) == "parley":
			check(int(o["toll"]) == 0 and String(o["win"]).find("0 gold") < 0,
				"a party with nothing is told what that means (%s)" % o["win"])
	check("Parley" in drawn(cc), "...and the fourth is the parley")
	# thrun is the scout the orders below name, so approach.gd's `named` is true
	# for the two scout-role ways and the card has to carry that through.
	check(ApproachCard.NAMED_MARK in drawn(cc),
		"a real options() with a standing order set is credited on the card")

	# This card is modal over a paused world and has no cancel, so it must
	# swallow input rather than merely sit on top: a player who can still reach
	# "Party" or "← Title" on the HUD behind it can walk away from a decision
	# the world is waiting on.
	# ponytail: whether it also COVERS the viewport depends on the anchors set
	# in _ready(), which card() deliberately overrides to size the thing for
	# these tests — so that half belongs to a world-scene test, not here.
	check(card().mouse_filter == Control.MOUSE_FILTER_STOP,
		"the card stops mouse events rather than passing them through")

	print("test_approach_card: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _chose(way: String) -> void:
	_got.append(way)


func _party():
	var p = Party.new()
	for ch in Party.demo_roster():
		p.add_member(ch)
	Travel.set_orders(p, "careful", "thrun", "")
	return p
