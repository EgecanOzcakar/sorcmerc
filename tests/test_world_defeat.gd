# T9x: real defeat consequences. A lost fight used to be free (retreat to the
# nearest settlement, no losses) — now it costs gold, and anyone the fight
# actually killed (encounter.gd's `deaths`, on either outcome) stays dead and
# benched until paid resurrection, same rule the linear campaign already uses.
#   godot --headless --path . -s tests/test_world_defeat.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	main.party.gold = 100
	var id: String = main.party.roster[0].id
	check(not main.party.roster[0].dead, "sanity: nobody's dead yet")

	main._apply_deaths({"deaths": [id]})
	check(main.party.roster[0].dead, "a death in the result marks the character dead")
	check(not main.party.active.has(id), "the fallen character is benched")

	var before_gold: int = main.party.gold
	main._retreat()
	check(main.party.gold < before_gold, "retreating after a loss costs gold (was %d, now %d)" % [before_gold, main.party.gold])
	check(main.world.player().position == main.world.settlements[0].position
		or main.world.settlements.any(func(s): return s.position == main.world.player().position),
		"the party falls back to a real settlement")

	print("test_world_defeat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
