# Raids on the world screen, on the roads — tests/test_world_raids.gd's
# counterpart for the default map (#231). That file keeps the free plane
# (SORCMERC_ROUTES=0), where a raid is a band that walks from its lair to the
# town's edge and stands there. On the roads nothing walks the map, so neither
# does a raid (core/raids.gd's header): the band is pinned on the town's own
# road at its gate the moment it sets out, standing its siege there, undrawn,
# and a company walking up that road meets it. Everything after — the landing,
# the board's line, the lift, settling the cleared lair — is the same town
# state. This drives it on the screen through the real click
# (tests/road_screen.gd):
#   * the Tangle's clock runs out: its band is pinned at its town's gate, not
#     on the map, and the HUD says the raiders are camped outside; the lair's
#     label and the town's say so;
#   * the march up that road meets it, and the fight there is hold the line,
#     its waves the lair's own kin; slipped, it is left standing at the gate;
#   * stood out, the raid lands: the label, and the board's line;
#   * the lair cleared, the raid lifts and says so;
#   * marched to, the cleared lair offers its settling, priced, and the camp
#     that goes up is a place the company can walk back into;
#   * a raid that lands while the company is in a town re-reads the open shelf.
#
# Arranged, as the free-plane file arranges its own: the Tangle is marked
# discovered (the free file marks the lair it adds), which on the roads is the
# rumour's door — its hidden way is revealed with it (RouteTravel's
# _follow_marks); its raid clock is set due now and every other lair's is
# pushed on, so the Tangle's is the raid under test; the stand is run out and
# the lair cleared by writing the same fields the free file writes. The road's
# own traffic met on the way is waved off, the way tests/drive_routes.gd
# answers it.
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_world_raids_routes.gd
extends SceneTree

const World = preload("res://core/world.gd")
const WorldLairs = preload("res://core/world_lairs.gd")
const Raids = preload("res://core/raids.gd")
const Objectives = preload("res://core/objectives.gd")
const WorldThreat = preload("res://core/world_threat.gd")
const Catalog = preload("res://core/rules/catalog.gd")
const RouteTravel = preload("res://core/route_travel.gd")
const RoutePins = preload("res://core/route_pins.gd")
const RoadScreen = preload("res://tests/road_screen.gd")

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

func _kin_of(waves: Array) -> Array:
	var seen := {}
	for wave in waves:
		for m in wave:
			seen[String(Catalog.monster(String(m["id"])).get("faction", ""))] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _label_for(main, id: String) -> String:
	for m in main.ground_marks():
		if String(m.get("label", "")).begins_with(id):
			return String(m["label"])
	return ""

func _init() -> void:
	OS.set_environment("SORCMERC_ROUTES", "1")
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	var main = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var w = main.world
	var p = w.player()
	check(RouteTravel.on(w), "the default map is a route world")
	var l = null
	for x in w.lairs:
		if x.id == "the-tangle":
			l = x
		else:
			x.raid_at = w.clock.elapsed   # nobody else's clock runs out now
	check(l != null, "the small map has the Tangle")
	if l == null:
		_done()
		return
	var town = Raids.target_for(w, l)
	check(town != null, "the Tangle has a town to raid")
	if town == null:
		_done()
		return
	l.discovered = true
	# The company's first walk: out to the Tangle by the way the rumour opened —
	# which lifts the fog off it, so its label draws, as the free file's lair
	# stands in fog already lifted — and back to the town it will raid.
	w.clock.resume()
	await RoadScreen.frame(self, main)   # the road's frame follows the mark: its way is revealed
	var got: String = await RoadScreen.go(self, main, l.position)
	check(got == "arrived" and p.position.distance_to(l.position) <= WorldLairs.DISCOVER_RADIUS, "a click on the found lair marches there by road (%s)" % got)
	check(w.routes.nodes["lair:%s" % l.id]["known"], "...the Tangle, found, has its way on the roads")
	got = await RoadScreen.go(self, main, town.position)
	check(got == "visit" and main._visit.get("settlement") == town, "back into %s (%s)" % [town.sname, got])
	main._close_visit()
	await process_frame
	l.raid_at = w.clock.elapsed - Raids.RAID_AFTER - Raids.RAID_JITTER
	w.clock.resume()
	for i in 3:
		await RoadScreen.frame(self, main)
	var b = Raids.band_of(w, l)
	check(b != null, "the band set out on the screen's poll")
	if b == null:
		_done()
		return
	check(w.pinned.has(b) and not w.parties.has(b), "...pinned on the road, not walking the map")
	check(b.position.distance_to(town.position) <= Raids.SIEGE_DIST + 1.0, "...at %s's gate (%.0f out)" % [town.sname, b.position.distance_to(town.position)])
	check(String(b.ai["phase"]) == "siege", "...standing its siege from the moment it sets out")
	check(("Raiders from %s are camped outside %s" % [l.sname, town.sname]) in main._lair_msg.text, "...and it is said: %s" % main._lair_msg.text)
	check(_label_for(main, l.sname).ends_with(" — raiding"), "the lair's label says so: %s" % _label_for(main, l.sname))
	check(" — raiders at the gate, " in _label_for(main, town.sname), "the town's label counts the hours: %s" % _label_for(main, town.sname))

	# --- met at the gate, walking out of it up the lair's road: hold the line ---
	got = await RoadScreen.go(self, main, l.position, b)
	check(got == "card" and main._approach_foe == b, "walking out of %s's gate meets the raiders there (%s)" % [town.sname, got])
	check(String(main._road_objective(b, "").get("kind", "")) == "hold", "meeting the raiders at the gate is hold the line")
	var spec: Dictionary = main.encounter_spec(b)
	var waves: Array = main._hold_waves(b, spec, WorldThreat.assess(main.party))
	check(waves.size() == Objectives.WAVE_ROUNDS.size(), "the gate fight's waves: one per WAVE_ROUNDS entry (%d)" % waves.size())
	var shaped := not waves.is_empty()
	for wave in waves:
		shaped = shaped and wave is Array and not wave.is_empty()
		for m in wave:
			shaped = shaped and m is Dictionary and m.has("id") and int(m.get("count", 0)) > 0 and m.has("mult")
	check(shaped, "...each a roster of {id, count, mult} with something in it")
	check(_kin_of(waves) == [String(l.faction)], "the %s's waves are the lair's own kin (%s)" % [l.sname, str(_kin_of(waves))])
	if main._approach_foe == b:
		RoadScreen.wave_off(main)
	check(w.pinned.has(b) and not w.parties.has(b), "slipped, the raiders are left standing at the gate")
	got = await RoadScreen.go(self, main, l.position)
	check(got == "arrived", "...and the march goes on up the road (%s)" % got)

	# --- stood out, the raid lands ------------------------------------------
	b.ai["until"] = w.clock.elapsed - 1.0
	w.clock.resume()
	for i in 3:
		await RoadScreen.frame(self, main)
	check(town.raided_by == l.id, "landed")
	check(w.band(b.id) == null and not w.pinned.has(b), "...and the band goes home off the map")
	check(_label_for(main, town.sname).ends_with(" — raided"), "the label says raided: %s" % _label_for(main, town.sname))
	# the board says it, to the company that walks back in
	got = await RoadScreen.go(self, main, town.position)
	check(got == "visit" and main._visit.get("settlement") == town, "back into %s (%s)" % [town.sname, got])
	main._goto_page("board")
	await process_frame
	check(said(main, "Raiders from %s hit the town on Day" % l.sname) and said(main, "The market is half what it was."),
		"the board page carries the line")
	main._close_visit()
	await process_frame

	# --- clearing lifts it ---------------------------------------------------
	WorldLairs.mark_cleared(l, w.clock.elapsed)
	w.clock.resume()
	for i in 3:
		await RoadScreen.frame(self, main)
	check(town.raided_by == "" and "breathes again" in main._lair_msg.text, "cleared, lifted, said: %s" % main._lair_msg.text)

	# --- settle it: march there, pay ------------------------------------------
	got = await RoadScreen.go(self, main, l.position)
	check(got == "arrived" and p.position.distance_to(l.position) <= WorldLairs.DISCOVER_RADIUS, "a click on the cleared lair marches there by road (%s)" % got)
	var cost := Raids.settle_cost(w, l)
	check(cost > 0, "a cleared lair on settled ground can be settled (%d ◉)" % cost)
	main.party.gold = cost - 1
	for i in 3:
		await process_frame
	check(main._lair_settle_btn.visible and main._lair_settle_btn.disabled and ("Settle it (%d ◉)" % cost) in main._lair_settle_btn.text,
		"the button is there, priced, and greyed on a short purse: %s" % main._lair_settle_btn.text)
	main.party.gold = cost + 100
	for i in 2:
		await process_frame
	check(not main._lair_settle_btn.disabled, "...and live with the gold")
	var n_settlements: int = w.settlements.size()
	main._lair_settle_btn.pressed.emit()
	for i in 3:
		await process_frame
	var camp = w.settlements[-1]
	check(not w.lairs.has(l) and w.settlements.size() == n_settlements + 1 and camp.id == "way-%s" % l.id,
		"settled: the lair is gone and a camp stands")
	check("put up the first roof at" in main._lair_msg.text, "said: %s" % main._lair_msg.text)
	check(not main._lair_settle_btn.visible, "the button is gone with the lair")
	check(main._settlements3d.footprint(camp) > 0.0, "the camp is on the 3D map")
	# ...and it is a place on the roads: out to the town, and back in by a click.
	got = await RoadScreen.go(self, main, town.position)
	check(got == "visit", "out to %s (%s)" % [town.sname, got])
	main._close_visit()
	got = await RoadScreen.go(self, main, camp.position)
	check(got == "visit" and main._visit.get("settlement") == camp, "a click on the new camp walks back into it (%s)" % got)
	main._close_visit()
	await process_frame

	# --- a raid that lands under an open visit re-reads the shelf, halved ------
	var open_town = w.settlements[0]
	got = await RoadScreen.go(self, main, open_town.position)
	check(got == "visit" and main._visit.get("settlement") == open_town, "a click on %s walks into it (%s)" % [open_town.sname, got])
	open_town.raided_by = ""
	open_town.battle_at = -1.0   # no fight nearby either: the only thing to change is the raid
	main._close_visit()
	main._open_visit(open_town)   # read again with the town quiet, from its own gate
	await process_frame
	check(not main._visit.is_empty() and not bool(main._visit.get("battle", false)), "an open visit to a quiet town: the full shelf")
	var raider = w.lairs.filter(func(x): return not x.looted)[0]   # a lair that stands: Raids.tick lifts a raid whose lair is gone
	open_town.raided_by = raider.id
	for i in 2:
		await process_frame
	check(bool(main._visit.get("battle", false)), "a raid lands under the open visit: the shelf is read again, halved")
	check(main._visit.get("settlement") == open_town, "...and it is still the same visit")
	open_town.raided_by = ""
	_done()

func _done() -> void:
	print("test_world_raids_routes: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
