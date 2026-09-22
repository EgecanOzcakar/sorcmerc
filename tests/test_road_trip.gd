# The road between two towns, walked, with the books kept: how many bands
# stop the company on the way, how many of those are fights, and what the
# company has left when it gets there — HP, spell slots, anyone dead. A
# balance readout with a floor under it, run on the large map's real roads
# with the real screen (world.tscn), the real encounter check and the real
# fights, played by the monsters' own AI on the heroes' side (core/ai.gd,
# the same hand tests/test_scaler.gd deals with) so the number measures the
# road and not a robot's aim.
#
#   SORCMERC_FAST=1 godot --headless --path . -s tests/test_road_trip.gd
#
# The policy at every meeting is the worst case: every hostile band is
# fought (POLICY "engage"); a civil one is greeted. Change POLICY to "avoid"
# for the stealthy player's road.
extends SceneTree

const World = preload("res://core/world.gd")
const WorldBands = preload("res://core/world_bands.gd")
const WorldAI = preload("res://core/world_ai.gd")
const AI = preload("res://core/ai.gd")
const Settings = preload("res://core/settings.gd")

const POLICY := "engage"
const RUNS := 4            # the large map, its bands reseeded each run
const LEGS := 2            # Riverhold -> Oakford -> Greenmarch: the first road a new company walks
const FRAMES := 20000      # per leg, before it is called wedged

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _hp_frac(party) -> float:
	var have := 0.0
	var top := 0.0
	for id in party.active:
		var ch = party.get_member(id)
		var m: int = maxi(1, int(ch.sheet().max_hp))
		top += m
		have += 0.0 if ch.dead else float(m if ch.hp_current < 0 else ch.hp_current)
	return have / maxf(1.0, top)

func _slots_used(party) -> int:
	var n := 0
	for id in party.active:
		for s in party.get_member(id).slots_used:
			n += int(s)
	return n

func _dead(party) -> int:
	var n := 0
	for id in party.active:
		if party.get_member(id).dead:
			n += 1
	return n

func _nearest(world, from: Vector2, skip: Array) -> Variant:
	var best = null
	for s in world.settlements:
		if s.id in skip or s.id.begins_with("way-") or WorldAI.is_monster(s.faction):
			continue
		if best == null or s.position.distance_to(from) < best.position.distance_to(from):
			best = s
	return best

# The company's turn, played by the same AI the monsters use; then the way on.
func _hero_turn(fight) -> void:
	var cb = fight.cb
	if cb == null or cb.is_over() or fight._busy or fight._advancing:
		return
	if fight._mode == "deploy":
		for c in fight._buttons.get_children():
			if c is Button and not c.disabled and c.visible and "Begin" in c.text:
				c.pressed.emit()
				return
		return
	if is_instance_valid(fight._reaction_card):
		for c in fight._reaction_card.get_children():
			if c is Button and not c.disabled:
				c.pressed.emit()
				return
	var h = cb.current()
	if h == null or h.team != "party" or fight._mode != "idle":
		return
	if h.conscious():
		AI.take_turn(cb, h)
	fight._end_turn()

func _meet(screen) -> void:
	var card = screen._approach_card
	var ways := {}
	for b in card.get_children():
		if b is Button and not b.disabled:
			ways[String(b.name).get_slice("_", 2)] = b
	for w in ["greet", "pass", POLICY, "engage", "parley"]:
		if ways.has(w):
			ways[w].pressed.emit()
			return
	for b in ways.values():
		b.pressed.emit()
		return

# One leg: march to `to`, keep the books, come back when the gate opens.
func _leg(screen, to) -> Dictionary:
	var w = screen.world
	var p = w.player()
	var party = screen.party
	var t0: float = w.clock.elapsed
	var dist: float = p.position.distance_to(to.position)
	var slots0 := _slots_used(party)
	var gold0: int = party.gold
	var meets := 0
	var fights := 0
	var events := 0
	var in_fight := false
	var card_seen := false
	var ev_seen := false
	w.set_goal(p, to.position)
	w.clock.resume()
	screen._pause_btn.text = "Pause"
	var frames := 0
	while frames < FRAMES:
		frames += 1
		await process_frame
		if not screen._visit.is_empty():
			if screen._visit.get("settlement") == to:
				break
			screen._close_visit()   # a waystation or another town on the way: through it
			continue
		if screen._combat != null:
			if not in_fight:
				fights += 1
			in_fight = true
			_hero_turn(screen._combat)
			continue
		in_fight = false
		if is_instance_valid(screen._approach_card):
			if not card_seen:
				meets += 1
				card_seen = true
			_meet(screen)
			continue
		card_seen = false
		if is_instance_valid(screen._event_card):
			if not ev_seen:
				events += 1
				ev_seen = true
			screen._event_card.acknowledged.emit()
			continue
		ev_seen = false
		if screen._spoils_panel != null:
			screen._close_spoils()
			continue
		if screen._halted_on_arrival or w.clock.is_paused():
			w.clock.resume()
			screen._pause_btn.text = "Pause"
		if p.at_goal():
			w.set_goal(p, to.position)   # a bank or a fight stopped it short of the gate
	return {"to": to.sname, "arrived": screen._visit.get("settlement") == to, "frames": frames, "dist": dist,
		"meets": meets, "fights": fights, "events": events,
		"hours": (w.clock.elapsed - t0) / 60.0, "hp": _hp_frac(party),
		"slots": _slots_used(party) - slots0, "dead": _dead(party), "gold": party.gold - gold0}

func _leave_town(screen) -> void:
	if not screen._visit.is_empty():
		screen._close_visit()
	for i in 3:
		await process_frame

func _init() -> void:
	OS.set_environment("SORCMERC_SAVE_DIR", "user://test/%d-%d" % [OS.get_process_id(), randi()])
	Settings.current().reaction_prompts = false
	var legs: Array = []
	for run in RUNS:
		var screen = load("res://scenes/world/world.tscn").instantiate()
		screen.world_size = "large"
		root.add_child(screen)
		for i in 10:
			await process_frame
		var w = screen.world
		# The same roads, a different crowd on them each run.
		for q in w.parties.duplicate():
			for k in WorldBands.KINDS:
				if String(q.id).begins_with(String(k["id"]) + "-"):
					w.parties.erase(q)
					break
		WorldBands.seed(w, 1000 + run)
		var here = _nearest(w, w.player().position, [])
		w.player().position = here.position   # the trip starts at a gate, not on a hillside
		var seen: Array = [here.id]
		for leg in LEGS:
			var to = _nearest(w, here.position, seen)
			seen.append(to.id)
			var r: Dictionary = await _leg(screen, to)
			r["run"] = run
			r["from"] = here.sname
			legs.append(r)
			print("  run %d  %-12s -> %-12s %4.0f u %s  %d met, %d fought, %d road events, %4.1f h, hp %3.0f%%, %d slots, %d dead, %+d gold" % [
				run, here.sname, to.sname, r["dist"], "arrived" if r["arrived"] else "WEDGED ", r["meets"], r["fights"],
				r["events"], r["hours"], 100.0 * r["hp"], r["slots"], r["dead"], r["gold"]])
			if not r["arrived"]:
				break
			await _leave_town(screen)
			here = to
		screen.queue_free()
		await process_frame

	var n := legs.size()
	var arrived := legs.filter(func(r): return r["arrived"]).size()
	var meets := 0.0
	var fights := 0.0
	var hp := 0.0
	var whole := 0   # legs ended with everyone up and half the company's HP or more
	var nobody_dead := 0
	for r in legs:
		meets += r["meets"]; fights += r["fights"]; hp += r["hp"]
		if r["dead"] == 0:
			nobody_dead += 1
			if r["hp"] >= 0.5:
				whole += 1
	print("  %d legs: %d arrived, %.1f bands met and %.1f fought per leg, %.0f%% HP on arrival, %d/%d legs nobody died, %d/%d legs arrived whole (no dead, >=50%% HP)" % [
		n, arrived, meets / n, fights / n, 100.0 * hp / n, nobody_dead, n, whole, n])
	check(n == RUNS * LEGS, "every leg was walked (%d of %d)" % [n, RUNS * LEGS])
	check(arrived == n, "every leg reached its town (%d of %d)" % [arrived, n])
	check(meets / n <= 3.0, "a leg between neighbouring towns meets at most three bands on average (%.1f)" % (meets / n))
	check(meets / n >= 0.5, "...and is not empty either (%.1f)" % (meets / n))
	check(float(nobody_dead) / n >= 0.8, "four legs in five, nobody dies on the road (%d/%d)" % [nobody_dead, n])
	check(float(whole) / n >= 0.6, "three legs in five arrive whole — no dead, half the HP or more (%d/%d)" % [whole, n])
	print("test_road_trip: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
