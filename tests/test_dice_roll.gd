# Live rolls — scenes/dice_roll.gd, and the road's card rolling the die before
# it says what happened (scenes/world/event_card.gd). Headless: what the die
# lands on and says, that the card holds back the outcome while it is in the
# air, that a press lands it rather than skipping it, and that SORCMERC_FAST
# (every test and robot) sees the old, open card on the first frame.
#   godot --headless --path . -s tests/test_dice_roll.gd
extends SceneTree

const DiceRoll = preload("res://scenes/dice_roll.gd")
const EventCard = preload("res://scenes/world/event_card.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

const ROAD := {"id": "wolves", "title": "Wolves on the ridge", "kind": "bad",
	"text": "The pack circles, loses interest and slinks off.", "ok": true,
	"char_id": "vera", "cname": "Vera Kord", "skill": "survival", "nat": 14, "bonus": 5, "dc": 13,
	"gold": 12}

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	await test_die_fast()
	await test_card_fast_is_the_old_card()
	OS.set_environment("SORCMERC_FAST", "")
	await test_die_live()
	await test_card_rolls_then_opens()
	await test_card_without_a_roll()
	OS.set_environment("SORCMERC_FAST", "1")
	print("test_dice_roll: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _drawn(card) -> String:
	var out := ""
	for op in card._ops:
		if op.has("text"):
			out += String(op["text"]) + "\n"
	return out

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func test_die_fast() -> void:
	var d := DiceRoll.new()
	root.add_child(d)
	var got := [0]
	d.landed.connect(func(): got[0] += 1)
	d.play({"nat": 14, "bonus": 5, "dc": 13, "ok": true})
	check(d.has_landed() and not d.is_playing() and got[0] == 1, "under SORCMERC_FAST the die has landed at once, and said so once")
	check(d.tally() == "14 + 5 = 19 vs DC 13  —  made it", "the tally: %s" % d.tally())
	d.play({"nat": 3, "bonus": -2, "dc": 12, "ok": false})
	check(d.tally() == "3 − 2 = 1 vs DC 12  —  missed", "a minus bonus reads as one: %s" % d.tally())
	d.play({"nat": 1, "bonus": 30, "dc": 5, "ok": false})
	check(d.tally().ends_with("missed"), "the verdict is the caller's ok, never re-decided (a nat 1 the rule said missed)")
	d.play({"nat": 17, "bonus": 2, "dc": 10, "ok": true, "dice": [4, 17], "mode": "adv"})
	check(d._other == 4, "with advantage the other die is kept to show beside the one that counted")
	d.queue_free()

func test_card_fast_is_the_old_card() -> void:
	var c := EventCard.new()
	c.size = Vector2(1280, 720)
	root.add_child(c)
	c.show_event(ROAD)
	await process_frame
	check(not c.rolling(), "SORCMERC_FAST: no roll in the air")
	var t := _drawn(c)
	check("The pack circles" in t and "Survival 14+5 vs DC 13" in t, "...the whole card, prose and roll line, from the first frame")
	c.queue_free()

func test_die_live() -> void:
	var d := DiceRoll.new()
	root.add_child(d)
	var got := [0]
	d.landed.connect(func(): got[0] += 1)
	d.play({"nat": 9, "bonus": 3, "dc": 15, "ok": false})
	await process_frame
	check(d.is_playing() and not d.has_landed() and got[0] == 0, "at normal speed the die tumbles first")
	d.finish()
	check(d.has_landed() and d._face == 9 and got[0] == 1, "finish() lands it on the face the rules rolled, and says so once")
	d.finish()
	check(got[0] == 1, "...only once")
	d.queue_free()

func test_card_rolls_then_opens() -> void:
	var c := EventCard.new()
	c.size = Vector2(1280, 720)
	root.add_child(c)
	var acks := [0]
	c.acknowledged.connect(func(): acks[0] += 1)
	c.show_event(ROAD)
	await process_frame
	check(c.rolling(), "a road check rolls live")
	var t := _drawn(c)
	check("Vera Kord rolls Survival (+5) against DC 13." in t, "before the dice: who, what, against what")
	check(not "The pack circles" in t, "...and not what happened")
	check(c._art_rect.size.y == 0.0, "...and not the picture, which is the outcome's frame")
	check(c._btn.text == EventCard.ROLL_HINT, "the button says it is rolling")
	c._input(_key(KEY_ENTER))
	await process_frame
	check(not c.rolling() and acks[0] == 0, "Enter while the die is in the air lands it — it does not skip the result")
	t = _drawn(c)
	check("The pack circles" in t and "Survival 14+5 vs DC 13" in t, "...and the card opens: prose, roll line")
	check(c._btn.text == EventCard.DISMISS_TEXT, "the button is the way back to the road again")
	c._input(_key(KEY_ENTER))
	check(acks[0] == 1, "the next Enter closes it, once")
	c.queue_free()

	var c2 := EventCard.new()
	c2.size = Vector2(1280, 720)
	root.add_child(c2)
	c2.show_event(ROAD)
	await process_frame
	c2._btn.pressed.emit()
	check(not c2.rolling(), "the button lands the die too")
	c2.queue_free()

func test_card_without_a_roll() -> void:
	var c := EventCard.new()
	c.size = Vector2(1280, 720)
	root.add_child(c)
	c.show_event({"id": "quiet", "title": "A quiet road", "kind": "good", "text": "Nothing happens."})
	await process_frame
	check(not c.rolling() and "Nothing happens." in _drawn(c), "an event with no check is the open card, as ever")
	c.queue_free()
