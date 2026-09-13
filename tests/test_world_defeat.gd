# T9x: real defeat consequences, with a soft landing. A lost fight used to be
# free (retreat to the nearest settlement, no losses) — now it costs gold and
# benches anyone the fight actually killed (encounter.gd's `deaths`, applied
# on either outcome). But a world-map encounter isn't sized like the curated
# early-game jobs Party.REVIVE_COST was priced against, so a run-ending loss
# is forgiving the same way campaign.gd's own run-ending loss already is: the
# fallen come back for free (1 HP, still benched) on the retreat itself, not
# stuck needing paid resurrection on top of the retreat's own gold tax. A
# death during a fight the party still WON keeps the real, paid-resurrection
# stakes — only the retreat path gets the free revive.
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
	check(not main.party.roster[0].dead, "retreating is a soft landing — the fallen come back for free")
	check(not main.party.active.has(id), "...but still benched, not auto re-activated")
	check(main.world.player().position == main.world.settlements[0].position
		or main.world.settlements.any(func(s): return s.position == main.world.player().position),
		"the party falls back to a real settlement")

	# The soft landing is specific to a retreat (a run-ending loss) — a death
	# in a fight the party still WON is not touched by _retreat() at all, so
	# it keeps the real, paid-resurrection stakes exactly as before.
	var id2: String = main.party.roster[1].id
	main._apply_deaths({"deaths": [id2]})
	check(main.party.roster[1].dead, "a death in a won fight still marks the character dead")
	check(not main.party.active.has(id2), "...and still benched — no free revive without a retreat")

	print("test_world_defeat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
