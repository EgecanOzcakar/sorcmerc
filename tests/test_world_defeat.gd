# T9x: real defeat consequences. A lost fight costs gold (the victors go
# through the pockets of whoever still breathes), and anyone the fight actually
# killed (encounter.gd's `deaths`, applied on either outcome) is dead and
# benched. Since the design audit (docs/audit-game-design.md §1.2, 2026-09-24)
# the retreat stands up only the DOWNED: the dead stay dead, this fight's and
# every earlier fight's, and come back only the paid way (a healer's raise,
# Revivify, a scroll). The road applies the fight's deaths BEFORE the retreat,
# the same order a site wipe always used, so neither path can revive them.
#   godot --headless --path . -s tests/test_world_defeat.gd
extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

const Defeat = preload("res://core/defeat.gd")
const WorldSave = preload("res://core/world_save.gd")

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "0")   # the free plane, where bands walk the map (#231: routes are the default)
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
	var downed = main.party.get_member(main.party.active[0])
	downed.hp_current = 0   # down, not dead
	var t_before: float = main.world.clock.elapsed
	main._retreat([id], [downed.id])
	check(main.party.gold < before_gold, "retreating after a loss costs gold (was %d, now %d)" % [before_gold, main.party.gold])
	check(main.party.roster[0].dead, "the retreat does not raise the dead: they need a paid raise")
	check(not main.party.active.has(id), "...and they stay benched")
	check(not downed.dead and downed.hp_current == 1, "the downed come to at 1 HP (%d)" % downed.hp_current)
	check(main._lair_msg.text.contains(main.party.roster[0].cname) and main._lair_msg.text.contains("healer"),
		"the map names the dead and the way back (%s)" % main._lair_msg.text)
	check(main.world.player().position == main.world.settlements[0].position
		or main.world.settlements.any(func(s): return s.position == main.world.player().position),
		"the party falls back to a real settlement")
	check(main._lair_msg.text.contains("beaten"), "...and the map says so (%s)" % main._lair_msg.text)
	# The design audit §1.8: a cost the strongroom cannot shelter. A day passes
	# through the world's own tick, and the downed roll for a wound.
	check(is_equal_approx(main.world.clock.elapsed - t_before, Defeat.DAYS_LOST * Defeat.DAY),
		"the company comes to a day later (%.0f minutes)" % (main.world.clock.elapsed - t_before))
	check(main._lair_msg.text.contains("a day later"), "...and the line says so")
	check(main._trait_news.any(func(l): return String(l).contains(downed.cname)),
		"the downed hero rolled for a wound, and the page will say how it went (%s)" % [main._trait_news])
	main._trait_news = []
	main._moment_queue = []

	# The whole thing, lost against a band standing right by that settlement:
	# the map must NOT come back with the same fight/parley/ambush card the
	# party just answered — the band is marked slipped until it is out of range.
	var World = load("res://core/world.gd")
	var p = main.world.player()
	p.position = main.world.settlements[0].position + Vector2(10, 0)
	var foe = main.world.add_party(World.RoamingParty.new("hound", p.position + Vector2(1, 0), "goblinoid"))
	main._process(0.1); await process_frame
	check(main._approach_card != null, "sanity: a hostile band next to the party opens the approach card")
	# Whichever band the card is for: the earlier retreat's lost day lets the
	# map's own bands walk up to the town too, so it need not be the hound.
	var met = main._approach_foe if main._approach_foe != null else foe
	main._on_approach_chosen("engage")
	main._process(0.1); await process_frame
	if main._event_card != null:
		main._event_card.acknowledged.emit()
	for i in 2:
		main._process(0.1); await process_frame
	check(main._combat != null, "sanity: engaging launches the fight")
	var clock_before: float = main.world.clock.elapsed
	# One of the marchers dies in the loss: on the road the deaths are applied
	# before the retreat, so revive_downed finds them already dead.
	var fell: String = main.party.active[0]
	if main._combat != null:
		main._combat.result = {"outcome": "Defeat", "xp": 0, "gold": 0, "rounds": 5, "deaths": [fell]}
	for i in 3:
		main._process(0.1); await process_frame
	check(main._combat == null, "the lost fight is torn down")
	check(main.party.get_member(fell).dead and not main.party.active.has(fell),
		"the road's loss: this fight's dead are dead and benched after the retreat")
	check(main.party.roster[0].dead, "...and the earlier dead are still dead")
	check(is_equal_approx(main.world.clock.elapsed - clock_before, 5 * main.MINUTES_PER_ROUND + Defeat.DAYS_LOST * Defeat.DAY),
		"five rounds cost five hours of daylight, and the company comes to a day later (%.0f)" % (main.world.clock.elapsed - clock_before))
	check(main._approach_card == null, "...and the band that won does not re-open its approach card")
	# Marked slipped, and — since the beaten company now lies a day where it
	# fell (core/defeat.gd) and the band may walk off and back meanwhile — under
	# the victors' truce, so it does not come straight back for them.
	check(main._slipped.has(met.id) and load("res://core/world_ai.gd").in_truce(met, main.world.clock.elapsed),
		"it is marked slipped instead, and holds off under a truce")

	# A death in a fight the party WON is not touched by _retreat() at all:
	# the same paid-resurrection stakes as a loss.
	var id2: String = main.party.roster[1].id
	main._apply_deaths({"deaths": [id2]})
	check(main.party.roster[1].dead, "a death in a won fight still marks the character dead")
	check(not main.party.active.has(id2), "...and still benched")

	# The whole company dead: it is finished (the owner's call, 2026-09-25).
	# Nobody is stood up; the record is written, and ending the company marks
	# the save finished — the title screen will list it and not resume it.
	for ch in main.party.roster:
		ch.dead = true
		main.party.bench(ch.id)
	var t_wipe: float = main.world.clock.elapsed
	var line: String = main._retreat([main.party.roster[0].id])
	check(main.party.roster.all(func(c): return c.dead), "a wiped-out company keeps nobody alive")
	check(not main.party.finished.is_empty(), "...it is finished, and the record is written")
	check(main.party.finished["fell"] == [main.party.roster[0].cname] and main.party.finished["roll"].size() == main.party.roster.size(),
		"...naming the last to fall and the whole roll (%s)" % [main.party.finished])
	check(main.world.clock.elapsed == t_wipe, "...and no day passes on a map nobody is left on")
	check(line.contains("nobody gets up"), "...and says so: %s" % line)
	main._end_company()
	var saved = WorldSave.load_latest()
	check(saved != null and not saved["party"].finished.is_empty(), "the save is marked finished")
	check(not WorldSave.summary().get("finished", {}).is_empty(), "...and the slot's facts say so, for the title screen")

	print("test_world_defeat: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
