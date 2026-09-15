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
	check(main._lair_msg.text.contains("beaten"), "...and the map says so (%s)" % main._lair_msg.text)

	# The whole thing, lost against a band standing right by that settlement:
	# the map must NOT come back with the same fight/parley/ambush card the
	# party just answered — the band is marked slipped until it is out of range.
	var World = load("res://core/world.gd")
	var p = main.world.player()
	p.position = main.world.settlements[0].position + Vector2(10, 0)
	var foe = main.world.add_party(World.RoamingParty.new("hound", p.position + Vector2(1, 0), "goblinoid"))
	main._process(0.1); await process_frame
	check(main._approach_card != null, "sanity: a hostile band next to the party opens the approach card")
	main._on_approach_chosen("engage")
	main._process(0.1); await process_frame
	if main._event_card != null:
		main._event_card.acknowledged.emit()
	for i in 2:
		main._process(0.1); await process_frame
	check(main._combat != null, "sanity: engaging launches the fight")
	if main._combat != null:
		main._combat.result = {"outcome": "Defeat", "xp": 0, "gold": 0}
	for i in 3:
		main._process(0.1); await process_frame
	check(main._combat == null, "the lost fight is torn down")
	check(main._approach_card == null, "...and the band that won does not re-open its approach card")
	check(main._slipped.has(foe.id), "it is marked slipped instead")

	# The soft landing is specific to a retreat (a run-ending loss) — a death
	# in a fight the party still WON is not touched by _retreat() at all, so
	# it keeps the real, paid-resurrection stakes exactly as before.
	var id2: String = main.party.roster[1].id
	main._apply_deaths({"deaths": [id2]})
	check(main.party.roster[1].dead, "a death in a won fight still marks the character dead")
	check(not main.party.active.has(id2), "...and still benched — no free revive without a retreat")

	print("test_world_defeat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
