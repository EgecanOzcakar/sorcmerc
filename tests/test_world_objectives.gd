# Objectives on the map: a delivery makes the road fight an escort, a hunt job
# makes the band a hunt, a jumped camp is a breakout; and what comes back —
# the chief that got away keeps the band and the job, the dead carter loses
# the crate, the spoils page says what the objective came to.
#   godot --headless --path . -s tests/test_world_objectives.gd
extends SceneTree
const World = preload("res://core/world.gd")
const Quest = preload("res://core/quest.gd")
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

func _open_fight(main, foe, forced_ambush := false) -> bool:
	main._launch_combat(foe, false, forced_ambush)
	var guard := 0
	while main._combat == null and guard < 60:
		await process_frame
		guard += 1
	return main._combat != null

func _finish(main, result: Dictionary) -> void:
	main._combat.result = result
	for i in 8:
		await process_frame

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var p = main.world.player()

	# --- escort: a delivery on the road, and the carter dies ---------------
	Quest.accept(main.party, {"id": "deliver:t:x", "kind": "deliver_goods", "state": "offered",
		"target_settlement_id": "x", "required": 1, "progress": 0,
		"title": "Run a crate of goods to X", "reward": {"gold": 40}})
	var foe = World.RoamingParty.new("bandits-a", p.position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe)
	check(await _open_fight(main, foe), "the fight opened")
	check(main._combat.spec.get("objective", {}).get("kind", "") == "escort", "with a delivery on the road, the fight is an escort")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "escort", "done": false, "xp": 0}})
	check(Quest.get_quest(main.party, "deliver:t:x").is_empty(), "the carter dead, the delivery is lost")
	check(main._spoils_panel != null and said(main._spoils_panel, "carter is dead"), "the spoils page says so")
	check(said(main._spoils_panel, "delivery"), "...and names the lost job")
	main._close_spoils()
	await process_frame

	# --- hunt: the band a job names; its chief gets away ---------------------
	var foe2 = World.RoamingParty.new("raiders-b", main.world.player().position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe2)
	Quest.accept(main.party, {"id": "world:hunt_party:raiders-b:0", "kind": "hunt_party", "state": "offered",
		"target_party_id": "raiders-b", "required": 1, "progress": 0,
		"title": "Hunt down the raiders-b band", "reward": {"gold": 100}, "chain_faction": "bandit", "chain_tier": 0})
	check(await _open_fight(main, foe2), "the second fight opened")
	check(main._combat.spec["objective"]["kind"] == "hunt", "a band a job names is a hunt")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "hunt", "done": false, "xp": 0}})
	check(main.world.parties.has(foe2), "the chief got away: the band stays on the map")
	check(main._slipped.get(foe2.id, false), "...marked slipped, so the card does not reopen at once")
	check(Quest.get_quest(main.party, "world:hunt_party:raiders-b:0")["state"] == "active", "...and the job stays open")
	check(said(main._spoils_panel, "quarry got away"), "the spoils page says so")
	main._close_spoils()
	await process_frame

	# ...and then does not
	main._slipped.erase(foe2.id)
	check(await _open_fight(main, foe2), "the rematch opened")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "hunt", "done": true, "xp": 15}})
	check(not main.world.parties.has(foe2), "the quarry down: the band is gone")
	check(Quest.get_quest(main.party, "world:hunt_party:raiders-b:0")["state"] == "complete", "...and the job is done")
	check(said(main._spoils_panel, "+15 XP"), "the bonus is shown as its own number")
	main._close_spoils()
	await process_frame

	# --- breakout: a jumped camp ---------------------------------------------
	var foe3 = World.RoamingParty.new("camp-ambush-t", main.world.player().position, "bandit")
	check(await _open_fight(main, foe3, true), "the ambush opened")
	check(main._combat.spec["objective"]["kind"] == "breakout", "a failed watch is a breakout")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "breakout", "done": true, "xp": 20}})
	check(said(main._spoils_panel, "party got clear"), "the spoils page says so")
	main._close_spoils()
	await process_frame

	# --- rout: nothing on the spec, nothing on the page -----------------------
	var foe4 = World.RoamingParty.new("bandits-d", main.world.player().position + Vector2(10, 0), "bandit")
	main.world.parties.append(foe4)
	check(await _open_fight(main, foe4), "a plain fight opened")
	check(not main._combat.spec.has("objective"), "no job, no delivery, no ambush: no objective")
	await _finish(main, {"outcome": "Victory", "xp": 30, "gold": 5, "loot": [], "kills": [], "deaths": [],
		"objective": {"kind": "", "done": false, "xp": 0}})
	check(not said(main._spoils_panel, "Objective"), "no objective row for a rout")
	main._close_spoils()

	print("test_world_objectives: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
