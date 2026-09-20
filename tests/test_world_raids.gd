# Raids on the world screen: the band sets out and it is said, the siege shows
# on the label, the landing shows on the board, clearing lifts it, and a
# cleared lair can be settled from the lair button row.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_raids.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const Objectives = preload("res://core/objectives.gd")
const WorldThreat = preload("res://core/world_threat.gd")

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

func _label_for(main, id: String) -> String:
	for m in main.ground_marks():
		if String(m.get("label", "")).begins_with(id):
			return String(m["label"])
	return ""

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	var town = w.settlements[0]     # Riverhold, at the origin, where the party starts
	# a lair of our own 300 out, due now; the map's own lairs are not due for two days
	# 220 out: inside the fog the party has already lifted (VISION_RADIUS 260
	# from where it stands), so the lair's label draws; still heartland ground.
	var l = w.add_lair(World.Lair.new("t-warren", town.position + Vector2(220, 0), "goblinoid", "the Test Warren"))
	l.discovered = true
	l.raid_at = w.clock.elapsed - Raids.RAID_AFTER - Raids.RAID_JITTER
	main._lairs3d.reset(w)
	w.clock.resume()
	for i in 3:
		await process_frame
	var b = Raids.band_of(w, l)
	check(b != null, "the band set out on the screen's poll")
	check("Raiders are out from the Test Warren" in main._lair_msg.text, "...and it is said: %s" % main._lair_msg.text)
	check(_label_for(main, "the Test Warren").ends_with(" — raiding"), "the lair's label says so: %s" % _label_for(main, "the Test Warren"))
	# jump it to the gate
	b.position = Vector2(b.ai["to"])
	for i in 3:
		await process_frame
	check(b.ai["phase"] == "siege", "at the gate")
	check("camped outside" in main._lair_msg.text, "...said: %s" % main._lair_msg.text)
	check(" — raiders at the gate, " in _label_for(main, town.sname), "the town's label counts the hours: %s" % _label_for(main, town.sname))
	# the fight at the gate is a hold; on the road it is not
	check(String(main._road_objective(b, "").get("kind", "")) == "hold", "meeting the raiders at the gate is hold the line")
	# ...and a hold has waves, or combat.gd calls it held at round six whatever
	# stands: one roster per WAVE_ROUNDS entry, each a list of {id, count, mult}
	var spec: Dictionary = main.encounter_spec(b)
	check(not Objectives.waves_for(main.party.party_characters(), String(spec["theme"]), absi(hash(b.id)), 1.0).is_empty(),
		"the band's theme draws waves")
	var waves: Array = main._hold_waves(b, spec, WorldThreat.assess(main.party))
	check(waves.size() == Objectives.WAVE_ROUNDS.size(), "the gate fight's waves: one per WAVE_ROUNDS entry (%d)" % waves.size())
	var shaped := not waves.is_empty()
	for wave in waves:
		shaped = shaped and wave is Array and not wave.is_empty()
		for m in wave:
			shaped = shaped and m is Dictionary and m.has("id") and int(m.get("count", 0)) > 0 and m.has("mult")
	check(shaped, "...each a roster of {id, count, mult} with something in it (%s)" % str(waves))
	b.position = town.position + Vector2(600, 0)
	check(main._road_objective(b, "").is_empty(), "...and out on the road it is a plain fight")
	b.position = Vector2(b.ai["to"])
	# stand it out
	b.ai["until"] = w.clock.elapsed - 1.0
	for i in 3:
		await process_frame
	check(town.raided_by == "t-warren", "landed")
	check(_label_for(main, town.sname).ends_with(" — raided"), "the label says raided: %s" % _label_for(main, town.sname))
	# the board says it
	w.clock.pause()
	main._open_visit(town)
	main._goto_page("board")
	await process_frame
	check(said(main, "Raiders from the Test Warren hit the town on Day") and said(main, "The market is half what it was."),
		"the board page carries the line")
	main._close_visit()
	await process_frame
	# clearing lifts it
	WorldLairs.mark_cleared(l, w.clock.elapsed)
	w.clock.resume()
	for i in 3:
		await process_frame
	check(town.raided_by == "" and "breathes again" in main._lair_msg.text, "cleared, lifted, said: %s" % main._lair_msg.text)
	# settle it: stand on it, pay
	p.position = l.position
	p.goal = l.position
	main.party.gold = 50
	for i in 3:
		await process_frame
	check(main._lair_settle_btn.visible and main._lair_settle_btn.disabled and "Settle it (120 ◉)" in main._lair_settle_btn.text,
		"the button is there, priced, and greyed on a short purse: %s" % main._lair_settle_btn.text)
	main.party.gold = 500
	for i in 2:
		await process_frame
	check(not main._lair_settle_btn.disabled, "...and live with the gold")
	var n_settlements: int = w.settlements.size()
	main._lair_settle_btn.pressed.emit()
	for i in 3:
		await process_frame
	check(not w.lairs.has(l) and w.settlements.size() == n_settlements + 1 and w.settlements[-1].id == "way-t-warren",
		"settled: the lair is gone and a camp stands")
	check("Settlers from Riverhold put up the first roof at" in main._lair_msg.text, "said: %s" % main._lair_msg.text)
	check(not main._lair_settle_btn.visible, "the button is gone with the lair")
	check(main._settlements3d.footprint(w.settlements[-1]) > 0.0, "the camp is on the 3D map")
	print("test_world_raids: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
