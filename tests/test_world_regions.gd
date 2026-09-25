# D6 on the map itself: the band label, the crossing, and the one crossing that
# gets to stop a fast-forward.
#
# The model is tested in tests/test_regions.gd. What is pinned here is that a
# player can find out which country they are in WITHOUT walking into a fight to
# discover it — the whole failure mode a level-banded map has is a wall you only
# learn about by hitting it.
#   godot --headless --path . -s tests/test_world_regions.gd
extends SceneTree

const World = preload("res://core/world.gd")
const Regions = preload("res://core/regions.gd")
const Encounter = preload("res://core/encounter.gd")
const Power = preload("res://core/rules/power.gd")
const WorldHomes = preload("res://core/world_homes.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

# Put the party somewhere and let the map notice. Never right on top of the
# anchor: that is a settlement, and walking into one opens its screen, which
# (correctly) suppresses everything below.
func _stand(main, pos: Vector2) -> void:
	var p = main.world.player()
	p.position = pos
	p.goal = pos
	await process_frame
	await process_frame

func _init() -> void:
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world

	# The small map is the one the world screen builds, and the one nobody thinks
	# to check because it is hand-placed. Its near ring has to hold a landmark: a
	# heartland with only the starting town in it means a level 1-3 party has to
	# ride into the marches to find its first fight, which is exactly the wall D6
	# exists to remove.
	var home_lairs := 0
	for l in w.lairs:
		if Regions.band_of(w, l.position) == "heartland":
			home_lairs += 1
	check(home_lairs > 0, "the small map's heartland has a lair of its own")
	# ...and every people with a home has a lair in it (core/world_homes.gd,
	# 2026-09-25), the cult's included — the one boss that casts from slots.
	check(WorldHomes.homeless(w).is_empty(), "every people has a lair on the small map (%s)" % str(WorldHomes.homeless(w)))
	check(w.lairs.any(func(l): return l.faction == "cultist" and Regions.within(w, l.position, "frontier")),
		"...the cult's in the frontier")

	# --- the always-on label ------------------------------------------------
	await _stand(main, Regions.anchor(w) + Vector2(200, 0))
	check(main._region_lbl != null and main._region_lbl.text != "", "the HUD says which country this is")
	check(main._region_lbl.text.find("Heartland") >= 0, "home reads as the heartland (%s)" % main._region_lbl.text)
	check(main._region_lbl.text.find("levels 1 to 3") >= 0, "...and who it is for (%s)" % main._region_lbl.text)

	# --- crossing out -------------------------------------------------------
	var deeps: Array = Regions.ring(w, "deeps")
	var far: Vector2 = Regions.anchor(w) + Vector2(float(deeps[0]) + 20.0, 0)
	await _stand(main, far)
	check(Regions.band_of(w, far) == "deeps", "the far ring really is the deeps")
	check(main._region_lbl.text.find("Deeps") >= 0, "the label follows the party out (%s)" % main._region_lbl.text)
	check(main._region_msg != null and main._region_msg.text.find("out into") >= 0,
		"and the crossing is called out: %s" % main._region_msg.text)

	# A level 3 party in the deeps is exactly the case worth stopping for.
	check(Regions.party_level(main.party) < 10, "the demo party is nowhere near deeps level")
	check(main._event_card != null, "riding into country over your head stops the clock")
	check(main.world.clock.is_paused(), "...literally stops it")
	main._event_card.acknowledged.emit()
	check(main._event_card == null and not main.world.clock.is_paused(), "and it lets go again")

	# Once per band: a party working a seam is not stopped every few minutes to
	# be told the same thing it already decided to ignore.
	await _stand(main, Regions.anchor(w) + Vector2(200, 0))
	await _stand(main, far)
	check(main._event_card == null, "the same warning does not stop the clock twice")
	check(not main.world.clock.is_paused(), "...and the march keeps going")
	check(main._region_msg.text.find("out into") >= 0, "but the crossing is still narrated")

	# --- crossing back ------------------------------------------------------
	await _stand(main, Regions.anchor(w) + Vector2(200, 0))
	check(main._region_lbl.text.find("Heartland") >= 0, "coming home reads as coming home")
	check(main._region_msg.text.find("back inside") >= 0, "...and is narrated that way (%s)" % main._region_msg.text)
	check(main._event_card == null, "good news does not interrupt a march")
	check(not main.world.clock.is_paused(), "...and does not stop the clock")

	# --- the Unmapped: the Far Deeps' outer half (2026-09-25) ----------------
	var outer: Array = Regions.ring(w, "unmapped")
	var edge: Vector2 = Regions.anchor(w) + Vector2((float(outer[0]) + float(outer[1])) * 0.5, 0)
	await _stand(main, far)
	if main._event_card != null:
		main._event_card.acknowledged.emit()
	await _stand(main, edge)
	check(Regions.band_of(w, edge) == "unmapped", "the edge of the small map is the Unmapped")
	check(main._region_lbl.text.find("the Unmapped, levels 15 to 20") >= 0,
		"the label names the new band and who it is for (%s)" % main._region_lbl.text)
	check(main._region_msg.text.find("out into the Unmapped") >= 0,
		"crossing the seam inside the Far Deeps is called out (%s)" % main._region_msg.text)
	check(main._event_card != null, "...and, over the party's head, it stops the clock once")
	if main._event_card != null:
		main._event_card.acknowledged.emit()
	await _stand(main, Regions.anchor(w) + Vector2(200, 0))

	# --- the fight the band implies ----------------------------------------
	# The band reaches the actual roster, not only the label: the same foe is a
	# bigger fight in the deeps than at home.
	var foe = World.RoamingParty.new("probe", Regions.anchor(w) + Vector2(200, 0), "bandit")
	var home_spec: Dictionary = main.encounter_spec(foe)
	foe.position = far
	var deep_spec: Dictionary = main.encounter_spec(foe)
	check(_power(deep_spec) > _power(home_spec),
		"the same band is a harder fight in the deeps (%.1f vs %.1f)" % [
			_power(deep_spec), _power(home_spec)])

	# --- what a lair advertises --------------------------------------------
	var lair = w.add_lair(World.Lair.new("probe-lair", far, "dragon", "Probe Hollow"))
	lair.discovered = true
	await _stand(main, far)
	if main._event_card != null:
		main._event_card.acknowledged.emit()   # the crossing card again; not what is under test
	main._check_lairs()
	check(main._lair_btn.visible, "standing on a known lair offers the way in")
	check(main._lair_btn.text.find("Deeps") >= 0,
		"the button that walks into a lair says what country it is in (%s)" % main._lair_btn.text)
	check(main._lair_btn.text.find("levels") >= 0, "...and what it will take")
	# #89: a party halted on top of it (paused) is still offered the way in
	main.world.clock.pause()
	main._check_lairs()
	check(main._lair_btn.visible, "...and still does while the clock is paused")
	main.world.clock.resume()

	print("test_world_regions: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# What the roster is actually worth, on core/rules/power.gd's own scale — the
# same measure tests/test_scaler.gd uses. Counting bodies would miss the whole
# point: a bigger budget is usually spent on BIGGER monsters, not more of them.
func _power(spec: Dictionary) -> float:
	var roster: Array = []
	for e in spec.get("monsters", []):
		for i in int(e["count"]):
			roster.append(Encounter.spawn(String(e["id"]), float(e["mult"]), "foe", Vector2i.ZERO))
	return Power.team_score(roster)
