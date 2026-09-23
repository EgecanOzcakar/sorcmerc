# #176 — the trait moment (scenes/world/trait_moment.gd): the full-screen popup
# for a personality trait gained, a scar or a resilience decided on a save, a
# wound, a cure. Headless: what it says, the order it says it in, that a press
# during the show finishes the show instead of skipping the moment, and that
# `finished` fires exactly once at the end of the queue.
#   godot --headless --path . -s tests/test_trait_moment.gd
extends SceneTree

const TraitMoment = preload("res://scenes/world/trait_moment.gd")

var _pass := 0
var _fail := 0
var _finished := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

const TRIUMPH := {"cname": "Vera Kord", "kind": "triumph", "event": "Cleared the Bloodfang warren",
	"trait": {"name": "Delver", "text": "Knows how a lair breathes.", "effects": ["+1 to hit on lair boards"]}}
const SCAR := {"cname": "Pike Sallow", "kind": "scar", "event": "Downed by the fire giant",
	"save": {"ability": "wis", "dc": 18, "nat": 7, "bonus": 3},
	"trait": {"name": "Burn-shy", "effects": ["-1 to hit against anything that deals fire"],
		"cure": "down a fire-dealer yourself, and make the save"}}
const NAT20 := {"cname": "Ilsa Vane", "kind": "resilience", "save": {"ability": "con", "dc": 25, "nat": 20, "bonus": 1},
	"trait": {"name": "Fire-tempered"}}

func _init() -> void:
	await process_frame
	OS.set_environment("SORCMERC_FAST", "1")
	await test_queue_in_order()
	await test_fallbacks()
	await test_nat20_and_unknown_kind()
	OS.set_environment("SORCMERC_FAST", "")
	await test_press_during_show_finishes_it_first()
	print("test_trait_moment: %d passed, %d failed" % [_pass, _fail])
	# A script that failed to compile runs no checks at all; that is a failure.
	quit(1 if _fail > 0 or _pass == 0 else 0)

func _fresh() -> TraitMoment:
	var m := TraitMoment.new()
	root.add_child(m)
	_finished = 0
	m.finished.connect(func(): _finished += 1)
	return m

func test_queue_in_order() -> void:
	var m := _fresh()
	m.show_moments([TRIUMPH, SCAR])
	await process_frame
	var t: Dictionary = m.texts()
	check(t["caption"] == TraitMoment.KIND_CAPTION["triumph"], "a triumph says so first")
	check(t["hero"] == "Vera Kord" and t["event"] == "Cleared the Bloodfang warren", "who, and what happened")
	check(t["name"] == "Delver" and t["verb"] == "is now", "the trait's name, under 'is now'")
	check(t["d20"] == "", "a triumph has no save to roll (it is chance, not a save)")
	check(t["count"] == "1 of 2" and m.remaining() == 2, "the first of two")
	check(not t["playing"], "under SORCMERC_FAST the show is already over")

	m._skip_or_advance()
	await process_frame
	t = m.texts()
	check(t["caption"] == TraitMoment.KIND_CAPTION["scar"] and t["hero"] == "Pike Sallow", "then the scar, on the next hero")
	check(t["d20"] == "7", "the die shows the roll core/traits.gd made")
	check(t["verdict"] == "10 — failed by 8.", "and the verdict: 7 + 3 against DC 18 (%s)" % t["verdict"])
	check(t["name"] == "Burn-shy" and t["count"] == "2 of 2", "the scar's name, the last of two")
	check(_finished == 0, "nothing finished while a moment is still up")

	m._skip_or_advance()
	check(_finished == 1, "the last one acknowledged: finished, once")
	m._skip_or_advance()
	check(_finished == 1, "...and never twice")
	m.queue_free()

func test_fallbacks() -> void:
	var m := _fresh()
	m.show_moments([])
	await process_frame
	var t: Dictionary = m.texts()
	check(t["hero"] != "" and t["event"] != "" and t["name"] != "", "an empty queue still says something: %s" % str(t))
	m._skip_or_advance()
	check(_finished == 1, "and can be closed")
	m.queue_free()

func test_nat20_and_unknown_kind() -> void:
	var m := _fresh()
	var odd := NAT20.duplicate(true)
	m.show_moments([odd, {"kind": "prophecy", "cname": "Nobody"}])
	await process_frame
	var t: Dictionary = m.texts()
	check(t["caption"] == TraitMoment.KIND_CAPTION["resilience"], "resilience has its own caption")
	check(t["verdict"] == "A natural 20.", "a nat 20 makes it whatever the DC")
	m._skip_or_advance()
	await process_frame
	check(m.texts()["caption"] == TraitMoment.KIND_CAPTION["triumph"], "a kind nobody knows reads as a triumph, not a crash")
	m.queue_free()

func test_press_during_show_finishes_it_first() -> void:
	var m := _fresh()
	m.show_moments([SCAR])
	await process_frame
	check(m.texts()["playing"], "at normal speed the show runs")
	check(m._btn.disabled, "...and its button waits for it")
	m._skip_or_advance()
	await process_frame
	var t: Dictionary = m.texts()
	check(not t["playing"] and m.remaining() == 1 and _finished == 0,
		"a press during the show ends the show, it does not skip the scar")
	check(t["d20"] == "7" and t["verdict"] != "", "the roll is landed when it is cut short")
	check(m._name_label.scale == Vector2.ONE and m._stamp.modulate.a == 1.0, "and the name is on screen")
	m._skip_or_advance()
	check(_finished == 1, "the next press moves on")
	m.queue_free()
