# T39 UI check: a scouted fight opens the deployment phase, swapping trades two
# party members' start hexes, and "Begin the ambush" hands off to the turn loop.
#   godot --headless --path . -s tests/drive_deploy.gd
extends SceneTree

var main

func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.scouted_ahead = true
	root.add_child(main)
	_run()

func _btns() -> Array:
	return main._buttons.get_children().filter(func(b): return b is Button and not b.is_queued_for_deletion())

func _run() -> void:
	var fails := 0
	for _i in 8:
		await process_frame
	if main._mode != "deploy":
		printerr("FAIL: a scouted fight didn't open the deployment phase"); fails += 1
	if not main.cb.unseen:
		printerr("FAIL: a scouted fight isn't unseen"); fails += 1
	var heroes: Array = main.cb.team_of("party")
	var before := heroes.map(func(c): return c.pos)
	var swap: Button = null
	for b in _btns():
		if "Swap" in b.text:
			swap = b
			break
	if swap == null:
		printerr("FAIL: no swap control in the deployment phase"); fails += 1
	else:
		swap.pressed.emit()
		await process_frame
		var after := heroes.map(func(c): return c.pos)
		var moved := 0
		for i in before.size():
			if before[i] != after[i]:
				moved += 1
		if moved != 2:
			printerr("FAIL: a swap should move exactly two party members, moved %d" % moved); fails += 1
		var same := true
		for p in after:
			same = same and p in before
		if not same:
			printerr("FAIL: a swap must permute the start hexes, not invent new ones"); fails += 1
	var rest: Array = _btns()
	rest[rest.size() - 1].pressed.emit()
	for _i in 8:
		await process_frame
	if main._mode == "deploy":
		printerr("FAIL: Begin didn't leave the deployment phase"); fails += 1
	if main.cb.round_num == 1 and main.cb.current().team == "foe":
		printerr("FAIL: a foe is acting during the surprise round"); fails += 1
	print("drive_deploy: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
