# Landmarks on the world screen: found by walking, a button to visit, the
# approach card asks, the event card answers, and a spent place is quiet.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_landmarks.gd
extends SceneTree
const World = preload("res://core/world.gd")
const Landmarks = preload("res://core/landmarks.gd")
var _pass := 0
var _fail := 0
func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)
func labels(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Label:
			out.append(String(c.text))
		out.append_array(labels(c))
	return out
func said(node: Node, text: String) -> bool:
	for l in labels(node):
		if text in l:
			return true
	return false

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "0")   # the free plane, where bands walk the map (#231: routes are the default)
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	check(w.landmarks.size() >= 6, "the small map has landmarks (%d)" % w.landmarks.size())

	# a shrine under the party's feet: found by being explored, and a button appears
	var shrine = w.add_landmark(World.Landmark.new("t-shrine", "shrine", p.position + Vector2(20, 0)))
	for i in 3:
		await process_frame
	check(shrine.found, "walked up to, it is found")
	check(main._place_btn.visible and "Visit" in main._place_btn.text and shrine.sname in main._place_btn.text,
		"the button offers a visit: %s" % main._place_btn.text)
	main._place_btn.pressed.emit()
	await process_frame
	check(main._approach_card != null and w.clock.is_paused(), "the card opens and the clock stops")
	# choose the offering (no roll): the event card answers, the place is spent
	main.party.gold = 500
	main._on_place_chosen("offering")
	for i in 3:
		await process_frame
	check(main._event_card != null, "the outcome is on the event card")
	check(shrine.spent and main.party.blessed, "the offering blesses and spends the shrine")
	main._event_card.acknowledged.emit()
	for i in 3:
		await process_frame
	check(not w.clock.is_paused(), "acknowledged, the clock runs")
	check(not main._place_btn.visible or not (shrine.sname in main._place_btn.text), "a spent place offers no visit")

	# leave spends nothing
	var ruins = w.add_landmark(World.Landmark.new("t-ruins", "ruins", p.position + Vector2(-20, 0)))
	for i in 3:
		await process_frame
	main._place_btn.pressed.emit()
	await process_frame
	main._on_place_chosen(Landmarks.LEAVE)
	for i in 3:
		await process_frame
	check(not ruins.spent and main._approach_card == null and not w.clock.is_paused(), "leave closes the card, spends nothing")

	# a hidden hut: the button offers the search instead
	var hut = w.add_landmark(World.Landmark.new("t-hut", "hut", p.position + Vector2(0, 25)))
	ruins.spent = true
	for i in 3:
		await process_frame
	check(main._place_btn.visible and "Search" in main._place_btn.text, "a hidden place offers a search: %s" % main._place_btn.text)

	# markers: found landmarks draw, unfound ones do not
	var rows: Array = main.ground_marks()
	check(rows.any(func(r): return r.get("label", "") == shrine.sname), "a found landmark is a marker")
	check(not rows.any(func(r): return r.get("label", "") == hut.sname), "an unfound one is not")
	print("test_world_landmarks: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
