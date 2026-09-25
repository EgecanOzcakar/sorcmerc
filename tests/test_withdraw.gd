# Withdrawing off the board's edge (the design audit, docs/audit-game-design.md
# §3.5; core/combat.gd's _leave_field). A hero on an edge hex spends the action
# to walk off; the heroes left behind fight on; when the last one standing
# walks off, the fight ends as a WITHDRAWAL — no XP, no loot, no quest
# progress, and not a defeat — and anyone left lying on the field is dead,
# unless a hero walked off from the hex beside them and carried them out (the
# owner's call, 2026-09-25): off the field, stable, and home at 1 HP.
# The co-op half: the verb crosses the wire by id, a refused one changes
# nothing, and `withdrew` is in the hash.
#   godot --headless --path . -s tests/test_withdraw.gd
extends SceneTree

const Adapter = preload("res://core/adapter.gd")
const Combat = preload("res://core/combat.gd")
const Coop = preload("res://core/coop.gd")
const Encounter = preload("res://core/encounter.gd")
const Hex = preload("res://core/hex.gd")
const Objectives = preload("res://core/objectives.gd")
const Presets = preload("res://core/presets.gd")

var _pass := 0
var _fail := 0

func check(cond: bool, label: String) -> void:
	if cond: _pass += 1
	else: _fail += 1; printerr("  FAIL: ", label)

func _init() -> void:
	test_only_where_allowed()
	test_edges()
	test_leave()
	test_everyone_leaves()
	test_left_behind_lose()
	test_carried_off()
	test_coop()
	test_coop_carry()
	print("test_withdraw: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# --- fixtures -------------------------------------------------------------------

func _spec(withdraw := true) -> Dictionary:
	var s := {"monsters": [{"id": "snik", "count": 2}], "theme": "goblin-camp"}
	if withdraw:
		s["withdraw"] = true
	return s

func _fight(spec: Dictionary, seed := 11) -> Combat:
	var sp: Dictionary = spec.duplicate(true)
	sp["seed"] = seed
	var board: Dictionary = Encounter.board_for(String(sp.get("theme", "")), seed)
	var starts: Array = Encounter.starts_for(sp, board, seed)
	var chars: Array = Presets.party()
	var party_c: Array = []
	for i in chars.size():
		party_c.append(Adapter.to_combatant(chars[i], "party", starts[i]))
	var cb := Encounter.build(sp, party_c, board)
	# Nobody moves and nobody dies unless a test says so: tokens are placed by hand.
	for c in cb.combatants:
		c.speed = 0
		c.max_hp = 100000
		c.hp = 100000
		c.new_turn()
	return cb

func _verb(cb: Combat, c) -> Dictionary:
	for v in cb.all_verbs(c):
		if String(v["id"]) == "leave_field":
			return v
	return {}

# An edge hex nobody stands on, and one well inside the board.
func _free_edge(cb: Combat, not_near := []) -> Vector2i:
	var taken: Array = cb.combatants.map(func(c): return c.pos)
	for e in cb.edge_hexes():
		if e in taken:
			continue
		var clear := true
		for c in not_near:
			if Hex.distance(c.pos, e) <= 2:
				clear = false
		if clear:
			return e
	return Combat.NOWHERE

func _interior(cb: Combat) -> Vector2i:
	for h in cb.board["hexes"]:
		if not cb.on_edge(h) and Hex.neighbors(h).all(func(n): return n in cb.board["hexes"]):
			return h
	return Combat.NOWHERE

# --- tests ------------------------------------------------------------------------

func test_only_where_allowed() -> void:
	var off := _fight(_spec(false))
	var hero = off.heroes()[0]
	check(_verb(off, hero).is_empty(), "a fight that does not allow it offers no Leave the field")
	var on := _fight(_spec())
	check(on.can_withdraw, "the spec's withdraw key reaches the fight")
	check(not _verb(on, on.heroes()[0]).is_empty(), "...and every hero has the button")
	check(_verb(on, on.team_of("foe")[0]).is_empty(), "a foe never does")
	var bo := _fight(_spec().merged({"objective": Objectives.make("breakout")}))
	check(not bo.can_withdraw, "a breakout's way off the board is its objective, not a withdrawal")

func test_edges() -> void:
	var cb := _fight(_spec())
	var edges: Array = cb.edge_hexes()
	check(not edges.is_empty(), "the board has an edge (%d hexes)" % edges.size())
	var ok := true
	for e in edges:
		ok = ok and e in cb.board["hexes"] and Hex.neighbors(e).any(func(n): return not n in cb.board["hexes"])
	check(ok, "every edge hex is on the board with a neighbour off it")
	var mid := _interior(cb)
	check(mid != Combat.NOWHERE and not cb.on_edge(mid), "a hex surrounded by board is not an edge")
	var again := _fight(_spec())
	check(again.edge_hexes() == edges, "the same board gives the same edge, in the same order (co-op)")

func test_leave() -> void:
	var cb := _fight(_spec())
	var foes: Array = cb.team_of("foe")
	var h = cb.heroes()[0]
	var v := _verb(cb, h)
	# not at the edge: no button, and a forced press changes nothing
	h.pos = _interior(cb)
	check(cb.leave_refusal(h) == "not at the edge of the field", "inside the board: refused (%s)" % cb.leave_refusal(h))
	check(not cb.available(h).any(func(x): return x["id"] == "leave_field"), "...and the button is not live")
	var act_before: int = int(h.econ["action"])
	var r: Dictionary = cb.perform(h, v)
	check(r.has("error") and int(h.econ["action"]) == act_before and not h.has("withdrawn"),
		"a refused leave spends nothing and moves nobody")
	# grappled at the edge: held fast
	h.pos = _free_edge(cb, foes)
	h.statuses["grappled"] = {"by": foes[0]}
	check(cb.leave_refusal(h) == "held fast", "grappled at the edge: refused")
	h.statuses.erase("grappled")
	# at the edge, nobody near: gone, alive, and out of everything
	check(cb.available(h).any(func(x): return x["id"] == "leave_field"), "at the edge the button is live")
	var hp: int = h.hp
	r = cb.perform(h, v)
	check(not r.has("error") and bool(r.get("left", false)), "the hero leaves the field")
	check(h.has("withdrawn") and h.pos == Combat.NOWHERE and not h.conscious() and not h.is_dead() and h.hp == hp,
		"...off the board, out of the fight, alive, at the HP they left with")
	check(int(h.econ["action"]) == act_before - 1, "...for their action")
	check(not h in cb.heroes() and cb.enemies_of(foes[0]).all(func(c): return c != h), "...and nothing can target them")
	check(cb.log[-1].contains("leaves the field"), "the log says so: %s" % cb.log[-1])
	check(not cb.is_over(), "the heroes left behind fight on")
	# end_turn skips the withdrawn
	var seen := false
	for i in cb.order.size() * 3:
		cb.end_turn()
		if cb.current() == h:
			seen = true
	check(not seen, "a withdrawn hero never gets another turn")
	# a foe beside the edge swings as they go
	var cb2 := _fight(_spec())
	var h2 = cb2.heroes()[0]
	var f2 = cb2.team_of("foe")[0]
	var e2 := _free_edge(cb2)
	h2.pos = e2
	for n in Hex.neighbors(e2):
		if n in cb2.board["hexes"] and not cb2.combatants.any(func(c): return c.pos == n):
			f2.pos = n
			break
	check(Hex.distance(f2.pos, h2.pos) <= f2.reach, "fixture: a goblin beside the leaving hero")
	var reacts: int = int(f2.econ["reaction"])
	cb2.perform(h2, _verb(cb2, h2))
	check(int(f2.econ["reaction"]) == reacts - 1, "walking off from beside a foe provokes it")
	check(h2.has("withdrawn"), "...and a hero who is not cut down still gets away")

func test_everyone_leaves() -> void:
	var cb := _fight(_spec())
	var foes: Array = cb.team_of("foe")
	var hs: Array = cb.heroes()
	# one of them is down on the field; the rest walk off
	var down = hs[-1]
	down.hp = 0
	down.statuses["down"] = true
	down.pos = _interior(cb)   # nobody walks off from beside them
	var kill = foes[0]
	cb._apply_damage(kill, 999999)
	check(kill.is_dead(), "fixture: one goblin is dead before the company goes")
	var walkers: Array = hs.slice(0, hs.size() - 1)
	for w in walkers:
		w.pos = _free_edge(cb, foes + [down])
		cb.perform(w, _verb(cb, w))
	check(cb.withdrew and cb.is_over() and cb.outcome() == Combat.WITHDRAWN,
		"the last one standing walks off: the fight ends as a withdrawal (%s)" % cb.outcome())
	check(down.is_dead(), "the one left lying on the field is dead: nobody is left to engage, so nobody is spared")
	check(cb.log[-1].contains(down.cname) and cb.log[-1].contains("left where they fell"), "...and the log names them: %s" % cb.log[-1])
	var chars: Array = Presets.party()
	var res: Dictionary = Encounter.resolve_outcome(cb, chars)
	check(res["outcome"] == Combat.WITHDRAWN, "the result says withdrawn, not victory or defeat")
	check(int(res["xp"]) == 0 and int(res["gold"]) == 0 and (res["loot"] as Array).is_empty(),
		"no XP, no coin, no loot — even for the goblin that died")
	check((res["kills"] as Array).is_empty(), "...and no kills, so no job counts it")
	check(down.id in res["deaths"] and not walkers[0].id in res["deaths"], "the left-behind are the fight's dead; the walkers are not")
	check(not bool(res["objective"]["done"]), "no objective is done by walking away")
	check(Combat.withdrawal_line([]).contains("Nothing is won"), "the line with nobody left behind: %s" % Combat.withdrawal_line([]))

func test_left_behind_lose() -> void:
	var cb := _fight(_spec())
	var hs: Array = cb.heroes()
	var goer = hs[0]
	goer.pos = _free_edge(cb, cb.team_of("foe"))
	cb.perform(goer, _verb(cb, goer))
	check(not cb.is_over(), "one walks off; the fight goes on")
	for h in hs.slice(1):
		cb._apply_damage(h, 999999)
	check(cb.is_over() and cb.outcome() == "Defeat" and not cb.withdrew,
		"the ones left behind all go down: it is a defeat, not a withdrawal (%s)" % cb.outcome())

func test_coop() -> void:
	var a := _fight(_spec(), 23)
	var b := _fight(_spec(), 23)
	check(Coop.state_hash(a) == Coop.state_hash(b), "fixture: two peers from one setup agree")
	var ha = a.heroes()[0]
	var hb = b.heroes()[0]
	# a refused leave: the harness drops it unsent, and nothing on either side moved
	var r: Dictionary = a.perform(ha, _verb(a, ha))
	var mid := _interior(a)
	if r.has("error"):
		check(Coop.state_hash(a) == Coop.state_hash(b), "a refused leave changes nothing (the hash still agrees)")
	var e := _free_edge(a, a.team_of("foe"))
	ha.pos = e
	hb.pos = e
	check(Coop.state_hash(a) == Coop.state_hash(b), "both peers put the hero on the same edge hex")
	var intent: Dictionary = Coop.perform(ha, _verb(a, ha), null)
	a.perform(ha, _verb(a, ha))
	Coop.apply(b, intent)
	check(hb.has("withdrawn") and Coop.state_hash(a) == Coop.state_hash(b),
		"the leave crosses the wire by id and both peers agree after it")
	b.withdrew = not b.withdrew
	check(Coop.state_hash(a) != Coop.state_hash(b), "withdrew is in the hash: drift in it would show")
	check(mid != Combat.NOWHERE, "fixture: an interior hex exists")

# An edge hex with a free board hex beside it, clear of `not_near` by more than
# two: somewhere a downed hero can lie next to a hero about to walk off.
func _edge_with_room(cb: Combat, not_near: Array) -> Array:
	var taken: Array = cb.combatants.map(func(c): return c.pos)
	for e in cb.edge_hexes():
		if e in taken or not_near.any(func(c): return Hex.distance(c.pos, e) <= 2):
			continue
		for n in Hex.neighbors(e):
			if n in cb.board["hexes"] and not n in taken and not not_near.any(func(c): return Hex.distance(c.pos, n) <= 2):
				return [e, n]
	return []

func _down(c) -> void:
	c.hp = 0
	c.statuses["down"] = true
	c.death_f = 2

func test_carried_off() -> void:
	var cb := _fight(_spec())
	var foes: Array = cb.team_of("foe")
	var hs: Array = cb.heroes()
	check(hs.size() >= 3, "fixture: three heroes or more (%d)" % hs.size())
	var carrier = hs[0]
	var fallen = hs[1]
	var lost = hs[2]
	var rest: Array = hs.slice(3)
	# the fallen lies beside the carrier's edge hex; the other downed lies far inside
	_down(lost)
	lost.pos = _interior(cb)
	var spot := _edge_with_room(cb, foes + [lost])
	check(spot.size() == 2, "fixture: an edge hex with room beside it")
	carrier.pos = spot[0]
	fallen.pos = spot[1]
	_down(fallen)
	var second = null
	for n in Hex.neighbors(carrier.pos):
		if n in cb.board["hexes"] and n != fallen.pos and not cb.combatants.any(func(c): return c.pos == n):
			second = n
			break
	# a second downed hero beside the same carrier: one pair of arms, one body
	var extra = null
	if not rest.is_empty() and second != null:
		extra = rest[0]
		rest = rest.slice(1)
		extra.pos = second
		_down(extra)
	cb.perform(carrier, _verb(cb, carrier))
	check(carrier.has("withdrawn"), "the carrier leaves the field")
	check(fallen.has("withdrawn") and fallen.pos == Combat.NOWHERE and not fallen.is_dead(),
		"the downed hero beside them goes too: off the board, alive")
	check(fallen.is_stable() and fallen.is_down() and fallen.hp == 0 and fallen.death_f == 0,
		"...stable, out cold at 0 HP, their failed saves wiped")
	check(cb.log.any(func(l): return String(l).contains("carrying %s" % fallen.cname)), "the log says who carried whom")
	if extra != null:
		check(not extra.has("withdrawn") and extra.pos != Combat.NOWHERE, "a second downed hero beside the same carrier stays: one body each")
	check(not cb.is_over() or rest.is_empty(), "the ones still standing fight on")
	# the carried hero never takes a turn again, so never rolls a save again
	var seen := false
	for i in cb.order.size() * 3:
		if cb.is_over():
			break
		cb.end_turn()
		if cb.current() == fallen:
			seen = true
	check(not seen, "a carried hero never gets another turn")
	# everyone else standing walks off from well away from the far one
	for w in rest:
		w.pos = _free_edge(cb, foes + [lost] + ([extra] if extra != null else []))
		cb.perform(w, _verb(cb, w))
	check(cb.withdrew and cb.outcome() == Combat.WITHDRAWN, "the last one off makes it a withdrawal")
	check(lost.is_dead(), "the downed hero nobody stood beside is dead, as before")
	if extra != null:
		check(extra.is_dead(), "...and so is the one the carrier's arms were too full for")
	check(not fallen.is_dead(), "the carried hero is not")
	var chars: Array = Presets.party()
	var res: Dictionary = Encounter.resolve_outcome(cb, chars)
	check(not fallen.id in res["deaths"] and lost.id in res["deaths"], "the result's dead: the left-behind, not the carried")
	var ch = null
	for x in chars:
		if x.id == fallen.id:
			ch = x
	Adapter.write_back(fallen, ch)
	check(ch != null and ch.hp_current == 1 and not ch.dead, "the carried hero comes to at 1 HP on the walk home (%d)" % (ch.hp_current if ch != null else -1))
	check(Combat.withdrawal_line([lost.cname]).contains(lost.cname), "the withdrawal line names only the left-behind")

func test_coop_carry() -> void:
	var a := _fight(_spec(), 29)
	var b := _fight(_spec(), 29)
	var sides := []
	for cb in [a, b]:
		var hs: Array = cb.heroes()
		var spot := _edge_with_room(cb, cb.team_of("foe"))
		hs[0].pos = spot[0]
		hs[1].pos = spot[1]
		_down(hs[1])
		sides.append(hs)
	check(Coop.state_hash(a) == Coop.state_hash(b), "fixture: both peers hold the same fallen beside the same carrier")
	var ha = sides[0][0]
	var intent: Dictionary = Coop.perform(ha, _verb(a, ha), null)
	a.perform(ha, _verb(a, ha))
	Coop.apply(b, intent)
	check(sides[1][1].has("withdrawn") and sides[1][1].is_stable(), "the carry happens on the guest's side from the same intent")
	check(Coop.state_hash(a) == Coop.state_hash(b), "...and both peers agree after it")
	sides[1][1].statuses.erase("stable")
	check(Coop.state_hash(a) != Coop.state_hash(b), "the carried hero's stable is in the hash: drift in it would show")
